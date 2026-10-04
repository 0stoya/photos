# Phase 1 — native host discovery

This phase is read-only.

Do not install packages, change Nginx, create databases, request certificates or create storage directories until the host output has been reviewed.

## Run

From a checkout of this repository on the intended Ubuntu server:

```bash
cd /path/to/photos
bash scripts/preflight.sh
```

Paste the complete output into the deployment review.

## What the preflight establishes

- Ubuntu version and kernel;
- CPU and memory;
- root and `/srv` storage;
- presence and versions of Nginx, PHP, PostgreSQL, Redis, ffmpeg and ffprobe;
- PHP extensions required by Nextcloud/Memories;
- relevant service states;
- DNS resolution for `photos.linetty.co.uk`.

## Acceptance

Phase 1 discovery passes when we have enough information to write the installation steps without guessing:

- supported Ubuntu release;
- supported PHP version;
- PostgreSQL 15+ available or installable;
- Redis available or installable;
- sufficient storage for the expected photo/video library;
- a known PHP-FPM socket;
- DNS pointed at the intended server.

The preflight itself does not declare the host production-ready.
