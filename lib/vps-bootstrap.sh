#!/usr/bin/env bash

VPS_BOOTSTRAP_LIB_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

reset_config() {
  VPS_HOST=""
  VPS_LOGIN_USER=""
  VPS_ADMIN_USER="deploy"
  VPS_PUBKEY="${HOME}/.ssh/id_ed25519.pub"
  VPS_IDENTITY=""
  VPS_LOGIN_IDENTITY=""
  VPS_INITIAL_SSH_OPTIONS=()
  VPS_HOSTNAME=""
  VPS_ENABLE_TAILSCALE_SSH="0"
  VPS_INSTALL_AGENT_CLIS="0"
  VPS_FULL_SUDO="0"
  VPS_SWAP_ENABLED="1"
  VPS_SWAP_SIZE="2G"
  VPS_WEB="1"
  VPS_DRY_RUN="0"
  VPS_DOCTOR="0"
  VPS_DOCTOR_FAILURES="0"
  VPS_SHOW_HELP="0"
}

reset_config

error() {
  printf 'vps-bootstrap: %s\n' "$*" >&2
}

usage() {
  cat << 'USAGE'
Usage:
  vps-bootstrap --host <ip-or-hostname> [options]
  vps-bootstrap doctor [options]

Options:
  --host <host>                 Public VPS address for the initial SSH login.
  --login-user <name>           Provider's initial SSH user. Required for bootstrap and dry-run.
  --login-identity <path>       Private key for the initial SSH login. Optional; use SSH agent/config otherwise.
  --user <name>                 Admin sudo user to create. Default: deploy.
  --pubkey <path>               Public key to install. Default: ~/.ssh/id_ed25519.pub.
  --identity <path>             Private key used to verify Tailnet login. Default: pubkey without .pub.
  --hostname <name>             Hostname to set on the server and use for Tailscale.
  --enable-tailscale-ssh        Enable Tailscale SSH after joining the Tailnet.
  --install-agent-clis          Install Codex, Grok, and GitHub CLIs. Opt-in.
  --skip-agent-clis             Skip Codex, Grok, and GitHub CLI installation. Default.
  --full-sudo                   Use NOPASSWD:ALL instead of scoped passwordless sudo.
  --swap-size <size>            Create this swap size when no active swap exists. Default: 2G.
  --no-swap                     Do not create or enable swap during prepare.
  --web                         Keep public TCP 80/443 open. Default.
  --web=false                   Disable public TCP 80/443.
  --no-web                      Disable public TCP 80/443.
  --dry-run                     Print the phased plan without opening SSH connections.
  -h, --help                    Show this help.

The tool uses --login-user for the first public SSH connection. Pass
--login-identity when the provider requires a key that is not already available
through your SSH agent or config. Before that first connection, paste the
provider SSH host key if available, or press Enter to scan the live host key and
confirm its fingerprint before pinning it.

The doctor command performs local/read-only checks only. Run it from your
workstation before bootstrap or on a bootstrapped VPS after setup.
USAGE
}

parse_bool() {
  local value lowered
  value="$1"
  lowered="$(printf '%s' "$value" | tr '[:upper:]' '[:lower:]')"

  case "$lowered" in
    1 | true | yes | y | on)
      printf '1'
      ;;
    0 | false | no | n | off)
      printf '0'
      ;;
    *)
      return 1
      ;;
  esac
}

require_option_value() {
  local option="$1"
  local value="${2-}"

  if [[ -z "$value" || "$value" == --* ]]; then
    error "$option requires a value"
    return 1
  fi
}

validate_admin_user() {
  local user="$1"

  if [[ ! "$user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    error "user must match ^[a-z_][a-z0-9_-]{0,31}$"
    return 1
  fi
}

validate_hostname() {
  local hostname="$1"

  if [[ -z "$hostname" ]]; then
    return 0
  fi

  if [[ ! "$hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,251}[A-Za-z0-9]$ ]]; then
    error "hostname must contain only letters, numbers, dots, and hyphens"
    return 1
  fi
}

validate_swap_size() {
  local size="$1"

  if [[ ! "$size" =~ ^[1-9][0-9]*[MmGg]$ ]]; then
    error "swap size must be a positive whole number followed by M or G, for example 2G"
    return 1
  fi
}

detect_identity_path() {
  local pubkey_path="$1"

  case "$pubkey_path" in
    *.pub)
      printf '%s' "${pubkey_path%.pub}"
      ;;
    *)
      printf '%s' "$pubkey_path"
      ;;
  esac
}

parse_args() {
  local parsed_bool

  if [[ "${1-}" == "doctor" ]]; then
    VPS_DOCTOR="1"
    shift
  fi

  while [[ "$#" -gt 0 ]]; do
    case "$1" in
      --host)
        require_option_value "$1" "${2-}" || return 1
        VPS_HOST="$2"
        shift 2
        ;;
      --host=*)
        VPS_HOST="${1#*=}"
        shift
        ;;
      --login-user)
        require_option_value "$1" "${2-}" || return 1
        VPS_LOGIN_USER="$2"
        shift 2
        ;;
      --login-user=*)
        VPS_LOGIN_USER="${1#*=}"
        shift
        ;;
      --login-identity)
        require_option_value "$1" "${2-}" || return 1
        VPS_LOGIN_IDENTITY="$2"
        shift 2
        ;;
      --login-identity=*)
        VPS_LOGIN_IDENTITY="${1#*=}"
        shift
        ;;
      --user)
        require_option_value "$1" "${2-}" || return 1
        VPS_ADMIN_USER="$2"
        shift 2
        ;;
      --user=*)
        VPS_ADMIN_USER="${1#*=}"
        shift
        ;;
      --pubkey)
        require_option_value "$1" "${2-}" || return 1
        VPS_PUBKEY="$2"
        shift 2
        ;;
      --pubkey=*)
        VPS_PUBKEY="${1#*=}"
        shift
        ;;
      --identity)
        require_option_value "$1" "${2-}" || return 1
        VPS_IDENTITY="$2"
        shift 2
        ;;
      --identity=*)
        VPS_IDENTITY="${1#*=}"
        shift
        ;;
      --hostname)
        require_option_value "$1" "${2-}" || return 1
        VPS_HOSTNAME="$2"
        shift 2
        ;;
      --hostname=*)
        VPS_HOSTNAME="${1#*=}"
        shift
        ;;
      --enable-tailscale-ssh)
        VPS_ENABLE_TAILSCALE_SSH="1"
        shift
        ;;
      --install-agent-clis)
        VPS_INSTALL_AGENT_CLIS="1"
        shift
        ;;
      --skip-agent-clis | --no-agent-clis)
        VPS_INSTALL_AGENT_CLIS="0"
        shift
        ;;
      --full-sudo)
        VPS_FULL_SUDO="1"
        shift
        ;;
      --swap-size)
        require_option_value "$1" "${2-}" || return 1
        VPS_SWAP_SIZE="$2"
        shift 2
        ;;
      --swap-size=*)
        VPS_SWAP_SIZE="${1#*=}"
        shift
        ;;
      --no-swap)
        VPS_SWAP_ENABLED="0"
        shift
        ;;
      --web)
        VPS_WEB="1"
        shift
        ;;
      --web=*)
        parsed_bool="$(parse_bool "${1#*=}")" || {
          error "--web expects true or false"
          return 1
        }
        VPS_WEB="$parsed_bool"
        shift
        ;;
      --no-web)
        VPS_WEB="0"
        shift
        ;;
      --dry-run)
        VPS_DRY_RUN="1"
        shift
        ;;
      -h | --help)
        VPS_SHOW_HELP="1"
        shift
        ;;
      *)
        error "unknown option: $1"
        return 1
        ;;
    esac
  done

  if [[ "$VPS_SHOW_HELP" == "1" ]]; then
    return 0
  fi

  if [[ -z "$VPS_HOST" && "$VPS_DOCTOR" != "1" ]]; then
    error "--host is required"
    return 1
  fi

  if [[ -z "$VPS_LOGIN_USER" && "$VPS_DOCTOR" != "1" ]]; then
    error "--login-user is required; pass the provider image SSH user"
    return 1
  fi

  if [[ -n "$VPS_HOST" && "$VPS_HOST" == *@* ]]; then
    error "--host expects a hostname or IP only; pass the SSH username with --login-user"
    return 1
  fi

  if [[ -n "$VPS_LOGIN_USER" ]]; then
    validate_admin_user "$VPS_LOGIN_USER" || return 1
  fi
  validate_admin_user "$VPS_ADMIN_USER" || return 1
  validate_hostname "$VPS_HOSTNAME" || return 1
  validate_swap_size "$VPS_SWAP_SIZE" || return 1

  if [[ -z "$VPS_IDENTITY" ]]; then
    VPS_IDENTITY="$(detect_identity_path "$VPS_PUBKEY")"
  fi
}

read_public_key() {
  local pubkey_path="$1"
  local line

  if [[ ! -r "$pubkey_path" ]]; then
    error "public key is not readable: $pubkey_path"
    return 1
  fi

  while IFS= read -r line || [[ -n "$line" ]]; do
    case "$line" in
      '' | \#*)
        continue
        ;;
      ssh-* | ecdsa-* | sk-*)
        printf '%s' "$line"
        return 0
        ;;
      *)
        error "public key does not look like an OpenSSH public key: $pubkey_path"
        return 1
        ;;
    esac
  done < "$pubkey_path"

  error "public key file is empty: $pubkey_path"
  return 1
}

validate_local_files() {
  read_public_key "$VPS_PUBKEY" > /dev/null || return 1

  if [[ ! -r "$VPS_IDENTITY" ]]; then
    error "identity file is not readable: $VPS_IDENTITY"
    error "pass --identity if the private key is not ${VPS_PUBKEY%.pub}"
    return 1
  fi

  if [[ -n "$VPS_LOGIN_IDENTITY" && ! -r "$VPS_LOGIN_IDENTITY" ]]; then
    error "login identity file is not readable: $VPS_LOGIN_IDENTITY"
    return 1
  fi
}

shell_quote() {
  printf '%q' "$1"
}

set_initial_ssh_options() {
  local known_hosts_file="$1"

  VPS_INITIAL_SSH_OPTIONS=(
    -o "UserKnownHostsFile=$known_hosts_file"
    -o HostKeyAlias=vps-bootstrap-target
    -o StrictHostKeyChecking=yes
  )

  if [[ -n "$VPS_LOGIN_IDENTITY" ]]; then
    VPS_INITIAL_SSH_OPTIONS+=(-i "$VPS_LOGIN_IDENTITY" -o IdentitiesOnly=yes)
  fi
}

generate_sshd_hardening_config() {
  cat << 'SSHD_CONFIG'
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
}

generate_sudoers_policy() {
  local admin_user="$1"
  local full_sudo="$2"

  if [[ "$full_sudo" == "1" ]]; then
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$admin_user"
    return 0
  fi

  cat << SUDOERS_POLICY
# Managed by vps-bootstrap. Passwordless sudo is limited to root-owned helpers.
Cmnd_Alias VPS_AGENT_HELPERS = /usr/local/sbin/vps-agent-sudo-check, /usr/local/sbin/vps-agent-package, /usr/local/sbin/vps-agent-service, /usr/local/sbin/vps-agent-logs, /usr/local/sbin/vps-agent-firewall, /usr/local/sbin/vps-agent-deploy, /usr/local/sbin/vps-agent-cli-update, /usr/local/sbin/vps-os-update
$admin_user ALL=(root) NOPASSWD: VPS_AGENT_HELPERS
SUDOERS_POLICY
}

validate_host_public_key_line() {
  local key_line="$1"

  case "$key_line" in
    ssh-*' '* | ecdsa-*' '* | sk-*' '*)
      return 0
      ;;
    *)
      error "host public key must be one OpenSSH public key line, for example: ssh-ed25519 AAAA..."
      return 1
      ;;
  esac
}

extract_keyscan_public_key() {
  awk '
    $1 !~ /^#/ && $2 ~ /^(ssh-|ecdsa-|sk-)/ {
      $1 = ""
      sub(/^ /, "")
      print
      exit
    }
  '
}

host_public_key_fingerprint() {
  local key_line="$1"

  printf '%s\n' "$key_line" | ssh-keygen -lf - 2> /dev/null
}

scan_host_public_key() {
  local keyscan_output key_line

  if ! command -v ssh-keyscan > /dev/null 2>&1; then
    error "ssh-keyscan is required when the provider does not publish the SSH host key"
    return 1
  fi

  keyscan_output="$(ssh-keyscan -T 10 "$VPS_HOST" 2> /dev/null)" || {
    error "could not scan SSH host key from $VPS_HOST"
    return 1
  }
  key_line="$(printf '%s\n' "$keyscan_output" | extract_keyscan_public_key)"
  if [[ -z "$key_line" ]]; then
    error "could not find an OpenSSH host key in ssh-keyscan output for $VPS_HOST"
    return 1
  fi

  validate_host_public_key_line "$key_line" || return 1
  printf '%s\n' "$key_line"
}

confirm_scanned_host_public_key() {
  local key_line="$1"
  local fingerprint answer

  fingerprint="$(host_public_key_fingerprint "$key_line")" || {
    error "could not calculate scanned SSH host key fingerprint"
    return 1
  }

  cat >&2 << PROMPT
[vps-bootstrap] Scanned SSH host key from $VPS_HOST:
[vps-bootstrap]   $key_line
[vps-bootstrap] Fingerprint:
[vps-bootstrap]   $fingerprint
[vps-bootstrap] If this is a fresh VPS and your provider does not expose a host key, type yes to trust and pin this key for bootstrap:
PROMPT
  IFS= read -r answer
  case "$answer" in
    yes | YES | Yes)
      return 0
      ;;
    *)
      error "SSH host key was not trusted; bootstrap stopped before connecting"
      return 1
      ;;
  esac
}

prompt_host_public_key() {
  local key_line
  local scanned_key

  cat >&2 << PROMPT
[vps-bootstrap] If your provider shows the VPS SSH host public key, paste it here.
[vps-bootstrap] If not, press Enter to scan the live SSH host key and confirm its fingerprint.
[vps-bootstrap] This is the server host key, not your user login key.
[vps-bootstrap] Example: ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAA...
Host public key, or Enter to scan:
PROMPT
  IFS= read -r key_line
  if [[ -z "$key_line" ]]; then
    scanned_key="$(scan_host_public_key)" || return 1
    confirm_scanned_host_public_key "$scanned_key" || return 1
    printf '%s\n' "$scanned_key"
    return 0
  fi

  validate_host_public_key_line "$key_line" || return 1
  printf '%s\n' "$key_line"
}

write_known_hosts_file() {
  local key_line="$1"
  local output="$2"

  validate_host_public_key_line "$key_line" || return 1
  umask 077
  printf 'vps-bootstrap-target %s\n' "$key_line" > "$output"
}

generate_ufw_rules() {
  local phase="$1"
  local web_enabled="$2"

  cat << 'UFW_RULES'
ufw default deny incoming
ufw default allow outgoing
ufw allow in on tailscale0 to any port 22 proto tcp comment 'vps-bootstrap tailnet ssh'
UFW_RULES

  if [[ "$phase" == "prepare" ]]; then
    cat << 'UFW_PREPARE'
ufw allow 22/tcp comment 'vps-bootstrap temporary public ssh'
UFW_PREPARE
  else
    cat << 'UFW_HARDEN'
ufw --force delete allow 22/tcp || true
ufw --force delete allow OpenSSH || true
ufw --force delete allow ssh || true
UFW_HARDEN
  fi

  if [[ "$web_enabled" == "1" ]]; then
    cat << 'UFW_WEB'
ufw allow 80/tcp comment 'vps-bootstrap public http'
ufw allow 443/tcp comment 'vps-bootstrap public https'
UFW_WEB
  else
    cat << 'UFW_NO_WEB'
ufw --force delete allow 80/tcp || true
ufw --force delete allow 443/tcp || true
UFW_NO_WEB
  fi

  printf 'ufw --force enable\n'
}

generate_firewalld_rules() {
  local phase="$1"
  local web_enabled="$2"

  cat << 'FIREWALLD_RULES'
firewall-cmd --permanent --new-zone=tailnet || true
firewall-cmd --permanent --zone=tailnet --change-interface=tailscale0
firewall-cmd --permanent --zone=tailnet --add-service=ssh
firewall-cmd --set-default-zone=public
FIREWALLD_RULES

  if [[ "$phase" == "prepare" ]]; then
    printf 'firewall-cmd --permanent --zone=public --add-service=ssh\n'
  else
    printf 'firewall-cmd --permanent --zone=public --remove-service=ssh || true\n'
  fi

  if [[ "$web_enabled" == "1" ]]; then
    cat << 'FIREWALLD_WEB'
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --permanent --zone=public --add-service=https
FIREWALLD_WEB
  else
    cat << 'FIREWALLD_NO_WEB'
firewall-cmd --permanent --zone=public --remove-service=http || true
firewall-cmd --permanent --zone=public --remove-service=https || true
FIREWALLD_NO_WEB
  fi

  printf 'firewall-cmd --reload\n'
}

generate_remote_script() {
  cat << 'REMOTE_SCRIPT_HEAD'
#!/usr/bin/env bash
set -Eeuo pipefail

: "${phase:?phase required}"
: "${admin_user:?admin user required}"
: "${public_key:?public key required}"
requested_hostname="${requested_hostname:-}"
enable_tailscale_ssh="${enable_tailscale_ssh:-0}"
web_enabled="${web_enabled:-1}"
install_agent_clis="${install_agent_clis:-0}"
full_sudo="${full_sudo:-0}"
swap_enabled="${swap_enabled:-1}"
swap_size="${swap_size:-2G}"

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
    fail "remote script must run as root"
  fi
}

validate_admin_user_remote() {
  if [[ ! "$admin_user" =~ ^[a-z_][a-z0-9_-]{0,31}$ ]]; then
    fail "admin user must match ^[a-z_][a-z0-9_-]{0,31}$"
  fi
}

validate_hostname_remote() {
  if [[ -z "$requested_hostname" ]]; then
    return 0
  fi

  if [[ ! "$requested_hostname" =~ ^[A-Za-z0-9][A-Za-z0-9.-]{0,251}[A-Za-z0-9]$ ]]; then
    fail "hostname must contain only letters, numbers, dots, and hyphens"
  fi
}

validate_swap_size_remote() {
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
    apt-get install -y sudo ca-certificates curl gnupg git openssh-server ufw unattended-upgrades util-linux
    return 0
  fi

  if [[ "$PKG_BACKEND" == "dnf" ]]; then
    dnf makecache -y
    dnf install -y sudo ca-certificates curl git openssh-server firewalld util-linux
    install_optional_package dnf-automatic || true
    return 0
  fi

  yum makecache -y
  yum install -y sudo ca-certificates curl git openssh-server firewalld util-linux
  install_optional_package dnf-automatic || true
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

  validate_swap_size_remote
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

configure_automatic_updates() {
  if [[ "$PKG_BACKEND" == "apt" ]]; then
    if command_exists dpkg-reconfigure; then
      printf 'unattended-upgrades unattended-upgrades/enable_auto_updates boolean true\n' | debconf-set-selections || true
      dpkg-reconfigure -f noninteractive unattended-upgrades || true
    fi

    cat >/etc/apt/apt.conf.d/20auto-upgrades <<'APT_AUTO_UPGRADES'
APT::Periodic::Update-Package-Lists "14";
APT::Periodic::Unattended-Upgrade "14";
APT::Periodic::AutocleanInterval "14";
APT_AUTO_UPGRADES

    systemctl enable --now unattended-upgrades >/dev/null 2>&1 || warn "unattended-upgrades service not enabled"
  elif command_exists dnf-automatic; then
    log "dnf-automatic is installed; vps-os-update.timer controls the two-week update cadence"
  else
    warn "dnf-automatic is unavailable; vps-os-update.timer will still run package-manager updates"
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
REMOTE_SCRIPT_HEAD
  cat "$VPS_BOOTSTRAP_LIB_DIR/templates/vps-agent-audit-prelude.sh"
  cat << 'REMOTE_SCRIPT_BODY'
AGENT_AUDIT_PRELUDE
}

generate_sudoers_policy_remote() {
  local policy_full="${1:-$full_sudo}"

  if [[ "$policy_full" == "1" ]]; then
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$admin_user"
    return 0
  fi

  cat <<SUDOERS_POLICY
# Managed by vps-bootstrap. Passwordless sudo is limited to root-owned helpers.
Cmnd_Alias VPS_AGENT_HELPERS = /usr/local/sbin/vps-agent-sudo-check, /usr/local/sbin/vps-agent-package, /usr/local/sbin/vps-agent-service, /usr/local/sbin/vps-agent-logs, /usr/local/sbin/vps-agent-firewall, /usr/local/sbin/vps-agent-deploy, /usr/local/sbin/vps-agent-cli-update, /usr/local/sbin/vps-os-update
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

  {
    cat <<'DEPLOY_HELPER_HEAD'
#!/usr/bin/env bash
set -Eeuo pipefail
DEPLOY_HELPER_HEAD
    printf 'admin_user=%q\n' "$admin_user"
    printf 'home_dir=%q\n' "$home_dir"
    agent_audit_prelude
    cat <<'DEPLOY_HELPER_BODY'

usage() {
  printf 'Usage: vps-agent-deploy <source-dir> <target-dir-under-/srv-or-/var/www>\n' >&2
  exit 2
}

[[ "$#" -eq 2 ]] || usage
source_dir="${1%/}"
target_dir="${2%/}"

case "$source_dir" in
  "$home_dir"/* | /tmp/*)
    ;;
  *)
    printf 'source must be under %s or /tmp\n' "$home_dir" >&2
    exit 2
    ;;
esac

case "$target_dir" in
  /srv/* | /var/www/*)
    ;;
  *)
    printf 'target must be under /srv or /var/www\n' >&2
    exit 2
    ;;
esac

[[ -d "$source_dir" ]] || {
  printf 'source directory does not exist: %s\n' "$source_dir" >&2
  exit 2
}

install -d -m 0755 "$target_dir"
rsync -a --delete "$source_dir"/ "$target_dir"/
chown -R "$admin_user:$admin_user" "$target_dir"
DEPLOY_HELPER_BODY
  } >/usr/local/sbin/vps-agent-deploy

  chmod 755 \
    /usr/local/sbin/vps-agent-sudo-check \
    /usr/local/sbin/vps-agent-package \
    /usr/local/sbin/vps-agent-service \
    /usr/local/sbin/vps-agent-logs \
    /usr/local/sbin/vps-agent-firewall \
    /usr/local/sbin/vps-agent-deploy
}

write_sudoers_policy() {
  local policy_full="${1:-$full_sudo}"
  local sudoers_file

  sudoers_file="/etc/sudoers.d/90-vps-bootstrap-$admin_user"
  generate_sudoers_policy_remote "$policy_full" >"$sudoers_file"
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
  if [[ "$install_agent_clis" != "1" ]]; then
    log "developer CLI installation skipped"
    return 0
  fi

  install_codex_cli || warn "Codex CLI installation failed; continuing with bootstrap"
  remove_legacy_third_party_grok_cli || warn "legacy third-party Grok CLI removal failed; continuing with bootstrap"
  install_grok_cli || warn "Grok CLI installation failed; continuing with bootstrap"
  install_github_cli || warn "GitHub CLI installation failed; continuing with bootstrap"
  install_agent_auth_helper
  install_agent_cli_update_timer
  print_agent_cli_versions
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
REMOTE_SCRIPT_BODY
  cat "$VPS_BOOTSTRAP_LIB_DIR/templates/vps-agent-auth.sh"
  cat << 'REMOTE_SCRIPT_BODY'
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

  # The harden phase runs through `sudo bash -s` after local key verification.
  # It rewrites this temporary broad policy to the requested final policy.
  write_sudoers_policy "1"
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

enable_tailscale_ssh_if_requested() {
  if [[ "$enable_tailscale_ssh" != "1" ]]; then
    return 0
  fi

  log "enabling Tailscale SSH on this node"
  if ! tailscale set --ssh; then
    warn "Tailscale SSH enable failed; OpenSSH over Tailnet remains the supported access path"
    return 0
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

write_sshd_hardening() {
  local snippet include_backup

  snippet="/etc/ssh/sshd_config.d/90-vps-bootstrap-hardening.conf"
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
  validate_admin_user_remote
  validate_hostname_remote
  select_platform
  install_required_packages
  install_swap
  enable_service "$SSHD_SERVICE"
  configure_automatic_updates
  install_ban_service
  ensure_admin_user
  install_agent_sudo_helpers
  set_requested_hostname
  install_agent_clis_if_requested
  ensure_tailscale_connected
  configure_firewall prepare
  validate_prepare_state

  printf 'VPS_BOOTSTRAP_TAILSCALE_IP=%s\n' "$TAILSCALE_IP"
  printf 'VPS_BOOTSTRAP_FIREWALL=%s\n' "$FIREWALL_BACKEND"
  printf 'VPS_BOOTSTRAP_SWAP=%s\n' "$([[ "$swap_enabled" == "1" ]] && printf 'enabled' || printf 'disabled')"
  log "prepare phase complete; public SSH remains available until local Tailnet login verification passes"
}

run_harden() {
  require_root
  validate_admin_user_remote
  validate_hostname_remote
  select_platform
  ensure_tailscale_connected
  install_agent_sudo_helpers
  configure_firewall harden
  write_sshd_hardening
  write_sudoers_policy "$full_sudo"
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
REMOTE_SCRIPT_BODY
}

build_prepare_command() {
  local login_user="$1"
  local host="$2"
  local login_identity="${3-}"
  local login_options=""

  if [[ -n "$login_identity" ]]; then
    login_options="-i $(shell_quote "$login_identity") -o IdentitiesOnly=yes "
  fi

  if [[ "$login_user" == "root" ]]; then
    printf 'paste or scan host public key -> temporary known_hosts; stream config + script | ssh -tt %s-o UserKnownHostsFile=<temporary-known-hosts> -o HostKeyAlias=vps-bootstrap-target -o StrictHostKeyChecking=yes %s %s' \
      "$login_options" \
      "$(shell_quote "$login_user@$host")" \
      "$(shell_quote "bash -s")"
    return 0
  fi

  printf 'paste or scan host public key -> temporary known_hosts; upload temporary script with scp; ssh -tt %s-o UserKnownHostsFile=<temporary-known-hosts> -o HostKeyAlias=vps-bootstrap-target -o StrictHostKeyChecking=yes %s %s' \
    "$login_options" \
    "$(shell_quote "$login_user@$host")" \
    "$(shell_quote "sudo bash <remote-temp-script> prepare")"
}

build_admin_verify_command() {
  local admin_user="$1"
  local tailnet_ip="$2"
  local identity="$3"

  printf 'ssh -i %s -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile=<temporary-known-hosts> -o HostKeyAlias=vps-bootstrap-target -o StrictHostKeyChecking=yes %s %s' \
    "$(shell_quote "$identity")" \
    "$(shell_quote "$admin_user@$tailnet_ip")" \
    "'sudo -n /usr/local/sbin/vps-agent-sudo-check'"
}

build_admin_harden_command() {
  local admin_user="$1"
  local tailnet_ip="$2"
  local identity="$3"

  printf 'stream config + script | ssh -tt -i %s -o IdentitiesOnly=yes -o BatchMode=yes -o UserKnownHostsFile=<temporary-known-hosts> -o HostKeyAlias=vps-bootstrap-target -o StrictHostKeyChecking=yes %s %s' \
    "$(shell_quote "$identity")" \
    "$(shell_quote "$admin_user@$tailnet_ip")" \
    "$(shell_quote "sudo bash -s")"
}

generate_remote_config_prelude() {
  local phase="$1"
  local public_key="$2"

  printf 'phase=%q\n' "$phase"
  printf 'admin_user=%q\n' "$VPS_ADMIN_USER"
  printf 'public_key=%q\n' "$public_key"
  printf 'requested_hostname=%q\n' "$VPS_HOSTNAME"
  printf 'enable_tailscale_ssh=%q\n' "$VPS_ENABLE_TAILSCALE_SSH"
  printf 'web_enabled=%q\n' "$VPS_WEB"
  printf 'install_agent_clis=%q\n' "$VPS_INSTALL_AGENT_CLIS"
  printf 'full_sudo=%q\n' "$VPS_FULL_SUDO"
  printf 'swap_enabled=%q\n' "$VPS_SWAP_ENABLED"
  printf 'swap_size=%q\n' "$VPS_SWAP_SIZE"
}

parse_prepare_tailnet_ip() {
  local output="$1"

  printf '%s\n' "$output" |
    sed -n 's/.*VPS_BOOTSTRAP_TAILSCALE_IP=//p' |
    tail -n 1 |
    tr -d '\r'
}

confirm_harden_after_manual_ssh_check() {
  local tailnet_ip="$1"
  local answer

  cat >&2 << PROMPT
[vps-bootstrap] Automated Tailnet SSH and sudo verification passed.
[vps-bootstrap] Before public SSH is disabled, verify from another terminal:
[vps-bootstrap]   ssh -i $(shell_quote "$VPS_IDENTITY") $(shell_quote "$VPS_ADMIN_USER@$tailnet_ip")
[vps-bootstrap] Continue with hardening now? Type yes to disable public SSH:
PROMPT
  IFS= read -r answer
  case "$answer" in
    yes | YES | Yes)
      return 0
      ;;
    *)
      cat >&2 << SKIP
[vps-bootstrap] Leaving public SSH available.
[vps-bootstrap] To finish later, verify the SSH command above and rerun the same vps-bootstrap command.
[vps-bootstrap] The next run will re-check completed setup and continue to hardening after confirmation.
SKIP
      return 1
      ;;
  esac
}

confirm_tailscale_ssh_acl_ready() {
  local tailnet_ip="$1"
  local answer

  if [[ "$VPS_ENABLE_TAILSCALE_SSH" != "1" ]]; then
    return 0
  fi

  cat >&2 << PROMPT
[vps-bootstrap] --enable-tailscale-ssh was requested.
[vps-bootstrap] Tailscale SSH can block normal OpenSSH over the Tailnet unless your Tailnet ACL SSH rules permit this user and node.
[vps-bootstrap] Keep OpenSSH as the safe access path unless you have already configured and reviewed Tailscale SSH ACLs.
[vps-bootstrap] Enable Tailscale SSH during hardening now? Type yes to enable, or anything else to skip it:
PROMPT
  IFS= read -r answer
  case "$answer" in
    yes | YES | Yes)
      return 0
      ;;
    *)
      VPS_ENABLE_TAILSCALE_SSH="0"
      cat >&2 << SKIP
[vps-bootstrap] Skipping Tailscale SSH. Bootstrap will still finish with OpenSSH over the Tailnet.
[vps-bootstrap] To enable it later, configure Tailnet ACL SSH rules first, then run: sudo tailscale set --ssh
SKIP
      return 0
      ;;
  esac
}

run_remote_prepare_with_sudo_login() {
  local public_key="$1"
  local known_hosts_file="$2"
  local local_script remote_script remote_command status

  local_script="$(mktemp "${TMPDIR:-/tmp}/vps-bootstrap-prepare.XXXXXX")" || return 1
  remote_script="/tmp/vps-bootstrap-prepare-${VPS_LOGIN_USER}.$$.$RANDOM.sh"
  set_initial_ssh_options "$known_hosts_file"

  {
    generate_remote_config_prelude prepare "$public_key"
    generate_remote_script
  } > "$local_script"

  scp \
    -q \
    "${VPS_INITIAL_SSH_OPTIONS[@]}" \
    "$local_script" \
    "$VPS_LOGIN_USER@$VPS_HOST:$remote_script" || {
    status=$?
    rm -f "$local_script"
    return "$status"
  }

  rm -f "$local_script"

  remote_command="sudo bash $(shell_quote "$remote_script") prepare; status=\$?; rm -f $(shell_quote "$remote_script"); exit \$status"
  ssh \
    -tt \
    "${VPS_INITIAL_SSH_OPTIONS[@]}" \
    "$VPS_LOGIN_USER@$VPS_HOST" \
    "$remote_command"
}

run_remote_prepare() {
  local public_key="$1"
  local known_hosts_file="$2"

  if [[ "$VPS_LOGIN_USER" == "root" ]]; then
    set_initial_ssh_options "$known_hosts_file"
    {
      generate_remote_config_prelude prepare "$public_key"
      generate_remote_script
    } |
      ssh \
        -tt \
        "${VPS_INITIAL_SSH_OPTIONS[@]}" \
        "$VPS_LOGIN_USER@$VPS_HOST" \
        'bash -s' -- \
        prepare
    return $?
  fi

  run_remote_prepare_with_sudo_login "$public_key" "$known_hosts_file"
}

verify_admin_login() {
  local tailnet_ip="$1"
  local known_hosts_file="$2"

  ssh \
    -i "$VPS_IDENTITY" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o UserKnownHostsFile="$known_hosts_file" \
    -o HostKeyAlias=vps-bootstrap-target \
    -o StrictHostKeyChecking=yes \
    "$VPS_ADMIN_USER@$tailnet_ip" \
    'sudo -n /usr/local/sbin/vps-agent-sudo-check'
}

run_remote_harden() {
  local tailnet_ip="$1"
  local public_key="$2"
  local known_hosts_file="$3"

  {
    generate_remote_config_prelude harden "$public_key"
    generate_remote_script
  } |
    ssh \
      -tt \
      -i "$VPS_IDENTITY" \
      -o IdentitiesOnly=yes \
      -o BatchMode=yes \
      -o UserKnownHostsFile="$known_hosts_file" \
      -o HostKeyAlias=vps-bootstrap-target \
      -o StrictHostKeyChecking=yes \
      "$VPS_ADMIN_USER@$tailnet_ip" \
      'sudo bash -s' -- \
      harden
}

run_dry_run() {
  local public_key
  public_key="$(read_public_key "$VPS_PUBKEY")" || return 1

  cat << DRY_RUN
Dry run: no SSH connections will be opened.

Configuration:
  host: $VPS_HOST
  initial login user: $VPS_LOGIN_USER
  admin user: $VPS_ADMIN_USER
  public key: $VPS_PUBKEY
  identity: $VPS_IDENTITY
  login identity: ${VPS_LOGIN_IDENTITY:-<SSH agent/config>}
  hostname: ${VPS_HOSTNAME:-<server default>}
  public key fingerprint source: ${#public_key} bytes
  Tailscale SSH: $([[ "$VPS_ENABLE_TAILSCALE_SSH" == "1" ]] && printf 'requested after OpenSSH verification' || printf 'disabled')
  developer CLIs: $([[ "$VPS_INSTALL_AGENT_CLIS" == "1" ]] && printf 'install' || printf 'skip')
  sudo mode: $([[ "$VPS_FULL_SUDO" == "1" ]] && printf 'full passwordless' || printf 'scoped passwordless')
  swap: $([[ "$VPS_SWAP_ENABLED" == "1" ]] && printf 'ensure active (%s if no existing swap)' "$VPS_SWAP_SIZE" || printf 'disabled')
  public web ports 80/443: $([[ "$VPS_WEB" == "1" ]] && printf 'enabled' || printf 'disabled')

Phase 1: prepare through $VPS_LOGIN_USER
  $(build_prepare_command "$VPS_LOGIN_USER" "$VPS_HOST" "$VPS_LOGIN_IDENTITY")

Phase 2: verify Tailnet key login
  $(build_admin_verify_command "$VPS_ADMIN_USER" "<tailnet-ip>" "$VPS_IDENTITY")

Manual checkpoint:
  verify SSH in another terminal, then type yes here to disable public SSH

Phase 3: harden over Tailnet
  $(build_admin_harden_command "$VPS_ADMIN_USER" "<tailnet-ip>" "$VPS_IDENTITY")

Tailscale SSH:
$(
    if [[ "$VPS_ENABLE_TAILSCALE_SSH" == "1" ]]; then
      printf '  after verification, confirm Tailnet ACL SSH rules before enabling Tailscale SSH\n'
    else
      printf '  disabled; OpenSSH over Tailnet remains the access model\n'
    fi
  )

Agent CLI authentication:
$(
    if [[ "$VPS_INSTALL_AGENT_CLIS" == "1" ]]; then
      cat << 'AGENT_AUTH_DRY_RUN'
  vps-agent-auth --all
  vps-agent-auth --status
AGENT_AUTH_DRY_RUN
    else
      printf '  skipped; pass --install-agent-clis to install Codex, Grok, GitHub CLI, and vps-agent-auth\n'
    fi
  )

UFW prepare preview:
$(generate_ufw_rules prepare "$VPS_WEB")

firewalld harden preview:
$(generate_firewalld_rules harden "$VPS_WEB")
DRY_RUN
}

doctor_ok() {
  printf '[ok] %s\n' "$*"
}

doctor_warn() {
  printf '[warn] %s\n' "$*"
}

doctor_info() {
  printf '[info] %s\n' "$*"
}

doctor_fail() {
  printf '[fail] %s\n' "$*"
  VPS_DOCTOR_FAILURES=$((VPS_DOCTOR_FAILURES + 1))
}

doctor_command() {
  local command_name="$1"
  local purpose="$2"

  if command -v "$command_name" > /dev/null 2>&1; then
    doctor_ok "$command_name: available for $purpose"
  else
    doctor_warn "$command_name: unavailable; $purpose may need a package install"
  fi
}

doctor_local_inputs() {
  local public_key

  printf '\n== Local bootstrap inputs ==\n'
  if [[ -n "$VPS_HOST" ]]; then
    doctor_ok "target host configured: $VPS_HOST"
  else
    doctor_info "target host not supplied; pass --host when checking a specific VPS plan"
  fi

  if public_key="$(read_public_key "$VPS_PUBKEY" 2> /dev/null)"; then
    doctor_ok "public key readable: $VPS_PUBKEY (${#public_key} bytes)"
  else
    doctor_fail "public key missing or invalid: $VPS_PUBKEY"
  fi

  if [[ -r "$VPS_IDENTITY" ]]; then
    doctor_ok "identity file readable: $VPS_IDENTITY"
  else
    doctor_fail "identity file missing or unreadable: $VPS_IDENTITY"
  fi

  if [[ -n "$VPS_LOGIN_IDENTITY" ]]; then
    if [[ -r "$VPS_LOGIN_IDENTITY" ]]; then
      doctor_ok "login identity file readable: $VPS_LOGIN_IDENTITY"
    else
      doctor_fail "login identity file missing or unreadable: $VPS_LOGIN_IDENTITY"
    fi
  else
    doctor_info "initial SSH identity: use SSH agent or config"
  fi

  doctor_info "first SSH host key: paste a provider key if available, or scan and confirm the fingerprint when bootstrap prompts"
  doctor_command ssh "root prepare, Tailnet verification, and harden phases"
  doctor_command nc "post-bootstrap public port checks from a non-Tailnet network"
}

doctor_local_plan() {
  printf '\n== Bootstrap plan ==\n'
  doctor_info "admin user: $VPS_ADMIN_USER"
  doctor_info "hostname: ${VPS_HOSTNAME:-<server default>}"
  doctor_info "Tailscale SSH: $([[ "$VPS_ENABLE_TAILSCALE_SSH" == "1" ]] && printf 'requested after OpenSSH verification' || printf 'disabled')"
  doctor_info "developer CLIs: $([[ "$VPS_INSTALL_AGENT_CLIS" == "1" ]] && printf 'install' || printf 'skip')"
  doctor_info "sudo mode: $([[ "$VPS_FULL_SUDO" == "1" ]] && printf 'full passwordless' || printf 'scoped passwordless')"
  doctor_info "swap: $([[ "$VPS_SWAP_ENABLED" == "1" ]] && printf 'ensure active (%s if no existing swap)' "$VPS_SWAP_SIZE" || printf 'disabled')"
  doctor_info "public web ports 80/443: $([[ "$VPS_WEB" == "1" ]] && printf 'enabled' || printf 'disabled')"
}

doctor_provider_firewall() {
  printf '\n== Provider firewall checklist ==\n'
  doctor_info "deny public TCP 22 after bootstrap"
  if [[ "$VPS_WEB" == "1" ]]; then
    doctor_info "allow public TCP 80/443 only for hosted web traffic"
  else
    doctor_info "deny public TCP 80/443 for private-only servers"
  fi
  doctor_info "deny other unsolicited public inbound traffic unless an app explicitly requires it"
  doctor_info "provider firewalls usually cannot express Tailnet-only SSH; rely on Tailscale plus host firewall"
}

doctor_remote_vps_state() {
  local helper sudoers_file tailscale_ip unit

  printf '\n== VPS state checks when run on the server ==\n'
  if [[ -r /etc/os-release ]]; then
    # shellcheck disable=SC1091
    . /etc/os-release
    doctor_ok "os-release readable: ${PRETTY_NAME:-${ID:-unknown}}"
  else
    doctor_info "not running on a supported Linux VPS, or /etc/os-release is unreadable"
  fi

  if command -v tailscale > /dev/null 2>&1; then
    tailscale_ip="$(tailscale ip -4 2> /dev/null | head -n 1 || true)"
    if [[ "$tailscale_ip" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]]; then
      doctor_ok "Tailscale reports IPv4: $tailscale_ip"
    else
      doctor_warn "tailscale exists but does not currently report a Tailnet IPv4"
    fi
  else
    doctor_info "tailscale command not found; expected before bootstrap or on non-VPS workstations"
  fi

  if [[ "$VPS_SWAP_ENABLED" != "1" ]]; then
    doctor_info "swap setup disabled by plan"
  elif [[ -r /proc/swaps ]]; then
    if awk 'NR > 1 && $1 != "" { found = 1 } END { exit(found ? 0 : 1) }' /proc/swaps; then
      doctor_ok "active swap detected"
    else
      doctor_warn "no active swap detected"
    fi
  else
    doctor_info "swap state unavailable; run doctor on the VPS to inspect it"
  fi

  for helper in \
    /usr/local/sbin/vps-agent-sudo-check \
    /usr/local/sbin/vps-agent-package \
    /usr/local/sbin/vps-agent-service \
    /usr/local/sbin/vps-agent-logs \
    /usr/local/sbin/vps-agent-firewall \
    /usr/local/sbin/vps-agent-deploy \
    /usr/local/sbin/vps-agent-cli-update \
    /usr/local/sbin/vps-os-update; do
    if [[ -x "$helper" ]]; then
      doctor_ok "helper executable: $helper"
    else
      doctor_info "helper not installed yet: $helper"
    fi
  done

  sudoers_file="/etc/sudoers.d/90-vps-bootstrap-$VPS_ADMIN_USER"
  if [[ -r "$sudoers_file" ]]; then
    if grep -q 'VPS_AGENT_HELPERS' "$sudoers_file" && ! grep -q 'NOPASSWD:ALL' "$sudoers_file"; then
      doctor_ok "sudo helper policy is scoped: $sudoers_file"
    elif grep -q 'NOPASSWD:ALL' "$sudoers_file"; then
      doctor_warn "sudo policy grants full passwordless sudo: $sudoers_file"
    else
      doctor_warn "sudo policy exists but does not match expected vps-bootstrap shape: $sudoers_file"
    fi
  else
    doctor_info "sudo policy not readable or not installed yet: $sudoers_file"
  fi

  for unit in vps-agent-cli-update.timer vps-os-update.timer; do
    if command -v systemctl > /dev/null 2>&1 && systemctl list-unit-files "$unit" --no-legend 2> /dev/null | grep -q .; then
      doctor_ok "systemd timer installed: $unit"
    else
      doctor_info "systemd timer not detected: $unit"
    fi
  done

  if [[ -r /etc/ssh/sshd_config.d/90-vps-bootstrap-hardening.conf ]]; then
    doctor_ok "SSH hardening snippet installed"
  else
    doctor_info "SSH hardening snippet not readable or not installed yet"
  fi

  if command -v ufw > /dev/null 2>&1; then
    doctor_info "host firewall backend candidate: ufw"
    ufw status verbose 2> /dev/null | sed 's/^/  /' || true
  elif command -v firewall-cmd > /dev/null 2>&1; then
    doctor_info "host firewall backend candidate: firewalld"
    firewall-cmd --list-all 2> /dev/null | sed 's/^/  /' || true
  else
    doctor_info "no supported host firewall command detected yet"
  fi

  printf '\n== Exposed ports observation ==\n'
  if command -v ss > /dev/null 2>&1; then
    ss -tuln 2> /dev/null | sed 's/^/  /' || true
  elif command -v netstat > /dev/null 2>&1; then
    netstat -tuln 2> /dev/null | sed 's/^/  /' || true
  else
    doctor_info "ss/netstat unavailable; verify public exposure externally with nc from a non-Tailnet network"
  fi
}

run_doctor() {
  VPS_DOCTOR_FAILURES=0

  cat << 'DOCTOR_HEADER'
vps-bootstrap doctor
Read-only audit: no SSH connections will be opened and no local or remote state will be changed.
DOCTOR_HEADER

  doctor_local_inputs
  doctor_local_plan
  doctor_provider_firewall
  doctor_remote_vps_state

  if [[ "$VPS_DOCTOR_FAILURES" -gt 0 ]]; then
    printf '\nDoctor found %s blocking local input issue(s).\n' "$VPS_DOCTOR_FAILURES"
    return 1
  fi

  printf '\nDoctor completed without blocking local input issues.\n'
}

run_bootstrap() {
  local host_public_key known_hosts_file public_key prepare_log prepare_output tailnet_ip

  validate_local_files || return 1
  public_key="$(read_public_key "$VPS_PUBKEY")" || return 1

  if [[ "$VPS_DRY_RUN" == "1" ]]; then
    run_dry_run
    return $?
  fi

  host_public_key="$(prompt_host_public_key)" || return 1
  known_hosts_file="$(mktemp "${TMPDIR:-/tmp}/vps-bootstrap-known-hosts.XXXXXX")"
  write_known_hosts_file "$host_public_key" "$known_hosts_file" || return 1
  prepare_log="$(mktemp "${TMPDIR:-/tmp}/vps-bootstrap.XXXXXX")"
  trap 'rm -f "$prepare_log" "$known_hosts_file"' RETURN

  printf '[vps-bootstrap] Phase 1: prepare through %s. OpenSSH and sudo follow your local and server auth settings.\n' "$VPS_LOGIN_USER"
  run_remote_prepare "$public_key" "$known_hosts_file" 2>&1 | tee "$prepare_log"

  prepare_output="$(cat "$prepare_log")"
  tailnet_ip="$(parse_prepare_tailnet_ip "$prepare_output")"
  if [[ -z "$tailnet_ip" ]]; then
    error "could not find Tailnet IP in prepare output; public SSH was not disabled"
    return 1
  fi

  printf '[vps-bootstrap] Phase 2: verify Tailnet key login for %s@%s.\n' "$VPS_ADMIN_USER" "$tailnet_ip"
  verify_admin_login "$tailnet_ip" "$known_hosts_file"

  if ! confirm_harden_after_manual_ssh_check "$tailnet_ip"; then
    return 0
  fi
  confirm_tailscale_ssh_acl_ready "$tailnet_ip"

  printf '[vps-bootstrap] Phase 3: harden over Tailnet after successful key/sudo verification.\n'
  run_remote_harden "$tailnet_ip" "$public_key" "$known_hosts_file"

  cat << SUMMARY

Bootstrap complete.

Admin user: $VPS_ADMIN_USER
Tailnet SSH target: $VPS_ADMIN_USER@$tailnet_ip
Swap: $([[ "$VPS_SWAP_ENABLED" == "1" ]] && printf 'enabled (%s if created)' "$VPS_SWAP_SIZE" || printf 'disabled')
Verify from this laptop:
  ssh -i $(shell_quote "$VPS_IDENTITY") $(shell_quote "$VPS_ADMIN_USER@$tailnet_ip")

Public inbound policy:
  - TCP 22: Tailnet only
  - TCP 80/443: $([[ "$VPS_WEB" == "1" ]] && printf 'public' || printf 'closed')

Provider firewall reminder:
  Mirror this policy in your VPS provider firewall: no public TCP 22; public TCP 80/443 only when hosting web apps.

Agent CLI authentication:
$(
    if [[ "$VPS_INSTALL_AGENT_CLIS" == "1" ]]; then
      cat << 'AGENT_AUTH_SUMMARY'
  SSH to the server over Tailnet, then run:
    vps-agent-auth --all
    vps-agent-auth --status
AGENT_AUTH_SUMMARY
    else
      printf '  Skipped. Rerun bootstrap with --install-agent-clis if this server should install Codex, Grok, GitHub CLI, and vps-agent-auth.\n'
    fi
  )
SUMMARY
}

main() {
  reset_config
  parse_args "$@" || return 1

  if [[ "$VPS_SHOW_HELP" == "1" ]]; then
    usage
    return 0
  fi

  if [[ "$VPS_DOCTOR" == "1" ]]; then
    run_doctor
    return $?
  fi

  run_bootstrap
}
