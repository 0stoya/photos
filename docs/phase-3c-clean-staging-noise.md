# Phase 3C — remove staging noise safely

## Goal

Make Linetty Photos feel like a photo service rather than a generic Nextcloud install, without manually deleting Nextcloud runtime state.

## Important rule

Do **not** manually delete directories inside `/srv/linetty-photos/data` merely because they look temporary.

Nextcloud owns several directories that are easy to mistake for rubbish:

- `appdata_*` — app data, previews and generated state;
- `<user>/files` — the user's actual files;
- `<user>/files_trashbin` — deleted-file storage;
- `<user>/files_versions` — version history;
- `<user>/uploads` — chunked-upload working state;
- `.ocdata` — data-directory marker;
- `updater-*` — updater state.

Chunked upload folders are removed by Nextcloud when uploads complete. Preview data is also Nextcloud-managed and is valuable for a photo-heavy service.

## What Phase 3C changes

The safe default cleanup does four things:

1. disables Nextcloud skeleton content for future users;
2. disables default template content for future users;
3. disables generic staging UI apps:
   - Dashboard;
   - Weather Status;
   - First-run wizard;
   - Recommendations;
4. runs `occ files:cleanup`, which cleans stale file-cache entries rather than deleting real user files.

Files, Photos and Memories remain enabled.

Nextcloud 35 officially supports an empty `skeletondirectory` to prevent default files from being copied into new accounts. The `templatedirectory` source can also be left empty.

## Apply

```bash
cd /srv/photos
git checkout feat/phase3c-clean-staging-noise
git pull

sudo bash scripts/clean-staging-noise.sh
sudo bash scripts/accept-phase3c-clean.sh
```

## Existing users

Disabling skeleton content only affects future first logins. Files already copied into existing user accounts are now ordinary user files.

Delete those through the Files UI if they are unwanted.

For an explicit server-side deletion, use Nextcloud's own file command rather than deleting the disk file directly:

```bash
sudo -u www-data \
  env NEXTCLOUD_CONFIG_DIR=/etc/nextcloud \
  php8.5 /var/www/nextcloud/occ files:delete \
  /USER_ID/files/EXACT_FILE_OR_FOLDER
```

The command asks for confirmation and understands Nextcloud shares/trash semantics.

## Optional destructive staging cleanup

By default Phase 3C does **not** empty trash or delete file-version history.

To permanently empty every user's trash bin:

```bash
sudo \
  LINETTY_PURGE_TRASH=yes \
  bash scripts/clean-staging-noise.sh
```

To permanently remove all stored file versions:

```bash
sudo \
  LINETTY_PURGE_VERSIONS=yes \
  bash scripts/clean-staging-noise.sh
```

Both at once:

```bash
sudo \
  LINETTY_PURGE_TRASH=yes \
  LINETTY_PURGE_VERSIONS=yes \
  bash scripts/clean-staging-noise.sh
```

Those two operations are intentionally opt-in because they are irreversible.

## Preview cleanup

Nextcloud provides `occ preview:cleanup`, but Phase 3C deliberately does not run it. Generated previews are useful on a photo service and would simply need to be regenerated as the family browses the library.

## Temp files

PHP's temporary directory is managed by the operating system. Nextcloud's upload chunks are application state and should be left to Nextcloud.

There is no benefit in periodically sweeping `/tmp` or `*/uploads` ourselves on this staging box.
