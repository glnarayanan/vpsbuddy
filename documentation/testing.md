# Testing

This project uses a lightweight Bash test harness so tests can run without mutating a real VPS.

Run the full local check:

```bash
make check
```

Run tests only:

```bash
make test
```

Run linting only:

```bash
make lint
```

`make lint` uses ShellCheck when it is installed. If ShellCheck is unavailable, it falls back to `bash -n` syntax checks.

## Test Coverage

The tests cover:

- CLI argument parsing and defaults.
- Public/private key path handling.
- SSH hardening snippet generation.
- UFW and firewalld command generation.
- Remote script support for apt, dnf, yum, Tailscale install, interactive `tailscale up`, and `sshd -t`.
- Developer CLI install generation for Codex CLI, Grok CLI, and GitHub CLI.
- Agent CLI helper generation for native auth commands plus Grok `XAI_API_KEY` status handling.
- Agent CLI update timer generation for two-day Codex installer reruns and `grok update`.
- OS update timer generation for two-week unattended apt/dnf/yum package updates.
- Dry-run phase ordering that verifies Tailnet login before hardening.
- Streamed remote config generation so public keys with spaces and empty optional values survive SSH execution.
- Scoped sudo policy generation and the `--full-sudo` escape hatch.
- Parsing the prepare phase Tailnet IP from remote output.
- Safe SSH include placement when a distro image lacks `/etc/ssh/sshd_config.d` support in the main config.

Tests must not connect to or mutate a real server. Use dry-run output, fixtures, and generated script inspection for local verification.
