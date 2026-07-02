# Roundcube — hardened Docker image (Debian / Angie-minimal / PHP-FPM 8.5)

A small, **fully-unprivileged**, defence-in-depth Docker image for
[Roundcube](https://roundcube.net/) webmail. PID 1 and the whole PHP/web tree
run as a non-root user (uid 10001), the container holds **zero Linux
capabilities**, the root filesystem is **read-only**, and an Angie WAF sits in
front of PHP.

You bring an IMAP/SMTP server (your own mail host) and a database; the image
brings the webmail front-end. The bundled `docker-compose.yml` includes a
hardened MariaDB so you can be running in two commands.

**Just want it running?** Jump to [Quick start](#quick-start). Curious *how* it's
locked down? See [Security & hardening](#security--hardening). Want to know which
plugins/skins ship? See [Bundled plugins & skins](#bundled-plugins--skins).

## Links

- **Image source / this repo:** <https://github.com/myguard-labs/dockerized/tree/master/src/roundcube>
- **Docker Hub:** <https://hub.docker.com/r/eilandert/roundcube>
- **App source (upstream):** <https://github.com/roundcube/roundcubemail>
- **Write-up / guided tour:** <https://deb.myguard.nl/2026/06/hardened-roundcube-docker-image/>
- **deb.myguard.nl:** <https://deb.myguard.nl/>

## What's in the image

| | |
|---|---|
| Base | `eilandert/debian-base:stable` (trixie + deb.myguard.nl repo + hardening) |
| Web | `angie-minimal` — single self-contained `angie.conf` with a WAF gate in front of PHP |
| Runtime | `php8.5-fpm`, minimal extension set, **Snuffleupagus** + a strict source-audited Roundcube ruleset |
| Cache | tuned **OPcache** + **APCu** |
| DB | external **MariaDB/MySQL or PostgreSQL** (mandatory; no SQLite) |
| Init | **rootless s6-overlay** PID1 — [`init-bootstrap.sh`](s6-scripts/init-bootstrap.sh) oneshot (setup + DB schema) then php-fpm/angie/fpm-watch longruns ([`s6-rc.d/`](s6-rc.d/)) |
| Config | one file each: [`angie.conf`](angie.conf) (incl. loopback healthz), [`phpfpm.conf`](phpfpm.conf) |

## Security & hardening

Defence in depth: the **runtime** is hardened by Snuffleupagus + the FPM pool,
the **edge** by an Angie WAF, and the **container** by the measures below.

### Container / image

- **Runs fully unprivileged — no root, anywhere.** PID 1 is **rootless
  s6-overlay** (`S6_READ_ONLY_ROOT=1`); it, the Angie and PHP-FPM masters, every
  worker — all of it runs as the unprivileged `roundcube` user (`USER
  roundcube:roundcube` in the image; `user: "10001:10001"` in compose). No root
  process at any point. s6 supervises php-fpm + angie, so a killed master is
  reaped and restarted instead of leaving a silent outage.
- **Zero Linux capabilities** — `cap_drop: [ALL]` with **no `cap_add`**. Angie
  binds a high port (**:8080**, no `CAP_NET_BIND_SERVICE`); nothing does runtime
  `setuid`/`chown` (the masters are already unprivileged; writable mounts are
  pre-owned — see *Mount ownership*).
- **`no-new-privileges`** + **AppArmor** (`apparmor=docker-default`).
- **Read-only root filesystem** (`read_only: true`). Only the config volume and
  the `/tmp` tmpfs are writable; Angie's pid/sockets/temp + the FPM error log
  are redirected there so the rest of the rootfs stays immutable.
- **Codebase read-only to the web/PHP user** — owned `roundcube:roundcube`
  `0440`/`0550`. The web/PHP processes cannot modify a line of code.
- **No baked secrets** — the Roundcube `des_key` and the Snuffleupagus
  `secret_key` are each generated on first boot, unique per deployment, persisted
  on the config volume and never in an image layer (override with a Docker secret
  or `ROUNDCUBEMAIL_DES_KEY` / `ROUNDCUBEMAIL_SP_SECRET`).
- **Every setuid/setgid bit stripped** at build time.

### Runtime (PHP)

- **Snuffleupagus** with a strict, source-audited Roundcube rulebook (virtual
  patching, dangerous-function kills, uploaded-file no-exec, secure cookies).
- **Hardened PHP-FPM pool** (`php_admin_*`, not overridable by userland):
  `open_basedir` jail, `expose_php` off, `allow_url_fopen`/`allow_url_include`
  off, a wide `disable_functions` (exec/system/proc_open/passthru/… gone), and
  `Secure`+`HttpOnly`+`SameSite=Strict` session cookies with 64-char IDs.

### Edge (Angie WAF)

- **gzip off** — closes the [BREACH](https://deb.myguard.nl/2026/05/breach-attack-explained-prevention/)
  side-channel on CSRF-token-bearing HTML.
- **`real_ip`** from the trusted private proxy ranges (reads `X-Forwarded-For`)
  so the throttle + RC's failed-login tracking see the real client.
- **Scanner / empty-UA gate**  `return 444` (nikto/sqlmap/nmap/nuclei/wpscan/…).
- **Login brute-force throttle** (`limit_req`, 12 r/min + burst) keyed on the
  real client IP, applied to login POSTs only (an empty-key map keeps normal
  browsing through `index.php` un-throttled).
- **CSP + HSTS** response headers; `X-Content-Type-Options`, `X-Frame-Options`.
- **PHP execution allow-list** — only `index.php` and `static.php` ever execute;
  any other `.php` (a dropped webshell) returns 404.

## Bundled plugins & skins

Pre-installed; enable with `ROUNDCUBEMAIL_PLUGINS` (comma-separated). Nothing
loads unless you list it.

### Plugins

| Plugin | Version | What it does |
|---|---|---|
| `contextmenu` | 3.3.1 | Right-click context menus (message list / folders) |
| `contextmenu_folder` | 2.0.2 | Folder management context menu |
| `swipe` | 0.6 | Touch swipe gestures (mobile) |
| `show_folder_size` | 0.7.22 | Folder size column |
| `quota` | git | Mailbox/IMAP quota display |
| `persistent_login` | 1.0.3 | "Keep me logged in" |
| `identity_switch` | 3.0.5 | Switch between separate IMAP/SMTP accounts (toteph42 fork) |
| `advanced_search` | 3.7 | Extended search form |
| `account_details` | 5.0.0 | Per-account info pane |
| `message_highlight` | 1.0.5 | Colour-highlight messages by rule |
| `authres` (authres_status) | 0.7.1 | Show SPF/DKIM/DMARC results |
| `thunderbird_labels` | 1.6.2 | Thunderbird-compatible coloured labels |
| `responses` | 1.3.13 | Canned-response templates |
| `easy_unsubscribe` | git | One-click List-Unsubscribe |
| `rcguard` | 1.3.2 | reCAPTCHA after failed logins |
| `twofactor_gauthenticator` | composer | Two-factor auth (TOTP / Google Authenticator) |
| `scheduled_sending` | composer | Queue messages for later delivery |
| `customizr` | composer | Custom logo / watermark / stylesheets via config |
| `dovecot_client_ip` | composer | Forward client IP to Dovecot on IMAP connect |
| `carddav` | composer | CardDAV address-book sync |

Roundcube core plugins (`archive`, `zipdownload`, `managesieve`, `password`,
`newmail_notifier`, `new_user_dialog`) ship with RC and are on by default.

### Skins

Pick one with `ROUNDCUBEMAIL_SKIN` (default `elastic`).

| Skin | Source | Notes |
|---|---|---|
| `elastic` | Roundcube core | Default, responsive |
| `elastic4mobile` | eilandert/roundcube-elastic4mobile (fork) | Mobile-tuned elastic |
| `elastic-dark` | tborychowski/elastic-dark | Dark theme |
| `elastic2025` | bijanbina/Elastic2025 | Refreshed elastic look |
| `gmail` | bundled (this image) | Gmail look-alike |
| `outlook365` | bundled (this image) | Outlook 365 look-alike |
| `larry` | roundcube/larry | Classic RC 1.x skin |
| `classic` | roundcube/classic | Minimal classic skin |

## Quick start

```sh
curl -fsSLO https://raw.githubusercontent.com/eilandert/dockerized/master/src/roundcube/docker-compose.yml
$EDITOR docker-compose.yml     # set MARIADB_* + ROUNDCUBEMAIL_DB_PASSWORD,
                               # and ROUNDCUBEMAIL_DEFAULT_HOST / SMTP_SERVER
docker compose up -d
# Browse http://localhost:8080/  ->  log in with an IMAP account.
```

### `docker-compose.yml`

```yaml
services:
  db:
    image: docker.io/eilandert/mariadb:debian
    restart: unless-stopped
    environment:
      MARIADB_DATABASE: roundcube
      MARIADB_USER: roundcube
      MARIADB_PASSWORD: change-me
      MARIADB_ROOT_PASSWORD: change-me-too
    volumes:
      - db:/var/lib/mysql
    networks: [rc]
    security_opt:
      - no-new-privileges:true
    cap_drop: [ALL]
    cap_add: [CHOWN, SETUID, SETGID, DAC_OVERRIDE]
    deploy:
      resources:
        limits:
          memory: 512M
          pids: 256
    healthcheck:
      test: ["CMD", "healthcheck.sh", "--connect", "--innodb_initialized"]
      interval: 10s
      timeout: 5s
      retries: 12

  roundcube:
    image: docker.io/eilandert/roundcube:latest
    restart: unless-stopped
    depends_on:
      db:
        condition: service_healthy
    # Unprivileged: cap_drop ALL -> the container CANNOT chown, so the config
    # mount must already be owned 10001:10001 (a named volume inherits it).
    user: "10001:10001"
    environment:
      TZ: Europe/Amsterdam
      # ---- IMAP (reading mail) ----
      ROUNDCUBEMAIL_DEFAULT_HOST: ssl://imap.example.org
      ROUNDCUBEMAIL_DEFAULT_PORT: 993
      # ---- SMTP (sending mail) ----
      ROUNDCUBEMAIL_SMTP_SERVER: tls://smtp.example.org
      ROUNDCUBEMAIL_SMTP_PORT: 587
      # TLS to your mail server is VERIFIED by default. If the cert won't match:
      #   pin a CA: ROUNDCUBEMAIL_SSL_CA=/etc/ssl/mail-ca.pem (mount it :ro)
      #   trusted LAN only (allows MITM): ROUNDCUBEMAIL_SSL_VERIFY: 0
      # ---- database (points at the bundled `db` service) ----
      ROUNDCUBEMAIL_DB_TYPE: mysql
      ROUNDCUBEMAIL_DB_HOST: db
      ROUNDCUBEMAIL_DB_PORT: 3306
      ROUNDCUBEMAIL_DB_USER: roundcube
      ROUNDCUBEMAIL_DB_PASSWORD: change-me      # must match MARIADB_PASSWORD
      ROUNDCUBEMAIL_DB_NAME: roundcube
      # ---- app ----
      ROUNDCUBEMAIL_PLUGINS: archive,zipdownload,managesieve,newmail_notifier,password,new_user_dialog,contextmenu,persistent_login
      ROUNDCUBEMAIL_UPLOAD_MAX_FILESIZE: 25M
      ROUNDCUBEMAIL_SKIN: elastic
      CLEAN_INACTIVE_USERS_DAYS: 365
    ports:
      # Loopback only — :8080 trusts X-Forwarded-For from private ranges, so do
      # not expose it to an untrusted network; terminate TLS at your edge proxy.
      - "127.0.0.1:8080:8080"
    networks: [rc]
    # ---- hardening ----
    read_only: true        # rootfs is immutable; writes go to the mounts below
    volumes:
      - conf:/var/roundcube/config
    tmpfs:
      - /tmp:uid=10001,gid=10001,mode=1770,noexec,nosuid,nodev
      - /run:uid=10001,gid=10001,mode=0750,exec,nosuid,nodev   # s6 scratch — exec REQUIRED
    security_opt:
      - no-new-privileges:true
      - apparmor=docker-default
    cap_drop: [ALL]        # angie binds :8080 -> ZERO capabilities required
    ulimits:
      nofile:
        soft: 10240
        hard: 10240
    deploy:
      resources:
        limits:
          memory: 512M
          pids: 256
    logging:
      driver: json-file
      options:
        max-size: "10m"
        max-file: "3"

networks:
  rc:

volumes:
  db:
  conf:
```

The compose file bundles a hardened MariaDB; point `ROUNDCUBEMAIL_DEFAULT_HOST`
/ `ROUNDCUBEMAIL_SMTP_SERVER` at your own IMAP/SMTP servers. Run behind TLS in
production (terminate at your edge proxy, forward the real client IP via
`X-Forwarded-For`). The container listens on **:8080** only.

## Mount ownership (because the container can't chown)

`cap_drop: [ALL]` removes `CAP_CHOWN`, so any **writable** mount must already be
owned by **uid `10001`**:

- **Named volumes** — nothing to do, they inherit it.
- **Host bind mounts** — `sudo chown -R 10001:10001 /your/bind/dir`.
- **tmpfs** — set it inline: `--tmpfs /tmp:uid=10001,gid=10001,mode=1770,noexec,nosuid,nodev`.

A *Permission denied* on boot = a writable mount not owned `10001:10001`. The
fix is always the `chown` — never add a capability back. (The container prints
these same instructions in its startup logs.)

## Configuration

Driven by `ROUNDCUBEMAIL_*` env vars (IMAP/SMTP hosts+ports, DB DSN, plugin
list, skin, upload size, TLS verification). Per-deployment PHP overrides go in a
`phpfpm.conf.override` in the config volume; extra Roundcube config in a
`config.inc.php.user`. TLS to your mail server is **verified by default** — set
`ROUNDCUBEMAIL_SSL_CA` to pin a private CA, or (trusted LAN only, allows MITM)
`ROUNDCUBEMAIL_SSL_VERIFY=0`.
