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
- developer CLI failure stops prepare before update timers
- safe shell quoting in the generated phase prelude

These tests do not change a host. Before release, run the guided installer on a
disposable VPS and follow [release-process.md](release-process.md).
