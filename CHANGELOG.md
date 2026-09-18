# Changelog

## [Unreleased]

### Changed

- Renamed the project and CLI from `vps-bootstrap` to `vpsbuddy`.
- Helper binaries, timers, sudoers, SSH drop-in, and audit log now use the
  `vpsbuddy` prefix.
- Developer CLI failures are recorded without stopping SSH hardening; selected
  CLI update timers remain managed for retry.
- Tailnet confirmation accepts `y` as well as `yes`.
- Reruns retire installer-owned helper, sudoers, timer, update, and SSH files
  from the old `vps-bootstrap` name.
- The old generic `/usr/local/bin/agent` link is removed only when it points to
  the managed Grok binary.
- Trimmed public documentation to operator-useful material.
- OpenSSH over the Tailnet is the supported SSH path. Bootstrap disables
  Tailscale SSH before the operator login test.

### Added

- Guided bootstrap run directly on the VPS.
- Checkout-free `install.sh` download entrypoint.
- Prompts for admin user, public key, hostname, swap, web ports, developer CLIs,
  automatic OS updates, and sudo policy.
- Valid public-key detection from the current login account.
- Idempotent swap setup with an operator-chosen size.
- Root-owned helper audit records.
- SSH hardening disables root and password login after the admin Tailnet login
  is confirmed.

### Removed

- Workstation-side SSH and SCP orchestration.
- Host, login-user, identity, public-key-path, swap-size, web, CLI, sudo, and
  doctor command flags.
- The fixed admin name and `2G` swap defaults.
- Positioning docs (`comparison`, `roadmap`, `faq`) and the standalone threat
  model file.
- Retired Tailscale SSH choices from saved plans and dated installer research.
