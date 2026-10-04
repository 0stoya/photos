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

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root."

echo "LINETTY PHOTOS - PHASE 3A LOGIN/UI ACCEPTANCE"
echo "============================================="

[[ "$(occ config:app:get theming name)" == "Linetty Photos" ]] \
  || fail "Instance name is not Linetty Photos."
pass "Instance is branded Linetty Photos"

[[ "$(occ config:app:get theming url)" == "https://photo.linetty.co.uk" ]] \
  || fail "Instance URL is not photo.linetty.co.uk."
pass "Theme URL points to photo.linetty.co.uk"

[[ "$(occ config:app:get theming slogan)" == "Our family photos, in one place." ]] \
  || fail "Unexpected instance slogan."
pass "Family photo slogan is configured"

DEFAULTAPP="$(occ config:system:get defaultapp)"
[[ "$DEFAULTAPP" == "memories,files" ]]   || fail "Expected defaultapp=memories,files; got $DEFAULTAPP."
pass "Memories is the first post-login app"

occ app:getpath memories >/dev/null 2>&1 || fail "Memories is not installed."
pass "Memories remains installed"

LOCAL_LOGIN_HEADERS="$(curl -fsSI --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/login" | tr -d '\r')"
grep -qE '^HTTP/[0-9.]+ (200|303) ' <<<"$LOCAL_LOGIN_HEADERS"   || fail "Local login route is not healthy."
pass "Local login route is healthy"

PUBLIC_STATUS="$(curl -fsS --max-time 20 "https://$DOMAIN/status.php")"
grep -q '"installed":true' <<<"$PUBLIC_STATUS" || fail "Public Nextcloud status is unhealthy."
pass "Public HTTPS remains healthy"

BACKUP_AUTOMATION="$(find /etc/systemd/system /etc/cron.d -maxdepth 2 -type f \
  \( -iname '*linetty*backup*' -o -iname '*nextcloud*backup*' -o -iname '*photos*backup*' \) \
  -print -quit 2>/dev/null || true)"
if [[ -n "$BACKUP_AUTOMATION" ]]; then
  fail "A Linetty/Nextcloud backup unit or cron file exists on staging: $BACKUP_AUTOMATION"
fi
pass "No Linetty/Nextcloud backup automation is installed on staging"

echo
echo "PHASE 3A: PASS"
