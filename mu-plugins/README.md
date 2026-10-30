# Refungi custom PHP

Use the **child theme** (`themes/refungi-child/`) for presentation:

- CSS overrides in `assets/css/custom.css`
- small template changes (copy a parent template into the child and edit the copy)
- hooks that only affect markup or assets

Use **this must-use plugin** for behavior that should survive a theme switch:

- WooCommerce checkout, cart, price, tax, email, or order logic
- redirects, webhooks, and other site rules

WordPress only auto-loads PHP files sitting **directly** in `wp-content/mu-plugins/`, not files in a subfolder. When there is something to ship, copy `refungi-custom.php` to:

```text
<docroot>/wp-content/mu-plugins/refungi-custom.php
```

Do that by hand or with a separate step. `.github/workflows/deploy-theme.yml` uploads the child theme only.

A must-use plugin cannot be switched off from the Plugins screen. While this file has no hooks, that is harmless. Prefer a normal plugin under `wp-content/plugins/refungi-custom/` later if the change must be easy to deactivate. Keep LayerSlider, WPBakery, WPML, WooCommerce, and the parent theme out of Git.
