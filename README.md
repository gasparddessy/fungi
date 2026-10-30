# Refungi

Git source of truth for **custom code** on the WooCommerce site [https://refungi.be](https://refungi.be) (ex-PermaFungi).

WordPress itself, the database, media, and commercial plugins stay on the o2switch server. This repository tracks the Refungi child theme and a small custom plugin, and it deploys those two directories when `main` changes.

## What belongs in Git

| Path | Purpose |
| --- | --- |
| `themes/refungi-child/` | Presentation: CSS, copied parent templates, small display PHP |
| `plugins/refungi-custom/` | Behaviour that should survive a theme switch. Empty for now |
| `.github/workflows/deploy.yml` | Deploy of those two folders only |
| `README.md`, `.gitignore` | How this repo is operated |

The child theme and custom plugin are GPL-2.0-or-later, as WordPress derivatives are.

## What stays on the server

Do not commit any of this:

- WordPress core (`wp-admin`, `wp-includes`, root `wp-*.php`)
- `wp-config.php` and any other secret or environment file
- `wp-content/uploads/` and other media
- The database, cache, and backup archives
- Commercial or third-party plugins and themes, including LayerSlider, WPBakery, and WPML
- The parent theme. It may be commercial or custom. It does not go in Git
- The child theme that is already active in production, until someone reviews it and copies the pieces this site still needs

Page content (including the homepage hero) is stored by the page builder and in uploads. A CSS commit does not edit that copy. The starter note in `themes/refungi-child/assets/css/overrides.css` is there because the production hero still says PERMAFUNGI and should be checked on the live page.

## Layout

```text
themes/refungi-child/          child theme deployed to wp-content/themes/refungi-child
plugins/refungi-custom/        optional plugin deployed to wp-content/plugins/refungi-custom
.github/workflows/deploy.yml   GitHub Actions deploy
.github/scripts/               path guards used by the workflow and by local tests
```

Use the child theme for CSS and templates. Use the plugin for checkout, emails, product data, and other behaviour. See `plugins/refungi-custom/README.md`. There is no WooCommerce logic in the plugin yet.

## Claude Code, Cursor, and Grok Bot

These tools work on this repository the same way a person does:

1. Clone `gasparddessy/fungi` and branch from `main`.
2. Change only `themes/refungi-child/` and `plugins/refungi-custom/`, plus the docs or deploy guards when the task is about those.
3. Open a pull request. Merging to `main` is what deploys.
4. Treat Git as the source of truth. Do not edit production over SFTP and leave the repo behind.

They must not commit credentials, WordPress core, uploads, `wp-config.php`, commercial plugins, or the Bridge parent theme. Secrets are typed into GitHub by Gaspard or Chris (Settings → Secrets and variables → Actions). They are not written into files, pull requests, or chat.

## Parent theme

`themes/refungi-child/style.css` contains:

```text
Template: bridge
```

`bridge` is the parent directory (`wp-content/themes/bridge`), confirmed from the live homepage body class `wp-theme-bridge`. The child theme that is active today is `bridge-child`. This repository's theme folder is `refungi-child`. Deploying it does not replace `bridge` or `bridge-child`.

Bridge's own `style.css` is a placeholder. The visual CSS is `wp-content/themes/bridge/css/stylesheet.min.css`. The child `functions.php` enqueues that parent file, then `themes/refungi-child/style.css`, then `assets/css/overrides.css`.

Do not commit the Bridge parent. If `bridge-child` has templates or PHP you still need, copy them into `themes/refungi-child/` before activating Refungi Child. This theme does not import that code.

## Activate the child theme after deploy

Take a backup, and look at a staging copy first if you have one, before activating on production.

1. Confirm the GitHub deploy for `main` is green and the folder `wp-content/themes/refungi-child` is on the server. `wp-content/themes/bridge` must still be there too.
2. In wp-admin, go to **Appearance → Themes**.
3. If Refungi Child says the parent theme is missing, stop. `Template` must stay `bridge`, and the Bridge folder must remain installed.
4. Activate **Refungi Child**. The previous theme files stay on disk. You can switch back from the same screen.
5. Check the homepage, a shop page, and each language the site serves.
6. Purge the site cache. The public homepage is served with minified CSS from `wp-content/cache/`, so a stylesheet deploy can look unchanged until that cache is cleared.
7. Optionally activate **Plugins → Refungi Custom**. It loads no hooks yet.

## Staging with JetBackup or a subdomain

Take a restorable copy before the first activation on production.

- In the o2switch cPanel account, open **JetBackup** and create a full backup (files plus database) so a theme switch can be rolled back.
- Prefer a subdomain clone for the first activation: create the subdomain, restore or copy the site into that document root, and activate Refungi Child there first.
- A staging path is valid for this workflow when it still ends with `wp-content/themes/refungi-child` (for example `public_html/staging/wp-content/themes/refungi-child`). The job syncs exactly the path in the secret. Point `SFTP_REMOTE_THEME_PATH` at the clone, not at the live theme, while you are testing.
- Production keeps its current theme until someone clicks Activate in wp-admin. Uploading the folder does not switch the theme.

## Deploy

Pushes to `main` that touch `themes/refungi-child/**` or `plugins/refungi-custom/**` run `.github/workflows/deploy.yml`. Pull requests run the checks only. They do not connect to the server. A manual run from the Actions tab (**Deploy custom code**, branch `main`) deploys again without a new commit. That is the button to use after the secrets are first saved.

The workflow fails in the preflight step, before any connection, when a required secret is missing. The log names the missing secrets.

### Secrets

Create **repository** secrets (not files in Git):

**Settings → Secrets and variables → Actions → New repository secret**

| Secret | Required | Value |
| --- | --- | --- |
| `SFTP_HOST` | Yes | SSH hostname only, no `https://` and no path. Example: `obsidienne.o2switch.net` |
| `SFTP_PORT` | No | TCP port. Defaults to **22** when the secret is omitted |
| `SFTP_USER` | Yes | cPanel user. Example: `crch2121` |
| `SFTP_KEY` | Preferred | Private key of a deploy keypair. Full PEM or OpenSSH block, **no passphrase** |
| `SFTP_PASSWORD` | Alternate | Account password, used only when `SFTP_KEY` is empty. Ignored when a key is set |
| `SFTP_REMOTE_THEME_PATH` | Yes | Must end with `wp-content/themes/refungi-child`. Example: `public_html/wp-content/themes/refungi-child` |
| `SFTP_REMOTE_PLUGIN_PATH` | No | Must end with `wp-content/plugins/refungi-custom` when set. If omitted, the plugin is not deployed |

Gaspard or Chris needs to enable SSH or SFTP on the o2switch account (port 22) and install the matching **public** key in the account's authorized keys. Generate the key on a trusted machine, paste the private key into `SFTP_KEY`, and do not commit either file:

```bash
ssh-keygen -m PEM -t rsa -b 4096 -N "" -C "refungi-github-deploy" -f refungi-deploy
```

`refungi-deploy.pub` goes on the server. `refungi-deploy` is the secret. `.gitignore` ignores both names.

Fill `SFTP_REMOTE_THEME_PATH` after you know where the site's `wp-content/themes` directory is. The first successful deploy can create the `refungi-child` folder itself, but only when `wp-content/themes` already exists. It will not create `wp-content`, and it will not upload WordPress.

An absolute path is fine too (`/home/crch2121/public_html/wp-content/themes/refungi-child`) if that is what the SSH session sees. The server-side check resolves the path and refuses the sync unless the real directory still ends with `wp-content/themes/refungi-child`.

### What the job syncs

- **Key** (`SFTP_KEY`): [easingthemes/ssh-deploy](https://github.com/easingthemes/ssh-deploy) `v6.0.3`, rsync over SSH. Before rsync, a remote script checks the directory.
- **Password** (`SFTP_PASSWORD` only): the same rsync flags over SSH on `SFTP_PORT`. FTP-Deploy-Action v4 is not used, because it no longer speaks SFTP and this host is port 22.
- `--delete` applies only inside the validated theme or plugin directory, so files removed from Git are removed there on the next deploy. It does not clean the rest of the account. `dangerous-clean-slate` is not set.
- Owner and group are not preserved, which avoids permission errors on shared hosting. New files are `644` and new directories `755`.
- Paths that end in `bridge`, `bridge-child`, `wp-content`, `public_html`, or anything other than the two Refungi directories are rejected.

Local check, with no server and no secrets:

```bash
bash .github/scripts/run-tests.sh
```
