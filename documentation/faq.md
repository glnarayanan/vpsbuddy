# FAQ

## Is this a Dokploy or Coolify alternative?

No. `vps-bootstrap` does not deploy apps or run a hosting control plane. It
secures the fresh VPS baseline underneath whatever app deployment approach you
choose later.

## Can I run it on an existing production server?

That is not the intended alpha path. The script is designed for fresh VPS hosts
where temporary root/password SSH is still available and there is no existing
application state to preserve.

For an existing server, inspect dry-run output and the generated behavior first.
You are responsible for understanding how it interacts with existing users,
SSH, firewall, sudo, and service configuration.

## Why require the server SSH host public key from the provider console?

The first connection is the riskiest one. Pasting the server host public key lets
the CLI use strict host-key checking instead of trusting whatever key appears on
first contact.

Use the OpenSSH host public key line, such as `ssh-ed25519 AAAA...`. Do not
paste your local user public key, a private key, or only a SHA256 fingerprint.

## Why keep public SSH open during the prepare phase?

To avoid lockout. Public root/password SSH remains available until the script
verifies that the new admin user can SSH over the Tailnet and run the bounded
sudo check. Only then does the harden phase remove public SSH.

## Does it store my API keys or CLI tokens?

No. Bootstrap does not accept, upload, or store raw Codex, Grok, GitHub, or API
tokens. Developer CLI auth happens after setup through `vps-agent-auth`, using
native CLI auth flows where available.

## Why install agent CLIs at all?

The default flow prepares a server for operator workflows that use Codex CLI,
Grok CLI, and GitHub CLI. You can skip those installs:

```bash
bin/vps-bootstrap --host 203.0.113.10 --skip-agent-clis
```

## What does the default sudo policy allow?

The admin user gets passwordless sudo only for root-owned `vps-agent-*` helper
commands by default. Raw package managers, `systemctl`, generic file-write
tools, and user-level agent binaries are not directly passwordless sudo targets.

Use `--full-sudo` only when you intentionally want broad `NOPASSWD:ALL`.

## Why are public TCP 80 and 443 open by default?

The default assumes the VPS may host web applications after bootstrap. Use
`--no-web` or `--web=false` for private-only servers.

Provider firewalls must be configured separately. See
[provider-firewall-checklist.md](provider-firewall-checklist.md).

## Does Tailscale SSH replace OpenSSH here?

OpenSSH over the Tailnet is the default access model. `--enable-tailscale-ssh`
also enables Tailscale SSH on the host, but Tailnet ACL SSH rules still need to
be configured in the Tailscale admin console.

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
Root/password SSH remains available so you can repair or destroy the disposable
host.

## Which operating systems are supported?

The alpha target is fresh systemd-based Ubuntu/Debian apt hosts and
Fedora/RHEL-family dnf/yum hosts. See
[compatibility-matrix.md](compatibility-matrix.md).
