# Changelog

This project follows a lightweight changelog format while it is in alpha.
Release entries should describe operator-visible changes, security posture
changes, compatibility changes, and smoke-test notes.

## [Unreleased]

### Added

- Public repository documentation and community hygiene files.
- Alpha roadmap, public threat model, compatibility matrix, release process,
  comparison guide, and FAQ.
- Read-only `vps-bootstrap doctor` audit mode.
- Best-effort JSONL audit logging for root-owned `vps-agent-*` helper calls.
- Idempotent swap setup with a configurable default `2G` `/swapfile`.
- Key-based initial SSH login through the optional `--login-identity` path.

### Changed

- Root documentation now positions the project as a security-first fresh VPS
  bootstrap tool rather than a hosting panel or application orchestrator.
- Developer CLI installation is opt-in through `--install-agent-clis`.
- `vps-agent-auth` generation now uses a shared template instead of duplicated
  heredocs.
- `documentation/README.md` is now an advanced usage reference instead of a
  duplicate project overview.
- Interactive prompts now use the controlling terminal, and failed Tailnet
  admin verification reports that hardening was skipped.
- A completed prepare response is now parsed before a non-zero SSH session
  status can stop the local verification and hardening phases.
- The local handoff now requires the remote prepare-complete marker before it
  can continue to Tailnet verification.

### Removed

- Unused Node.js runtime installer helper.
- Premature CI/release hygiene issue template.

## [0.1.0-alpha] - Planned

Initial alpha release target.

Expected scope:

- Fresh VPS bootstrap from temporary root/provider SSH to Tailnet-first admin
  access.
- Host-key pinning from provider-console SSH host public keys.
- Non-root admin user creation with local SSH key installation.
- Tailscale install and interactive join.
- Verification before SSH hardening.
- Public SSH removal after Tailnet verification.
- Public HTTP/HTTPS allowed by default, with `--no-web` for private-only hosts.
- Bounded passwordless sudo helpers by default, with `--full-sudo` as an
  explicit escape hatch.
- Optional Codex CLI, Grok CLI, and GitHub CLI installation with
  `--install-agent-clis`.
- OS update timer by default; agent CLI update timer only when agent CLIs are
  installed.
- Swap setup by default when no active swap exists, with `--swap-size` and
  `--no-swap` controls.
- Read-only doctor audit.
- Helper audit events under `/var/log/vps-agent-actions.log`.
- Local shell lint and generated-script test coverage.

Release readiness is tracked in
[documentation/release-process.md](documentation/release-process.md).
