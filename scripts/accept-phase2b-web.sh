#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="photo.linetty.co.uk"
NC_ROOT="/var/www/nextcloud"
NC_CONFIG="/etc/nextcloud"
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"

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

http_code() {
  curl -sS -o /dev/null -w '%{http_code}' "$@"
}

[[ "${EUID}" -eq 0 ]] || fail "Run as root."

echo "LINETTY PHOTOS - PHASE 2B WEB ACCEPTANCE"
echo "========================================"

nginx -t >/dev/null 2>&1 || fail "nginx -t failed."
pass "Nginx configuration is valid"

systemctl is-active --quiet nginx.service || fail "Nginx is not active."
systemctl is-active --quiet php8.3-fpm.service || fail "PHP-FPM is not active."
pass "Nginx and PHP-FPM are active"

[[ -r "$CERT_DIR/fullchain.pem" ]] || fail "TLS certificate is missing."
[[ -r "$CERT_DIR/privkey.pem" ]] || fail "TLS private key is missing."
pass "Let's Encrypt certificate files exist"

LOCAL_STATUS="$(curl -fsS --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/status.php")"
grep -q '"installed":true' <<<"$LOCAL_STATUS" || fail "Local HTTPS status.php is not healthy."
pass "Local HTTPS serves installed Nextcloud"

HTTP_CODE="$(http_code --resolve "$DOMAIN:80:127.0.0.1" "http://$DOMAIN/")"
[[ "$HTTP_CODE" == "301" ]] || fail "HTTP did not redirect to HTTPS; got $HTTP_CODE."
pass "HTTP redirects to HTTPS"

ROOT_HEADERS="$(curl -fsSI --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/" | tr -d '\r')"

HSTS="$(awk 'BEGIN{IGNORECASE=1} /^strict-transport-security:/ {print; exit}' <<<"$ROOT_HEADERS")"
[[ "$HSTS" == *"max-age=15552000"* ]] || fail "Expected HSTS header was not found."
pass "HSTS is enabled"

for expected in   'referrer-policy: no-referrer'   'x-content-type-options: nosniff'   'x-frame-options: SAMEORIGIN'   'x-permitted-cross-domain-policies: none'   'x-robots-tag: noindex, nofollow'; do
  grep -Fiqx "$expected" <<<"$ROOT_HEADERS"     || fail "Missing expected security header: $expected"
done
pass "Dynamic responses include the Nextcloud security header set"

MJS_FILE="$(find "$NC_ROOT" -type f -name '*.mjs' -print -quit)"
[[ -n "$MJS_FILE" ]] || fail "Could not find a Nextcloud .mjs asset for MIME validation."
MJS_PATH="${MJS_FILE#"$NC_ROOT"}"
MJS_HEADERS="$(curl -fsSI --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN$MJS_PATH" | tr -d '\r')"
MJS_TYPE="$(awk 'BEGIN{IGNORECASE=1} /^content-type:/ {print tolower($0); exit}' <<<"$MJS_HEADERS")"
[[ "$MJS_TYPE" == *"text/javascript"* || "$MJS_TYPE" == *"application/javascript"* ]]   || fail ".mjs asset has an invalid Content-Type: $MJS_TYPE"
for expected in   'referrer-policy: no-referrer'   'x-content-type-options: nosniff'   'x-frame-options: SAMEORIGIN'   'x-permitted-cross-domain-policies: none'   'x-robots-tag: noindex, nofollow'; do
  grep -Fiqx "$expected" <<<"$MJS_HEADERS"     || fail "Static .mjs response is missing security header: $expected"
done
pass "Static .mjs assets use JavaScript MIME type and security headers"

SENSITIVE_CODE="$(http_code --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/config/config.php")"
[[ "$SENSITIVE_CODE" == "404" ]] || fail "Sensitive config path returned $SENSITIVE_CODE instead of 404."
pass "Sensitive config path is blocked"

CARDDAV_CODE="$(http_code --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/.well-known/carddav")"
[[ "$CARDDAV_CODE" == "301" ]] || fail "CardDAV well-known returned $CARDDAV_CODE instead of 301."
pass "CardDAV well-known redirect works"

PUBLIC4_STATUS="$(curl -4 -fsS --max-time 20 "https://$DOMAIN/status.php")"
grep -q '"installed":true' <<<"$PUBLIC4_STATUS" || fail "Public IPv4 HTTPS status check failed."
pass "Public IPv4 HTTPS works"

if getent ahostsv6 "$DOMAIN" >/dev/null 2>&1; then
  PUBLIC6_STATUS="$(curl -6 -fsS --max-time 20 "https://$DOMAIN/status.php")"     || fail "AAAA record exists but public IPv6 HTTPS failed."
  grep -q '"installed":true' <<<"$PUBLIC6_STATUS" || fail "Public IPv6 HTTPS status response is unhealthy."
  pass "Public IPv6 HTTPS works"
fi

[[ "$(occ config:system:get trusted_domains 0)" == "$DOMAIN" ]] || fail "Trusted domain is incorrect."
[[ "$(occ config:system:get overwriteprotocol)" == "https" ]] || fail "overwriteprotocol is not https."
[[ "$(occ config:system:get overwritehost)" == "$DOMAIN" ]] || fail "overwritehost is incorrect."
pass "Nextcloud canonical HTTPS host settings are correct"

occ app:getpath memories >/dev/null 2>&1 || fail "Memories is not installed."
pass "Memories remains installed"

if command -v certbot >/dev/null 2>&1; then
  certbot certificates 2>/dev/null | grep -q "$DOMAIN" || fail "Certbot does not list the domain certificate."
  pass "Certbot manages the domain certificate"
else
  fail "Certbot is not available."
fi

echo
echo "Nextcloud setup checks:"
occ setupchecks || true

echo
echo "PHASE 2B: PASS"
