# Outlook 365 skin for Roundcube

A Microsoft Outlook-on-the-web (Office 365 / Fluent UI) look-alike skin for
Roundcube **1.6+ / 1.7.x**. It **extends** the stock `elastic` skin (inheriting
all of Elastic's JavaScript, icons and `deps/`), but ships its own fully
recoloured stylesheet plus a real top app bar — it is not a thin tint layer.

## How it's built

| File | Purpose |
|------|---------|
| `meta.json` | `"extends": "elastic"` + Fluent `theme-color` |
| `templates/includes/layout.html` | overrides Elastic's layout include to (a) link the skin's own `styles/styles.css` and (b) inject a real `<header id="o365-appbar">` (blue command band + search) above the flex layout |
| `styles/styles.css` | Elastic's **compiled** `styles.min.css` with every brand colour rewritten to the Fluent palette (`#37beff`→`#0f6cbd`, dark task rail → light, etc.), followed by an override block that builds the Outlook chrome: light task rail with dark text, filled-blue Compose, blue unread rows + selection bar, rounded search, Fluent flyouts/login card, Segoe UI |
| `styles/print.css`, `styles/embed.css` | recoloured Elastic print + editor stylesheets |
| `images/logo.svg` | Outlook wordmark |

Everything else (`ui.js`, `deps/`, all other templates) resolves from the parent
Elastic skin at runtime.

## Regenerating the stylesheet

The base is produced by recolouring Elastic's compiled CSS (no LESS toolchain
required):

```sh
EL=skins/elastic/styles
sed -e 's/#37beff/#0f6cbd/g' -e 's/#00acff/#0f6cbd/g' \
    -e 's/#2f3a3f/#f3f2f1/g' -e 's/#f4f4f4/#faf9f8/g' \
    $EL/styles.min.css > base.css
cat base.css overrides.css > styles/styles.css   # overrides.css = the chrome block
```

## Install

Drop into `skins/outlook365/`, then `$config['skin'] = 'outlook365';` or let
users pick it in **Settings → Preferences → User Interface**. Requires the
`elastic` skin (shipped with core Roundcube). Pure CSS + one template, no PHP —
safe under the strict Snuffleupagus rulebook.

## Notes

* The app-bar search box is decorative (the functional search is Elastic's, in
  the list pane).
* Dark-mode accents are recoloured along with the light theme.
