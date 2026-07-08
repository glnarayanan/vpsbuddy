# Agent Notes

This repository contains a Bash CLI for securely bootstrapping fresh VPS hosts.
The initial SSH login user is distinct from the managed admin user; see `--login-user` vs `--user`.

Keep this file lean. Load the detailed project docs in `documentation/` when changing behavior:

- `documentation/README.md` for advanced usage and operator notes.
- `documentation/security-model.md` for the phased hardening model.
- `documentation/threat-model.md` for assets, trust boundaries, threats, and non-goals.
- `documentation/compatibility-matrix.md` for supported fresh VPS targets and smoke-test expectations.
- `documentation/release-process.md` for release and disposable VPS smoke-test guidance.
- `documentation/roadmap.md`, `documentation/comparison.md`, and `documentation/faq.md` for public positioning.
- `documentation/provider-firewall-checklist.md` for provider firewall expectations.
- `documentation/testing.md` for local checks and test strategy.
- `documentation/references.md` for upstream install/auth references used by the script.
