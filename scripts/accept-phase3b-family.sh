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

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root."

echo "LINETTY PHOTOS - PHASE 3B FAMILY EXPERIENCE ACCEPTANCE"
echo "======================================================"

for app in photos memories twofactor_totp twofactor_backupcodes; do
  app_enabled "$app" || fail "$app is not enabled."
  pass "$app is enabled"
done

occ group:info family >/dev/null 2>&1 || fail "family group does not exist."
pass "family group exists"

[[ "$(occ config:system:get defaultapp)" == "memories,files" ]] \
  || fail "Memories is not the first default app."
pass "Memories remains the first post-login app"

ALLOW_LINKS="$(occ config:app:get core shareapi_allow_links)"
ENFORCE_PASSWORD="$(occ config:app:get core shareapi_enforce_links_password)"

case "${ALLOW_LINKS,,}" in
  yes|true|1) ;;
  *) fail "Public link sharing is not enabled; stored value is: $ALLOW_LINKS" ;;
esac

case "${ENFORCE_PASSWORD,,}" in
  yes|true|1) ;;
  *) fail "Public link password protection is not enforced; stored value is: $ENFORCE_PASSWORD" ;;
esac

pass "Public share links require passwords"

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
echo "Admin account 2FA state (informational):"
occ twofactorauth:state admin || true

echo
echo "PHASE 3B: PASS"
