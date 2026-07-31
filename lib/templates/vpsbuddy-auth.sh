#!/usr/bin/env bash
# VPSBUDDY_AUTH_BODY
set -Eeuo pipefail

selected_clis="${selected_clis:-}"

selected_cli() {
  local cli_id="$1"
  local selected_id

  for selected_id in $selected_clis; do
    [[ "$selected_id" == "$cli_id" ]] && return 0
  done
  return 1
}

require_selected() {
  local cli_id="$1"

  if ! selected_cli "$cli_id"; then
    printf '%s was not selected for management by vpsbuddy\n' "$cli_id" >&2
    return 1
  fi
}

usage() {
  cat << 'USAGE'
Usage:
  vpsbuddy-auth [--all] [--status] [--codex] [--grok] [--github] [--pi] [--opencode] [--amp] [--droid] [--claude]

Runs native interactive authentication where available and prints setup checks
for CLIs that use API-key based configuration. No tokens are accepted, copied,
or stored by this helper.
USAGE
}

have() {
  command -v "$1" > /dev/null 2>&1
}

status_codex() {
  require_selected codex || return 1
  have codex && codex login status
}

grok_command() {
  if command -v grok > /dev/null 2>&1; then
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
  require_selected grok || return 1

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
    printf '%s/.grok/auth.json exists from Grok login.\n' "$HOME"
    return 0
  fi

  printf 'Grok is not authenticated. Run grok login, or set XAI_API_KEY in non-browser environments.\n' >&2
  return 1
}

status_github() {
  require_selected github || return 1
  have gh && gh auth status --hostname github.com
}

auth_codex() {
  require_selected codex || return 1
  if ! have codex; then
    printf 'codex is not installed\n' >&2
    return 1
  fi

  codex login
}

auth_grok() {
  local grok_bin
  require_selected grok || return 1

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
  require_selected github || return 1
  if ! have gh; then
    printf 'gh is not installed\n' >&2
    return 1
  fi

  gh auth login --hostname github.com --git-protocol ssh
}

auth_pi() {
  require_selected pi || return 1
  if ! have pi; then
    printf 'pi is not installed\n' >&2
    return 1
  fi

  printf 'Pi is interactive. At its prompt, enter /login, then exit when done.\n' >&2
  pi
}

status_pi() {
  require_selected pi || return 1
  if ! have pi; then
    printf 'pi is not installed\n' >&2
    return 1
  fi
  printf 'Pi does not expose a non-interactive auth status check. Run vpsbuddy-auth --pi and use /login.\n'
}

auth_opencode() {
  require_selected opencode || return 1
  if ! have opencode; then
    printf 'opencode is not installed\n' >&2
    return 1
  fi

  opencode auth login
}

status_opencode() {
  require_selected opencode || return 1
  have opencode && opencode auth list
}

auth_amp() {
  require_selected amp || return 1
  if ! have amp; then
    printf 'amp is not installed\n' >&2
    return 1
  fi

  amp login
}

status_amp() {
  require_selected amp || return 1
  if ! have amp; then
    printf 'amp is not installed\n' >&2
    return 1
  fi
  printf 'Amp does not expose a non-interactive auth status check. Run vpsbuddy-auth --amp.\n'
}

auth_droid() {
  require_selected droid || return 1
  if ! have droid; then
    printf 'droid is not installed\n' >&2
    return 1
  fi

  printf 'Droid is interactive. At its prompt, enter /login, then exit when done.\n' >&2
  droid
}

status_droid() {
  require_selected droid || return 1
  if ! have droid; then
    printf 'droid is not installed\n' >&2
    return 1
  fi
  printf 'Droid auth status is interactive. Run vpsbuddy-auth --droid and use /login.\n'
}

auth_claude() {
  require_selected claude || return 1
  if ! have claude; then
    printf 'claude is not installed\n' >&2
    return 1
  fi

  claude auth login
}

status_claude() {
  require_selected claude || return 1
  have claude && claude auth status
}

auth_cli() {
  case "$1" in
    codex) auth_codex ;;
    grok) auth_grok ;;
    github) auth_github ;;
    pi) auth_pi ;;
    opencode) auth_opencode ;;
    amp) auth_amp ;;
    droid) auth_droid ;;
    claude) auth_claude ;;
    *) return 2 ;;
  esac
}

status_cli() {
  case "$1" in
    codex) status_codex ;;
    grok) status_grok ;;
    github) status_github ;;
    pi) status_pi ;;
    opencode) status_opencode ;;
    amp) status_amp ;;
    droid) status_droid ;;
    claude) status_claude ;;
    *) return 2 ;;
  esac
}

run_status() {
  local cli_id status=0

  for cli_id in codex grok github pi opencode amp droid claude; do
    selected_cli "$cli_id" || continue
    printf '\n== %s ==\n' "$cli_id"
    status_cli "$cli_id" || status=1
  done
  return "$status"
}

run_all() {
  local cli_id status=0

  for cli_id in codex grok github pi opencode amp droid claude; do
    selected_cli "$cli_id" || continue
    auth_cli "$cli_id" || status=1
  done
  return "$status"
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
    --pi)
      auth_pi
      ;;
    --opencode)
      auth_opencode
      ;;
    --amp)
      auth_amp
      ;;
    --droid)
      auth_droid
      ;;
    --claude)
      auth_claude
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
