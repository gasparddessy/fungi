# Refungi Child

Child theme for [refungi.be](https://refungi.be). It holds presentation only: CSS, template overrides copied from the parent, and small display tweaks.

`style.css` still has `Template: PARENT_THEME_SLUG`. That value is a TODO. WordPress needs the parent theme's directory name there before this theme can be activated. Confirm the folder under `wp-content/themes/` on the server. Do not guess, and do not commit the parent theme.

Put visual overrides in `assets/css/overrides.css`. The starter comment is there because the production hero still needs a PermaFungi check (image text and older media filenames are not edited by this file). Behaviour that must survive a theme switch belongs in `plugins/refungi-custom/`.

Deploy and activation steps are in the repository root README.
