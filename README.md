# vpsbuddy

`vpsbuddy` prepares a fresh VPS after you have logged into it. It creates an
admin user, installs the chosen SSH key, joins Tailscale, sets up swap, hardens
SSH, sets firewall rules, and can install developer CLIs.

It does not deploy apps, manage containers, issue certificates, or run a web
control plane.

## Quick Start

Provision the VPS with your SSH key, then log in with the provider user:

```bash
ssh -i ~/.ssh/provider_key root@203.0.113.10
```

Run the guided installer on the VPS:

```bash
curl -fsSL https://raw.githubusercontent.com/glnarayanan/vpsbuddy/main/install.sh | bash
```

To inspect prompts and summary without changing the server:

```bash
curl -fsSL https://raw.githubusercontent.com/glnarayanan/vpsbuddy/main/install.sh |
  bash -s -- --dry-run
```

The installer asks for every operator choice: admin user, SSH public key,
optional hostname, swap, public web ports, Codex/Grok/GitHub CLI installation,
automatic OS updates, scoped or full passwordless sudo, and optional Tailscale
SSH. There is no default admin name or swap size. Active swap is left unchanged.

## Safe Hardening Flow

1. Prepare the user, key, packages, Tailscale, swap, helpers, and firewall while
   public SSH stays open.
2. Check the new admin user's sudo helper on the server.
3. Wait while you test `ssh <admin>@<tailscale-ip>` from another terminal.
4. Harden SSH and remove public TCP 22 only after you type `yes`.

If preparation, the sudo check, or your Tailnet login test fails, public SSH
stays open.

## Final State

- SSH passwords and root SSH login are disabled.
- OpenSSH is reachable through the Tailscale interface.
- The host firewall denies other inbound traffic.
- Public TCP 80/443 follow the choice made during setup.
- The admin user gets passwordless access to root-owned `vpsbuddy-*` helpers
  unless full sudo was chosen.
- `/swapfile` is created only when requested and no swap is active.
- OS and developer CLI timers are installed only when selected.

When developer CLIs are installed, authenticate after setup:

```bash
ssh <admin>@<tailscale-ip>
vpsbuddy-auth --all
vpsbuddy-auth --status
```

`vpsbuddy` does not ask for or store CLI tokens.

Mirror the final host firewall policy in the VPS provider firewall: no public
TCP 22, and public TCP 80/443 only when chosen. See
[documentation/provider-firewall-checklist.md](documentation/provider-firewall-checklist.md).

## Supported Hosts

Fresh systemd VPS images:

- Ubuntu or Debian with apt
- Fedora with dnf
- AlmaLinux, Rocky Linux, or another supported RHEL-family image with dnf or yum

Ubuntu LTS is the primary smoke-tested target. See
[documentation/compatibility-matrix.md](documentation/compatibility-matrix.md).

## Local Development

```bash
make check
bin/vpsbuddy --dry-run
```

Use a disposable VPS for a real smoke test. Do not run this alpha against a
long-lived server without checking how it will affect SSH, sudo, firewall, swap,
users, and services.

## Documentation

- [Operator guide](documentation/README.md)
- [Security model](documentation/security-model.md)
- [Compatibility matrix](documentation/compatibility-matrix.md)
- [Provider firewall checklist](documentation/provider-firewall-checklist.md)
- [Release process](documentation/release-process.md)
- [Testing](documentation/testing.md)
- [Upstream references](documentation/references.md)

Security issues: [SECURITY.md](SECURITY.md). Contributions: [CONTRIBUTING.md](CONTRIBUTING.md).

Apache License 2.0. See [LICENSE](LICENSE).
