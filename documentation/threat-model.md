# Threat Model

This document describes the public threat model for `vps-bootstrap` as of the
`v0.1.0-alpha` positioning.

## Scope

In scope:

- The local `bin/vps-bootstrap` CLI.
- Generated remote shell executed on a fresh VPS.
- SSH host-key pinning for the first connection.
- Admin user creation and SSH key installation.
- Tailscale installation and Tailnet verification.
- SSH daemon hardening.
- Host firewall configuration.
- Bounded sudo helper installation.
- Optional agent CLI and OS update timers.
- Helper audit logging.
- Post-setup `vps-agent-auth` guidance when agent CLIs are installed.

Out of scope:

- Applications deployed after bootstrap.
- Provider console account security.
- Tailscale account and ACL administration beyond documented assumptions.
- Vulnerabilities in upstream package managers, OpenSSH, Tailscale, Codex CLI,
  Grok CLI, GitHub CLI, UFW, or firewalld.
- General-purpose server compliance hardening.

## Assets

- Root access to the fresh VPS during bootstrap.
- The new admin user's SSH access.
- Local SSH private keys on the operator workstation.
- Server SSH host identity.
- Tailnet access to the host.
- Final SSH and firewall posture.
- Sudo helper policy.
- `/var/log/vps-agent-actions.log` helper audit trail.
- Developer CLI auth state created after bootstrap.

## Trust Boundaries

- Operator workstation to public initial SSH as `--login-user`.
- Operator workstation to Tailnet SSH after Tailscale joins.
- VPS to OS package repositories.
- VPS to Tailscale coordination and DERP infrastructure.
- VPS to official Codex, Grok, and GitHub CLI installer/update endpoints.
- Host firewall to provider firewall.
- Root-owned helper commands to user-level agent CLIs.

## Attacker Assumptions

The model assumes attackers may:

- Observe or interfere with public-network SSH if host identity is not pinned.
- Attempt password SSH against public TCP 22 before hardening.
- Exploit loose provider firewall rules.
- Abuse overly broad passwordless sudo if granted.
- Seek leaked API keys, private keys, or CLI auth material.
- Compromise mutable upstream installer endpoints or transport paths.

The model does not assume the bootstrap can defend against a compromised VPS
provider account, a malicious base OS image, a compromised operator workstation,
or a compromised Tailnet administrator.

## Primary Threats and Mitigations

| Threat                                     | Mitigation                                                                                                                                                                      |
| ------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| First-connection SSH impersonation         | Pin a provider-supplied host key when available; otherwise scan the live host key, require explicit fingerprint confirmation, and use strict host-key checking afterward.       |
| Operator lockout during hardening          | Keep the original public password SSH path open until Tailnet admin SSH and sudo verification succeed.                                                                          |
| Public SSH remains exposed after success   | Harden SSH only after verification and remove public SSH from UFW or firewalld.                                                                                                 |
| Provider firewall keeps TCP 22 exposed     | Document provider firewall rules and require independent verification from a non-Tailnet network.                                                                               |
| Admin user receives excessive default sudo | Default to passwordless sudo only for root-owned `vps-agent-*` helpers.                                                                                                         |
| Agent CLIs obtain direct root primitives   | User-level Codex and Grok binaries are not directly sudo-allowed by the default policy.                                                                                         |
| Agent/helper misuse is hard to reconstruct | Root-owned helpers write best-effort JSONL audit events with helper, user, action, sanitized args, and exit code.                                                               |
| Raw secrets are collected during bootstrap | Bootstrap does not accept, upload, or store raw agent CLI tokens, API keys, GitHub private keys, or local SSH private keys.                                                     |
| Mutable installer supply-chain risk        | Agent CLIs are opt-in; trust boundary is documented; installers run as the admin user where possible; installed CLIs do not receive direct passwordless root access by default. |
| OS packages fall behind after setup        | A systemd OS update timer runs every two weeks.                                                                                                                                 |

## Residual Risks

- Official mutable installer endpoints for Codex, Grok, Tailscale, and package
  repositories remain supply-chain dependencies.
- Provider firewalls vary and must be configured outside the host.
- Tailscale ACLs are managed outside this repository.
- A failed or interrupted bootstrap may require provider-console repair.
- Alpha compatibility is based on documented support paths and smoke tests, not
  exhaustive provider coverage.

## Security Review Checklist

For behavior changes, reviewers should ask:

- Does this change affect the prepare, verify, or harden phase?
- Could a failure leave public SSH open longer than documented?
- Could a failure lock out the operator?
- Does the default sudo policy become broader?
- Are secrets accepted, printed, uploaded, or stored?
- Does dry-run output still make the plan inspectable?
- Does `doctor` still report the relevant local or post-bootstrap state?
- Does helper audit logging still preserve the helper's real exit code?
- Does the provider firewall guidance need updating?
