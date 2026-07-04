#!/usr/bin/env bash
set -Eeuo pipefail

usage() {
  cat <<'USAGE'
Usage:
  vps-agent-auth [--all] [--status] [--codex] [--grok] [--github]

Runs native interactive authentication where available and prints setup checks
for CLIs that use API-key based configuration. No tokens are accepted, copied,
or stored by this helper.
USAGE
}

have() {
  command -v "$1" >/dev/null 2>&1
}

status_codex() {
  have codex && codex login status
}

grok_command() {
  if command -v grok >/dev/null 2>&1; then
    command -v grok
    return 0
  fi

  if [[ -x "${HOME}/.grok/bin/grok" ]]; then
    printf '%s\n' "${HOME}/.grok/bin/grok"
    return 0
  fi

  return 1
}

status_grok() {
  local grok_bin

  if ! grok_bin="$(grok_command)"; then
    printf 'grok is not installed\n' >&2
    return 1
  fi

  "$grok_bin" --version
  if [[ -n "${XAI_API_KEY:-}" ]]; then
    printf 'XAI_API_KEY is set in this shell.\n'
    return 0
  fi

  if [[ -r "${HOME}/.grok/auth.json" ]]; then
    printf '~/.grok/auth.json exists from Grok login.\n'
    return 0
  fi

  printf 'Grok is not authenticated. Run grok login, or set XAI_API_KEY in non-browser environments.\n' >&2
  return 1
}

status_github() {
  have gh && gh auth status --hostname github.com
}

auth_codex() {
  if ! have codex; then
    printf 'codex is not installed\n' >&2
    return 1
  fi

  codex login
}

auth_grok() {
  local grok_bin

  if ! grok_bin="$(grok_command)"; then
    printf 'grok is not installed\n' >&2
    return 1
  fi

  if [[ -n "${XAI_API_KEY:-}" ]]; then
    printf 'XAI_API_KEY is already set; Grok will use API-key auth in this shell.\n'
    return 0
  fi

  "$grok_bin" login
}

auth_github() {
  if ! have gh; then
    printf 'gh is not installed\n' >&2
    return 1
  fi

  gh auth login --hostname github.com --git-protocol ssh
}

run_status() {
  printf '\n== Codex ==\n'
  status_codex || true
  printf '\n== Grok CLI ==\n'
  status_grok || true
  printf '\n== GitHub CLI ==\n'
  status_github || true
}

run_all() {
  auth_codex
  auth_grok
  auth_github
}

if [[ "$#" -eq 0 ]]; then
  run_all
  exit 0
fi

while [[ "$#" -gt 0 ]]; do
  case "$1" in
    --all)
      run_all
      ;;
    --status)
      run_status
      ;;
    --codex)
      auth_codex
      ;;
    --grok)
      auth_grok
      ;;
    --github)
      auth_github
      ;;
    -h | --help)
      usage
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
  shift
done
