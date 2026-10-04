#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="photo.linetty.co.uk"
NC_ROOT="/var/www/nextcloud"
NC_DATA="/srv/linetty-photos/data"
NC_BACKUPS="/srv/linetty-photos/backups"
NC_CONFIG="/etc/nextcloud"
PRIVATE_DIR="/etc/linetty-photos"
PHP_VERSION="8.3"
PHP_FPM_SERVICE="php8.3-fpm.service"
DB_NAME="nextcloud"
DB_USER="nextcloud"
DB_PASS_FILE="${PRIVATE_DIR}/postgres-nextcloud-password"
ADMIN_USER_FILE="${PRIVATE_DIR}/nextcloud-admin-user"
ADMIN_PASS_FILE="${PRIVATE_DIR}/nextcloud-admin-password"
SWAP_FILE="/swapfile"
SWAP_SIZE="4G"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

section() {
  printf '\n==> %s\n' "$1"
}

require_command() {
  command -v "$1" >/dev/null 2>&1 || fail "Required command is missing: $1"
}

occ() {
  runuser -u www-data -- env NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" /usr/bin/php "$NC_ROOT/occ" "$@"
}

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root."

[[ -r /etc/os-release ]] || fail "/etc/os-release is missing."
. /etc/os-release
[[ "${ID:-}" == "ubuntu" ]] || fail "Ubuntu is required."
[[ "${VERSION_ID:-}" == "24.04" ]] || fail "This phase is pinned to Ubuntu 24.04; found ${PRETTY_NAME:-unknown}."

for cmd in nginx php psql redis-cli ffmpeg ffprobe convert curl tar sha256sum openssl runuser systemctl swapon mkswap; do
  require_command "$cmd"
done

[[ "$(php -r 'echo PHP_MAJOR_VERSION.".".PHP_MINOR_VERSION;')" == "$PHP_VERSION" ]]   || fail "Expected PHP $PHP_VERSION."

systemctl is-active --quiet nginx.service || fail "nginx.service is not active."
systemctl is-active --quiet postgresql.service || fail "postgresql.service is not active."
systemctl is-active --quiet redis-server.service || fail "redis-server.service is not active."
systemctl is-active --quiet "$PHP_FPM_SERVICE" || fail "$PHP_FPM_SERVICE is not active."

section "Swap"
if [[ "$(swapon --noheadings 2>/dev/null | wc -l)" -eq 0 ]]; then
  if [[ -e "$SWAP_FILE" ]]; then
    fail "$SWAP_FILE already exists but no swap is active; inspect it before continuing."
  fi
  echo "Creating $SWAP_SIZE swap at $SWAP_FILE"
  fallocate -l "$SWAP_SIZE" "$SWAP_FILE"
  chmod 600 "$SWAP_FILE"
  mkswap "$SWAP_FILE" >/dev/null
  swapon "$SWAP_FILE"
  grep -Eq '^[[:space:]]*/swapfile[[:space:]]' /etc/fstab     || echo '/swapfile none swap sw 0 0' >> /etc/fstab
else
  echo "Swap is already active; leaving it unchanged."
fi
swapon --show

section "Private directories"
install -d -m 0700 "$PRIVATE_DIR"
install -d -o www-data -g www-data -m 0750 "$NC_CONFIG"
install -d -o www-data -g www-data -m 0750 "$NC_DATA"
install -d -o root -g root -m 0750 "$NC_BACKUPS"
install -d -o root -g root -m 0755 /var/www

section "Secrets"
if [[ ! -s "$DB_PASS_FILE" ]]; then
  openssl rand -hex 32 > "$DB_PASS_FILE"
fi
chmod 0600 "$DB_PASS_FILE"
chown root:root "$DB_PASS_FILE"

if [[ ! -s "$ADMIN_USER_FILE" ]]; then
  printf '%s\n' "${NEXTCLOUD_ADMIN_USER:-admin}" > "$ADMIN_USER_FILE"
fi
chmod 0600 "$ADMIN_USER_FILE"
chown root:root "$ADMIN_USER_FILE"

if [[ ! -s "$ADMIN_PASS_FILE" ]]; then
  openssl rand -hex 24 > "$ADMIN_PASS_FILE"
fi
chmod 0600 "$ADMIN_PASS_FILE"
chown root:root "$ADMIN_PASS_FILE"

DB_PASS="$(tr -d '\r\n' < "$DB_PASS_FILE")"
ADMIN_USER="$(tr -d '\r\n' < "$ADMIN_USER_FILE")"
ADMIN_PASS="$(tr -d '\r\n' < "$ADMIN_PASS_FILE")"

[[ "$DB_PASS" =~ ^[0-9a-f]{64}$ ]] || fail "Unexpected database password format."
[[ -n "$ADMIN_USER" ]] || fail "Admin username is empty."
[[ "$ADMIN_PASS" =~ ^[0-9a-f]{48}$ ]] || fail "Unexpected admin password format."

section "PostgreSQL"
runuser -u postgres -- psql --set=ON_ERROR_STOP=1 --dbname=postgres <<SQL
DO \$\$
BEGIN
  IF NOT EXISTS (SELECT 1 FROM pg_roles WHERE rolname = '$DB_USER') THEN
    CREATE ROLE $DB_USER LOGIN PASSWORD '$DB_PASS';
  ELSE
    ALTER ROLE $DB_USER WITH LOGIN PASSWORD '$DB_PASS';
  END IF;
END
\$\$;

SELECT 'CREATE DATABASE $DB_NAME OWNER $DB_USER ENCODING ''UTF8'' TEMPLATE template0'
WHERE NOT EXISTS (SELECT 1 FROM pg_database WHERE datname = '$DB_NAME') \gexec

ALTER DATABASE $DB_NAME OWNER TO $DB_USER;
REVOKE ALL ON DATABASE $DB_NAME FROM PUBLIC;
SQL

PGPASSWORD="$DB_PASS" psql   --host=127.0.0.1   --username="$DB_USER"   --dbname="$DB_NAME"   --set=ON_ERROR_STOP=1   --command='SELECT current_database(), current_user;' >/dev/null

echo "PostgreSQL connection: OK"

section "PHP tuning"
PHP_FPM_INI="/etc/php/$PHP_VERSION/fpm/conf.d/99-linetty-photos.ini"
PHP_CLI_INI="/etc/php/$PHP_VERSION/cli/conf.d/99-linetty-photos.ini"

cat > "$PHP_FPM_INI" <<'INI'
memory_limit = 512M
upload_max_filesize = 20G
post_max_size = 20G
max_execution_time = 3600
max_input_time = 3600
output_buffering = 0
apc.enable_cli = 1
INI

cp "$PHP_FPM_INI" "$PHP_CLI_INI"
systemctl restart "$PHP_FPM_SERVICE"
systemctl is-active --quiet "$PHP_FPM_SERVICE" || fail "$PHP_FPM_SERVICE failed after PHP tuning."

php -r 'printf("memory_limit=%s upload_max_filesize=%s post_max_size=%s\n", ini_get("memory_limit"), ini_get("upload_max_filesize"), ini_get("post_max_size"));'

section "Redis"
redis-cli ping | grep -qx PONG || fail "Redis did not answer PONG."
echo "Redis: OK"

section "Nextcloud 35 application"
if [[ ! -e "$NC_ROOT" ]]; then
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "${TMP_DIR:-}"' EXIT

  ARCHIVE="$TMP_DIR/latest-35.tar.bz2"
  ARCHIVE_URL="https://download.nextcloud.com/server/releases/latest-35.tar.bz2"
  CHECKSUM_URL="${ARCHIVE_URL}.sha256"

  echo "Downloading current Nextcloud 35 release..."
  curl -fL --retry 3 --retry-delay 2 -o "$ARCHIVE" "$ARCHIVE_URL"

  EXPECTED_SHA="$(curl -fsSL --retry 3 "$CHECKSUM_URL" | awk 'NR == 1 {print $1}')"
  ACTUAL_SHA="$(sha256sum "$ARCHIVE" | awk '{print $1}')"

  [[ "$EXPECTED_SHA" =~ ^[0-9a-fA-F]{64}$ ]] || fail "Could not read the upstream SHA-256."
  [[ "$ACTUAL_SHA" == "$EXPECTED_SHA" ]] || fail "Nextcloud archive SHA-256 mismatch."

  tar -xjf "$ARCHIVE" -C /var/www
elif [[ ! -f "$NC_ROOT/occ" ]]; then
  fail "$NC_ROOT exists but does not look like a Nextcloud installation."
else
  echo "$NC_ROOT already exists; preserving it."
fi

chown -R www-data:www-data "$NC_ROOT"
find "$NC_ROOT" -type d -exec chmod 0750 {} +
find "$NC_ROOT" -type f -exec chmod 0640 {} +

section "Nextcloud installation"
if occ status --output=json 2>/dev/null | grep -q '"installed":true'; then
  echo "Nextcloud is already installed; preserving the existing installation."
else
  occ maintenance:install     --database=pgsql     --database-name="$DB_NAME"     --database-host=127.0.0.1     --database-user="$DB_USER"     --database-pass="$DB_PASS"     --admin-user="$ADMIN_USER"     --admin-pass="$ADMIN_PASS"     --data-dir="$NC_DATA"     --no-interaction
fi

section "Nextcloud system configuration"
occ config:system:set trusted_domains 0 --value="$DOMAIN"
occ config:system:set overwrite.cli.url --value="https://$DOMAIN"
occ config:system:set default_phone_region --value="GB"
occ config:system:set maintenance_window_start --type=integer --value=1
occ config:system:set memcache.local --value='\OC\Memcache\APCu'
occ config:system:set memcache.distributed --value='\OC\Memcache\Redis'
occ config:system:set memcache.locking --value='\OC\Memcache\Redis'
occ config:system:set redis host --value=127.0.0.1
occ config:system:set redis port --type=integer --value=6379
occ background:cron

section "Memories"
if occ app:getpath memories >/dev/null 2>&1; then
  occ app:enable memories >/dev/null
  echo "Memories already installed; enabled."
else
  occ app:install memories
fi

section "Background jobs"
cat > /etc/cron.d/linetty-nextcloud <<CRON
*/5 * * * * www-data NEXTCLOUD_CONFIG_DIR=$NC_CONFIG /usr/bin/php -f $NC_ROOT/cron.php
CRON
chmod 0644 /etc/cron.d/linetty-nextcloud
chown root:root /etc/cron.d/linetty-nextcloud

section "Permissions"
chown -R www-data:www-data "$NC_CONFIG" "$NC_DATA"
chmod 0750 "$NC_CONFIG" "$NC_DATA"
find "$NC_CONFIG" -maxdepth 1 -type f -exec chmod 0640 {} +

section "Acceptance"
occ status
echo
echo "Config directory: $NC_CONFIG"
echo "Data directory:   $NC_DATA"
echo "Admin user file:  $ADMIN_USER_FILE"
echo "Admin pass file:  $ADMIN_PASS_FILE"
echo
echo "Phase 2A complete."
echo "Nginx and TLS have NOT been changed by this script."
