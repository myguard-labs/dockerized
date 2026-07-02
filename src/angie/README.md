# Angie — hardened, high-performance, modular Docker image

A hardened **[Angie](https://angie.software/)** image (the nginx fork that
actually ships the features you'd otherwise patch in) built from the
[deb.myguard.nl](https://deb.myguard.nl/) `angie-full` package: HTTP/3/QUIC, a
large dynamic-module set (ModSecurity, PageSpeed, Brotli, zstd, Lua, GeoIP, VTS,
njs, …), ModSecurity-CRS, and an SSL-Labs-A++ default `angie.conf` shipped by
the package itself. Optional bundled PHP-FPM (single- or multi-version) for an
all-in-one web+PHP container.

> Yes, it's another web-server image. No, it isn't running with the full
> capability set and a config last sane in 2014. It boots, it tests its own
> config before it touches anything, and it tells you *exactly* why it refused
> to start instead of restart-looping in silence at 3 a.m. You're welcome.

## Links

- **Image source / this repo:** <https://github.com/myguard-labs/dockerized/tree/master/src/angie>
- **Docker Hub:** <https://hub.docker.com/r/eilandert/angie>
- **Write-up / guided tour:** <https://deb.myguard.nl/angie-dockerized/>
- **angie packages / module list:** <https://deb.myguard.nl/angie-modules/>
- **deb.myguard.nl:** <https://deb.myguard.nl/>
- **Post-quantum TLS on NGINX & Angie (ML-KEM):** <https://deb.myguard.nl/2026/05/post-quantum-cryptography-with-nginx-and-angie-ml-kem-hybrid-tls-and-how-to-configure-it/>
- **Dedicated openssl-nginx build:** <https://deb.myguard.nl/2026/05/openssl-nginx-a-dedicated-openssl-build-for-nginx-and-angie/>
- **We audited the zstd-nginx-module:** <https://deb.myguard.nl/2026/05/we-audited-the-zstd-nginx-module-and-found-a-lot-of-bugs/>
- **Docker hardening guide:** <https://deb.myguard.nl/2026/05/docker-hardening-rootless-readonly-distroless/>
- **Discord:** <https://discord.gg/UQNsFg2y>

## Tags

Debian tags are prefixed `deb-`; Ubuntu tags have no prefix.

| Tag | Base | PHP |
|---|---|---|
| `latest` / `deb-latest` | Ubuntu (rolling) / Debian (trixie) | none |
| `php8.5` / `deb-php8.5` | Ubuntu / Debian | PHP-FPM 8.5 |
| `php8.4` … `php5.6` (+ `deb-`) | Ubuntu / Debian | that PHP version |
| `multi` / `deb-multi` | Ubuntu / Debian | multi-version PHP-FPM (pick via `PHPxx=YES`) |

Yes, `php5.6` exists. No, we won't discuss your life choices. It's there for the
legacy app you swear you'll rewrite "next quarter."

## What's in the image

- **`angie-full`** from deb.myguard.nl — HTTP/3/QUIC, the full dynamic-module
  set, ModSecurity v3 + OWASP CRS, PageSpeed. Installed alongside `brotli`,
  `zstd`, `geoip-bin`, the LuaJIT/lua-resty stack, `fcgiwrap`, `modsecurity-crs`.
- **Package-shipped config** — the package's own `angie.conf` (TLS 1.3/1.2
  AEAD-only, OCSP-ready, HTTP/2+3 tuned, slowloris timeouts, `server_tokens
  off`, gzip) and `snippets/` (`ssl-labs-aplus.conf`, `security.conf`,
  `cloudflare.conf`, `proxy.conf`, `cache-key-normalize.conf`,
  `wordpress-example.conf`, …). This image does **not** bundle its own snippets
  — the package already did the homework, twice.
- **Default vhost that actually works on first boot** — ships enabled, serves
  HTTPS on a self-signed snakeoil cert with zero certs mounted. `docker run`,
  hit `:443`, done. Browser will whine about the cert; that's the cert doing its
  job, not a bug to open a ticket about.
- **Liveness + readiness healthcheck** — probes the loopback healthz vhost, and
  on PHP images also checks that php-fpm is actually alive. "angie is up" and
  "the site works" are not the same sentence, and this image knows it.
- **Selectable allocator** via `MALLOC` (`jemalloc` default, `mimalloc`, `none`).
- Optional PHP-FPM + nullmailer + composer when a PHP tag is used.

## First-run behaviour (`bootstrap.sh`)

- On first start, copies package defaults from `/etc/angie.orig` into (possibly
  mounted-empty) `/etc/angie`, and `/etc/modsecurity.orig` into
  `/etc/modsecurity`. Existing configs are kept — it won't clobber your work.
- Refreshes `mime.types`, `scripts/`, `snippets/`, `modules-available/` from the
  package copy, then runs `scripts/reorder-modules.sh`.
- **Snakeoil fallback:** if no cert is mounted, the default vhost uses the
  self-signed snakeoil cert so `:443` answers immediately.
- **Module loading:** with **no `NGX_MODULES`** *every* module loads — slower,
  and a great way to discover which module needs config it didn't get. It warns
  and disables `mod-http-lua` / `mod-stream-lua` (they need hand-holding). **Set
  `NGX_MODULES`** to only what you use. `touch
  /etc/angie/modules-enabled/.quiet` to keep all modules and silence the nag.
- **Boot config test is fatal:** `angie -t` runs before launch. Broken config
  loud, specific error and a clean `exit 1`. No cryptic restart loop, no
  guessing, no "works on my machine."
- **24 h reload loop** picks up renewed certs and rotates the TLS session-ticket
  key (forward secrecy). It runs `angie -t` *first* and **skips the reload if
  the config is broken** — it will not faceplant your live master because you
  fat-fingered a semicolon into a mounted file.
- Sets `LD_PRELOAD` per `MALLOC`, then `exec angie -g 'daemon off;'`.

## Environment variables

| Var | Purpose |
|---|---|
| `TZ` | container timezone (e.g. `Europe/Amsterdam`) |
| `MALLOC` | `jemalloc` (default), `mimalloc`, or `none` |
| `NGX_MODULES` (or `MODULES`) | comma-separated modules to enable; unset = all (don't) |
| `PHPVERSION` | set on PHP images; `MULTI` on multi images |
| `MODE` | `FPM` (single) or `MULTI` |
| `PHP56`/`PHP74`/`PHP80`/`PHP81`/`PHP82`/`PHP83`/`PHP84`/`PHP85` | `YES` to start that PHP-FPM on a `multi` image |

## Quick start

```sh
curl -fsSLO https://raw.githubusercontent.com/eilandert/dockerized/master/src/angie/docker-compose.yml
$EDITOR docker-compose.yml      # set NGX_MODULES, mounts, TZ — read it, don't just paste
docker compose up -d
```

### `docker-compose.yml`

```yaml
services:
  angie:
    container_name: angie
    image: docker.io/eilandert/angie:deb-latest
    stop_grace_period: 3s
    restart: always
    ports:
      - 80:80
      - 443:443
      - 443:443/udp           # HTTP/3 / QUIC
    # ---- hardening: master is root (port bind + worker spawn), so a small
    # capability set is required, not the full default buffet ----
    security_opt:
      - no-new-privileges:true
    cap_drop: [ALL]
    cap_add: [NET_BIND_SERVICE, SETUID, SETGID, CHOWN, DAC_OVERRIDE]
    ulimits:
      nofile: { soft: 65535, hard: 65535 }   # matches worker_rlimit_nofile
    volumes:
      - ./config/angie:/etc/angie:rw
#      - ./config/modsecurity/:/etc/modsecurity:rw
#      - ./cache/angie:/var/cache/angie:rw
      # if pulled with a PHP tag:
#      - ./config/php:/etc/php:rw
#      - ./config/nullmailer:/etc/nullmailer:rw
      # for use with the letsencrypt docker:
#      - ./letsencrypt/certs:/etc/letsencrypt:ro
#      - ./letsencrypt/html:/var/www/html:ro
    environment:
      - TZ=Europe/Amsterdam
      - MALLOC=jemalloc        # jemalloc (default) | mimalloc | none
      # Enable only the modules you use (full list: deb.myguard.nl/angie-modules/)
      - NGX_MODULES=mod-security-headers,mod-http-fancyindex
      # if pulled with the :multi tag, pick PHP versions:
#      - PHP56=YES
#      - PHP74=YES
#      - PHP80=YES
#      - PHP82=YES
#      - PHP84=YES
#      - PHP85=YES
```

Enableable modules include `mod-http-brotli`, `mod-http-cache-purge`,
`mod-http-dav-ext`, `mod-http-doh`, `mod-http-fancyindex`, `mod-http-geoip2`,
`mod-http-headers-more-filter`, `mod-http-image-filter`, `mod-http-lua`,
`mod-http-njs`, `mod-http-subs-filter`, `mod-modsecurity`, `mod-nchan`,
`mod-pagespeed`, `mod-rtmp`, `mod-security-headers`, `mod-vts`, `mod-stream` —
full list at <https://deb.myguard.nl/angie-modules/>.

## Security & hardening

Because "it's behind a firewall" is not a security model.

- deb.myguard.nl apt repo added with **`signed-by` GPG verification** (keyring
  ships in the base image — no `trusted=yes`, no MITM-by-design).
- Built on the hardened MyGuard base: SUID/SGID stripped, system users pruned,
  core dumps off, docs/man/locales purged.
- angie master runs as root, workers drop to `www-data`; config dirs
  `root:www-data` group-write-stripped; writable dirs pre-created `0750`; all
  setuid/setgid bits stripped in this layer too.
- `server_tokens off`; upstream `X-Powered-By` / `X-Generator` headers hidden —
  attackers can fingerprint you the hard way.
- Healthcheck vhost is loopback-only; the public default returns `444` (the
  "I'm not even going to dignify that with a status line" response).
- Compose runs with `no-new-privileges`, `cap_drop: [ALL]` and only the five
  capabilities angie actually needs.
- TLS session-ticket key rotated daily for forward secrecy.

Terminate TLS at this container or an upstream proxy; the package's
`ssl-labs-aplus.conf` snippet + HSTS assume HTTPS-only. If you serve this over
plain HTTP in production, that's between you and your incident report.

## Building

Dockerfiles are generated from `Dockerfile.template` by `.generate.sh` (one per
PHP version × {Debian, Ubuntu} + base + multi). Edit the **template**, never the
generated `Dockerfile-*` — they get overwritten and your "quick fix" with them.
Images are built/tagged via `docker-bake.hcl` in the repo root (`angie` group).
Inject provenance labels at build time:

```sh
VCS_REF=$(git rev-parse --short HEAD) \
BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
  docker buildx bake angie --push
```
