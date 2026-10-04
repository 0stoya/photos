# Phase 2B — Nginx and HTTPS exposure

Phase 2A must be green before running this phase.

Production host facts:

- public hostname: `photo.linetty.co.uk`;
- Nginx 1.24;
- PHP-FPM socket: `/run/php/php8.3-fpm.sock`;
- Nextcloud root: `/var/www/nextcloud`;
- external Nextcloud config: `/etc/nextcloud`;
- Nextcloud data: `/srv/linetty-photos/data`.

## What Phase 2B changes

1. creates a temporary HTTP-only ACME site;
2. verifies DNS is resolvable and probes IPv4/IPv6 challenge paths where possible;
3. installs Certbot from the supported snap distribution when needed;
4. obtains a Let's Encrypt certificate with the webroot challenge;
5. replaces the bootstrap site with the production Nextcloud Nginx vhost;
6. redirects HTTP to HTTPS while preserving the ACME challenge path;
7. uses the exact local PHP 8.3 Unix socket;
8. allows request bodies up to 20 GiB and long-running upload requests;
9. denies direct requests to Nextcloud private/internal paths;
10. configures WebDAV well-known redirects;
11. enables a six-month HSTS policy;
12. pins Nextcloud's canonical host/protocol to HTTPS;
13. runs local and public web acceptance checks.

OCSP stapling is deliberately disabled because current Nextcloud guidance notes that Let's Encrypt has ended OCSP support.

## Run

```bash
cd /srv/photos
git fetch origin
git checkout feat/phase2b-nginx-tls
git pull

sudo CERTBOT_EMAIL=your-email@example.com bash scripts/expose-nextcloud.sh
sudo bash scripts/accept-phase2b-web.sh
```

Using `CERTBOT_EMAIL` is recommended so Let's Encrypt can send account notices.

If it is omitted, the script uses Certbot's non-interactive no-email registration mode.

## Rollback boundary

Before certificate issuance, only the HTTP bootstrap vhost is public.

After certificate issuance, the generated site file is:

```text
/etc/nginx/sites-available/linetty-photos
```

and is enabled by:

```text
/etc/nginx/sites-enabled/linetty-photos
```

The default Ubuntu Nginx site is left untouched.

Every Nginx change is gated by `nginx -t` before reload.

## Acceptance

Acceptance checks:

- valid Nginx syntax;
- Nginx/PHP-FPM active;
- certificate files present;
- local TLS/SNI path serves healthy Nextcloud;
- port 80 redirects to HTTPS;
- HSTS header present;
- direct access to `/config/config.php` is blocked;
- CardDAV well-known redirect works;
- public IPv4 HTTPS works;
- public IPv6 HTTPS works when an AAAA record exists;
- Nextcloud canonical host/protocol settings are correct;
- Memories remains installed;
- Certbot manages the certificate.

The script also prints `occ setupchecks` at the end for review.
