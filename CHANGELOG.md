# Changelog

## [Unreleased]

### Added

- Guided bootstrap run directly on the VPS.
- Checkout-free `install.sh` download entrypoint.
- Prompts for admin user, public key, hostname, swap, web ports, developer CLIs,
  automatic OS updates, sudo policy, and Tailscale SSH.
- Valid public-key detection from the current login account.
- Idempotent swap setup with an operator-chosen size.
- Root-owned helper audit records.

### Changed

- Prepare now runs locally on the VPS and waits on the controlling terminal.
- Hardening runs only after the operator confirms a separate Tailnet admin login.
- The selected sudo policy applies during prepare; no temporary full-sudo handoff
  is needed.
- SSH config is written and checked before public SSH is removed from the host
  firewall.
- Developer CLI and OS update setup follow explicit prompts.

### Removed

- Workstation-side SSH and SCP orchestration.
- Host, login-user, identity, public-key-path, swap-size, web, CLI, sudo, and
  doctor command flags.
- The fixed admin name and `2G` swap defaults.

## [0.1.0-alpha] - Planned

Initial alpha release target.
