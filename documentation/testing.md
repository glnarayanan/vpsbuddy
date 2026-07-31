# Testing

```bash
make check
```

ShellCheck is used when present. Otherwise lint falls back to `bash -n`.
`make check` also runs the repository's exact `shfmt` command when `shfmt` is
installed. CI runs the same command in its formatter job.

## Covered Locally

- no hidden defaults for admin, swap, web, CLIs, or sudo
- guided dry-run input and summary output
- CLI input in space-separated, comma-separated, mixed, `all`, and `none`
  forms, including blank, malformed, mixed-token, range, duplicate, and
  canonical-order cases
- detection and fingerprinting of a valid SSH public key
- checkout-free installer download and execution
- generated server-script syntax and security-control order
- swap symlink refusal
- SSH validation before public SSH removal
- generated cleanup paths for old helpers, sudoers, timers, updates, links, and SSH files
- generated SSH rollback steps for migration validation failures
- explicit `none` and missing CLI-selection state are distinguished
- selected-only installer dispatch executes all eight CLI branches and checks
  vendor commands and exact user-scoped binary paths
- GitHub CLI package setup rejects an unmanaged PATH binary, invalid key data,
  mixed or extra repository settings, and package installs that are not limited
  or pinned to the official source
- failed CLI reruns keep the prior auth helper and update timer
- Pi version and update commands use its private Node while system tools stay
  ahead of other user-writable CLI directories; managed CLI commands run by full
  path even when a system command has the same name
- every supported Codex and Amp command path is exercised
- Factory Droid alone installs `xdg-utils`
- successful reruns remove deselected managed links and state while retaining
  third-party binaries; unmanaged links remain untouched
- forced prepare installer failure stops before hardening starts
- no CLI update timer for `none` or GitHub CLI alone
- legacy CLI-link migration requires an old `vps-bootstrap` ownership record
- updater failures return a failure status
- safe shell quoting in the generated phase prelude

These tests do not change host files or run `sshd` and systemd failure paths.
Before release, run the guided installer and rename migration on disposable VPS
hosts as described in [release-process.md](release-process.md).
