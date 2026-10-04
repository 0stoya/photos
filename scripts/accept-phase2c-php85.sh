#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="photo.linetty.co.uk"
NC_ROOT="/var/www/nextcloud"
NC_CONFIG="/etc/nextcloud"
SITE_FILE="/etc/nginx/sites-available/linetty-photos"
CRON_FILE="/etc/cron.d/linetty-nextcloud"
PHP85="/usr/bin/php8.5"
FPM_SERVICE="php8.5-fpm.service"
FPM_SOCKET="/run/php/php8.5-fpm.sock"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

occ85() {
  runuser -u www-data -- env NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" "$PHP85" "$NC_ROOT/occ" "$@"
}

[[ "${EUID}" -eq 0 ]] || fail "Run as root."

echo "LINETTY PHOTOS - PHASE 2C PHP 8.5 ACCEPTANCE"
echo "============================================="

[[ -x "$PHP85" ]] || fail "PHP 8.5 CLI is missing."
PHP_VERSION="$("$PHP85" -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')"
[[ "$PHP_VERSION" == "8.5" ]] || fail "Expected PHP 8.5; got $PHP_VERSION."
pass "PHP 8.5 CLI is installed"

[[ "$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')" == "8.5" ]]   || fail "Default php alternative is not PHP 8.5."
pass "Default PHP CLI points to 8.5"

systemctl is-active --quiet "$FPM_SERVICE" || fail "$FPM_SERVICE is not active."
systemctl is-enabled --quiet "$FPM_SERVICE" || fail "$FPM_SERVICE is not enabled."
[[ -S "$FPM_SOCKET" ]] || fail "PHP 8.5 FPM socket is missing."
pass "PHP 8.5 FPM is active and enabled"

grep -Fq "$FPM_SOCKET" "$SITE_FILE" || fail "Nginx does not use the PHP 8.5 socket."
! grep -Fq '/run/php/php8.3-fpm.sock' "$SITE_FILE" || fail "Nginx still references PHP 8.3."
nginx -t >/dev/null 2>&1 || fail "Nginx configuration is invalid."
pass "Nginx uses only PHP 8.5 FPM"

grep -Fq '/usr/bin/php8.5 -f /var/www/nextcloud/cron.php' "$CRON_FILE"   || fail "Nextcloud cron does not explicitly use PHP 8.5."
pass "Nextcloud cron uses PHP 8.5"

modules="$("$PHP85" -m | tr '[:upper:]' '[:lower:]')"
for module in apcu bz2 curl dom exif fileinfo gd gmp imagick intl mbstring openssl pdo_pgsql redis sodium sysvsem xml zip; do
  grep -qx "$module" <<<"$modules" || fail "Missing PHP 8.5 module: $module"
done
pass "Required and recommended PHP 8.5 modules are loaded"

"$PHP85" -r 'exit(function_exists("opcache_get_status") ? 0 : 1);'   || fail "PHP 8.5 built-in OPcache is unavailable."
[[ "$("$PHP85" -r 'echo ini_get("opcache.enable");')" == "1" ]]   || fail "PHP 8.5 OPcache is not enabled."
pass "PHP 8.5 built-in OPcache is available and enabled"

[[ "$("$PHP85" -r 'echo ini_get("memory_limit");')" == "512M" ]]   || fail "PHP 8.5 memory_limit is not 512M."
[[ "$("$PHP85" -r 'echo ini_get("upload_max_filesize");')" == "20G" ]]   || fail "PHP 8.5 upload_max_filesize is not 20G."
[[ "$("$PHP85" -r 'echo ini_get("post_max_size");')" == "20G" ]]   || fail "PHP 8.5 post_max_size is not 20G."
pass "PHP 8.5 Nextcloud tuning is active"

occ85 status --output=json | grep -q '"installed":true' || fail "Nextcloud is not healthy under PHP 8.5."
[[ "$(occ85 status --output=json | php8.5 -r '$j=json_decode(stream_get_contents(STDIN), true); echo $j["versionstring"] ?? "";')" == "35.0.1" ]]   || echo "INFO: Nextcloud version differs from the original 35.0.1 baseline."
pass "Nextcloud runs under PHP 8.5"

occ85 app:getpath memories >/dev/null 2>&1 || fail "Memories is not available under PHP 8.5."
pass "Memories runs under PHP 8.5"

LOCAL_STATUS="$(curl -fsS --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/status.php")"
grep -q '"installed":true' <<<"$LOCAL_STATUS" || fail "Local HTTPS Nextcloud status is unhealthy."
pass "Local HTTPS works through PHP 8.5 FPM"

PUBLIC4_STATUS="$(curl -4 -fsS --max-time 20 "https://$DOMAIN/status.php")"
grep -q '"installed":true' <<<"$PUBLIC4_STATUS" || fail "Public IPv4 HTTPS failed."
pass "Public IPv4 HTTPS works"

if getent ahostsv6 "$DOMAIN" >/dev/null 2>&1; then
  PUBLIC6_STATUS="$(curl -6 -fsS --max-time 20 "https://$DOMAIN/status.php")"     || fail "Public IPv6 HTTPS failed."
  grep -q '"installed":true' <<<"$PUBLIC6_STATUS" || fail "Public IPv6 status is unhealthy."
  pass "Public IPv6 HTTPS works"
fi

if systemctl is-active --quiet php8.3-fpm.service; then
  fail "PHP 8.3 FPM is still active after cutover."
fi
pass "PHP 8.3 FPM is not active"

echo
echo "Nextcloud setup checks:"
occ85 setupchecks || true

echo
echo "PHASE 2C: PASS"
