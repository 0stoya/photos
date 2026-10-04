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

occ() {
  runuser -u www-data -- env NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" "$PHP_BIN" "$NC_ROOT/occ" "$@"
}

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root."
[[ -x "$PHP_BIN" ]] || fail "PHP 8.5 CLI is missing."

UID_VALUE="${LINETTY_UID:-}"
DISPLAY_NAME="${LINETTY_DISPLAY_NAME:-}"
EMAIL="${LINETTY_EMAIL:-}"
MAKE_ADMIN="${LINETTY_ADMIN:-no}"

[[ -n "$UID_VALUE" ]] || fail "Set LINETTY_UID to the desired immutable login ID."
[[ "$UID_VALUE" =~ ^[a-zA-Z0-9._@-]+$ ]] || fail "LINETTY_UID contains unsupported characters."
[[ -n "$DISPLAY_NAME" ]] || DISPLAY_NAME="$UID_VALUE"

if occ user:info "$UID_VALUE" >/dev/null 2>&1; then
  fail "User $UID_VALUE already exists. This script will not overwrite an existing account."
fi

if ! occ group:info "$FAMILY_GROUP" >/dev/null 2>&1; then
  occ group:add "$FAMILY_GROUP"
fi

read -r -s -p "Password for $UID_VALUE: " PASSWORD_ONE
echo
read -r -s -p "Confirm password: " PASSWORD_TWO
echo

[[ -n "$PASSWORD_ONE" ]] || fail "Password cannot be empty."
[[ "$PASSWORD_ONE" == "$PASSWORD_TWO" ]] || fail "Passwords do not match."

args=(user:add --password-from-env --display-name="$DISPLAY_NAME" --group="$FAMILY_GROUP")
if [[ -n "$EMAIL" ]]; then
  args+=(--email "$EMAIL")
fi
args+=("$UID_VALUE")

runuser -u www-data -- env \
  NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" \
  OC_PASS="$PASSWORD_ONE" \
  "$PHP_BIN" "$NC_ROOT/occ" "${args[@]}"

unset PASSWORD_ONE PASSWORD_TWO

if [[ "$MAKE_ADMIN" == "yes" ]]; then
  occ group:adduser admin "$UID_VALUE"
  echo "User $UID_VALUE added to admin group."
fi

echo
occ user:info "$UID_VALUE"
echo
echo "Created family account: $UID_VALUE"
