# Refungi — code custom

Dépôt Git du code custom de [refungi.be](https://refungi.be) (ex-PermaFungi). Il ne contient pas le cœur WordPress, ni les plugins commerciaux, ni les médias.

**Avant d’activer le thème :** dans `themes/refungi-child/style.css`, Gaspard ou Chris remplace `Template: PARENT_THEME_SLUG` par le **nom du dossier** du thème parent. Le HTML public du 2026-10-30 montre les classes `wp-theme-bridge` et `wp-child-theme-bridge-child`, et les chemins `/wp-content/themes/bridge/` et `/wp-content/themes/bridge-child/`. À confirmer sur le serveur avant de changer cette ligne. Ne pas écraser le child déjà en production (`bridge-child`) : ce dépôt livre un nouveau dossier, `refungi-child`. Déployer d’abord sur un staging (JetBackup ou sous-domaine).

Le reste de ce fichier est en anglais, pour Claude Code, Cursor et Codex.

## Layout

Custom code only. This repository is not a WordPress root.

| In Git | On the server (confirm the document root in cPanel) |
| --- | --- |
| `themes/refungi-child/` | `<docroot>/wp-content/themes/refungi-child/` |
| `mu-plugins/refungi-custom.php` | `<docroot>/wp-content/mu-plugins/refungi-custom.php` (copy by hand; the SFTP workflow does not upload it) |

`themes/refungi-child/` is the child theme agents should edit. `mu-plugins/` is an empty stub for later WooCommerce behavior. See [mu-plugins/README.md](mu-plugins/README.md).

## What belongs in Git

- This child theme: CSS, small template overrides, presentation PHP.
- Small custom plugins / the mu-plugin stub, once they do something.
- This README and `.github/workflows/deploy-theme.yml`.

## What stays on the server

Do not commit these, and do not edit them in Git:

- WordPress core (`wp-admin`, `wp-includes`, root PHP files). The public site reports WordPress 6.8.2.
- `wp-config.php`, salts, and database credentials.
- `wp-content/uploads/` (media, including PermaFungi-era files).
- Commercial and third-party plugins. The public homepage reports LayerSlider 6.7.6, WPBakery Page Builder 8.7.2, WPML 4.8.5, and WooCommerce 10.6.2. Leave those update paths on the host.
- The parent theme. It is not in this repo. Public HTML points at a `bridge` directory (Qode, theme version class `qode-theme-ver-16.8`) and an already active child directory `bridge-child`. Confirm both names on disk before changing `PARENT_THEME_SLUG`.
- Cache, JetBackup archives, and anything under `wp-content/cache/`.

`.gitignore` also ignores `.env`, keys, `node_modules/`, `vendor/`, SQL dumps, and a full WordPress tree if one is copied into the repo by mistake.

## How to work in this repo

Clone `https://github.com/gasparddessy/fungi` and open that folder in Claude Code, Cursor, or Codex.

- Edit `themes/refungi-child/assets/css/custom.css` for visual overrides. The production hero still carries PermaFungi-era assets; notes are in that file.
- Edit `themes/refungi-child/functions.php` for asset loading and presentation hooks.
- To change a parent template, copy that file from the parent theme **on the server** into `themes/refungi-child/` (keep the same relative path) and edit the copy. Do not vendor the parent theme into Git.
- WooCommerce rules that must survive a theme switch go in `mu-plugins/refungi-custom.php`, not in the theme.
- Open a pull request to `main`. Do not commit passwords, `wp-config.php`, or plugin zips.

There is no local WordPress in this repository. Check PHP with `php -l` on files you change. Confirm CSS on staging, because the live homepage is served from `wp-content/cache/minify/`.

## Staging before production

Do not activate this child on https://refungi.be for the first test.

1. In o2switch cPanel (user `crch2121`), use JetBackup to restore a copy of the site onto a subdomain, or clone the site to a subdomain you already use for staging.
2. Deploy `themes/refungi-child/` to that copy only.
3. Replace `PARENT_THEME_SLUG`, then activate **Refungi Child** in wp-admin on the staging site.
4. Check the homepage, a product, the cart, and the French, Dutch, and English WPML URLs (`/`, `/nl/`, `/en/`).
5. Purge the minify / page cache. The public HTML is currently concatenated from `wp-content/cache/minify/`.
6. Repeat the deploy against production only after that check.

## Deploy to o2switch

cPanel user: `crch2121`. The SSH/SFTP host is often `obsidienne.o2switch.net`. Confirm the hostname, the document root, and that SSH is enabled in the cPanel welcome screen. No password belongs in this repository.

### A. SSH and git pull

Use this when the account has SSH and `git`. Keep the clone **outside** the document root. A read-only GitHub deploy key can live in `~/.ssh` on the server; do not commit it.

```bash
mkdir -p ~/repos
cd ~/repos
git clone git@github.com:gasparddessy/fungi.git
cd fungi
git pull --ff-only origin main

# Confirm DOCROOT in cPanel → Domains before running rsync.
DOCROOT=~/public_html
rsync -a themes/refungi-child/ "$DOCROOT/wp-content/themes/refungi-child/"
```

`rsync -a` does not delete files that exist only on the server, and it does not touch `wp-content/themes/bridge-child/`. Add `--delete` later only if you intend this Git tree to be the full contents of `refungi-child`.

If `git` or SSH is not available on the plan, use the SFTP workflow below.

### B. GitHub Action (SFTP)

Workflow: [`.github/workflows/deploy-theme.yml`](.github/workflows/deploy-theme.yml).

- It does **not** run on push or on pull requests. CI on this PR will not fail because secrets are missing.
- Run it by hand: Actions → “Deploy child theme (manual SFTP)” → Run workflow.
- **Upload files** defaults to off (dry run). Turn it on only when the remote path is correct.
- It uploads `themes/refungi-child/` and does not delete extra files on the server. It does not upload `mu-plugins/`.

Create these repository secrets (Settings → Secrets and variables → Actions). Values are not stored in Git:

| Secret | Value |
| --- | --- |
| `SFTP_HOST` | SSH/SFTP host, often `obsidienne.o2switch.net` |
| `SFTP_USER` | `crch2121` |
| `SFTP_PASS` | The account SSH/SFTP password |
| `SFTP_REMOTE_PATH` | Absolute path of the **new** theme directory. No spaces or quotes. Example shape: `/home/crch2121/<document-root>/wp-content/themes/refungi-child` |

The workflow uses SFTP on port 22. If cPanel shows another SSH port, change `SFTP_PORT` in the workflow. The first connection accepts the server host key (`sftp:auto-confirm`). Runners are ephemeral, so this happens again on the next run.

## Activate the child theme

WordPress will treat the theme as broken until `Template` matches a real parent directory.

1. Set `Template` in `themes/refungi-child/style.css` (see the TODO). Deploy again so the server has that header.
2. Confirm the parent theme’s folder is installed next to it under `wp-content/themes/`.
3. In wp-admin (the site is `fr-FR`): **Apparence → Thèmes → Refungi Child → Activer**.
4. If WordPress reports a missing parent, the slug does not match the directory name. Fix the header. Do not rename `bridge-child` to force it.
5. Purge the minify cache and reload the homepage.

Activating Refungi Child switches the live theme away from the current `bridge-child`. Do that on staging first. Customizations that exist only inside `bridge-child` on the server are not in this repo; copy across the pieces you still need, file by file.

## Theme vs plugin

| Change | Where |
| --- | --- |
| CSS, fonts, spacing, hero presentation | `themes/refungi-child/assets/css/custom.css` |
| Copied templates and presentation hooks | `themes/refungi-child/` |
| Checkout, prices, emails, other WooCommerce rules | `mu-plugins/refungi-custom.php`, then copy that file to `wp-content/mu-plugins/` |
| Licensed plugins and the parent theme | On the server only. Update them from wp-admin. |
