# Phase 2A — native Nextcloud base

Phase 1 established this production host:

- Ubuntu 24.04.4 LTS;
- 4 CPU threads;
- approximately 3.8 GiB RAM;
- approximately 111 GiB free on the root ext4 filesystem;
- PHP 8.3.6 / PHP-FPM;
- PostgreSQL 16.15;
- Redis 7.0.15;
- ffmpeg / ffprobe 6.1.1;
- ImageMagick + Imagick;
- Nginx 1.24;
- DNS for `photo.linetty.co.uk`.

The upstream Nextcloud 35 requirements support Ubuntu 24.04, PHP 8.3 and PostgreSQL 16. Memories requires PostgreSQL 15+, Imagick, ffmpeg/ffprobe and distributed caching.

## Scope

Phase 2A deliberately does **not** alter Nginx or request a TLS certificate.

It:

1. creates a 4 GiB swapfile when the machine has no active swap;
2. creates private config/data/backup directories;
3. generates local root-only database/admin credential files;
4. creates the PostgreSQL application role/database;
5. tunes PHP for large iPhone video uploads;
6. verifies Redis;
7. downloads the current Nextcloud 35 archive from the official release server;
8. verifies the upstream SHA-256 before extraction;
9. installs Nextcloud with its config directory outside the web root;
10. configures APCu + Redis caching and Redis transactional locking;
11. installs and enables Memories;
12. switches background jobs to system cron;
13. provides a read-only acceptance script.

## Run

The Phase 2 branch is stacked on the Phase 1 branch until PR #1 is merged.

```bash
cd /srv/photos
git fetch origin
git checkout feat/phase2-native-nextcloud
git pull

sudo bash scripts/install-nextcloud-base.sh
sudo bash scripts/accept-phase2-base.sh
```

The default initial administrator user is `admin`.

To select a different immutable Nextcloud user ID on the **first** run:

```bash
sudo NEXTCLOUD_ADMIN_USER=my-admin-user bash scripts/install-nextcloud-base.sh
```

The generated password is stored only on the server:

```text
/etc/linetty-photos/nextcloud-admin-password
```

Do not paste that password into Git or chat.

## Paths

```text
/var/www/nextcloud
/etc/nextcloud
/etc/linetty-photos
/srv/linetty-photos/data
/srv/linetty-photos/backups
```

## Phase 2B

Only after Phase 2A passes:

- install the Nginx virtual host for `photo.linetty.co.uk`;
- verify the A and AAAA records terminate on this host;
- obtain a Let's Encrypt certificate;
- enable HTTPS-only access;
- add Nextcloud well-known redirects and upload-safe FastCGI settings;
- run the web-facing health and security checks.
