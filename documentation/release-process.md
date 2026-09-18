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
explicit swap size, choose a CLI list or `none`, complete Tailscale login, keep
the first public SSH session open, test the printed admin Tailnet login from
another terminal, and type `yes` only after that login works.

After hardening, as the admin user:

```bash
sudo -n /usr/local/sbin/vpsbuddy-sudo-check
swapon --show
systemctl list-timers | grep -E 'vpsbuddy-(os|cli)-update'
sudo sshd -T -C "user=root,host=$(hostname),addr=127.0.0.1" | grep '^permitrootlogin '
sudo sshd -T -C "user=$(id -un),host=$(hostname),addr=127.0.0.1" |
  grep -E '^(passwordauthentication|kbdinteractiveauthentication) '
sudo ufw status verbose 2>/dev/null || sudo firewall-cmd --list-all
```

From a non-Tailnet network:

```bash
nc -vz <public-ip> 22
nc -vz <public-ip> 80
nc -vz <public-ip> 443
```

Expect: public TCP 22 closed; Tailnet SSH works; password and root SSH disabled;
TCP 80/443 match the setup choice; swap, selected CLIs, and selected timers
match; no CLI update timer exists for `none` or GitHub CLI alone; helper use
appends to `/var/log/vpsbuddy-actions.log`.

Test at least Ubuntu before a release. Record the provider image in the release
notes.
