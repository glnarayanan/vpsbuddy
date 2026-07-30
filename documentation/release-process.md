# Release Process

This is an alpha security tool. A release needs both local checks and a
disposable VPS run.

## Local Checks

```bash
make check
bin/vps-bootstrap --dry-run
```

Confirm that dry-run asks for and prints:

- admin user and SSH key fingerprint
- hostname choice
- swap choice and size
- public web ports
- developer CLIs
- automatic OS updates
- sudo policy
- Tailscale SSH

Review:

- [../README.md](../README.md)
- [security-model.md](security-model.md)
- [threat-model.md](threat-model.md)
- [compatibility-matrix.md](compatibility-matrix.md)
- [provider-firewall-checklist.md](provider-firewall-checklist.md)
- [../CHANGELOG.md](../CHANGELOG.md)

## Disposable VPS Smoke Test

Provision a new VPS with an SSH key and keep the provider console open.

Log in, then run:

```bash
curl -fsSL https://raw.githubusercontent.com/glnarayanan/server-setup-scripts/main/install.sh | bash
```

During the run:

- confirm the detected public-key fingerprint or paste a test key
- choose an explicit swap size
- complete the Tailscale login
- keep the first public SSH session open
- test the printed admin Tailnet login from another terminal
- type `yes` in the first terminal only after that login works

After hardening, run as the admin user:

```bash
sudo -n /usr/local/sbin/vps-agent-sudo-check
swapon --show
systemctl list-timers | grep -E 'vps-(os|agent-cli)-update'
sudo sshd -T | grep -E 'passwordauthentication|kbdinteractiveauthentication|permitrootlogin'
sudo ufw status verbose 2>/dev/null || sudo firewall-cmd --list-all
```

From a non-Tailnet network:

```bash
nc -vz <public-ip> 22
nc -vz <public-ip> 80
nc -vz <public-ip> 443
```

Expected:

- public TCP 22 is closed
- Tailnet SSH works for the admin user
- password login and root SSH login are disabled
- TCP 80/443 match the choice made during setup
- swap matches the chosen state
- selected timers exist
- selected developer CLIs exist and `vps-agent-auth --status` runs
- helper use appends to `/var/log/vps-agent-actions.log`

Test at least Ubuntu before an alpha tag. Record the provider image and any
differences in the release notes.

## Tag

After review and smoke tests:

```bash
git tag -a v0.1.0-alpha -m "v0.1.0-alpha"
git push origin v0.1.0-alpha
```

Do not tag a dirty or unreviewed tree.
