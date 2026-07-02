# ViMbAdmin — hardened Debian / Angie-minimal / PHP-FPM 8.5

A small, **fully-unprivileged**, defence-in-depth Docker image for the
modernised **[ViMbAdmin fork](https://github.com/eilandert/ViMbAdmin)** — the
web admin panel for **Postfix + Dovecot virtual mailboxes** (domains, mailboxes,
aliases, quotas, archiving, 2FA).

## Links

- 🚀 **Live demo:** <https://vimbadmin.myguard.nl> — try the panel before you pull
- 📦 **Image source / full README:** <https://github.com/myguard-labs/dockerized/tree/master/src/vimbadmin>
- 🔧 **App source (fork):** <https://github.com/eilandert/ViMbAdmin>
- 📖 **Write-up / guided tour:** <https://deb.myguard.nl/2026/06/vimbadmin-postfix-dovecot-mailbox-admin-panel/>

## Tags

| Tag | What |
|---|---|
| `latest`, `debian` | Debian trixie · Angie-minimal · PHP-FPM 8.5 (amd64) |

## Why this image

Most mailbox-admin images run a web server + PHP as root with a fat cap set.
This one doesn't run root **anywhere** and holds **zero Linux capabilities**.

### Security highlights

- **No root, anywhere.** PID 1, every Angie worker and the whole PHP-FPM tree
  run as the unprivileged `phpfpm` user (`user: "997:33"`).
- **Zero capabilities** — `cap_drop: [ALL]`, **no `cap_add`**. Verified at
  runtime: `CapEff = CapBnd = 0`. Angie binds a high port (**:8080**) so it
  needs no `CAP_NET_BIND_SERVICE`; nothing does runtime `setuid`/`chown`.
- **`no-new-privileges`** + **AppArmor** (`docker-default`).
- **Read-only root filesystem.** Only the data volumes + `/run` `/tmp`
  `/var/log/php-fpm` are writable; the code is immutable to the web/PHP user.
- **No baked secrets** — the `securitysalt` and the Snuffleupagus `secret_key`
  are generated on first boot, unique per deployment, never in an image layer.
- **Snuffleupagus** loaded with the app's audited `vimbadmin-strict` ruleset,
  on a **hardened PHP-FPM pool** (`open_basedir`, `expose_php` off,
  `HttpOnly`+`Secure`+`SameSite=Lax` cookies, `.php`-only execution).
- **Native positive-security edge gate** (in Angie): only allow-listed HTTP
  methods, the real route map, and the app's known argument names reach PHP —
  unknown method → 405, route → 404, arg → 403, scanner/empty UA → dropped.
- **Minimal surface / stripped:** `angie-minimal` (no modsecurity/lua/brotli),
  only the PHP extensions the app uses, no apt/composer/git at runtime, no
  docs/man/locales, every setuid/setgid bit removed.
- Resource limits (memory, pids, nofile) + a dependency-free healthcheck.

## Quick start

```sh
# Grab the compose file and CHANGE THE PASSWORDS first.
curl -fsSLO https://raw.githubusercontent.com/eilandert/dockerized/master/src/vimbadmin/docker-compose.yml
$EDITOR docker-compose.yml          # set MARIADB_* passwords
docker compose up -d
# Browse http://localhost:8080/  -> first-run super-admin setup.
# The username is an EMAIL address (you@yourdomain), not "admin".
```

Run it behind TLS in production (terminate at your edge proxy, forward the real
client IP). The container listens on **:8080** only.

## ⚠️ Mount ownership (because the container can't chown)

With `cap_drop: [ALL]` the container **cannot** change file ownership, so any
**writable** mount must already be owned by the runtime user **uid `997`
(`phpfpm`) : gid `33` (`www-data`)**:

- **Named volumes** (compose default) — nothing to do, they inherit it.
- **Host bind mounts** — pre-own once:
  ```sh
  sudo chown -R 997:33 /your/bind/dir
  ```
- **tmpfs** — set it in the mount options:
  ```yaml
  tmpfs:
    - /run:uid=997,gid=33,mode=0770
    - /tmp:uid=997,gid=33,mode=0770
  ```

A *Permission denied* on boot means a writable mount isn't owned `997:33`. The
fix is always the `chown` above — never add a capability back. (The container
prints these same instructions in its startup logs.)

## Wiring to Postfix + Dovecot

ViMbAdmin only maintains the SQL user database; Postfix and Dovecot read the
**same MariaDB** through their own SQL maps. Example `virtual_*` maps, Dovecot
`sql.conf` and the schema are in the repo's `EXAMPLES/`. Match ViMbAdmin's
password scheme to Dovecot's `default_pass_scheme` or logins fail.

Full deploy guide, archiving/quota sidecar, config editing, tunables and 2FA
reset: **see the [README](https://github.com/myguard-labs/dockerized/tree/master/src/vimbadmin).**
