# Refungi Child

Child theme for [refungi.be](https://refungi.be). It holds presentation only: CSS, template overrides copied from the parent, and small display tweaks.

`Template` is `bridge` (the Qode Bridge directory `wp-content/themes/bridge`). This theme's own folder is `refungi-child`. Do not deploy it over `bridge` or `bridge-child`, and do not commit the parent theme.

Bridge's `style.css` is a placeholder. `functions.php` loads `css/stylesheet.min.css` from the parent, then this theme's stylesheet, then `assets/css/overrides.css`. The starter comment in the overrides file is there because the production hero still needs a PermaFungi check (image text and older media filenames are not edited by this file). Behaviour that must survive a theme switch belongs in `plugins/refungi-custom/`.

Deploy and activation steps are in the repository root README.
