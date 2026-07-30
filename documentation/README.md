# Advanced Usage

This file is the operator reference for `vps-bootstrap`. The public overview and
quick start live in [../README.md](../README.md).

## Common Commands

Inspect a bootstrap plan without opening SSH:

```bash
bin/vps-bootstrap --host 203.0.113.10 --login-user your-provider-user --hostname app-01 --dry-run
```

Run a read-only readiness audit:

```bash
bin/vps-bootstrap doctor --host 203.0.113.10
```

Bootstrap a fresh VPS with the default minimal posture:

```bash
bin/vps-bootstrap --host 203.0.113.10 --login-user your-provider-user --hostname app-01
```

Reuse the provider's initial SSH user as the managed admin user:

```bash
bin/vps-bootstrap --host 203.0.113.10 --login-user your-provider-user --user your-provider-user --hostname app-01
```

Bootstrap an agent-ready host with optional developer CLIs:

```bash
bin/vps-bootstrap --host 203.0.113.10 --login-user your-provider-user --hostname app-01 --install-agent-clis
```

## Useful Options

- `--login-user <name>`: provider's initial SSH user. Required for bootstrap and
  dry-run.
- `--login-identity <path>`: private key for the initial public SSH login. Use
  this when the provider key is not already available through your SSH agent or
  SSH config.
- `--user <name>`: admin sudo user to create or reuse after login. Defaults to
  `deploy`.
- `--pubkey <path>`: public key to install. Defaults to
  `~/.ssh/id_ed25519.pub`.
- `--identity <path>`: private key used for Tailnet verification. Defaults to
  the public key path without `.pub`.
- `--hostname <name>`: hostname to set on the VPS and use for Tailscale.
- `--enable-tailscale-ssh`: request Tailscale SSH after OpenSSH over the
  Tailnet has been verified. The CLI asks for confirmation before enabling it
  because Tailnet ACL SSH rules are still required.
- `--install-agent-clis`: best-effort install of Codex CLI, Grok CLI, GitHub
  CLI, `vps-agent-auth`, and the agent CLI update timer.
- `--swap-size <size>`: create this swap size when no active swap exists.
  Accepts a positive whole number followed by `M` or `G`. Defaults to `2G`.
- `--no-swap`: skip swap setup.
- `--no-web` or `--web=false`: close public TCP 80/443 for private-only hosts.
- `--full-sudo`: use broad `NOPASSWD:ALL` instead of the default bounded helper
  policy.

## Operator Notes

- If the provider shows the VPS SSH host public key, paste it when prompted. If
  it does not, press Enter to scan the live SSH host key, review the fingerprint,
  and type `yes` to pin it for bootstrap. This is the server host key, not your
  local user key and not only a SHA256 fingerprint.
- `--pubkey` is your local login public key to install for the admin user. It is
  expected to be absent on a fresh VPS before the prepare phase.
- The prepare phase temporarily keeps the original public SSH path available.
  The harden phase runs only after Tailnet admin SSH and bounded sudo
  verification pass and you type `yes` after manually checking SSH from another
  terminal.
- The top-level CLI can run from a workstation or an interactive server shell.
  Run `bin/vps-bootstrap`; do not run only the generated remote prepare payload.
  The private key must be available in the environment where the CLI runs.
- For a provider that installs a key and disables password SSH at provisioning,
  pass `--login-identity ~/.ssh/provider_key`. This key is used for the initial
  SSH and SCP steps only; `--identity` remains the managed admin key.
- For non-root `--login-user` values, the CLI uploads a temporary prepare script
  and then runs it with interactive `sudo`. The login user still needs usable
  sudo access.
- If you decline hardening, rerun the same command later. The prepare phase is
  safe to repeat and will re-check existing user, key, Tailscale, and sudo state
  before asking again.
- Prepare creates `/swapfile` with mode `0600` when no active swap exists,
  enables it, and adds it to `/etc/fstab`. A valid existing swap file is reused;
  an unusable `/swapfile` is never overwritten.
- Default passwordless sudo is limited to root-owned `vps-agent-*` helpers under
  `/usr/local/sbin`.
- Helper calls append best-effort JSONL audit events to
  `/var/log/vps-agent-actions.log`.
- Developer CLI authentication is never collected during bootstrap. When
  `--install-agent-clis` is used, authenticate later with `vps-agent-auth`.
- Codex and Grok use their official standalone Linux installers. GitHub CLI
  uses GitHub's signed apt/rpm package repositories on Linux rather than adding
  Homebrew to the server.

See [security-model.md](security-model.md), [threat-model.md](threat-model.md),
and [release-process.md](release-process.md) before changing bootstrap or
hardening behavior.
