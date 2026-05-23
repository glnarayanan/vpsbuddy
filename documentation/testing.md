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
- Dry-run phase ordering that verifies Tailnet login before hardening.
- Parsing the prepare phase Tailnet IP from remote output.
- Safe SSH include placement when a distro image lacks `/etc/ssh/sshd_config.d` support in the main config.

Tests must not connect to or mutate a real server. Use dry-run output, fixtures, and generated script inspection for local verification.
