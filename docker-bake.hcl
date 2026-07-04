# Provenance / supply-chain build args. Override from the environment, e.g.:
#   VCS_REF=$(git rev-parse --short HEAD) BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ) \
#     docker buildx bake nginx --push
variable "VCS_REF"    { default = "unknown" }
variable "BUILD_DATE" { default = "unknown" }
# yarad's own source version (git describe of src/mailstrix), baked into the
# binary's main.version and surfaced on its /version endpoint. daily.sh exports
# it; defaults to "dev" for an ad-hoc build that doesn't set it.
variable "MAILSTRIX_VERSION" { default = "dev" }
# The nearest published release tag (e.g. 1.0.0), from `git describe --abbrev=0`.
# debian-mailstrix's Dockerfile.release downloads the per-arch release binaries
# from this tag and tags the image with it. Must name a release that has assets.
variable "MAILSTRIX_RELEASE" { default = "" }

# Shared metadata args. Targets inherit this to receive VCS_REF / BUILD_DATE
# without repeating the args block.
target "_meta" {
    args = {
        VCS_REF    = "${VCS_REF}"
        BUILD_DATE = "${BUILD_DATE}"
    }
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
       "ubuntu-postfix", "debian-postfix", "debian-rspamd-git", "debian-rspamd", "debian-rspamd-official", "ubuntu-rspamd", "debian-rspamd-drp", "debian-dovecot", "debian-olefied", "debian-mailstrix" ]
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
    dockerfile = "Dockerfile-deb"
    context = "src/docker-cms"
    # :debian-s6 is the tag the deployed myguard stack pins (docker-compose.yml).
    # The image is already s6-based, so it's the same content — keep the tag so
    # `compose pull` on the host tracks the daily rebuild.
    tags = ["docker.io/eilandert/angie-cms:debian", "docker.io/eilandert/angie-cms:debian-s6", "docker.io/eilandert/angie-cms:latest"]
    contexts = {
        "docker.io/eilandert/angie:deb-php8.5" = "target:debian-angie-php85"
    }
}

target "ubuntu-base" {
    dockerfile = "Dockerfile-ubuntu-base"
    context = "src/base"
    tags = ["docker.io/eilandert/ubuntu-base:rolling"]
}

target "debian-base" {
    dockerfile = "Dockerfile-debian-base"
    context = "src/base"
    tags = ["docker.io/eilandert/debian-base:stable"]
}

target "ubuntu-phpfpm56" {
    tags = ["docker.io/eilandert/php-fpm:5.6"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-56-ubu"
    inherits = ["ubuntu-base"]
    contexts = { "docker.io/eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "debian-phpfpm56" {
    tags = ["docker.io/eilandert/php-fpm:deb-5.6"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-56-deb"
    contexts = { "docker.io/eilandert/debian-base:stable" = "target:debian-base" }
}

target "ubuntu-phpfpm74" {
    tags = ["docker.io/eilandert/php-fpm:7.4"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-74-ubu"
    contexts = { "docker.io/eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "debian-phpfpm74" {
    tags = ["docker.io/eilandert/php-fpm:deb-7.4"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-74-deb"
    contexts = { "docker.io/eilandert/debian-base:stable" = "target:debian-base" }
}

target "ubuntu-phpfpm80" {
    tags = ["docker.io/eilandert/php-fpm:8.0", "docker.io/eilandert/php-fpm:latest"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-80-ubu"
    contexts = { "docker.io/eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "debian-phpfpm80" {
    tags = ["docker.io/eilandert/php-fpm:deb-8.0", "docker.io/eilandert/php-fpm:deb-latest"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-80-deb"
    contexts = { "docker.io/eilandert/debian-base:stable" = "target:debian-base" }
}

target "ubuntu-phpfpm82" {
    tags = ["docker.io/eilandert/php-fpm:8.2"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-82-ubu"
    contexts = { "docker.io/eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "debian-phpfpm82" {
    tags = ["docker.io/eilandert/php-fpm:deb-8.2"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-82-deb"
    contexts = { "docker.io/eilandert/debian-base:stable" = "target:debian-base" }
}

target "ubuntu-phpfpm84" {
    tags = ["docker.io/eilandert/php-fpm:8.4"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-84-ubu"
    contexts = { "docker.io/eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "debian-phpfpm84" {
    tags = ["docker.io/eilandert/php-fpm:deb-8.4"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-84-deb"
    contexts = { "docker.io/eilandert/debian-base:stable" = "target:debian-base" }
}

target "ubuntu-phpfpm85" {
    tags = ["docker.io/eilandert/php-fpm:8.5"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-85-ubu"
    contexts = { "docker.io/eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "debian-phpfpm85" {
    tags = ["docker.io/eilandert/php-fpm:deb-8.5"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-85-deb"
    contexts = { "docker.io/eilandert/debian-base:stable" = "target:debian-base" }
}

target "ubuntu-multiphp" {
    tags = ["docker.io/eilandert/php-fpm:multi"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-multi-ubu"
    contexts = { "docker.io/eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "debian-multiphp" {
    tags = ["docker.io/eilandert/php-fpm:deb-multi"]
    context = "src/php-fpm"
    dockerfile = "Dockerfile-multi-deb"
    contexts = { "docker.io/eilandert/debian-base:stable" = "target:debian-base" }
}

target "debian-mariadb" {
    tags = ["docker.io/eilandert/mariadb:debian", "docker.io/eilandert/mariadb:latest"]
    context = "src/mariadb"
    dockerfile = "Dockerfile-deb"
    contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}

target "ubuntu-mariadb" {
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
    contexts = { "docker.io/eilandert/debian-base:stable" = "target:debian-base" }
}

target "ubuntu-nginx" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:latest", "docker.io/eilandert/nginx:latest"]
    context = "src/nginx"
    dockerfile = "Dockerfile-ubu"
    contexts = { "docker.io/eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "ubuntu-nginx-php56" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:php5.6", "docker.io/eilandert/nginx:php5.6"]
    context = "src/nginx"
    dockerfile = "Dockerfile-php56-ubu"
    contexts = { "docker.io/eilandert/php-fpm:5.6" = "target:ubuntu-phpfpm56" }
}

target "debian-nginx-php56" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:deb-php5.6", "docker.io/eilandert/nginx:deb-php5.6"]
    context = "src/nginx"
    dockerfile = "Dockerfile-php56-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-5.6" = "target:debian-phpfpm56" }
}

target "ubuntu-nginx-php74" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:php7.4", "docker.io/eilandert/nginx:php7.4"]
    context = "src/nginx"
    dockerfile = "Dockerfile-php74-ubu"
    contexts = { "docker.io/eilandert/php-fpm:7.4" = "target:ubuntu-phpfpm74" }
}

target "debian-nginx-php74" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:deb-php7.4", "docker.io/eilandert/nginx:deb-php7.4"]
    context = "src/nginx"
    dockerfile = "Dockerfile-php74-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-7.4" = "target:debian-phpfpm74" }
}

target "ubuntu-nginx-php80" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:php8.0", "docker.io/eilandert/nginx:php8.0"]
    context = "src/nginx"
    dockerfile = "Dockerfile-php80-ubu"
    contexts = { "docker.io/eilandert/php-fpm:8.0" = "target:ubuntu-phpfpm80" }
}

target "debian-nginx-php80" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:deb-php8.0", "docker.io/eilandert/nginx:deb-php8.0"]
    context = "src/nginx"
    dockerfile = "Dockerfile-php80-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-8.0" = "target:debian-phpfpm80" }
}

target "ubuntu-nginx-php82" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:php8.2", "docker.io/eilandert/nginx:php8.2"]
    context = "src/nginx"
    dockerfile = "Dockerfile-php82-ubu"
    contexts = { "docker.io/eilandert/php-fpm:8.2" = "target:ubuntu-phpfpm82" }
}

target "debian-nginx-php82" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:deb-php8.2", "docker.io/eilandert/nginx:deb-php8.2"]
    context = "src/nginx"
    dockerfile = "Dockerfile-php82-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-8.2" = "target:debian-phpfpm82" }
}

target "ubuntu-nginx-php84" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:php8.4", "docker.io/eilandert/nginx:php8.4"]
    context = "src/nginx"
    dockerfile = "Dockerfile-php84-ubu"
    contexts = { "docker.io/eilandert/php-fpm:8.4" = "target:ubuntu-phpfpm84" }
}

target "debian-nginx-php84" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:deb-php8.4", "docker.io/eilandert/nginx:deb-php8.4"]
    context = "src/nginx"
    dockerfile = "Dockerfile-php84-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-8.4" = "target:debian-phpfpm84" }
}

target "ubuntu-nginx-php85" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:php8.5", "docker.io/eilandert/nginx:php8.5"]
    context = "src/nginx"
    dockerfile = "Dockerfile-php85-ubu"
    contexts = { "docker.io/eilandert/php-fpm:8.5" = "target:ubuntu-phpfpm85" }
}

target "debian-nginx-php85" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:deb-php8.5", "docker.io/eilandert/nginx:deb-php8.5"]
    context = "src/nginx"
    dockerfile = "Dockerfile-php85-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-8.5" = "target:debian-phpfpm85" }
}

target "ubuntu-nginx-multi" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:multi", "docker.io/eilandert/nginx:multi"]
    context = "src/nginx"
    dockerfile = "Dockerfile-multi-ubu"
    contexts = { "docker.io/eilandert/php-fpm:multi" = "target:ubuntu-multiphp" }
}

target "debian-nginx-multi" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/nginx-modsecurity3-pagespeed:deb-multi", "docker.io/eilandert/nginx:deb-multi"]
    context = "src/nginx"
    dockerfile = "Dockerfile-multi-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-multi" = "target:debian-multiphp" }
}

target "debian-apache-php56" {
    tags = ["docker.io/eilandert/apache-phpfpm:deb-5.6"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-56-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-5.6" = "target:debian-phpfpm56" }
}

target "debian-apache-php74" {
    tags = ["docker.io/eilandert/apache-phpfpm:deb-7.4"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-74-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-7.4" = "target:debian-phpfpm74" }
}

target "debian-apache-php80" {
    tags = ["docker.io/eilandert/apache-phpfpm:deb-8.0", "docker.io/eilandert/apache-phpfpm:deb-latest"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-80-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-8.0" = "target:debian-phpfpm80" }
}

target "debian-apache-php82" {
    tags = ["docker.io/eilandert/apache-phpfpm:deb-8.2"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-82-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-8.2" = "target:debian-phpfpm82" }
}

target "debian-apache-php84" {
    tags = ["docker.io/eilandert/apache-phpfpm:deb-8.4"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-84-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-8.4" = "target:debian-phpfpm84" }
}

target "debian-apache-php85" {
    tags = ["docker.io/eilandert/apache-phpfpm:deb-8.5"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-85-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-8.5" = "target:debian-phpfpm85" }
}

target "debian-apache-multiphp" {
    tags = ["docker.io/eilandert/apache-phpfpm:deb-multi"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-multi-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-multi" = "target:debian-multiphp" }
}

target "ubuntu-apache-php56" {
    tags = ["docker.io/eilandert/apache-phpfpm:5.6"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-56-ubu"
    contexts = { "docker.io/eilandert/php-fpm:5.6" = "target:ubuntu-phpfpm56" }
}

target "ubuntu-apache-php74" {
    tags = ["docker.io/eilandert/apache-phpfpm:7.4"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-74-ubu"
    contexts = { "docker.io/eilandert/php-fpm:7.4" = "target:ubuntu-phpfpm74" }
}

target "ubuntu-apache-php80" {
    tags = ["docker.io/eilandert/apache-phpfpm:8.0", "docker.io/eilandert/apache-phpfpm:latest"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-80-ubu"
    contexts = { "docker.io/eilandert/php-fpm:8.0" = "target:ubuntu-phpfpm80" }
}

target "ubuntu-apache-php82" {
    tags = ["docker.io/eilandert/apache-phpfpm:8.2"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-82-ubu"
    contexts = { "docker.io/eilandert/php-fpm:8.2" = "target:ubuntu-phpfpm82" }
}

target "ubuntu-apache-php84" {
    tags = ["docker.io/eilandert/apache-phpfpm:8.4"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-84-ubu"
    contexts = { "docker.io/eilandert/php-fpm:8.4" = "target:ubuntu-phpfpm84" }
}

target "ubuntu-apache-php85" {
    tags = ["docker.io/eilandert/apache-phpfpm:8.5"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-85-ubu"
    contexts = { "docker.io/eilandert/php-fpm:8.5" = "target:ubuntu-phpfpm85" }
}

target "ubuntu-apache-multiphp" {
    tags = ["docker.io/eilandert/apache-phpfpm:multi"]
    context = "src/apache-phpfpm"
    dockerfile = "Dockerfile-multi-ubu"
    contexts = { "docker.io/eilandert/php-fpm:multi" = "target:ubuntu-multiphp" }
}



target "debian-dovecot" {
   tags = ["docker.io/eilandert/dovecot:debian", "docker.io/eilandert/dovecot:latest"]
   context = "src/dovecot-ubuntu"
   dockerfile = "Dockerfile-deb"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}

target "alpine-letsencrypt" {
   tags = ["docker.io/eilandert/letsencrypt"]
   context = "src/letsencrypt"
   dockerfile = "Dockerfile"
}

target "ubuntu-postfix" {
   tags = ["docker.io/eilandert/postfix:ubuntu", "docker.io/eilandert/postfix:latest"]
   context = "src/postfix"
   dockerfile = "Dockerfile-ubu"
   contexts = { "eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "debian-postfix" {
   tags = ["docker.io/eilandert/postfix:debian"]
   context = "src/postfix"
   dockerfile = "Dockerfile-deb"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}

target "rbldnsd" {
   tags = ["docker.io/eilandert/rbldnsd"]
   context = "src/rbldnsd"
   dockerfile = "Dockerfile"
}

target "ubuntu-valkey" {
   tags = ["docker.io/eilandert/valkey:ubuntu"]
   context = "src/valkey"
   dockerfile = "Dockerfile-ubu"
   contexts = { "eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "debian-valkey" {
   tags = ["docker.io/eilandert/valkey:debian"]
   context = "src/valkey"
   dockerfile = "Dockerfile-deb"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}

target "ubuntu-reprepro" {
   tags = ["docker.io/eilandert/reprepro"]
   context = "src/reprepro"
   dockerfile = "Dockerfile-ubu"
   contexts = { "eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "debian-roundcube" {
   tags = ["docker.io/eilandert/roundcube:debian", "docker.io/eilandert/roundcube:latest"]
   context = "src/roundcube"
   dockerfile = "Dockerfile"
   contexts = {
      "eilandert/debian-base:stable" = "target:debian-base"
      "skin-gmail"      = "src/roundcube/roundcube-skin-gmail"
      "skin-outlook365" = "src/roundcube/roundcube-skin-outlook365"
   }
}

# Website-tester. Standalone project (own git repo at ../webtester), builds
# FROM debian:trixie-slim directly (no base-image target dependency). Pushes to
# the PRIVATE eilandert/webtest repo. Context lives outside the repo, so the
# build relies on BUILDX_BAKE_ENTITLEMENTS_FS=0 (set in buildx-sequential.sh).
target "debian-webtest" {
   tags = ["docker.io/eilandert/webtest:debian", "docker.io/eilandert/webtest:latest"]
   context = "../webtester"
   dockerfile = "Dockerfile"
}

target "debian-rspamd-git" {
   tags = ["docker.io/eilandert/rspamd-git:latest"]
   context = "src/rspamd-git"
   dockerfile = "Dockerfile-deb-git"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}
target "debian-rspamd-official" {
   tags = ["docker.io/eilandert/rspamd-git:official"]
   context = "src/rspamd-git"
   dockerfile = "Dockerfile-deb-official"
}

target "debian-rspamd" {
   tags = ["docker.io/eilandert/rspamd-git:debian", "docker.io/eilandert/rspamd-git:release"]
   context = "src/rspamd-git"
   dockerfile = "Dockerfile-deb"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}
target "ubuntu-rspamd" {
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
   tags = ["docker.io/eilandert/rspamd-olefy:debian", "docker.io/eilandert/rspamd-olefy:latest"]
   context = "src/rspamd-olefy"
   dockerfile = "docker/Dockerfile"
   args = { CACHEBUST = "${BUILD_DATE}" }
}
# yarad — YARA scanner backend for rspamd (rspamd has no native YARA module).
# Own git repo (eilandert/mailstrix), submodule at src/mailstrix. Go + libyara (CGO,
# static libyara), distroless. The image bakes public rulesets (YARA-Forge +
# signature-base + ANY.RUN) at build time, so CACHEBUST=${BUILD_DATE} makes the
# daily rebuild re-pull the latest rules. Built from the repo ROOT context.
target "debian-mailstrix" {
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
   platforms = ["linux/amd64", "linux/arm64"]
   # VERSION = the release tag whose per-arch binaries Dockerfile.release pulls.
   args = { CACHEBUST = "${BUILD_DATE}", VERSION = "${MAILSTRIX_RELEASE}" }
}
target "debian-sitewarmup" {
   tags = ["docker.io/eilandert/sitemap_warmup"]
   context = "src/sitemap_warmup"
   dockerfile = "Dockerfile-deb"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}
target "alpine-unbound" {
   tags = ["docker.io/eilandert/unbound"]
   context = "src/unbound"
   dockerfile = "Dockerfile"
}
target "debian-vimbadmin" {
   tags = ["docker.io/eilandert/vimbadmin:debian", "docker.io/eilandert/vimbadmin:latest"]
   context = "src/vimbadmin"
   dockerfile = "Dockerfile"
   contexts = { "docker.io/eilandert/debian-base:stable" = "target:debian-base" }
}
target "psol" {
   tags = ["docker.io/eilandert/psol"]
   context = "src/psol-build"
   dockerfile = "Dockerfile-ubu"
}

target "debian-openssh" {
   tags = ["docker.io/eilandert/openssh:debian"]
   context = "src/openssh"
   dockerfile = "Dockerfile-deb"
   contexts = { "eilandert/debian-base:stable" = "target:debian-base" }
}

target "aptly" {
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
    contexts = { "docker.io/eilandert/debian-base:stable" = "target:debian-base" }
}

target "ubuntu-angie" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:latest"]
    context = "src/angie"
    dockerfile = "Dockerfile-ubu"
    contexts = { "docker.io/eilandert/ubuntu-base:rolling" = "target:ubuntu-base" }
}

target "ubuntu-angie-php56" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:php5.6"]
    context = "src/angie"
    dockerfile = "Dockerfile-php56-ubu"
    contexts = { "docker.io/eilandert/php-fpm:5.6" = "target:ubuntu-phpfpm56" }
}

target "debian-angie-php56" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:deb-php5.6"]
    context = "src/angie"
    dockerfile = "Dockerfile-php56-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-5.6" = "target:debian-phpfpm56" }
}

target "ubuntu-angie-php74" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:php7.4"]
    context = "src/angie"
    dockerfile = "Dockerfile-php74-ubu"
    contexts = { "docker.io/eilandert/php-fpm:7.4" = "target:ubuntu-phpfpm74" }
}

target "debian-angie-php74" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:deb-php7.4"]
    context = "src/angie"
    dockerfile = "Dockerfile-php74-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-7.4" = "target:debian-phpfpm74" }
}

target "ubuntu-angie-php80" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:php8.0"]
    context = "src/angie"
    dockerfile = "Dockerfile-php80-ubu"
    contexts = { "docker.io/eilandert/php-fpm:8.0" = "target:ubuntu-phpfpm80" }
}

target "debian-angie-php80" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:deb-php8.0"]
    context = "src/angie"
    dockerfile = "Dockerfile-php80-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-8.0" = "target:debian-phpfpm80" }
}

target "ubuntu-angie-php82" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:php8.2"]
    context = "src/angie"
    dockerfile = "Dockerfile-php82-ubu"
    contexts = { "docker.io/eilandert/php-fpm:8.2" = "target:ubuntu-phpfpm82" }
}

target "debian-angie-php82" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:deb-php8.2"]
    context = "src/angie"
    dockerfile = "Dockerfile-php82-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-8.2" = "target:debian-phpfpm82" }
}

target "ubuntu-angie-php84" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:php8.4"]
    context = "src/angie"
    dockerfile = "Dockerfile-php84-ubu"
    contexts = { "docker.io/eilandert/php-fpm:8.4" = "target:ubuntu-phpfpm84" }
}

target "debian-angie-php84" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:deb-php8.4"]
    context = "src/angie"
    dockerfile = "Dockerfile-php84-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-8.4" = "target:debian-phpfpm84" }
}

target "ubuntu-angie-php85" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:php8.5"]
    context = "src/angie"
    dockerfile = "Dockerfile-php85-ubu"
    contexts = { "docker.io/eilandert/php-fpm:8.5" = "target:ubuntu-phpfpm85" }
}

target "debian-angie-php85" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:deb-php8.5"]
    context = "src/angie"
    dockerfile = "Dockerfile-php85-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-8.5" = "target:debian-phpfpm85" }
}

target "ubuntu-angie-multi" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:multi"]
    context = "src/angie"
    dockerfile = "Dockerfile-multi-ubu"
    contexts = { "docker.io/eilandert/php-fpm:multi" = "target:ubuntu-multiphp" }
}

target "debian-angie-multi" {
    inherits = ["_meta"]
    tags = ["docker.io/eilandert/angie:deb-multi"]
    context = "src/angie"
    dockerfile = "Dockerfile-multi-deb"
    contexts = { "docker.io/eilandert/php-fpm:deb-multi" = "target:debian-multiphp" }
}

# Cache is applied per-invocation by the orchestrator via:
#   --set "*.cache-from=type=local,src=$CACHE_DIR"
#   --set "*.cache-to=type=local,dest=$CACHE_DIR,mode=max"
# The previous `common { output { ... } }` block was not valid bake syntax
# and silently did nothing — removed to avoid confusion.
