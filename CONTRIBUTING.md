# Contributing

Thanks for helping improve `vpsbuddy`. This project is early alpha and
security-sensitive, so changes should stay narrow, testable, and explicit about
their operational impact.

Good contributions improve fresh-server bootstrap reliability, lockout
prevention, SSH/sudo/firewall/update safety, distro compatibility, and operator
documentation. Avoid turning this into an app orchestrator, certificate manager,
container platform, or web dashboard without prior discussion.

## Development Workflow

1. Read [documentation/README.md](documentation/README.md) and
   [documentation/security-model.md](documentation/security-model.md).
2. Keep changes small and explain the affected bootstrap phase.
3. Add or update tests for behavior changes.
4. Update relevant documentation in `documentation/`.
5. Run `make check` before opening a pull request.

## Pull Request Checklist

- The change is scoped to a clear problem.
- The final host state is documented when behavior changes.
- Lockout and rollback implications are considered.
- Tests cover generated commands, dry-run output, or helper behavior where
  practical.
- `make check` passes locally, or any failure is explained.
- No secrets, private keys, real provider credentials, or real server passwords
  are committed.

## Security Changes

For security-sensitive changes, include the affected asset or trust boundary,
the failure mode being fixed, expected before/after behavior, and smoke-test
guidance for a disposable fresh VPS when local tests are not enough.

Report vulnerabilities privately through [SECURITY.md](SECURITY.md).

## Coding Style

- Bash should stay readable, defensive, and explicit.
- Prefer generated-script tests over real-server mutation for local coverage.
- Avoid unrelated formatting churn.

## License

By contributing, you agree that your contribution is licensed under the MIT License.
