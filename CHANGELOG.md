# Changelog

This project follows a lightweight changelog format while it is in alpha.
Release entries should describe operator-visible changes, security posture
changes, compatibility changes, and smoke-test notes.

## [Unreleased]

### Added

- Public repository documentation and community hygiene files.
- Alpha roadmap, public threat model, compatibility matrix, release process,
  comparison guide, and FAQ.

### Changed

- Root documentation now positions the project as a security-first fresh VPS
  bootstrap tool rather than a hosting panel or application orchestrator.

## [0.1.0-alpha] - Planned

Initial alpha release target.

Expected scope:

- Fresh VPS bootstrap from temporary root/password SSH to Tailnet-first admin
  access.
- Host-key pinning from provider-console SSH host public keys.
- Non-root admin user creation with local SSH key installation.
- Tailscale install and interactive join.
- Verification before SSH hardening.
- Public SSH removal after Tailnet verification.
- Public HTTP/HTTPS allowed by default, with `--no-web` for private-only hosts.
- Bounded passwordless sudo helpers by default, with `--full-sudo` as an
  explicit escape hatch.
- Codex CLI, Grok CLI, and GitHub CLI installation.
- Agent CLI and OS update timers.
- Local shell lint and generated-script test coverage.

Release readiness is tracked in
[documentation/release-process.md](documentation/release-process.md).
