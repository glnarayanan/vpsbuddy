# Testing

```bash
make check
```

ShellCheck is used when present. Otherwise lint falls back to `bash -n`.

## Covered Locally

- no hidden defaults for admin, swap, web, CLIs, or sudo
- guided dry-run input and summary output
- detection and fingerprinting of a valid SSH public key
- checkout-free installer download and execution
- generated server-script syntax and security-control order
- swap symlink refusal
- SSH validation before public SSH removal
- generated cleanup paths for old helpers, sudoers, timers, updates, links, and SSH files
- generated SSH rollback steps for migration validation failures
- developer CLI failure or opt-out clears the update timer
- safe shell quoting in the generated phase prelude

These tests do not change host files or run `sshd` and systemd failure paths.
Before release, run the guided installer and rename migration on disposable VPS
hosts as described in [release-process.md](release-process.md).
