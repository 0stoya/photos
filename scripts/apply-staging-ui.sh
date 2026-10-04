#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="photo.linetty.co.uk"
NC_ROOT="/var/www/nextcloud"
NC_CONFIG="/etc/nextcloud"
PHP_BIN="/usr/bin/php8.5"

INSTANCE_NAME="${LINETTY_INSTANCE_NAME:-Linetty Photos}"
INSTANCE_SLOGAN="${LINETTY_INSTANCE_SLOGAN:-Our family photos, in one place.}"
INSTANCE_URL="${LINETTY_INSTANCE_URL:-https://photo.linetty.co.uk}"

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

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root."
[[ -x "$PHP_BIN" ]] || fail "PHP 8.5 CLI is missing."
[[ -f "$NC_ROOT/occ" ]] || fail "Nextcloud is missing at $NC_ROOT."
[[ -f "$NC_CONFIG/config.php" ]] || fail "Nextcloud config is missing at $NC_CONFIG/config.php."

occ status --output=json | grep -q '"installed":true' || fail "Nextcloud is not installed."
occ app:getpath memories >/dev/null 2>&1 || fail "Memories is not installed."

section "Instance branding"
occ theming:config name "$INSTANCE_NAME"
occ theming:config url "$INSTANCE_URL"
occ theming:config slogan "$INSTANCE_SLOGAN"

section "Family photo landing"
occ config:system:set defaultapp --value="memories,files"

section "Optional theme colours"
if [[ -n "${LINETTY_PRIMARY_COLOR:-}" ]]; then
  occ theming:config primary_color "$LINETTY_PRIMARY_COLOR"
  echo "Primary colour set to $LINETTY_PRIMARY_COLOR"
else
  echo "Primary colour unchanged."
fi

if [[ -n "${LINETTY_BACKGROUND_COLOR:-}" ]]; then
  occ theming:config background_color "$LINETTY_BACKGROUND_COLOR"
  occ theming:config background backgroundColor
  echo "Background colour set to $LINETTY_BACKGROUND_COLOR"
else
  echo "Background colour/image unchanged."
fi

apply_image() {
  local key="$1"
  local value="$2"

  [[ -n "$value" ]] || return 0
  [[ -r "$value" ]] || fail "Theme asset is not readable: $value"
  occ theming:config "$key" "$value"
}

section "Optional theme images"
apply_image logo "${LINETTY_LOGO:-}"
apply_image logoheader "${LINETTY_HEADER_LOGO:-}"
apply_image favicon "${LINETTY_FAVICON:-}"
apply_image background "${LINETTY_LOGIN_BACKGROUND:-}"

if [[ -z "${LINETTY_LOGO:-}${LINETTY_HEADER_LOGO:-}${LINETTY_FAVICON:-}${LINETTY_LOGIN_BACKGROUND:-}" ]]; then
  echo "No image assets supplied; existing theme images remain unchanged."
fi

section "User theming policy"
if [[ "${LINETTY_DISABLE_USER_THEMING:-no}" == "yes" ]]; then
  occ theming:config disable-user-theming true
  echo "Per-user theming disabled."
else
  echo "Per-user theming remains available."
fi

section "Acceptance preview"
echo "Name:       $(occ config:app:get theming name)"
echo "Slogan:     $(occ config:app:get theming slogan)"
echo "URL:        $(occ config:app:get theming url)"
echo "Defaultapp: $(occ config:system:get defaultapp)"
echo
echo "Staging UI configuration applied."
echo "No backup jobs, backup timers or storage migration are part of Phase 3A."
