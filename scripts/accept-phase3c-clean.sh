#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="photo.linetty.co.uk"
NC_ROOT="/var/www/nextcloud"
NC_CONFIG="/etc/nextcloud"
PHP_BIN="/usr/bin/php8.5"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

occ() {
  runuser -u www-data -- env NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" "$PHP_BIN" "$NC_ROOT/occ" "$@"
}

app_enabled() {
  local app="$1"
  occ app:list --enabled | grep -Eq "^[[:space:]]*-[[:space:]]+$app:"
}

[[ "${EUID}" -eq 0 ]] || fail "Run as root."

echo "LINETTY PHOTOS - PHASE 3C CLEAN STAGING ACCEPTANCE"
echo "=================================================="

SKELETON="$(occ config:system:get skeletondirectory 2>/dev/null || true)"
[[ -z "$SKELETON" ]] || fail "skeletondirectory is not empty: $SKELETON"
pass "Default skeleton files are disabled for future users"

TEMPLATES="$(occ config:system:get templatedirectory 2>/dev/null || true)"
[[ -z "$TEMPLATES" ]] || fail "templatedirectory is not empty: $TEMPLATES"
pass "Default template content is disabled for future users"

for app in dashboard weather_status firstrunwizard recommendations; do
  if app_enabled "$app"; then
    fail "$app is still enabled."
  fi
done
pass "Generic staging UI apps are disabled"

for app in files photos memories; do
  app_enabled "$app" || fail "$app is not enabled."
done
pass "Files, Photos and Memories remain enabled"

[[ "$(occ config:system:get defaultapp)" == "memories,files" ]]   || fail "Memories is no longer the first default app."
pass "Memories remains the first post-login app"

PUBLIC_STATUS="$(curl -fsS --max-time 20 "https://$DOMAIN/status.php")"
grep -q '"installed":true' <<<"$PUBLIC_STATUS" || fail "Public Nextcloud status is unhealthy."
pass "Public HTTPS remains healthy"

BACKUP_AUTOMATION="$(find /etc/systemd/system /etc/cron.d -maxdepth 2 -type f   \( -iname '*linetty*backup*' -o -iname '*nextcloud*backup*' -o -iname '*photos*backup*' \)   -print -quit 2>/dev/null || true)"
[[ -z "$BACKUP_AUTOMATION" ]]   || fail "Backup automation exists on staging: $BACKUP_AUTOMATION"
pass "No Linetty/Nextcloud backup automation exists on staging"

echo
echo "PHASE 3C: PASS"
