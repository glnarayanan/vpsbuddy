# Compatibility Matrix

Provider image changes can still affect package names, SSH includes, services,
and firewall behavior.

## Host Operating Systems

| OS family                    | Package path | Status                                     |
| ---------------------------- | ------------ | ------------------------------------------ |
| Ubuntu LTS                   | apt          | Primary target; required before alpha tags |
| Debian stable                | apt          | Supported path; not yet smoke-tested       |
| Fedora Server                | dnf          | Supported path; not yet smoke-tested       |
| AlmaLinux                    | dnf or yum   | Supported path; not yet smoke-tested       |
| Rocky Linux                  | dnf or yum   | Supported path; not yet smoke-tested       |
| Other RHEL-family images     | dnf or yum   | Best effort                                |
| Arch, Alpine, NixOS, FreeBSD | none         | Unsupported                                |

## Required VPS State

| Capability         | Requirement                                            |
| ------------------ | ------------------------------------------------------ |
| Initial shell      | Log in first as root, or as a user with working sudo.  |
| Bash               | Required to run the installer and bootstrap.           |
| curl               | Required by the public one-line installer.             |
| systemd            | Required for services and timers.                      |
| OpenSSH server     | Required and must support config includes.             |
| Outbound internet  | Required for packages, Tailscale, and selected CLIs.   |
| Tailscale approval | Required before hardening can finish.                  |
| Public key         | A valid OpenSSH public key must be detected or pasted. |
| Recovery console   | Strongly advised for smoke tests and recovery.         |

The operator needs a second Tailnet-connected terminal to test the new admin
login before hardening.

## Unsupported Use

- hosts without systemd
- long-lived production servers with custom SSH, firewall, or sudo state
- hosts that cannot reach Tailscale
- fleet management
- compliance hardening
