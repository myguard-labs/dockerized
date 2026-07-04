# Gmail skin for Roundcube

A Gmail (Material / Google Sans era) look-alike skin for Roundcube
**1.6+ / 1.7.x**. It **extends** the stock `elastic` skin, inheriting every
template, icon set and JavaScript behaviour from Elastic and only overriding:

| File | Purpose |
|------|---------|
| `meta.json` | `"extends": "elastic"` + white `theme-color` |
| `templates/includes/layout.html` | adds one extra `<link>` to `styles/theme.css` after Elastic's own CSS so the override wins the cascade |
| `styles/theme.css` | the entire reskin: Google Sans/Roboto font, white top bar, tonal "Compose" pill, rounded label rail, Gmail message rows (bold-black unread, hover elevation), tinted search pill, Material flyouts, dark-mode harmonisation |
| `images/logo.svg` | Gmail wordmark for the login + task menu |

Everything else (`styles/styles.css`, `print.css`, `ui.js`, `deps/`, all the
other templates) resolves from the parent Elastic skin at runtime — nothing is
duplicated, so the skin keeps working across Roundcube point releases.

## Install

Drop this directory into Roundcube's `skins/` as `skins/gmail/`, then set it as
the default in `config/config.inc.php`:

```php
$config['skin'] = 'gmail';
```

or let users pick it from **Settings → Preferences → User Interface**.

## Notes

* Requires the `elastic` skin (shipped with core Roundcube).
* Dark mode follows Elastic's `.dark-mode` toggle automatically.
* Pure CSS reskin of the Elastic DOM — no PHP, no template logic changes, so it
  is safe under the strict Snuffleupagus rulebook.
