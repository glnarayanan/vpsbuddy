# Release Process

This project is alpha and security-sensitive. A release should prove that the
documented bootstrap flow still works on disposable fresh VPS hosts before users
are asked to trust it.

## Versioning

Use `v0.1.0-alpha` for the first public alpha tag.

Before stable releases, breaking changes are allowed when they improve safety or
clarity. Document operator-visible changes in [../CHANGELOG.md](../CHANGELOG.md).

## Pre-Release Checklist

Run local checks:

```bash
make check
```

Review docs:

- [README.md](../README.md)
- [security-model.md](security-model.md)
- [threat-model.md](threat-model.md)
- [compatibility-matrix.md](compatibility-matrix.md)
- [provider-firewall-checklist.md](provider-firewall-checklist.md)
- [CHANGELOG.md](../CHANGELOG.md)

Inspect the dry-run plan:

```bash
bin/vps-bootstrap --host 203.0.113.10 --hostname smoke-01 --dry-run
```

Run the read-only doctor audit:

```bash
bin/vps-bootstrap doctor --host 203.0.113.10
```

Confirm the dry-run communicates:

- Host-key prompt expectations.
- Initial key-only SSH access through `--login-identity` when the provider image disables password SSH.
- Prepare, verify, and harden phase ordering.
- Admin user and key paths.
- Tailscale verification before SSH hardening.
- Final web exposure based on `--web` or `--no-web`.
- Default bounded sudo policy or explicit `--full-sudo` behavior.
- Agent CLI installation is skipped unless `--install-agent-clis` is present.

## Disposable VPS Smoke Test

Use a new disposable VPS with no application data.

Minimum smoke test:

```bash
bin/vps-bootstrap --host <public-ip> --hostname smoke-01
```

During the run:

- Paste the server SSH host public key when the provider exposes it; otherwise
  press Enter, confirm the scanned fingerprint, and verify the pinned-key path.
- Complete the interactive Tailscale login.
- Watch for successful Tailnet SSH verification.
- Confirm the harden phase runs only after verification.

After the run:

```bash
ssh deploy@<tailscale-ip>
sudo -n /usr/local/sbin/vps-agent-sudo-check
swapon --show
systemctl list-timers | grep 'vps-os-update'
test -r /var/log/vps-agent-actions.log && tail -n 5 /var/log/vps-agent-actions.log
```

From the workstation checkout, run `doctor` again after bootstrap to capture the
same local plan plus any state visible from the current machine:

```bash
bin/vps-bootstrap doctor --host <public-ip>
```

If you intentionally copied this repository to the VPS, you may also run
`bin/vps-bootstrap doctor` there for on-server observations.

If the release specifically validates optional agent CLIs, rerun the smoke test
with `--install-agent-clis`, confirm `vps-agent-cli-update.timer`, and then run
`vps-agent-auth --status`.

From a non-Tailnet network:

```bash
nc -vz <public-ip> 22
nc -vz <public-ip> 80
nc -vz <public-ip> 443
```

Expected results:

- TCP 22 is closed publicly.
- TCP 80/443 are open only when web access is enabled.
- Tailnet SSH works for the admin user.
- The bounded sudo check succeeds.
- Active swap is present, unless the run used `--no-swap`.
- The OS update timer is installed.
- `doctor` reports expected post-bootstrap state.
- Helper audit events are written after helper use.
- Developer CLI auth is deferred until `vps-agent-auth` when agent CLIs are installed.

## Release Notes

Each release note should include:

- Version and date.
- Supported or smoke-tested OS/provider images.
- Security posture changes.
- Compatibility changes.
- Known alpha limitations.
- Any manual provider firewall expectations.

## Tagging

After checks and smoke tests pass:

```bash
git tag -a v0.1.0-alpha -m "v0.1.0-alpha"
git push origin v0.1.0-alpha
```

Do not tag a release from an unreviewed dirty worktree.

## Post-Release

- Verify the tag and release notes render correctly.
- Re-read [SECURITY.md](../SECURITY.md) for any version support updates.
- Open follow-up issues for smoke-test gaps rather than hiding them.
