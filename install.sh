#!/usr/bin/env bash
set -Eeuo pipefail

source_ref="${VPSBUDDY_REF:-main}"
install_dir="$(mktemp -d "${TMPDIR:-/tmp}/vpsbuddy.XXXXXX")"
archive="$install_dir/source.tar.gz"

cleanup() {
  rm -rf "$install_dir"
}
trap cleanup EXIT

if [[ ! "$source_ref" =~ ^[A-Za-z0-9._/-]+$ ]]; then
  printf 'vpsbuddy: invalid VPSBUDDY_REF\n' >&2
  exit 1
fi

if ! command -v curl > /dev/null 2>&1; then
  printf 'vpsbuddy: curl is required to download the installer\n' >&2
  exit 1
fi

if ! command -v tar > /dev/null 2>&1; then
  printf 'vpsbuddy: tar is required to unpack the installer\n' >&2
  exit 1
fi

curl \
  -fsSL \
  --connect-timeout 15 \
  --max-time 120 \
  "https://codeload.github.com/glnarayanan/vpsbuddy/tar.gz/refs/heads/$source_ref" \
  -o "$archive"
tar -xzf "$archive" -C "$install_dir" --strip-components=1

for required_file in \
  bin/vpsbuddy \
  lib/vpsbuddy.sh \
  lib/templates/vpsbuddy-audit-prelude.sh \
  lib/templates/vpsbuddy-auth.sh; do
  if [[ ! -f "$install_dir/$required_file" ]]; then
    printf 'vpsbuddy: downloaded bundle is missing %s\n' "$required_file" >&2
    exit 1
  fi
done

chmod 700 "$install_dir/bin/vpsbuddy"
"$install_dir/bin/vpsbuddy" "$@"
