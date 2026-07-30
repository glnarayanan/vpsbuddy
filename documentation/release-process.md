# Release Process

## Local Checks

```bash
make check
bin/vpsbuddy --dry-run
```

Review README, security-model, compatibility-matrix, provider-firewall-checklist,
and CHANGELOG.

## Disposable VPS Smoke Test

Provision a new VPS with an SSH key and keep the provider console open.

```bash
curl -fsSL https://raw.githubusercontent.com/glnarayanan/vpsbuddy/main/install.sh | bash
```

During the run: confirm the key fingerprint or paste a test key, choose an
explicit swap size, complete Tailscale login, keep the first public SSH session
open, test the printed admin Tailnet login from another terminal, and type
`yes` only after that login works.

After hardening, as the admin user:

```bash
sudo -n /usr/local/sbin/vpsbuddy-sudo-check
swapon --show
systemctl list-timers | grep -E 'vpsbuddy-(os|cli)-update'
sudo sshd -T | grep -E 'passwordauthentication|kbdinteractiveauthentication|permitrootlogin'
sudo ufw status verbose 2>/dev/null || sudo firewall-cmd --list-all
```

From a non-Tailnet network:

```bash
nc -vz <public-ip> 22
nc -vz <public-ip> 80
nc -vz <public-ip> 443
```

Expect: public TCP 22 closed; Tailnet SSH works; password and root SSH disabled;
TCP 80/443 match the setup choice; swap and selected timers/CLIs match; helper
use appends to `/var/log/vpsbuddy-actions.log`.

Test at least Ubuntu before an alpha tag. Record the provider image in the
release notes.

## Tag

```bash
git tag -a v0.1.0-alpha -m "v0.1.0-alpha"
git push origin v0.1.0-alpha
```

Do not tag a dirty or unreviewed tree.
