# shellcheck shell=bash
VPS_AGENT_AUDIT_HELPER="${0##*/}"
VPS_AGENT_AUDIT_ACTION="${1:-}"
VPS_AGENT_AUDIT_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VPS_AGENT_AUDIT_ARGS=("$@")

vps_agent_json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

vps_agent_audit_args_json() {
  local arg first
  first="1"
  printf '['
  for arg in "${VPS_AGENT_AUDIT_ARGS[@]}"; do
    if [[ "$first" == "1" ]]; then
      first="0"
    else
      printf ','
    fi
    printf '"%s"' "$(vps_agent_json_escape "$arg")"
  done
  printf ']'
}

vps_agent_audit_finish() {
  local status="$1" user args_json
  set +e
  user="${SUDO_USER:-${USER:-unknown}}"
  args_json="$(vps_agent_audit_args_json)"
  printf '{"ts":"%s","helper":"%s","user":"%s","action":"%s","args":%s,"exit_code":%s}\n' \
    "$(vps_agent_json_escape "$VPS_AGENT_AUDIT_STARTED_AT")" \
    "$(vps_agent_json_escape "$VPS_AGENT_AUDIT_HELPER")" \
    "$(vps_agent_json_escape "$user")" \
    "$(vps_agent_json_escape "$VPS_AGENT_AUDIT_ACTION")" \
    "$args_json" \
    "$status" \
    >>/var/log/vps-agent-actions.log 2>/dev/null || true
  chmod 0640 /var/log/vps-agent-actions.log 2>/dev/null || true
}

trap 'vps_agent_audit_finish "$?"' EXIT
