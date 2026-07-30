#!/usr/bin/env bash
set -Eeuo pipefail

source_ref="${VPS_BOOTSTRAP_REF:-main}"
install_dir="$(mktemp -d "${TMPDIR:-/tmp}/vps-bootstrap.XXXXXX")"
archive="$install_dir/source.tar.gz"

cleanup() {
  rm -rf "$install_dir"
}
trap cleanup EXIT

if ! command -v curl > /dev/null 2>&1; then
  printf 'vps-bootstrap: curl is required to download the installer\n' >&2
  exit 1
fi

if ! command -v tar > /dev/null 2>&1; then
  printf 'vps-bootstrap: tar is required to unpack the installer\n' >&2
  exit 1
fi

curl \
  -fsSL \
  --connect-timeout 15 \
  --max-time 120 \
  "https://codeload.github.com/glnarayanan/server-setup-scripts/tar.gz/refs/heads/$source_ref" \
  -o "$archive"
tar -xzf "$archive" -C "$install_dir" --strip-components=1

for required_file in \
  bin/vps-bootstrap \
  lib/vps-bootstrap.sh \
  lib/templates/vps-agent-audit-prelude.sh \
  lib/templates/vps-agent-auth.sh; do
  if [[ ! -f "$install_dir/$required_file" ]]; then
    printf 'vps-bootstrap: downloaded bundle is missing %s\n' "$required_file" >&2
    exit 1
  fi
done

chmod 700 "$install_dir/bin/vps-bootstrap"
"$install_dir/bin/vps-bootstrap" "$@"
