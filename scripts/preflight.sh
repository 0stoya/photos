#!/usr/bin/env bash
set -u

DOMAIN="photos.linetty.co.uk"

section() {
  printf '\n==> %s\n' "$1"
}

version_or_missing() {
  local label="$1"
  local command_name="$2"
  shift 2

  printf '%-18s ' "$label"
  if command -v "$command_name" >/dev/null 2>&1; then
    "$command_name" "$@" 2>&1 | head -n 1
  else
    echo "MISSING"
  fi
}

service_status() {
  local unit="$1"
  local active="absent"
  local enabled="absent"

  if systemctl list-unit-files "$unit" --no-legend 2>/dev/null | grep -q .; then
    active="$(systemctl is-active "$unit" 2>/dev/null || true)"
    enabled="$(systemctl is-enabled "$unit" 2>/dev/null || true)"
    [[ -n "$active" ]] || active="unknown"
    [[ -n "$enabled" ]] || enabled="unknown"
  fi

  printf '%-18s active=%-12s enabled=%s\n' "$unit" "$active" "$enabled"
}

echo "LINETTY PHOTOS - NATIVE UBUNTU HOST PREFLIGHT"
echo "============================================="
date -u '+Checked UTC: %Y-%m-%d %H:%M:%S'

section "Operating system"
if [[ -r /etc/os-release ]]; then
  . /etc/os-release
  echo "OS: ${PRETTY_NAME:-unknown}"
else
  echo "OS: unknown"
fi
echo "Kernel: $(uname -srmo)"
echo "Architecture: $(uname -m)"

section "Compute"
if command -v nproc >/dev/null 2>&1; then
  echo "CPU threads: $(nproc)"
fi
if command -v free >/dev/null 2>&1; then
  free -h
fi

section "Storage"
df -hT /
if [[ -e /srv ]]; then
  df -hT /srv | tail -n +2
else
  echo "/srv: MISSING"
fi
if command -v findmnt >/dev/null 2>&1; then
  echo
  echo "Mounts relevant to / and /srv:"
  findmnt -T / -o TARGET,SOURCE,FSTYPE,SIZE,AVAIL,USE% 2>/dev/null || true
  findmnt -T /srv -o TARGET,SOURCE,FSTYPE,SIZE,AVAIL,USE% 2>/dev/null || true
fi

section "Runtime versions"
version_or_missing "nginx" nginx -v
version_or_missing "php" php -v
version_or_missing "psql" psql --version
version_or_missing "redis-server" redis-server --version
version_or_missing "ffmpeg" ffmpeg -version
version_or_missing "ffprobe" ffprobe -version
version_or_missing "imagemagick" convert -version

section "PHP modules"
if command -v php >/dev/null 2>&1; then
  required_modules=(curl dom fileinfo gd gmp intl mbstring openssl xml zip)
  useful_modules=(apcu bz2 exif imagick redis sodium)
  php_modules="$(php -m 2>/dev/null | tr '[:upper:]' '[:lower:]')"

  for module in "${required_modules[@]}"; do
    if grep -qx "$module" <<<"$php_modules"; then
      printf '%-12s OK\n' "$module"
    else
      printf '%-12s MISSING\n' "$module"
    fi
  done

  echo "-- useful / app-specific --"
  for module in "${useful_modules[@]}"; do
    if grep -qx "$module" <<<"$php_modules"; then
      printf '%-12s OK\n' "$module"
    else
      printf '%-12s MISSING\n' "$module"
    fi
  done
else
  echo "PHP is not installed."
fi

section "PHP-FPM sockets"
if compgen -G '/run/php/*.sock' >/dev/null 2>&1; then
  ls -l /run/php/*.sock 2>/dev/null || true
else
  echo "No /run/php/*.sock sockets found."
fi

section "Service state"
if command -v systemctl >/dev/null 2>&1; then
  service_status nginx
  service_status postgresql
  service_status redis-server
  service_status redis

  while IFS= read -r unit; do
    [[ -z "$unit" ]] && continue
    service_status "$unit"
  done < <(systemctl list-unit-files 'php*-fpm.service' --no-legend 2>/dev/null | awk '{print $1}')
else
  echo "systemctl unavailable"
fi

section "DNS"
if command -v getent >/dev/null 2>&1; then
  getent ahosts "$DOMAIN" | awk '!seen[$1]++ {print}' || true
else
  echo "getent unavailable"
fi

section "Existing target paths"
for path in /var/www/nextcloud /srv/linetty-photos /etc/linetty-photos /etc/nextcloud; do
  if [[ -e "$path" ]]; then
    echo "$path: EXISTS"
  else
    echo "$path: absent"
  fi
done

section "Result"
echo "Discovery complete. This script made no configuration changes."
