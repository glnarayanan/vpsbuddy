# Operator Guide

Run `vps-bootstrap` after logging into a fresh VPS. The public bootstrap command
downloads one source archive to a temporary directory and removes it when the
run ends:

```bash
curl -fsSL https://raw.githubusercontent.com/glnarayanan/server-setup-scripts/main/install.sh | bash
```

From a checkout already present on the VPS, run:

```bash
sudo bin/vps-bootstrap
```

Use `--dry-run` to answer the same prompts and print the chosen configuration
without changing the host.

## SSH Key Input

When the current login account has a valid key in `~/.ssh/authorized_keys`, the
script shows its fingerprint and asks whether to install that key for the new
admin user. This covers provider images that add a key for root and disable
password login.

If no valid key is found, or you reject it, paste one OpenSSH public key. The
script never asks for a private key.

## Swap

If active swap exists, the script leaves it unchanged. Otherwise it asks for a
size such as `4G`, or `none`.

For a requested swap file, prepare:

- refuses a symlink at `/swapfile`
- creates or safely reuses `/swapfile`
- sets mode `0600`
- runs `mkswap` and `swapon`
- adds one `/swapfile` entry to `/etc/fstab`

## Prepare and Harden

Prepare is safe to rerun. It checks or updates the chosen user, key, packages,
swap, services, Tailscale, helpers, CLIs, and firewall rules. It keeps public
SSH open.

After prepare, the script runs the scoped sudo check as the new admin user. It
then prints the Tailnet SSH command and waits. Open another terminal, test that
command, return to the first session, and type `yes`.

Harden then:

- writes and validates the OpenSSH hardening file
- writes the chosen sudo policy
- limits SSH to `tailscale0`
- applies the chosen public web rules
- optionally enables Tailscale SSH

If you do not type `yes`, the script says setup is paused and leaves public SSH
open. Rerun the installer later. The prompts appear again so the next run uses
an explicit configuration.

## Developer CLIs

The CLI choice covers Codex, Grok, and GitHub CLI. If a selected installer
fails, prepare stops while public SSH stays open.

After setup, log in as the admin user and run:

```bash
vps-agent-auth --all
vps-agent-auth --status
```

The bootstrap does not accept or copy API keys, tokens, or SSH private keys.

## Sudo

The scoped choice grants passwordless access only to root-owned
`vps-agent-*` helpers under `/usr/local/sbin`. The full choice writes
`NOPASSWD:ALL`.

Helper calls write best-effort JSONL audit events to
`/var/log/vps-agent-actions.log`.

## Reruns and Upgrades

Reruns are meant to be idempotent. Existing users, keys, active swap, Tailscale
state, helper files, timers, firewall rules, and SSH config are checked or
rewritten to the chosen state.

Rerunning a newer installer applies the current script. Review release notes and
use `--dry-run` first on any server that has changed since its first bootstrap.
The tool is for fresh-server baselines, not general configuration management.

See [security-model.md](security-model.md) and
[release-process.md](release-process.md) before changing the phase order.
