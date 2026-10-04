#!/usr/bin/env bash
set -Eeuo pipefail

NC_ROOT="/var/www/nextcloud"
NC_CONFIG="/etc/nextcloud"
PHP_BIN="/usr/bin/php8.5"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

occ() {
  runuser -u www-data -- env NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" "$PHP_BIN" "$NC_ROOT/occ" "$@"
}

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root."

for key in name url slogan primary_color background_color logo logoheader favicon background disable-user-theming; do
  occ theming:config --reset "$key" >/dev/null 2>&1 || true
done

occ config:system:delete defaultapp >/dev/null 2>&1 || true

echo "Linetty staging UI overrides reset to Nextcloud defaults."
