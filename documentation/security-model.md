# Security Model

The bootstrap process optimizes for avoiding accidental lockout while ending with a narrow SSH exposure.

## Final State

- SSH password authentication is disabled.
- Root SSH login is disabled.
- Public key authentication is enabled.
- SSH is allowed only on the Tailscale interface.
- Public TCP 80/443 remain open by default for hosted web applications.
- Unsolicited inbound traffic is denied by the host firewall.
- The admin user has passwordless sudo by default only for root-owned `vps-agent-*` helpers so common agentic operations can work without raw broad root primitives.
- Codex CLI, Grok CLI, and GitHub CLI are installed only when `--install-agent-clis` is passed, and authentication is deferred to the post-setup `vps-agent-auth` helper.
- Codex and Grok are updated every two days by `vps-agent-cli-update.timer` only when agent CLIs are installed.
- OS packages are updated every two weeks by `vps-os-update.timer`; apt hosts also receive fourteen-day `unattended-upgrades` periodic configuration.

## Phased Rollback Protection

Before the first remote phase, the local CLI prompts for the VPS SSH host public key from the provider console and pins it in a temporary `known_hosts` file. The script then uses strict host-key checking instead of trusting the first key seen.

The first remote phase creates the admin user, installs the key, installs bounded sudo helpers, installs Tailscale, joins the Tailnet, enables baseline services, optionally installs developer CLIs, and configures the firewall with temporary public SSH still allowed.

The local CLI then connects to the Tailnet IP as the new admin user and runs `sudo -n /usr/local/sbin/vps-agent-sudo-check`. Only after that succeeds does the harden phase run over the Tailnet connection.

The prepare phase temporarily grants broad passwordless sudo so the verified Tailnet harden phase can run through `sudo bash -s`. The harden phase then writes the final requested sudo policy: bounded helper access by default, or `NOPASSWD:ALL` only when `--full-sudo` is passed.

The harden phase also writes `/etc/ssh/sshd_config.d/90-vps-bootstrap-hardening.conf`, validates it with `sshd -t`, reloads SSH, and removes public SSH from UFW or firewalld.

## Developer CLI Credentials

When `--install-agent-clis` is used, `vps-agent-auth` runs native auth flows where available and prints setup checks for API-key based tools after bootstrap is complete.

The bootstrap script does not accept, upload, or store raw agent CLI tokens, API keys, or GitHub private keys. Each CLI handles its own auth state or configuration:

- Codex auth through `codex login`.
- Grok auth through `grok login`, or `XAI_API_KEY` in non-browser environments.
- GitHub CLI auth through `gh auth login --hostname github.com --git-protocol ssh`.

The admin user receives passwordless sudo by default for these root-owned helpers only: `vps-agent-sudo-check`, `vps-agent-package`, `vps-agent-service`, `vps-agent-logs`, `vps-agent-firewall`, `vps-agent-deploy`, `vps-agent-cli-update`, and `vps-os-update`. Raw package managers, `systemctl`, `npm`, file ownership/write tools, and user-level Codex/Grok binaries are not directly sudo-allowed by the default policy. Use `--full-sudo` only when a server intentionally needs broad `NOPASSWD:ALL`.

Each `vps-agent-*` helper writes a best-effort JSONL event to `/var/log/vps-agent-actions.log`. Events include timestamp, helper name, invoking user, action, sanitized arguments, and exit code. Logging failures do not override the helper's real result.

## Update Automation

When agent CLIs are installed, `vps-agent-cli-update.timer` runs every two days with persistence across reboots. It reruns OpenAI's Codex installer in non-interactive mode and runs `grok update` as the admin user.

The Codex, Grok, and Tailscale installer paths intentionally trust official mutable upstream installer/update endpoints because version-pinned installers are not available in this script. The bootstrap logs that accepted supply-chain trust boundary when those installers or updates run, and the default sudo policy does not give the installed user-level CLIs direct passwordless root access.

`vps-os-update.timer` runs every two weeks with persistence across reboots. It uses `unattended-upgrade -d` on apt hosts when available, `dnf -y upgrade` on dnf hosts, and `yum -y update` on yum hosts.

## Tailscale SSH

OpenSSH over the Tailnet is the default model. `--enable-tailscale-ssh` also runs `tailscale set --ssh` on the host, but Tailnet ACL SSH rules must still be configured in the Tailscale admin console.

## Provider Firewalls

The host firewall cannot override a provider firewall that already blocks traffic, and a provider firewall can still expose TCP 22 if it is configured loosely. Mirror the final host policy at the provider layer.
