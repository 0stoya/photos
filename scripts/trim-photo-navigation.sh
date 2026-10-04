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

app_enabled() {
  local app="$1"
  occ app:list --enabled | grep -Eq "^[[:space:]]*-[[:space:]]+$app:"
}

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root."

if [[ "${LINETTY_CONFIRM_NAV_TRIM:-no}" != "yes" ]]; then
  echo "Navigation trim is optional."
  echo "Re-run with LINETTY_CONFIRM_NAV_TRIM=yes to disable staging-only clutter."
  echo "Candidates: dashboard, weather_status, firstrunwizard"
  exit 0
fi

for app in dashboard weather_status firstrunwizard; do
  if app_enabled "$app"; then
    occ app:disable "$app"
  else
    echo "$app is already disabled or unavailable."
  fi
done

echo
echo "Photo-focused navigation trim applied. Files, Photos and Memories were not disabled."
