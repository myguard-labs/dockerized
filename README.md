# Dockerized — container images that match the deb.myguard.nl stack

**In short:** these are Docker images for the same web/mail/DB stack that runs [deb.myguard.nl](https://deb.myguard.nl), built straight from the hardened Debian/Ubuntu packages that site publishes.

This is a monorepo: a directory of Dockerfiles plus a Buildx orchestrator that builds them in the right order. Every image is built on top of the **same hardened packages** — nginx, Angie, ModSecurity, PHP, Postfix, Dovecot, rspamd, openssl-nginx — published at [deb.myguard.nl](https://deb.myguard.nl). The upshot: running one of these containers gets you exactly what `apt install` would give you on a Debian/Ubuntu box pointed at the repo, with none of the manual setup.

New here? Read [Scope](#scope) for what's included, then [Quick start](#quick-start) to build something.

Want to chat, file bugs, suggest a module? Join the Discord: **[discord.gg/UQNsFg2y](https://discord.gg/UQNsFg2y)**.

## Scope

Numbers are derived from `build/config.sh` and `docker-bake.hcl` — run the commands yourself to confirm.

- **Base distros:** Ubuntu `resolute` (rolling) and Debian `trixie`, plus a few Alpine targets where it matters (rspamd, letsencrypt, unbound)
- **PHP versions:** `5.6`, `7.4`, `8.0`, `8.2`, `8.4`, `8.5` (six branches; see `PHP_VERSIONS` in [build/config.sh](build/config.sh))
- **Build targets:** **89** — one image variant each; count with `grep -c '^target ' docker-bake.hcl`
- **Source components:** **24** subdirectories under [src/](src/), one per service
- **Registry prefix:** `docker.io/eilandert/<image>` (see `DOCKER_REGISTRY_PREFIX` in `build/config.sh`)

## Repository layout

```
dockerized/
├── buildx.sh                # wrapper → build/buildx-sequential.sh
├── generate.sh              # wrapper → build/generate.sh
├── docker-bake.hcl          # 89 targets + groups (base, phpfpm, nginx, angie, mail, db, …)
├── build/                   # the build machinery (you rarely edit these directly)
│   ├── buildx-sequential.sh # orchestrator — builds one target at a time, in layer order
│   ├── generate.sh          # walks src/<component>/.generate.sh in dependency order
│   ├── generate-lib.sh      # shared template helpers
│   ├── config.sh            # distro versions, PHP versions, registry prefix, version markers
│   └── monitor-builds.sh    # tail/inspect helper for long bake runs
└── src/                     # one directory per component (24 total) — this is where you make changes
    ├── base/                       # ubuntu-base + debian-base (everything else builds on these)
    ├── php-fpm/                    # php-fpm 5.6 … 8.5, both distros
    ├── nginx/                      # nginx + ModSecurity3 + PageSpeed (matches deb.myguard.nl nginx)
    ├── angie/                      # Angie-nextgen build (matches deb.myguard.nl angie)
    ├── apache-phpfpm/              # Apache + PHP-FPM
    ├── mariadb/                    # MariaDB (upstream mariadb-docker, repinnable)
    ├── valkey/                     # Redis-compatible fork
    ├── postfix/                    # SMTP, paired with the deb.myguard.nl postfix package
    ├── dovecot-ubuntu/             # IMAP/POP3 (debian-dovecot target)
    ├── rspamd-git/                 # rspamd (git/HEAD + stable variants)
    ├── rspamd-dcc-razor-pyzor/     # rspamd DCC/Razor/Pyzor backends (+ gozer)
    ├── rspamd-olefy/               # rspamd OLE/Office-document scanning sidecar
    ├── rspamd-yarad/               # rspamd YARA rule daemon
    ├── roundcube/                  # webmail (hardened — see src/roundcube/README.md)
    ├── vimbadmin/                  # mail admin UI
    ├── unbound/  rbldnsd/          # recursive DNS + RBL DNS
    ├── openssh/                    # ssh daemon image
    ├── aptly/  reprepro/           # APT repo tooling
    ├── letsencrypt/                # ACME client image
    ├── docker-cms/                 # CMS bundle
    ├── psol-build/                 # PageSpeed Optimization Library compile env
    └── sitemap_warmup/             # support utility
```

`docker buildx bake --print` will list every target and the groups they belong to.

## Quick start

Prereqs: Docker with Buildx (`docker buildx version`), Linux, network access to docker.io for base layers. Builds run sequentially so a laptop is fine — they're just slow.

```bash
# Regenerate Dockerfiles from templates (after editing src/<component>/Dockerfile-template*)
./generate.sh

# Build everything, one target at a time, in dependency order
./buildx.sh

# Build a single target
docker buildx bake -f docker-bake.hcl ubuntu-nginx-php84

# Build a group
docker buildx bake base
docker buildx bake phpfpm
docker buildx bake nginx angie
docker buildx bake mail
docker buildx bake db
```

### Build layers (the order buildx-sequential.sh walks)

1. **base** — `ubuntu-base`, `debian-base` (one target per distro)
2. **phpfpm + db + utilities** — every PHP-FPM version against every base, plus `mariadb`, `redis`, `valkey`
3. **webservers + services** — `nginx-*`, `angie-*`, `apache-phpfpm-*`, mail stack
4. **composed images** — `roundcube`, `docker-cms`, etc. that need a finished webserver

`build/buildx-sequential.sh` enforces this so a missing base never breaks a downstream build.

## Environment knobs

| Variable | Default | Effect |
|---|---|---|
| `PUSH` | on if `hostname == build`, off otherwise | `PUSH=1` forces `--push`; `PUSH=0` forces it off |
| `LOAD` | `0` | `LOAD=1` loads into the local docker daemon (only when `PUSH` is off) |
| `BUILDX_CACHE_DIR` | `$XDG_CACHE_HOME/dockerized-buildx` | Persistent local buildkit cache |
| `BUILDX_BUILDER` | `dockerized-build` | Name of the buildx builder created/used |
| `DOCKERIZED_PRUNE` | `0` | `1` re-enables the old `docker system prune -a` between targets |
| `GENERATE_COMMIT` | `0` | `1` makes `generate.sh` commit + push regenerated Dockerfiles |
| `MARIADB_UPSTREAM_REF` | `master` | git ref pulled from `MariaDB/mariadb-docker` (pin to a tag for reproducibility) |
| `MARIADB_UPSTREAM_PATH` | `10.11` | directory inside the upstream repo |
| `MARIADB_TARGET_VERSION` | `11.8` | version string written into the rebuilt Dockerfiles |

## Why these images exist

Most public docker images for nginx/Angie ship the upstream binaries with the upstream defaults. These don't — they're built on top of the same Debian/Ubuntu packages published at [deb.myguard.nl](https://deb.myguard.nl), with the same patches and modules. So:

- **HTTP/3 + QUIC + kTLS** out of the box on nginx and Angie. See [Post-Quantum Cryptography with NGINX and Angie](https://deb.myguard.nl/2026/05/post-quantum-cryptography-with-nginx-and-angie-ml-kem-hybrid-tls-and-how-to-configure-it/) for what's actually wired up.
- **Dedicated OpenSSL build** (`openssl-nginx`) tuned for nginx — RDRAND entropy, EC-NISTP 64-bit GCC backend, OpenResty session yield patch, no legacy ciphers. Background: [OpenSSL-NGINX: A Dedicated OpenSSL Build for NGINX and Angie](https://deb.myguard.nl/2026/05/openssl-nginx-a-dedicated-openssl-build-for-nginx-and-angie/).
- **Audited dynamic modules.** The full set shipped in the nginx image is documented at [deb.myguard.nl/nginx-modules/](https://deb.myguard.nl/nginx-modules/); zstd in particular went through a deep audit — see [We audited the zstd-nginx-module and found a lot of bugs](https://deb.myguard.nl/2026/05/we-audited-the-zstd-nginx-module-and-found-a-lot-of-bugs/).
- **ModSecurity3** compiled in, with the same CRS exclusions used on the upstream site.

If you're running these containers in production, the matching server-side context lives in the articles at [deb.myguard.nl/articles/](https://deb.myguard.nl/articles/).

## Adding a new component

1. `mkdir src/<service>/` and add either a static `Dockerfile` or a `Dockerfile-template*` plus a `.generate.sh`.
2. Add a `target "<service>"` block (and any per-distro variants) to `docker-bake.hcl`.
3. Add the target name to the appropriate `LAYERS` entry in `build/buildx-sequential.sh` so it builds in the right order.
4. `./generate.sh && docker buildx bake <service>` to test locally.
5. Commit, push.

For modifications to existing components, edit the template (not the generated `Dockerfile`) and re-run `./generate.sh` — the per-component `.generate.sh` scripts under `src/<component>/` are also runnable standalone for fast iteration.

## Troubleshooting

```bash
# Generation
ls src/php-fpm/Dockerfile-template.*       # template present?
./build/generate.sh -v                     # verbose generator
(cd src/nginx && bash ./.generate.sh)      # regenerate one component in isolation

# Build
grep -A 5 'ubuntu-nginx-php84' docker-bake.hcl   # inspect the target
docker buildx bake --print ubuntu-nginx-php84    # dry-run / show plan
docker buildx bake ubuntu-nginx-php84            # real build
```

If a build fails on a base layer, rebuild that layer first — `buildx-sequential.sh` does this for you on a full run, but a single-target `bake` won't.

## Links

- Package repo & articles: **[deb.myguard.nl](https://deb.myguard.nl)**
- Module catalogue: **[deb.myguard.nl/nginx-modules/](https://deb.myguard.nl/nginx-modules/)**
- All articles: **[deb.myguard.nl/articles/](https://deb.myguard.nl/articles/)**
- Discord: **[discord.gg/UQNsFg2y](https://discord.gg/UQNsFg2y)**
- Source: [github.com/myguard-labs/dockerized](https://github.com/myguard-labs/dockerized)
