# Provenance / supply-chain build args. Override from the environment, e.g.:
#   VCS_REF=$(git rev-parse --short HEAD) BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
#     docker buildx bake nginx --push
variable "VCS_REF"    { default = "unknown" }
variable "BUILD_DATE" { default = "unknown" }
# Every published image includes both architectures. For a local single-arch
# build (including --load on classic Docker stores), set PLATFORMS=linux/amd64
# or PLATFORMS=linux/arm64.
variable "PLATFORMS" { default = "linux/amd64,linux/arm64" }
# yarad's own source version (git describe of src/mailstrix), baked into the
# binary's main.version and surfaced on its /version endpoint. daily.sh exports
# it; defaults to "dev" for an ad-hoc build that doesn't set it.
variable "MAILSTRIX_VERSION" { default = "dev" }
# The nearest published release tag (e.g. 1.0.0), from `git describe --abbrev=0`.
# debian-mailstrix's Dockerfile.release downloads the per-arch release binaries
# from this tag and tags the image with it. Must name a release that has assets.
variable "MAILSTRIX_RELEASE" { default = "" }
# The mailstrix main commit :testing is built from. daily.sh resolves it with
# git ls-remote so the git context and the revision label name the same
# commit; an ad-hoc build without it falls back to the moving main branch.
variable "MAILSTRIX_MAIN_REF" { default = "main" }

# Shared metadata. Targets inherit this to receive VCS_REF / BUILD_DATE both as
# build-args (for Dockerfiles that bake them into their own LABEL block, e.g.
# nginx/angie) AND as buildkit-applied OCI labels (revision/created), so EVERY
# inheriting image carries provenance even when its Dockerfile has no LABEL for
# it. The `labels` map is stamped at build time by buildkit regardless of the
# Dockerfile — no per-image ARG/LABEL edit needed.
target "_meta" {
    platforms = split(",", PLATFORMS)
    args = {
        VCS_REF    = "${VCS_REF}"
        BUILD_DATE = "${BUILD_DATE}"
    }
    labels = {
        "org.opencontainers.image.revision" = "${VCS_REF}"
        "org.opencontainers.image.created"  = "${BUILD_DATE}"
        "org.opencontainers.image.source"   = "https://github.com/myguard-labs/dockerized"
    }
}

# ---------------------------------------------------------------------------
# Generated web/php-fpm targets (bake matrix)
#
# The 48 per-(distro x PHP-version) targets for php-fpm, nginx, angie and
# apache are mechanical over {ubuntu,debian} x {5.6,7.4,8.0,8.2,8.4,8.5}, so
# they are expressed as bake `matrix` targets instead of 48 hand-written
# blocks. The `name` attribute reproduces the exact previous target names
# (e.g. ubuntu-nginx-php84). The `multi` variants and the bare (no-PHP)
# nginx/angie targets are irregular (naming + tags) and stay hand-written.
#
# IMPORTANT: PHP_MATRIX below must stay in sync with PHP_VERSIONS in
# build/config.sh (which drives Dockerfile generation). Keep both equal;
# build/check-matrix-sync.sh asserts it.
# ---------------------------------------------------------------------------

variable "PHP_MATRIX" {
  default = [
    { v = "5.6", nn = "56" },
    { v = "7.4", nn = "74" },
    { v = "8.0", nn = "80" },
    { v = "8.2", nn = "82" },
    { v = "8.4", nn = "84" },
    { v = "8.5", nn = "85" },
  ]
}

variable "DISTRO_MATRIX" {
  default = [
    { distro = "ubuntu", pfx = "",     dsuf = "ubu", base = "ubuntu-base", basetag = "eilandert/ubuntu-base:rolling" },
    { distro = "debian", pfx = "deb-", dsuf = "deb", base = "debian-base", basetag = "eilandert/debian-base:stable" },
  ]
}

target "gen-phpfpm" {
  name = "${tgt.distro}-phpfpm${php.nn}"
  matrix = { tgt = DISTRO_MATRIX, php = PHP_MATRIX }
  inherits = ["_meta"]
  context = "src/php-fpm"
  dockerfile = "Dockerfile-${php.nn}-${tgt.dsuf}"
  tags = php.nn == "80" ? [
    "docker.io/eilandert/php-fpm:${tgt.pfx}${php.v}",
    "docker.io/eilandert/php-fpm:${tgt.pfx}latest",
  ] : [
    "docker.io/eilandert/php-fpm:${tgt.pfx}${php.v}",
  ]
  contexts = { "${tgt.basetag}" = "target:${tgt.base}" }
}

target "gen-nginx-php" {
  name = "${tgt.distro}-nginx-php${php.nn}"
  matrix = { tgt = DISTRO_MATRIX, php = PHP_MATRIX }
  inherits = ["_meta"]
  context = "src/nginx"
  dockerfile = "Dockerfile-php${php.nn}-${tgt.dsuf}"
  tags = [
    "docker.io/eilandert/nginx-modsecurity3-pagespeed:${tgt.pfx}php${php.v}",
    "docker.io/eilandert/nginx:${tgt.pfx}php${php.v}",
  ]
  contexts = { "eilandert/php-fpm:${tgt.pfx}${php.v}" = "target:${tgt.distro}-phpfpm${php.nn}" }
}

target "gen-angie-php" {
  name = "${tgt.distro}-angie-php${php.nn}"
  matrix = { tgt = DISTRO_MATRIX, php = PHP_MATRIX }
  inherits = ["_meta"]
  context = "src/angie"
  dockerfile = "Dockerfile-php${php.nn}-${tgt.dsuf}"
  tags = ["docker.io/eilandert/angie:${tgt.pfx}php${php.v}"]
  contexts = { "eilandert/php-fpm:${tgt.pfx}${php.v}" = "target:${tgt.distro}-phpfpm${php.nn}" }
}

target "gen-apache" {
  name = "${tgt.distro}-apache-php${php.nn}"
  matrix = { tgt = DISTRO_MATRIX, php = PHP_MATRIX }
  inherits = ["_meta"]
  context = "src/apache-phpfpm"
  dockerfile = "Dockerfile-${php.nn}-${tgt.dsuf}"
  tags = php.nn == "80" ? [
    "docker.io/eilandert/apache-phpfpm:${tgt.pfx}${php.v}",
    "docker.io/eilandert/apache-phpfpm:${tgt.pfx}latest",
  ] : [
    "docker.io/eilandert/apache-phpfpm:${tgt.pfx}${php.v}",
  ]
  contexts = { "eilandert/php-fpm:${tgt.pfx}${php.v}" = "target:${tgt.distro}-phpfpm${php.nn}" }
}


group "default" {
    targets = ["ubuntu-base", "debian-base"]
}

group "base-current" {
    targets = ["ubuntu-base", "debian-base"]
}

group "base" {
    targets = ["ubuntu-base", "debian-base"]
}

# ---------------------------------------------------------------------------
# Build layers — dependency tiers for the sequential daily build.
# buildx-sequential.sh derives its LAYERS array from these groups, so
# docker-bake.hcl is the single source of truth for what the daily builds.
# Add a target to the right layer group and it is picked up automatically.
# Keep the tiers dependency-ordered: base -> phpfpm/db -> web+php -> services.
# The 7 explicit web targets below are the bare (no-PHP) servers + cms +
# vimbadmin + roundcube that no family roll-up covers.
# ---------------------------------------------------------------------------

group "layer1-base" {
    targets = ["base"]
}

group "layer2-phpfpm-db" {
    targets = ["phpfpm", "db"]
}

group "layer3-webphp" {
    targets = ["nginx-php", "angie-php", "apache"]
}

group "layer4-services" {
    targets = [
        "mail", "misc",
        "debian-nginx", "ubuntu-nginx",
        "debian-angie", "ubuntu-angie", "debian-angie-cms",
        "debian-vimbadmin", "debian-roundcube",
    ]
}

# ---------------------------------------------------------------------------
# Per-family roll-ups (both OS)
# ---------------------------------------------------------------------------

group "phpfpm" {
    targets = ["debian-phpfpm", "ubuntu-phpfpm"]
}

group "multiphp" {
    targets = ["ubuntu-multiphp", "debian-multiphp"]
}

group "nginx" {
    targets = ["debian-nginx-all", "ubuntu-nginx-all"]
}

group "angie" {
    targets = ["debian-angie-all", "ubuntu-angie-all"]
}

group "angie-php" {
    targets = ["debian-angie-php", "ubuntu-angie-php"]
}

group "nginx-php" {
    targets = ["debian-nginx-php", "ubuntu-nginx-php"]
}

group "apache" {
    targets = ["debian-apache", "ubuntu-apache"]
}

# ---------------------------------------------------------------------------
# Debian roll-ups
# ---------------------------------------------------------------------------

group "debian" {
    targets = [
        "debian-base",
        "debian-phpfpm", "debian-multiphp",
        "debian-nginx-all",
        "debian-angie-all",
        "debian-apache",
        "debian-mariadb", "debian-valkey",
        "debian-postfix", "debian-dovecot",
        "debian-rspamd", "debian-rspamd-git", "debian-rspamd-official",
        "debian-rspamd-drp",
        "debian-roundcube", "debian-webtest", "debian-vimbadmin",
        "debian-sitewarmup", "debian-openssh",
    ]
}

group "debian-phpfpm" {
    targets = [
        "debian-phpfpm56", "debian-phpfpm74", "debian-phpfpm80",
        "debian-phpfpm82", "debian-phpfpm84", "debian-phpfpm85",
        "debian-multiphp",
    ]
}

group "debian-nginx-all" {
    targets = [
        "debian-nginx",
        "debian-nginx-php56", "debian-nginx-php74", "debian-nginx-php80",
        "debian-nginx-php82", "debian-nginx-php84", "debian-nginx-php85",
        "debian-nginx-multi",
    ]
}

group "debian-nginx-php" {
    targets = [
        "debian-nginx-php56", "debian-nginx-php74", "debian-nginx-php80",
        "debian-nginx-php82", "debian-nginx-php84", "debian-nginx-php85",
        "debian-nginx-multi",
    ]
}

group "debian-angie-all" {
    targets = [
        "debian-angie",
        "debian-angie-php56", "debian-angie-php74", "debian-angie-php80",
        "debian-angie-php82", "debian-angie-php84", "debian-angie-php85",
        "debian-angie-multi",
        "debian-angie-cms",
    ]
}

group "debian-angie-php" {
    targets = [
        "debian-angie-php56", "debian-angie-php74", "debian-angie-php80",
        "debian-angie-php82", "debian-angie-php84", "debian-angie-php85",
        "debian-angie-multi",
    ]
}

group "debian-apache" {
    targets = [
        "debian-apache-php56", "debian-apache-php74", "debian-apache-php80",
        "debian-apache-php82", "debian-apache-php84", "debian-apache-php85",
        "debian-apache-multiphp",
    ]
}

# ---------------------------------------------------------------------------
# Ubuntu roll-ups
# ---------------------------------------------------------------------------

group "ubuntu" {
    targets = [
        "ubuntu-base",
        "ubuntu-phpfpm", "ubuntu-multiphp",
        "ubuntu-nginx-all",
        "ubuntu-angie-all",
        "ubuntu-apache",
        "ubuntu-mariadb", "ubuntu-valkey",
        "ubuntu-postfix",
        "ubuntu-rspamd",
        "ubuntu-reprepro",
    ]
}

group "ubuntu-phpfpm" {
    targets = [
        "ubuntu-phpfpm56", "ubuntu-phpfpm74", "ubuntu-phpfpm80",
        "ubuntu-phpfpm82", "ubuntu-phpfpm84", "ubuntu-phpfpm85",
        "ubuntu-multiphp",
    ]
}

group "ubuntu-nginx-all" {
    targets = [
        "ubuntu-nginx",
        "ubuntu-nginx-php56", "ubuntu-nginx-php74", "ubuntu-nginx-php80",
        "ubuntu-nginx-php82", "ubuntu-nginx-php84", "ubuntu-nginx-php85",
        "ubuntu-nginx-multi",
    ]
}

group "ubuntu-nginx-php" {
    targets = [
        "ubuntu-nginx-php56", "ubuntu-nginx-php74", "ubuntu-nginx-php80",
        "ubuntu-nginx-php82", "ubuntu-nginx-php84", "ubuntu-nginx-php85",
        "ubuntu-nginx-multi",
    ]
}

group "ubuntu-angie-all" {
    targets = [
        "ubuntu-angie",
        "ubuntu-angie-php56", "ubuntu-angie-php74", "ubuntu-angie-php80",
        "ubuntu-angie-php82", "ubuntu-angie-php84", "ubuntu-angie-php85",
        "ubuntu-angie-multi",
    ]
}

group "ubuntu-angie-php" {
    targets = [
        "ubuntu-angie-php56", "ubuntu-angie-php74", "ubuntu-angie-php80",
        "ubuntu-angie-php82", "ubuntu-angie-php84", "ubuntu-angie-php85",
        "ubuntu-angie-multi",
    ]
}

group "ubuntu-apache" {
    targets = [
        "ubuntu-apache-php56", "ubuntu-apache-php74", "ubuntu-apache-php80",
        "ubuntu-apache-php82", "ubuntu-apache-php84", "ubuntu-apache-php85",
        "ubuntu-apache-multiphp",
    ]
}

group "apache-misc" {
    targets = [
       "debian-roundcube"
    ]
}

group "mail" {
    targets = [
       "ubuntu-postfix", "debian-postfix", "debian-rspamd-git", "debian-rspamd", "debian-rspamd-official", "ubuntu-rspamd", "debian-rspamd-drp", "debian-dovecot", "debian-olefied", "debian-mailstrix", "debian-mailstrix-testing" ]
}

group "db" {
    targets = [
        "ubuntu-valkey", "debian-valkey", "ubuntu-mariadb", "debian-mariadb" ]
}

group "misc" {
    targets = [
       "alpine-letsencrypt", "rbldnsd", "ubuntu-reprepro", "debian-sitewarmup", "alpine-unbound", "aptly", "debian-openssh", "debian-webtest" ]
}

target "debian-angie-cms" {
    inherits = ["_meta"]
    dockerfile = "Dockerfile-deb"
    context = "src/docker-cms"
    # :debian-s6 is the tag the deployed myguard stack pins (docker-compose.yml).
    # The image is already s6-based, so it's the same content — keep the tag so
    # `compose pull` on the host tracks the daily rebuild.
    tags = ["docker.io/eilandert/angie-cms:debian", "docker.io/eilandert/angie-cms:debian-s6", "docker.io/eilandert/angie-cms:latest"]
    contexts = {
        "eilandert/angie:deb-php8.5" = "target:debian-angie-php85"
    }
}

target "ubuntu-base" {
    inherits = ["_meta"]
    dockerfile = "Dockerfile-ubuntu-base"
    context = "src/base"
    tags = ["docker.io/eilandert/ubuntu-base:rolling"]
}

target "debian-base" {
    inherits = ["_meta"]
    dockerfile = "Dockerfile-debian-base"
    context = "src/base"
    tags = ["docker.io/eilandert/debian-base:stable"]
}

target "ubuntu-multiphp" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/php-fpm:multi"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-multi-ubu"
    contexts = { "eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "debian-multiphp" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/php-fpm:deb-multi"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-multi-deb"
    contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}

target "debian-mariadb" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/mariadb:debian", "docker.io/eilandert/mariadb:latest"]
    context = "src/mariadb"
    dockerfile = "Dockerfile-deb"
    contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}

target "ubuntu-mariadb" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/mariadb:ubuntu"]
    context = "src/mariadb"
    dockerfile = "Dockerfile-ubu"
    contexts = { "eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "debian-nginx" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:deb-latest", "docker.io/eilandert/nginx:deb-latest"]
    context = "src/nginx"
    dockerfile = "Dockerfile-deb"
    contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}

target "ubuntu-nginx" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:latest", "docker.io/eilandert/nginx:latest"]
    context = "src/nginx"
    dockerfile = "Dockerfile-ubu"
    contexts = { "eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "ubuntu-nginx-multi" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:multi", "docker.io/eilandert/nginx:multi"]
    context = "src/nginx"
    dockerfile = "Dockerfile-multi-ubu"
    contexts = { "eilandert/php-fpm:multi" = "target:ubuntu-multiphp" }
}

target "debian-nginx-multi" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:deb-multi", "docker.io/eilandert/nginx:deb-multi"]
    context = "src/nginx"
    dockerfile = "Dockerfile-multi-deb"
    contexts = { "eilandert/php-fpm:deb-multi" = "target:debian-multiphp" }
}

target "debian-apache-multiphp" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/apache-phpfpm:deb-multi"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-multi-deb"
    contexts = { "eilandert/php-fpm:deb-multi" = "target:debian-multiphp" }
}

target "ubuntu-apache-multiphp" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/apache-phpfpm:multi"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-multi-ubu"
    contexts = { "eilandert/php-fpm:multi" = "target:ubuntu-multiphp" }
}



target "debian-dovecot" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/dovecot:debian", "docker.io/eilandert/dovecot:latest"]
   context = "src/dovecot-ubuntu"
   dockerfile = "Dockerfile-deb"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}

target "alpine-letsencrypt" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/letsencrypt"]
   context = "src/letsencrypt"
   dockerfile = "Dockerfile"
}

target "ubuntu-postfix" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/postfix:ubuntu", "docker.io/eilandert/postfix:latest"]
   context = "src/postfix"
   dockerfile = "Dockerfile-ubu"
   contexts = { "eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "debian-postfix" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/postfix:debian"]
   context = "src/postfix"
   dockerfile = "Dockerfile-deb"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}

target "rbldnsd" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/rbldnsd"]
   context = "src/rbldnsd"
   dockerfile = "Dockerfile"
}

target "ubuntu-valkey" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/valkey:ubuntu"]
   context = "src/valkey"
   dockerfile = "Dockerfile-ubu"
   contexts = { "eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "debian-valkey" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/valkey:debian"]
   context = "src/valkey"
   dockerfile = "Dockerfile-deb"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}

target "ubuntu-reprepro" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/reprepro"]
   context = "src/reprepro"
   dockerfile = "Dockerfile-ubu"
   contexts = { "eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "debian-roundcube" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/roundcube:debian", "docker.io/eilandert/roundcube:latest"]
   context = "src/roundcube"
   dockerfile = "Dockerfile"
   contexts = {
      "eilandert/debian-base:stable" = "target:debian-base"
      "skin-gmail"      = "src/roundcube/roundcube-skin-gmail"
      "skin-outlook365" = "src/roundcube/roundcube-skin-outlook365"
   }
}

# Website-tester. Standalone project (own git repo at ../labs/webtester), builds
# FROM debian:trixie-slim directly (no base-image target dependency). Pushes to
# the PRIVATE eilandert/webtest repo. Context lives outside the repo, so the
# build relies on BUILDX_BAKE_ENTITLEMENTS_FS=0 (set in buildx-sequential.sh).
target "debian-webtest" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/webtest:debian", "docker.io/eilandert/webtest:latest"]
   context = "../labs/webtester"
   dockerfile = "Dockerfile"
}

target "debian-rspamd-git" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/rspamd-git:latest"]
   context = "src/rspamd-git"
   dockerfile = "Dockerfile-deb-git"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}
target "debian-rspamd-official" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/rspamd-git:official"]
   context = "src/rspamd-git"
   dockerfile = "Dockerfile-deb-official"
}

target "debian-rspamd" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/rspamd-git:debian", "docker.io/eilandert/rspamd-git:release"]
   context = "src/rspamd-git"
   dockerfile = "Dockerfile-deb"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}
target "ubuntu-rspamd" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/rspamd-git:ubuntu"]
   context = "src/rspamd-git"
   dockerfile = "Dockerfile-ubu"
   contexts = { "eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

# DCC/Razor/Pyzor collaborative-filter backend for rspamd. Own git repo, vendored
# here as a submodule at src/rspamd-dcc-razor-pyzor (so a standalone dockerized
# clone + `git submodule update --init` builds it). A single static Go binary on
# a distroless base — no debian-base dependency.
target "debian-rspamd-drp" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/rspamd-dcc-razor-pyzor:debian", "docker.io/eilandert/rspamd-dcc-razor-pyzor:latest"]
   context = "src/rspamd-dcc-razor-pyzor/docker"
   dockerfile = "Dockerfile-deb"
}
# olefied — production olefy (oletools-over-TCP) for rspamd: pooled workers +
# scan timeout + backpressure. Own git repo (eilandert/rspamd-olefy), submodule at
# src/rspamd-olefy. Dockerfile pulls olefy.py + requirements.txt FRESH from upstream
# HeinleinSupport/olefy at build time, so CACHEBUST=${BUILD_DATE} makes the daily
# rebuild re-pull the latest. Built from the repo ROOT context (the Dockerfile
# COPYs docker/olefyd.py etc. from there), so context=src/rspamd-olefy.
target "debian-olefied" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/rspamd-olefy:debian", "docker.io/eilandert/rspamd-olefy:latest"]
   context = "src/rspamd-olefy"
   dockerfile = "docker/Dockerfile"
   args = { CACHEBUST = "${BUILD_DATE}" }
}
# yarad — YARA scanner backend for rspamd (rspamd has no native YARA module).
# Own git repo (myguard-labs/mailstrix), submodule at src/mailstrix. Go + libyara (CGO,
# static libyara), distroless. The image bakes public rulesets (YARA-Forge +
# signature-base + ANY.RUN) at build time, so CACHEBUST=${BUILD_DATE} makes the
# daily rebuild re-pull the latest rules. Built from the repo ROOT context.
target "debian-mailstrix" {
    inherits = ["_meta"]
   # Multi-arch from the GitHub release binaries (Dockerfile.release ADDs the
   # per-arch strixd/strix-scan by TARGETARCH, no Go/libyara compile under QEMU);
   # only the native yarac rules-compile runs emulated. The final image is
   # distroless (not a debian: image), so the old :debian tag was wrong and is
   # dropped — :latest + the version tag are a multi-arch manifest list.
   # Guard: an empty MAILSTRIX_RELEASE (release-race: gh release/tag not resolved
   # yet) must not emit a bare "mailstrix:" tag — that fails as "invalid reference
   # format". Fall back to :latest-only until a version is available.
   tags = notequal("", MAILSTRIX_RELEASE) ? ["docker.io/eilandert/mailstrix:latest", "docker.io/eilandert/mailstrix:${MAILSTRIX_RELEASE}"] : ["docker.io/eilandert/mailstrix:latest"]
   context = "src/mailstrix"
   dockerfile = "docker/Dockerfile.release"
   # VERSION = the release tag whose per-arch binaries Dockerfile.release pulls.
   args = { CACHEBUST = "${BUILD_DATE}", VERSION = "${MAILSTRIX_RELEASE}" }
}
# mailstrix:testing — the default branch (main) built from source, with the
# latest public rulesets at build time. The daily only rebuilds it when main has
# moved past the published image's revision label (buildx-sequential.sh;
# MAILSTRIX_TESTING_FORCE=1 overrides); strixd's own rules poll keeps a running
# container's rules fresh in between. :latest and
# :<version> above stay on the newest published release. Built straight from
# the public git repo, so it always tracks main and never the src/mailstrix pin.
# Compiles Go + static libyara on each target architecture; native ARM64 workers
# are preferable to QEMU for this source build.
target "debian-mailstrix-testing" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/mailstrix:testing"]
   context = "https://github.com/myguard-labs/mailstrix.git#${MAILSTRIX_MAIN_REF}"
   dockerfile = "docker/Dockerfile"
   target = "final"
   # The inherited revision label names the dockerized commit; this image is
   # built from mailstrix, so label it with the mailstrix commit instead.
   labels = { "org.opencontainers.image.revision" = MAILSTRIX_MAIN_REF, "org.opencontainers.image.source" = "https://github.com/myguard-labs/mailstrix" }
   args = { CACHEBUST = "${BUILD_DATE}", VERSION = "testing" }
}
target "debian-sitewarmup" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/sitemap_warmup"]
   context = "src/sitemap_warmup"
   dockerfile = "Dockerfile-deb"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}
target "alpine-unbound" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/unbound"]
   context = "src/unbound"
   dockerfile = "Dockerfile"
}
target "debian-vimbadmin" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/vimbadmin:debian", "docker.io/eilandert/vimbadmin:latest"]
   context = "src/vimbadmin"
   dockerfile = "Dockerfile"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}
target "debian-openssh" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/openssh:debian"]
   context = "src/openssh"
   dockerfile = "Dockerfile-deb"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}

target "aptly" {
    inherits = ["_meta"]
   tags = ["docker.io/eilandert/aptly"]
   context = "src/aptly"
   dockerfile = "Dockerfile"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}

target "debian-angie" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:deb-latest"]
    context = "src/angie"
    dockerfile = "Dockerfile-deb"
    contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}

target "ubuntu-angie" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:latest"]
    context = "src/angie"
    dockerfile = "Dockerfile-ubu"
    contexts = { "eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "ubuntu-angie-multi" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:multi"]
    context = "src/angie"
    dockerfile = "Dockerfile-multi-ubu"
    contexts = { "eilandert/php-fpm:multi" = "target:ubuntu-multiphp" }
}

target "debian-angie-multi" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:deb-multi"]
    context = "src/angie"
    dockerfile = "Dockerfile-multi-deb"
    contexts = { "eilandert/php-fpm:deb-multi" = "target:debian-multiphp" }
}

# Cache is applied per-invocation by the orchestrator via:
#   --set "*.cache-from=type=local,src=$CACHE_DIR"
#   --set "*.cache-to=type=local,dest=$CACHE_DIR,mode=max"
# The previous `common { output { ... } }` block was not valid bake syntax
# and silently did nothing — removed to avoid confusion.
