# roundcube-rule-exclusions-plugin

An [OWASP CRS](https://coreruleset.org/) plugin that remedies the false
positives a default **Roundcube** webmail install triggers against the
Core Rule Set — the webmail equivalent of the
[`wordpress-rule-exclusions-plugin`](https://github.com/coreruleset/wordpress-rule-exclusions-plugin).

It is meant for the **reverse proxy that fronts Roundcube and runs
ModSecurity + CRS** (e.g. the Angie/ModSecurity edge in front of the
`eilandert/roundcube` container). The container itself runs
`angie-minimal` with no WAF — the relevant protection layer is the proxy.

## Rule ID block

`9,508,000 – 9,508,999` (WordPress exclusions use `9,507,xxx`).

## What it excludes

All exclusions are scoped by Roundcube's `_task` / `_action` arguments and
target only the specific fields that legitimately carry rich content, so
the rest of every request is still inspected:

| Area | Why it false-positives | Scope |
|------|------------------------|-------|
| Login | `_user` / `_pass` / `_token` high-entropy | `_task=login` |
| CSRF token | base64-ish, trips SQLi/encoding | `ARGS:_token` |
| Compose/send | HTML body + headers contain `<script>`, SQL text | `_task=mail` `_action=send\|compose\|save.draft` |
| Mail/contact search | search strings contain `UNION`, `OR 1=1` | `_action=search\|list` |
| vCard import | multipart quoted strings | `_task=addressbook` `_action=import` |
| Identity signature | HTML signature | `ARGS:_signature` |
| managesieve | raw Sieve DSL looks like injection | `_action=plugin.managesieve*` |
| Elastic AJAX | large JSON/multipart XHR bodies | `X-Requested-With: XMLHttpRequest` |

## Install (CRS plugin folder)

Copy the two files into your CRS `plugins/` directory and reload:

```bash
cp plugins/roundcube-rule-exclusions-*.conf /etc/modsecurity/crs/plugins/
# or wherever your CRS plugins live; then reload the proxy
```

CRS loads `*-config.conf` then `*-before.conf` automatically from the
plugins folder. Disable without removing the files:

```
SecAction "id:9508001,phase:1,nolog,pass,setvar:tx.roundcube-rule-exclusions-plugin_enabled=0"
```

## Include from Angie (example)

On a ModSecurity-enabled Angie reverse proxy, the CRS bundle already
`Include`s its `plugins/*.conf`. If you load CRS by hand, the snippet is:

```nginx
# inside the Roundcube server { } on the WAF proxy
modsecurity on;
modsecurity_rules_file /etc/modsecurity/main.conf;   # which Includes:
#   Include /etc/modsecurity/crs/crs-setup.conf
#   Include /etc/modsecurity/crs/plugins/*-config.conf
#   Include /etc/modsecurity/crs/plugins/*-before.conf
#   Include /etc/modsecurity/crs/rules/*.conf
#   Include /etc/modsecurity/crs/plugins/*-after.conf
```

## Tuning

If you enable the **enigma** (PGP) plugin or a shell-based `password`
driver, you may need to relax `attack-rce` further on `_task=settings`;
those are intentionally left strict here because the default container
does not ship them.
