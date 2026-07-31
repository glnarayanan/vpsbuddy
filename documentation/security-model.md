# Security Model

`vpsbuddy` aims to avoid lockout while ending with a narrow SSH surface.

## Trust Before Bootstrap

The operator logs into the VPS before running this script. The provider account,
initial SSH host-key check, private key storage, and first login are outside the
script. The script runs as root on the VPS and never receives a private key.

The public `curl | bash` installer downloads the current branch archive from
GitHub with no checksum pin. Treat that as an explicit trust boundary, or run
from a reviewed checkout.

## Explicit Configuration

The guided setup asks for the admin user, public key, hostname choice, swap,
web ports, developer CLIs, automatic updates, sudo policy, and Tailscale SSH.
It prints a summary and asks before changing the host. No admin name or swap
size is assumed. Existing active swap is kept.

## Prepare Phase

Prepare installs packages, creates or reuses the admin user and public key,
writes the selected sudo policy, installs root-owned helpers and audit logging,
sets up swap when requested, joins Tailscale, installs selected developer CLIs,
sets selected update timers, and enables the host firewall while keeping public
SSH open.
Prepare also retires known files from the old `vps-bootstrap` name. It removes
only fixed installer paths. It keeps the old audit log and removes the generic
agent link only when that link points to the old managed Grok binary.

It then checks the admin user's sudo helper locally and waits while the operator
tests OpenSSH over the Tailnet from another terminal.

## Harden Phase

Harden runs only after the operator confirms the Tailnet login. It writes
`/etc/ssh/sshd_config.d/00-vpsbuddy-hardening.conf`, validates with `sshd -t`
and `sshd -T`, then reloads SSH. When an old hardening drop-in exists, harden
backs it up before validation and restores the prior SSH policy if validation
fails. It then writes the sudo policy again and removes public SSH from UFW or
firewalld.

The final SSH policy disables password authentication and root login. OpenSSH
remains available on the Tailscale interface for the admin user.

If core prepare work, the local sudo check, or manual Tailnet verification
fails, harden does not run and public SSH stays open. Developer CLI install and
management failures are optional. They are recorded and reported, but they do
not stop the Tailnet check or an operator-approved harden phase.

## Sudo and Helpers

Scoped sudo allows only root-owned `vpsbuddy-*` helpers. The helpers themselves
can install packages, manage services, and change firewall web rules; they are
not a least-privilege package or unit allowlist. Full passwordless sudo is
applied only when chosen.

Each helper writes a best-effort JSONL event to
`/var/log/vpsbuddy-actions.log`. A logging error does not replace the helper's
real exit code.

## Threats and Residual Risk

| Threat                     | Control                                                                |
| -------------------------- | ---------------------------------------------------------------------- |
| Operator lockout           | Keep public SSH open until local sudo and Tailnet login checks pass.   |
| Public SSH remains open    | Remove public TCP 22 in harden after SSH config validation.            |
| Invalid SSH key            | Validate the selected or pasted public key and show its fingerprint.   |
| Broad sudo by accident     | Ask for the policy; default path is helper-scoped, not `NOPASSWD:ALL`. |
| Swap path abuse            | Reject a symlink and do not overwrite an unusable `/swapfile`.         |
| Secret collection          | Accept public keys only; defer developer CLI auth until after setup.   |
| Provider firewall mismatch | Require a separate provider firewall check.                            |

Residual risk remains: wrong key or Tailnet target approval, mutable package and
CLI endpoints, provider firewall or Tailnet ACL mistakes, and lost root sessions
before Tailnet verification.

## Developer CLI Credentials

Codex, Grok, GitHub CLI, Pi, OpenCode, Amp, Factory Droid, and Claude Code are
installed only when selected. Bootstrap does not ask for or store their tokens.
User-scoped upstream installers run as the chosen admin user, not root. GitHub
CLI and required OS packages are installed as root through the supported apt,
dnf, or yum package manager. Each selected GitHub CLI run validates downloaded
repository data, pins apt to the official source or limits rpm package commands
to the `gh-cli` repository, and replaces `gh` from that source. CLI checks and
updates use each managed user binary by its full path. System tools stay ahead
of other user-writable directories. The other CLI install and update paths
trust official mutable upstream
endpoints. Authenticate after setup with `vpsbuddy-auth`.
The helper runs auth flows only for selected CLIs, and `xdg-utils` is installed
only when Factory Droid is selected.

## Updates

When selected, `vpsbuddy-os-update.timer` runs every two weeks. Apt hosts also
receive matching unattended-upgrades setup. When a selected developer CLI
has a self-update command, `vpsbuddy-cli-update.timer` runs every two days. It is not installed for `none`
or for GitHub CLI alone; GitHub updates through the package manager. The timer tries each selected CLI and refreshes its recorded command link. It
exits with a failure status if any update or link refresh fails, so systemd
records the run as failed.

## Resume State

vpsbuddy saves the confirmed setup plan before it changes the server. The state
directory uses mode `0700`; plan, phase, and failed-CLI files use mode `0600`.
Resume checks that the directory and plan are not symlinks, belong to the
running root user, and have no group or other access before loading the plan.
Each loaded field passes the same validation as guided input. Phase values are
limited to `preparing`, `prepared`, `hardening`, and `complete`.

Resume never treats a saved phase as proof that Tailnet login works. Before
hardening, it checks the admin sudo helper and Tailscale address again, then
waits for the operator to confirm a real login from another Tailnet device.

## Tailscale SSH

OpenSSH over the Tailnet is the base path. Tailscale SSH is optional and should
be selected only after Tailnet SSH ACL rules are ready.

## Provider Firewall

Host rules do not change provider firewall rules. Mirror the final policy at the
provider: no public TCP 22, and public TCP 80/443 only when needed.
