# Compatibility Matrix

This matrix describes intended `v0.1.0-alpha` compatibility for fresh VPS
images. It is not a guarantee that every provider image has been smoke-tested.

## Host Operating Systems

| OS family                    | Package path | Intended status | Notes                                                             |
| ---------------------------- | ------------ | --------------- | ----------------------------------------------------------------- |
| Ubuntu LTS                   | apt          | Primary target  | Best first smoke-test target.                                     |
| Debian stable                | apt          | Intended        | Should follow the apt path; image defaults vary by provider.      |
| Fedora Server                | dnf          | Intended        | Requires systemd and firewalld-compatible behavior.               |
| AlmaLinux                    | dnf/yum      | Intended        | RHEL-family path; provider images may differ.                     |
| Rocky Linux                  | dnf/yum      | Intended        | RHEL-family path; provider images may differ.                     |
| RHEL-compatible derivatives  | dnf/yum      | Best effort     | Verify package names, firewalld state, and SSH include support.   |
| Arch, Alpine, NixOS, FreeBSD | none         | Unsupported     | Package manager and service assumptions do not match this script. |

## Required Host Capabilities

| Capability                           | Required | Why                                                           |
| ------------------------------------ | -------- | ------------------------------------------------------------- |
| Initial `root@host` password SSH     | Yes      | The prepare phase uses temporary root access.                 |
| systemd                              | Yes      | Timers and service management assume systemd.                 |
| OpenSSH server                       | Yes      | The hardening phase writes OpenSSH config.                    |
| UFW or firewalld path                | Yes      | Host firewall commands are generated for supported families.  |
| Outbound internet                    | Yes      | Packages, Tailscale, and CLI installers need outbound access. |
| Provider-console SSH host public key | Yes      | The first SSH connection is pinned to this key.               |
| Tailscale login approval             | Yes      | Tailnet verification must succeed before hardening.           |

## Local Workstation

| Dependency         | Required    | Notes                                                           |
| ------------------ | ----------- | --------------------------------------------------------------- |
| Bash               | Yes         | Runs the local CLI and tests.                                   |
| OpenSSH client     | Yes         | Used for public root SSH and Tailnet verification.              |
| Local SSH key pair | Yes         | Public key is installed for the admin user.                     |
| `make`             | Recommended | Runs local checks.                                              |
| ShellCheck         | Optional    | `make lint` uses it when installed and falls back to `bash -n`. |
| `nc`               | Recommended | Useful for provider firewall smoke tests.                       |

## Smoke-Test Targets

For `v0.1.0-alpha`, prioritize disposable fresh instances in this order:

1. Ubuntu LTS apt path.
2. Debian stable apt path.
3. Fedora dnf path.
4. AlmaLinux or Rocky Linux RHEL-family path.

For each target, verify the release checklist in
[release-process.md](release-process.md) and record provider image details in
the release notes.

## Unsupported Scenarios

- Existing production servers with manual SSH, firewall, or sudo customization.
- Hosts without systemd.
- Hosts where the provider cannot expose the SSH host public key before first
  connection.
- Private networks where Tailscale login cannot complete.
- Environments requiring FIPS, CIS, FedRAMP, PCI, or other formal compliance
  baselines.
