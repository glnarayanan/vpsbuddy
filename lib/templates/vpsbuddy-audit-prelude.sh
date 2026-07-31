# shellcheck shell=bash
VPSBUDDY_AUDIT_HELPER="${0##*/}"
VPSBUDDY_AUDIT_ACTION="${1:-}"
VPSBUDDY_AUDIT_STARTED_AT="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
VPSBUDDY_AUDIT_ARGS=("$@")

vpsbuddy_json_escape() {
  local value="$1"
  value="${value//\\/\\\\}"
  value="${value//\"/\\\"}"
  value="${value//$'\n'/\\n}"
  value="${value//$'\r'/\\r}"
  value="${value//$'\t'/\\t}"
  printf '%s' "$value"
}

vpsbuddy_audit_args_json() {
  local arg first
  first="1"
  printf '['
  if [[ "${#VPSBUDDY_AUDIT_ARGS[@]}" -gt 0 ]]; then
    for arg in "${VPSBUDDY_AUDIT_ARGS[@]}"; do
      if [[ "$first" == "1" ]]; then
        first="0"
      else
        printf ','
      fi
      printf '"%s"' "$(vpsbuddy_json_escape "$arg")"
    done
  fi
  printf ']'
}

vpsbuddy_audit_finish() {
  local status="$1" user args_json
  set +e
  user="${SUDO_USER:-${USER:-unknown}}"
  args_json="$(vpsbuddy_audit_args_json)"
  ({
    printf '{"ts":"%s","helper":"%s","user":"%s","action":"%s","args":%s,"exit_code":%s}\n' \
      "$(vpsbuddy_json_escape "$VPSBUDDY_AUDIT_STARTED_AT")" \
      "$(vpsbuddy_json_escape "$VPSBUDDY_AUDIT_HELPER")" \
      "$(vpsbuddy_json_escape "$user")" \
      "$(vpsbuddy_json_escape "$VPSBUDDY_AUDIT_ACTION")" \
      "$args_json" \
      "$status"
  } >> /var/log/vpsbuddy-actions.log) 2> /dev/null || true
  chmod 0640 /var/log/vpsbuddy-actions.log 2> /dev/null || true
}

trap 'vpsbuddy_audit_finish "$?"' EXIT
