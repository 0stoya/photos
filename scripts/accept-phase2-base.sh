#!/usr/bin/env bash
set -Eeuo pipefail

NC_ROOT="/var/www/nextcloud"
NC_CONFIG="/etc/nextcloud"
NC_DATA="/srv/linetty-photos/data"
PRIVATE_DIR="/etc/linetty-photos"
DB_PASS_FILE="$PRIVATE_DIR/postgres-nextcloud-password"
DB_NAME="nextcloud"
DB_USER="nextcloud"
PHP_FPM_POOL="/etc/php/8.3/fpm/pool.d/www.conf"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

pass() {
  echo "PASS: $*"
}

occ() {
  runuser -u www-data -- env NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" /usr/bin/php "$NC_ROOT/occ" "$@"
}

[[ "${EUID}" -eq 0 ]] || fail "Run as root."

echo "LINETTY PHOTOS - PHASE 2A ACCEPTANCE"
echo "===================================="

[[ -f "$NC_ROOT/occ" ]] || fail "Nextcloud occ is missing."
pass "Nextcloud application exists"

[[ -d "$NC_CONFIG" ]] || fail "External config directory is missing."
[[ -f "$NC_CONFIG/config.php" ]] || fail "External config.php is missing."
pass "External config directory is in use"

[[ -f "$PHP_FPM_POOL" ]] || fail "PHP-FPM pool config is missing."
grep -Eq '^[[:space:]]*env\[NEXTCLOUD_CONFIG_DIR\][[:space:]]*=[[:space:]]*/etc/nextcloud[[:space:]]*
[[ -d "$NC_DATA" ]] || fail "Data directory is missing."
[[ "$(stat -c '%U:%G' "$NC_DATA")" == "www-data:www-data" ]] || fail "Data directory ownership is not www-data:www-data."
pass "Private data directory exists outside web root"

[[ -s "$DB_PASS_FILE" ]] || fail "Database password file is missing."
DB_PASS="$(tr -d '\r\n' < "$DB_PASS_FILE")"
PGPASSWORD="$DB_PASS" psql --host=127.0.0.1 --username="$DB_USER" --dbname="$DB_NAME" --tuples-only --command='SELECT 1;' | grep -q 1   || fail "Nextcloud PostgreSQL login failed."
pass "PostgreSQL application login works"

redis-cli ping | grep -qx PONG || fail "Redis did not answer PONG."
pass "Redis responds"

occ status --output=json | grep -q '"installed":true' || fail "Nextcloud does not report installed=true."
pass "Nextcloud reports installed=true"

[[ "$(occ config:system:get trusted_domains 0)" == "photo.linetty.co.uk" ]] || fail "Trusted domain is incorrect."
pass "Trusted domain is photo.linetty.co.uk"

[[ "$(occ config:system:get memcache.locking)" == '\OC\Memcache\Redis' ]] || fail "Redis locking is not configured."
pass "Redis transactional locking is configured"

occ app:getpath memories >/dev/null 2>&1 || fail "Memories is not installed."
pass "Memories is installed"

[[ -f /etc/cron.d/linetty-nextcloud ]] || fail "Nextcloud cron file is missing."
pass "System cron is configured"

swapon --noheadings | grep -q . || fail "No active swap was found."
pass "Swap is active"

echo
occ status
echo
echo "PHASE 2A: PASS"
 "$PHP_FPM_POOL"   || fail "PHP-FPM is not configured with NEXTCLOUD_CONFIG_DIR=/etc/nextcloud."
pass "PHP-FPM receives the external Nextcloud config directory"

[[ -d "$NC_DATA" ]] || fail "Data directory is missing."
[[ "$(stat -c '%U:%G' "$NC_DATA")" == "www-data:www-data" ]] || fail "Data directory ownership is not www-data:www-data."
pass "Private data directory exists outside web root"

[[ -s "$DB_PASS_FILE" ]] || fail "Database password file is missing."
DB_PASS="$(tr -d '\r\n' < "$DB_PASS_FILE")"
PGPASSWORD="$DB_PASS" psql --host=127.0.0.1 --username="$DB_USER" --dbname="$DB_NAME" --tuples-only --command='SELECT 1;' | grep -q 1   || fail "Nextcloud PostgreSQL login failed."
pass "PostgreSQL application login works"

redis-cli ping | grep -qx PONG || fail "Redis did not answer PONG."
pass "Redis responds"

occ status --output=json | grep -q '"installed":true' || fail "Nextcloud does not report installed=true."
pass "Nextcloud reports installed=true"

[[ "$(occ config:system:get trusted_domains 0)" == "photo.linetty.co.uk" ]] || fail "Trusted domain is incorrect."
pass "Trusted domain is photo.linetty.co.uk"

[[ "$(occ config:system:get memcache.locking)" == '\OC\Memcache\Redis' ]] || fail "Redis locking is not configured."
pass "Redis transactional locking is configured"

occ app:getpath memories >/dev/null 2>&1 || fail "Memories is not installed."
pass "Memories is installed"

[[ -f /etc/cron.d/linetty-nextcloud ]] || fail "Nextcloud cron file is missing."
pass "System cron is configured"

swapon --noheadings | grep -q . || fail "No active swap was found."
pass "Swap is active"

echo
occ status
echo
echo "PHASE 2A: PASS"
