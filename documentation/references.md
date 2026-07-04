# Upstream References

These are the upstream references used for install and auth behavior.

## Codex CLI

- OpenAI Codex CLI setup: https://developers.openai.com/codex/cli
- OpenAI API key safety: https://help.openai.com/en/articles/5112595-best-practices-for-api-key-safety

When `--install-agent-clis` is used, Codex is installed with `curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh` as the admin user. The same command is rerun by `vps-agent-cli-update.timer` every two days. Post-setup auth uses `codex login` through `vps-agent-auth`.

## Grok CLI

- Grok Build CLI: https://x.ai/cli
- Grok Build docs: https://docs.x.ai/build/overview
- xAI API docs: https://docs.x.ai/

When `--install-agent-clis` is used, Grok CLI is installed with xAI's official `curl -fsSL https://x.ai/cli/install.sh | bash` installer, run as the admin user so its files live under that user's `~/.grok` directory. `vps-agent-cli-update.timer` runs `grok update` every two days. Post-setup auth uses `grok login`; non-browser environments can set `XAI_API_KEY`. `vps-agent-auth` does not accept or store API keys.

## GitHub CLI

- GitHub CLI Linux install docs: https://github.com/cli/cli/blob/trunk/docs/install_linux.md
- `gh auth login`: https://cli.github.com/manual/gh_auth_login
- `gh` environment variables: https://cli.github.com/manual/gh_help_environment

When `--install-agent-clis` is used, GitHub CLI is installed from GitHub's signed apt or rpm repositories. Post-setup auth uses `gh auth login --hostname github.com --git-protocol ssh` through `vps-agent-auth`.
