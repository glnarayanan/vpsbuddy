# Testing

Run all local checks:

```bash
make check
```

Run only the Bash tests:

```bash
make test
```

Run only lint:

```bash
make lint
```

ShellCheck is used when present. Otherwise lint falls back to `bash -n`.

## Covered Locally

The test harness checks:

- no hidden defaults for admin, swap, web, CLIs, or sudo
- guided dry-run input and summary output
- detection and fingerprinting of a valid SSH public key
- removal of the old SSH and SCP orchestrator
- checkout-free installer file downloads
- generated server-script syntax
- swap symlink refusal
- prepare firewall behavior
- SSH config and sudo policy generation
- SSH validation before public SSH removal
- developer CLI and automatic update choices
- safe shell quoting in the generated phase prelude

These tests do not change a host.

## Disposable VPS Check

Local tests cannot prove package, service, Tailscale, SSH, or firewall behavior
on a provider image. Before release, run the guided installer on a disposable
VPS and follow [release-process.md](release-process.md).

Keep the provider console open. Verify both the Tailnet login and the final
public port state from separate terminals.
