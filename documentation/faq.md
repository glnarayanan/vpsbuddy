# FAQ

## Where do I run it?

Log into the VPS first, then run the installer there:

```bash
curl -fsSL https://raw.githubusercontent.com/glnarayanan/server-setup-scripts/main/install.sh | bash
```

The laptop only makes the first SSH connection and the later Tailnet login
test. It does not run the bootstrap.

## Does the VPS need a checkout or GitHub CLI?

No. `install.sh` downloads the entrypoint, library, and two templates into a
temporary directory, runs them, and removes them.

## What if the provider only allows key login as root?

Log in with that key as usual. When root's `authorized_keys` contains a valid
key, the guided setup shows its fingerprint and asks whether to reuse it for the
new admin user. You can reject it and paste another public key.

The script never needs the private key.

## Does it set up swap?

Yes, when you ask it to. If no active swap exists, enter a size such as `4G` or
enter `none`. There is no default size. Active swap is left unchanged.

## Why does public SSH stay open during prepare?

The new admin user and Tailnet path must work first. After prepare, the script
checks scoped sudo locally and waits while you test the printed Tailnet SSH
command from another terminal.

## Do I need to do anything after the Tailnet test?

Yes. Return to the first terminal and type `yes`. Only then does the script
harden SSH and remove public TCP 22.

## What if I do not type yes?

The script states that setup is paused and leaves public SSH open. Rerun it
later. Prepare is designed to reuse valid state.

## How do reruns work?

Each run asks for the configuration again. Existing users, keys, swap,
Tailscale state, helper files, timers, SSH config, and firewall rules are
checked or set to the chosen state.

Use `--dry-run` before applying a newer script to a server that has changed.

## Are Codex, Grok, and GitHub CLI installed?

Only when you answer yes. If a selected CLI fails to install, prepare stops
while public SSH stays open. Fix the cause or rerun and answer no. Authenticate
after setup with `vps-agent-auth`.

## Does bootstrap store tokens?

No. It does not ask for API keys, CLI tokens, GitHub private keys, or SSH
private keys.

## What does scoped sudo allow?

It allows passwordless use of the root-owned `vps-agent-*` helpers. Choose full
passwordless sudo only when the server needs `NOPASSWD:ALL`.

## Are ports 80 and 443 open?

Only when you answer yes. Provider firewall rules must be changed separately.

## Does Tailscale SSH replace OpenSSH?

OpenSSH over the Tailnet is the base path. Tailscale SSH is optional. Select it
only when the Tailnet SSH ACL rules are ready.

## Can I run this on an existing production server?

That is not the intended alpha use. The script rewrites SSH, sudo, firewall,
timer, and helper state. Use a fresh VPS or audit the code and dry-run output
against the server's current state first.
