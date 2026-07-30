# Security Model

The bootstrap aims to avoid lockout while ending with a narrow SSH surface.

## Trust Before Bootstrap

The operator logs into the VPS before running this script. The provider account,
initial SSH host-key check, private key storage, and first login are outside the
script. Use the provider console and your normal SSH host-key checks.

The script runs as root on the VPS. It never receives a local private key.

## Explicit Configuration

The guided setup asks for the admin user, public key, hostname choice, swap,
web ports, developer CLIs, automatic updates, sudo policy, and Tailscale SSH.
It prints a summary and asks before changing the host.

No admin name or swap size is assumed. Existing active swap is kept.

## Prepare Phase

Prepare:

- installs required OS packages
- creates or reuses the admin user
- installs the selected public key
- writes the selected sudo policy
- installs root-owned helpers and audit logging
- sets up swap when requested
- installs and joins Tailscale
- installs selected developer CLIs
- sets selected update timers
- enables the host firewall while keeping public SSH open

The script checks the new admin user's sudo helper locally. It then waits while
the operator tests OpenSSH over the Tailnet from another terminal.

## Harden Phase

Harden runs only after the operator types `yes` to confirm the Tailnet login.
It writes `/etc/ssh/sshd_config.d/00-vps-bootstrap-hardening.conf`, validates
the full SSH config with `sshd -t`, checks the effective policy with `sshd -T`,
reloads SSH, writes the sudo policy again, then removes public SSH from UFW or
firewalld.

The final SSH policy disables password authentication and root login. OpenSSH
remains available on the Tailscale interface for the admin user.

If prepare, the local sudo check, or manual Tailnet verification fails, harden
does not run and public SSH stays open.

## Sudo and Helpers

Scoped sudo is the normal choice. It allows only root-owned
`vps-agent-*` helpers. Raw package managers, `systemctl`, generic file tools,
and user-level developer CLIs are not direct passwordless sudo targets.

Full passwordless sudo is applied only when the operator chooses it.

Each helper writes a best-effort JSONL event to
`/var/log/vps-agent-actions.log`. A logging error does not replace the helper's
real exit code.

## Swap

When active swap exists, prepare leaves it alone. For a requested `/swapfile`,
the script rejects symlinks, uses mode `0600`, enables the file, and adds it to
`/etc/fstab`. It does not overwrite an unusable existing file.

## Developer CLI Credentials

Codex, Grok, and GitHub CLI are installed only when selected. Bootstrap does not
ask for or store their tokens. The admin user completes native auth after setup
with `vps-agent-auth`.

The CLI install and update paths trust official mutable upstream endpoints.
That supply-chain risk remains. The scoped sudo policy does not grant the
installed user-level CLIs direct root access.

## Updates

When automatic OS updates are selected, `vps-os-update.timer` runs every two
weeks. Apt hosts also receive the matching unattended-upgrades setup.

When developer CLIs are selected, `vps-agent-cli-update.timer` runs every two
days.

## Tailscale SSH

OpenSSH over the Tailnet is the base path. Tailscale SSH is optional and should
be selected only after the Tailnet SSH ACL rules are ready. A wrong ACL can
block access even after OpenSSH verification.

## Provider Firewall

Host rules do not change provider firewall rules. Mirror the final policy at
the provider: no public TCP 22, and public TCP 80/443 only when needed.
