# Security Model

The bootstrap process optimizes for avoiding accidental lockout while ending with a narrow SSH exposure.

## Final State

- SSH password authentication is disabled.
- Root SSH login is disabled.
- Public key authentication is enabled.
- SSH is allowed only on the Tailscale interface.
- Public TCP 80/443 remain open by default for hosted web applications.
- Unsolicited inbound traffic is denied by the host firewall.
- The admin user has scoped passwordless sudo by default so common agentic operations can work without broad root access.
- Codex CLI, Grok CLI, and GitHub CLI are installed by default, but authentication is deferred to the post-setup `vps-agent-auth` helper.

## Phased Rollback Protection

The first remote phase creates the admin user, installs the key, installs Tailscale, joins the Tailnet, enables baseline services, installs developer CLIs, and configures the firewall with temporary public SSH still allowed.

The local CLI then connects to the Tailnet IP as the new admin user and runs `sudo -n true`. Only after that succeeds does the harden phase run over the Tailnet connection.

The prepare phase temporarily grants broad passwordless sudo so the verified Tailnet harden phase can run through `sudo bash -s`. The harden phase then writes the final requested sudo policy: scoped by default, or `NOPASSWD:ALL` only when `--full-sudo` is passed.

The harden phase also writes `/etc/ssh/sshd_config.d/90-vps-bootstrap-hardening.conf`, validates it with `sshd -t`, reloads SSH, and removes public SSH from UFW or firewalld.

## Developer CLI Credentials

`vps-agent-auth` runs native auth flows where available and prints setup checks for API-key based tools after bootstrap is complete.

The bootstrap script does not accept, upload, or store raw agent CLI tokens or API keys. Each CLI handles its own auth state or configuration:

- Codex auth through `codex login`.
- Grok auth through `grok login`, or `XAI_API_KEY` in non-browser environments.
- GitHub CLI auth through `gh auth login --hostname github.com --git-protocol ssh`.

The admin user receives scoped passwordless sudo by default for package, service, log, firewall, deployment, and agent-tool operations. Use `--full-sudo` only when a server intentionally needs broad `NOPASSWD:ALL`.

## Tailscale SSH

OpenSSH over the Tailnet is the default model. `--enable-tailscale-ssh` also runs `tailscale set --ssh` on the host, but Tailnet ACL SSH rules must still be configured in the Tailscale admin console.

## Provider Firewalls

The host firewall cannot override a provider firewall that already blocks traffic, and a provider firewall can still expose TCP 22 if it is configured loosely. Mirror the final host policy at the provider layer.
