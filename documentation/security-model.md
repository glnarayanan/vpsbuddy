# Security Model

The bootstrap process optimizes for avoiding accidental lockout while ending with a narrow SSH exposure.

## Final State

- SSH password authentication is disabled.
- Root SSH login is disabled.
- Public key authentication is enabled.
- SSH is allowed only on the Tailscale interface.
- Public TCP 80/443 remain open by default for hosted web applications.
- Unsolicited inbound traffic is denied by the host firewall.
- The admin user has passwordless sudo so the local key-based verification and future automation can work without a server-side password.

## Phased Rollback Protection

The first remote phase creates the admin user, installs the key, installs Tailscale, joins the Tailnet, enables baseline services, and configures the firewall with temporary public SSH still allowed.

The local CLI then connects to the Tailnet IP as the new admin user and runs `sudo -n true`. Only after that succeeds does the harden phase run over the Tailnet connection.

The harden phase writes `/etc/ssh/sshd_config.d/90-vps-bootstrap-hardening.conf`, validates it with `sshd -t`, reloads SSH, and removes public SSH from UFW or firewalld.

## Tailscale SSH

OpenSSH over the Tailnet is the default model. `--enable-tailscale-ssh` also runs `tailscale set --ssh` on the host, but Tailnet ACL SSH rules must still be configured in the Tailscale admin console.

## Provider Firewalls

The host firewall cannot override a provider firewall that already blocks traffic, and a provider firewall can still expose TCP 22 if it is configured loosely. Mirror the final host policy at the provider layer.
