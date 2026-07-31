# Changelog

## [Unreleased]

### Changed

- Renamed the project and CLI from `vps-bootstrap` to `vpsbuddy`.
- Helper binaries, timers, sudoers, SSH drop-in, and audit log now use the
  `vpsbuddy` prefix.
- Developer CLI update timers install only after all selected CLIs succeed.
- Tailnet confirmation accepts `y` as well as `yes`.
- Reruns retire installer-owned helper, sudoers, timer, update, and SSH files
  from the old `vps-bootstrap` name.
- The old generic `/usr/local/bin/agent` link is removed only when it points to
  the managed Grok binary.
- Trimmed public documentation to operator-useful material.

### Added

- Guided bootstrap run directly on the VPS.
- Checkout-free `install.sh` download entrypoint.
- Prompts for admin user, public key, hostname, swap, web ports, developer CLIs,
  automatic OS updates, sudo policy, and Tailscale SSH.
- Valid public-key detection from the current login account.
- Idempotent swap setup with an operator-chosen size.
- Root-owned helper audit records.

### Removed

- Workstation-side SSH and SCP orchestration.
- Host, login-user, identity, public-key-path, swap-size, web, CLI, sudo, and
  doctor command flags.
- The fixed admin name and `2G` swap defaults.
- Positioning docs (`comparison`, `roadmap`, `faq`) and the standalone threat
  model file.

## [0.1.0-alpha] - Planned

Initial alpha release target.
