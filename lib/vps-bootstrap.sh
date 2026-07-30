#!/usr/bin/env bash

VPS_BOOTSTRAP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

reset_config() {
  VPS_ADMIN_USER=""
  VPS_PUBLIC_KEY=""
  VPS_HOSTNAME=""
  VPS_SWAP_ENABLED=""
  VPS_SWAP_SIZE=""
  VPS_SWAP_ACTION=""
  VPS_WEB=""
  VPS_INSTALL_AGENT_CLIS=""
  VPS_AUTOMATIC_UPDATES=""
  VPS_FULL_SUDO=""
  VPS_ENABLE_TAILSCALE_SSH=""
  VPS_DRY_RUN="0"
  VPS_SHOW_HELP="0"
}

reset_config

error() {
  printf 'vps-bootstrap: %s\n' "$*" >&2
}

usage() {
  cat << 'USAGE'
Usage:
  sudo vps-bootstrap [--dry-run]

Run this command after logging into the VPS. The guided setup asks for:
  - the admin user name
  - the SSH public key to install
  - an optional hostname
  - swap setup
  - public web ports
  - Codex, Grok, and GitHub CLI installation
  - automatic OS updates
  - scoped or full passwordless sudo
  - optional Tailscale SSH

Options:
  --dry-run   Collect and print the configuration without changing the server.
  -h, --help  Show this help.

The prepare phase keeps public SSH open. After it completes, test the new admin
login over the Tailnet from another terminal. The script only disables public
SSH after you type yes to confirm that test passed.
USAGE
}

parse_args() {
  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --dry-run)
        VPS_DRY_RUN="1"
        ;;
      -h | --help)
        VPS_SHOW_HELP="1"
        ;;
      *)
        error "unknown option: $1"
        return 1
        ;;
    esac
    shift
  done
}

read_interactive_answer() {
  local answer

  if [[ -n "${VPS_INPUT_FD:-}" ]]; then
    IFS= read -r -u "$VPS_INPUT_FD" answer || return 1
    printf '%s' "$answer"
    return
  fi

  if [[ ! -r /dev/tty ]]; then
    error "interactive input requires a terminal"
    return 1
  fi

  IFS= read -r answer < /dev/tty || return 1
  printf '%s' "$answer"
}

prompt_required() {
  local prompt="$1"
  local answer

  while true; do
    printf '[vps-bootstrap] %s: ' "$prompt" >&2
    answer="$(read_interactive_answer)" || return 1
    if [[ -n "$answer" ]]; then
      printf '%s' "$answer"
      return 0
    fi
    error "a value is required"
  done
}

prompt_optional() {
  local prompt="$1"
  local answer

  printf '[vps-bootstrap] %s: ' "$prompt" >&2
  answer="$(read_interactive_answer)" || return 1
  printf '%s' "$answer"
}

prompt_yes_no() {
  local prompt="$1"
  local answer

  while true; do
    printf '[vps-bootstrap] %s (yes/no): ' "$prompt" >&2
    answer="$(read_interactive_answer)" || return 1
    case "$answer" in
      yes | YES | Yes | y | Y)
        printf '1'
        return 0
        ;;
      no | NO | No | n | N)
        printf '0'
        return 0
        ;;
      *)
        error "answer yes or no"
        ;;
    esac
  done
}

validate_admin_user() {
  local user="$1"

  if [[ "$user" == "root" ]]; then
    error "root cannot be the managed admin user"
    return 1
  fi

  if [[ ! "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    error "admin user must match ^[a-z_][a-z0-9_-]{0,31}$"
    return 1
  fi
}

validate_hostname() {
  local hostname="$1"

  if [[ -n "$hostname" && ! "$hostname" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$ ]]; then
    error "hostname must contain only letters, numbers, dots, and hyphens"
    return 1
  fi
}

validate_swap_size() {
  local size="$1"

  if [[ ! "$size" =~ ^[1-9][0-9]*[MmGg]$ ]]; then
    error "swap size must be a positive whole number followed by M or G, for example 4G"
    return 1
  fi
}

validate_public_key() {
  local public_key="$1"
  local key_file status

  case "$public_key" in
    ssh-ed25519\ * | ssh-rsa\ * | ecdsa-sha2-nistp256\ * | ecdsa-sha2-nistp384\ * | ecdsa-sha2-nistp521\ * | sk-ssh-ed25519@openssh.com\ * | sk-ecdsa-sha2-nistp256@openssh.com\ *)
      ;;
    *)
      error "enter one OpenSSH public key"
      return 1
      ;;
  esac

  if ! command -v ssh-keygen > /dev/null 2>&1; then
    return 0
  fi

  key_file="$(mktemp "${TMPDIR:-/tmp}/vps-bootstrap-key.XXXXXX")" || return 1
  chmod 600 "$key_file"
  printf '%s\n' "$public_key" > "$key_file"
  if ssh-keygen -l -f "$key_file" > /dev/null 2>&1; then
    status=0
  else
    error "SSH public key is not valid"
    status=1
  fi
  rm -f "$key_file"
  return "$status"
}

public_key_fingerprint() {
  local public_key="$1"
  local key_file fingerprint

  if ! command -v ssh-keygen > /dev/null 2>&1; then
    printf 'configured'
    return 0
  fi

  key_file="$(mktemp "${TMPDIR:-/tmp}/vps-bootstrap-key.XXXXXX")" || return 1
  chmod 600 "$key_file"
  printf '%s\n' "$public_key" > "$key_file"
  fingerprint="$(ssh-keygen -l -f "$key_file" 2> /dev/null | awk '{ print $2 }')"
  rm -f "$key_file"
  printf '%s' "${fingerprint:-configured}"
}

login_home() {
  local login_user="${SUDO_USER:-$(id -un)}"

  getent passwd "$login_user" 2> /dev/null | cut -d: -f6
}

detect_existing_public_key() {
  local home_dir authorized_keys

  home_dir="$(login_home)"
  [[ -n "$home_dir" ]] || return 1
  authorized_keys="$home_dir/.ssh/authorized_keys"
  [[ -r "$authorized_keys" ]] || return 1

  awk '
    $1 ~ /^(ssh-(ed25519|rsa)|ecdsa-sha2-nistp(256|384|521)|sk-(ssh-ed25519|ecdsa-sha2-nistp256)@openssh.com)$/ && NF >= 2 {
      print $1 " " $2
      exit
    }
  ' "$authorized_keys"
}

has_active_swap() {
  [[ -r /proc/swaps ]] || return 1
  awk 'NR > 1 && $1 != "" { found = 1 } END { exit(found ? 0 : 1) }' /proc/swaps
}

collect_public_key() {
  local detected_key use_detected_key entered_key

  detected_key="$(detect_existing_public_key || true)"
  if [[ -n "$detected_key" ]] && validate_public_key "$detected_key"; then
    printf '[vps-bootstrap] Found the SSH key used by the current login: %s\n' \
      "$(public_key_fingerprint "$detected_key")" >&2
    use_detected_key="$(prompt_yes_no "Install this key for the new admin user")" || return 1
    if [[ "$use_detected_key" == "1" ]]; then
      VPS_PUBLIC_KEY="$detected_key"
      return 0
    fi
  fi

  while true; do
    entered_key="$(prompt_required "Paste the SSH public key to install")" || return 1
    if validate_public_key "$entered_key"; then
      VPS_PUBLIC_KEY="$entered_key"
      return 0
    fi
  done
}

collect_swap_configuration() {
  local answer

  if has_active_swap; then
    VPS_SWAP_ENABLED="0"
    VPS_SWAP_SIZE=""
    VPS_SWAP_ACTION="keep existing"
    printf '[vps-bootstrap] Active swap exists and will be left unchanged.\n' >&2
    return 0
  fi

  while true; do
    answer="$(prompt_required "Swap size such as 4G, or none to leave swap disabled")" || return 1
    case "$answer" in
      none | NONE | None)
        VPS_SWAP_ENABLED="0"
        VPS_SWAP_SIZE=""
        VPS_SWAP_ACTION="leave disabled"
        return 0
        ;;
      *)
        if validate_swap_size "$answer"; then
          VPS_SWAP_ENABLED="1"
          VPS_SWAP_SIZE="$answer"
          VPS_SWAP_ACTION="create $answer"
          return 0
        fi
        ;;
    esac
  done
}

collect_configuration() {
  while true; do
    VPS_ADMIN_USER="$(prompt_required "Admin user name")" || return 1
    validate_admin_user "$VPS_ADMIN_USER" && break
  done

  collect_public_key || return 1

  while true; do
    VPS_HOSTNAME="$(prompt_optional "Hostname, or press Enter to keep the current hostname")" || return 1
    validate_hostname "$VPS_HOSTNAME" && break
  done

  collect_swap_configuration || return 1
  VPS_WEB="$(prompt_yes_no "Open public web ports 80 and 443")" || return 1
  VPS_INSTALL_AGENT_CLIS="$(prompt_yes_no "Install Codex, Grok, and GitHub CLIs")" || return 1
  VPS_AUTOMATIC_UPDATES="$(prompt_yes_no "Manage automatic OS updates with vps-bootstrap")" || return 1
  VPS_FULL_SUDO="$(prompt_yes_no "Grant the admin user full passwordless sudo")" || return 1
  VPS_ENABLE_TAILSCALE_SSH="$(
    prompt_yes_no "Enable Tailscale SSH (only if Tailnet SSH ACL rules are ready)"
  )" || return 1
}

configuration_summary() {
  cat << SUMMARY

Configuration:
  Admin user: $VPS_ADMIN_USER
  SSH public key: $(public_key_fingerprint "$VPS_PUBLIC_KEY")
  Hostname: $([[ -n "$VPS_HOSTNAME" ]] && printf '%s' "$VPS_HOSTNAME" || printf 'keep current')
  Swap: $VPS_SWAP_ACTION
  Public web ports: $([[ "$VPS_WEB" == "1" ]] && printf 'open 80/443' || printf 'closed')
  Developer CLIs: $([[ "$VPS_INSTALL_AGENT_CLIS" == "1" ]] && printf 'install' || printf 'skip')
  Automatic OS updates: $([[ "$VPS_AUTOMATIC_UPDATES" == "1" ]] && printf 'enable' || printf 'disable bootstrap timer')
  Sudo policy: $([[ "$VPS_FULL_SUDO" == "1" ]] && printf 'full passwordless sudo' || printf 'scoped helpers')
  Tailscale SSH: $([[ "$VPS_ENABLE_TAILSCALE_SSH" == "1" ]] && printf 'enabled' || printf 'disabled')
SUMMARY
}

require_vps_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    error "run this command as root, for example: sudo vps-bootstrap"
    return 1
  fi

  if [[ ! -r /etc/os-release ]]; then
    error "/etc/os-release is missing; this does not look like a supported Linux VPS"
    return 1
  fi
}

generate_server_script() {
  cat << 'SERVER_SCRIPT_HEAD'
#!/usr/bin/env bash
set -Eeuo pipefail

: "${phase:?phase required}"
: "${admin_user:?admin user required}"
: "${public_key:?public key required}"
requested_hostname="${requested_hostname:-}"
: "${enable_tailscale_ssh:?Tailscale SSH choice required}"
: "${web_enabled:?web port choice required}"
: "${install_agent_clis:?developer CLI choice required}"
: "${automatic_updates:?automatic update choice required}"
: "${full_sudo:?sudo policy choice required}"
: "${swap_enabled:?swap choice required}"
swap_size="${swap_size:-}"

OS_ID=""
OS_LIKE=""
OS_NAME=""
PKG_BACKEND=""
PKG_BIN=""
FIREWALL_BACKEND=""
SSHD_SERVICE=""
SUDO_GROUP=""
TAILSCALE_IP=""

log() {
  printf '[vps-bootstrap] %s\n' "$*"
}

warn() {
  printf '[vps-bootstrap] warning: %s\n' "$*" >&2
}

fail() {
  printf '[vps-bootstrap] error: %s\n' "$*" >&2
  exit 1
}

command_exists() {
  command -v "$1" >/dev/null 2>&1
}

require_root() {
  if [[ "$(id -u)" -ne 0 ]]; then
    fail "vps-bootstrap must run as root"
  fi
}

validate_admin_user_server() {
  local existing_uid

  if [[ "$admin_user" == "root" ]]; then
    fail "root cannot be the managed admin user"
  fi

  if [[ ! "$admin_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    fail "admin user must match ^[a-z_][a-z0-9_-]{0,31}$"
  fi

  existing_uid="$(id -u "$admin_user" 2>/dev/null || true)"
  if [[ "$existing_uid" == "0" ]]; then
    fail "managed admin user must not have UID 0"
  fi
}

validate_hostname_server() {
  if [[ -z "$requested_hostname" ]]; then
    return 0
  fi

  if [[ ! "$requested_hostname" =~ ^[A-Za-z0-9]([A-Za-z0-9.-]{0,251}[A-Za-z0-9])?$ ]]; then
    fail "hostname must contain only letters, numbers, dots, and hyphens"
  fi
}

validate_swap_size_server() {
  if [[ ! "$swap_size" =~ ^[1-9][0-9]*[MmGg]$ ]]; then
    fail "swap size must be a positive whole number followed by M or G, for example 2G"
  fi
}

swap_size_mb() {
  case "$swap_size" in
    [1-9][0-9]*[Mm])
      printf '%s\n' "${swap_size%?}"
      ;;
    [1-9][0-9]*[Gg])
      printf '%s\n' "$(( ${swap_size%?} * 1024 ))"
      ;;
  esac
}

load_os_release() {
  if [[ ! -r /etc/os-release ]]; then
    fail "/etc/os-release is missing; unsupported Linux distribution"
  fi

  # shellcheck disable=SC1091
  . /etc/os-release
  OS_ID="${ID:-}"
  OS_LIKE="${ID_LIKE:-}"
  OS_NAME="${PRETTY_NAME:-$OS_ID}"
}

family_contains() {
  local needle="$1"
  case " $OS_ID $OS_LIKE " in
    *" $needle "*)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

select_platform() {
  load_os_release

  if command_exists apt-get && { family_contains ubuntu || family_contains debian; }; then
    PKG_BACKEND="apt"
    PKG_BIN="apt-get"
    FIREWALL_BACKEND="ufw"
    SSHD_SERVICE="ssh"
    SUDO_GROUP="sudo"
    return 0
  fi

  if command_exists dnf && {
    family_contains fedora || family_contains rhel || family_contains centos || family_contains rocky || family_contains almalinux || family_contains ol;
  }; then
    PKG_BACKEND="dnf"
    PKG_BIN="dnf"
    FIREWALL_BACKEND="firewalld"
    SSHD_SERVICE="sshd"
    SUDO_GROUP="wheel"
    return 0
  fi

  if command_exists yum && {
    family_contains fedora || family_contains rhel || family_contains centos || family_contains rocky || family_contains almalinux || family_contains ol;
  }; then
    PKG_BACKEND="yum"
    PKG_BIN="yum"
    FIREWALL_BACKEND="firewalld"
    SSHD_SERVICE="sshd"
    SUDO_GROUP="wheel"
    return 0
  fi

  fail "unsupported distribution: $OS_NAME"
}

install_optional_package() {
  local package="$1"

  if "$PKG_BIN" install -y "$package"; then
    log "installed optional package: $package"
    return 0
  fi

  warn "optional package unavailable or failed to install: $package"
  return 1
}

install_required_packages() {
  log "installing required packages on $OS_NAME"

  if [[ "$PKG_BACKEND" == "apt" ]]; then
    export DEBIAN_FRONTEND=noninteractive
    apt-get update
    apt-get install -y sudo ca-certificates curl gnupg git openssh-server ufw util-linux
    if [[ "$automatic_updates" == "1" ]]; then
      apt-get install -y unattended-upgrades
    fi
    return 0
  fi

  if [[ "$PKG_BACKEND" == "dnf" ]]; then
    dnf makecache -y
    dnf install -y sudo ca-certificates curl git openssh-server firewalld util-linux
    return 0
  fi

  yum makecache -y
  yum install -y sudo ca-certificates curl git openssh-server firewalld util-linux
}

has_active_swap() {
  [[ -r /proc/swaps ]] || return 1
  awk 'NR > 1 && $1 != "" { found = 1 } END { exit(found ? 0 : 1) }' /proc/swaps
}

ensure_swap_fstab() {
  if ! grep -Eq '^[[:space:]]*/swapfile[[:space:]]+none[[:space:]]+swap([[:space:]]|$)' /etc/fstab; then
    printf '/swapfile none swap sw 0 0\n' >>/etc/fstab
  fi
}

install_swap() {
  local swap_file="/swapfile" swap_size_mb_value

  if [[ "$swap_enabled" != "1" ]]; then
    log "swap setup skipped"
    return 0
  fi

  validate_swap_size_server
  command_exists mkswap || fail "mkswap is required for swap setup"
  command_exists swapon || fail "swapon is required for swap setup"
  [[ -r /proc/swaps ]] || fail "/proc/swaps is unavailable; cannot verify swap state"

  if has_active_swap; then
    if awk '$1 == "/swapfile" { found = 1 } END { exit(found ? 0 : 1) }' /proc/swaps; then
      ensure_swap_fstab
    fi
    log "active swap already exists; leaving it unchanged"
    return 0
  fi

  if [[ -L "$swap_file" ]]; then
    fail "$swap_file is a symlink; refusing to use it for swap"
  fi

  if [[ -e "$swap_file" ]]; then
    chmod 600 "$swap_file"
    if swapon "$swap_file" 2>/dev/null; then
      ensure_swap_fstab
      log "enabled existing swap file: $swap_file"
      return 0
    fi

    fail "$swap_file exists but is not usable; refusing to overwrite it"
  fi

  install -o root -g root -m 0600 /dev/null "$swap_file"
  if ! command_exists fallocate || ! fallocate -l "$swap_size" "$swap_file" 2>/dev/null; then
    swap_size_mb_value="$(swap_size_mb)"
    log "fallocate unavailable or failed; creating $swap_size swap with dd"
    rm -f "$swap_file"
    install -o root -g root -m 0600 /dev/null "$swap_file"
    if ! dd if=/dev/zero of="$swap_file" bs=1048576 count="$swap_size_mb_value"; then
      rm -f "$swap_file"
      fail "could not allocate $swap_size swap file"
    fi
  fi

  chmod 600 "$swap_file"
  if ! mkswap "$swap_file" >/dev/null; then
    rm -f "$swap_file"
    fail "could not format $swap_file as swap"
  fi
  if ! swapon "$swap_file"; then
    rm -f "$swap_file"
    fail "could not activate $swap_file"
  fi

  ensure_swap_fstab
  log "created and enabled $swap_size swap at $swap_file"
}

enable_service() {
  local service="$1"
  local unit="$1"

  case "$unit" in
    *.*)
      ;;
    *)
      unit="${service}.service"
      ;;
  esac

  if systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q . || systemctl cat "$service" >/dev/null 2>&1; then
    systemctl enable --now "$service"
    return 0
  fi

  warn "service not found: $service"
  return 1
}

remove_legacy_auto_updates_config() {
  local legacy_file legacy_contents expected_contents

  legacy_file="/etc/apt/apt.conf.d/20auto-upgrades"
  [[ -f "$legacy_file" ]] || return 0

  legacy_contents="$(cat "$legacy_file")"
  expected_contents=$'APT::Periodic::Update-Package-Lists "14";\nAPT::Periodic::Unattended-Upgrade "14";\nAPT::Periodic::AutocleanInterval "14";'
  if [[ "$legacy_contents" == "$expected_contents" ]]; then
    rm -f "$legacy_file"
    log "removed the legacy vps-bootstrap apt update schedule"
  fi
}

configure_automatic_updates() {
  if [[ "$PKG_BACKEND" == "apt" ]]; then
    remove_legacy_auto_updates_config
  fi

  if [[ "$automatic_updates" != "1" ]]; then
    systemctl disable --now vps-os-update.timer >/dev/null 2>&1 || true
    rm -f \
      /etc/systemd/system/vps-os-update.service \
      /etc/systemd/system/vps-os-update.timer \
      /etc/apt/apt.conf.d/52vps-bootstrap-auto-upgrades \
      /usr/local/sbin/vps-os-update
    systemctl daemon-reload
    log "vps-bootstrap automatic OS updates disabled"
    return 0
  fi

  if [[ "$PKG_BACKEND" == "apt" ]]; then
    cat >/etc/apt/apt.conf.d/52vps-bootstrap-auto-upgrades <<'APT_AUTO_UPGRADES'
APT::Periodic::Update-Package-Lists "14";
APT::Periodic::Unattended-Upgrade "14";
APT::Periodic::AutocleanInterval "14";
APT_AUTO_UPGRADES

    systemctl enable --now unattended-upgrades >/dev/null 2>&1 || warn "unattended-upgrades service not enabled"
  fi

  install_os_update_timer
}

install_os_update_timer() {
  install -d -m 0755 /usr/local/sbin

  {
    cat <<'OS_UPDATE_SCRIPT_HEAD'
#!/usr/bin/env bash
set -Eeuo pipefail

export DEBIAN_FRONTEND=noninteractive
OS_UPDATE_SCRIPT_HEAD
    printf 'pkg_backend=%q\n' "$PKG_BACKEND"
    cat <<'OS_UPDATE_SCRIPT_BODY'

case "$pkg_backend" in
  apt)
    apt-get update
    if command -v unattended-upgrade >/dev/null 2>&1; then
      unattended-upgrade -d
    else
      apt-get -y upgrade
    fi
    apt-get -y autoremove
    ;;
  dnf)
    dnf -y upgrade
    ;;
  yum)
    yum -y update
    ;;
  *)
    printf 'unsupported package backend: %s\n' "$pkg_backend" >&2
    exit 1
    ;;
esac
OS_UPDATE_SCRIPT_BODY
  } >/usr/local/sbin/vps-os-update

  chmod 755 /usr/local/sbin/vps-os-update

  cat >/etc/systemd/system/vps-os-update.service <<'OS_UPDATE_SERVICE'
[Unit]
Description=Install OS updates managed by vps-bootstrap
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vps-os-update
OS_UPDATE_SERVICE

  cat >/etc/systemd/system/vps-os-update.timer <<'OS_UPDATE_TIMER'
[Unit]
Description=Run vps-bootstrap OS updates every two weeks

[Timer]
OnBootSec=45min
OnUnitActiveSec=14d
Persistent=true
RandomizedDelaySec=2h

[Install]
WantedBy=timers.target
OS_UPDATE_TIMER

  systemctl daemon-reload
  systemctl enable --now vps-os-update.timer
}

install_ban_service() {
  if install_optional_package fail2ban; then
    enable_service fail2ban || true
    return 0
  fi

  if install_optional_package sshguard; then
    enable_service sshguard || true
    return 0
  fi

  warn "neither fail2ban nor sshguard is available from configured repositories"
}

agent_audit_prelude() {
  cat <<'AGENT_AUDIT_PRELUDE'
SERVER_SCRIPT_HEAD
  cat "$VPS_BOOTSTRAP_LIB_DIR/templates/vps-agent-audit-prelude.sh"
  cat << 'SERVER_SCRIPT_BODY'
AGENT_AUDIT_PRELUDE
}

generate_sudoers_policy_server() {
  local policy_full="${1:-$full_sudo}"

  if [[ "$policy_full" == "1" ]]; then
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$admin_user"
    return 0
  fi

  cat <<SUDOERS_POLICY
# Managed by vps-bootstrap. Passwordless sudo is limited to root-owned helpers.
Cmnd_Alias VPS_AGENT_HELPERS = /usr/local/sbin/vps-agent-sudo-check, /usr/local/sbin/vps-agent-package, /usr/local/sbin/vps-agent-service, /usr/local/sbin/vps-agent-logs, /usr/local/sbin/vps-agent-firewall, /usr/local/sbin/vps-agent-cli-update, /usr/local/sbin/vps-os-update
$admin_user ALL=(root) NOPASSWD: VPS_AGENT_HELPERS
SUDOERS_POLICY
}

install_agent_sudo_helpers() {
  local home_dir

  home_dir="$(admin_home_dir)"
  install -d -m 0755 /usr/local/sbin

  cat >/usr/local/sbin/vps-agent-sudo-check <<'SUDO_CHECK_HELPER_HEAD'
#!/usr/bin/env bash
set -Eeuo pipefail
SUDO_CHECK_HELPER_HEAD
  agent_audit_prelude >>/usr/local/sbin/vps-agent-sudo-check
  cat >>/usr/local/sbin/vps-agent-sudo-check <<'SUDO_CHECK_HELPER_BODY'
printf 'vps-agent sudo helper access ok\n'
SUDO_CHECK_HELPER_BODY

  {
    cat <<'PACKAGE_HELPER_HEAD'
#!/usr/bin/env bash
set -Eeuo pipefail
PACKAGE_HELPER_HEAD
    printf 'pkg_backend=%q\n' "$PKG_BACKEND"
    agent_audit_prelude
    cat <<'PACKAGE_HELPER_BODY'

valid_package() {
  [[ "$1" =~ ^[A-Za-z0-9][A-Za-z0-9+_.:-]*$ ]]
}

usage() {
  printf 'Usage: vps-agent-package update|upgrade|install <package> [...]\n' >&2
  exit 2
}

[[ "$#" -ge 1 ]] || usage
action="$1"
shift

case "$action" in
  update)
    [[ "$#" -eq 0 ]] || usage
    case "$pkg_backend" in
      apt) apt-get update ;;
      dnf) dnf makecache -y ;;
      yum) yum makecache -y ;;
      *) printf 'unsupported package backend: %s\n' "$pkg_backend" >&2; exit 1 ;;
    esac
    ;;
  upgrade)
    [[ "$#" -eq 0 ]] || usage
    case "$pkg_backend" in
      apt) export DEBIAN_FRONTEND=noninteractive; apt-get update; apt-get -y upgrade ;;
      dnf) dnf -y upgrade ;;
      yum) yum -y update ;;
      *) printf 'unsupported package backend: %s\n' "$pkg_backend" >&2; exit 1 ;;
    esac
    ;;
  install)
    [[ "$#" -ge 1 ]] || usage
    for package in "$@"; do
      valid_package "$package" || {
        printf 'invalid package name: %s\n' "$package" >&2
        exit 2
      }
    done
    case "$pkg_backend" in
      apt) export DEBIAN_FRONTEND=noninteractive; apt-get update; apt-get install -y "$@" ;;
      dnf) dnf install -y "$@" ;;
      yum) yum install -y "$@" ;;
      *) printf 'unsupported package backend: %s\n' "$pkg_backend" >&2; exit 1 ;;
    esac
    ;;
  *)
    usage
    ;;
esac
PACKAGE_HELPER_BODY
  } >/usr/local/sbin/vps-agent-package

  cat >/usr/local/sbin/vps-agent-service <<'SERVICE_HELPER_HEAD'
#!/usr/bin/env bash
set -Eeuo pipefail
SERVICE_HELPER_HEAD
  agent_audit_prelude >>/usr/local/sbin/vps-agent-service
  cat >>/usr/local/sbin/vps-agent-service <<'SERVICE_HELPER_BODY'

usage() {
  printf 'Usage: vps-agent-service start|stop|restart|reload|status|enable|disable <service>\n' >&2
  exit 2
}

valid_service() {
  [[ "$1" =~ ^[A-Za-z0-9@_.-]+(\\.service)?$ ]]
}

[[ "$#" -eq 2 ]] || usage
action="$1"
service="$2"
valid_service "$service" || {
  printf 'invalid service name: %s\n' "$service" >&2
  exit 2
}

case "$action" in
  start | stop | restart | reload | status | enable | disable)
    systemctl "$action" "$service"
    ;;
  *)
    usage
    ;;
esac
SERVICE_HELPER_BODY

  cat >/usr/local/sbin/vps-agent-logs <<'LOGS_HELPER_HEAD'
#!/usr/bin/env bash
set -Eeuo pipefail
LOGS_HELPER_HEAD
  agent_audit_prelude >>/usr/local/sbin/vps-agent-logs
  cat >>/usr/local/sbin/vps-agent-logs <<'LOGS_HELPER_BODY'

usage() {
  printf 'Usage: vps-agent-logs <service> [lines]\n' >&2
  exit 2
}

valid_service() {
  [[ "$1" =~ ^[A-Za-z0-9@_.-]+(\\.service)?$ ]]
}

[[ "$#" -ge 1 && "$#" -le 2 ]] || usage
service="$1"
lines="${2:-200}"
valid_service "$service" || {
  printf 'invalid service name: %s\n' "$service" >&2
  exit 2
}
[[ "$lines" =~ ^[0-9]+$ && "$lines" -le 5000 ]] || {
  printf 'lines must be a number up to 5000\n' >&2
  exit 2
}

journalctl -u "$service" -n "$lines" --no-pager
LOGS_HELPER_BODY

  {
    cat <<'FIREWALL_HELPER_HEAD'
#!/usr/bin/env bash
set -Eeuo pipefail
FIREWALL_HELPER_HEAD
    printf 'firewall_backend=%q\n' "$FIREWALL_BACKEND"
    agent_audit_prelude
    cat <<'FIREWALL_HELPER_BODY'

usage() {
  printf 'Usage: vps-agent-firewall web-on|web-off|status\n' >&2
  exit 2
}

[[ "$#" -eq 1 ]] || usage
case "$1:$firewall_backend" in
  web-on:ufw)
    ufw allow 80/tcp comment 'vps-agent public http'
    ufw allow 443/tcp comment 'vps-agent public https'
    ;;
  web-off:ufw)
    ufw --force delete allow 80/tcp || true
    ufw --force delete allow 443/tcp || true
    ;;
  status:ufw)
    ufw status verbose
    ;;
  web-on:firewalld)
    firewall-cmd --permanent --zone=public --add-service=http
    firewall-cmd --permanent --zone=public --add-service=https
    firewall-cmd --reload
    ;;
  web-off:firewalld)
    firewall-cmd --permanent --zone=public --remove-service=http || true
    firewall-cmd --permanent --zone=public --remove-service=https || true
    firewall-cmd --reload
    ;;
  status:firewalld)
    firewall-cmd --list-all
    ;;
  *)
    usage
    ;;
esac
FIREWALL_HELPER_BODY
  } >/usr/local/sbin/vps-agent-firewall

  rm -f /usr/local/sbin/vps-agent-deploy
  chmod 755 \
    /usr/local/sbin/vps-agent-sudo-check \
    /usr/local/sbin/vps-agent-package \
    /usr/local/sbin/vps-agent-service \
    /usr/local/sbin/vps-agent-logs \
    /usr/local/sbin/vps-agent-firewall
}

write_sudoers_policy() {
  local policy_full="${1:-$full_sudo}"
  local sudoers_file

  sudoers_file="/etc/sudoers.d/90-vps-bootstrap-$admin_user"
  generate_sudoers_policy_server "$policy_full" >"$sudoers_file"
  chmod 440 "$sudoers_file"
  visudo -cf "$sudoers_file" >/dev/null
}

admin_home_dir() {
  getent passwd "$admin_user" | cut -d: -f6
}

run_as_admin() {
  local home_dir="$1"
  local command="$2"

  sudo -H -u "$admin_user" env HOME="$home_dir" SHELL=/bin/bash bash -lc "$command"
}

admin_command_path() {
  local home_dir="$1"
  local command_name="$2"
  local candidate

  case "$command_name" in
    codex)
      for candidate in "$home_dir/.codex/bin/codex" "$home_dir/.local/bin/codex" "$home_dir/bin/codex"; do
        if [[ -x "$candidate" ]]; then
          printf '%s\n' "$candidate"
          return 0
        fi
      done
      ;;
    grok | agent)
      candidate="$home_dir/.grok/bin/$command_name"
      if [[ -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
      ;;
  esac

  run_as_admin "$home_dir" "command -v $(printf '%q' "$command_name")" 2>/dev/null || true
}

link_admin_command() {
  local home_dir="$1"
  local command_name="$2"
  local command_path

  command_path="$(admin_command_path "$home_dir" "$command_name")"
  if [[ -z "$command_path" || ! -x "$command_path" ]]; then
    return 1
  fi

  install -d -m 0755 /usr/local/bin
  ln -sf "$command_path" "/usr/local/bin/$command_name"
}

install_codex_cli() {
  local home_dir

  home_dir="$(admin_home_dir)"
  log "installing/updating official Codex CLI for $admin_user"
  warn "executing OpenAI's mutable official Codex installer; this is an accepted supply-chain trust boundary"
  run_as_admin "$home_dir" 'curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh'

  if ! link_admin_command "$home_dir" codex; then
    warn "Codex CLI installer did not put codex on $admin_user PATH"
    return 1
  fi

  run_as_admin "$home_dir" 'codex --version' >/dev/null
}

install_grok_cli() {
  local home_dir grok_bin

  home_dir="$(admin_home_dir)"
  grok_bin="$home_dir/.grok/bin/grok"

  if [[ -x "$grok_bin" ]]; then
    log "Grok CLI is already installed for $admin_user"
  else
    log "installing official Grok CLI for $admin_user"
    warn "executing xAI's mutable official Grok installer; this is an accepted supply-chain trust boundary"
    sudo -H -u "$admin_user" env SHELL=/bin/bash bash -c 'curl -fsSL https://x.ai/cli/install.sh | bash'
  fi

  if [[ ! -x "$grok_bin" ]]; then
    warn "Grok CLI installer did not create $grok_bin"
    return 1
  fi

  install -d -m 0755 /usr/local/bin
  ln -sf "$grok_bin" /usr/local/bin/grok
  if [[ -x "$home_dir/.grok/bin/agent" ]]; then
    ln -sf "$home_dir/.grok/bin/agent" /usr/local/bin/agent
  fi

  sudo -H -u "$admin_user" "$grok_bin" --version >/dev/null
}

remove_legacy_third_party_grok_cli() {
  if ! command_exists npm; then
    return 0
  fi

  if npm list -g @vibe-kit/grok-cli >/dev/null 2>&1; then
    log "removing legacy third-party Grok CLI npm package"
    npm uninstall -g @vibe-kit/grok-cli || warn "failed to remove @vibe-kit/grok-cli"
    return 0
  fi
}

install_github_cli() {
  if command_exists gh; then
    log "GitHub CLI is already installed"
    return 0
  fi

  log "installing GitHub CLI"

  if [[ "$PKG_BACKEND" == "apt" ]]; then
    install -d -m 0755 /etc/apt/keyrings
    curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      -o /etc/apt/keyrings/githubcli-archive-keyring.gpg
    chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
    install -d -m 0755 /etc/apt/sources.list.d
    printf 'deb [arch=%s signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main\n' \
      "$(dpkg --print-architecture)" \
      >/etc/apt/sources.list.d/github-cli.list
    apt-get update
    apt-get install -y gh
    gh --version >/dev/null
    return 0
  fi

  curl -fsSL https://cli.github.com/packages/rpm/gh-cli.repo -o /etc/yum.repos.d/gh-cli.repo
  "$PKG_BIN" install -y gh
  gh --version >/dev/null
}

install_agent_clis_if_requested() {
  local failures=0

  if [[ "$install_agent_clis" != "1" ]]; then
    log "developer CLI installation skipped"
    return 0
  fi

  install_codex_cli || {
    warn "Codex CLI installation failed"
    failures=$((failures + 1))
  }
  remove_legacy_third_party_grok_cli || {
    warn "legacy third-party Grok CLI removal failed"
    failures=$((failures + 1))
  }
  install_grok_cli || {
    warn "Grok CLI installation failed"
    failures=$((failures + 1))
  }
  install_github_cli || {
    warn "GitHub CLI installation failed"
    failures=$((failures + 1))
  }
  install_agent_auth_helper
  install_agent_cli_update_timer
  print_agent_cli_versions

  if [[ "$failures" -gt 0 ]]; then
    fail "one or more selected developer CLIs failed to install; public SSH remains open"
  fi
}

install_agent_cli_update_timer() {
  local home_dir

  home_dir="$(admin_home_dir)"
  install -d -m 0755 /usr/local/sbin

  {
    cat <<'AGENT_CLI_UPDATE_HEAD'
#!/usr/bin/env bash
set -Eeuo pipefail
AGENT_CLI_UPDATE_HEAD
    printf 'admin_user=%q\n' "$admin_user"
    printf 'home_dir=%q\n' "$home_dir"
    agent_audit_prelude
    cat <<'AGENT_CLI_UPDATE_BODY'

run_as_admin() {
  sudo -H -u "$admin_user" env HOME="$home_dir" SHELL=/bin/bash bash -lc "$1"
}

admin_command_path() {
  local command_name="$1"
  local candidate

  case "$command_name" in
    codex)
      for candidate in "$home_dir/.codex/bin/codex" "$home_dir/.local/bin/codex" "$home_dir/bin/codex"; do
        if [[ -x "$candidate" ]]; then
          printf '%s\n' "$candidate"
          return 0
        fi
      done
      ;;
    grok | agent)
      candidate="$home_dir/.grok/bin/$command_name"
      if [[ -x "$candidate" ]]; then
        printf '%s\n' "$candidate"
        return 0
      fi
      ;;
  esac

  run_as_admin "command -v $(printf '%q' "$command_name")" 2>/dev/null || true
}

link_admin_command() {
  local command_name="$1"
  local command_path

  command_path="$(admin_command_path "$command_name")"
  if [[ -z "$command_path" || ! -x "$command_path" ]]; then
    return 1
  fi

  install -d -m 0755 /usr/local/bin
  ln -sf "$command_path" "/usr/local/bin/$command_name"
}

printf '[vps-bootstrap] updating Codex from OpenAI official installer; accepted mutable installer trust boundary\n' >&2
if run_as_admin 'curl -fsSL https://chatgpt.com/codex/install.sh | CODEX_NON_INTERACTIVE=1 sh'; then
  link_admin_command codex || true
else
  printf '[vps-bootstrap] warning: Codex CLI update failed; continuing with other agent CLI updates\n' >&2
fi

if run_as_admin 'command -v grok >/dev/null 2>&1'; then
  printf '[vps-bootstrap] updating Grok with xAI official grok update command; accepted mutable updater trust boundary\n' >&2
  run_as_admin 'grok update' || printf '[vps-bootstrap] warning: Grok CLI update failed\n' >&2
elif [[ -x "$home_dir/.grok/bin/grok" ]]; then
  printf '[vps-bootstrap] updating Grok with xAI official grok update command; accepted mutable updater trust boundary\n' >&2
  run_as_admin "$(printf '%q' "$home_dir/.grok/bin/grok") update" || printf '[vps-bootstrap] warning: Grok CLI update failed\n' >&2
else
  printf '[vps-bootstrap] installing Grok from xAI official installer; accepted mutable installer trust boundary\n' >&2
  run_as_admin 'curl -fsSL https://x.ai/cli/install.sh | bash' || printf '[vps-bootstrap] warning: Grok CLI install failed\n' >&2
fi

link_admin_command grok || true
link_admin_command agent || true
AGENT_CLI_UPDATE_BODY
  } >/usr/local/sbin/vps-agent-cli-update

  chmod 755 /usr/local/sbin/vps-agent-cli-update

  cat >/etc/systemd/system/vps-agent-cli-update.service <<'AGENT_CLI_UPDATE_SERVICE'
[Unit]
Description=Update agent CLIs managed by vps-bootstrap
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStart=/usr/local/sbin/vps-agent-cli-update
AGENT_CLI_UPDATE_SERVICE

  cat >/etc/systemd/system/vps-agent-cli-update.timer <<'AGENT_CLI_UPDATE_TIMER'
[Unit]
Description=Run vps-bootstrap agent CLI updates every two days

[Timer]
OnBootSec=30min
OnUnitActiveSec=2d
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
AGENT_CLI_UPDATE_TIMER

  systemctl daemon-reload
  systemctl enable --now vps-agent-cli-update.timer
}

install_agent_auth_helper() {
  log "installing /usr/local/bin/vps-agent-auth"

  cat >/usr/local/bin/vps-agent-auth <<'AGENT_AUTH_HELPER'
SERVER_SCRIPT_BODY
  cat "$VPS_BOOTSTRAP_LIB_DIR/templates/vps-agent-auth.sh"
  cat << 'SERVER_SCRIPT_BODY'
AGENT_AUTH_HELPER

  chmod 755 /usr/local/bin/vps-agent-auth
}

print_agent_cli_versions() {
  printf 'VPS_BOOTSTRAP_CODEX_VERSION=%s\n' "$(codex --version 2>/dev/null | head -n 1 || true)"
  printf 'VPS_BOOTSTRAP_GROK_VERSION=%s\n' "$(grok --version 2>/dev/null | head -n 1 || true)"
  printf 'VPS_BOOTSTRAP_GH_VERSION=%s\n' "$(gh --version 2>/dev/null | head -n 1 || true)"
}

ensure_admin_user() {
  local home_dir

  if ! getent passwd "$admin_user" >/dev/null 2>&1; then
    log "creating admin user: $admin_user"
    useradd --create-home --shell /bin/bash "$admin_user"
  else
    log "admin user already exists: $admin_user"
  fi

  usermod -aG "$SUDO_GROUP" "$admin_user"
  home_dir="$(getent passwd "$admin_user" | cut -d: -f6)"

  install -d -m 700 -o "$admin_user" -g "$admin_user" "$home_dir/.ssh"
  touch "$home_dir/.ssh/authorized_keys"
  chown "$admin_user:$admin_user" "$home_dir/.ssh/authorized_keys"
  chmod 600 "$home_dir/.ssh/authorized_keys"

  if ! grep -qxF "$public_key" "$home_dir/.ssh/authorized_keys"; then
    log "installing public key for $admin_user"
    printf '%s\n' "$public_key" >>"$home_dir/.ssh/authorized_keys"
  else
    log "public key already present for $admin_user"
  fi

  chown "$admin_user:$admin_user" "$home_dir/.ssh/authorized_keys"
  chmod 600 "$home_dir/.ssh/authorized_keys"

  write_sudoers_policy "$full_sudo"
}

set_requested_hostname() {
  if [[ -z "$requested_hostname" ]]; then
    return 0
  fi

  log "setting hostname: $requested_hostname"
  hostnamectl set-hostname "$requested_hostname"
}

install_tailscale() {
  if command_exists tailscale; then
    log "tailscale is already installed"
  else
    log "installing tailscale with official Linux installer"
    warn "executing Tailscale's mutable official installer as root; this is an accepted supply-chain trust boundary"
    curl -fsSL https://tailscale.com/install.sh | sh
  fi

  enable_service tailscaled
}

ensure_tailscale_connected() {
  local tailscale_hostname attempt

  install_tailscale
  tailscale_hostname="$requested_hostname"
  if [[ -z "$tailscale_hostname" ]]; then
    tailscale_hostname="$(hostname -s)"
  fi

  if ! tailscale ip -4 >/dev/null 2>&1; then
    log "joining Tailnet interactively; approve the login URL printed by Tailscale"
    tailscale up --hostname "$tailscale_hostname"
  fi

  attempt=0
  while [[ "$attempt" -lt 60 ]]; do
    TAILSCALE_IP="$(tailscale ip -4 2>/dev/null | head -n 1 || true)"
    if [[ -n "$TAILSCALE_IP" ]]; then
      log "Tailnet IPv4: $TAILSCALE_IP"
      return 0
    fi

    attempt=$((attempt + 1))
    sleep 2
  done

  fail "tailscale did not report an IPv4 address"
}

disable_tailscale_ssh_for_verification() {
  if ! tailscale set --ssh=false; then
    fail "could not disable Tailscale SSH before OpenSSH verification; public SSH remains open"
  fi
}

enable_tailscale_ssh_if_requested() {
  if [[ "$enable_tailscale_ssh" != "1" ]]; then
    return 0
  fi

  log "enabling Tailscale SSH on this node"
  if ! tailscale set --ssh; then
    fail "Tailscale SSH enable failed; OpenSSH over the Tailnet remains available"
  fi

  warn "Tailscale SSH also requires matching Tailnet ACL SSH rules"
}

configure_ufw() {
  local firewall_phase="$1"

  systemctl enable --now ufw >/dev/null 2>&1 || true
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow in on tailscale0 to any port 22 proto tcp comment 'vps-bootstrap tailnet ssh'

  if [[ "$firewall_phase" == "prepare" ]]; then
    ufw allow 22/tcp comment 'vps-bootstrap temporary public ssh'
  else
    ufw --force delete allow 22/tcp || true
    ufw --force delete allow OpenSSH || true
    ufw --force delete allow ssh || true
  fi

  if [[ "$web_enabled" == "1" ]]; then
    ufw allow 80/tcp comment 'vps-bootstrap public http'
    ufw allow 443/tcp comment 'vps-bootstrap public https'
  else
    ufw --force delete allow 80/tcp || true
    ufw --force delete allow 443/tcp || true
  fi

  ufw --force enable
}

configure_firewalld() {
  local firewall_phase="$1"

  enable_service firewalld
  firewall-cmd --permanent --new-zone=tailnet || true
  firewall-cmd --permanent --zone=tailnet --change-interface=tailscale0
  firewall-cmd --permanent --zone=tailnet --add-service=ssh
  firewall-cmd --set-default-zone=public

  if [[ "$firewall_phase" == "prepare" ]]; then
    firewall-cmd --permanent --zone=public --add-service=ssh
  else
    firewall-cmd --permanent --zone=public --remove-service=ssh || true
  fi

  if [[ "$web_enabled" == "1" ]]; then
    firewall-cmd --permanent --zone=public --add-service=http
    firewall-cmd --permanent --zone=public --add-service=https
  else
    firewall-cmd --permanent --zone=public --remove-service=http || true
    firewall-cmd --permanent --zone=public --remove-service=https || true
  fi

  firewall-cmd --reload
}

configure_firewall() {
  local firewall_phase="$1"

  log "configuring $FIREWALL_BACKEND firewall for phase: $firewall_phase"

  if [[ "$FIREWALL_BACKEND" == "ufw" ]]; then
    configure_ufw "$firewall_phase"
    return 0
  fi

  configure_firewalld "$firewall_phase"
}

validate_effective_sshd_hardening() {
  local connection_host effective_admin effective_root setting

  connection_host="$(hostname)"
  effective_admin="$(sshd -T -C "user=$admin_user,host=$connection_host,addr=127.0.0.1")" ||
    return 1
  effective_root="$(sshd -T -C "user=root,host=$connection_host,addr=127.0.0.1")" ||
    return 1

  for setting in \
    "pubkeyauthentication yes" \
    "passwordauthentication no" \
    "kbdinteractiveauthentication no" \
    "permitemptypasswords no"; do
    grep -qxF "$setting" <<<"$effective_admin" || return 1
  done

  grep -qxF "permitrootlogin no" <<<"$effective_root"
}

write_sshd_hardening() {
  local snippet include_backup

  snippet="/etc/ssh/sshd_config.d/00-vps-bootstrap-hardening.conf"
  install -d -m 755 /etc/ssh/sshd_config.d

  if ! grep -Eiq '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/\*\.conf' /etc/ssh/sshd_config; then
    include_backup="/etc/ssh/sshd_config.vps-bootstrap.bak.$(date +%Y%m%d%H%M%S)"
    cp -p /etc/ssh/sshd_config "$include_backup"
    {
      printf 'Include /etc/ssh/sshd_config.d/*.conf\n\n'
      cat /etc/ssh/sshd_config
    } >"${snippet}.tmp"
    install -m 644 "${snippet}.tmp" /etc/ssh/sshd_config
    rm -f "${snippet}.tmp"
    log "added sshd_config Include; backup: $include_backup"
  fi

  cat >"$snippet" <<'SSHD_CONFIG'
# Managed by vps-bootstrap. Do not edit directly.
PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
ChallengeResponseAuthentication no
PermitRootLogin no
PermitEmptyPasswords no
MaxAuthTries 3
X11Forwarding no
SSHD_CONFIG

  chmod 644 "$snippet"

  if ! sshd -t; then
    rm -f "$snippet"
    fail "sshd -t failed; removed hardening snippet and left current SSH policy active"
  fi

  rm -f /etc/ssh/sshd_config.d/90-vps-bootstrap-hardening.conf
  if ! validate_effective_sshd_hardening; then
    rm -f "$snippet"
    fail "effective sshd settings did not match the hardening policy; public SSH remains open"
  fi

  if ! systemctl reload "$SSHD_SERVICE"; then
    systemctl restart "$SSHD_SERVICE"
  fi
}

validate_prepare_state() {
  local home_dir

  getent passwd "$admin_user" >/dev/null 2>&1 || fail "admin user missing after creation"
  home_dir="$(getent passwd "$admin_user" | cut -d: -f6)"
  [[ -s "$home_dir/.ssh/authorized_keys" ]] || fail "authorized_keys missing for $admin_user"
  [[ -n "$TAILSCALE_IP" ]] || fail "Tailnet IP missing"
  systemctl is-active "$SSHD_SERVICE" >/dev/null 2>&1 || fail "$SSHD_SERVICE is not active"
  if [[ "$swap_enabled" == "1" ]] && ! has_active_swap; then
    fail "swap is not active"
  fi
}

run_prepare() {
  require_root
  validate_admin_user_server
  validate_hostname_server
  select_platform
  install_required_packages
  install_swap
  enable_service "$SSHD_SERVICE"
  configure_automatic_updates
  install_ban_service
  ensure_admin_user
  install_agent_sudo_helpers
  set_requested_hostname
  ensure_tailscale_connected
  disable_tailscale_ssh_for_verification
  configure_firewall prepare
  validate_prepare_state
  install_agent_clis_if_requested

  printf 'VPS_BOOTSTRAP_TAILSCALE_IP=%s\n' "$TAILSCALE_IP"
  printf 'VPS_BOOTSTRAP_FIREWALL=%s\n' "$FIREWALL_BACKEND"
  printf 'VPS_BOOTSTRAP_SWAP=%s\n' "$([[ "$swap_enabled" == "1" ]] && printf 'enabled' || printf 'disabled')"
  log "prepare phase complete; public SSH remains available until you verify the Tailnet admin login"
}

run_harden() {
  require_root
  validate_admin_user_server
  validate_hostname_server
  select_platform
  ensure_tailscale_connected
  install_agent_sudo_helpers
  write_sshd_hardening
  write_sudoers_policy "$full_sudo"
  configure_firewall harden
  enable_tailscale_ssh_if_requested

  printf 'VPS_BOOTSTRAP_TAILSCALE_IP=%s\n' "$TAILSCALE_IP"
  printf 'VPS_BOOTSTRAP_FIREWALL=%s\n' "$FIREWALL_BACKEND"
  log "harden phase complete; SSH is restricted to Tailnet and public web ports follow requested policy"
}

case "$phase" in
  prepare)
    run_prepare
    ;;
  harden)
    run_harden
    ;;
  *)
    fail "unknown phase: $phase"
    ;;
esac
SERVER_SCRIPT_BODY
}

generate_server_config_prelude() {
  local selected_phase="$1"

  printf 'phase=%q\n' "$selected_phase"
  printf 'admin_user=%q\n' "$VPS_ADMIN_USER"
  printf 'public_key=%q\n' "$VPS_PUBLIC_KEY"
  printf 'requested_hostname=%q\n' "$VPS_HOSTNAME"
  printf 'enable_tailscale_ssh=%q\n' "$VPS_ENABLE_TAILSCALE_SSH"
  printf 'web_enabled=%q\n' "$VPS_WEB"
  printf 'install_agent_clis=%q\n' "$VPS_INSTALL_AGENT_CLIS"
  printf 'automatic_updates=%q\n' "$VPS_AUTOMATIC_UPDATES"
  printf 'full_sudo=%q\n' "$VPS_FULL_SUDO"
  printf 'swap_enabled=%q\n' "$VPS_SWAP_ENABLED"
  printf 'swap_size=%q\n' "$VPS_SWAP_SIZE"
}

run_server_phase() {
  local selected_phase="$1"
  local phase_script status

  phase_script="$(mktemp "${TMPDIR:-/tmp}/vps-bootstrap-${selected_phase}.XXXXXX")" || return 1
  chmod 700 "$phase_script"
  {
    generate_server_config_prelude "$selected_phase"
    generate_server_script
  } > "$phase_script"

  if bash "$phase_script"; then
    status=0
  else
    status=$?
  fi
  rm -f "$phase_script"
  return "$status"
}

tailnet_ipv4() {
  tailscale ip -4 2> /dev/null | awk 'NF { print; exit }'
}

verify_prepared_admin() {
  sudo -H -u "$VPS_ADMIN_USER" sudo -n /usr/local/sbin/vps-agent-sudo-check
}

confirm_tailnet_login() {
  local tailnet_ip="$1"
  local answer

  cat >&2 << PROMPT

[vps-bootstrap] Prepare is complete. Public SSH is still open.
[vps-bootstrap] From another terminal on a device in your Tailnet, run:
[vps-bootstrap]   ssh $VPS_ADMIN_USER@$tailnet_ip
[vps-bootstrap] Keep this session open until that login works.
[vps-bootstrap] Type yes only after the Tailnet login succeeds:
PROMPT
  answer="$(read_interactive_answer)" || return 1
  case "$answer" in
    yes | YES | Yes)
      return 0
      ;;
    *)
      cat >&2 << PAUSED
[vps-bootstrap] Setup paused. Public SSH remains open.
[vps-bootstrap] Rerun this installer when you are ready to verify and harden the VPS.
PAUSED
      return 1
      ;;
  esac
}

print_completion_summary() {
  local tailnet_ip="$1"

  cat << SUMMARY

Bootstrap complete.

Admin user: $VPS_ADMIN_USER
Tailnet SSH target: $VPS_ADMIN_USER@$tailnet_ip
Swap: $VPS_SWAP_ACTION

Public inbound policy:
  - TCP 22: Tailnet only
  - TCP 80/443: $([[ "$VPS_WEB" == "1" ]] && printf 'public' || printf 'closed')

Mirror this policy in the VPS provider firewall.
SUMMARY

  if [[ "$VPS_INSTALL_AGENT_CLIS" == "1" ]]; then
    cat << 'AUTH'

Authenticate the developer CLIs while logged in as the admin user:
  vps-agent-auth --all
  vps-agent-auth --status
AUTH
  fi
}

run_bootstrap() {
  local confirmed tailnet_ip

  if [[ "$VPS_DRY_RUN" != "1" ]]; then
    require_vps_root || return 1
  fi

  collect_configuration || return 1
  configuration_summary

  if [[ "$VPS_DRY_RUN" == "1" ]]; then
    printf '\nDry run complete; no server changes were made.\n'
    return 0
  fi

  confirmed="$(prompt_yes_no "Apply this configuration to the VPS")" || return 1
  if [[ "$confirmed" != "1" ]]; then
    printf '[vps-bootstrap] No server changes were made.\n'
    return 0
  fi

  printf '[vps-bootstrap] Phase 1: prepare the VPS while public SSH remains open.\n'
  run_server_phase prepare || return 1

  tailnet_ip="$(tailnet_ipv4)"
  if [[ -z "$tailnet_ip" ]]; then
    error "Tailscale did not return an IPv4 address; public SSH remains open"
    return 1
  fi

  if ! verify_prepared_admin; then
    error "the new admin user failed the local sudo check; public SSH remains open"
    return 1
  fi

  if ! confirm_tailnet_login "$tailnet_ip"; then
    return 0
  fi

  printf '[vps-bootstrap] Phase 2: apply SSH and firewall hardening.\n'
  run_server_phase harden || return 1
  print_completion_summary "$tailnet_ip"
}

main() {
  reset_config
  parse_args "$@" || return 1

  if [[ "$VPS_SHOW_HELP" == "1" ]]; then
    usage
    return 0
  fi

  run_bootstrap
}
