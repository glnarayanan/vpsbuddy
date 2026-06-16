#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=../lib/vps-bootstrap.sh
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
    --user ops \
    --pubkey tests/fixtures/id_ed25519.pub \
    --identity tests/fixtures/identity_fixture \
    --hostname app-vps \
    --enable-tailscale-ssh \
    --full-sudo \
    --no-web \
    --dry-run

  assert_eq "parse host" "203.0.113.10" "$VPS_HOST"
  assert_eq "parse admin user" "ops" "$VPS_ADMIN_USER"
  assert_eq "parse pubkey" "tests/fixtures/id_ed25519.pub" "$VPS_PUBKEY"
  assert_eq "parse identity" "tests/fixtures/identity_fixture" "$VPS_IDENTITY"
  assert_eq "parse hostname" "app-vps" "$VPS_HOSTNAME"
  assert_eq "parse tailscale ssh flag" "1" "$VPS_ENABLE_TAILSCALE_SSH"
  assert_eq "parse agent cli install default" "1" "$VPS_INSTALL_AGENT_CLIS"
  assert_eq "parse full sudo flag" "1" "$VPS_FULL_SUDO"
  assert_eq "parse no web flag" "0" "$VPS_WEB"
  assert_eq "parse dry-run flag" "1" "$VPS_DRY_RUN"
}

test_parse_args_supports_web_equals_false() {
  reset_config
  parse_args --host example.test --web=false

  assert_eq "web=false disables public web" "0" "$VPS_WEB"
}

test_parse_args_supports_skipping_agent_clis() {
  reset_config
  parse_args --host example.test --skip-agent-clis

  assert_eq "skip agent clis disables install" "0" "$VPS_INSTALL_AGENT_CLIS"
}

test_parse_args_rejects_removed_agent_auth_options() {
  reset_config
  if parse_args --host example.test --agent-auth interactive >/tmp/vps-bootstrap-test.out 2>/tmp/vps-bootstrap-test.err; then
    fail "removed --agent-auth should fail"
    return
  fi

  if parse_args --host example.test --agent-auth-env-file tests/fixtures/agent-cli.env >/tmp/vps-bootstrap-test.out 2>/tmp/vps-bootstrap-test.err; then
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
  assert_contains "remote script supports dnf automatic install timer" "$script" "dnf-automatic-install.timer"
  assert_contains "remote script supports dnf automatic fallback timer" "$script" "dnf-automatic.timer"
  assert_contains "remote script installs tailscale officially" "$script" "https://tailscale.com/install.sh"
  assert_contains "remote script uses interactive tailscale up" "$script" "tailscale up --hostname"
  assert_contains "remote script validates sshd" "$script" "sshd -t"
}

test_remote_script_installs_agent_clis_and_supports_auth_modes() {
  local script
  script="$(generate_remote_script)"

  assert_contains "remote script installs codex cli" "$script" "npm install -g @openai/codex"
  assert_contains "remote script installs official grok cli" "$script" "https://x.ai/cli/install.sh | bash"
  assert_contains "remote script installs grok cli as admin user" "$script" 'sudo -H -u "$admin_user"'
  assert_contains "remote script removes third-party grok package" "$script" "npm uninstall -g @vibe-kit/grok-cli"
  assert_contains "remote script installs github cli apt repo" "$script" "https://cli.github.com/packages stable main"
  assert_contains "remote script installs github cli rpm repo" "$script" "https://cli.github.com/packages/rpm/gh-cli.repo"
  assert_contains "remote script records codex version" "$script" "VPS_BOOTSTRAP_CODEX_VERSION="
  assert_contains "remote script records grok version" "$script" "VPS_BOOTSTRAP_GROK_VERSION="
  assert_contains "remote script records github cli version" "$script" "VPS_BOOTSTRAP_GH_VERSION="
  assert_not_contains "remote script does not install third-party grok package" "$script" "npm install -g @vibe-kit/grok-cli"
  assert_not_contains "remote script does not install claude" "$script" "claude-code"
}

test_agent_auth_helper_uses_native_auth_only() {
  local helper
  helper="$(generate_agent_auth_helper_script)"

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

  assert_contains "scoped sudo allows apt" "$policy" "/usr/bin/apt-get"
  assert_contains "scoped sudo allows systemctl" "$policy" "/usr/bin/systemctl"
  assert_contains "scoped sudo allows journalctl" "$policy" "/usr/bin/journalctl"
  assert_contains "scoped sudo allows npm global installs" "$policy" "/usr/bin/npm"
  assert_contains "scoped sudo allows grok cli" "$policy" "/usr/bin/grok"
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
  assert_contains "remote script writes final requested sudo policy" "$script" 'write_sudoers_policy "$full_sudo"'
  assert_order "remote script final sudo policy happens during harden" "$script" "write_sshd_hardening" 'write_sudoers_policy "$full_sudo"'
}

test_dry_run_prints_rollback_safe_phase_ordering() {
  local output
  reset_config
  output="$(
    main \
      --host 203.0.113.10 \
      --pubkey tests/fixtures/id_ed25519.pub \
      --identity tests/fixtures/identity_fixture \
      --dry-run
  )"

  assert_contains "dry-run announces no remote mutation" "$output" "Dry run: no SSH connections will be opened."
  assert_contains "dry-run includes prepare phase" "$output" "Phase 1: prepare as root"
  assert_contains "dry-run includes verify phase" "$output" "Phase 2: verify Tailnet key login"
  assert_contains "dry-run includes agent cli config" "$output" "developer CLIs: install"
  assert_contains "dry-run includes post setup auth command" "$output" "vps-agent-auth --all"
  assert_contains "dry-run includes post setup status command" "$output" "vps-agent-auth --status"
  assert_contains "dry-run includes harden phase" "$output" "Phase 3: harden over Tailnet"
  assert_order "dry-run verifies before hardening" "$output" "Phase 2: verify Tailnet key login" "Phase 3: harden over Tailnet"
  assert_order "dry-run prepares before verification" "$output" "Phase 1: prepare as root" "Phase 2: verify Tailnet key login"
}

test_build_admin_verify_command_uses_batch_mode_and_tailnet_ip() {
  local command
  command="$(build_admin_verify_command "deploy" "100.64.0.10" "tests/fixtures/identity_fixture")"

  assert_contains "verify command uses batch mode" "$command" "-o BatchMode=yes"
  assert_contains "verify command pins identity" "$command" "-i tests/fixtures/identity_fixture"
  assert_contains "verify command targets tailnet ip" "$command" "deploy@100.64.0.10"
  assert_contains "verify command checks sudo" "$command" "sudo -n true"
}

test_parse_prepare_output_extracts_tailnet_ip() {
  local output ip
  output=$'some log\nVPS_BOOTSTRAP_TAILSCALE_IP=100.64.0.25\nmore log'
  ip="$(parse_prepare_tailnet_ip "$output")"

  assert_eq "parse prepare tailnet ip" "100.64.0.25" "$ip"
}

test_remote_config_prelude_preserves_public_key_and_empty_hostname() {
  local prelude public_key loaded_public_key loaded_hostname
  reset_config
  VPS_ADMIN_USER="deploy"
  VPS_HOSTNAME=""
  public_key="$(read_public_key tests/fixtures/id_ed25519.pub)"
  prelude="$(generate_remote_config_prelude prepare "$public_key")"

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

  assert_eq "remote config preserves spaced public key" "$public_key" "$loaded_public_key"
  assert_eq "remote config preserves empty hostname" "" "$loaded_hostname"
  assert_contains "remote config sets phase" "$prelude" "phase=prepare"
}

test_parse_args_sets_default_user() {
  reset_config
  parse_args --host example.test

  assert_eq "default user is deploy" "deploy" "$VPS_ADMIN_USER"
}

test_parse_args_requires_host() {
  reset_config
  if parse_args --user deploy >/tmp/vps-bootstrap-test.out 2>/tmp/vps-bootstrap-test.err; then
    fail "missing host should fail"
    return
  fi

  pass "missing host should fail"
}

test_remote_script_prepends_missing_sshd_include() {
  local script
  script="$(generate_remote_script)"

  assert_contains "remote script backs up sshd config before include edit" "$script" "sshd_config.vps-bootstrap.bak"
  assert_contains "remote script prepends include before existing sshd directives" "$script" "cat /etc/ssh/sshd_config"
  assert_not_contains "remote script does not append include after existing sshd directives" "$script" ">>/etc/ssh/sshd_config"
}

test_parse_args_sets_defaults_and_flags
test_parse_args_supports_web_equals_false
test_parse_args_supports_skipping_agent_clis
test_parse_args_rejects_removed_agent_auth_options
test_identity_path_defaults_from_public_key
test_hardening_config_contains_required_directives
test_ufw_rules_keep_public_ssh_until_harden_phase
test_firewalld_rules_remove_public_ssh_and_keep_web
test_remote_script_contains_supported_distros_and_tailscale_flow
test_remote_script_installs_agent_clis_and_supports_auth_modes
test_agent_auth_helper_uses_native_auth_only
test_remote_script_installs_agent_auth_helper
test_sudoers_policy_is_scoped_by_default
test_sudoers_policy_supports_full_sudo_escape_hatch
test_remote_script_uses_temporary_bootstrap_sudo_then_final_policy
test_dry_run_prints_rollback_safe_phase_ordering
test_build_admin_verify_command_uses_batch_mode_and_tailnet_ip
test_parse_prepare_output_extracts_tailnet_ip
test_remote_config_prelude_preserves_public_key_and_empty_hostname
test_parse_args_sets_default_user
test_parse_args_requires_host
test_remote_script_prepends_missing_sshd_include

if [[ "$failures" -gt 0 ]]; then
  printf '\n%s test(s) failed\n' "$failures" >&2
  exit 1
fi

printf '\nall tests passed\n'
