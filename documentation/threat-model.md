# Threat Model

This model covers the guided script once it starts on a fresh VPS.

## In Scope

- interactive configuration on the VPS
- admin user and authorized key setup
- swap setup
- Tailscale install and join
- SSH daemon hardening
- UFW or firewalld rules
- scoped sudo helpers and audit records
- optional developer CLIs and update timers

## Out of Scope

- the provider account and console
- the first SSH connection to the VPS
- storage of the operator's private key
- application deployment
- Tailnet account and ACL administration
- formal compliance baselines
- flaws in the base image or upstream packages

## Assets

- root access during setup
- the admin user's SSH access
- the installed public key
- Tailnet access
- SSH, sudo, swap, timer, and firewall state
- developer CLI auth created after setup
- `/var/log/vps-agent-actions.log`

## Trust Boundaries

- operator terminal input to the root bootstrap process
- VPS to OS package repositories
- VPS to Tailscale
- VPS to official developer CLI install and update endpoints
- host firewall to provider firewall
- admin user to root-owned helpers

## Main Threats

| Threat                     | Control                                                                          |
| -------------------------- | -------------------------------------------------------------------------------- |
| Operator lockout           | Keep public SSH open until local sudo and manual Tailnet login checks pass.      |
| Public SSH remains open    | Remove the public TCP 22 rule in harden after SSH config validation.             |
| Invalid SSH key            | Validate the selected or pasted public key and show its fingerprint.             |
| Broad sudo by accident     | Ask for the policy and use scoped root-owned helpers unless full sudo is chosen. |
| Swap path abuse            | Reject a symlink and do not overwrite an unusable `/swapfile`.                   |
| Secret collection          | Accept public keys only; defer developer CLI auth until after setup.             |
| Weak audit trail           | Write helper, user, action, arguments, time, and exit code to JSONL.             |
| Package drift              | Offer OS and developer CLI update timers as explicit choices.                    |
| Provider firewall mismatch | Require a separate provider firewall check.                                      |

## Residual Risk

- The operator can approve the wrong public key or Tailnet target.
- Mutable package and CLI endpoints can be compromised.
- Provider firewall and Tailnet ACL errors can still block or expose access.
- A lost root session before Tailnet verification may require provider-console
  recovery.
- Supported provider images can differ from their base distribution.

## Review Questions

- Can any failure close public SSH before the Tailnet test?
- Does SSH config validation still happen before the public firewall rule is
  removed?
- Does the change broaden sudo?
- Does it accept, print, or store a private key or token?
- Are all new operator choices prompted and shown before mutation?
- Do reruns preserve valid state without hiding a failed step?
- Does provider firewall guidance still match the host rules?
