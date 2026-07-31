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
    selected_clis_present=1
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
    selected_clis_present=1
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
    selected_clis_present=1
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

test_generated_missing_cli_selection_state() {
  local server_script server_fixture
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
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
    validate_selected_clis_server
  ' bash "$server_fixture"; then
    fail "missing CLI selection marker is rejected"
  else
    pass "missing CLI selection marker is rejected"
  fi

  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis_present=1
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    validate_selected_clis_server
  ' bash "$server_fixture"; then
    fail "missing CLI selection value is rejected"
  else
    pass "missing CLI selection value is rejected"
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
    selected_clis_present=1
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

test_generated_cli_installers_have_a_deadline() {
  local output server_fixture server_script
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-cli-timeout.XXXXXX)"
  printf '%s\n' "$server_script" | sed '/^case "\$phase" in/,$d' > "$server_fixture"

  output="$(
    bash -c '
      set -Eeuo pipefail
      phase=prepare
      admin_user=deploy
      public_key=ssh-ed25519
      requested_hostname=
      enable_tailscale_ssh=0
      web_enabled=1
      selected_clis=codex
      selected_clis_present=1
      automatic_updates=0
      full_sudo=0
      swap_enabled=0
      swap_size=
      source "$1"
      admin_home_dir() { printf "/home/deploy\n"; }
      run_as_admin() {
        printf "%s\n" "$2"
        return 124
      }
      if install_codex_cli; then
        exit 1
      fi
    ' bash "$server_fixture" 2>&1
  )"

  assert_contains "optional CLI installers stop after a fixed deadline" "$output" "--foreground --kill-after=30s 15m"
  assert_contains "Codex installer bounds its download time" "$server_script" "--connect-timeout 15 --max-time 120"
  assert_contains "timed-out Codex install is reported as optional failure" "$output" "Codex CLI installer command failed"
  rm -f "$server_fixture"
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
    selected_clis_present=1
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

  unmanaged_target="$link_dir/unmanaged-home/.grok/bin/grok"
  mkdir -p "$(dirname "$unmanaged_target")" "$link_dir/no-legacy"
  printf '#!/usr/bin/env bash\n' > "$unmanaged_target"
  chmod 755 "$unmanaged_target"
  ln -s "$unmanaged_target" "$link_dir/grok"

  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis=
    selected_clis_present=1
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    cli_link_dir="$2"
    cli_link_manifest="$3"
    legacy_sudoers_dir="$4"
    remove_deselected_cli_links
    [[ -L "$cli_link_dir/grok" ]]
    [[ "$(readlink "$cli_link_dir/grok")" == "$5" ]]
    [[ ! -e "$cli_link_manifest" ]]
  ' bash "$server_fixture" "$link_dir" "$manifest" "$link_dir/no-legacy" "$unmanaged_target"; then
    pass "deselection leaves an unmanaged CLI link untouched"
  else
    fail "deselection leaves an unmanaged CLI link untouched"
  fi

  rm -f "$link_dir/grok"

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
    selected_clis_present=1
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
    selected_clis_present=1
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
  ln -s "$home_dir/.grok/bin/grok" "$link_dir/grok"
  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis=
    selected_clis_present=1
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
    [[ -L "$cli_link_dir/grok" ]]
    [[ "$(readlink "$cli_link_dir/grok")" == "$3/.grok/bin/grok" ]]
    [[ ! -e "$cli_link_manifest" ]]
  ' bash "$server_fixture" "$link_dir" "$home_dir" 2> /dev/null; then
    pass "CLI link rejects an unmanaged link to the expected binary"
  else
    fail "CLI link rejects an unmanaged link to the expected binary"
  fi

  rm -f "$link_dir/grok"
  ln -s "$link_dir/grok" "$link_dir/self-grok"
  mv "$link_dir/self-grok" "$link_dir/grok"
  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis=
    selected_clis_present=1
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
    selected_clis_present=1
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

test_successful_rerun_deselects_managed_cli() {
  local server_script server_fixture home_dir link_dir
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  home_dir="$(mktemp -d /tmp/vpsbuddy-rerun-home.XXXXXX)"
  link_dir="$(mktemp -d /tmp/vpsbuddy-rerun-links.XXXXXX)"
  mkdir -p "$home_dir/.grok/bin"
  printf '#!/usr/bin/env bash\n' > "$home_dir/.grok/bin/grok"
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
    selected_clis_present=1
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    cli_link_dir="$2"
    cli_link_manifest="$2/manifest"
    home_dir="$3"
    timer_marker="$2/timer"
    auth_marker="$2/auth"
    admin_home_dir() {
      printf "%s\n" "$home_dir"
    }
    install_grok_cli() {
      link_admin_command "$home_dir" grok
    }
    remove_agent_cli_update_timer() {
      rm -f "$timer_marker"
    }
    remove_agent_auth_helper() {
      rm -f "$auth_marker"
    }
    install_agent_auth_helper() {
      : >"$auth_marker"
    }
    install_agent_cli_update_timer() {
      : >"$timer_marker"
    }
    print_selected_cli_versions() {
      :
    }
    install_selected_clis
    [[ -L "$cli_link_dir/grok" ]]
    [[ -s "$cli_link_manifest" ]]
    [[ -e "$timer_marker" && -e "$auth_marker" ]]

    selected_clis=
    install_selected_clis
    [[ ! -e "$cli_link_manifest" ]]
    [[ ! -L "$cli_link_dir/grok" ]]
    [[ -x "$home_dir/.grok/bin/grok" ]]
    [[ ! -e "$timer_marker" && ! -e "$auth_marker" ]]
  ' bash "$server_fixture" "$link_dir" "$home_dir"; then
    pass "successful rerun removes deselected managed CLI state"
  else
    fail "successful rerun removes deselected managed CLI state"
  fi

  rm -rf "$server_fixture" "$home_dir" "$link_dir"
}

test_github_cli_requires_managed_package() {
  local server_script server_fixture root_dir bin_dir record state gh_path
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  root_dir="$(mktemp -d /tmp/vpsbuddy-gh-root.XXXXXX)"
  bin_dir="$(mktemp -d /tmp/vpsbuddy-gh-bin.XXXXXX)"
  record="$(mktemp /tmp/vpsbuddy-gh-record.XXXXXX)"
  printf '%s\n' "$server_script" | sed '/^case "\$phase" in/,$d' > "$server_fixture"
  state="$root_dir/package-installed"
  gh_path="$root_dir/usr/bin/gh"
  mkdir -p "$(dirname "$gh_path")" "$root_dir/etc/apt/keyrings" "$root_dir/etc/apt/sources.list.d" "$root_dir/etc/apt/preferences.d"
  printf 'untrusted-key\n' > "$root_dir/etc/apt/keyrings/githubcli-archive-keyring.gpg"
  printf 'deb [arch=amd64] https://cli.github.com/packages stable main\n# signed-by=%s\n' \
    "$root_dir/etc/apt/keyrings/githubcli-archive-keyring.gpg" \
    > "$root_dir/etc/apt/sources.list.d/github-cli.list"
  printf '#!/usr/bin/env bash\nprintf "gh-package\\n"\n' > "$gh_path"
  chmod 755 "$gh_path"
  touch "$state"

  cat > "$bin_dir/dpkg-query" << 'DPKG_QUERY'
#!/usr/bin/env bash
if [[ ! -f "$VPSBUDDY_TEST_GH_STATE" ]]; then
  exit 1
fi
case "$1" in
  -W)
    printf 'install ok installed\n'
    ;;
  -S)
    printf 'gh: %s\n' "$2"
    ;;
esac
DPKG_QUERY
  cat > "$bin_dir/dpkg" << 'DPKG'
#!/usr/bin/env bash
printf 'amd64\n'
DPKG
  cat > "$bin_dir/apt-get" << 'APT_GET'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >>"$VPSBUDDY_TEST_RECORD"
if [[ "$*" == *"install -y --reinstall --allow-downgrades gh"* ]]; then
  touch "$VPSBUDDY_TEST_GH_STATE"
  mkdir -p "$(dirname "$VPSBUDDY_TEST_GH_BINARY")"
  printf '#!/usr/bin/env bash\nprintf "gh-package\\n"\n' >"$VPSBUDDY_TEST_GH_BINARY"
  chmod 755 "$VPSBUDDY_TEST_GH_BINARY"
fi
APT_GET
  cat > "$bin_dir/curl" << 'CURL'
#!/usr/bin/env bash
output=""
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    output="$2"
    shift 2
  else
    shift
  fi
done
printf 'curl\n' >>"$VPSBUDDY_TEST_RECORD"
printf '%s\n' "${VPSBUDDY_TEST_GH_KEY_CONTENT:-signed-key}" >"$output"
CURL
  cat > "$bin_dir/gpg" << 'GPG'
#!/usr/bin/env bash
key_file="${@: -1}"
grep -Fqx 'signed-key' "$key_file"
GPG
  chmod 755 "$bin_dir/dpkg-query" "$bin_dir/dpkg" "$bin_dir/apt-get" "$bin_dir/curl" "$bin_dir/gpg"

  if PATH="$bin_dir:$root_dir/path-bin:$PATH" \
    VPSBUDDY_TEST_RECORD="$record" \
    VPSBUDDY_TEST_GH_STATE="$state" \
    VPSBUDDY_TEST_GH_BINARY="$gh_path" \
    bash -c '
      set -Eeuo pipefail
      phase=prepare
      admin_user=deploy
      public_key=ssh-ed25519
      requested_hostname=
      enable_tailscale_ssh=0
      web_enabled=1
      selected_clis=github
      selected_clis_present=1
      automatic_updates=0
      full_sudo=0
      swap_enabled=0
      swap_size=
      source "$1"
      PKG_BACKEND=apt
      PKG_BIN=apt-get
      github_cli_binary="$2/usr/bin/gh"
      github_cli_apt_keyring="$2/etc/apt/keyrings/githubcli-archive-keyring.gpg"
      github_cli_apt_repo="$2/etc/apt/sources.list.d/github-cli.list"
      github_cli_apt_preferences="$2/etc/apt/preferences.d/github-cli"
      github_cli_rpm_repo="$2/etc/yum.repos.d/gh-cli.repo"
      if github_cli_apt_repository_configured; then
        exit 1
      fi
      install_github_cli
      grep -Fq "curl" "$VPSBUDDY_TEST_RECORD"
      grep -Fq "apt-get update" "$VPSBUDDY_TEST_RECORD"
      grep -Fq "apt-get install -y --reinstall --allow-downgrades gh" "$VPSBUDDY_TEST_RECORD"
      github_cli_package_is_managed
      grep -Fqx "Pin-Priority: 1001" "$github_cli_apt_preferences"

      old_key="$(cat "$github_cli_apt_keyring")"
      export VPSBUDDY_TEST_GH_KEY_CONTENT=invalid-key
      : >"$VPSBUDDY_TEST_RECORD"
      if install_github_cli; then
        exit 1
      fi
      [[ "$(cat "$github_cli_apt_keyring")" == "$old_key" ]]
      if grep -Fq "apt-get update" "$VPSBUDDY_TEST_RECORD"; then
        exit 1
      fi
      unset VPSBUDDY_TEST_GH_KEY_CONTENT

      : >"$VPSBUDDY_TEST_RECORD"
      printf "%s\n" "#!/usr/bin/env bash" "exit 1" >"$github_cli_binary"
      install_github_cli
      grep -Fq "apt-get install -y --reinstall --allow-downgrades gh" "$VPSBUDDY_TEST_RECORD"
      : >"$VPSBUDDY_TEST_RECORD"
      rm -f "$VPSBUDDY_TEST_GH_STATE" "$github_cli_binary" "$github_cli_apt_keyring" "$github_cli_apt_repo" "$github_cli_apt_preferences"
      mkdir -p "$2/path-bin"
      printf "%s\n" "#!/usr/bin/env bash" >"$2/path-bin/gh"
      chmod 755 "$2/path-bin/gh"
      if ! command -v gh | grep -Fq "$2/path-bin/gh"; then
        exit 1
      fi
      if admin_command_path "$2" github; then
        exit 1
      fi
      install_github_cli
      [[ "$(admin_command_path "$2" github)" == "$github_cli_binary" ]]
      grep -Fq "curl" "$VPSBUDDY_TEST_RECORD"
      grep -Fq "apt-get update" "$VPSBUDDY_TEST_RECORD"
      grep -Fq "apt-get install -y --reinstall --allow-downgrades gh" "$VPSBUDDY_TEST_RECORD"
      github_cli_package_is_managed
    ' bash "$server_fixture" "$root_dir"; then
    pass "GitHub CLI uses the signed package path instead of PATH"
  else
    fail "GitHub CLI uses the signed package path instead of PATH"
  fi

  rm -rf "$server_fixture" "$root_dir" "$bin_dir" "$record"
}

test_github_cli_rpm_package_path() {
  local server_script server_fixture root_dir bin_dir record state gh_path
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  root_dir="$(mktemp -d /tmp/vpsbuddy-gh-rpm-root.XXXXXX)"
  bin_dir="$(mktemp -d /tmp/vpsbuddy-gh-rpm-bin.XXXXXX)"
  record="$(mktemp /tmp/vpsbuddy-gh-rpm-record.XXXXXX)"
  printf '%s\n' "$server_script" | sed '/^case "\$phase" in/,$d' > "$server_fixture"

  state="$root_dir/package-installed"
  gh_path="$root_dir/usr/bin/gh"
  mkdir -p "$(dirname "$gh_path")" "$root_dir/etc/yum.repos.d"
  cat > "$root_dir/rpm-source.repo" << 'REPO'
[gh-cli]
name=packages for the GitHub CLI
baseurl=https://cli.github.com/packages/rpm
enabled=1
gpgcheck=1
gpgkey=https://cli.github.com/packages/githubcli-archive-keyring.asc
REPO
  cat > "$root_dir/etc/yum.repos.d/gh-cli.repo" << 'REPO'
[gh-cli]
baseurl=https://cli.github.com/packages/rpm
enabled=1
gpgcheck=0

[other]
gpgcheck=1
gpgkey=https://cli.github.com/packages/githubcli-archive-keyring.asc
REPO
  printf '#!/usr/bin/env bash\nprintf "gh-rpm\\n"\n' > "$gh_path"
  chmod 755 "$gh_path"
  touch "$state"

  cat > "$bin_dir/rpm" << 'RPM'
#!/usr/bin/env bash
case "$1" in
  -q)
    [[ "$2" == gh && -f "$VPSBUDDY_TEST_RPM_STATE" ]]
    ;;
  -qf)
    [[ -f "$VPSBUDDY_TEST_RPM_STATE" ]] || exit 1
    printf 'gh-2.0-1.x86_64\n'
    ;;
  *)
    exit 1
    ;;
esac
RPM
  cat > "$bin_dir/dnf" << 'DNF'
#!/usr/bin/env bash
printf 'dnf %s\n' "$*" >>"$VPSBUDDY_TEST_RECORD"
if [[ "$*" == *"--enablerepo=gh-cli"* && "$*" == *"-y gh"* ]]; then
  touch "$VPSBUDDY_TEST_RPM_STATE"
  mkdir -p "$(dirname "$VPSBUDDY_TEST_RPM_BINARY")"
  printf '#!/usr/bin/env bash\nprintf "gh-rpm\\n"\n' >"$VPSBUDDY_TEST_RPM_BINARY"
  chmod 755 "$VPSBUDDY_TEST_RPM_BINARY"
fi
DNF
  cat > "$bin_dir/curl" << 'CURL'
#!/usr/bin/env bash
output=""
while [[ "$#" -gt 0 ]]; do
  if [[ "$1" == "-o" ]]; then
    output="$2"
    shift 2
  else
    shift
  fi
done
printf 'curl\n' >>"$VPSBUDDY_TEST_RECORD"
cat "$VPSBUDDY_TEST_RPM_SOURCE" >"$output"
CURL
  chmod 755 "$bin_dir/rpm" "$bin_dir/dnf" "$bin_dir/curl"

  if PATH="$bin_dir:$PATH" \
    VPSBUDDY_TEST_RECORD="$record" \
    VPSBUDDY_TEST_RPM_STATE="$state" \
    VPSBUDDY_TEST_RPM_BINARY="$gh_path" \
    VPSBUDDY_TEST_RPM_SOURCE="$root_dir/rpm-source.repo" \
    bash -c '
      set -Eeuo pipefail
      phase=prepare
      admin_user=deploy
      public_key=ssh-ed25519
      requested_hostname=
      enable_tailscale_ssh=0
      web_enabled=1
      selected_clis=github
      selected_clis_present=1
      automatic_updates=0
      full_sudo=0
      swap_enabled=0
      swap_size=
      source "$1"
      PKG_BACKEND=dnf
      PKG_BIN=dnf
      github_cli_binary="$2/usr/bin/gh"
      github_cli_rpm_repo="$2/etc/yum.repos.d/gh-cli.repo"
      github_cli_apt_keyring="$2/etc/apt/keyrings/githubcli-archive-keyring.gpg"
      github_cli_apt_repo="$2/etc/apt/sources.list.d/github-cli.list"
      github_cli_apt_preferences="$2/etc/apt/preferences.d/github-cli"
      if github_cli_rpm_repository_configured; then
        exit 1
      fi
      install_github_cli
      grep -Fq "curl" "$VPSBUDDY_TEST_RECORD"
      grep -Fq "dnf --disablerepo=* --enablerepo=gh-cli install -y gh" "$VPSBUDDY_TEST_RECORD"
      grep -Fq "dnf --disablerepo=* --enablerepo=gh-cli reinstall -y gh" "$VPSBUDDY_TEST_RECORD"
      github_cli_package_is_managed
      : >"$VPSBUDDY_TEST_RECORD"

      printf "%s\n" "#!/usr/bin/env bash" "exit 1" >"$github_cli_binary"
      install_github_cli
      grep -Fq "dnf --disablerepo=* --enablerepo=gh-cli install -y gh" "$VPSBUDDY_TEST_RECORD"
      : >"$VPSBUDDY_TEST_RECORD"

      rm -f "$VPSBUDDY_TEST_RPM_STATE" "$github_cli_binary" "$github_cli_rpm_repo"
      mkdir -p "$2/path-bin"
      printf "%s\n" "#!/usr/bin/env bash" >"$2/path-bin/gh"
      chmod 755 "$2/path-bin/gh"
      if admin_command_path "$2" github; then
        exit 1
      fi
      install_github_cli
      [[ "$(admin_command_path "$2" github)" == "$github_cli_binary" ]]
      grep -Fq "curl" "$VPSBUDDY_TEST_RECORD"
      grep -Fq "dnf --disablerepo=* --enablerepo=gh-cli install -y gh" "$VPSBUDDY_TEST_RECORD"
      github_cli_package_is_managed

      : >"$VPSBUDDY_TEST_RECORD"
      printf "%s\n" \
        "[gh-cli]" \
        "baseurl=https://cli.github.com/packages/rpm" \
        "enabled=1" \
        "gpgcheck=1" \
        "gpgkey=https://cli.github.com/packages/githubcli-archive-keyring.asc" \
        "" \
        "[unsigned-extra]" \
        "baseurl=https://example.invalid/packages" \
        "enabled=1" \
        "gpgcheck=0" \
        >"$VPSBUDDY_TEST_RPM_SOURCE"
      if install_github_cli; then
        exit 1
      fi
      if grep -Fq "dnf --disablerepo=* --enablerepo=gh-cli install -y gh" "$VPSBUDDY_TEST_RECORD"; then
        exit 1
      fi
    ' bash "$server_fixture" "$root_dir"; then
    pass "GitHub CLI uses the signed RPM package path"
  else
    fail "GitHub CLI uses the signed RPM package path"
  fi

  rm -rf "$server_fixture" "$root_dir" "$bin_dir" "$record"
}
test_selected_cli_install_dispatch() {
  local server_script server_fixture home_dir link_dir bin_dir record output expected
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  home_dir="$(mktemp -d /tmp/vpsbuddy-cli-dispatch-home.XXXXXX)"
  link_dir="$(mktemp -d /tmp/vpsbuddy-cli-dispatch-links.XXXXXX)"
  record="$(mktemp /tmp/vpsbuddy-cli-dispatch-record.XXXXXX)"
  # installer fixture
  bin_dir="$(mktemp -d /tmp/vpsbuddy-cli-dispatch-bin.XXXXXX)"
  cat > "$bin_dir/curl" << 'FAKE_CURL'
#!/usr/bin/env bash
printf 'curl %s\n' "$*" >>"$VPSBUDDY_TEST_RECORD"
case "$*" in
  *chatgpt.com/codex/install.sh*)
    target="$HOME/.codex/bin/codex"
    output_file="${!#}"
    printf 'mkdir -p "%s"\nprintf "exit 0\\n" >"%s"\nchmod 755 "%s"\n' \
      "$(dirname "$target")" "$target" "$target" >"$output_file"
    exit 0
    ;;
  *x.ai/cli/install.sh*) target="$HOME/.grok/bin/grok" ;;
  *pi.dev/install.sh*) target="$HOME/.local/bin/pi" ;;
  *opencode.ai/install*) target="$HOME/.opencode/bin/opencode" ;;
  *ampcode.com/install.sh*) target="$HOME/.amp/bin/amp" ;;
  *app.factory.ai/cli*) target="$HOME/.local/bin/droid" ;;
  *claude.ai/install.sh*) target="$HOME/.local/bin/claude" ;;
  *) exit 1 ;;
esac
printf 'mkdir -p "%s"\nprintf "exit 0\\n" >"%s"\nchmod 755 "%s"\n' \
  "$(dirname "$target")" "$target" "$target"
FAKE_CURL
  chmod 755 "$bin_dir/curl"
  printf '%s\n' "$server_script" | sed '/^case "\$phase" in/,$d' > "$server_fixture"

  if VPSBUDDY_TEST_RECORD="$record" bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis="codex grok github pi opencode amp droid claude"
    selected_clis_present=1
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    test_home="$3"
    test_bin="$4"
    cli_link_dir="$2/bin"
    cli_link_manifest="$2/manifest"
    admin_home_dir() {
      printf "%s\n" "$test_home"
    }
    run_as_admin() {
      local home_dir="$1"
      local command="$2"
      local admin_path
      admin_path="$test_bin:$home_dir/.local/share/pi-node/current/bin:$home_dir/.codex/bin:$home_dir/.grok/bin:$home_dir/.opencode/bin:$home_dir/.amp/bin:$home_dir/.local/bin:$home_dir/bin:/usr/bin:/bin"
      printf "%s\n" "$command" >>"$VPSBUDDY_TEST_RECORD"
      HOME="$home_dir" PATH="$admin_path" /bin/bash --noprofile --norc -c "set -o pipefail; $command"
    }
    install_github_cli() {
      printf "github-package-manager\n" >>"$VPSBUDDY_TEST_RECORD"
    }
    install_droid_package() {
      printf "xdg-utils\n" >>"$VPSBUDDY_TEST_RECORD"
    }
    remove_agent_cli_update_timer() {
      :
    }
    remove_agent_auth_helper() {
      :
    }
    remove_deselected_cli_links() {
      :
    }
    install_agent_auth_helper() {
      :
    }
    install_agent_cli_update_timer() {
      :
    }
    has_cli_updates() {
      return 1
    }
    print_selected_cli_versions() {
      :
    }
    install_selected_clis
  ' bash "$server_fixture" "$link_dir" "$home_dir" "$bin_dir"; then
    output="$(cat "$record")"
    for expected in \
      "curl -fsSL --retry 3 --retry-delay 2 --retry-connrefused --connect-timeout 15 --max-time 120 https://chatgpt.com/codex/install.sh" \
      "https://x.ai/cli/install.sh" \
      "github-package-manager" \
      "https://pi.dev/install.sh" \
      "https://opencode.ai/install" \
      "mkdir -p \"\$HOME/.local/bin\"" \
      "https://ampcode.com/install.sh" \
      "xdg-utils" \
      "https://app.factory.ai/cli" \
      "https://claude.ai/install.sh"; do
      assert_contains "selected CLI dispatch runs $expected" "$output" "$expected"
    done

    for expected in \
      "codex|$home_dir/.codex/bin/codex" \
      "grok|$home_dir/.grok/bin/grok" \
      "pi|$home_dir/.local/bin/pi" \
      "opencode|$home_dir/.opencode/bin/opencode" \
      "amp|$home_dir/.amp/bin/amp" \
      "droid|$home_dir/.local/bin/droid" \
      "claude|$home_dir/.local/bin/claude"; do
      IFS='|' read -r cli_id cli_path <<< "$expected"
      if [[ -x "$cli_path" ]] && [[ -L "$link_dir/bin/$cli_id" ]] &&
        [[ "$(readlink "$link_dir/bin/$cli_id")" == "$cli_path" ]]; then
        pass "selected CLI installer creates and links $cli_id at $cli_path"
      else
        fail "selected CLI installer creates and links $cli_id at $cli_path"
      fi
    done
  else
    fail "selected CLI installer dispatch runs all eight selections"
  fi

  rm -rf "$server_fixture" "$home_dir" "$link_dir" "$bin_dir" "$record"
}

test_generated_cli_candidate_paths() {
  local server_script server_fixture home_dir
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  home_dir="$(mktemp -d /tmp/vpsbuddy-cli-candidates.XXXXXX)"
  printf '%s\n' "$server_script" | sed '/^case "\$phase" in/,$d' > "$server_fixture"

  if bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis="codex amp"
    selected_clis_present=1
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    home_dir="$2"

    make_candidate() {
      local path="$1"
      mkdir -p "$(dirname "$path")"
      printf "#!/usr/bin/env bash\nexit 0\n" >"$path"
      chmod 755 "$path"
    }

    for candidate in \
      "$home_dir/.codex/bin/codex" \
      "$home_dir/.local/bin/codex" \
      "$home_dir/bin/codex"; do
      make_candidate "$candidate"
      [[ "$(admin_command_path "$home_dir" codex)" == "$candidate" ]]
      rm -f "$candidate"
    done

    for candidate in \
      "$home_dir/.local/bin/amp" \
      "$home_dir/.amp/bin/amp"; do
      make_candidate "$candidate"
      [[ "$(admin_command_path "$home_dir" amp)" == "$candidate" ]]
      rm -f "$candidate"
    done

    run_as_admin() {
      printf "/usr/bin/codex\n"
    }
    if admin_command_path "$home_dir" codex; then
      exit 1
    fi
  ' bash "$server_fixture" "$home_dir"; then
    pass "generated CLI path lookup executes every Codex and Amp candidate"
  else
    fail "generated CLI path lookup executes every Codex and Amp candidate"
  fi

  rm -rf "$server_fixture" "$home_dir"
}

test_droid_only_installs_xdg_utils() {
  local server_script server_fixture home_dir link_dir bin_dir record output xdg_state
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  home_dir="$(mktemp -d /tmp/vpsbuddy-droid-home.XXXXXX)"
  link_dir="$(mktemp -d /tmp/vpsbuddy-droid-links.XXXXXX)"
  bin_dir="$(mktemp -d /tmp/vpsbuddy-droid-bin.XXXXXX)"
  record="$(mktemp /tmp/vpsbuddy-droid-record.XXXXXX)"
  xdg_state="$(mktemp /tmp/vpsbuddy-droid-xdg-state.XXXXXX)"
  printf '%s\n' "$server_script" | sed '/^case "\$phase" in/,$d' > "$server_fixture"

  cat > "$bin_dir/apt-get" << 'APT_GET'
#!/usr/bin/env bash
printf 'apt-get %s\n' "$*" >>"$VPSBUDDY_TEST_RECORD"
[[ "$*" == "install -y xdg-utils" ]] || exit 1
touch "$VPSBUDDY_TEST_XDG_STATE"
APT_GET
  cat > "$bin_dir/curl" << 'CURL'
#!/usr/bin/env bash
[[ "$*" == *"https://app.factory.ai/cli"* ]] || exit 1
printf 'mkdir -p "%s"\nprintf "exit 0\\n" >"%s"\nchmod 755 "%s"\n' \
  "$HOME/.local/bin" "$HOME/.local/bin/droid" "$HOME/.local/bin/droid"
CURL
  chmod 755 "$bin_dir/apt-get" "$bin_dir/curl"

  if PATH="$bin_dir:$PATH" VPSBUDDY_TEST_RECORD="$record" VPSBUDDY_TEST_XDG_STATE="$xdg_state" bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis=droid
    selected_clis_present=1
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    PKG_BACKEND=apt
    PKG_BIN=apt-get
    test_home="$3"
    test_bin="$4"
    cli_link_dir="$2/bin"
    cli_link_manifest="$2/manifest"
    admin_home_dir() {
      printf "%s\n" "$test_home"
    }
    run_as_admin() {
      local home_dir="$1"
      local command="$2"
      local admin_path
      admin_path="$test_bin:$home_dir/.local/share/pi-node/current/bin:$home_dir/.codex/bin:$home_dir/.grok/bin:$home_dir/.opencode/bin:$home_dir/.amp/bin:$home_dir/.local/bin:$home_dir/bin:/usr/bin:/bin"
      printf "%s\n" "$command" >>"$VPSBUDDY_TEST_RECORD"
      HOME="$home_dir" PATH="$admin_path" /bin/bash --noprofile --norc -c "set -o pipefail; $command"
    }
    remove_agent_cli_update_timer() {
      :
    }
    remove_agent_auth_helper() {
      :
    }
    remove_deselected_cli_links() {
      :
    }
    install_agent_auth_helper() {
      :
    }
    has_cli_updates() {
      return 1
    }
    print_selected_cli_versions() {
      :
    }
    install_selected_clis
  ' bash "$server_fixture" "$link_dir" "$home_dir" "$bin_dir"; then
    output="$(cat "$record")"
    assert_contains "Droid-only selection installs xdg-utils" "$output" "apt-get install -y xdg-utils"
    assert_contains "Droid-only selection runs the Factory installer" "$output" "https://app.factory.ai/cli"
    assert_not_contains "Droid-only selection skips Pi installer" "$output" "pi.dev/install.sh"
    [[ -f "$xdg_state" ]]
    [[ -x "$home_dir/.local/bin/droid" ]]
    [[ -L "$link_dir/bin/droid" ]]
    [[ "$(readlink "$link_dir/bin/droid")" == "$home_dir/.local/bin/droid" ]]
    pass "Droid-only selection executes xdg-utils and Factory setup"
  else
    fail "Droid-only selection executes xdg-utils and Factory setup"
  fi

  rm -rf "$server_fixture" "$home_dir" "$link_dir" "$bin_dir" "$record" "$xdg_state"
}

test_generated_pi_node_precedence() {
  local server_script server_fixture home_dir system_bin bin_dir link_dir sbin_dir systemd_dir record shell_record
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  home_dir="$(mktemp -d /tmp/vpsbuddy-pi-home.XXXXXX)"
  system_bin="$(mktemp -d /tmp/vpsbuddy-system-node.XXXXXX)"
  bin_dir="$(mktemp -d /tmp/vpsbuddy-pi-bin.XXXXXX)"
  link_dir="$(mktemp -d /tmp/vpsbuddy-pi-links.XXXXXX)"
  sbin_dir="$(mktemp -d /tmp/vpsbuddy-pi-sbin.XXXXXX)"
  systemd_dir="$(mktemp -d /tmp/vpsbuddy-pi-systemd.XXXXXX)"
  record="$home_dir/pi-node-record"
  shell_record="$home_dir/user-shell-record"
  mkdir -p "$home_dir/.local/share/pi-node/current/bin" "$home_dir/.local/bin" "$home_dir/.grok/bin"

  printf '#!/bin/bash\nprintf "pi-private-node\n"\n' \
    > "$home_dir/.local/share/pi-node/current/bin/node"
  printf '#!/bin/bash\nprintf "system-node\n"\n' > "$system_bin/node"
  chmod 755 "$home_dir/.local/share/pi-node/current/bin/node" "$system_bin/node"

  cat > "$home_dir/.local/bin/pi" << 'PI'
#!/bin/bash
printf '%s %s\n' "$*" "$(node --version)" >>"$HOME/pi-node-record"
PI
  chmod 755 "$home_dir/.local/bin/pi"
  cat > "$home_dir/.grok/bin/grok" << 'GROK'
#!/bin/bash
printf 'managed-grok %s\n' "$*" >>"$HOME/pi-node-record"
GROK
  cat > "$system_bin/grok" << 'SYSTEM_GROK'
#!/bin/bash
printf 'system-grok %s\n' "$*" >>"$HOME/pi-node-record"
SYSTEM_GROK
  chmod 755 "$home_dir/.grok/bin/grok" "$system_bin/grok"
  cat > "$home_dir/.local/bin/bash" << 'USER_BASH'
#!/bin/bash
printf 'user bash was selected\n' >"$HOME/user-shell-record"
exit 99
USER_BASH
  chmod 755 "$home_dir/.local/bin/bash"

  cat > "$bin_dir/sudo" << 'FAKE_SUDO'
#!/bin/bash
if [[ "$1" == "-H" ]]; then
  shift
fi
if [[ "$1" == "-u" ]]; then
  shift 2
fi
exec "$@"
FAKE_SUDO
  chmod 755 "$bin_dir/sudo"

  sed \
    -e "s|:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:|:$system_bin:/usr/bin:/bin:|g" \
    -e "s|/usr/local/sbin|$sbin_dir|g" \
    -e "s|/etc/systemd/system|$systemd_dir|g" \
    -e '/^case "\$phase" in/,$d' \
    < <(printf '%s\n' "$server_script") > "$server_fixture"

  if PATH="$bin_dir:$PATH" VPSBUDDY_TEST_RECORD="$record" bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=1
    selected_clis="pi grok"
    selected_clis_present=1
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    test_home="$2"
    home_dir="$test_home"
    cli_link_dir="$3"
    cli_link_manifest="$3/manifest"
    admin_home_dir() {
      printf "%s\n" "$test_home"
    }
    systemctl() {
      return 0
    }
    run_admin_cli "$home_dir" pi --version
    run_admin_cli "$home_dir" pi update --self
    run_admin_cli "$home_dir" grok update
    install_agent_cli_update_timer
    PATH="$4:$PATH" bash "$5/vpsbuddy-cli-update"
  ' bash "$server_fixture" "$home_dir" "$link_dir" "$system_bin" "$sbin_dir"; then
    assert_contains "Pi version and update checks use private Node" "$(cat "$record")" "pi-private-node"
    assert_not_contains "Pi checks do not use system Node" "$(cat "$record")" "system-node"
    assert_contains "managed CLI path wins over a system collision" "$(cat "$record")" "managed-grok update"
    assert_not_contains "system CLI collision is not executed" "$(cat "$record")" "system-grok"
    if grep -F "update --self" "$record" | grep -Fq "pi-private-node"; then
      pass "Pi updater uses the private Node"
    else
      fail "Pi updater uses the private Node"
    fi
    if [[ ! -e "$shell_record" ]]; then
      pass "system shell stays ahead of user CLI directories"
    else
      fail "system shell stays ahead of user CLI directories"
    fi
  else
    fail "Pi version and update checks use private Node"
  fi

  rm -rf "$server_fixture" "$home_dir" "$system_bin" "$bin_dir" "$link_dir" "$sbin_dir" "$systemd_dir" "$record"
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
    selected_clis_present=1
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

test_generated_cli_updater_refuses_unmanaged_link() {
  local server_script server_fixture sbin_dir systemd_dir link_dir home_dir bin_dir record
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  sbin_dir="$(mktemp -d /tmp/vpsbuddy-cli-updater-unmanaged-sbin.XXXXXX)"
  systemd_dir="$(mktemp -d /tmp/vpsbuddy-cli-updater-unmanaged-systemd.XXXXXX)"
  link_dir="$(mktemp -d /tmp/vpsbuddy-cli-updater-unmanaged-links.XXXXXX)"
  home_dir="$(mktemp -d /tmp/vpsbuddy-cli-updater-unmanaged-home.XXXXXX)"
  bin_dir="$(mktemp -d /tmp/vpsbuddy-cli-updater-unmanaged-bin.XXXXXX)"
  record="$(mktemp /tmp/vpsbuddy-cli-updater-unmanaged-record.XXXXXX)"
  mkdir -p "$home_dir/.grok/bin"
  printf '#!/usr/bin/env bash\nexit 0\n' > "$home_dir/.grok/bin/grok"
  chmod 755 "$home_dir/.grok/bin/grok"
  ln -s "$home_dir/.grok/bin/grok" "$link_dir/grok"
  cat > "$bin_dir/sudo" << 'FAKE_SUDO'
#!/usr/bin/env bash
shift 12
printf '%s\n' "$1" >>"$VPSBUDDY_TEST_RECORD"
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
    selected_clis_present=1
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
    [[ "$(readlink "$cli_link_dir/grok")" == "$3/.grok/bin/grok" ]]
    [[ ! -e "$cli_link_manifest" ]]
    grep -Fq "grok update" "$5"
  ' bash "$server_fixture" "$link_dir" "$home_dir" "$bin_dir" "$record" "$sbin_dir"; then
    pass "generated CLI updater refuses an unmanaged link"
  else
    fail "generated CLI updater refuses an unmanaged link"
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
    selected_clis_present=1
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    source "$1"
    install_agent_auth_helper
    sed "s|/usr/bin/gh|$3/gh|g" "$2" >"$2.rewritten"
    mv "$2.rewritten" "$2"
  ' bash "$server_fixture" "$auth_path" "$bin_dir"; then
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
  local bin_dir record empty_path auth_path output cli_id expected
  bin_dir="$(mktemp -d /tmp/vpsbuddy-auth-bin.XXXXXX)"
  record="$(mktemp /tmp/vpsbuddy-auth-record.XXXXXX)"
  empty_path="$(mktemp -d /tmp/vpsbuddy-auth-empty.XXXXXX)"
  auth_path="$(mktemp /tmp/vpsbuddy-auth-fixture.XXXXXX)"
  sed "s|/usr/bin/gh|$bin_dir/gh|g" lib/templates/vpsbuddy-auth.sh > "$auth_path"
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
      bash "$auth_path" --all 2>&1
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
    bash "$auth_path" --codex > /dev/null 2>&1; then
    fail "auth helper rejects an unselected CLI"
  else
    pass "auth helper rejects an unselected CLI"
  fi

  for cli_id in pi amp droid; do
    if selected_clis="$cli_id" PATH="$empty_path" /bin/bash "$auth_path" --status > /dev/null 2>&1; then
      fail "auth status rejects missing $cli_id"
    else
      pass "auth status rejects missing $cli_id"
    fi
  done

  rm -rf "$bin_dir" "$record" "$empty_path" "$auth_path"
}

test_configuration_has_no_hidden_operator_defaults() {
  reset_config

  assert_eq "admin user has no default" "" "$VPS_ADMIN_USER"
  assert_eq "swap choice has no default" "" "$VPS_SWAP_ENABLED"
  assert_eq "swap size has no default" "" "$VPS_SWAP_SIZE"
  assert_eq "web exposure has no default" "" "$VPS_WEB"
  assert_eq "developer CLI choice has no default" "" "$VPS_SELECTED_CLIS"
  assert_eq "developer CLI selection marker has no default" "" "$VPS_SELECTED_CLIS_PRESENT"
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

test_login_home_uses_local_passwd_by_uid() {
  local actual expected
  expected="$(awk -F: '$3 == 0 { print $6; exit }' /etc/passwd)"
  actual="$(
    unset SUDO_UID SUDO_USER
    # shellcheck disable=SC2317,SC2329
    getent() { return 97; }
    id() {
      [[ "${1:-}" == "-u" ]] || return 98
      printf '0\n'
    }
    login_home
  )"

  assert_eq "login home avoids NSS name lookup" "$expected" "$actual"
}

test_non_regular_authorized_keys_does_not_block_recovery() {
  local key_home output public_key timeout_bin
  key_home="$(mktemp -d "${TMPDIR:-/tmp}/vpsbuddy-key-fifo.XXXXXX")"
  public_key="$(cat tests/fixtures/id_ed25519.pub)"
  timeout_bin="$(command -v timeout || command -v gtimeout || true)"
  mkdir -p "$key_home/.ssh"
  mkfifo "$key_home/.ssh/authorized_keys"

  if [[ -z "$timeout_bin" ]]; then
    printf 'ok - non-regular authorized_keys check skipped: timeout unavailable\n'
    unlink "$key_home/.ssh/authorized_keys"
    rm -rf "$key_home"
    return
  fi

  # The inner shell expands the test fixture variables.
  # shellcheck disable=SC2016
  if output="$(
    TEST_KEY_HOME="$key_home" TEST_PUBLIC_KEY="$public_key" "$timeout_bin" 2 bash -c '
      set -Eeuo pipefail
      source lib/vpsbuddy.sh
      exec 3<<<"ubuntu
${TEST_PUBLIC_KEY}

none
no
none
no
no
no"
      VPS_INPUT_FD=3
      login_home() { printf "%s\n" "$TEST_KEY_HOME"; }
      has_active_swap() { return 1; }
      collect_configuration
      printf "admin:%s\n" "$VPS_ADMIN_USER"
      printf "key:%s\n" "$(public_key_fingerprint "$VPS_PUBLIC_KEY")"
    ' 2>&1
  )"; then
    assert_contains "non-regular authorized_keys falls back to pasted key" "$output" "Paste the SSH public key to install"
    assert_contains "guided recovery continues after non-regular key state" "$output" "admin:ubuntu"
  else
    fail "non-regular authorized_keys does not block guided recovery: $output"
  fi

  unlink "$key_home/.ssh/authorized_keys"
  rm -rf "$key_home"
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
    save_resume_plan() { :; }
    write_bootstrap_status() { :; }
    read_failed_cli_state() { VPS_FAILED_CLIS=; }
    run_bootstrap
  ' 2>&1
}

test_prepare_installer_failure_still_reaches_hardening() {
  local server_script server_fixture record public_key output state_dir
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  record="$(mktemp /tmp/vpsbuddy-prepare-failure-record.XXXXXX)"
  state_dir="$(mktemp -d /tmp/vpsbuddy-prepare-failure-state.XXXXXX)"
  public_key="$(cat tests/fixtures/id_ed25519.pub)"
  printf '%s\n' "$server_script" | sed '/^case "\$phase" in/,$d' > "$server_fixture"

  if TEST_PUBLIC_KEY="$public_key" \
    TEST_SERVER_FIXTURE="$server_fixture" \
    TEST_RECORD="$record" \
    TEST_STATE="$state_dir" \
    bash -c '
      set -Eeuo pipefail
      source lib/vpsbuddy.sh
      VPS_STATE_DIR="$TEST_STATE"
      exec 3<<<"deploy
yes

none
no
2
no
no
no
yes
yes"
      VPS_INPUT_FD=3
      require_vps_root() {
        :
      }
      save_resume_plan() { :; }
      write_bootstrap_status() { :; }
      detect_existing_public_key() {
        printf "%s\n" "$TEST_PUBLIC_KEY"
      }
      verify_prepared_admin() { :; }
      tailnet_ipv4() { printf "100.64.0.10\n"; }
      run_server_phase() {
        local phase_name="$1"
        printf "phase:%s\n" "$phase_name" >>"$TEST_RECORD"
        if [[ "$phase_name" != prepare ]]; then
          return 0
        fi

        (
          phase=prepare
          admin_user="$VPS_ADMIN_USER"
          public_key="$VPS_PUBLIC_KEY"
          requested_hostname="$VPS_HOSTNAME"
          enable_tailscale_ssh="$VPS_ENABLE_TAILSCALE_SSH"
          web_enabled="$VPS_WEB"
          selected_clis="$VPS_SELECTED_CLIS"
          selected_clis_present="$VPS_SELECTED_CLIS_PRESENT"
          automatic_updates="$VPS_AUTOMATIC_UPDATES"
          full_sudo="$VPS_FULL_SUDO"
          swap_enabled="$VPS_SWAP_ENABLED"
          swap_size="$VPS_SWAP_SIZE"
          bootstrap_state_dir="$TEST_STATE"
          source "$TEST_SERVER_FIXTURE"
          require_root() {
            :
          }
          select_platform() {
            PKG_BACKEND=apt
            PKG_BIN=apt-get
            FIREWALL_BACKEND=ufw
            SSHD_SERVICE=ssh
            SUDO_GROUP=sudo
          }
          install_required_packages() {
            :
          }
          remove_legacy_vps_bootstrap_timers() {
            :
          }
          remove_deselected_cli_links() {
            :
          }
          install_swap() {
            :
          }
          enable_service() {
            :
          }
          configure_automatic_updates() {
            :
          }
          install_intrusion_prevention() {
            :
          }
          ensure_admin_user() {
            :
          }
          install_agent_sudo_helpers() {
            :
          }
          set_requested_hostname() {
            :
          }
          ensure_tailscale_connected() {
            TAILSCALE_IP=100.64.0.10
          }
          disable_tailscale_ssh_for_verification() {
            :
          }
          configure_firewall() {
            :
          }
          validate_prepare_state() {
            :
          }
          install_grok_cli() {
            printf "installer-failure\n" >>"$TEST_RECORD"
            return 1
          }
          remove_agent_cli_update_timer() {
            printf "remove-cli-timer\n" >>"$TEST_RECORD"
          }
          remove_agent_auth_helper() {
            printf "remove-auth-helper\n" >>"$TEST_RECORD"
          }
          install_agent_auth_helper() {
            printf "auth-helper\n" >>"$TEST_RECORD"
          }
          install_agent_cli_update_timer() {
            printf "cli-timer\n" >>"$TEST_RECORD"
          }
          print_selected_cli_versions() {
            :
          }
          run_prepare
        )
      }
      run_bootstrap
    '; then
    output="$(cat "$record")"
    assert_contains "forced prepare installer failure runs prepare" "$output" "phase:prepare"
    assert_contains "forced prepare installer failure is recorded" "$output" "installer-failure"
    assert_contains "forced prepare installer failure still starts hardening" "$output" "phase:harden"
    assert_eq "forced installer failure is saved for recovery" "grok" "$(cat "$state_dir/failed-clis")"
  else
    fail "forced prepare installer failure still reaches hardening"
  fi

  rm -rf "$server_fixture" "$record" "$state_dir"
}

test_server_phase_cleanup_does_not_leak_return_trap() {
  local output

  if output="$(
    bash -c '
      set -Eeuo pipefail
      source lib/vpsbuddy.sh
      generate_server_config_prelude() {
        printf "phase=%q\n" "$1"
      }
      generate_server_script() {
        printf "%s\n" "#!/usr/bin/env bash" "exit 0"
      }
      run_server_phase prepare
      trap -p RETURN
      printf "after-phase\n"
    ' 2>&1
  )"; then
    assert_eq "server phase cleanup leaves no RETURN trap" "after-phase" "$output"
  else
    fail "server phase cleanup leaves no RETURN trap: $output"
  fi
}

test_resume_options_are_accepted() {
  reset_config
  if parse_args --resume && [[ "$VPS_RESUME" == "1" ]]; then
    pass "--resume is accepted"
  else
    fail "--resume is accepted"
  fi

  reset_config
  if parse_args --continue && [[ "$VPS_RESUME" == "1" ]]; then
    pass "--continue is accepted as a resume alias"
  else
    fail "--continue is accepted as a resume alias"
  fi
}

test_resume_plan_round_trip() {
  local server_fixture state_dir public_key
  state_dir="$(mktemp -d /tmp/vpsbuddy-resume-state.XXXXXX)"
  server_fixture="$(mktemp /tmp/vpsbuddy-resume-server.XXXXXX)"
  public_key="$(cat tests/fixtures/id_ed25519.pub)"
  chmod 700 "$state_dir"

  VPS_STATE_DIR="$state_dir"
  VPS_ADMIN_USER="deploy"
  VPS_PUBLIC_KEY="$public_key"
  VPS_HOSTNAME="apps-1"
  VPS_SWAP_ENABLED="1"
  VPS_SWAP_SIZE="6G"
  VPS_SWAP_ACTION="create 6G"
  VPS_WEB="1"
  VPS_SELECTED_CLIS="codex github"
  VPS_SELECTED_CLIS_PRESENT="1"
  VPS_AUTOMATIC_UPDATES="1"
  VPS_FULL_SUDO="0"
  VPS_ENABLE_TAILSCALE_SSH="0"

  save_resume_plan
  write_bootstrap_status prepared

  generate_server_script | sed '/^case "\$phase" in/,$d' > "$server_fixture"
  bash -c '
    set -Eeuo pipefail
    phase=prepare
    admin_user=deploy
    public_key=ssh-ed25519
    requested_hostname=
    enable_tailscale_ssh=0
    web_enabled=0
    selected_clis=
    selected_clis_present=1
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    bootstrap_state_dir="$2"
    source "$1"
    record_cli_link codex /home/deploy/.codex/bin/codex
  ' bash "$server_fixture" "$state_dir"

  reset_config
  VPS_STATE_DIR="$state_dir"
  if load_resume_plan; then
    assert_eq "resume restores the admin user" "deploy" "$VPS_ADMIN_USER"
    assert_eq "resume restores the exact SSH key" "$public_key" "$VPS_PUBLIC_KEY"
    assert_eq "resume restores the swap choice" "6G" "$VPS_SWAP_SIZE"
    assert_eq "resume restores the CLI selection" "codex github" "$VPS_SELECTED_CLIS"
    assert_eq "resume reads the saved phase" "prepared" "$(read_bootstrap_status)"
  else
    fail "resume loads a trusted saved plan"
  fi

  assert_eq "resume plan is private" "600" "$(state_file_mode "$state_dir/bootstrap-plan")"
  assert_eq "resume state directory is private" "700" "$(state_file_mode "$state_dir")"
  assert_eq "CLI link manifest is private" "600" "$(state_file_mode "$state_dir/cli-links")"
  rm -rf "$server_fixture" "$state_dir"
}

test_resume_rejects_untrusted_state() {
  local state_dir public_key
  state_dir="$(mktemp -d /tmp/vpsbuddy-untrusted-state.XXXXXX)"
  public_key="$(cat tests/fixtures/id_ed25519.pub)"

  VPS_STATE_DIR="$state_dir"
  VPS_ADMIN_USER=deploy
  VPS_PUBLIC_KEY="$public_key"
  VPS_HOSTNAME=
  VPS_SWAP_ENABLED=0
  VPS_SWAP_SIZE=
  VPS_SWAP_ACTION="leave disabled"
  VPS_WEB=0
  VPS_SELECTED_CLIS=
  VPS_SELECTED_CLIS_PRESENT=1
  VPS_AUTOMATIC_UPDATES=0
  VPS_FULL_SUDO=0
  VPS_ENABLE_TAILSCALE_SSH=0
  save_resume_plan

  chmod 0666 "$state_dir/bootstrap-plan"
  reset_config
  VPS_STATE_DIR="$state_dir"
  if load_resume_plan; then
    fail "resume rejects a group-writable saved plan"
  else
    pass "resume rejects a group-writable saved plan"
  fi

  rm -f "$state_dir/bootstrap-plan"
  ln -s /dev/null "$state_dir/bootstrap-plan"
  if load_resume_plan; then
    fail "resume rejects a symlinked saved plan"
  else
    pass "resume rejects a symlinked saved plan"
  fi
  rm -rf "$state_dir"
}

test_failed_cli_recovery_commands_are_printed() {
  local output

  VPS_FAILED_CLIS="codex amp"
  output="$(print_failed_cli_recovery)"
  assert_contains "failed Codex install prints the official retry command" "$output" "Codex: curl -fsSL https://chatgpt.com/codex/install.sh | sh"
  assert_contains "failed Amp install prints the official retry command" "$output" "Amp: curl -fsSL https://ampcode.com/install.sh | bash"
  assert_contains "failed CLI recovery does not ask for an OS rebuild" "$output" "You do not need to rebuild the VPS."
}

test_cli_management_failure_does_not_abort_prepare() {
  local server_script server_fixture state_dir
  server_script="$(generate_server_script)"
  server_fixture="$(mktemp /tmp/vpsbuddy-server-functions.XXXXXX)"
  state_dir="$(mktemp -d /tmp/vpsbuddy-cli-optional-state.XXXXXX)"
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
    selected_clis_present=1
    automatic_updates=0
    full_sudo=0
    swap_enabled=0
    swap_size=
    bootstrap_state_dir="$2"
    source "$1"
    install_grok_cli() { :; }
    remove_agent_cli_update_timer() { return 1; }
    remove_agent_auth_helper() { return 1; }
    remove_deselected_cli_links() { return 1; }
    install_agent_auth_helper() { return 1; }
    install_agent_cli_update_timer() { return 1; }
    print_selected_cli_versions() { return 1; }
    install_selected_clis
  ' bash "$server_fixture" "$state_dir"; then
    pass "developer CLI management failures do not abort prepare"
  else
    fail "developer CLI management failures do not abort prepare"
  fi

  rm -rf "$server_fixture" "$state_dir"
}

run_saved_resume_phase() {
  local saved_phase="$1"
  local output public_key state_dir
  public_key="$(cat tests/fixtures/id_ed25519.pub)"
  state_dir="$(mktemp -d /tmp/vpsbuddy-resume-flow.XXXXXX)"

  output="$(
    TEST_PUBLIC_KEY="$public_key" VPSBUDDY_STATE_DIR="$state_dir" bash -c '
      set -Eeuo pipefail
      source lib/vpsbuddy.sh
      reset_config
      VPS_ADMIN_USER=deploy
      VPS_PUBLIC_KEY="$TEST_PUBLIC_KEY"
      VPS_HOSTNAME=
      VPS_SWAP_ENABLED=0
      VPS_SWAP_SIZE=
      VPS_SWAP_ACTION="leave disabled"
      VPS_WEB=0
      VPS_SELECTED_CLIS=codex
      VPS_SELECTED_CLIS_PRESENT=1
      VPS_AUTOMATIC_UPDATES=0
      VPS_FULL_SUDO=0
      VPS_ENABLE_TAILSCALE_SSH=0
      save_resume_plan
      write_bootstrap_status "$1"

      exec 3<<<"yes
yes"
      VPS_INPUT_FD=3
      require_vps_root() { :; }
      run_server_phase() { printf "phase:%s\n" "$1"; }
      tailnet_ipv4() { printf "100.64.0.10\n"; }
      verify_prepared_admin() { :; }
      print_completion_summary() { printf "summary:%s\n" "$1"; }
      main --resume
      printf "saved-status:%s\n" "$(cat "$VPS_STATE_DIR/bootstrap-status")"
    ' bash "$saved_phase" 2>&1
  )"

  rm -rf "$state_dir"
  printf '%s\n' "$output"
}

test_prepared_resume_skips_prepare_and_hardens() {
  local output

  output="$(run_saved_resume_phase prepared)"

  assert_not_contains "prepared resume does not repeat prepare" "$output" "phase:prepare"
  assert_contains "prepared resume still runs hardening" "$output" "phase:harden"
  assert_contains "prepared resume completes" "$output" "summary:100.64.0.10"
  assert_contains "prepared resume records completion" "$output" "saved-status:complete"
}

test_other_resume_phases_follow_safe_boundaries() {
  local complete_output hardening_output preparing_output

  preparing_output="$(run_saved_resume_phase preparing)"
  assert_order "preparing resume repeats prepare before hardening" "$preparing_output" "phase:prepare" "phase:harden"
  assert_contains "preparing resume records completion" "$preparing_output" "saved-status:complete"

  hardening_output="$(run_saved_resume_phase hardening)"
  assert_not_contains "hardening resume does not repeat prepare" "$hardening_output" "phase:prepare"
  assert_contains "hardening resume safely repeats hardening" "$hardening_output" "phase:harden"
  assert_contains "hardening resume records completion" "$hardening_output" "saved-status:complete"

  complete_output="$(run_saved_resume_phase complete)"
  assert_not_contains "complete resume does not run prepare" "$complete_output" "phase:prepare"
  assert_not_contains "complete resume does not run hardening" "$complete_output" "phase:harden"
  assert_contains "complete resume reports the server" "$complete_output" "summary:100.64.0.10"
  assert_contains "complete resume leaves the checkpoint complete" "$complete_output" "saved-status:complete"
}

test_resume_without_saved_plan_starts_guided_recovery() {
  local output public_key state_dir
  public_key="$(cat tests/fixtures/id_ed25519.pub)"
  state_dir="$(mktemp -d /tmp/vpsbuddy-resume-recovery.XXXXXX)"

  output="$(
    TEST_PUBLIC_KEY="$public_key" VPSBUDDY_STATE_DIR="$state_dir" bash -c '
      set -Eeuo pipefail
      source lib/vpsbuddy.sh
      collect_configuration() {
        VPS_ADMIN_USER=deploy
        VPS_PUBLIC_KEY="$TEST_PUBLIC_KEY"
        VPS_HOSTNAME=
        VPS_SWAP_ENABLED=0
        VPS_SWAP_SIZE=
        VPS_SWAP_ACTION="leave disabled"
        VPS_WEB=0
        VPS_SELECTED_CLIS=
        VPS_SELECTED_CLIS_PRESENT=1
        VPS_AUTOMATIC_UPDATES=0
        VPS_FULL_SUDO=0
        VPS_ENABLE_TAILSCALE_SSH=0
      }
      configuration_summary() { :; }
      require_vps_root() { :; }
      run_server_phase() { printf "phase:%s\n" "$1"; }
      tailnet_ipv4() { printf "100.64.0.10\n"; }
      verify_prepared_admin() { :; }
      print_completion_summary() { printf "summary:%s\n" "$1"; }
      exec 3<<<"yes
yes"
      VPS_INPUT_FD=3
      main --resume
      printf "saved-status:%s\n" "$(cat "$VPS_STATE_DIR/bootstrap-status")"
    ' 2>&1
  )"

  assert_contains "resume without a plan starts guided recovery" "$output" "No trusted saved plan was found"
  assert_order "guided recovery prepares before hardening" "$output" "phase:prepare" "phase:harden"
  assert_contains "guided recovery completes" "$output" "saved-status:complete"
  rm -rf "$state_dir"
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
  assert_contains "selected developer CLI failure does not stop hardening" "$server_script" 'continuing to Tailnet verification and SSH hardening'
  assert_contains "admin command pipelines use pipefail" "$server_script" "bash --noprofile --norc -c \"set -o pipefail; \$command\""
  assert_contains "deselected CLI links are cleaned" "$server_script" 'remove_deselected_cli_links'
  assert_contains "CLI links refuse unmanaged replacement" "$server_script" 'refusing to replace unmanaged CLI command'
  assert_contains "CLI updater reports update failures" "$server_script" "exit \"\$failures\""
  assert_contains "Codex updater checks all supported paths" "$server_script" "\$home_dir/.local/bin/codex"
  assert_contains "automatic updates follow operator choice" "$server_script" 'vpsbuddy automatic OS updates disabled'
  assert_contains "automatic update opt-out removes timer" "$server_script" '/etc/systemd/system/vpsbuddy-os-update.timer'
  assert_contains "CLI update timer remains managed after optional installer failures" "$server_script" 'install_agent_cli_update_timer'
  assert_contains "CLI auth helper remains available after optional failures" "$server_script" 'install_agent_auth_helper'
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
  assert_contains "prepare keeps CLI cleanup optional" "$server_script" \
    "could not clean old managed developer CLI links; continuing with VPS setup"
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
  VPS_SELECTED_CLIS_PRESENT="1"
  VPS_AUTOMATIC_UPDATES="1"
  VPS_FULL_SUDO="0"
  VPS_SWAP_ENABLED="1"
  VPS_SWAP_SIZE="8G"
  prelude="$(generate_server_config_prelude prepare)"

  assert_contains "phase prelude carries admin user" "$prelude" "admin_user=ops"
  assert_contains "phase prelude carries swap size" "$prelude" "swap_size=8G"
  assert_contains "phase prelude carries CLI choice" "$prelude" "selected_clis=codex\ github\ claude"
  assert_contains "phase prelude carries CLI selection marker" "$prelude" "selected_clis_present=1"
  assert_contains "phase prelude carries update choice" "$prelude" "automatic_updates=1"
}

test_selected_cli_prompt_accepts_formats
test_generated_selected_cli_behavior
test_generated_missing_cli_selection_state
test_generated_installer_failure_is_not_masked
test_generated_cli_installers_have_a_deadline
test_generated_cli_link_cleanup
test_generated_cli_link_safety
test_successful_rerun_deselects_managed_cli
test_github_cli_requires_managed_package
test_github_cli_rpm_package_path
test_selected_cli_install_dispatch
test_generated_cli_candidate_paths
test_droid_only_installs_xdg_utils
test_generated_pi_node_precedence
test_generated_cli_updater_reports_failures
test_generated_cli_updater_refuses_unmanaged_link
test_generated_auth_helper_honors_selected_clis
test_auth_helper_honors_selected_clis
test_configuration_has_no_hidden_operator_defaults
test_guided_dry_run_captures_operator_configuration
test_fallback_key_and_no_swap_are_captured
test_root_and_restricted_detected_keys_are_rejected
test_login_home_uses_local_passwd_by_uid
test_non_regular_authorized_keys_does_not_block_recovery
test_prepare_installer_failure_still_reaches_hardening
test_server_phase_cleanup_does_not_leak_return_trap
test_resume_options_are_accepted
test_resume_plan_round_trip
test_resume_rejects_untrusted_state
test_failed_cli_recovery_commands_are_printed
test_cli_management_failure_does_not_abort_prepare
test_prepared_resume_skips_prepare_and_hardens
test_other_resume_phases_follow_safe_boundaries
test_resume_without_saved_plan_starts_guided_recovery
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
