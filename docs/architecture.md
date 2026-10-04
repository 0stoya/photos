# Linetty Photos architecture

## Purpose

`photos.linetty.co.uk` is a private family photo and video service.

The service must support:

- automatic photo/video upload from iPhone through the official Nextcloud iOS app;
- timeline and album browsing through Memories;
- password-protected public share links;
- optional downloads, expiry and upload-only shares;
- original media retained on storage controlled by us;
- straightforward backup and restore.

## Deployment model

Native Ubuntu services only. Docker is intentionally out of scope.

### Application path

```text
/var/www/nextcloud
```

Contains Nextcloud application code only.

### Private configuration

```text
/etc/linetty-photos/
/etc/nextcloud/
```

Secrets and Nextcloud production configuration stay outside the repository and outside the web root.

Nextcloud's `NEXTCLOUD_CONFIG_DIR` should point to `/etc/nextcloud` for both PHP-FPM and CLI/cron.

### Media/data path

```text
/srv/linetty-photos/data
```

The Nextcloud data directory must live outside `/var/www`.

This directory will contain private family media and must never be committed or served directly by Nginx.

### Planned services

```text
Internet
   |
   v
Nginx :443
   |
   v
PHP-FPM
   |
   +--> Nextcloud 35
   |      |
   |      +--> Memories
   |
   +--> PostgreSQL 15+
   +--> Redis
   +--> ImageMagick / Imagick
   +--> ffmpeg / ffprobe

Nextcloud data
   |
   v
/srv/linetty-photos/data
```

## Security boundaries

1. HTTPS only for the public service.
2. PostgreSQL and Redis remain local/private; they are not internet-facing.
3. The Nextcloud data directory is outside the web root.
4. Production `config.php`, database credentials and TLS private keys are not stored in Git.
5. Public sharing is disabled or tightly configured unless explicitly needed.
6. Family user accounts use strong passwords; 2FA can be enabled for administrator accounts.
7. Nginx and PHP upload limits must explicitly support large iPhone video files.
8. Background jobs use system cron rather than AJAX cron.

## Storage and backup

A photo service is not a backup simply because it contains photographs.

The production backup must cover both:

- PostgreSQL database; and
- `/srv/linetty-photos/data`.

A database-only backup cannot restore the media library.

The backup copy should live on different storage from the primary library.

## Version baseline

Initial target:

- Nextcloud 35 stable;
- PHP 8.3-8.5;
- PostgreSQL 15-18;
- current Memories release compatible with Nextcloud 35.

Exact package versions will be selected after host discovery.

## Phase 1 boundary

Before any package installation or service changes:

1. inspect the Ubuntu release and hardware;
2. inspect existing Nginx/PHP/PostgreSQL/Redis services;
3. inspect storage capacity and mount layout;
4. confirm DNS for `photos.linetty.co.uk`;
5. choose exact application/data/backup paths;
6. only then create an idempotent installation/deployment script.
