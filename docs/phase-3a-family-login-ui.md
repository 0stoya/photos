# Phase 3A — family login and UI

## Boundary

This is a **staging UI phase**.

It intentionally does not:

- create backup jobs or backup timers;
- migrate storage;
- format or mount disks;
- create family users;
- enforce 2FA;
- disable core Nextcloud apps;
- patch Nextcloud core PHP, JavaScript or CSS.

The staging host remains disposable until the later 2 TB system is prepared.

## Goals

1. Present the instance as **Linetty Photos**, rather than generic Nextcloud.
2. Use a family-oriented login slogan.
3. Send authenticated users to Memories first.
4. Keep the implementation entirely within supported Nextcloud theming/configuration APIs.
5. Allow logo, header logo, favicon, login background and colours to be added without code changes.
6. Keep the changes resettable.

Nextcloud 35 ships the Theming app and supports configuring its name, slogan, URL, colours, logo, header logo, favicon and login background through `occ theming:config`.

The standard `defaultapp` system setting is used to prefer `memories`, with `files` as a fallback.

## Apply the text-only staging theme

```bash
cd /srv/photos
git checkout feat/phase3a-family-login-ui
git pull

sudo bash scripts/apply-staging-ui.sh
sudo bash scripts/accept-phase3a-ui.sh
```

The default theme text is:

```text
Name:    Linetty Photos
Slogan:  Our family photos, in one place.
URL:     https://photo.linetty.co.uk
Home:    Memories, with Files as fallback
```

## Optional logo / login assets

Theme images must be readable from a local server path.

Example:

```bash
sudo \
  LINETTY_LOGO=/path/to/linetty-logo.png \
  LINETTY_HEADER_LOGO=/path/to/linetty-header-logo.png \
  LINETTY_FAVICON=/path/to/favicon.ico \
  LINETTY_LOGIN_BACKGROUND=/path/to/family-background.jpg \
  bash scripts/apply-staging-ui.sh
```

Optional colours:

```bash
sudo \
  LINETTY_PRIMARY_COLOR='#334155' \
  LINETTY_BACKGROUND_COLOR='#0f172a' \
  bash scripts/apply-staging-ui.sh
```

No colour is imposed by default. This avoids inventing Linetty branding before the login design is reviewed visually.

## User theming

Per-user theming stays available by default.

To lock the instance to the Linetty theme:

```bash
sudo LINETTY_DISABLE_USER_THEMING=yes bash scripts/apply-staging-ui.sh
```

## Reset

```bash
sudo bash scripts/reset-staging-ui.sh
```

This resets the theme keys and the `defaultapp` override to Nextcloud defaults.

## Next step

After the text-only theme is accepted visually:

- add the Linetty logo;
- choose a login background or plain background;
- choose the primary colour;
- review which navigation apps should remain visible;
- create the first family accounts;
- configure admin 2FA;
- test the iPhone login and upload flow.

Backups remain out of scope on staging.
