#!/usr/bin/env bash

reset_config() {
  VPS_HOST=""
  VPS_ADMIN_USER="deploy"
  VPS_PUBKEY="${HOME}/.ssh/id_ed25519.pub"
  VPS_IDENTITY=""
  VPS_HOSTNAME=""
  VPS_ENABLE_TAILSCALE_SSH="0"
  VPS_INSTALL_AGENT_CLIS="1"
  VPS_FULL_SUDO="0"
  VPS_WEB="1"
  VPS_DRY_RUN="0"
  VPS_SHOW_HELP="0"
}

reset_config

error() {
  printf 'vps-bootstrap: %s\n' "$*" >&2
}

usage() {
  cat <<'USAGE'
Usage:
  vps-bootstrap --host <ip-or-hostname> [options]

Options:
  --host <host>                 Public VPS address for the initial root SSH login.
  --user <name>                 Admin sudo user to create. Default: deploy.
  --pubkey <path>               Public key to install. Default: ~/.ssh/id_ed25519.pub.
  --identity <path>             Private key used to verify Tailnet login. Default: pubkey without .pub.
  --hostname <name>             Hostname to set on the server and use for Tailscale.
  --enable-tailscale-ssh        Enable Tailscale SSH after joining the Tailnet.
  --install-agent-clis          Install Codex, Grok, and GitHub CLIs. Default.
  --skip-agent-clis             Skip Codex, Grok, and GitHub CLI installation.
  --full-sudo                   Use NOPASSWD:ALL instead of scoped passwordless sudo.
  --web                         Keep public TCP 80/443 open. Default.
  --web=false                   Disable public TCP 80/443.
  --no-web                      Disable public TCP 80/443.
  --dry-run                     Print the phased plan without opening SSH connections.
  -h, --help                    Show this help.

The tool assumes the first connection is root@<host> with password auth. It does
not store or pass the root password; OpenSSH prompts for it normally.
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
    error "admin user must match ^[a-z_][a-z0-9_-]{0,31}$"
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

  if [[ -z "$VPS_HOST" ]]; then
    error "--host is required"
    return 1
  fi

  if [[ "$VPS_HOST" == *@* ]]; then
    error "--host expects a hostname or IP only; root@ is added automatically"
    return 1
  fi

  validate_admin_user "$VPS_ADMIN_USER" || return 1
  validate_hostname "$VPS_HOSTNAME" || return 1

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
  done <"$pubkey_path"

  error "public key file is empty: $pubkey_path"
  return 1
}

validate_local_files() {
  read_public_key "$VPS_PUBKEY" >/dev/null || return 1

  if [[ ! -r "$VPS_IDENTITY" ]]; then
    error "identity file is not readable: $VPS_IDENTITY"
    error "pass --identity if the private key is not ${VPS_PUBKEY%.pub}"
    return 1
  fi
}

shell_quote() {
  printf '%q' "$1"
}

generate_sshd_hardening_config() {
  cat <<'SSHD_CONFIG'
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

  cat <<SUDOERS_POLICY
# Managed by vps-bootstrap. Scoped passwordless sudo for agentic operations.
Cmnd_Alias VPS_PKG = /usr/bin/apt-get, /usr/bin/apt, /usr/bin/dnf, /usr/bin/yum
Cmnd_Alias VPS_SVC = /usr/bin/systemctl, /bin/systemctl
Cmnd_Alias VPS_LOG = /usr/bin/journalctl, /bin/journalctl
Cmnd_Alias VPS_FIREWALL = /usr/sbin/ufw, /usr/bin/firewall-cmd, /usr/sbin/firewall-cmd
Cmnd_Alias VPS_DEPLOY = /usr/bin/install, /usr/bin/chown, /usr/bin/chmod, /usr/bin/mkdir, /usr/bin/rsync
Cmnd_Alias VPS_AGENT_TOOLS = /usr/bin/npm, /usr/local/bin/npm, /usr/bin/codex, /usr/local/bin/codex, /usr/bin/grok, /usr/local/bin/grok, /usr/bin/gh, /usr/local/bin/gh, /usr/local/bin/vps-agent-auth
$admin_user ALL=(ALL) NOPASSWD: VPS_PKG, VPS_SVC, VPS_LOG, VPS_FIREWALL, VPS_DEPLOY, VPS_AGENT_TOOLS
SUDOERS_POLICY
}

generate_agent_auth_helper_script() {
  cat <<'AGENT_AUTH_HELPER'
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
AGENT_AUTH_HELPER
}

generate_ufw_rules() {
  local phase="$1"
  local web_enabled="$2"

  cat <<'UFW_RULES'
ufw default deny incoming
ufw default allow outgoing
ufw allow in on tailscale0 to any port 22 proto tcp comment 'vps-bootstrap tailnet ssh'
UFW_RULES

  if [[ "$phase" == "prepare" ]]; then
    cat <<'UFW_PREPARE'
ufw allow 22/tcp comment 'vps-bootstrap temporary public ssh'
UFW_PREPARE
  else
    cat <<'UFW_HARDEN'
ufw --force delete allow 22/tcp || true
ufw --force delete allow OpenSSH || true
ufw --force delete allow ssh || true
UFW_HARDEN
  fi

  if [[ "$web_enabled" == "1" ]]; then
    cat <<'UFW_WEB'
ufw allow 80/tcp comment 'vps-bootstrap public http'
ufw allow 443/tcp comment 'vps-bootstrap public https'
UFW_WEB
  else
    cat <<'UFW_NO_WEB'
ufw --force delete allow 80/tcp || true
ufw --force delete allow 443/tcp || true
UFW_NO_WEB
  fi

  printf 'ufw --force enable\n'
}

generate_firewalld_rules() {
  local phase="$1"
  local web_enabled="$2"

  cat <<'FIREWALLD_RULES'
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
    cat <<'FIREWALLD_WEB'
firewall-cmd --permanent --zone=public --add-service=http
firewall-cmd --permanent --zone=public --add-service=https
FIREWALLD_WEB
  else
    cat <<'FIREWALLD_NO_WEB'
firewall-cmd --permanent --zone=public --remove-service=http || true
firewall-cmd --permanent --zone=public --remove-service=https || true
FIREWALLD_NO_WEB
  fi

  printf 'firewall-cmd --reload\n'
}

generate_remote_script() {
  cat <<'REMOTE_SCRIPT'
#!/usr/bin/env bash
set -Eeuo pipefail

: "${phase:?phase required}"
: "${admin_user:?admin user required}"
: "${public_key:?public key required}"
requested_hostname="${requested_hostname:-}"
enable_tailscale_ssh="${enable_tailscale_ssh:-0}"
web_enabled="${web_enabled:-1}"
install_agent_clis="${install_agent_clis:-1}"
full_sudo="${full_sudo:-0}"

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
    apt-get install -y sudo ca-certificates curl gnupg git openssh-server ufw unattended-upgrades
    return 0
  fi

  if [[ "$PKG_BACKEND" == "dnf" ]]; then
    dnf makecache -y
    dnf install -y sudo ca-certificates curl git openssh-server firewalld
    install_optional_package dnf-automatic || true
    return 0
  fi

  yum makecache -y
  yum install -y sudo ca-certificates curl git openssh-server firewalld
  install_optional_package dnf-automatic || true
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

    systemctl enable --now unattended-upgrades >/dev/null 2>&1 || warn "unattended-upgrades service not enabled"
    return 0
  fi

  if command_exists dnf-automatic; then
    if enable_service dnf-automatic-install.timer; then
      return 0
    fi

    enable_service dnf-automatic.timer || warn "dnf automatic install timer not enabled"
  else
    warn "dnf-automatic is unavailable; automatic security updates were not enabled"
  fi
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

generate_sudoers_policy_remote() {
  local policy_full="${1:-$full_sudo}"

  if [[ "$policy_full" == "1" ]]; then
    printf '%s ALL=(ALL) NOPASSWD:ALL\n' "$admin_user"
    return 0
  fi

  cat <<SUDOERS_POLICY
# Managed by vps-bootstrap. Scoped passwordless sudo for agentic operations.
Cmnd_Alias VPS_PKG = /usr/bin/apt-get, /usr/bin/apt, /usr/bin/dnf, /usr/bin/yum
Cmnd_Alias VPS_SVC = /usr/bin/systemctl, /bin/systemctl
Cmnd_Alias VPS_LOG = /usr/bin/journalctl, /bin/journalctl
Cmnd_Alias VPS_FIREWALL = /usr/sbin/ufw, /usr/bin/firewall-cmd, /usr/sbin/firewall-cmd
Cmnd_Alias VPS_DEPLOY = /usr/bin/install, /usr/bin/chown, /usr/bin/chmod, /usr/bin/mkdir, /usr/bin/rsync
Cmnd_Alias VPS_AGENT_TOOLS = /usr/bin/npm, /usr/local/bin/npm, /usr/bin/codex, /usr/local/bin/codex, /usr/bin/grok, /usr/local/bin/grok, /usr/bin/gh, /usr/local/bin/gh, /usr/local/bin/vps-agent-auth
$admin_user ALL=(ALL) NOPASSWD: VPS_PKG, VPS_SVC, VPS_LOG, VPS_FIREWALL, VPS_DEPLOY, VPS_AGENT_TOOLS
SUDOERS_POLICY
}

write_sudoers_policy() {
  local policy_full="${1:-$full_sudo}"
  local sudoers_file

  sudoers_file="/etc/sudoers.d/90-vps-bootstrap-$admin_user"
  generate_sudoers_policy_remote "$policy_full" >"$sudoers_file"
  chmod 440 "$sudoers_file"
  visudo -cf "$sudoers_file" >/dev/null
}

install_node_runtime() {
  if command_exists npm; then
    return 0
  fi

  log "installing Node.js and npm for Codex CLI"

  if [[ "$PKG_BACKEND" == "apt" ]]; then
    apt-get install -y nodejs npm
    return 0
  fi

  "$PKG_BIN" install -y nodejs npm
}

install_codex_cli() {
  install_node_runtime

  if command_exists codex; then
    log "Codex CLI is already installed"
    return 0
  fi

  log "installing Codex CLI with npm"
  npm install -g @openai/codex
  codex --version >/dev/null
}

install_grok_cli() {
  local home_dir grok_bin

  home_dir="$(getent passwd "$admin_user" | cut -d: -f6)"
  grok_bin="$home_dir/.grok/bin/grok"

  if [[ -x "$grok_bin" ]]; then
    log "Grok CLI is already installed for $admin_user"
  else
    log "installing official Grok CLI for $admin_user"
    sudo -H -u "$admin_user" env SHELL=/bin/bash bash -c 'curl -fsSL https://x.ai/cli/install.sh | bash'
  fi

  if [[ ! -x "$grok_bin" ]]; then
    fail "Grok CLI installer did not create $grok_bin"
  fi

  install -d -m 0755 /usr/local/bin
  ln -sf "$grok_bin" /usr/local/bin/grok
  if [[ -x "$home_dir/.grok/bin/agent" ]]; then
    ln -sf "$home_dir/.grok/bin/agent" /usr/local/bin/agent
  fi

  sudo -H -u "$admin_user" "$grok_bin" --version >/dev/null
}

remove_legacy_third_party_grok_cli() {
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

  install_codex_cli
  remove_legacy_third_party_grok_cli
  install_grok_cli
  install_github_cli
  install_agent_auth_helper
  print_agent_cli_versions
}

install_agent_auth_helper() {
  log "installing /usr/local/bin/vps-agent-auth"

  cat >/usr/local/bin/vps-agent-auth <<'AGENT_AUTH_HELPER'
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
    printf '%s\n' "$public_key" >>"$home_dir/.ssh/authorized_keys"
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
  tailscale set --ssh
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
}

run_prepare() {
  require_root
  validate_admin_user_remote
  validate_hostname_remote
  select_platform
  install_required_packages
  enable_service "$SSHD_SERVICE"
  configure_automatic_updates
  install_ban_service
  ensure_admin_user
  set_requested_hostname
  install_agent_clis_if_requested
  ensure_tailscale_connected
  enable_tailscale_ssh_if_requested
  configure_firewall prepare
  validate_prepare_state

  printf 'VPS_BOOTSTRAP_TAILSCALE_IP=%s\n' "$TAILSCALE_IP"
  printf 'VPS_BOOTSTRAP_FIREWALL=%s\n' "$FIREWALL_BACKEND"
  log "prepare phase complete; password/root SSH remains available until local Tailnet login verification passes"
}

run_harden() {
  require_root
  validate_admin_user_remote
  validate_hostname_remote
  select_platform
  ensure_tailscale_connected
  configure_firewall harden
  write_sshd_hardening
  write_sudoers_policy "$full_sudo"

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
REMOTE_SCRIPT
}

build_root_prepare_command() {
  local host="$1"

  printf 'stream config + script | ssh -tt -o StrictHostKeyChecking=accept-new %s %s' \
    "$(shell_quote "root@$host")" \
    "$(shell_quote "bash -s")"
}

build_admin_verify_command() {
  local admin_user="$1"
  local tailnet_ip="$2"
  local identity="$3"

  printf 'ssh -i %s -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new %s %s' \
    "$(shell_quote "$identity")" \
    "$(shell_quote "$admin_user@$tailnet_ip")" \
    "'sudo -n true'"
}

build_admin_harden_command() {
  local admin_user="$1"
  local tailnet_ip="$2"
  local identity="$3"

  printf 'stream config + script | ssh -tt -i %s -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=accept-new %s %s' \
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
}

parse_prepare_tailnet_ip() {
  local output="$1"

  printf '%s\n' "$output" |
    sed -n 's/.*VPS_BOOTSTRAP_TAILSCALE_IP=//p' |
    tail -n 1 |
    tr -d '\r'
}

run_remote_prepare() {
  local public_key="$1"

  {
    generate_remote_config_prelude prepare "$public_key"
    generate_remote_script
  } |
    ssh -tt -o StrictHostKeyChecking=accept-new "root@$VPS_HOST" 'bash -s' -- \
      prepare
}

verify_admin_login() {
  local tailnet_ip="$1"

  ssh \
    -i "$VPS_IDENTITY" \
    -o IdentitiesOnly=yes \
    -o BatchMode=yes \
    -o StrictHostKeyChecking=accept-new \
    "$VPS_ADMIN_USER@$tailnet_ip" \
    'sudo -n true'
}

run_remote_harden() {
  local tailnet_ip="$1"
  local public_key="$2"

  {
    generate_remote_config_prelude harden "$public_key"
    generate_remote_script
  } |
    ssh \
      -tt \
      -i "$VPS_IDENTITY" \
      -o IdentitiesOnly=yes \
      -o BatchMode=yes \
      -o StrictHostKeyChecking=accept-new \
      "$VPS_ADMIN_USER@$tailnet_ip" \
      'sudo bash -s' -- \
      harden
}

run_dry_run() {
  local public_key
  public_key="$(read_public_key "$VPS_PUBKEY")" || return 1

  cat <<DRY_RUN
Dry run: no SSH connections will be opened.

Configuration:
  host: $VPS_HOST
  admin user: $VPS_ADMIN_USER
  public key: $VPS_PUBKEY
  identity: $VPS_IDENTITY
  hostname: ${VPS_HOSTNAME:-<server default>}
  public key fingerprint source: ${#public_key} bytes
  Tailscale SSH: $([[ "$VPS_ENABLE_TAILSCALE_SSH" == "1" ]] && printf 'enabled' || printf 'disabled')
  developer CLIs: $([[ "$VPS_INSTALL_AGENT_CLIS" == "1" ]] && printf 'install' || printf 'skip')
  sudo mode: $([[ "$VPS_FULL_SUDO" == "1" ]] && printf 'full passwordless' || printf 'scoped passwordless')
  public web ports 80/443: $([[ "$VPS_WEB" == "1" ]] && printf 'enabled' || printf 'disabled')

Phase 1: prepare as root
  $(build_root_prepare_command "$VPS_HOST")

Phase 2: verify Tailnet key login
  $(build_admin_verify_command "$VPS_ADMIN_USER" "<tailnet-ip>" "$VPS_IDENTITY")

Phase 3: harden over Tailnet
  $(build_admin_harden_command "$VPS_ADMIN_USER" "<tailnet-ip>" "$VPS_IDENTITY")

Post-setup agent auth on the VPS:
  vps-agent-auth --all
  vps-agent-auth --status

UFW prepare preview:
$(generate_ufw_rules prepare "$VPS_WEB")

firewalld harden preview:
$(generate_firewalld_rules harden "$VPS_WEB")
DRY_RUN
}

run_bootstrap() {
  local public_key prepare_log prepare_output tailnet_ip

  validate_local_files || return 1
  public_key="$(read_public_key "$VPS_PUBKEY")" || return 1

  if [[ "$VPS_DRY_RUN" == "1" ]]; then
    run_dry_run
    return $?
  fi

  prepare_log="$(mktemp "${TMPDIR:-/tmp}/vps-bootstrap.XXXXXX")"
  trap 'rm -f "$prepare_log"' RETURN

  printf '[vps-bootstrap] Phase 1: prepare as root. OpenSSH will prompt for the root password.\n'
  run_remote_prepare "$public_key" 2>&1 | tee "$prepare_log"

  prepare_output="$(cat "$prepare_log")"
  tailnet_ip="$(parse_prepare_tailnet_ip "$prepare_output")"
  if [[ -z "$tailnet_ip" ]]; then
    error "could not find Tailnet IP in prepare output; root/password SSH was not disabled"
    return 1
  fi

  printf '[vps-bootstrap] Phase 2: verify Tailnet key login for %s@%s.\n' "$VPS_ADMIN_USER" "$tailnet_ip"
  verify_admin_login "$tailnet_ip"

  printf '[vps-bootstrap] Phase 3: harden over Tailnet after successful key/sudo verification.\n'
  run_remote_harden "$tailnet_ip" "$public_key"

  cat <<SUMMARY

Bootstrap complete.

Admin user: $VPS_ADMIN_USER
Tailnet SSH target: $VPS_ADMIN_USER@$tailnet_ip
Verify from this laptop:
  ssh -i $(shell_quote "$VPS_IDENTITY") $(shell_quote "$VPS_ADMIN_USER@$tailnet_ip")

Public inbound policy:
  - TCP 22: Tailnet only
  - TCP 80/443: $([[ "$VPS_WEB" == "1" ]] && printf 'public' || printf 'closed')

Provider firewall reminder:
  Mirror this policy in your VPS provider firewall: no public TCP 22; public TCP 80/443 only when hosting web apps.

Agent CLI authentication:
  SSH to the server over Tailnet, then run:
    vps-agent-auth --all
    vps-agent-auth --status
SUMMARY
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
