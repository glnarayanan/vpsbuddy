# FAQ

## Is this a Dokploy or Coolify alternative?

No. `vps-bootstrap` does not deploy apps or run a hosting control plane. It
secures the fresh VPS baseline underneath whatever app deployment approach you
choose later.

## Can I run it on an existing production server?

That is not the intended alpha path. The script is designed for fresh VPS hosts
where the provider's initial SSH user is reachable by key or password, and there
is no existing application state to preserve.

For an existing server, inspect dry-run output and the generated behavior first.
You are responsible for understanding how it interacts with existing users,
SSH, firewall, sudo, and service configuration.

## What if the provider disables password SSH at provisioning?

Pass the provider key with `--login-identity`:

```bash
bin/vps-bootstrap \
  --host 203.0.113.10 \
  --login-user root \
  --login-identity ~/.ssh/provider_key \
  --pubkey ~/.ssh/id_ed25519.pub \
  --identity ~/.ssh/id_ed25519
```

That key is used for the initial public SSH and SCP steps. `--identity` remains
the private key used for the managed admin user over the Tailnet. If the provider
key is already in your SSH agent or SSH config, `--login-identity` is optional.

## What if my provider does not show the server SSH host public key?

The first connection is the riskiest one. If the provider shows the OpenSSH host
public key, paste it. If it does not, press Enter at the prompt; the CLI scans
the live SSH host key, shows the key and fingerprint, and asks you to type `yes`
before pinning it for bootstrap.

The scanned-key path is trust-on-first-use. It is still pinned before the first
SSH login and reused for the rest of the run, but it cannot prove provider
identity by itself. Do not paste your local user public key, a private key, or
only a SHA256 fingerprint.

## Should my local SSH key already be on the VPS?

No. `--pubkey` points to your local public key, and the prepare phase installs it
for the admin user. If that exact key is already present, the script logs that
and continues.

## Why keep public SSH open during the prepare phase?

To avoid lockout. The original public SSH path remains available until
the script verifies that the new admin user can SSH over the Tailnet and run the
bounded sudo check, and until you confirm that you manually verified SSH from
another terminal. Only then does the harden phase remove public SSH.

## What if I am not ready to disable public SSH?

Answer anything other than `yes` at the hardening prompt. The script leaves the
original public SSH path available and exits cleanly. Rerun the same command
after you have verified SSH; completed prepare work is checked again and reused.

## Does it store my API keys or CLI tokens?

No. Bootstrap does not accept, upload, or store raw Codex, Grok, GitHub, or API
tokens. When optional agent CLIs are installed, developer CLI auth happens after
setup through `vps-agent-auth`, using native CLI auth flows where available.

## Why install agent CLIs at all?

Some operator workflows use Codex CLI, Grok CLI, and GitHub CLI directly on the
server. The alpha default skips those installs; opt in only for servers that
need them:

```bash
bin/vps-bootstrap --host 203.0.113.10 --login-user your-provider-user --install-agent-clis
```

## Does bootstrap set up swap?

Yes. During prepare, it keeps active swap as-is. If no active swap exists, it
creates and enables a root-owned `0600` `/swapfile` and adds it to `/etc/fstab`.
The default size is `2G`; use `--swap-size 4G` to change it or `--no-swap` to
skip swap setup. An unusable existing `/swapfile` is not overwritten.

## What does the default sudo policy allow?

The admin user gets passwordless sudo only for root-owned `vps-agent-*` helper
commands by default. Raw package managers, `systemctl`, generic file-write
tools, and user-level agent binaries are not directly passwordless sudo targets.

Use `--full-sudo` only when you intentionally want broad `NOPASSWD:ALL`.

Each helper writes a best-effort JSONL audit event to
`/var/log/vps-agent-actions.log` with timestamp, helper name, invoking user,
action, sanitized arguments, and exit code.

## What does `doctor` check?

`bin/vps-bootstrap doctor` is read-only. From a workstation it checks local key
inputs, command availability, host-key expectations, planned sudo/web/agent CLI
settings, and provider firewall reminders. On a bootstrapped VPS it also reports
detected helpers, sudo policy shape, timers, SSH hardening, firewall status,
Tailnet status, and listening ports.

## Why are public TCP 80 and 443 open by default?

The default assumes the VPS may host web applications after bootstrap. Use
`--no-web` or `--web=false` for private-only servers.

Provider firewalls must be configured separately. See
[provider-firewall-checklist.md](provider-firewall-checklist.md).

## Does Tailscale SSH replace OpenSSH here?

OpenSSH over the Tailnet is the default access model. `--enable-tailscale-ssh`
is deferred until after OpenSSH verification and the manual hardening
checkpoint, then the CLI asks for confirmation before running `tailscale set
--ssh`. Configure Tailnet ACL SSH rules first; otherwise Tailscale SSH can block
normal OpenSSH over the Tailnet.

## What should I test before trusting a release?

Run:

```bash
make check
bin/vps-bootstrap --host 203.0.113.10 --hostname smoke-01 --dry-run
```

For release confidence, use a disposable fresh VPS and follow
[release-process.md](release-process.md).

## What happens if Tailscale login fails?

The harden phase should not run because Tailnet verification cannot succeed.
Public SSH remains available so you can repair or destroy the disposable host.

## Which operating systems are supported?

The alpha target is fresh systemd-based Ubuntu/Debian apt hosts and
Fedora/RHEL-family dnf/yum hosts. See
[compatibility-matrix.md](compatibility-matrix.md).
