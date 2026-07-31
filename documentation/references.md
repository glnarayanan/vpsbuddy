# Upstream References

## Codex CLI

- https://developers.openai.com/codex/cli
- Install: `curl -fsSL https://chatgpt.com/codex/install.sh | sh`
- vpsbuddy downloads that installer with bounded retries and a two-minute
  download limit, then runs it with `CODEX_NON_INTERACTIVE=1` inside the shared
  15-minute optional-installer deadline
- Auth: `codex login` via `vpsbuddy-auth`

## Grok CLI

- https://x.ai/cli
- https://docs.x.ai/build/overview
- Install: `curl -fsSL https://x.ai/cli/install.sh | bash`
- Auth: `grok login`, or `XAI_API_KEY` in non-browser environments

## GitHub CLI

- https://github.com/cli/cli/blob/trunk/docs/install_linux.md
- https://cli.github.com/manual/gh_auth_login
- Install: official apt/rpm repositories
- Auth: `gh auth login --hostname github.com --git-protocol ssh`

## Pi

- https://pi.dev/docs/latest/quickstart
- https://github.com/badlogic/pi-mono/blob/main/packages/coding-agent/README.md
- Install: `curl -fsSL https://pi.dev/install.sh | sh`
- Update: `pi update --self`
- Auth: run `pi`, then use `/login`

## OpenCode

- https://opencode.ai/docs/cli/
- https://opencode.ai/docs/providers
- Install: `curl -fsSL https://opencode.ai/install | bash`
- Update: `opencode upgrade`
- Auth: `opencode auth login` and `opencode auth list`

## Amp

- https://ampcode.com/manual
- Install: `curl -fsSL https://ampcode.com/install.sh | bash`
- Update: `amp update`
- Auth: `amp login`

## Factory Droid

- https://docs.factory.ai/cli/getting-started/quickstart
- https://docs.factory.ai/reference/cli-reference
- Install: `curl -fsSL https://app.factory.ai/cli | sh`
- Update: `droid update`
- Auth: run `droid`, then use `/login`

## Claude Code

- https://code.claude.com/docs/en/installation
- https://code.claude.com/docs/en/authentication
- Install: `curl -fsSL https://claude.ai/install.sh | bash`
- Update: `claude update`
- Auth: `claude auth login` and `claude auth status`
