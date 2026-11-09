# Operator Guide

Run `vpsbuddy` after logging into a fresh VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/glnarayanan/vpsbuddy/main/install.sh | bash
```

From a checkout on the VPS:

```bash
sudo bin/vpsbuddy
```

For a provider admin such as `ubuntu`, run the download with root privileges:

```bash
curl -fsSL https://raw.githubusercontent.com/glnarayanan/vpsbuddy/main/install.sh |
  sudo bash
```

Use `--dry-run` to answer the same prompts and print the chosen configuration
without changing the host.

## Existing Admin Accounts and SSH Keys

Setup offers the non-root sudo caller first, followed by local interactive
accounts with admin-group membership or sudo access. Accept an account, decline
it to see the next one, or enter an existing or new name after declining the
detected accounts. A new user is created only when the selected name is absent.

For an existing user, setup reports a passwordless sudo probe and lists its sudo
grants. It checks the selected user's `~/.ssh/authorized_keys` first, then the
invoking account's key file. It shows a detected key's fingerprint and asks
before using it. Otherwise paste one OpenSSH public key. Discovery accepts only
plain unrestricted key lines; it does not strip options from restricted keys.
Existing keys remain in place. The script never asks for a private key.

Prepare checks the selected home and SSH paths, sets `.ssh` to `0700` and
`authorized_keys` to `0600`, and uses the account's actual primary group. It
refuses symlinked homes or SSH paths and non-regular key files.

## Swap

If active swap exists, it is left unchanged. Otherwise enter a size such as
`4G`, or `none`.

For a requested `/swapfile`, prepare refuses a symlink, creates or safely reuses
the file, sets mode `0600`, runs `mkswap`/`swapon`, and adds one `/swapfile`
entry to `/etc/fstab`.

## Prepare and Harden

Prepare checks or updates the chosen user, key, packages, swap, services,
Tailscale, helpers, CLIs, and firewall rules while keeping public SSH open. It
disables Tailscale SSH before the OpenSSH login test.

After prepare, the script runs the scoped sudo check as the selected admin user,
prints the Tailnet SSH command, and waits. Test that login from another
terminal, return to the first session, and type `yes`.

Harden then writes and validates OpenSSH hardening, writes the chosen sudo
policy, limits SSH to `tailscale0`, and applies public web rules. OpenSSH remains
the Tailnet port 22 service.

If you do not confirm, setup pauses with public SSH open. Rerun with
`--resume`; vpsbuddy loads the saved choices, restores public SSH, disables
Tailscale SSH, checks the admin and Tailnet state again, and waits
for a new explicit confirmation before hardening.

Prepare, resumed access preparation, and harden report effective root SSH
settings, root password status, and the selected user's sudo grants. The SSH
report uses a loopback connection context. Harden still validates the effective
key-only admin policy and `PermitRootLogin no` before closing public SSH. Root
console/password state is reported and preserved for provider recovery.

## Developer CLIs

The CLI prompt covers Codex, Grok, GitHub CLI, Pi, OpenCode, Amp, Factory
Droid, and Claude Code. Enter numbers separated by spaces or commas. Blank input
is rejected; `all` selects every CLI and `none` skips them. The prompt removes
duplicates and shows the final selection before confirmation.

User-scoped upstream CLI installers run as the chosen admin user. GitHub CLI and
required OS packages are installed as root through the supported apt, dnf, or yum
package manager. Bootstrap accepts GitHub CLI only when its signed official
repository is configured.

A selected CLI installer or CLI helper failure does not stop VPS setup. vpsbuddy
records failed installers, continues to Tailnet login verification, and hardens
SSH only after the operator confirms that login. The final summary prints an
official repair command for each failed tool. User-scoped installers have a
15-minute deadline, so a stalled optional installer cannot block the Tailnet
gate forever. Deselecting a CLI stops vpsbuddy management but does not uninstall
a third-party tool. The CLI update timer is omitted for `none` and GitHub CLI
alone.

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

Existing provider sudoers files and group grants remain in effect. Selecting
scoped helpers controls only vpsbuddy's grant; it does not revoke pre-existing
full sudo. Setup displays those grants so you can assess the effective access.
The prepare gate verifies passwordless helper access for both policies, and
also tests passwordless `/usr/bin/true` when full sudo was selected.
These checks ignore cached sudo authentication.

Helper calls write best-effort JSONL audit events to
`/var/log/vpsbuddy-actions.log`.

## Optional Developer Tools After Bootstrap

Log in as the chosen admin. From a checkout, run:

```bash
bin/vpsbuddy --dev-tools
```

Or download the current installer without a checkout:

```bash
curl -fsSL https://raw.githubusercontent.com/glnarayanan/vpsbuddy/main/install.sh |
  bash -s -- --dev-tools
```

Run this without sudo. It rejects root, and requires access to the installed
vpsbuddy sudo helper before installing. It never loads the private bootstrap
plan or runs SSH, firewall, Tailscale, user, or sudo-policy setup. Host recovery
remains a separate command: `sudo bin/vpsbuddy --resume` from a checkout, or
pipe the downloaded installer to `sudo bash -s -- --resume`.

Choose numbers or names for mise, Ruby, Rails, and Node.js/npm; `all` and `none`
are supported. Rails includes Ruby, and runtimes include mise. Choose a numeric
Ruby version or `latest`, a numeric Rails version or `latest`, and a numeric
Node.js version or `lts`. Mise accepts version prefixes for Ruby and Node;
Rails versions are passed directly to RubyGems. No versions are silently chosen.
`latest` and `lts` resolve at install time and may change on a later rerun.
The summary requires confirmation. Add `--dry-run` to preview without installing.

Mise is installed through its official installer at `~/.local/bin/mise` if absent.
An existing binary there is reused. Ruby, Rails gems, Node, and npm are installed
as the current user. Ruby build prerequisites use `sudo -n vpsbuddy-package` on
supported apt/rpm distributions; no full sudo grant is required. RPM package
availability depends on the image's enabled repositories. No OS Node/Ruby package
or root-owned gem install is used.

The command verifies tool versions and adds mise activation to `.bashrc`, plus
the current Zsh configuration when applicable, without duplicating its line.
Open a new shell afterward. On failure, rerun `--dev-tools` and select the tools
to retry; existing mise installations are reused. Tool selection is collected
again, while installed runtime state is managed by mise. Deselecting a tool does
not uninstall it. Developer-tool failures do not change host hardening.

## Reruns and Resume

Reruns are meant to be idempotent. Existing users, keys, active swap, Tailscale
state, helper files, timers, firewall rules, and SSH config are checked or set
to the chosen state.

vpsbuddy saves the confirmed plan before the first change. It writes the plan,
phase, and failed CLI list to private root-owned files under
`/var/lib/vpsbuddy`. Use this checkout-free command after a pause, failed core
step, or lost terminal:

```bash
curl -fsSL https://raw.githubusercontent.com/glnarayanan/vpsbuddy/main/install.sh |
  bash -s -- --resume
```

`--continue` is an alias. A saved `prepared` or `hardening` phase skips full
package and user setup, temporarily restores public SSH, disables Tailscale
SSH, rechecks the admin sudo helper and Tailscale, and waits for Tailnet login
approval before hardening. A saved `complete` phase reports the final
state without changing the server. If no trusted current plan exists, including
when a saved plan has an older format, resume starts the guided setup and saves
the new choices before changing the VPS.

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
