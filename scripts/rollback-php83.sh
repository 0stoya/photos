#!/usr/bin/env bash
set -Eeuo pipefail

NC_ROOT="/var/www/nextcloud"
NC_CONFIG="/etc/nextcloud"
SITE_FILE="/etc/nginx/sites-available/linetty-photos"
CRON_FILE="/etc/cron.d/linetty-nextcloud"
BACKUP_DIR="/etc/linetty-photos/php85-cutover"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root."
[[ -f "$BACKUP_DIR/nginx-site.before-php85" ]] || fail "Nginx rollback copy is missing."
[[ -f "$BACKUP_DIR/cron.before-php85" ]] || fail "Cron rollback copy is missing."
[[ -x /usr/bin/php8.3 ]] || fail "PHP 8.3 CLI is not installed."

echo "Enabling PHP 8.3 FPM..."
systemctl enable --now php8.3-fpm.service
systemctl restart php8.3-fpm.service
[[ -S /run/php/php8.3-fpm.sock ]] || fail "PHP 8.3 FPM socket is missing."

echo "Restoring Nginx and cron..."
cp -a "$BACKUP_DIR/nginx-site.before-php85" "$SITE_FILE"
cp -a "$BACKUP_DIR/cron.before-php85" "$CRON_FILE"

update-alternatives --set php /usr/bin/php8.3
nginx -t
systemctl reload nginx

runuser -u www-data -- env NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" /usr/bin/php8.3 "$NC_ROOT/occ" maintenance:mode --off
runuser -u www-data -- env NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" /usr/bin/php8.3 "$NC_ROOT/occ" status

systemctl stop php8.5-fpm.service || true
systemctl disable php8.5-fpm.service >/dev/null 2>&1 || true

echo
echo "Rollback complete. Production is back on PHP 8.3."
