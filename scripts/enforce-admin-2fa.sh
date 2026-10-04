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

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root."

for app in twofactor_totp twofactor_backupcodes; do
  occ app:getpath "$app" >/dev/null 2>&1 || fail "$app is not installed."
  occ app:list --enabled | grep -Eq "^[[:space:]]*-[[:space:]]+$app:" \
    || fail "$app is not enabled."
done

if [[ "${LINETTY_CONFIRM_ADMIN_2FA:-no}" != "yes" ]]; then
  fail "Refusing to enforce 2FA without LINETTY_CONFIRM_ADMIN_2FA=yes. Configure TOTP and backup codes for the current admin account first."
fi

occ twofactorauth:enforce --on --group=admin

echo
echo "2FA is now enforced for members of the Nextcloud admin group."
echo "Keep a tested backup code outside the server before ending your current admin session."
