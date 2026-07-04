# Contributing

Thanks for helping improve `vps-bootstrap`. This project is early alpha and
security-sensitive, so changes should stay narrow, testable, and explicit about
their operational impact.

## Project Positioning

The project prepares fresh VPS hosts for secure operations. It is not trying to
be a Dokploy, Coolify, CapRover, PaaS, or server control panel clone.

Good contributions improve:

- Fresh-server bootstrap reliability.
- Lockout prevention.
- SSH, sudo, firewall, and update safety.
- Provider and distro compatibility.
- Release and smoke-test clarity.
- Documentation that helps operators understand the security posture.

Avoid broad feature work that turns this into an app orchestrator, certificate
manager, container platform, or web dashboard without prior discussion.

## Development Workflow

1. Read [documentation/README.md](documentation/README.md) and
   [documentation/security-model.md](documentation/security-model.md).
2. Keep changes small and explain the affected bootstrap phase.
3. Add or update tests for behavior changes.
4. Update relevant documentation in `documentation/`.
5. Run the local checks before opening a pull request:

```bash
make check
```

If ShellCheck is unavailable, `make lint` falls back to `bash -n` syntax checks.

## Pull Request Checklist

- The change is scoped to a clear problem.
- The final host state is documented when behavior changes.
- Lockout and rollback implications are considered.
- Tests cover generated commands, dry-run output, or helper behavior where
  practical.
- `make check` passes locally, or any failure is explained.
- New user-facing behavior is reflected in `documentation/`.
- No secrets, private keys, real provider credentials, or real server passwords
  are committed.

## Security Changes

For security-sensitive changes, include:

- The affected asset or trust boundary.
- The failure mode being fixed.
- The expected before/after behavior.
- Smoke-test guidance for a disposable fresh VPS when local tests are not
  enough.

Report vulnerabilities privately through [SECURITY.md](SECURITY.md) rather than
opening a public issue first.

## Coding Style

- Bash should stay readable, defensive, and explicit.
- Prefer generated-script tests over real-server mutation for local coverage.
- Use meaningful names for phase-specific behavior.
- Avoid unrelated formatting churn.
- Keep Markdown docs under `documentation/` unless the file is a standard public
  repository file such as `README.md`, `SECURITY.md`, or `CONTRIBUTING.md`.

## License

By contributing, you agree that your contribution is licensed under the Apache
License 2.0.
