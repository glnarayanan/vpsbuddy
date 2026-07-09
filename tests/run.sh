#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=lib/vps-bootstrap.sh
source "$ROOT_DIR/lib/vps-bootstrap.sh"

failures=0

fail() {
  printf 'not ok - %s\n' "$1" >&2
  failures=$((failures + 1))
}

pass() {
  printf 'ok - %s\n' "$1"
}

assert_eq() {
  local name="$1"
  local expected="$2"
  local actual="$3"

  if [[ "$expected" != "$actual" ]]; then
    fail "$name: expected [$expected], got [$actual]"
    return
  fi

  pass "$name"
}

assert_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" != *"$needle"* ]]; then
    fail "$name: missing [$needle]"
    return
  fi

  pass "$name"
}

assert_not_contains() {
  local name="$1"
  local haystack="$2"
  local needle="$3"

  if [[ "$haystack" == *"$needle"* ]]; then
    fail "$name: unexpectedly found [$needle]"
    return
  fi

  pass "$name"
}

assert_order() {
  local name="$1"
  local haystack="$2"
  local first="$3"
  local second="$4"
  local first_index second_index

  first_index=$(printf '%s' "$haystack" | awk -v needle="$first" 'index($0, needle) { print NR; exit }')
  second_index=$(printf '%s' "$haystack" | awk -v needle="$second" 'index($0, needle) { print NR; exit }')

  if [[ -z "$first_index" || -z "$second_index" || "$first_index" -ge "$second_index" ]]; then
    fail "$name: [$first] should appear before [$second]"
    return
  fi

  pass "$name"
}

test_parse_args_sets_defaults_and_flags() {
  reset_config
  parse_args \
    --host 203.0.113.10 \
    --login-user admin \
    --user ops \
    --pubkey tests/fixtures/id_ed25519.pub \
    --identity tests/fixtures/identity_fixture \
    --hostname app-vps \
    --enable-tailscale-ssh \
    --full-sudo \
    --no-web \
    --dry-run

  assert_eq "parse host" "203.0.113.10" "$VPS_HOST"
  assert_eq "parse login user" "admin" "$VPS_LOGIN_USER"
  assert_eq "parse admin user" "ops" "$VPS_ADMIN_USER"
  assert_eq "parse pubkey" "tests/fixtures/id_ed25519.pub" "$VPS_PUBKEY"
  assert_eq "parse identity" "tests/fixtures/identity_fixture" "$VPS_IDENTITY"
  assert_eq "parse hostname" "app-vps" "$VPS_HOSTNAME"
  assert_eq "parse tailscale ssh flag" "1" "$VPS_ENABLE_TAILSCALE_SSH"
  assert_eq "parse agent cli install default" "0" "$VPS_INSTALL_AGENT_CLIS"
  assert_eq "parse full sudo flag" "1" "$VPS_FULL_SUDO"
  assert_eq "parse no web flag" "0" "$VPS_WEB"
  assert_eq "parse dry-run flag" "1" "$VPS_DRY_RUN"
}

test_parse_args_supports_installing_agent_clis() {
  reset_config
  parse_args --host example.test --login-user admin --install-agent-clis

  assert_eq "install agent clis enables install" "1" "$VPS_INSTALL_AGENT_CLIS"
}

test_parse_args_supports_web_equals_false() {
  reset_config
  parse_args --host example.test --login-user admin --web=false

  assert_eq "web=false disables public web" "0" "$VPS_WEB"
}

test_parse_args_supports_skipping_agent_clis() {
  reset_config
  parse_args --host example.test --login-user admin --skip-agent-clis

  assert_eq "skip agent clis disables install" "0" "$VPS_INSTALL_AGENT_CLIS"
}

test_parse_args_rejects_removed_agent_auth_options() {
  reset_config
  if parse_args --host example.test --agent-auth interactive > /tmp/vps-bootstrap-test.out 2> /tmp/vps-bootstrap-test.err; then
    fail "removed --agent-auth should fail"
    return
  fi

  if parse_args --host example.test --agent-auth-env-file tests/fixtures/agent-cli.env > /tmp/vps-bootstrap-test.out 2> /tmp/vps-bootstrap-test.err; then
    fail "removed --agent-auth-env-file should fail"
    return
  fi

  pass "removed agent auth options should fail"
}

test_identity_path_defaults_from_public_key() {
  local identity
  identity="$(detect_identity_path "/home/me/.ssh/id_ed25519.pub")"

  assert_eq "identity path strips .pub" "/home/me/.ssh/id_ed25519" "$identity"
}

test_hardening_config_contains_required_directives() {
  local config
  config="$(generate_sshd_hardening_config)"

  assert_contains "hardening enables pubkey" "$config" "PubkeyAuthentication yes"
  assert_contains "hardening disables password" "$config" "PasswordAuthentication no"
  assert_contains "hardening disables keyboard interactive" "$config" "KbdInteractiveAuthentication no"
  assert_contains "hardening disables root login" "$config" "PermitRootLogin no"
  assert_contains "hardening limits auth tries" "$config" "MaxAuthTries 3"
  assert_contains "hardening disables x11" "$config" "X11Forwarding no"
}

test_ufw_rules_keep_public_ssh_until_harden_phase() {
  local prepare harden
  prepare="$(generate_ufw_rules prepare 1)"
  harden="$(generate_ufw_rules harden 0)"

  assert_contains "ufw prepare keeps temporary public ssh" "$prepare" "ufw allow 22/tcp"
  assert_contains "ufw prepare allows tailnet ssh" "$prepare" "ufw allow in on tailscale0 to any port 22 proto tcp"
  assert_contains "ufw prepare opens http" "$prepare" "ufw allow 80/tcp"
  assert_contains "ufw harden removes public ssh" "$harden" "ufw --force delete allow 22/tcp"
  assert_not_contains "ufw harden no web omits http" "$harden" "ufw allow 80/tcp"
}

test_firewalld_rules_remove_public_ssh_and_keep_web() {
  local harden
  harden="$(generate_firewalld_rules harden 1)"

  assert_contains "firewalld creates tailnet zone" "$harden" "firewall-cmd --permanent --new-zone=tailnet"
  assert_contains "firewalld binds tailscale interface" "$harden" "firewall-cmd --permanent --zone=tailnet --change-interface=tailscale0"
  assert_contains "firewalld removes public ssh" "$harden" "firewall-cmd --permanent --zone=public --remove-service=ssh"
  assert_contains "firewalld keeps http" "$harden" "firewall-cmd --permanent --zone=public --add-service=http"
  assert_contains "firewalld keeps https" "$harden" "firewall-cmd --permanent --zone=public --add-service=https"
}

test_remote_script_contains_supported_distros_and_tailscale_flow() {
  local script
  script="$(generate_remote_script)"

  assert_contains "remote script reads os-release" "$script" ". /etc/os-release"
  assert_contains "remote script supports apt" "$script" "apt-get update"
  assert_contains "remote script supports dnf" "$script" "dnf makecache"
  assert_contains "remote script supports yum" "$script" "yum makecache"
  assert_contains "remote script leaves update cadence to managed timer" "$script" "vps-os-update.timer controls the two-week update cadence"
  assert_contains "remote script installs tailscale officially" "$script" "https://tailscale.com/install.sh"
  assert_contains "remote script uses interactive tailscale up" "$script" "tailscale up --hostname"
  assert_contains "remote script validates sshd" "$script" "sshd -t"
}

test_remote_script_installs_agent_clis_and_supports_auth_modes() {
  local script
  script="$(generate_remote_script)"

  assert_contains "remote script installs codex cli with official installer" "$script" "https://chatgpt.com/codex/install.sh"
  assert_contains "remote script installs codex non-interactively" "$script" "CODEX_NON_INTERACTIVE=1 sh"
  assert_contains "remote script treats codex install as optional" "$script" "Codex CLI installation failed; continuing with bootstrap"
  assert_not_contains "remote script does not fatally abort on missing codex binary" "$script" "fail \"Codex CLI installer did not put codex on"
  assert_contains "remote script installs official grok cli" "$script" "https://x.ai/cli/install.sh | bash"
  assert_contains "remote script installs grok cli as admin user" "$script" "sudo -H -u \"\$admin_user\""
  assert_contains "remote script treats grok install as optional" "$script" "Grok CLI installation failed; continuing with bootstrap"
  assert_not_contains "remote script does not fatally abort on missing grok binary" "$script" "fail \"Grok CLI installer did not create"
  assert_contains "remote script removes third-party grok package" "$script" "npm uninstall -g @vibe-kit/grok-cli"
  assert_contains "remote script installs github cli apt repo" "$script" "https://cli.github.com/packages stable main"
  assert_contains "remote script installs github cli rpm repo" "$script" "https://cli.github.com/packages/rpm/gh-cli.repo"
  assert_contains "remote script treats github cli install as optional" "$script" "GitHub CLI installation failed; continuing with bootstrap"
  assert_contains "remote script records codex version" "$script" "VPS_BOOTSTRAP_CODEX_VERSION="
  assert_contains "remote script records grok version" "$script" "VPS_BOOTSTRAP_GROK_VERSION="
  assert_contains "remote script records github cli version" "$script" "VPS_BOOTSTRAP_GH_VERSION="
  assert_contains "remote script logs accepted codex installer trust" "$script" "accepted supply-chain trust boundary"
  assert_not_contains "remote script does not install third-party grok package" "$script" "npm install -g @vibe-kit/grok-cli"
  assert_not_contains "remote script does not install codex with npm" "$script" "npm install -g @openai/codex"
  assert_not_contains "remote script does not install claude" "$script" "claude-code"
}

test_remote_script_installs_update_timers() {
  local script
  script="$(generate_remote_script)"

  assert_contains "remote script installs agent cli updater" "$script" "/usr/local/sbin/vps-agent-cli-update"
  assert_contains "agent updater reruns codex installer" "$script" "https://chatgpt.com/codex/install.sh"
  assert_contains "agent updater does not abort on codex failure" "$script" "Codex CLI update failed; continuing with other agent CLI updates"
  assert_contains "agent updater runs grok update" "$script" "grok update"
  assert_contains "agent updater does not abort on grok failure" "$script" "Grok CLI update failed"
  assert_contains "agent updater installs two day timer" "$script" "OnUnitActiveSec=2d"
  assert_contains "remote script installs os updater" "$script" "/usr/local/sbin/vps-os-update"
  assert_contains "os updater runs apt unattended upgrade" "$script" "unattended-upgrade -d"
  assert_contains "os updater supports dnf upgrade" "$script" "dnf -y upgrade"
  assert_contains "os updater supports yum update" "$script" "yum -y update"
  assert_contains "os updater installs two week timer" "$script" "OnUnitActiveSec=14d"
  assert_contains "apt periodic unattended upgrade is every fourteen days" "$script" 'APT::Periodic::Unattended-Upgrade "14";'
}

test_remote_script_defers_tailscale_ssh_until_harden() {
  local script prepare_body harden_body
  script="$(generate_remote_script)"
  prepare_body="$(printf '%s\n' "$script" | awk '/^run_prepare\(\)/,/^}/')"
  harden_body="$(printf '%s\n' "$script" | awk '/^run_harden\(\)/,/^}/')"

  assert_not_contains "prepare does not enable tailscale ssh before verification" "$prepare_body" "enable_tailscale_ssh_if_requested"
  assert_contains "harden can enable requested tailscale ssh" "$harden_body" "enable_tailscale_ssh_if_requested"
  assert_order "tailscale ssh waits until hardening policy is written" "$harden_body" "write_sudoers_policy \"\$full_sudo\"" "enable_tailscale_ssh_if_requested"
}

test_agent_auth_helper_uses_native_auth_only() {
  local helper
  helper="$(cat lib/templates/vps-agent-auth.sh)"

  assert_contains "helper supports all mode" "$helper" "--all"
  assert_contains "helper supports status mode" "$helper" "--status"
  assert_contains "helper uses codex native auth" "$helper" "codex login"
  assert_contains "helper supports grok setup" "$helper" "--grok"
  assert_contains "helper runs grok login" "$helper" "grok_bin\" login"
  assert_contains "helper documents xai api key env" "$helper" "XAI_API_KEY"
  assert_contains "helper checks grok auth file" "$helper" ".grok/auth.json"
  assert_contains "helper uses github native auth" "$helper" "gh auth login --hostname github.com --git-protocol ssh"
  assert_contains "helper checks codex status" "$helper" "codex login status"
  assert_contains "helper checks grok status" "$helper" "status_grok"
  assert_contains "helper checks github status" "$helper" "gh auth status --hostname github.com"
  assert_not_contains "helper does not use codex api key login" "$helper" "codex login --with-api-key"
  assert_not_contains "helper does not use token login" "$helper" "gh auth login --with-token"
  assert_not_contains "helper does not reference auth env file" "$helper" "agent-cli.env"
  assert_not_contains "helper does not reference claude" "$helper" "claude"
  assert_not_contains "helper does not use third-party grok settings" "$helper" "user-settings.json"
}

test_remote_script_installs_agent_auth_helper() {
  local script
  script="$(generate_remote_script)"

  assert_contains "remote script installs auth helper" "$script" "/usr/local/bin/vps-agent-auth"
  assert_contains "remote script makes auth helper executable" "$script" "chmod 755 /usr/local/bin/vps-agent-auth"
  assert_not_contains "remote script does not upload auth env" "$script" "agent-cli.env"
  assert_not_contains "remote script does not store headless tokens" "$script" "ANTHROPIC_API_KEY"
}

test_sudoers_policy_is_scoped_by_default() {
  local policy
  policy="$(generate_sudoers_policy "deploy" "0")"

  assert_contains "scoped sudo allows package helper" "$policy" "/usr/local/sbin/vps-agent-package"
  assert_contains "scoped sudo allows service helper" "$policy" "/usr/local/sbin/vps-agent-service"
  assert_contains "scoped sudo allows deploy helper" "$policy" "/usr/local/sbin/vps-agent-deploy"
  assert_contains "scoped sudo allows sudo check helper" "$policy" "/usr/local/sbin/vps-agent-sudo-check"
  assert_not_contains "scoped sudo avoids raw apt" "$policy" "/usr/bin/apt-get"
  assert_not_contains "scoped sudo avoids raw systemctl" "$policy" "/usr/bin/systemctl"
  assert_not_contains "scoped sudo avoids raw npm" "$policy" "/usr/bin/npm"
  assert_not_contains "scoped sudo avoids user cli symlink" "$policy" "/usr/local/bin/grok"
  assert_not_contains "scoped sudo avoids claude cli" "$policy" "/usr/bin/claude"
  assert_not_contains "scoped sudo avoids all access" "$policy" "NOPASSWD:ALL"
}

test_sudoers_policy_supports_full_sudo_escape_hatch() {
  local policy
  policy="$(generate_sudoers_policy "deploy" "1")"

  assert_contains "full sudo preserves nopasswd all" "$policy" "deploy ALL=(ALL) NOPASSWD:ALL"
}

test_remote_script_uses_temporary_bootstrap_sudo_then_final_policy() {
  local script
  script="$(generate_remote_script)"

  assert_contains "remote script grants temporary bootstrap sudo" "$script" "write_sudoers_policy \"1\""
  assert_contains "remote script installs bounded sudo helpers" "$script" "install_agent_sudo_helpers"
  assert_contains "remote script writes package helper" "$script" "/usr/local/sbin/vps-agent-package"
  assert_contains "remote script writes deploy helper" "$script" "/usr/local/sbin/vps-agent-deploy"
  assert_contains "remote script writes final requested sudo policy" "$script" "write_sudoers_policy \"\$full_sudo\""
  assert_order "remote script final sudo policy happens during harden" "$script" "write_sshd_hardening" "write_sudoers_policy \"\$full_sudo\""
}

test_host_public_key_validation_and_known_hosts() {
  local known_hosts scanned_key

  validate_host_public_key_line "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAexample"
  if validate_host_public_key_line "SHA256:not-a-public-key" > /tmp/vps-bootstrap-test.out 2> /tmp/vps-bootstrap-test.err; then
    fail "fingerprint should not be accepted as host public key"
    return
  fi

  scanned_key="$(
    printf '# comment\n203.0.113.10 ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAexample\n' |
      extract_keyscan_public_key
  )"
  assert_eq "keyscan parser extracts public key line" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAexample" "$scanned_key"

  known_hosts="$(mktemp "${TMPDIR:-/tmp}/vps-bootstrap-test-known-hosts.XXXXXX")"
  write_known_hosts_file "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAexample" "$known_hosts"
  assert_contains "known hosts uses stable alias" "$(cat "$known_hosts")" "vps-bootstrap-target ssh-ed25519"
  rm -f "$known_hosts"
}

test_dry_run_prints_rollback_safe_phase_ordering() {
  local output
  reset_config
  output="$(
    main \
      --host 203.0.113.10 \
      --login-user admin \
      --pubkey tests/fixtures/id_ed25519.pub \
      --identity tests/fixtures/identity_fixture \
      --dry-run
  )"

  assert_contains "dry-run announces no remote mutation" "$output" "Dry run: no SSH connections will be opened."
  assert_contains "dry-run includes prepare phase" "$output" "Phase 1: prepare through admin"
  assert_contains "dry-run includes pinned host key note" "$output" "temporary known_hosts"
  assert_contains "dry-run includes verify phase" "$output" "Phase 2: verify Tailnet key login"
  assert_contains "dry-run includes agent cli config" "$output" "developer CLIs: skip"
  assert_contains "dry-run explains skipped agent auth" "$output" "pass --install-agent-clis"
  assert_not_contains "dry-run omits post setup auth command when skipped" "$output" "vps-agent-auth --all"
  assert_contains "dry-run includes manual harden checkpoint" "$output" "Manual checkpoint"
  assert_contains "dry-run includes harden phase" "$output" "Phase 3: harden over Tailnet"
  assert_order "dry-run verifies before hardening" "$output" "Phase 2: verify Tailnet key login" "Phase 3: harden over Tailnet"
  assert_order "dry-run prepares before verification" "$output" "Phase 1: prepare through admin" "Phase 2: verify Tailnet key login"
}

test_build_prepare_command_uses_sudo_for_non_root_login_user() {
  local command
  command="$(build_prepare_command "admin" "203.0.113.10")"

  assert_contains "prepare command targets login user" "$command" "admin@203.0.113.10"
  assert_contains "prepare command uploads script for non-root" "$command" "upload temporary script with scp"
  assert_contains "prepare command uses sudo for non-root" "$command" "sudo\\ bash"
}

test_build_admin_verify_command_uses_batch_mode_and_tailnet_ip() {
  local command
  command="$(build_admin_verify_command "deploy" "100.64.0.10" "tests/fixtures/identity_fixture")"

  assert_contains "verify command uses batch mode" "$command" "-o BatchMode=yes"
  assert_contains "verify command pins known hosts file" "$command" "UserKnownHostsFile=<temporary-known-hosts>"
  assert_contains "verify command uses host key alias" "$command" "HostKeyAlias=vps-bootstrap-target"
  assert_contains "verify command requires strict host checking" "$command" "StrictHostKeyChecking=yes"
  assert_contains "verify command pins identity" "$command" "-i tests/fixtures/identity_fixture"
  assert_contains "verify command targets tailnet ip" "$command" "deploy@100.64.0.10"
  assert_contains "verify command checks bounded sudo helper" "$command" "sudo -n /usr/local/sbin/vps-agent-sudo-check"
}

test_parse_prepare_output_extracts_tailnet_ip() {
  local output ip
  output=$'some log\nVPS_BOOTSTRAP_TAILSCALE_IP=100.64.0.25\nmore log'
  ip="$(parse_prepare_tailnet_ip "$output")"

  assert_eq "parse prepare tailnet ip" "100.64.0.25" "$ip"
}

test_remote_config_prelude_preserves_public_key_and_empty_hostname() {
  local expected_public_key prelude loaded_public_key loaded_hostname
  reset_config
  VPS_ADMIN_USER="deploy"
  VPS_HOSTNAME=""
  expected_public_key="$(read_public_key tests/fixtures/id_ed25519.pub)"
  prelude="$(generate_remote_config_prelude prepare "$expected_public_key")"

  loaded_public_key="$(
    public_key=""
    requested_hostname="not-empty"
    eval "$prelude"
    printf '%s' "$public_key"
  )"
  loaded_hostname="$(
    requested_hostname="not-empty"
    eval "$prelude"
    printf '%s' "$requested_hostname"
  )"

  assert_eq "remote config preserves spaced public key" "$expected_public_key" "$loaded_public_key"
  assert_eq "remote config preserves empty hostname" "" "$loaded_hostname"
  assert_contains "remote config sets phase" "$prelude" "phase=prepare"
}

test_parse_args_sets_default_user() {
  reset_config
  parse_args --host example.test --login-user admin

  assert_eq "default user is deploy" "deploy" "$VPS_ADMIN_USER"
}

test_parse_args_requires_host() {
  reset_config
  if parse_args --user deploy > /tmp/vps-bootstrap-test.out 2> /tmp/vps-bootstrap-test.err; then
    fail "missing host should fail"
    return
  fi

  pass "missing host should fail"
}

test_parse_args_requires_login_user() {
  reset_config
  if parse_args --host example.test > /tmp/vps-bootstrap-test.out 2> /tmp/vps-bootstrap-test.err; then
    fail "missing login user should fail"
    return
  fi

  pass "missing login user should fail"
}

test_parse_args_doctor_does_not_require_host() {
  reset_config
  parse_args doctor --pubkey tests/fixtures/id_ed25519.pub --identity tests/fixtures/identity_fixture

  assert_eq "doctor mode enabled" "1" "$VPS_DOCTOR"
  assert_eq "doctor mode allows empty host" "" "$VPS_HOST"
}

test_remote_script_prepends_missing_sshd_include() {
  local script
  script="$(generate_remote_script)"

  assert_contains "remote script backs up sshd config before include edit" "$script" "sshd_config.vps-bootstrap.bak"
  assert_contains "remote script prepends include before existing sshd directives" "$script" "cat /etc/ssh/sshd_config"
  assert_not_contains "remote script does not append include after existing sshd directives" "$script" ">>/etc/ssh/sshd_config"
}

test_remote_script_installs_agent_helper_audit_logging() {
  local script
  script="$(generate_remote_script)"

  assert_contains "audit prelude template defines finish hook" "$(cat lib/templates/vps-agent-audit-prelude.sh)" "vps_agent_audit_finish()"
  assert_contains "helper audit writes jsonl log" "$script" "/var/log/vps-agent-actions.log"
  assert_contains "helper audit records helper name" "$script" '"helper":"%s"'
  assert_contains "helper audit records exit code" "$script" '"exit_code":%s'
  assert_contains "package helper receives audit prelude" "$script" "agent_audit_prelude"
  assert_contains "agent cli updater receives audit prelude" "$script" "AGENT_CLI_UPDATE_BODY"
}

test_remote_script_defaults_skip_agent_clis_without_prelude() {
  local script
  script="$(generate_remote_script)"

  assert_contains "remote script defaults agent clis off" "$script" "install_agent_clis=\"\${install_agent_clis:-0}\""
  assert_not_contains "remote script does not default agent clis on" "$script" "install_agent_clis=\"\${install_agent_clis:-1}\""
}

test_audit_prelude_handles_empty_args_and_suppresses_write_errors() {
  local output status

  set +e
  output="$(
    bash -c '
      set -Eeuo pipefail
      source lib/templates/vps-agent-audit-prelude.sh
      vps_agent_audit_finish 0
    ' 2>&1
  )"
  status="$?"
  set -e

  assert_eq "audit prelude empty args status" "0" "$status"
  assert_eq "audit prelude suppresses log write errors" "" "$output"
}

test_doctor_prints_read_only_audit() {
  local output
  reset_config
  output="$(
    main doctor \
      --host 203.0.113.10 \
      --pubkey tests/fixtures/id_ed25519.pub \
      --identity tests/fixtures/identity_fixture
  )"

  assert_contains "doctor announces read-only audit" "$output" "Read-only audit: no SSH connections will be opened"
  assert_contains "doctor checks local inputs" "$output" "== Local bootstrap inputs =="
  assert_contains "doctor reports host key expectation" "$output" "first SSH host key"
  assert_contains "doctor prints provider firewall checklist" "$output" "== Provider firewall checklist =="
  assert_contains "doctor checks vps state" "$output" "== VPS state checks when run on the server =="
  assert_contains "doctor observes exposed ports" "$output" "== Exposed ports observation =="
  assert_contains "doctor reports success summary" "$output" "Doctor completed without blocking local input issues."
}

test_parse_args_sets_defaults_and_flags
test_parse_args_supports_installing_agent_clis
test_parse_args_supports_web_equals_false
test_parse_args_supports_skipping_agent_clis
test_parse_args_rejects_removed_agent_auth_options
test_identity_path_defaults_from_public_key
test_hardening_config_contains_required_directives
test_ufw_rules_keep_public_ssh_until_harden_phase
test_firewalld_rules_remove_public_ssh_and_keep_web
test_remote_script_contains_supported_distros_and_tailscale_flow
test_remote_script_defers_tailscale_ssh_until_harden
test_remote_script_installs_agent_clis_and_supports_auth_modes
test_remote_script_installs_update_timers
test_agent_auth_helper_uses_native_auth_only
test_remote_script_installs_agent_auth_helper
test_sudoers_policy_is_scoped_by_default
test_sudoers_policy_supports_full_sudo_escape_hatch
test_remote_script_uses_temporary_bootstrap_sudo_then_final_policy
test_host_public_key_validation_and_known_hosts
test_dry_run_prints_rollback_safe_phase_ordering
test_build_admin_verify_command_uses_batch_mode_and_tailnet_ip
test_parse_prepare_output_extracts_tailnet_ip
test_remote_config_prelude_preserves_public_key_and_empty_hostname
test_parse_args_sets_default_user
test_parse_args_requires_host
test_parse_args_requires_login_user
test_parse_args_doctor_does_not_require_host
test_remote_script_prepends_missing_sshd_include
test_remote_script_installs_agent_helper_audit_logging
test_remote_script_defaults_skip_agent_clis_without_prelude
test_audit_prelude_handles_empty_args_and_suppresses_write_errors
test_doctor_prints_read_only_audit

if [[ "$failures" -gt 0 ]]; then
  printf '\n%s test(s) failed\n' "$failures" >&2
  exit 1
fi

printf '\nall tests passed\n'
