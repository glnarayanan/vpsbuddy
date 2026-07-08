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

The scheduled OpenSSF Scorecard workflow pins `ossf/scorecard-action` to a concrete upstream release tag. If GitHub cannot resolve that tag, update it to the current upstream release instead of using a missing floating major tag.

Because this repository is private, the Scorecard job also needs job-level read permissions for checks, issues, and pull requests. Without those reads, Scorecard can fail during commit or SAST discovery with `Resource not accessible by integration`.

Do not add `github/codeql-action/upload-sarif` to the Scorecard workflow unless code scanning is enabled for the repository. Without code scanning, the Scorecard run can succeed and then fail during SARIF upload.

To match CI locally on macOS:

```bash
brew install shellcheck shfmt
npm install -g prettier@3.3.3
```

## Test Coverage

The tests cover:

- CLI argument parsing and defaults.
- Opt-in developer CLI installation defaults.
- Public/private key path handling.
- SSH hardening snippet generation.
- UFW and firewalld command generation.
- Remote script support for apt, dnf, yum, Tailscale install, interactive `tailscale up`, and `sshd -t`.
- Developer CLI install generation for Codex CLI, Grok CLI, and GitHub CLI.
- Agent CLI helper generation for native auth commands plus Grok `XAI_API_KEY` status handling.
- Agent CLI update timer generation for two-day Codex installer reruns and `grok update`.
- OS update timer generation for two-week unattended apt/dnf/yum package updates.
- Dry-run phase ordering that verifies Tailnet login before hardening.
- Read-only `doctor` output for local inputs, provider firewall reminders, VPS state checks, and exposed port observations.
- Streamed remote config generation so public keys with spaces and empty optional values survive SSH execution.
- Scoped sudo policy generation and the `--full-sudo` escape hatch.
- Best-effort JSONL audit logging inserted into root-owned helper scripts.
- Parsing the prepare phase Tailnet IP from remote output.
- Safe SSH include placement when a distro image lacks `/etc/ssh/sshd_config.d` support in the main config.

Tests must not connect to or mutate a real server. Use dry-run output, fixtures, and generated script inspection for local verification.
