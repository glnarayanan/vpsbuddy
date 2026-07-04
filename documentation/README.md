# Advanced Usage

This file is the operator reference for `vps-bootstrap`. The public overview and
quick start live in [../README.md](../README.md).

## Common Commands

Inspect a bootstrap plan without opening SSH:

```bash
bin/vps-bootstrap --host 203.0.113.10 --hostname app-01 --dry-run
```

Run a read-only readiness audit:

```bash
bin/vps-bootstrap doctor --host 203.0.113.10
```

Bootstrap a fresh VPS with the default minimal posture:

```bash
bin/vps-bootstrap --host 203.0.113.10 --hostname app-01
```

Bootstrap an agent-ready host with optional developer CLIs:

```bash
bin/vps-bootstrap --host 203.0.113.10 --hostname app-01 --install-agent-clis
```

## Useful Options

- `--user <name>`: admin sudo user to create. Defaults to `deploy`.
- `--pubkey <path>`: public key to install. Defaults to
  `~/.ssh/id_ed25519.pub`.
- `--identity <path>`: private key used for Tailnet verification. Defaults to
  the public key path without `.pub`.
- `--hostname <name>`: hostname to set on the VPS and use for Tailscale.
- `--enable-tailscale-ssh`: enable Tailscale SSH in addition to OpenSSH over
  the Tailnet. Tailnet ACL SSH rules are still required.
- `--install-agent-clis`: install Codex CLI, Grok CLI, GitHub CLI,
  `vps-agent-auth`, and the agent CLI update timer.
- `--no-web` or `--web=false`: close public TCP 80/443 for private-only hosts.
- `--full-sudo`: use broad `NOPASSWD:ALL` instead of the default bounded helper
  policy.

## Operator Notes

- Paste the VPS SSH host public key from the provider console when prompted.
  This is the server host key, not your local user key and not only a SHA256
  fingerprint.
- The prepare phase temporarily keeps public root/password SSH available. The
  harden phase runs only after Tailnet admin SSH and bounded sudo verification
  pass.
- Default passwordless sudo is limited to root-owned `vps-agent-*` helpers under
  `/usr/local/sbin`.
- Helper calls append best-effort JSONL audit events to
  `/var/log/vps-agent-actions.log`.
- Developer CLI authentication is never collected during bootstrap. When
  `--install-agent-clis` is used, authenticate later with `vps-agent-auth`.

See [security-model.md](security-model.md), [threat-model.md](threat-model.md),
and [release-process.md](release-process.md) before changing bootstrap or
hardening behavior.
