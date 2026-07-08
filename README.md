# VPS Bootstrap

Security-first VPS setup scripts for fresh servers.

`vps-bootstrap` takes a newly provisioned VPS from an initial password SSH login
to a Tailnet-first operating baseline. It is meant for
operators who want a repeatable first-hour hardening flow before installing an
application stack.

This is not a Dokploy, Coolify, PaaS, or hosting-panel clone. It does not
schedule apps, issue certificates, manage containers, or provide a web UI. It
prepares the server underneath those choices: SSH hardening, firewall posture,
admin user setup, bounded sudo helpers, Tailscale access, update timers, and
developer CLI installation.

Current status: `v0.1.0-alpha`. The project is usable for review and local
testing, but public releases should be treated as early and security-sensitive.

## What It Does

- Creates a non-root sudo admin user, defaulting to `deploy`.
- Installs your local OpenSSH public key for that admin user.
- Pins the first SSH connection to a host public key pasted from the VPS
  provider console.
- Installs and joins Tailscale interactively.
- Verifies Tailnet SSH and bounded sudo before disabling public password
  SSH.
- Restricts SSH to the Tailnet while leaving public TCP 80/443 open by default
  for hosted web applications.
- Installs Codex CLI, Grok CLI, and GitHub CLI only when explicitly requested.
- Adds an OS package update timer by default and agent CLI update timers only
  when agent CLIs are installed.
- Supports fresh Ubuntu, Debian, Fedora, RHEL-family, AlmaLinux, and Rocky Linux
  hosts through apt, dnf, or yum paths.

## Requirements

- A fresh VPS where you can initially SSH with password authentication as
  `root`, `ubuntu`, `ec2-user`, or another sudo-capable login user.
- A local SSH public/private key pair.
- Access to the VPS provider console so you can copy the server SSH host public
  key before the first connection.
- Outbound internet access from the VPS for package installation and Tailscale
  login.
- A Tailscale account and the ability to approve the interactive login URL.

Do not run this against a long-lived or manually customized server unless you
have audited the generated dry-run output and are prepared to recover it.

## Quick Start

Inspect the plan first:

```bash
bin/vps-bootstrap --host 203.0.113.10 --hostname app-01 --dry-run
```

Run the bootstrap from your laptop or workstation:

```bash
bin/vps-bootstrap --host 203.0.113.10 --hostname app-01
```

Useful options:

```bash
bin/vps-bootstrap \
  --host 203.0.113.10 \
  --login-user root \
  --user deploy \
  --pubkey ~/.ssh/id_ed25519.pub \
  --identity ~/.ssh/id_ed25519 \
  --hostname app-01 \
  --enable-tailscale-ssh
```

For cloud images that start with `ubuntu` instead of direct root login:

```bash
bin/vps-bootstrap \
  --host 203.0.113.10 \
  --login-user ubuntu \
  --user ubuntu \
  --pubkey ~/.ssh/id_ed25519.pub \
  --identity ~/.ssh/id_ed25519 \
  --hostname app-01
```

Use `--no-web` or `--web=false` for private-only servers where public HTTP and
HTTPS should remain closed.

To install optional developer CLIs, pass `--install-agent-clis`:

```bash
bin/vps-bootstrap --host 203.0.113.10 --hostname app-01 --install-agent-clis
```

After setup with that option, SSH over the Tailnet and authenticate those CLIs:

```bash
ssh deploy@<tailscale-ip>
vps-agent-auth --all
vps-agent-auth --status
```

## Safety Model

The bootstrap intentionally keeps rollback access until the Tailnet path is
verified:

1. Prepare through the initial login user while temporary public SSH remains open.
2. Verify that the new admin user can SSH over the Tailnet and run the bounded
   sudo check.
3. Harden SSH and remove public SSH only after verification succeeds.

If preparation or verification fails, the original public SSH access path is left
active so the server can be repaired.

Read the detailed model in
[documentation/security-model.md](documentation/security-model.md) and the
public threat model in
[documentation/threat-model.md](documentation/threat-model.md).

## Smoke Test Guidance

Before cutting or trusting a release:

```bash
make check
bin/vps-bootstrap --host 203.0.113.10 --hostname smoke-01 --dry-run
```

For a real VPS smoke test, use a disposable fresh instance and verify:

- The script prompts for and uses the provider SSH host public key.
- Tailscale login completes during the prepare phase.
- `ssh deploy@<tailscale-ip>` succeeds after setup.
- `sudo -n /usr/local/sbin/vps-agent-sudo-check` succeeds for the admin user.
- Public TCP 22 is closed from a non-Tailnet network.
- Public TCP 80/443 match the selected `--web` setting.
- `systemctl list-timers` shows the OS update timer, plus the agent CLI update
  timer when `--install-agent-clis` was used.
- `bin/vps-bootstrap doctor` reports no blocking local input issues from the
  workstation.
- `vps-agent-auth --status` reports the expected post-setup auth state when
  `--install-agent-clis` was used.

The release checklist lives in
[documentation/release-process.md](documentation/release-process.md).

## Documentation

- [documentation/README.md](documentation/README.md): advanced usage and
  operator notes.
- [documentation/security-model.md](documentation/security-model.md): phased
  hardening and credential handling.
- [documentation/threat-model.md](documentation/threat-model.md): assets,
  trust boundaries, threats, and non-goals.
- [documentation/compatibility-matrix.md](documentation/compatibility-matrix.md):
  supported host families and smoke-test targets.
- [documentation/provider-firewall-checklist.md](documentation/provider-firewall-checklist.md):
  provider firewall expectations.
- [documentation/comparison.md](documentation/comparison.md): how this differs
  from hosting panels and provisioning tools.
- [documentation/faq.md](documentation/faq.md): common operating questions.
- [documentation/roadmap.md](documentation/roadmap.md): alpha roadmap.
- [documentation/testing.md](documentation/testing.md): local checks and test
  strategy.
- [documentation/references.md](documentation/references.md): upstream install
  and auth references.

## Community

Security issues should be reported through the private process in
[SECURITY.md](SECURITY.md). General contributions should follow
[CONTRIBUTING.md](CONTRIBUTING.md) and the
[CODE_OF_CONDUCT.md](CODE_OF_CONDUCT.md).

## License

Apache License 2.0. See [LICENSE](LICENSE).
