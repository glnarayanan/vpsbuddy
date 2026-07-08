# Comparison

`vps-bootstrap` is a fresh-server security bootstrap. It prepares a VPS so you
can safely continue with your preferred deployment approach.

It is deliberately smaller than a hosting platform.

## What It Is

- A local Bash CLI run from your workstation.
- A phased hardening flow for fresh VPS hosts.
- A way to move SSH access from temporary public password login to
  Tailnet-first admin access.
- A baseline for firewall posture, bounded sudo helpers, update timers, and
  developer CLI installation.
- A tool that leaves application architecture decisions to the operator.

## What It Is Not

- Not a Dokploy or Coolify clone.
- Not a PaaS.
- Not a web dashboard.
- Not a container scheduler.
- Not a reverse proxy or certificate manager.
- Not a database, queue, or app rollback manager.
- Not a replacement for provider firewall configuration.
- Not a compliance hardening framework.

## Compared With Hosting Panels

| Area                       | `vps-bootstrap`               | Dokploy/Coolify-style panels   |
| -------------------------- | ----------------------------- | ------------------------------ |
| Primary job                | Secure the fresh VPS baseline | Deploy and manage applications |
| Interface                  | Local CLI                     | Web UI/control plane           |
| Runtime footprint          | No ongoing app control plane  | Long-running platform services |
| App deployment             | Outside scope                 | Core feature                   |
| TLS/domain routing         | Outside scope                 | Core feature                   |
| SSH hardening              | Core feature                  | Usually adjacent setup         |
| Tailnet-first SSH          | Core feature                  | Depends on user setup          |
| Provider firewall guidance | Documented expectation        | Usually external               |

These tools can be complementary. A common path is to run `vps-bootstrap` first,
verify the final SSH/firewall posture, then install a deployment platform if
that is the right application layer.

## Compared With Cloud-Init or Ansible

Cloud-init and Ansible are broader provisioning systems. `vps-bootstrap` is a
narrow operator workflow with built-in phase ordering for one risky transition:
moving a fresh VPS from public password SSH to verified Tailnet admin SSH
without locking yourself out.

Use cloud-init or Ansible when you need general fleet provisioning. Use
`vps-bootstrap` when you want this specific security-first first-server flow and
you want to inspect it locally before it touches a host.

## Compared With Manual Setup

Manual hardening gives maximum control, but it is easy to get the order wrong.
The project exists to make the safe order repeatable:

1. Pin the initial host identity.
2. Prepare the admin account and Tailnet access.
3. Verify the new path.
4. Harden SSH and firewall exposure.
5. Authenticate optional developer CLIs after the server is stable.
