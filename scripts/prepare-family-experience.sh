#!/usr/bin/env bash
set -Eeuo pipefail

NC_ROOT="/var/www/nextcloud"
NC_CONFIG="/etc/nextcloud"
PHP_BIN="/usr/bin/php8.5"
FAMILY_GROUP="family"

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

ensure_app() {
  local app="$1"

  if ! occ app:getpath "$app" >/dev/null 2>&1; then
    echo "Installing $app..."
    occ app:install "$app"
  fi

  if ! occ app:list --enabled | grep -Eq "^[[:space:]]*-[[:space:]]+$app:"; then
    echo "Enabling $app..."
    occ app:enable "$app"
  else
    echo "$app already enabled."
  fi
}

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root."
[[ -x "$PHP_BIN" ]] || fail "PHP 8.5 CLI is missing."
[[ -f "$NC_ROOT/occ" ]] || fail "Nextcloud is missing at $NC_ROOT."
[[ -f "$NC_CONFIG/config.php" ]] || fail "Nextcloud config is missing at $NC_CONFIG/config.php."

occ status --output=json | grep -q '"installed":true' || fail "Nextcloud is not installed."

section "Photo applications"
ensure_app photos
ensure_app memories

section "Two-factor applications"
ensure_app twofactor_totp
ensure_app twofactor_backupcodes

section "Family group"
if occ group:info "$FAMILY_GROUP" >/dev/null 2>&1; then
  echo "Group $FAMILY_GROUP already exists."
else
  occ group:add "$FAMILY_GROUP"
fi

section "Memories-first landing"
occ config:system:set defaultapp --value="memories,files"

section "Password-protected public sharing"
occ config:app:set core shareapi_allow_links --value="yes"
occ config:app:set core shareapi_enforce_links_password --value="yes"

ALLOW_LINKS="$(occ config:app:get core shareapi_allow_links)"
ENFORCE_PASSWORD="$(occ config:app:get core shareapi_enforce_links_password)"
echo "shareapi_allow_links=$ALLOW_LINKS"
echo "shareapi_enforce_links_password=$ENFORCE_PASSWORD"
echo "Public link sharing is enabled and password protection is enforced."

section "Staging boundary"
echo "No backup automation or storage migration is performed by Phase 3B."
echo "Admin 2FA is prepared but NOT enforced by this script."
echo "Configure TOTP and backup codes on the admin account first, then run enforce-admin-2fa.sh."
