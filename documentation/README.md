# VPS Bootstrap

`vps-bootstrap` is a local Bash CLI for taking a fresh VPS from an initial `root@host` password SSH login to a hardened Tailnet-first setup.

The tool:

- Creates a non-root sudo admin user, defaulting to `deploy`.
- Installs a local OpenSSH public key into the new user.
- Installs and joins Tailscale interactively.
- Verifies the new user can SSH over the Tailnet and run sudo before lock-down.
- Disables root/password SSH only after that verification succeeds.
- Restricts SSH to the Tailnet while leaving public TCP 80/443 open by default for hosted applications.
- Installs Codex CLI, Grok CLI, and GitHub CLI only when `--install-agent-clis` is passed.
- Keeps Codex and Grok current with a two-day systemd update timer when agent CLIs are installed.
- Installs OS updates every two weeks with an unattended systemd update timer.
- Pins the first SSH connection to a host public key pasted from the provider console.
- Supports Ubuntu/Debian through apt and Fedora/RHEL-family hosts through dnf/yum.

## Usage

```bash
bin/vps-bootstrap --host 203.0.113.10 --hostname app-01
```

Useful options:

```bash
bin/vps-bootstrap \
  --host 203.0.113.10 \
  --user deploy \
  --pubkey ~/.ssh/id_ed25519.pub \
  --identity ~/.ssh/id_ed25519 \
  --hostname app-01 \
  --enable-tailscale-ssh
```

Use `--dry-run` to inspect the phased plan without connecting:

```bash
bin/vps-bootstrap --host 203.0.113.10 --dry-run
```

Use `doctor` for a read-only readiness audit without opening SSH connections:

```bash
bin/vps-bootstrap doctor --host 203.0.113.10
```

Use `--no-web` or `--web=false` for private-only servers where public HTTP/HTTPS should remain closed.

## Developer CLIs

The bootstrap skips developer CLIs by default. Install them only on servers that should be agent-ready:

```bash
bin/vps-bootstrap --host 203.0.113.10 --install-agent-clis
```

With that option, the bootstrap installs:

- Codex CLI via OpenAI's official installer, `curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh`, run as the admin user.
- Grok CLI via xAI's official installer, `curl -fsSL https://x.ai/cli/install.sh | bash`, run as the admin user.
- GitHub CLI through GitHub's signed apt or rpm repositories.

Codex and Grok do not currently expose version-pinned installer URLs in this script. The bootstrap intentionally trusts their official mutable installer/update endpoints, logs that trust boundary during installation and updates, and avoids giving the installed user-level CLIs direct passwordless root access.

The bootstrap also installs `vps-agent-cli-update.service` and `vps-agent-cli-update.timer`. The timer runs every two days and:

- Reruns `curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh` as the admin user.
- Runs `grok update` as the admin user.
- Refreshes `/usr/local/bin/codex`, `/usr/local/bin/grok`, and `/usr/local/bin/agent` symlinks when those user-level binaries exist.

OS updates are handled by `vps-os-update.service` and `vps-os-update.timer`, which run every two weeks. On apt systems, `unattended-upgrades` is configured with a fourteen-day periodic cadence; the managed timer also runs `unattended-upgrade -d`. On dnf/yum systems, the timer runs package-manager upgrades non-interactively.

The default minimal server path is equivalent to:

```bash
bin/vps-bootstrap --host 203.0.113.10 --skip-agent-clis
```

Authentication is not performed during bootstrap. After setup with `--install-agent-clis`, SSH to the VPS over the Tailnet as the admin user and run:

```bash
vps-agent-auth --all
vps-agent-auth --status
```

The helper starts native interactive auth where available and prints setup checks for API-key based tools:

- `codex login`
- `grok login`, or `XAI_API_KEY` in non-browser environments
- `gh auth login --hostname github.com --git-protocol ssh`

The bootstrap script does not accept, upload, or store raw agent CLI tokens, API keys, or GitHub private keys. GitHub SSH setup stays inside the native `gh auth login --git-protocol ssh` flow on the server.

## Sudo Policy

The admin user receives passwordless sudo by default, but only for root-owned `vps-agent-*` helper commands installed under `/usr/local/sbin`. These helpers bound common agent operations without granting direct passwordless access to raw package managers, `systemctl`, `npm`, generic file-write tools, or user-level Codex/Grok binaries.

Default helpers:

- `vps-agent-sudo-check`
- `vps-agent-package update|upgrade|install <package> [...]`
- `vps-agent-service start|stop|restart|reload|status|enable|disable <service>`
- `vps-agent-logs <service> [lines]`
- `vps-agent-firewall web-on|web-off|status`
- `vps-agent-deploy <source-dir> <target-dir-under-/srv-or-/var/www>`
- `vps-agent-cli-update`
- `vps-os-update`

Each helper invocation writes a best-effort JSONL audit event to `/var/log/vps-agent-actions.log` with timestamp, helper name, invoking user, action, sanitized arguments, and exit code. Audit logging is non-fatal so helper behavior does not change if logging fails.

Use `--full-sudo` only when you intentionally want broad `NOPASSWD:ALL` behavior:

```bash
bin/vps-bootstrap --host 203.0.113.10 --full-sudo
```

During bootstrap, the prepare phase briefly grants broad passwordless sudo so the verified Tailnet harden phase can run. The harden phase rewrites that file to the final scoped policy unless `--full-sudo` is set.

## First SSH Host Key

Before the first `root@host` connection, the CLI prompts you to paste the VPS SSH host public key from your provider console. Paste the full OpenSSH host public key line, for example:

```text
ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA...
```

This is the server host key, not your local user key and not a SHA256 fingerprint. The script writes the pasted key to a temporary `known_hosts` file and uses strict host-key checking for the public root connection and later Tailnet SSH verification.

## Requirements

- Run from your laptop or workstation.
- The VPS must initially allow `root@host` SSH with password authentication.
- Your local OpenSSH public key and matching private key path must be available locally so the script can install the public key and verify Tailnet login. Do not paste private keys into this bootstrap.
- Your VPS provider must expose the server SSH host public key so you can paste it into the prompt before first connection.
- The VPS must have outbound internet access for package installation and Tailscale login.
- You must be able to approve the interactive Tailscale login URL during the prepare phase.
- Developer CLI auth happens after setup through `vps-agent-auth` only when `--install-agent-clis` was used.

## Safety Model

The script intentionally works in three phases:

1. Prepare as root while keeping temporary public SSH open.
2. Verify the new admin user can SSH over the Tailnet and run `sudo -n /usr/local/sbin/vps-agent-sudo-check`.
3. Harden SSH and remove public SSH only after verification passes.
4. Optionally run `vps-agent-auth --all` later from the VPS when `--install-agent-clis` was used and you are ready to authenticate developer CLIs.

If phase 1 or 2 fails, root/password SSH is left active so the server can be repaired.
