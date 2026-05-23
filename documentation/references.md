# Upstream References

These are the upstream references used for install and auth behavior.

## Codex CLI

- OpenAI Codex CLI setup: https://developers.openai.com/codex/cli
- OpenAI API key safety: https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety

Codex is installed with `npm i -g @openai/codex`. Post-setup auth uses `codex login --device-auth` through `vps-agent-auth`.

## Claude Code CLI

- Claude Code setup: https://code.claude.com/docs/en/setup
- Claude Code authentication: https://code.claude.com/docs/en/iam
- Claude Code settings and env vars: https://code.claude.com/docs/en/settings

Claude Code is installed from Anthropic's signed apt or rpm repositories. Post-setup auth uses `claude auth login` through `vps-agent-auth`.

## GitHub CLI

- GitHub CLI Linux install docs: https://github.com/cli/cli/blob/trunk/docs/install_linux.md
- `gh auth login`: https://cli.github.com/manual/gh_auth_login
- `gh` environment variables: https://cli.github.com/manual/gh_help_environment

GitHub CLI is installed from GitHub's signed apt or rpm repositories. Post-setup auth uses `gh auth login --hostname github.com --git-protocol ssh` through `vps-agent-auth`.
