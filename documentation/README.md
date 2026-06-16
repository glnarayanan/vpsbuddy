# VPS Bootstrap

`vps-bootstrap` is a local Bash CLI for taking a fresh VPS from an initial `root@host` password SSH login to a hardened Tailnet-first setup.

The tool:

- Creates a non-root sudo admin user, defaulting to `deploy`.
- Installs a local OpenSSH public key into the new user.
- Installs and joins Tailscale interactively.
- Verifies the new user can SSH over the Tailnet and run sudo before lock-down.
- Disables root/password SSH only after that verification succeeds.
- Restricts SSH to the Tailnet while leaving public TCP 80/443 open by default for hosted applications.
- Installs Codex CLI, Grok CLI, and GitHub CLI by default.
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

Use `--no-web` or `--web=false` for private-only servers where public HTTP/HTTPS should remain closed.

## Developer CLIs

The bootstrap installs these developer tools by default:

- Codex CLI via `npm i -g @openai/codex`.
- Grok CLI via xAI's official installer, `curl -fsSL https://x.ai/cli/install.sh | bash`, run as the admin user.
- GitHub CLI through GitHub's signed apt or rpm repositories.

Skip them when building a minimal server:

```bash
bin/vps-bootstrap --host 203.0.113.10 --skip-agent-clis
```

Authentication is not performed during bootstrap. After setup, SSH to the VPS over the Tailnet as the admin user and run:

```bash
vps-agent-auth --all
vps-agent-auth --status
```

The helper starts native interactive auth where available and prints setup checks for API-key based tools:

- `codex login`
- `grok login`, or `XAI_API_KEY` in non-browser environments
- `gh auth login --hostname github.com --git-protocol ssh`

The bootstrap script does not accept, upload, or store raw agent CLI tokens or API keys.

## Sudo Policy

The admin user receives scoped passwordless sudo by default for package, service, log, firewall, deployment, and agent-tool operations. Use `--full-sudo` only when you intentionally want broad `NOPASSWD:ALL` behavior:

```bash
bin/vps-bootstrap --host 203.0.113.10 --full-sudo
```

During bootstrap, the prepare phase briefly grants broad passwordless sudo so the verified Tailnet harden phase can run. The harden phase rewrites that file to the final scoped policy unless `--full-sudo` is set.

## Requirements

- Run from your laptop or workstation.
- The VPS must initially allow `root@host` SSH with password authentication.
- Your OpenSSH public and private key files must be available locally.
- The VPS must have outbound internet access for package installation and Tailscale login.
- You must be able to approve the interactive Tailscale login URL during the prepare phase.
- Developer CLI auth happens after setup through `vps-agent-auth`.

## Safety Model

The script intentionally works in three phases:

1. Prepare as root while keeping temporary public SSH open.
2. Verify the new admin user can SSH over the Tailnet and run `sudo -n true`.
3. Harden SSH and remove public SSH only after verification passes.
4. Run `vps-agent-auth --all` later from the VPS when ready to authenticate developer CLIs.

If phase 1 or 2 fails, root/password SSH is left active so the server can be repaired.
