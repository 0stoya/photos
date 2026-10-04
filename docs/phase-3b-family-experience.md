# Phase 3B — family accounts, 2FA and sharing

## Boundary

This is still a staging phase.

It intentionally does **not**:

- create backup automation;
- migrate storage;
- upload the full iPhone library;
- enable face recognition or other heavy indexing extras;
- enforce 2FA before the administrator has configured TOTP and backup codes.

## What this phase prepares

- Nextcloud Photos and Memories enabled;
- the `family` group;
- TOTP and backup-code providers;
- Memories-first login;
- public link sharing with password protection enforced;
- secure family-user creation without passwords in shell history;
- an explicit second step to enforce 2FA for the `admin` group;
- optional removal of Dashboard / Weather / First-run wizard clutter;
- a small iPhone upload and public-sharing acceptance flow.

Memories uses the official Nextcloud iOS app for automatic photo/video uploads. New uploads are indexed automatically by Memories through Nextcloud hooks.

The Photos app remains enabled because Memories recommends it for album support.

## 1. Prepare the family experience

```bash
cd /srv/photos
git checkout feat/phase3b-family-experience
git pull

sudo bash scripts/prepare-family-experience.sh
sudo bash scripts/accept-phase3b-family.sh
```

Phase 3B enforces passwords for public share links:

```text
core.shareapi_allow_links = yes
core.shareapi_enforce_links_password = yes
```

Download/upload permissions remain a choice on each individual share.

## 2. Create family accounts

User IDs should be treated as permanent login IDs. Keep them short and boring; use the display name for the friendly name.

Example:

```bash
sudo \
  LINETTY_UID=chris \
  LINETTY_DISPLAY_NAME='Chris' \
  bash scripts/create-family-user.sh
```

The script prompts for the password twice without echoing it.

Optional email:

```bash
sudo \
  LINETTY_UID=alex \
  LINETTY_DISPLAY_NAME='Alex' \
  LINETTY_EMAIL='alex@example.com' \
  bash scripts/create-family-user.sh
```

Do not add ordinary family members to the admin group.

To create another administrator deliberately:

```bash
sudo \
  LINETTY_UID=second-admin \
  LINETTY_DISPLAY_NAME='Second Admin' \
  LINETTY_ADMIN=yes \
  bash scripts/create-family-user.sh
```

## 3. Configure administrator TOTP before enforcement

Log in to `https://photo.linetty.co.uk` with the existing administrator account.

Go to:

```text
Settings → Personal → Security
```

Then:

1. enable TOTP / authenticator-app two-factor authentication;
2. scan the QR code with the chosen authenticator;
3. verify one generated TOTP code;
4. generate backup codes;
5. store at least one tested backup code somewhere outside this server.

Check the server-side state if useful:

```bash
sudo -u www-data \
  env NEXTCLOUD_CONFIG_DIR=/etc/nextcloud \
  php8.5 /var/www/nextcloud/occ twofactorauth:state admin
```

Only after TOTP and backup codes are configured should enforcement be enabled:

```bash
sudo \
  LINETTY_CONFIRM_ADMIN_2FA=yes \
  bash scripts/enforce-admin-2fa.sh
```

This enforces 2FA for members of Nextcloud's `admin` group, not for normal family accounts.

## 4. Optional photo-focused navigation trim

The required Phase 3B setup does not disable apps automatically.

After reviewing the UI, the following optional command removes common staging clutter while preserving Files, Photos and Memories:

```bash
sudo \
  LINETTY_CONFIRM_NAV_TRIM=yes \
  bash scripts/trim-photo-navigation.sh
```

It disables, when present:

- Dashboard;
- Weather Status;
- First-run wizard.

## 5. iPhone staging test

Do **not** enable the full Camera Roll backup yet on this 120 GB staging machine.

On the iPhone:

1. install the official Nextcloud iOS app;
2. add server `https://photo.linetty.co.uk`;
3. sign in with a normal family account;
4. allow Photos access when iOS asks;
5. first upload a deliberately small test selection: roughly 10–20 photos plus one short video;
6. open Memories in Safari or the web app and confirm the files appear on the timeline;
7. confirm at least one HEIC image and one iPhone video can be previewed.

Only enable broad automatic upload after the later 2 TB migration.

## 6. Sharing acceptance

Create a small test album/folder and create a public share link.

Because password enforcement is enabled, Nextcloud must require a password for that link.

Test two useful share modes:

### Family download link

- public link;
- password set;
- read-only;
- downloads allowed;
- optional expiry.

### Family contribution link

For a folder where relatives should send their own photos:

- public link;
- password set;
- File drop / upload-only, or upload+edit if intentionally desired;
- optional expiry.

Nextcloud supports password-protected public links, read/download links, upload/edit links, File Drop, expiry and Hide download. Remember that Hide download is a UI restriction rather than DRM.

## Acceptance target

Required automated Phase 3B acceptance:

```text
photos enabled
memories enabled
twofactor_totp enabled
twofactor_backupcodes enabled
family group exists
Memories remains first app
public share links require passwords
public HTTPS healthy
no staging backup automation
```

Family user creation, TOTP enrollment, iPhone uploads and public-share behavior are operator/browser acceptance because they require personal credentials or device interaction.
