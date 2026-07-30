# Operator Guide

Run `vpsbuddy` after logging into a fresh VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/glnarayanan/vpsbuddy/main/install.sh | bash
```

From a checkout on the VPS:

```bash
sudo bin/vpsbuddy
```

Use `--dry-run` to answer the same prompts and print the chosen configuration
without changing the host.

## SSH Key Input

When the current login account has a valid key in `~/.ssh/authorized_keys`, the
script shows its fingerprint and asks whether to install that key for the new
admin user. Otherwise paste one OpenSSH public key. The script never asks for a
private key.

## Swap

If active swap exists, it is left unchanged. Otherwise enter a size such as
`4G`, or `none`.

For a requested `/swapfile`, prepare refuses a symlink, creates or safely reuses
the file, sets mode `0600`, runs `mkswap`/`swapon`, and adds one `/swapfile`
entry to `/etc/fstab`.

## Prepare and Harden

Prepare checks or updates the chosen user, key, packages, swap, services,
Tailscale, helpers, CLIs, and firewall rules while keeping public SSH open.

After prepare, the script runs the scoped sudo check as the new admin user,
prints the Tailnet SSH command, and waits. Test that login from another
terminal, return to the first session, and type `yes`.

Harden then writes and validates OpenSSH hardening, writes the chosen sudo
policy, limits SSH to `tailscale0`, applies public web rules, and optionally
enables Tailscale SSH.

If you do not confirm, setup pauses with public SSH open. Rerun later; prompts
appear again so the next run uses an explicit configuration.

## Developer CLIs

The CLI choice covers Codex, Grok, and GitHub CLI. If a selected installer
fails, prepare stops while public SSH stays open and no CLI update timer is
installed.

After setup, log in as the admin user and run:

```bash
vpsbuddy-auth --all
vpsbuddy-auth --status
```

## Sudo

Scoped sudo grants passwordless access only to root-owned `vpsbuddy-*` helpers
under `/usr/local/sbin`. Those helpers wrap package, service, log, firewall, and
update operations. Full sudo writes `NOPASSWD:ALL`.

Helper calls write best-effort JSONL audit events to
`/var/log/vpsbuddy-actions.log`.

## Reruns

Reruns are meant to be idempotent. Existing users, keys, active swap, Tailscale
state, helper files, timers, firewall rules, and SSH config are checked or
rewritten to the chosen state. Review release notes and use `--dry-run` first on
any server that has changed since its first bootstrap.
