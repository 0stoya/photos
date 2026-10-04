# Phase 2C — PHP 8.5 cutover

Nextcloud 35 supports PHP 8.3, 8.4 and 8.5, with PHP 8.5 recommended.

Ubuntu 24.04's base archive ships PHP 8.3. This phase therefore uses the Ondrej PHP PPA to install PHP 8.5 alongside the existing Ubuntu PHP 8.3 packages.

The cutover is deliberately reversible.

## Safety model

The upgrade:

1. places Nextcloud in maintenance mode;
2. adds the PHP PPA only if it is not already configured;
3. verifies an APT candidate exists for every required PHP 8.5 package;
4. installs PHP 8.5 alongside 8.3;
5. validates required/recommended modules before switching web traffic, including PHP 8.5's built-in OPcache;
6. reproduces the 20 GiB upload and 512 MiB memory tuning;
7. configures the external `NEXTCLOUD_CONFIG_DIR` for PHP 8.5 FPM;
8. validates Nextcloud and Memories with PHP 8.5 CLI;
9. backs up the current Nginx site and cron configuration;
10. switches Nginx to `/run/php/php8.5-fpm.sock`;
11. switches the default PHP CLI and Nextcloud cron to PHP 8.5;
12. verifies local HTTPS;
13. exits maintenance mode;
14. disables PHP 8.3 FPM but retains the PHP 8.3 packages for rollback.

## Run

```bash
cd /srv/photos
git fetch origin
git checkout feat/phase2c-php85
git pull

sudo bash scripts/upgrade-php85.sh
sudo bash scripts/accept-phase2c-php85.sh
```

Expected final result:

```text
PHASE 2C: PASS
```

## Rollback

PHP 8.3 remains installed after Phase 2C.

If the 8.5 cutover exposes an application issue:

```bash
sudo bash scripts/rollback-php83.sh
```

The rollback restores the exact pre-cutover Nginx site and cron files from:

```text
/etc/linetty-photos/php85-cutover/
```

Do not purge PHP 8.3 until PHP 8.5 has been accepted under normal family use.

## PHP 8.5 OPcache packaging

PHP 8.5 makes OPcache a non-optional, statically built part of PHP. There is therefore no separate `php8.5-opcache` package to install. The cutover validates OPcache at runtime instead.


## PHP-FPM systemd hardening

Current Sury PHP-FPM packages harden the service with `ProtectSystem=full`, which makes `/etc` read-only inside the FPM service namespace.

Linetty Photos intentionally keeps the live Nextcloud config at `/etc/nextcloud`, so Phase 2C installs a narrow systemd override:

```ini
[Service]
ReadWritePaths=/etc/nextcloud
```

This preserves the PHP-FPM hardening for the rest of `/etc` while allowing Nextcloud to update its own external configuration.

The override is stored at:

```text
/etc/systemd/system/php8.5-fpm.service.d/linetty-nextcloud.conf
```
