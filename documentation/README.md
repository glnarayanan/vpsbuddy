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

The CLI prompt covers Codex, Grok, GitHub CLI, Pi, OpenCode, Amp, Factory
Droid, and Claude Code. Enter numbers separated by spaces or commas. Blank input
is rejected; `all` selects every CLI and `none` skips them. The prompt removes
duplicates and shows the final selection before confirmation.

If a selected installer fails, prepare stops while public SSH stays open. Each
rerun clears the managed CLI update timer and auth helper, then adds them again
for the new selection only. Deselecting a CLI stops vpsbuddy management but does
not uninstall a third-party tool. The CLI update timer is omitted for `none` and
GitHub CLI alone.

After setup, log in as the admin user and run:

```bash
vpsbuddy-auth --all
vpsbuddy-auth --status
```

`--all` and `--status` cover only the selected CLIs. Pi and Factory Droid use
interactive login prompts; the other supported flows use their native auth
commands.

## Sudo

Scoped sudo grants passwordless access only to root-owned `vpsbuddy-*` helpers
under `/usr/local/sbin`. Those helpers wrap package, service, log, firewall, and
update operations. Full sudo writes `NOPASSWD:ALL`.

Helper calls write best-effort JSONL audit events to
`/var/log/vpsbuddy-actions.log`.

## Reruns

Reruns are meant to be idempotent. Existing users, keys, active swap, Tailscale
state, helper files, timers, firewall rules, and SSH config are checked or set
to the chosen state.

The first rerun after the rename retires files owned by `vps-bootstrap`: helper
commands, sudoers policy, timers, update files, and SSH drop-ins. SSH changes
roll back if validation fails. The old audit log stays as history. The generic
`/usr/local/bin/agent` link is removed only when it points to the Grok binary
managed by the old script.

Selected CLI links in `/usr/local/bin` are recorded in
`/var/lib/vpsbuddy/cli-links`. Reruns remove recorded links. If the old
`vps-bootstrap` ownership record remains, they also remove links left by that
admin. They refuse to replace an unmanaged file. The CLI update timer tries each
selected CLI and exits with a failure status if an update or link refresh fails.

Review release notes and use `--dry-run` first on any server that has changed
since its first bootstrap.
