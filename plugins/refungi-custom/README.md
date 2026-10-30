# Refungi Custom

Empty plugin stub for [refungi.be](https://refungi.be). It is safe to deploy and leave inactive. There is no WooCommerce logic yet.

## Theme or plugin?

Use **Refungi Child** (`themes/refungi-child/`) when the change is presentation:

- CSS in `assets/css/overrides.css`
- A parent template copied into the child theme and then edited
- Image sizes, fonts, or other display tweaks tied to the active theme

Use **this plugin** when the change is behaviour that should survive a theme switch:

- Checkout, cart, email, or product-data rules (later; do not add them until they are specified)
- Integrations with forms, payments, or other sites
- Admin tools and cron that are not visual

Do not put secrets, WordPress core, uploads, or commercial plugins in either place. If a change can be done with the page builder or Customizer on the server, it does not need a commit here.
