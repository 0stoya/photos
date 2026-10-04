#!/usr/bin/env bash
set -Eeuo pipefail

DOMAIN="photo.linetty.co.uk"
NC_ROOT="/var/www/nextcloud"
NC_CONFIG="/etc/nextcloud"
PHP_FPM_SOCKET="/run/php/php8.5-fpm.sock"
PHP_FPM_POOL="/etc/php/8.5/fpm/pool.d/www.conf"
SITE_AVAILABLE="/etc/nginx/sites-available/linetty-photos"
SITE_ENABLED="/etc/nginx/sites-enabled/linetty-photos"
ACME_ROOT="/var/www/certbot"
CERT_DIR="/etc/letsencrypt/live/$DOMAIN"

fail() {
  echo "ERROR: $*" >&2
  exit 1
}

section() {
  printf '\n==> %s\n' "$1"
}

occ() {
  runuser -u www-data -- env NEXTCLOUD_CONFIG_DIR="$NC_CONFIG" /usr/bin/php8.5 "$NC_ROOT/occ" "$@"
}

[[ "${EUID}" -eq 0 ]] || fail "Run this script as root."
[[ -f "$NC_ROOT/occ" ]] || fail "Nextcloud is not installed at $NC_ROOT."
[[ -f "$NC_CONFIG/config.php" ]] || fail "Nextcloud config.php is missing from $NC_CONFIG."
[[ -S "$PHP_FPM_SOCKET" ]] || fail "PHP-FPM socket is missing: $PHP_FPM_SOCKET."
systemctl is-active --quiet nginx.service || fail "nginx.service is not active."
systemctl is-active --quiet php8.5-fpm.service || fail "php8.5-fpm.service is not active."

section "PHP-FPM external config"
[[ -f "$PHP_FPM_POOL" ]] || fail "PHP-FPM pool config is missing: $PHP_FPM_POOL."
if grep -Eq '^[[:space:]]*env\[NEXTCLOUD_CONFIG_DIR\][[:space:]]*=' "$PHP_FPM_POOL"; then
  sed -i -E "s#^[[:space:]]*env\[NEXTCLOUD_CONFIG_DIR\][[:space:]]*=.*#env[NEXTCLOUD_CONFIG_DIR] = $NC_CONFIG#" "$PHP_FPM_POOL"
else
  printf '\n; Linetty Photos external Nextcloud config\nenv[NEXTCLOUD_CONFIG_DIR] = %s\n' "$NC_CONFIG" >> "$PHP_FPM_POOL"
fi
php-fpm8.5 -t
systemctl restart php8.5-fpm.service
systemctl is-active --quiet php8.5-fpm.service || fail "PHP-FPM failed after config environment update."

section "DNS"
A_RECORDS="$(getent ahostsv4 "$DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u || true)"
AAAA_RECORDS="$(getent ahostsv6 "$DOMAIN" 2>/dev/null | awk '{print $1}' | sort -u || true)"

[[ -n "$A_RECORDS" || -n "$AAAA_RECORDS" ]] || fail "$DOMAIN does not resolve."

echo "IPv4:"
if [[ -n "$A_RECORDS" ]]; then printf '%s\n' "$A_RECORDS"; else echo "none"; fi
echo "IPv6:"
if [[ -n "$AAAA_RECORDS" ]]; then printf '%s\n' "$AAAA_RECORDS"; else echo "none"; fi

section "ACME bootstrap site"
install -d -o root -g root -m 0755 "$ACME_ROOT/.well-known/acme-challenge"

cat > "$SITE_AVAILABLE" <<NGINX
server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    server_tokens off;

    location ^~ /.well-known/acme-challenge/ {
        root $ACME_ROOT;
        default_type text/plain;
        try_files \$uri =404;
    }

    location / {
        return 404;
    }
}
NGINX

ln -sfn "$SITE_AVAILABLE" "$SITE_ENABLED"
nginx -t
systemctl reload nginx

PROBE_NAME="linetty-phase2b-probe"
PROBE_VALUE="linetty-phase2b-ok"
printf '%s\n' "$PROBE_VALUE" > "$ACME_ROOT/.well-known/acme-challenge/$PROBE_NAME"

if [[ -n "$A_RECORDS" ]]; then
  if curl -4 -fsS --max-time 10 "http://$DOMAIN/.well-known/acme-challenge/$PROBE_NAME" | grep -qx "$PROBE_VALUE"; then
    echo "IPv4 HTTP challenge path: reachable"
  else
    echo "WARNING: local IPv4 challenge probe failed; Certbot will perform the authoritative external check." >&2
  fi
fi

if [[ -n "$AAAA_RECORDS" ]]; then
  if curl -6 -fsS --max-time 10 "http://$DOMAIN/.well-known/acme-challenge/$PROBE_NAME" | grep -qx "$PROBE_VALUE"; then
    echo "IPv6 HTTP challenge path: reachable"
  else
    echo "WARNING: local IPv6 challenge probe failed; verify the AAAA record if Certbot cannot validate." >&2
  fi
fi

rm -f "$ACME_ROOT/.well-known/acme-challenge/$PROBE_NAME"

section "Certbot"
if ! command -v certbot >/dev/null 2>&1; then
  if ! command -v snap >/dev/null 2>&1; then
    apt-get update
    DEBIAN_FRONTEND=noninteractive apt-get install -y snapd
    systemctl enable --now snapd.socket
  fi

  if ! snap list certbot >/dev/null 2>&1; then
    snap install --classic certbot
  fi
  ln -sfn /snap/bin/certbot /usr/local/bin/certbot
fi

CERTBOT_ARGS=(
  certonly
  --webroot
  --webroot-path "$ACME_ROOT"
  --domain "$DOMAIN"
  --non-interactive
  --agree-tos
  --keep-until-expiring
)

if [[ -n "${CERTBOT_EMAIL:-}" ]]; then
  CERTBOT_ARGS+=(--email "$CERTBOT_EMAIL")
else
  echo "CERTBOT_EMAIL is not set; registering without an email address."
  CERTBOT_ARGS+=(--register-unsafely-without-email)
fi

certbot "${CERTBOT_ARGS[@]}"

[[ -r "$CERT_DIR/fullchain.pem" ]] || fail "Certificate full chain was not created."
[[ -r "$CERT_DIR/privkey.pem" ]] || fail "Certificate private key was not created."

section "Production Nginx site"
cat > "$SITE_AVAILABLE" <<NGINX
map \$arg_v \$linetty_asset_immutable {
    "" "";
    default ", immutable";
}

upstream linetty_photos_php {
    server unix:$PHP_FPM_SOCKET;
}

server {
    listen 80;
    listen [::]:80;
    server_name $DOMAIN;

    server_tokens off;

    location ^~ /.well-known/acme-challenge/ {
        root $ACME_ROOT;
        default_type text/plain;
        try_files \$uri =404;
    }

    location / {
        return 301 https://\$server_name\$request_uri;
    }
}

server {
    listen 443 ssl http2;
    listen [::]:443 ssl http2;
    server_name $DOMAIN;

    root $NC_ROOT;
    index index.php index.html /index.php\$request_uri;

    server_tokens off;

    ssl_certificate $CERT_DIR/fullchain.pem;
    ssl_certificate_key $CERT_DIR/privkey.pem;
    ssl_protocols TLSv1.2 TLSv1.3;
    ssl_session_cache shared:LINETTYSSL:10m;
    ssl_session_timeout 1d;
    ssl_session_tickets off;
    ssl_stapling off;
    ssl_stapling_verify off;

    add_header Strict-Transport-Security "max-age=15552000" always;
    add_header Referrer-Policy "no-referrer" always;
    add_header X-Content-Type-Options "nosniff" always;
    add_header X-Frame-Options "SAMEORIGIN" always;
    add_header X-Permitted-Cross-Domain-Policies "none" always;
    add_header X-Robots-Tag "noindex, nofollow" always;

    include mime.types;
    types {
        text/javascript mjs;
        application/wasm wasm;
    }

    client_max_body_size 20G;
    client_body_timeout 3600s;
    client_body_buffer_size 512k;

    location = /robots.txt {
        allow all;
        log_not_found off;
        access_log off;
    }

    location = /.well-known/carddav {
        return 301 /remote.php/dav/;
    }

    location = /.well-known/caldav {
        return 301 /remote.php/dav/;
    }

    location ^~ /.well-known {
        return 301 /index.php\$request_uri;
    }

    location ~ ^/(?:build|tests|config|lib|3rdparty|templates|data)(?:\$|/) {
        return 404;
    }

    location ~ ^/(?:\.|autotest|occ|issue|indie|db_|console) {
        return 404;
    }

    location ~ ^/(?:composer\.(?:json|lock)|package(?:-lock)?\.json|core/shipped\.json)\$ {
        return 404;
    }

    location ~ \.php(?:\$|/) {
        rewrite ^/(?!index|remote|public|cron|status|ocs/v[12]|ocs-provider/.+|core/ajax/update|updater/.+|.+/richdocumentscode(_arm64)?/proxy) /index.php\$request_uri;

        fastcgi_split_path_info ^(.+?\.php)(/.*)\$;
        set \$path_info \$fastcgi_path_info;
        try_files \$fastcgi_script_name =404;

        include fastcgi_params;
        fastcgi_pass linetty_photos_php;
        fastcgi_param SCRIPT_FILENAME \$document_root\$fastcgi_script_name;
        fastcgi_param PATH_INFO \$path_info;
        fastcgi_param HTTPS on;
        fastcgi_param modHeadersAvailable true;
        fastcgi_param front_controller_active true;
        fastcgi_param HTTP_HOST \$host;

        fastcgi_intercept_errors on;
        fastcgi_hide_header X-Powered-By;
        fastcgi_request_buffering on;
        fastcgi_read_timeout 3600s;
        fastcgi_send_timeout 3600s;
        fastcgi_connect_timeout 60s;
        fastcgi_max_temp_file_size 0;
    }

    location ~ \.(?:css|js|mjs|svg|gif|png|jpg|jpeg|webp|ico|wasm|tflite|map|ogg|flac|mp4|webm)\$ {
        try_files \$uri /index.php\$request_uri;
        add_header Cache-Control "public, max-age=15778463\$linetty_asset_immutable";
        add_header Strict-Transport-Security "max-age=15552000" always;
        add_header Referrer-Policy "no-referrer" always;
        add_header X-Content-Type-Options "nosniff" always;
        add_header X-Frame-Options "SAMEORIGIN" always;
        add_header X-Permitted-Cross-Domain-Policies "none" always;
        add_header X-Robots-Tag "noindex, nofollow" always;
        access_log off;
    }

    location ~ \.(?:woff2?|eot|otf|ttf)\$ {
        try_files \$uri /index.php\$request_uri;
        expires 7d;
        access_log off;
    }

    location /remote {
        return 301 /remote.php\$request_uri;
    }

    location / {
        try_files \$uri \$uri/ /index.php\$request_uri;
    }
}
NGINX

nginx -t
systemctl reload nginx

section "Nextcloud HTTPS configuration"
occ config:system:set trusted_domains 0 --value="$DOMAIN"
occ config:system:set overwrite.cli.url --value="https://$DOMAIN"
occ config:system:set overwritehost --value="$DOMAIN"
occ config:system:set overwriteprotocol --value="https"

section "Local HTTPS check"
LOCAL_STATUS="$(curl -fsS --resolve "$DOMAIN:443:127.0.0.1" "https://$DOMAIN/status.php")"
grep -q '"installed":true' <<<"$LOCAL_STATUS" || fail "Local HTTPS Nextcloud status check failed."
echo "Local HTTPS status: OK"

section "Certificate renewal"
if command -v snap >/dev/null 2>&1 && snap list certbot >/dev/null 2>&1; then
  systemctl list-timers --all 2>/dev/null | grep -E 'certbot|snap.certbot' || true
fi

echo
echo "Phase 2B exposure complete."
echo "Run: sudo bash scripts/accept-phase2b-web.sh"
