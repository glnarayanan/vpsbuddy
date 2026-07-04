# Roadmap

`vps-bootstrap` is currently positioned for `v0.1.0-alpha`: a security-first
fresh VPS bootstrap tool that prepares the server beneath an application stack.

The roadmap favors hardening, recovery, compatibility, and release confidence
over hosting-panel features.

## v0.1.0-alpha

Goal: publish a reviewable alpha that operators can test on disposable fresh VPS
instances.

Required before tagging:

- Local `make check` passes.
- Dry-run output is understandable for the main bootstrap path.
- `doctor` provides a read-only local and post-bootstrap audit surface.
- Agent CLIs are opt-in and documented as a supply-chain trust boundary.
- Root-owned helpers emit JSONL audit events without broadening sudo.
- Release smoke test is documented and run on at least one fresh apt-family VPS.
- Security model, threat model, compatibility matrix, and provider firewall
  checklist are current.
- Changelog describes operator-visible behavior and known alpha limits.

Expected alpha limits:

- No web UI.
- No app deployment orchestration beyond bounded helper primitives.
- No built-in certificate automation.
- No migration support for existing customized servers.
- No guarantee that every provider image has been smoke-tested.

## Near-Term Candidates

- Broaden disposable VPS smoke tests across Debian, Ubuntu, Fedora, AlmaLinux,
  and Rocky Linux images.
- Add clearer dry-run and doctor summaries for final firewall and sudo policy.
- Add generated-script tests for additional distro edge cases.
- Document provider-specific host-key retrieval notes where providers expose
  them differently.
- Improve troubleshooting docs for failed Tailscale joins, SSH include support,
  UFW/firewalld differences, and package repository failures.
- Add release artifact verification notes if distribution expands beyond source
  tags.

## Deliberate Non-Goals

- Replacing Dokploy, Coolify, CapRover, or other hosting panels.
- Managing containers, domains, TLS certificates, databases, queues, or app
  rollbacks.
- Providing an always-running control plane on the VPS.
- Accepting or storing developer CLI tokens during bootstrap.
- Supporting in-place hardening of long-lived servers as the default path.

## Decision Standard

A roadmap item should make the fresh-server security baseline more reliable,
more inspectable, or easier to verify. If a feature mainly belongs to the
application platform layer, it should remain outside this repository unless the
project scope is intentionally changed.
