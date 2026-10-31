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

Pushes to `main` that touch the child theme, the custom plugin, the workflow, or the deploy scripts run `.github/workflows/deploy.yml`. Pull requests run the checks only. They do not connect to the server. A manual run from the Actions tab (**Deploy custom code**, branch `main`) deploys again without a new commit. That is the button to use after the secrets are first saved.

The workflow fails in the preflight step, before any connection, when a required secret is missing. The log names the missing secrets.

### Secrets

Create **repository** secrets (not files in Git):

**Settings → Secrets and variables → Actions → New repository secret**

| Secret | Required | Value |
| --- | --- | --- |
| `SFTP_HOST` | Yes | Hostname only, no `https://` and no path |
| `SFTP_PORT` | No | `21` selects plain FTP. Any other value, and an omitted secret, stay on SSH. The default is **22** |
| `SFTP_USER` | Yes | cPanel user |
| `SFTP_KEY` | Preferred on port 22 | Private key of a deploy keypair. Full PEM or OpenSSH block, **no passphrase**. Ignored when `SFTP_PORT` is `21` |
| `SFTP_PASSWORD` | Required on port 21 | cPanel account password. On port 22 it is used only when `SFTP_KEY` is empty |
| `SFTP_REMOTE_THEME_PATH` | Yes | Must end with `wp-content/themes/refungi-child`. On port 21 this is relative to the FTP login root. On port 22 an absolute filesystem path is correct |
| `SFTP_REMOTE_PLUGIN_PATH` | No | Must end with `wp-content/plugins/refungi-custom` when set. Same path rule as the theme. If omitted, the plugin is not deployed |

### This site, while SSH is blocked

o2switch **Autorisation SSH** allowlists port 22. GitHub-hosted runners are not on that list, so SSH and SFTP time out. FTPS is not a workaround: o2switch uses the same allowlist for FTPS data connections, and a client can list directories and then stall on the upload. Plain FTP on port 21 is open. The password is not encrypted on the wire. Switch back to port 22 and `SFTP_KEY` if SSH from GitHub starts working.

Set these repository secrets for the FTP deploy. Do not put the password in Git, in the workflow, or in this file. Paste the cPanel account password into `SFTP_PASSWORD` in the GitHub UI.

| Secret | Value |
| --- | --- |
| `SFTP_HOST` | `crch2121.odns.fr` |
| `SFTP_PORT` | `21` |
| `SFTP_USER` | `crch2121` |
| `SFTP_PASSWORD` | The cPanel account password. It is not written down in this repository |
| `SFTP_KEY` | Leave empty |
| `SFTP_REMOTE_THEME_PATH` | `public_html/wp-content/themes/refungi-child` |
| `SFTP_REMOTE_PLUGIN_PATH` | `public_html/wp-content/plugins/refungi-custom` |

Port 21 paths are relative to the FTP login root. o2switch chroots that login to the account home, so `/home/crch2121/public_html/...` is not a directory the FTP session can open (`550 No such file or directory`). Do not put `/home/USER/` in `SFTP_REMOTE_THEME_PATH` or `SFTP_REMOTE_PLUGIN_PATH` for this port.

If a secret still has the SSH form `/home/crch2121/public_html/...`, the FTP job drops the `/home/crch2121/` prefix and syncs `public_html/...`. The value to store is the relative path.

The theme directory is already on the server. The plugin directory is created on the first deploy when `wp-content/plugins` already exists. The job does not create `wp-content`, `themes`, or `plugins`, and it does not upload WordPress.

### When port 22 is reachable

Gaspard or Chris enables SSH on the o2switch account and installs the matching **public** key in the account's authorized keys. Generate the key on a trusted machine, paste the private key into `SFTP_KEY`, set `SFTP_PORT` to `22` or leave it empty, and do not commit either file:

```bash
ssh-keygen -m PEM -t rsa -b 4096 -N "" -C "refungi-github-deploy" -f refungi-deploy
```

`refungi-deploy.pub` goes on the server. `refungi-deploy` is the secret. `.gitignore` ignores both names.

The first successful SSH deploy can create the `refungi-child` folder itself, but only when `wp-content/themes` already exists. The server-side check resolves the path and refuses the sync unless the real directory still ends with `wp-content/themes/refungi-child`.

Port 22 sees the real filesystem, so the absolute paths are the ones to store:

- `SFTP_REMOTE_THEME_PATH` = `/home/crch2121/public_html/wp-content/themes/refungi-child`
- `SFTP_REMOTE_PLUGIN_PATH` = `/home/crch2121/public_html/wp-content/plugins/refungi-custom`

### What the job syncs

- **Port 21** (`SFTP_PASSWORD`): plain FTP with `lftp`. Paths are relative to the FTP login root (`public_html/...`). `mirror --reverse --delete` runs only inside the validated theme directory, then inside the plugin directory when that secret is set. Files removed from Git are removed there. `bridge`, `bridge-child`, and the rest of `wp-content` are not mirror targets.
- **Port 22** keeps absolute filesystem paths such as `/home/crch2121/public_html/wp-content/themes/refungi-child`. The FTP chroot rewrite does not apply.
- **Port 22, key** (`SFTP_KEY`): [easingthemes/ssh-deploy](https://github.com/easingthemes/ssh-deploy) `v6.0.3`, rsync over SSH. Before rsync, a remote script checks the directory.
- **Port 22, password** (`SFTP_PASSWORD` and no key): the same rsync flags over SSH.
- `--delete` applies only inside the validated theme or plugin directory. It does not clean the rest of the account. `dangerous-clean-slate` is not set.
- On SSH, owner and group are not preserved. New files are `644` and new directories `755`. On FTP, the host umask applies (cPanel usually uses the same modes).
- A remote symlink is refused. Paths that end in `bridge`, `bridge-child`, `wp-content`, `public_html`, or anything other than the two Refungi directories are rejected before a connection is opened.

Local check, with no server and no secrets:

```bash
bash .github/scripts/run-tests.sh
```
