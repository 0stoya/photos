#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="photo.linetty.co.uk"
NC_ROOT="/var/www/nextcloud"
NC_CONFIG="/etc/nextcloud"
PHP_BIN="/usr/bin/php8.5"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

section() {
  printf '\n==> %s\n' "$1"
}

occ() {
  runuser -u www-data -- env NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" "$PHP_BIN" "$NC_ROOT/occ" "$@"
}

app_enabled() {
  local app="$1"
  occ app:list --enabled | grep -Eq "^[[:space:]]*-[[:space:]]+$app:"
}

disable_if_enabled() {
  local app="$1"
  if app_enabled "$app"; then
    occ app:disable "$app"
  else
    echo "$app already disabled or unavailable."
  fi
}

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root."
[[ -x "$PHP_BIN" ]] || fail "PHP 8.5 CLI is missing."
[[ -f "$NC_ROOT/occ" ]] || fail "Nextcloud is missing at $NC_ROOT."
[[ -f "$NC_CONFIG/config.php" ]] || fail "Nextcloud config is missing at $NC_CONFIG/config.php."

occ status --output=json | grep -q '"installed":true' || fail "Nextcloud is not installed."

section "Stop default files for future users"
occ config:system:set skeletondirectory --value=""
occ config:system:set templatedirectory --value=""
echo "New users will not receive Nextcloud skeleton or template files."

section "Trim generic staging UI apps"
for app in dashboard weather_status firstrunwizard recommendations; do
  disable_if_enabled "$app"
done

section "Preserve photo apps"
for app in files photos memories; do
  occ app:getpath "$app" >/dev/null 2>&1 || fail "$app is missing."
done
echo "Files, Photos and Memories are preserved."

section "Safe file-cache cleanup"
occ files:cleanup

section "Optional destructive staging cleanup"
if [[ "${LINETTY_PURGE_TRASH:-no}" == "yes" ]]; then
  echo "Permanently emptying all user trash bins..."
  occ trashbin:cleanup --all-users
else
  echo "Trash retained. Set LINETTY_PURGE_TRASH=yes to permanently empty all user trash."
fi

if [[ "${LINETTY_PURGE_VERSIONS:-no}" == "yes" ]]; then
  echo "Permanently deleting stored file versions..."
  occ versions:cleanup
else
  echo "File versions retained. Set LINETTY_PURGE_VERSIONS=yes to permanently delete all versions."
fi

section "Runtime-owned directories"
cat <<'TEXT'
Not touched:
  - appdata_*              app cache, previews and generated app state
  - */files                user-owned files
  - */files_trashbin       Nextcloud-managed deleted files
  - */files_versions       Nextcloud-managed version history
  - */uploads              chunked-upload working state
  - .ocdata                data-directory marker
  - updater-*              updater-owned state

Generated previews are intentionally retained on a photo service.
TEXT

section "Staging boundary"
echo "No backup jobs, backup timers or storage migration were created."
echo "Active user files were not deleted."
