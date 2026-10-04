#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="photo.linetty.co.uk"
NC_ROOT="/var/www/nextcloud"
NC_CONFIG="/etc/nextcloud"
SITE_FILE="/etc/nginx/sites-available/linetty-photos"
CRON_FILE="/etc/cron.d/linetty-nextcloud"
OLD_PHP="8.3"
NEW_PHP="8.5"
OLD_FPM_SERVICE="php8.3-fpm.service"
NEW_FPM_SERVICE="php8.5-fpm.service"
OLD_SOCKET="/run/php/php8.3-fpm.sock"
NEW_SOCKET="/run/php/php8.5-fpm.sock"
NEW_POOL="/etc/php/8.5/fpm/pool.d/www.conf"
NEW_FPM_INI="/etc/php/8.5/fpm/conf.d/99-linetty-photos.ini"
NEW_CLI_INI="/etc/php/8.5/cli/conf.d/99-linetty-photos.ini"
FPM_OVERRIDE_DIR="/etc/systemd/system/php8.5-fpm.service.d"
FPM_OVERRIDE_FILE="${FPM_OVERRIDE_DIR}/linetty-nextcloud.conf"
BACKUP_DIR="/etc/linetty-photos/php85-cutover"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

section() {
  printf '\n==> %s\n' "$1"
}

occ85() {
  runuser -u www-data -- env NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" /usr/bin/php8.5 "$NC_ROOT/occ" "$@"
}

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root."
[[ -r /etc/os-release ]] || fail "/etc/os-release is missing."
. /etc/os-release
[[ "${ID:-}" == "ubuntu" && "${VERSION_ID:-}" == "24.04" ]]   || fail "This upgrade is pinned to Ubuntu 24.04."

for cmd in nginx php psql redis-cli curl apt-get apt-cache update-alternatives runuser systemctl; do
  command -v "$cmd" >/dev/null 2>&1 || fail "Required command is missing: $cmd"
done

[[ -f "$NC_ROOT/occ" ]] || fail "Nextcloud is missing at $NC_ROOT."
[[ -f "$NC_CONFIG/config.php" ]] || fail "Nextcloud config is missing at $NC_CONFIG/config.php."
[[ -f "$SITE_FILE" ]] || fail "Nginx site is missing: $SITE_FILE."
[[ -f "$CRON_FILE" ]] || fail "Nextcloud cron file is missing: $CRON_FILE."
systemctl is-active --quiet nginx.service || fail "nginx.service is not active."
systemctl is-active --quiet "$OLD_FPM_SERVICE" || {
  systemctl is-active --quiet "$NEW_FPM_SERVICE" || fail "Neither PHP 8.3 nor PHP 8.5 FPM is active."
}

section "Pre-upgrade Nextcloud state"
runuser -u www-data -- env NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" /usr/bin/php "$NC_ROOT/occ" status
runuser -u www-data -- env NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" /usr/bin/php "$NC_ROOT/occ" maintenance:mode --on

cleanup_maintenance() {
  if [[ -x /usr/bin/php8.5 ]]; then
    runuser -u www-data -- env NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" /usr/bin/php8.5 "$NC_ROOT/occ" maintenance:mode --off >/dev/null 2>&1 || true
  else
    runuser -u www-data -- env NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" /usr/bin/php "$NC_ROOT/occ" maintenance:mode --off >/dev/null 2>&1 || true
  fi
}
trap cleanup_maintenance EXIT

section "Repository"
apt-get update
DEBIAN_FRONTEND=noninteractive apt-get install -y software-properties-common ca-certificates apt-transport-https
command -v add-apt-repository >/dev/null 2>&1 || fail "add-apt-repository is unavailable after installing software-properties-common."

if ! grep -RqsE '(^|[[:space:]])ppa\.launchpadcontent\.net/ondrej/php/ubuntu|(^|[[:space:]])ppa\.launchpad\.net/ondrej/php/ubuntu'   /etc/apt/sources.list /etc/apt/sources.list.d 2>/dev/null; then
  LC_ALL=C.UTF-8 add-apt-repository -y ppa:ondrej/php
else
  echo "Ondrej PHP PPA already configured."
fi

apt-get update

required_packages=(
  php8.5-cli
  php8.5-fpm
  php8.5-common
  php8.5-bcmath
  php8.5-bz2
  php8.5-curl
  php8.5-gd
  php8.5-gmp
  php8.5-intl
  php8.5-mbstring
  php8.5-pgsql
  php8.5-xml
  php8.5-zip
  php8.5-apcu
  php8.5-redis
  php8.5-imagick
)

section "PHP 8.5 package availability"
for pkg in "${required_packages[@]}"; do
  candidate="$(apt-cache policy "$pkg" | awk '/Candidate:/ {candidate=$2} END {print candidate}')"
  [[ -n "$candidate" && "$candidate" != "(none)" ]] || fail "No install candidate for $pkg."
  printf '%-22s %s\n' "$pkg" "$candidate"
done

section "Install PHP 8.5"
DEBIAN_FRONTEND=noninteractive apt-get install -y "${required_packages[@]}"

[[ -x /usr/bin/php8.5 ]] || fail "/usr/bin/php8.5 was not installed."
[[ -x /usr/sbin/php-fpm8.5 ]] || fail "/usr/sbin/php-fpm8.5 was not installed."

section "PHP 8.5 modules"
modules="$(/usr/bin/php8.5 -m | tr '[:upper:]' '[:lower:]')"
required_modules=(
  apcu
  bz2
  curl
  dom
  exif
  fileinfo
  gd
  gmp
  imagick
  intl
  mbstring
  openssl
  pdo_pgsql
  redis
  sodium
  sysvsem
  xml
  zip
)

for module in "${required_modules[@]}"; do
  grep -qx "$module" <<<"$modules" || fail "PHP 8.5 module missing: $module"
  printf '%-14s OK\n' "$module"
done

/usr/bin/php8.5 -r 'exit(function_exists("opcache_get_status") ? 0 : 1);'   || fail "PHP 8.5 built-in OPcache is unavailable."
echo "Zend OPcache   OK (built into PHP 8.5)"

section "PHP 8.5 systemd write boundary"
install -d -m 0755 "$FPM_OVERRIDE_DIR"
cat > "$FPM_OVERRIDE_FILE" <<SYSTEMD
[Service]
ReadWritePaths=$NC_CONFIG
SYSTEMD
chmod 0644 "$FPM_OVERRIDE_FILE"
systemctl daemon-reload

section "PHP 8.5 tuning"
install -d -m 0755 "$(dirname "$NEW_FPM_INI")" "$(dirname "$NEW_CLI_INI")"

cat > "$NEW_FPM_INI" <<'INI'
memory_limit = 512M
upload_max_filesize = 20G
post_max_size = 20G
max_execution_time = 3600
max_input_time = 3600
output_buffering = 0
apc.enable_cli = 1
opcache.enable = 1
opcache.enable_cli = 1
opcache.memory_consumption = 192
opcache.interned_strings_buffer = 32
opcache.max_accelerated_files = 10000
opcache.revalidate_freq = 60
INI

cp "$NEW_FPM_INI" "$NEW_CLI_INI"

[[ -f "$NEW_POOL" ]] || fail "PHP 8.5 FPM pool is missing: $NEW_POOL."
if grep -Eq '^[[:space:]]*env\[NEXTCLOUD_CONFIG_DIR\][[:space:]]*=' "$NEW_POOL"; then
  sed -i -E "s#^[[:space:]]*env\[NEXTCLOUD_CONFIG_DIR\][[:space:]]*=.*#env[NEXTCLOUD_CONFIG_DIR] = $NC_CONFIG#" "$NEW_POOL"
else
  printf '\n; Linetty Photos external Nextcloud config\nenv[NEXTCLOUD_CONFIG_DIR] = %s\n' "$NC_CONFIG" >> "$NEW_POOL"
fi

/usr/sbin/php-fpm8.5 -t
systemctl enable --now "$NEW_FPM_SERVICE"
systemctl restart "$NEW_FPM_SERVICE"
systemctl is-active --quiet "$NEW_FPM_SERVICE" || fail "$NEW_FPM_SERVICE is not active."
[[ -S "$NEW_SOCKET" ]] || fail "PHP 8.5 FPM socket is missing: $NEW_SOCKET."

[[ "$(/usr/bin/php8.5 -r 'echo ini_get("opcache.enable");')" == "1" ]]   || fail "PHP 8.5 OPcache is not enabled."
[[ "$(/usr/bin/php8.5 -r 'echo ini_get("opcache.enable_cli");')" == "1" ]]   || fail "PHP 8.5 OPcache is not enabled for CLI validation."
echo "PHP 8.5 OPcache: enabled"

section "Nextcloud config permissions"
chown www-data:www-data "$NC_CONFIG"
chmod 0750 "$NC_CONFIG"
find "$NC_CONFIG" -maxdepth 1 -type f -exec chown www-data:www-data {} +
find "$NC_CONFIG" -maxdepth 1 -type f -exec chmod 0640 {} +

runuser -u www-data -- test -w "$NC_CONFIG"   || fail "$NC_CONFIG is not writable by www-data."
runuser -u www-data -- test -w "$NC_CONFIG/config.php"   || fail "$NC_CONFIG/config.php is not writable by www-data."
echo "Nextcloud external config is writable by www-data"

section "Validate Nextcloud on PHP 8.5 before web cutover"
occ85 status --output=json | grep -q '"installed":true' || fail "Nextcloud does not run correctly under PHP 8.5 CLI."
occ85 app:getpath memories >/dev/null 2>&1 || fail "Memories does not load under PHP 8.5."
occ85 config:system:get memcache.locking | grep -Fxq '\OC\Memcache\Redis'   || fail "Nextcloud Redis locking is not available under PHP 8.5."
echo "Nextcloud CLI on PHP 8.5: OK"

section "Backup cutover configuration"
install -d -o root -g root -m 0700 "$BACKUP_DIR"
cp -a "$SITE_FILE" "$BACKUP_DIR/nginx-site.before-php85"
cp -a "$CRON_FILE" "$BACKUP_DIR/cron.before-php85"
if [[ -L /etc/alternatives/php ]]; then
  readlink -f /etc/alternatives/php > "$BACKUP_DIR/php-alternative.before-php85"
fi

section "Nginx cutover"
if grep -Fq "$OLD_SOCKET" "$SITE_FILE"; then
  sed -i "s#$OLD_SOCKET#$NEW_SOCKET#g" "$SITE_FILE"
elif grep -Fq "$NEW_SOCKET" "$SITE_FILE"; then
  echo "Nginx already points to PHP 8.5."
else
  fail "Nginx site contains neither expected PHP-FPM socket."
fi

nginx -t || {
  cp -a "$BACKUP_DIR/nginx-site.before-php85" "$SITE_FILE"
  nginx -t || true
  fail "Nginx validation failed after PHP 8.5 socket change; site restored."
}
systemctl reload nginx

section "CLI and cron cutover"
update-alternatives --set php /usr/bin/php8.5

cat > "$CRON_FILE" <<CRON
*/5 * * * * www-data NEXTCLOUD_CONFIG_DIR=$NC_CONFIG /usr/bin/php8.5 -f $NC_ROOT/cron.php
CRON
chmod 0644 "$CRON_FILE"
chown root:root "$CRON_FILE"

section "Web validation"
systemctl restart "$NEW_FPM_SERVICE"
systemctl is-active --quiet "$NEW_FPM_SERVICE" || fail "$NEW_FPM_SERVICE failed before web validation."

LOCAL_STATUS="$(curl -fsS --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/status.php")"
grep -q '"installed":true' <<<"$LOCAL_STATUS" || {
  cp -a "$BACKUP_DIR/nginx-site.before-php85" "$SITE_FILE"
  cp -a "$BACKUP_DIR/cron.before-php85" "$CRON_FILE"
  nginx -t && systemctl reload nginx
  fail "Local HTTPS failed after PHP 8.5 cutover; Nginx and cron restored."
}
echo "Local HTTPS on PHP 8.5 socket: OK"

section "Nextcloud checks"
occ85 maintenance:mode --off
trap - EXIT
occ85 status
occ85 setupchecks || true

section "Retain PHP 8.3 for rollback"
if systemctl is-active --quiet "$OLD_FPM_SERVICE"; then
  systemctl stop "$OLD_FPM_SERVICE"
fi
systemctl disable "$OLD_FPM_SERVICE" >/dev/null 2>&1 || true

echo
echo "PHP cutover complete."
echo "Production FPM: $NEW_FPM_SERVICE"
echo "Production socket: $NEW_SOCKET"
echo "CLI: PHP $(php -r 'echo PHP_VERSION;')"
echo "PHP 8.3 packages remain installed for rollback, but php8.3-fpm is disabled."
