# Comparison

`vps-bootstrap` is a guided Bash script run inside a fresh VPS. Its job is the
host baseline: admin access, Tailscale, SSH, firewall, swap, sudo helpers,
updates, and optional developer CLIs.

It is not:

- a hosting panel
- a container or app scheduler
- a certificate or domain manager
- a long-running control plane
- a fleet configuration system
- a compliance framework

## Hosting Panels

Dokploy and Coolify manage apps. `vps-bootstrap` prepares the host below that
layer. You can run it first, verify access and firewall state, then install a
panel.

## Cloud-Init and Ansible

Cloud-init and Ansible handle broad provisioning and fleets.
`vps-bootstrap` handles one guided fresh-server flow with a manual checkpoint
before public SSH closes.

## Manual Setup

Manual setup gives full control. This script makes the risky order repeatable:

1. collect explicit choices
2. prepare while public SSH stays open
3. test admin access over the Tailnet
4. harden SSH and firewall
5. authenticate selected developer CLIs
