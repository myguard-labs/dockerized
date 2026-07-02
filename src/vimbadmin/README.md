# ViMbAdmin — Debian / Angie-minimal / PHP-FPM 8.5

Hardened Docker image for the modernised **[ViMbAdmin fork](https://github.com/eilandert/ViMbAdmin)** —
the Postfix + Dovecot virtual-mailbox admin panel.

- **Live demo:** <https://vimbadmin.myguard.nl> — try the panel before you pull
- **Docker Hub:** <https://hub.docker.com/r/eilandert/vimbadmin>
- **Image source (this dir):** <https://github.com/myguard-labs/dockerized/tree/master/src/vimbadmin>
- **App source (fork):** <https://github.com/eilandert/ViMbAdmin>
- **Write-up / guided tour:** <https://deb.myguard.nl/2026/06/vimbadmin-postfix-dovecot-mailbox-admin-panel/>

## What's in the image

| | |
|---|---|
| Base | `eilandert/debian-base` (trixie-slim + deb.myguard.nl repo + hardening) |
| Web | `angie-minimal` — no WAF module needed; a **native positive-security vhost** only lets known methods/routes/args reach PHP |
| Runtime | `php8.5-fpm`, minimal extension set, **Snuffleupagus** + the app's audited `vimbadmin-strict` ruleset |
| Cache | tuned **OPcache** (immutable code  no per-include stat) + **APCu**; Doctrine metadata cache defaults to `ApcuCache` (persistent, not per-request) |
| Config | all of Angie in one file: [`angie.conf`](angie.conf) (vhost + positive-security gate + fastcgi) |
| Size | ~320 MB |

## Security & hardening

This image is defence-in-depth: the **application** is hardened in the fork,
the **runtime** by Snuffleupagus + the FPM pool, the **edge** by a native
positive-security Angie vhost, and the **container** by the measures below.

### Container / image

- **Runs fully unprivileged — no root, anywhere.** PID 1 (the Angie master),
  every Angie worker and the whole PHP-FPM tree run as the unprivileged
  `phpfpm` user (`USER phpfpm:www-data` in the image; `user: "997:33"` in
  compose). There is no root process in the container at any point.
- **Zero Linux capabilities** — `cap_drop: [ALL]` with **no `cap_add` at all**.
  Verified at runtime: `CapEff = CapPrm = CapBnd = 0000000000000000`. This is
  possible because nothing in the container ever needs root: Angie binds a
  high port (**:8080**, no `CAP_NET_BIND_SERVICE`), and nothing does runtime
  `setuid`/`chown` (the FPM master is already unprivileged, so it never drops
  privileges, and the writable mounts are pre-owned — see *Mount ownership*).
- **`no-new-privileges`** — blocks any setuid/setgid escalation.
- **AppArmor** confined (`apparmor=docker-default`).
- **Read-only root filesystem** (`read_only: true`). Only the `var` + `configs`
  volumes and the writable runtime mounts (`/run`, `/tmp`, `/var/log/php-fpm`)
  can be written. Angie temp paths + pid and the FPM master error-log are
  redirected onto those mounts so the rest of the rootfs stays immutable.
- **Codebase is root-owned and read-only to the web/PHP user.** Only `var/`
  (cache, compiled templates, logs, brute-force state, the runtime Snuffleupagus
  ruleset) and `application/configs/` are writable, and only by `phpfpm`. The
  web/PHP processes cannot modify a single line of code.
- **No baked secrets.** The `securitysalt` (encrypts 2FA secrets, seeds CSRF)
  and the Snuffleupagus `secret_key` are generated **on first boot** and
  persisted in the volumes — unique per deployment, never in an image layer.
- **Minimal attack surface.** `angie-minimal` (no modsecurity/lua/brotli),
  only the PHP extensions ViMbAdmin uses, dedicated non-login `phpfpm` user.
- **Stripped:** all apt repositories + lists (no apt at runtime), composer,
  git, build deps, docs, man pages, info, non-English locales, app docs/tests,
  vendor docs/tests; every **setuid/setgid bit removed**.
- **Per-service resource limits** (memory, pids, nofile) and a healthcheck.
- **Composer installer is checksum-verified** at build (SHA-384 vs the
  published signature).

> **Heads-up — because the container has no root and cannot `chown`, any
> writable mount you provide must already be owned by the runtime user
> (`phpfpm` = uid `997`, group `www-data` = gid `33`).** Named volumes get this
> for free; bind mounts and tmpfs do not. See *[Mount ownership](#mount-ownership-important)* below.

### Edge (Angie — all in [`angie.conf`](angie.conf))

- **Positive-security gate** — only allow-listed HTTP methods (GET/HEAD/POST),
  the real route map (controllers + ZF1 `/key/value` URLs + static + ACME), and
  the app's known argument names reach PHP. Unknown method  405, route  404,
  arg  403; scanner / empty user-agents  dropped (444).
- **TLS-ready** strict **CSP** + `X-Frame-Options: DENY`, `nosniff`,
  Referrer-/Permissions-Policy; **rate-limited** login; dotfile + project-
  internal path denies; **BREACH mitigation** (gzip off for dynamic HTML,
  static assets only).

### Runtime + application

Provided by the fork and wired into this image:

- **Snuffleupagus** with the audited `vimbadmin-strict` ruleset (unique
  `secret_key` per deployment), and a **hardened PHP-FPM pool** (`open_basedir`
  confined to the app + runtime dirs, `expose_php` off, `display_errors` off,
  strict session cookies — `HttpOnly` + `Secure` + `SameSite=Lax`,
  `.php`-only execution, `disable_functions` delegated to Snuffleupagus).
- **App-level:** 2FA (TOTP, encrypted secrets, backup codes, replay guard,
  force-on-login), per-IP brute-force lockout, CSRF on every form + destructive
  link, Smarty XSS auto-escaping, constant-time password checks, CSPRNG tokens,
  session-fixation regeneration.
- Full list: the **fork's [Security section](https://github.com/eilandert/ViMbAdmin#security)**.

## Deploy

```sh
# 1. Grab the compose file (or this directory) and EDIT THE PASSWORDS.
curl -fsSLO https://raw.githubusercontent.com/eilandert/dockerized/master/src/vimbadmin/docker-compose.yml
$EDITOR docker-compose.yml          # change MARIADB_* passwords

# 2. Up.
docker compose up -d

# 3. Browse http://localhost:8080/  -> first-run super-admin setup.
#    The username is an EMAIL address (you@yourdomain), not "admin".
```

Run it behind TLS in production (terminate at your edge proxy and forward the
real client IP as `REMOTE_ADDR`, or the brute-force limiter + logs will see the
proxy). The container listens on **:8080** only (a high port, so it needs no
`CAP_NET_BIND_SERVICE` — part of running with zero capabilities). The shipped
compose publishes `8080:8080`; point your reverse proxy's upstream at the
container's `:8080`.

### Mount ownership (IMPORTANT)

The container runs unprivileged with **`cap_drop: [ALL]`**, so it **cannot
`chown`**. Every writable mount must already be owned by the runtime user
before you start it:

| | uid | gid |
|---|---|---|
| `phpfpm` (runtime user) | **997** | — |
| `www-data` (socket / group) | — | **33** |

- **Named volumes** (the default in the shipped compose) — **nothing to do.**
  Docker initialises a fresh named volume with the owner of the image directory
  it shadows, and those are already `phpfpm:www-data`.
- **Host bind mounts** — you **must** pre-own them once:

  ```sh
  sudo install -d -o 997 -g 33 -m 0750 \
      /srv/vimbadmin/{config,var,run,log-phpfpm}
  sudo install -d -o 997 -g 33 -m 0770 /srv/vimbadmin/tmp
  # if the dirs already exist with the wrong owner:
  sudo chown -R 997:33 /srv/vimbadmin/{config,var,run,tmp,log-phpfpm}
  ```

- **tmpfs** — pass the uid/gid in the mount options, e.g. in compose:

  ```yaml
  tmpfs:
    - /run:uid=997,gid=33,mode=0770
    - /tmp:uid=997,gid=33,mode=0770
  ```

If a writable mount is owned by `root` (or anything other than uid 997), the
entrypoint cannot create its runtime dirs and the container exits on boot with
a *Permission denied*. The fix is always the `chown` above — never add a
capability back.

### Wire it to Postfix + Dovecot

ViMbAdmin only maintains the SQL user database — it never talks to Postfix or
Dovecot directly. Both read the **same MariaDB** through their own SQL maps;
they can live on a different host or container entirely. The Postfix
`virtual_*` maps, Dovecot `sql.conf` and the schema are in
[`EXAMPLES/`](EXAMPLES/). Let Dovecot create maildirs on first delivery/login
(`mail_location` + LMTP/LDA); this image neither sees nor needs them.

> **Password scheme must match.** ViMbAdmin hashes passwords on write; set
> Dovecot's `default_pass_scheme` to the same scheme or logins fail.

### Archive / quota / disk-delete — run on the mail host

The ViMbAdmin features that touch the mail filesystem — **archive** (the
`archive.cli-*-pendings` queue), **mailbox size/quota** (`mailbox.cli-get-sizes`)
and on-disk mailbox deletion — must run **where the maildirs live**. By default
the web container has no maildir mount, so they belong on the Dovecot host
(pointed at the same MariaDB).

The image *is* archive-capable, though: it ships the full ViMbAdmin CLI plus
`tar`/`bzip2`, so you can also run it as a **sidecar** that bind-mounts the
maildir tree (read-write) and `archive.path` (e.g. `/srv/archives`), then runs
`php /opt/vimbadmin/bin/vimbtool.php -a archive.cli-archive-pendings` on a
schedule. Same image, same DB — just give it the volumes.

The web panel works regardless: the "Archive" button just queues a DB row. If
no filesystem cron processes that queue, rows sit at `PENDING_ARCHIVE` and
nothing is ever tarred. Example mail-host scripts + crontab live in the fork:
[`contrib/cron/`](https://github.com/eilandert/ViMbAdmin/tree/master/contrib/cron)
(`vimbadmin-archive.sh`, `vimbadmin-sizes.sh`, `crontab.example`) — each with
its requirements documented inline. If you don't use archiving, ignore them —
the feature degrades to a DB-only delete.

### Persisted state

Two named volumes hold everything that must survive a redeploy:

| Volume | Mount | Holds |
|---|---|---|
| `conf` | `/opt/vimbadmin/application/configs` | `application.ini` incl. the generated `securitysalt` |
| `var`  | `/opt/vimbadmin/var` | Smarty cache, logs, brute-force state, runtime Snuffleupagus ruleset (with secret_key) |

Back these up. Losing `conf` rotates the salt (invalidates stored 2FA secrets).

### Editing the config

The image ships its config defaults inside the image (`configs.orig`); the live
`application/configs` dir is a **mountable volume** so you can adjust
`application.ini` without rebuilding. On every start the entrypoint:

- **No `application.ini` yet** (first run / fresh volume)  seeds the whole
  config dir from the shipped defaults and generates the `securitysalt`.
- **`application.ini` present** (your config)  leaves it **untouched**, and
  drops the latest shipped default beside it as **`application.ini.orig`** so
  you can `diff` after an image bump and pull in any new keys yourself.

```sh
# inspect what changed in the shipped default after an upgrade
docker compose exec vimbadmin \
  diff -u /opt/vimbadmin/application/configs/application.ini.orig \
          /opt/vimbadmin/application/configs/application.ini
```

Your edits survive restarts and image upgrades; the image never overwrites a
config it didn't create.

### Tunables

Skin, footer toggle, brute-force thresholds + IP allowlist, 2FA reset and the
TLS/proxy notes are all documented in the fork's `application.ini.dist`.
2FA reset from the CLI:

```sh
docker compose exec vimbadmin \
  php /opt/vimbadmin/bin/vimbtool.php -a admin.cli-reset-totp --username=you@example.com
```

## Build

```sh
docker buildx bake -f docker-bake.hcl debian-vimbadmin
```
