#!/usr/bin/env bash
set -Eeuo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

# shellcheck source=lib/vpsbuddy.sh
source "$ROOT_DIR/lib/vpsbuddy.sh"

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
  local first_line second_line

  first_line="$(printf '%s\n' "$haystack" | grep -nF "$first" | tail -n 1 | cut -d: -f1)"
  second_line="$(printf '%s\n' "$haystack" | grep -nF "$second" | tail -n 1 | cut -d: -f1)"
  if [[ -z "$first_line" || -z "$second_line" || "$first_line" -ge "$second_line" ]]; then
    fail "$name: [$first] must appear before [$second]"
    return
  fi

  pass "$name"
}

test_selected_cli_prompt_accepts_formats() {
  local selection error_file

  error_file="$(mktemp /tmp/vpsbuddy-cli-input.XXXXXX)"
  selection="$(
    exec 3<<< $'\n1, 8 3 3\n'
    VPS_INPUT_FD=3
    prompt_selected_clis 2> "$error_file"
  )"
  assert_eq "CLI selection deduplicates and canonicalizes" "codex github claude" "$selection"
  assert_contains "blank CLI selection is rejected" "$(cat "$error_file")" "choose at least one CLI"
  rm -f "$error_file"

  selection="$(
    exec 3<<< "ALL"
    VPS_INPUT_FD=3
    prompt_selected_clis 2> /dev/null
  )"
  assert_eq "all selects every CLI in canonical order" "codex grok github pi opencode amp droid claude" "$selection"

  selection="$(
    exec 3<<< "none"
    VPS_INPUT_FD=3
    prompt_selected_clis 2> /dev/null
  )"
  assert_eq "none selects no CLI" "" "$selection"

  error_file="$(mktemp /tmp/vpsbuddy-cli-input.XXXXXX)"
  selection="$(
    exec 3<<< $'all 1\n2\n'
    VPS_INPUT_FD=3
    prompt_selected_clis 2> "$error_file"
  )"
  assert_eq "mixed all input is rejected and reprompted" "grok" "$selection"
  assert_contains "mixed all input reports a format error" "$(cat "$error_file")" "enter valid CLI numbers"
  rm -f "$error_file"

  error_file="$(mktemp /tmp/vpsbuddy-cli-input.XXXXXX)"
  selection="$(
    exec 3<<< $'9\n2\n'
    VPS_INPUT_FD=3
    prompt_selected_clis 2> "$error_file"
  )"
  assert_eq "out of range CLI input is rejected and reprompted" "grok" "$selection"
  assert_contains "out of range CLI input reports a range error" "$(cat "$error_file")" "number from 1 to 8"
  rm -f "$error_file"

  if selected_cli "codex github" "ode"; then
    fail "CLI membership uses exact tokens"
  else
    pass "CLI membership uses exact tokens"
  fi
}

test_generated_selected_cli_behavior() {
  local server_script server_fixture public_key
  public_key="$(cat tests/fixtures/id_ed25519.pub)"
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  printf '%s\n' "$server_script" | sed '/^case "\$phase" in/,$d' > "$server_fixture"

  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key="$1"
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis=
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$2"
    validate_selected_clis_server
    ! has_cli_updates
  ' bash "$public_key" "$server_fixture"; then
    pass "empty selection passes generated validation without a CLI timer"
  else
    fail "empty selection passes generated validation without a CLI timer"
  fi

  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis=github
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    validate_selected_clis_server
    ! has_cli_updates
  ' bash "$server_fixture"; then
    pass "GitHub-only selection has no CLI update timer"
  else
    fail "GitHub-only selection has no CLI update timer"
  fi

  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis="codex github"
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    validate_selected_clis_server
    has_cli_updates
    selected_cli codex
    ! selected_cli ode
  ' bash "$server_fixture"; then
    pass "selected CLI membership is exact in generated code"
  else
    fail "selected CLI membership is exact in generated code"
  fi

  rm -f "$server_fixture"
}

test_generated_installer_failure_is_not_masked() {
  local server_script server_fixture home_dir link_dir manifest
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  home_dir="$(mktemp -d /tmp/vpsbuddy-cli-home.XXXXXX)"
  link_dir="$(mktemp -d /tmp/vpsbuddy-cli-links.XXXXXX)"
  manifest="$link_dir/manifest"
  mkdir -p "$home_dir/.grok/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$home_dir/.grok/bin/grok"
  chmod 755 "$home_dir/.grok/bin/grok"
  printf '%s\n' "$server_script" | sed '/^case "\$phase" in/,$d' > "$server_fixture"

  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis=grok
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    test_home="$2"
    cli_link_dir="$3"
    cli_link_manifest="$3/manifest"
    admin_home_dir() {
      printf "%s\n" "$test_home"
    }
    run_as_admin() {
      case "$2" in
        *"grok update"*) return 1 ;;
        *) return 0 ;;
      esac
    }
    install_grok_cli
  ' bash "$server_fixture" "$home_dir" "$link_dir"; then
    fail "failed Grok update is not masked by an existing binary"
  else
    pass "failed Grok update is not masked by an existing binary"
  fi

  rm -rf "$server_fixture" "$home_dir" "$link_dir"
}

test_generated_cli_link_cleanup() {
  local server_script server_fixture link_dir manifest target legacy_sudoers_dir legacy_home legacy_target
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  link_dir="$(mktemp -d /tmp/vpsbuddy-cli-links.XXXXXX)"
  manifest="$link_dir/manifest"
  target="$link_dir/old-admin/.codex/bin/codex"
  mkdir -p "$(dirname "$target")"
  printf '#!/usr/bin/env bash\n' > "$target"
  chmod 755 "$target"
  ln -s "$target" "$link_dir/codex"
  printf 'codex\t%s\n' "$target" > "$manifest"
  printf '%s\n' "$server_script" | sed '/^case "\$phase" in/,$d' > "$server_fixture"

  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis=
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    cli_link_dir="$2"
    cli_link_manifest="$3"
    remove_deselected_cli_links
    [[ ! -L "$cli_link_dir/codex" && -x "$4" ]]
  ' bash "$server_fixture" "$link_dir" "$manifest" "$target"; then
    pass "deselected CLI link is removed without uninstalling its binary"
  else
    fail "deselected CLI link is removed without uninstalling its binary"
  fi

  legacy_sudoers_dir="$link_dir/legacy-sudoers"
  legacy_home="$link_dir/legacy-home"
  mkdir -p "$legacy_sudoers_dir"
  touch "$legacy_sudoers_dir/90-vps-bootstrap-root"
  legacy_target="$legacy_home/.codex/bin/codex"
  ln -s "$legacy_target" "$link_dir/codex"

  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis=
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    cli_link_dir="$2"
    cli_link_manifest="$3"
    legacy_sudoers_dir="$4"
    legacy_home="$5"
    getent() {
      if [[ "$1" == passwd && "$2" == root ]]; then
        printf 'root:x:0:0:root:%s:/bin/bash' "$legacy_home"
      fi
    }
    remove_deselected_cli_links
    [[ ! -L "$cli_link_dir/codex" && ! -e "$cli_link_manifest" ]]
  ' bash "$server_fixture" "$link_dir" "$manifest" "$legacy_sudoers_dir" "$legacy_home"; then
    pass "legacy CLI link is cleaned with old ownership record"
  else
    fail "legacy CLI link is cleaned with old ownership record"
  fi

  rm -rf "$server_fixture" "$link_dir"
}

test_generated_cli_link_safety() {
  local server_script server_fixture link_dir home_dir
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  link_dir="$(mktemp -d /tmp/vpsbuddy-cli-links.XXXXXX)"
  home_dir="$(mktemp -d /tmp/vpsbuddy-cli-home.XXXXXX)"
  mkdir -p "$home_dir/.grok/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$home_dir/.grok/bin/grok"
  chmod 755 "$home_dir/.grok/bin/grok"
  printf 'unmanaged\n' > "$link_dir/grok"
  printf '%s\n' "$server_script" | sed '/^case "\$phase" in/,$d' > "$server_fixture"

  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis=
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    cli_link_dir="$2"
    cli_link_manifest="$2/manifest"
    if link_admin_command "$3" grok; then
      exit 1
    fi
    [[ -f "$cli_link_dir/grok" && ! -L "$cli_link_dir/grok" ]]
  ' bash "$server_fixture" "$link_dir" "$home_dir" 2> /dev/null; then
    pass "CLI link refuses to replace an unmanaged command"
  else
    fail "CLI link refuses to replace an unmanaged command"
  fi

  rm -f "$link_dir/grok"
  ln -s "$link_dir/grok" "$link_dir/grok"
  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis=
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    cli_link_dir="$2"
    cli_link_manifest="$2/manifest"
    run_as_admin() {
      printf '%s' "$cli_link_dir/grok"
    }
    if link_admin_command "$3" grok; then
      exit 1
    fi
    [[ -L "$cli_link_dir/grok" ]]
  ' bash "$server_fixture" "$link_dir" "$home_dir" 2> /dev/null; then
    pass "CLI link rejects a self-referential global link"
  else
    fail "CLI link rejects a self-referential global link"
  fi

  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis=
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    cli_link_dir="$2/managed"
    cli_link_manifest="$cli_link_dir/manifest"
    link_admin_command "$3" grok
    [[ -L "$cli_link_dir/grok" ]]
    [[ "$(readlink "$cli_link_dir/grok")" == "$3/.grok/bin/grok" ]]
    [[ "$(cut -f1 "$cli_link_manifest")" == grok ]]
    [[ "$(cut -f2 "$cli_link_manifest")" == "$3/.grok/bin/grok" ]]
  ' bash "$server_fixture" "$link_dir" "$home_dir"; then
    pass "CLI link records the selected command target"
  else
    fail "CLI link records the selected command target"
  fi

  rm -rf "$server_fixture" "$link_dir" "$home_dir"
}

test_generated_cli_updater_reports_failures() {
  local server_script server_fixture sbin_dir systemd_dir link_dir home_dir bin_dir record
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  sbin_dir="$(mktemp -d /tmp/vpsbuddy-cli-updater-sbin.XXXXXX)"
  systemd_dir="$(mktemp -d /tmp/vpsbuddy-cli-updater-systemd.XXXXXX)"
  link_dir="$(mktemp -d /tmp/vpsbuddy-cli-updater-links.XXXXXX)"
  home_dir="$(mktemp -d /tmp/vpsbuddy-cli-updater-home.XXXXXX)"
  bin_dir="$(mktemp -d /tmp/vpsbuddy-cli-updater-bin.XXXXXX)"
  record="$(mktemp /tmp/vpsbuddy-cli-updater-record.XXXXXX)"
  mkdir -p "$home_dir/.grok/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$home_dir/.grok/bin/grok"
  chmod 755 "$home_dir/.grok/bin/grok"
  cat > "$bin_dir/sudo" << 'FAKE_SUDO'
#!/usr/bin/env bash
shift 12
command="$1"
printf '%s\n' "$command" >>"$VPSBUDDY_TEST_RECORD"
if [[ "$command" == *"grok update"* ]]; then
  exit 1
fi
exit 0
FAKE_SUDO
  chmod 755 "$bin_dir/sudo"
  printf '%s\n' "$server_script" |
    sed -e '/^case "\$phase" in/,$d' \
      -e "s|/usr/local/sbin|$sbin_dir|g" \
      -e "s|/etc/systemd/system|$systemd_dir|g" > "$server_fixture"

  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis=grok
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    cli_link_dir="$2"
    cli_link_manifest="$2/manifest"
    test_home="$3"
    admin_home_dir() {
      printf "%s" "$test_home"
    }
    systemctl() {
      return 0
    }
    install_agent_cli_update_timer
    if PATH="$4:$PATH" VPSBUDDY_TEST_RECORD="$5" bash "$6/vpsbuddy-cli-update"; then
      exit 1
    fi
    [[ -L "$cli_link_dir/grok" ]]
    [[ "$(cut -f1 "$cli_link_manifest")" == grok ]]
    [[ "$(cut -f2 "$cli_link_manifest")" == "$3/.grok/bin/grok" ]]
    grep -q "grok update" "$5"
  ' bash "$server_fixture" "$link_dir" "$home_dir" "$bin_dir" "$record" "$sbin_dir"; then
    pass "generated CLI updater reports failure after attempting selected update"
  else
    fail "generated CLI updater reports failure after attempting selected update"
  fi

  rm -rf "$server_fixture" "$sbin_dir" "$systemd_dir" "$link_dir" "$home_dir" "$bin_dir" "$record"
}

test_generated_auth_helper_honors_selected_clis() {
  local server_script server_fixture auth_path bin_dir record record_output expected
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  auth_path="$(mktemp /tmp/vpsbuddy-auth-generated.XXXXXX)"
  bin_dir="$(mktemp -d /tmp/vpsbuddy-auth-generated-bin.XXXXXX)"
  record="$(mktemp /tmp/vpsbuddy-auth-generated-record.XXXXXX)"
  cat > "$bin_dir/fake-cli" << 'FAKE_CLI'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >>"$VPSBUDDY_TEST_RECORD"
FAKE_CLI
  chmod 755 "$bin_dir/fake-cli"
  for cli_id in codex grok pi opencode amp droid claude gh; do
    ln -s fake-cli "$bin_dir/$cli_id"
  done
  printf '%s\n' "$server_script" |
    sed "s|/usr/local/bin/vpsbuddy-auth|$auth_path|g" |
    sed '/^case "\$phase" in/,$d' > "$server_fixture"

  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis="codex grok github pi opencode amp droid claude"
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    install_agent_auth_helper
  ' bash "$server_fixture"; then
    if VPSBUDDY_TEST_RECORD="$record" PATH="$bin_dir:$PATH" /bin/bash "$auth_path" --all > /dev/null 2>&1; then
      record_output="$(cat "$record")"
      for expected in \
        "codex login" \
        "grok login" \
        "gh auth login" \
        "pi" \
        "opencode auth login" \
        "amp login" \
        "droid" \
        "claude auth login"; do
        assert_contains "generated auth helper runs $expected" "$record_output" "$expected"
      done
    else
      fail "generated auth helper runs selected CLI auth"
    fi
  else
    fail "generated auth helper is generated"
  fi

  rm -rf "$server_fixture" "$auth_path" "$bin_dir" "$record"
}

test_auth_helper_honors_selected_clis() {
  local bin_dir record empty_path output cli_id expected
  bin_dir="$(mktemp -d /tmp/vpsbuddy-auth-bin.XXXXXX)"
  record="$(mktemp /tmp/vpsbuddy-auth-record.XXXXXX)"
  empty_path="$(mktemp -d /tmp/vpsbuddy-auth-empty.XXXXXX)"
  cat > "$bin_dir/fake-cli" << 'FAKE_CLI'
#!/usr/bin/env bash
printf '%s %s\n' "${0##*/}" "$*" >>"$VPSBUDDY_TEST_RECORD"
FAKE_CLI
  chmod 755 "$bin_dir/fake-cli"
  for cli_id in codex grok pi opencode amp droid claude gh; do
    ln -s fake-cli "$bin_dir/$cli_id"
  done

  output="$(
    VPSBUDDY_TEST_RECORD="$record" \
      selected_clis="codex grok github pi opencode amp droid claude" \
      PATH="$bin_dir:$PATH" \
      bash lib/templates/vpsbuddy-auth.sh --all 2>&1
  )"
  for expected in \
    "codex login" \
    "grok login" \
    "gh auth login" \
    "pi" \
    "opencode auth login" \
    "amp login" \
    "droid" \
    "claude auth login"; do
    assert_contains "auth helper runs $expected" "$(cat "$record")" "$expected"
  done
  assert_not_contains "auth helper does not run unselected command" "$output" "unselected"

  if VPSBUDDY_TEST_RECORD="$record" \
    selected_clis=github \
    PATH="$bin_dir:$PATH" \
    bash lib/templates/vpsbuddy-auth.sh --codex > /dev/null 2>&1; then
    fail "auth helper rejects an unselected CLI"
  else
    pass "auth helper rejects an unselected CLI"
  fi

  for cli_id in pi amp droid; do
    if selected_clis="$cli_id" PATH="$empty_path" /bin/bash lib/templates/vpsbuddy-auth.sh --status > /dev/null 2>&1; then
      fail "auth status rejects missing $cli_id"
    else
      pass "auth status rejects missing $cli_id"
    fi
  done

  rm -rf "$bin_dir" "$record" "$empty_path"
}

test_configuration_has_no_hidden_operator_defaults() {
  reset_config

  assert_eq "admin user has no default" "" "$VPS_ADMIN_USER"
  assert_eq "swap choice has no default" "" "$VPS_SWAP_ENABLED"
  assert_eq "swap size has no default" "" "$VPS_SWAP_SIZE"
  assert_eq "web exposure has no default" "" "$VPS_WEB"
  assert_eq "developer CLI choice has no default" "" "$VPS_SELECTED_CLIS"
  assert_eq "sudo policy has no default" "" "$VPS_FULL_SUDO"
}

test_guided_dry_run_captures_operator_configuration() {
  local output

  output="$(
    bash -c '
      set -Eeuo pipefail
      source lib/vpsbuddy.sh
      exec 3<<<$'"'"'deploy\nyes\n\n4G\nyes\n1, 3, 8\nyes\nno\nno\n'"'"'
      VPS_INPUT_FD=3
      detect_existing_public_key() {
        cat tests/fixtures/id_ed25519.pub
      }
      has_active_swap() {
        return 1
      }
      main --dry-run
    ' 2>&1
  )"

  assert_contains "dry-run captures admin user" "$output" "Admin user: deploy"
  assert_contains "dry-run captures existing SSH key" "$output" "SSH public key: SHA256:"
  assert_contains "dry-run keeps current hostname when blank" "$output" "Hostname: keep current"
  assert_contains "dry-run captures swap size" "$output" "Swap: create 4G"
  assert_contains "dry-run captures public web choice" "$output" "Public web ports: open 80/443"
  assert_contains "dry-run captures developer CLI choice" "$output" "Developer CLIs: Codex GitHub CLI Claude Code"
  assert_contains "dry-run captures update choice" "$output" "Automatic OS updates: enable"
  assert_contains "dry-run captures scoped sudo choice" "$output" "Sudo policy: scoped helpers"
  assert_contains "dry-run captures Tailscale SSH choice" "$output" "Tailscale SSH: disabled"
  assert_contains "dry-run does not mutate server" "$output" "Dry run complete; no server changes were made."
}

test_fallback_key_and_no_swap_are_captured() {
  local output public_key
  public_key="$(cat tests/fixtures/id_ed25519.pub)"

  output="$(
    TEST_PUBLIC_KEY="$public_key" bash -c '
      set -Eeuo pipefail
      source lib/vpsbuddy.sh
      exec 3<<<"deploy
${TEST_PUBLIC_KEY}

none
no
none
no
no
no"
      VPS_INPUT_FD=3
      detect_existing_public_key() {
        return 1
      }
      has_active_swap() {
        return 1
      }
      main --dry-run
    ' 2>&1
  )"

  assert_contains "dry-run accepts a pasted public key" "$output" "SSH public key: SHA256:"
  assert_contains "dry-run captures no swap" "$output" "Swap: leave disabled"
}

test_root_and_restricted_detected_keys_are_rejected() {
  local detected key_home

  if validate_admin_user root > /dev/null 2>&1; then
    fail "root admin user is rejected"
  else
    pass "root admin user is rejected"
  fi

  key_home="$(mktemp -d "${TMPDIR:-/tmp}/vpsbuddy-key-home.XXXXXX")"
  mkdir -p "$key_home/.ssh"
  printf 'restrict %s\n' "$(cat tests/fixtures/id_ed25519.pub)" > "$key_home/.ssh/authorized_keys"
  detected="$(
    login_home() {
      printf '%s\n' "$key_home"
    }
    detect_existing_public_key || true
  )"
  rm -rf "$key_home"

  assert_eq "restricted authorized_keys line is not stripped and reused" "" "$detected"
}

run_stubbed_bootstrap() {
  local confirmation="$1"
  local public_key
  public_key="$(cat tests/fixtures/id_ed25519.pub)"

  TEST_CONFIRMATION="$confirmation" TEST_PUBLIC_KEY="$public_key" bash -c '
    set -Eeuo pipefail
    source lib/vpsbuddy.sh
    exec 3<<<"deploy
yes

none
no
none
no
no
no
yes
${TEST_CONFIRMATION}"
    VPS_INPUT_FD=3
    require_vps_root() {
      return 0
    }
    detect_existing_public_key() {
      printf "%s\n" "$TEST_PUBLIC_KEY"
    }
    has_active_swap() {
      return 1
    }
    run_server_phase() {
      printf "phase:%s\n" "$1"
    }
    tailnet_ipv4() {
      printf "100.64.0.10\n"
    }
    verify_prepared_admin() {
      printf "sudo-check:ok\n"
    }
    print_completion_summary() {
      printf "summary:%s\n" "$1"
    }
    run_bootstrap
  ' 2>&1
}

test_tailnet_confirmation_controls_hardening() {
  local paused_output completed_output

  paused_output="$(run_stubbed_bootstrap no)"
  assert_contains "prepare runs before Tailnet confirmation" "$paused_output" "phase:prepare"
  assert_contains "declined confirmation pauses setup" "$paused_output" "Setup paused. Public SSH remains open."
  assert_not_contains "declined confirmation does not harden" "$paused_output" "phase:harden"

  completed_output="$(run_stubbed_bootstrap yes)"
  assert_order "confirmed Tailnet login hardens after prepare" "$completed_output" "phase:prepare" "phase:harden"
  assert_contains "confirmed Tailnet login completes" "$completed_output" "summary:100.64.0.10"
}

test_legacy_ssh_orchestration_is_removed() {
  local source
  source="$(cat lib/vpsbuddy.sh)"

  assert_not_contains "host option removed" "$source" "vpsbuddy --host"
  assert_not_contains "login identity option removed" "$source" "--login-identity"
  assert_not_contains "remote prepare removed" "$source" "run_remote_prepare"
  assert_not_contains "remote harden removed" "$source" "run_remote_harden"
  assert_not_contains "SSH transport removed" "$source" "ssh -tt"
  assert_not_contains "SCP transport removed" "$source" "scp "
}

test_checkout_free_installer_downloads_and_runs_bundle() {
  local installer

  if [[ ! -f install.sh ]]; then
    fail "checkout-free installer exists"
    return
  fi

  installer="$(cat install.sh)"
  assert_contains "installer downloads one repository archive" "$installer" "codeload.github.com"
  assert_contains "installer bounds connect time" "$installer" "--connect-timeout 15"
  assert_contains "installer bounds total time" "$installer" "--max-time 120"
  assert_contains "installer extracts one archive" "$installer" "tar -xzf"
  assert_contains "installer downloads bootstrap entrypoint" "$installer" "bin/vpsbuddy"
  assert_contains "installer downloads bootstrap library" "$installer" "lib/vpsbuddy.sh"
  assert_contains "installer downloads helper templates" "$installer" "lib/templates/vpsbuddy-auth.sh"
  assert_contains "installer runs downloaded entrypoint" "$installer" "\"\$install_dir/bin/vpsbuddy\" \"\$@\""
}

test_checkout_free_installer_executes_downloaded_bundle() {
  local output public_key
  public_key="$(cat tests/fixtures/id_ed25519.pub)"

  output="$(
    TEST_REPO_ROOT="$ROOT_DIR" TEST_PUBLIC_KEY="$public_key" bash -c '
      set -Eeuo pipefail
      curl() {
        local argument archive_path="" expect_path=0 bundle_dir
        for argument in "$@"; do
          if [[ "$expect_path" == "1" ]]; then
            archive_path="$argument"
            expect_path=0
            continue
          fi
          if [[ "$argument" == "-o" ]]; then
            expect_path=1
          fi
        done

        bundle_dir="$(mktemp -d "${TMPDIR:-/tmp}/vpsbuddy-bundle.XXXXXX")"
        mkdir -p "$bundle_dir/repository/bin" "$bundle_dir/repository/lib/templates"
        cp "$TEST_REPO_ROOT/bin/vpsbuddy" "$bundle_dir/repository/bin/vpsbuddy"
        cp "$TEST_REPO_ROOT/lib/vpsbuddy.sh" "$bundle_dir/repository/lib/vpsbuddy.sh"
        cp "$TEST_REPO_ROOT/lib/templates/vpsbuddy-audit-prelude.sh" "$bundle_dir/repository/lib/templates/vpsbuddy-audit-prelude.sh"
        cp "$TEST_REPO_ROOT/lib/templates/vpsbuddy-auth.sh" "$bundle_dir/repository/lib/templates/vpsbuddy-auth.sh"
        tar -czf "$archive_path" -C "$bundle_dir" repository
        rm -rf "$bundle_dir"
      }
      export -f curl

      exec 3<<<"deploy
${TEST_PUBLIC_KEY}

none
no
none
no
no
no"
      export VPS_INPUT_FD=3
      export SUDO_USER=vpsbuddy-test-missing
      bash install.sh --dry-run
    ' 2>&1
  )"

  assert_contains "downloaded installer bundle runs" "$output" "Dry run complete; no server changes were made."

  if bash -c '
    set -Eeuo pipefail
    curl() {
      return 28
    }
    export -f curl
    bash install.sh --dry-run
  ' > /dev/null 2>&1; then
    fail "failed installer download stops before bootstrap"
  else
    pass "failed installer download stops before bootstrap"
  fi
}

test_generated_server_phase_keeps_security_controls() {
  local server_script
  server_script="$(generate_server_script)"

  if printf '%s\n' "$server_script" | bash -n; then
    pass "generated server phase parses"
  else
    fail "generated server phase parses"
  fi

  assert_contains "swap rejects symlinks" "$server_script" 'is a symlink; refusing to use it for swap'
  assert_contains "prepare keeps public SSH rule" "$server_script" 'configure_firewall prepare'
  assert_contains "hardening writes SSH policy" "$server_script" 'write_sshd_hardening'
  assert_contains "hardening uses the first SSH drop-in" "$server_script" '00-vpsbuddy-hardening.conf'
  assert_contains "hardening checks effective SSH settings" "$server_script" 'validate_effective_sshd_hardening'
  assert_contains "hardening writes sudo policy" "$server_script" "write_sudoers_policy \"\$full_sudo\""
  assert_contains "developer CLI setup remains" "$server_script" 'install_selected_clis'
  assert_contains "selected developer CLI failure stops prepare" "$server_script" 'one or more selected developer CLIs failed to install'
  assert_contains "admin command pipelines use pipefail" "$server_script" "bash --noprofile --norc -c \"set -o pipefail; \$command\""
  assert_contains "deselected CLI links are cleaned" "$server_script" 'remove_deselected_cli_links'
  assert_contains "CLI links refuse unmanaged replacement" "$server_script" 'refusing to replace unmanaged CLI command'
  assert_contains "CLI updater reports update failures" "$server_script" "exit \"\$failures\""
  assert_contains "Codex updater checks all supported paths" "$server_script" "\$home_dir/.local/bin/codex"
  assert_contains "automatic updates follow operator choice" "$server_script" 'vpsbuddy automatic OS updates disabled'
  assert_contains "automatic update opt-out removes timer" "$server_script" '/etc/systemd/system/vpsbuddy-os-update.timer'
  assert_contains "CLI update timer installs only after successful installs" "$server_script" 'install_agent_cli_update_timer'
  assert_contains \
    "CLI timer cleanup runs before installer choice" \
    "$server_script" \
    $'install_selected_clis() {\n  local failures=0 cli_id\n\n  remove_agent_cli_update_timer\n  remove_agent_auth_helper'
  assert_order \
    "CLI auth helper installs after failure check" \
    "$server_script" \
    'one or more selected developer CLIs failed to install' \
    'install_agent_auth_helper'
  assert_contains "old OS update timer is retired" "$server_script" 'systemctl disable --now vps-os-update.timer'
  assert_contains "old CLI update timer is retired" "$server_script" 'systemctl disable --now vps-agent-cli-update.timer'
  assert_contains "old apt update config is handled" "$server_script" '/etc/apt/apt.conf.d/20auto-upgrades'
  assert_contains "all old sudoers policies are retired" "$server_script" '/etc/sudoers.d/90-vps-bootstrap-*'
  assert_contains "old admin is read from the sudoers name" "$server_script" "legacy_user=\"\${legacy_sudoers##*/90-vps-bootstrap-}\""
  assert_not_contains "sudoers cleanup is not tied to the new admin" "$server_script" "90-vps-bootstrap-\$admin_user"
  assert_contains "old unsafe deploy helper is retired" "$server_script" '/usr/local/sbin/vps-agent-deploy'
  assert_contains "old SSH drop-in is retired" "$server_script" '/etc/ssh/sshd_config.d/00-vps-bootstrap-hardening.conf'
  assert_contains "old SSH policy is restored on validation failure" "$server_script" 'restored the prior SSH policy and left public SSH open'
  assert_contains "main SSH config is restored on validation failure" "$server_script" "mv \"\$include_backup\" /etc/ssh/sshd_config"
  assert_contains \
    "prepare retires old timers before installing swap" \
    "$server_script" \
    $'install_required_packages\n  remove_legacy_vps_bootstrap_timers\n  remove_deselected_cli_links\n  install_swap'
  assert_contains "root admin is rejected on the server" "$server_script" 'root cannot be the managed admin user'
  assert_contains "UID 0 aliases are rejected" "$server_script" 'managed admin user must not have UID 0'
  assert_contains "prepare disables existing Tailscale SSH" "$server_script" 'tailscale set --ssh=false'
  assert_not_contains "generic agent symlink is not created" "$server_script" "ln -sf \"\$home_dir/.grok/bin/agent\" /usr/local/bin/agent"
  assert_contains "managed generic agent symlink is retired" "$server_script" "[[ \"\$link_target\" == \"\$home_dir/.grok/bin/agent\" ]]"
  assert_order \
    "SSH policy is validated before public SSH closes" \
    "$server_script" \
    'write_sshd_hardening' \
    'configure_firewall harden'
  assert_order \
    "Tailscale SSH is disabled before prepare firewall" \
    "$server_script" \
    'disable_tailscale_ssh_for_verification' \
    'configure_firewall prepare'
}

test_server_config_prelude_carries_every_choice() {
  local prelude

  VPS_ADMIN_USER="ops"
  VPS_PUBLIC_KEY="$(cat tests/fixtures/id_ed25519.pub)"
  VPS_HOSTNAME="apps-1"
  VPS_ENABLE_TAILSCALE_SSH="0"
  VPS_WEB="1"
  VPS_SELECTED_CLIS="codex github claude"
  VPS_AUTOMATIC_UPDATES="1"
  VPS_FULL_SUDO="0"
  VPS_SWAP_ENABLED="1"
  VPS_SWAP_SIZE="8G"
  prelude="$(generate_server_config_prelude prepare)"

  assert_contains "phase prelude carries admin user" "$prelude" "admin_user=ops"
  assert_contains "phase prelude carries swap size" "$prelude" "swap_size=8G"
  assert_contains "phase prelude carries CLI choice" "$prelude" "selected_clis=codex\ github\ claude"
  assert_contains "phase prelude carries update choice" "$prelude" "automatic_updates=1"
}

test_selected_cli_prompt_accepts_formats
test_generated_selected_cli_behavior
test_generated_installer_failure_is_not_masked
test_generated_cli_link_cleanup
test_generated_cli_link_safety
test_generated_cli_updater_reports_failures
test_generated_auth_helper_honors_selected_clis
test_auth_helper_honors_selected_clis
test_configuration_has_no_hidden_operator_defaults
test_guided_dry_run_captures_operator_configuration
test_fallback_key_and_no_swap_are_captured
test_root_and_restricted_detected_keys_are_rejected
test_tailnet_confirmation_controls_hardening
test_legacy_ssh_orchestration_is_removed
test_checkout_free_installer_downloads_and_runs_bundle
test_checkout_free_installer_executes_downloaded_bundle
test_generated_server_phase_keeps_security_controls
test_server_config_prelude_carries_every_choice

if [[ "$failures" -gt 0 ]]; then
  printf '\n%s test(s) failed\n' "$failures" >&2
  exit 1
fi

printf '\nall guided on-VPS tests passed\n'
