# VPS Bootstrap

Security-first VPS setup scripts for fresh servers.

`vps-bootstrap` takes a newly provisioned VPS from an initial provider SSH login
to a Tailnet-first operating baseline. It is meant for
operators who want a repeatable first-hour hardening flow before installing an
application stack.

This is not a Dokploy, Coolify, PaaS, or hosting-panel clone. It does not
schedule apps, issue certificates, manage containers, or provide a web UI. It
prepares the server underneath those choices: SSH hardening, firewall posture,
admin user setup, bounded sudo helpers, Tailscale access, swap space, update
timers, and developer CLI installation.

Current status: `v0.1.0-alpha`. The project is usable for review and local
testing, but public releases should be treated as early and security-sensitive.

## What It Does

- Creates a non-root sudo admin user, defaulting to `deploy`.
- Installs your local OpenSSH public key for that admin user.
- Pins the first SSH connection to a host public key pasted from the provider or
  scanned and confirmed during bootstrap.
- Installs and joins Tailscale interactively.
- Verifies Tailnet SSH and bounded sudo before disabling public SSH.
- Restricts SSH to the Tailnet while leaving public TCP 80/443 open by default
  for hosted web applications.
- Creates and enables a 2G `/swapfile` when no active swap exists, or uses the
  size passed with `--swap-size`.
- Asks whether to install Codex CLI, Grok CLI, and GitHub CLI during an
  interactive bootstrap; explicit flags control unattended runs.
- Adds an OS package update timer by default and agent CLI update timers only
  when agent CLIs are installed.
- Supports fresh Ubuntu, Debian, Fedora, RHEL-family, AlmaLinux, and Rocky Linux
  hosts through apt, dnf, or yum paths.

## Requirements

- A fresh VPS where you can initially SSH as the provider's initial SSH user,
  with a password or a key.
- A local SSH public/private key pair.
- Access to the VPS provider console for recovery and optional host-key
  comparison.
- Outbound internet access from the VPS for package installation and Tailscale
  login.
- Enough free disk space for the selected swap size when the VPS has no active
  swap. The default size is 2G.
- A Tailscale account and the ability to approve the interactive login URL.

Do not run this against a long-lived or manually customized server unless you
have audited the generated dry-run output and are prepared to recover it.

## Quick Start

Inspect the plan first:

```bash
bin/vps-bootstrap --host 203.0.113.10 --login-user your-provider-user --hostname app-01 --dry-run
```

Run the top-level CLI from your laptop or workstation. The VPS needs no checkout
or private key; the CLI sends the generated remote script over SSH:

```bash
bin/vps-bootstrap --host 203.0.113.10 --login-user your-provider-user --hostname app-01
```

Useful options:

```bash
bin/vps-bootstrap \
  --host 203.0.113.10 \
  --login-user your-provider-user \
  --login-identity ~/.ssh/provider_key \
  --user deploy \
  --pubkey ~/.ssh/id_ed25519.pub \
  --identity ~/.ssh/id_ed25519 \
  --hostname app-01 \
  --swap-size 4G \
  --enable-tailscale-ssh
```

When the provider's initial SSH user should also be the managed admin user:

```bash
bin/vps-bootstrap \
  --host 203.0.113.10 \
  --login-user your-provider-user \
  --user your-provider-user \
  --pubkey ~/.ssh/id_ed25519.pub \
  --identity ~/.ssh/id_ed25519 \
  --hostname app-01
```

If the provider installs a key for a root-only initial login, pass that private
key with `--login-identity`. The existing `--identity` option remains the key
used for the managed admin user over the Tailnet. If the login key is already
available through your SSH agent or SSH config, `--login-identity` is optional.

Use `--no-web` or `--web=false` for private-only servers where public HTTP and
HTTPS should remain closed.

Swap setup runs by default during prepare. Use `--no-swap` when another system
already manages memory or when the host should not create swap.

An interactive bootstrap asks before the first SSH connection whether to
install optional developer CLIs. Answer `yes` to install Codex CLI, Grok CLI,
GitHub CLI, `vps-agent-auth`, and the CLI update timer. These installs are
best-effort so an upstream CLI installer outage does not stop SSH hardening.
For unattended runs, pass `--install-agent-clis` or `--skip-agent-clis`:

```bash
bin/vps-bootstrap --host 203.0.113.10 --login-user your-provider-user --hostname app-01 --install-agent-clis
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
3. Ask you to verify SSH from another terminal and type `yes`.
4. Harden SSH and remove public SSH only after automated and manual verification
   succeed.

If preparation or verification fails, the original public SSH access path is left
active so the server can be repaired.

If you do not confirm hardening, the script leaves public SSH available
and exits cleanly. Rerun the same command later; it will re-check the completed
setup and continue to the hardening confirmation.

Read the detailed model in
[documentation/security-model.md](documentation/security-model.md) and the
public threat model in
[documentation/threat-model.md](documentation/threat-model.md).

## Smoke Test Guidance

Before cutting or trusting a release:

```bash
make check
bin/vps-bootstrap --host 203.0.113.10 --login-user your-provider-user --hostname smoke-01 --dry-run
```

For a real VPS smoke test, use a disposable fresh instance and verify:

- The script pins the first SSH host key from provider input or a confirmed scan.
- Tailscale login completes during the prepare phase.
- `ssh deploy@<tailscale-ip>` succeeds after setup.
- `sudo -n /usr/local/sbin/vps-agent-sudo-check` succeeds for the admin user.
- Public TCP 22 is closed from a non-Tailnet network.
- Public TCP 80/443 match the selected `--web` setting.
- `systemctl list-timers` shows the OS update timer, plus the agent CLI update
  timer when agent CLIs were selected.
- `swapon --show` reports active swap, unless `--no-swap` was used.
- `bin/vps-bootstrap doctor` reports no blocking local input issues from the
  workstation.
- `vps-agent-auth --status` reports the expected post-setup auth state when
  agent CLIs were selected.

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
