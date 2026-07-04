# Security Policy

`vps-bootstrap` changes SSH, sudo, firewall, package update, and developer CLI
state on fresh VPS hosts. Please report security issues privately first so users
are not given unsafe operational guidance before a fix is available.

## Supported Versions

| Version           | Status                                                        |
| ----------------- | ------------------------------------------------------------- |
| `v0.1.0-alpha`    | Security reports accepted. Breaking changes may still occur.  |
| Unreleased `main` | Security reports accepted. Use with review and smoke testing. |

## Report a Vulnerability

Open a private security advisory in the GitHub repository if available. If
private advisories are unavailable, contact the maintainer through a private
channel before opening a public issue.

Include:

- A concise description of the issue and affected phase.
- The OS image, provider, and package manager path involved.
- The command or generated script path that demonstrates the issue.
- Whether the issue can cause lockout, public SSH exposure, privilege escalation,
  credential disclosure, or supply-chain compromise.
- Any safe reproduction steps that do not expose real hosts or secrets.

Do not include private keys, API tokens, Tailscale auth material, server
passwords, provider credentials, or full public IP inventory.

## Scope

In scope:

- Accidental lockout paths caused by the phased bootstrap flow.
- SSH hardening defects that leave root/password SSH exposed after success.
- Firewall defects that expose more than the documented final state.
- Sudo helper policy defects that grant broader passwordless root access than
  documented.
- Token, API key, or private key handling defects.
- Unsafe installer, update, or release guidance.

Out of scope:

- Vulnerabilities in upstream services or CLIs such as Tailscale, Codex CLI,
  Grok CLI, GitHub CLI, apt, dnf, yum, UFW, firewalld, or OpenSSH.
- Misconfigured applications deployed after the bootstrap completes.
- Provider firewall behavior outside this repository's documented assumptions.
- Reports that require attacking a third-party VPS or Tailnet without
  authorization.

## Disclosure Expectations

The maintainer will aim to acknowledge valid reports promptly, triage severity,
prepare a fix, and document release notes. Alpha releases do not yet have a
formal SLA.

Public disclosure should wait until a fix or mitigation is available, unless the
issue is already being actively exploited or is already public.

## Security Model

Read:

- [documentation/security-model.md](documentation/security-model.md)
- [documentation/threat-model.md](documentation/threat-model.md)
- [documentation/provider-firewall-checklist.md](documentation/provider-firewall-checklist.md)
