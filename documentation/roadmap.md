# Roadmap

The alpha goal is a guided, reviewable fresh VPS bootstrap that does not lock
the operator out.

## v0.1.0-alpha

- guided on-VPS setup
- checkout-free installer
- explicit key, swap, web, CLI, update, sudo, and Tailscale SSH choices
- prepare and harden phases with a manual Tailnet checkpoint
- scoped root-owned helpers and audit events
- apt, dnf, and yum paths
- disposable Ubuntu smoke test
- current security, threat, compatibility, and release docs

## Near-Term

- smoke tests for Debian, Fedora, AlmaLinux, and Rocky Linux
- clearer errors for Tailscale, package, SSH include, UFW, and firewalld faults
- more generated-script tests for distro edge cases
- release artifact checks if distribution grows beyond source files

## Non-Goals

- app or container management
- TLS and domain setup
- an always-running control plane
- storage of developer tokens
- in-place management of long-lived custom servers
- broad fleet management
