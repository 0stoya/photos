# Linetty Photos

Private family photo and video hosting for **https://photo.linetty.co.uk**.

This repository contains the deployment configuration and operational tooling for a native Ubuntu installation. Media files, database contents, credentials, TLS keys and other private data must never be committed here.

## Target stack

- Ubuntu 24.04 LTS or 26.04 LTS
- Nginx
- PHP-FPM
- Nextcloud 35
- Memories
- PostgreSQL 15+
- Redis
- ImageMagick / PHP Imagick
- ffmpeg / ffprobe
- Let's Encrypt TLS

No Docker.

## Goals

1. Automatic iPhone photo and video uploads through the official Nextcloud iOS app.
2. A family-friendly Memories timeline and albums at `photo.linetty.co.uk`.
3. Password-protected share links with optional downloads and expiry.
4. Original media stored outside the web root.
5. Reliable database + media backups.
6. Repeatable, documented deployment and recovery.

## Repository policy

This repository may be public. Therefore:

- never commit passwords, app passwords or API tokens;
- never commit Nextcloud `config.php`;
- never commit TLS private keys;
- never commit database dumps;
- never commit uploaded photos/videos or generated previews;
- production values belong in root-owned files under `/etc/linetty-photos/`.

Initial deployment work will be developed through pull requests from `main`.
