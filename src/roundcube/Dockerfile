# syntax=docker/dockerfile:1.7
# This file might be outdated, see https://github.com/myguard-labs/dockerized/tree/master/roundcube for a recent one
#
# Roundcube webmail, hardened.
#   * base   : eilandert/debian-base:stable (Debian trixie, already hardened,
#              already carries the deb.myguard.nl apt repo + GPG key)
#   * php    : 8.5 FPM from the ondrej PPA mirror (edge.deb.myguard.nl)
#   * waf    : php8.5-snuffleupagus from the myguard repo (strict roundcube.rules)
#   * httpd  : angie-minimal, single merged config, listens on :8080 so the
#              container can run with ALL capabilities dropped (no privileged
#              port bind needed).
#   * users  : single unprivileged user `roundcube` (uid 10001) for both the
#              angie master and php-fpm. The container runs `USER roundcube`,
#              cap_drop ALL, read-only rootfs. Application code is owned
#              roundcube:roundcube 0440/0550 (read-only to the runtime user);
#              the only writable paths are the mounted runtime dirs.

FROM    eilandert/debian-base:stable
LABEL   org.opencontainers.image.authors="eilandert" \
        org.opencontainers.image.source="https://github.com/myguard-labs/dockerized" \
        org.opencontainers.image.title="Roundcube" \
        org.opencontainers.image.description="Hardened Roundcube webmail (PHP 8.5 FPM + Snuffleupagus + Angie)" \
        maintainer="Thijs Eilander <eilander@myguard.nl>"

# LD_PRELOAD is explicitly cleared below: do NOT inherit a mallocator preload
# (mimalloc) from the base image — the PHP-FPM/Angie stack runs on the stock
# glibc allocator in this image.
ENV     DEBIAN_FRONTEND="noninteractive" \
        INSTALLDIR="/var/www/html" \
        PHPVERSION="8.5" \
        COMPOSER_ALLOW_SUPERUSER=1 \
        LD_PRELOAD=""

# version is generated into .lastversion by the docker build script
COPY    .lastversion /tmp/lastversion

# s6-overlay supervises the runtime (PID1 reaps + restarts php-fpm/angie; a
# kill -9'd php-fpm master is respawned in ~1s). The old monolithic bootstrap.sh
# is split: one-time setup -> the s6 'init-bootstrap' oneshot; php-fpm, angie and
# fpm-watch are s6 longruns. Runs ROOTLESS (uid 10001, S6_READ_ONLY_ROOT=1), so
# cap_drop ALL + read-only rootfs are preserved.
ARG     S6_OVERLAY_VERSION=3.2.1.0
COPY --chmod=0755 healthcheck.sh /healthcheck.sh
COPY    s6-rc.d/ /etc/s6-overlay/s6-rc.d/
COPY --chmod=0755 s6-scripts/init-bootstrap.sh /etc/s6-overlay/scripts/init-bootstrap.sh

# ---------------------------------------------------------------------------
# 1. APT repos + runtime packages
#    The myguard repo (php8.5-snuffleupagus, angie) is inherited from the base
#    image. We only need to add the ondrej PHP mirror for the php8.5-* stack.
#    opcache ships inside php8.5-common (ondrej), so it is NOT a separate dep.
# ---------------------------------------------------------------------------
# Baked configs staged outside the package conffile paths — moved into place
# INSIDE the build RUN, after apt install, so dpkg never sees a pre-existing
# /etc/angie/angie.conf or pool.d/www.conf and never raises a conffile prompt.
COPY angie.conf  /usr/local/share/roundcube/angie.conf
COPY phpfpm.conf /usr/local/share/roundcube/www.conf
# Strict, source-audited Roundcube Snuffleupagus rulebook. Shipped here so the
# image carries it even before the php-snuffleupagus .deb (which also ships it)
# is rebuilt+republished. Moved into place inside the build RUN, after the
# package is installed, so it overwrites the packaged copy.
COPY roundcube.rules /usr/local/share/roundcube/roundcube.rules

# Local custom skins (live outside this build context; wired in as named build
# contexts in docker-bake.hcl). Staged here, installed into skins/ inside the
# build RUN after Roundcube is extracted. Both `extends: elastic`.
COPY --from=skin-gmail      . /usr/local/share/roundcube-skins/gmail/
COPY --from=skin-outlook365 . /usr/local/share/roundcube-skins/outlook365/

# ---------------------------------------------------------------------------
# Everything in ONE layer: install runtime + transient build tooling, fetch
# Roundcube + composer deps + pinned plugins, wire config, then purge ALL the
# build tooling and caches and chown — all before the layer is committed, so
# nothing transient (git/curl/composer/apt lists/composer cache) survives into
# the image. Single user model: angie + php-fpm both run as `roundcube`.
# ---------------------------------------------------------------------------
RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    --mount=type=cache,target=/root/.composer/cache,sharing=locked \
    set -eux ;\
    LASTVERSION="$(cat /tmp/lastversion)" ;\
    export COMPOSER_ROOT_VERSION="${LASTVERSION}" COMPOSER_NO_INTERACTION=1 ;\
    # ---- repos + packages (runtime + transient build tooling) ----
    # http transport (the mirror has no https on :8888) but the Release IS GPG
    # signed by the same MyGuard key the base image ships at
    # /usr/share/keyrings/deb.myguard.nl.gpg, so verify the signature instead of
    # [trusted=yes] — apt then rejects any MITM-tampered package.
    echo "deb [signed-by=/usr/share/keyrings/deb.myguard.nl.gpg] http://edge.deb.myguard.nl:8888/mirror/ondrej-php ${DIST} main" \
        > /etc/apt/sources.list.d/ondrej-ppa.list ;\
    apt-get update ;\
    apt-get install -y --no-install-recommends \
        angie-minimal \
        php${PHPVERSION}-fpm php${PHPVERSION}-apcu php${PHPVERSION}-bz2 \
        php${PHPVERSION}-curl \
        php${PHPVERSION}-gd php${PHPVERSION}-gmp php${PHPVERSION}-imap \
        php${PHPVERSION}-intl php${PHPVERSION}-ldap php${PHPVERSION}-mbstring \
        php${PHPVERSION}-mysql php${PHPVERSION}-readline php${PHPVERSION}-redis \
        php${PHPVERSION}-snuffleupagus php${PHPVERSION}-xml php${PHPVERSION}-zip \
        aspell aspell-en aspell-nl hunspell-en-us \
        dictionaries-common enchant-2 libonig5 dbconfig-no-thanks \
        git unzip curl xz-utils ca-certificates locales ;\
    # ---- composer (transient) ----
    php -r "copy('https://getcomposer.org/installer', '/tmp/composer-setup.php');" ;\
    php /tmp/composer-setup.php --filename=composer --install-dir=/usr/bin ;\
    rm -f /tmp/composer-setup.php ;\
    # ---- move baked configs into place now that the packages are installed ----
    mv /usr/local/share/roundcube/angie.conf /etc/angie/angie.conf ;\
    mv /usr/local/share/roundcube/www.conf  "/etc/php/${PHPVERSION}/fpm/pool.d/www.conf" ;\
    mv /usr/local/share/roundcube/roundcube.rules \
       "/etc/php/${PHPVERSION}/php-snuffleupagus/roundcube.rules" ;\
    rmdir /usr/local/share/roundcube ;\
    # ---- Roundcube core + composer deps ----
    rm -rf "${INSTALLDIR}" ; mkdir -p "${INSTALLDIR}" ;\
    curl -fSL --retry 5 --retry-all-errors --retry-delay 2 \
        "https://github.com/roundcube/roundcubemail/releases/download/${LASTVERSION}/roundcubemail-${LASTVERSION}-complete.tar.gz" \
        | tar xz --strip-components=1 -C "${INSTALLDIR}" ;\
    cd "${INSTALLDIR}" ;\
    # RC <=1.6 ships composer.json-dist; RC 1.7+ ships composer.json directly.
    [ -f composer.json-dist ] && mv composer.json-dist composer.json || true ;\
    # Pull elastic4mobile from the eilandert fork, NOT upstream. The fork keeps
    # the upstream composer name `roundcube/elastic4mobile`, so without this VCS
    # repo composer would resolve it off plugins.roundcube.net (upstream). A repo
    # entry sources it from the fork git; dev-master then comes from the fork.
    composer config repositories.elastic4mobile vcs \
        https://github.com/eilandert/roundcube-elastic4mobile ;\
    composer -n update --no-dev --no-scripts --no-autoloader ;\
    # All extra deps in ONE require: a single dependency solve instead of six.
    # (-W lets transitive constraints upgrade; --no-scripts skips package post
    # hooks; --no-autoloader is NOT a require option, so the authoritative
    # classmap is generated once at the end instead.)
    composer -n require -W --no-scripts \
        roundcube/elastic4mobile:dev-master \
        alexandregz/twofactor_gauthenticator:dev-master \
        texxasrulez/scheduled_sending \
        roundcube/customizr \
        foorschtbar/dovecot_client_ip \
        roundcube/carddav ;\
    # ---- pinned third-party plugins (downloaded in parallel) ----
    # fetch <dir> <url> : grab + extract a release tarball. Runs in the
    # background; all downloads happen concurrently, then we `wait`.
    fetch() { \
        name="$1" ; url="$2" ; tmp="$(mktemp)" ; mkdir -p "${name}" ; \
        curl -fSL --retry 5 --retry-all-errors --retry-delay 2 -o "$tmp" "$url" ; \
        tar xz --strip-components=1 -C "${name}" -f "$tmp" ; rm -f "$tmp" ; \
    } ;\
    fetch plugins/contextmenu        https://github.com/johndoh/roundcube-contextmenu/archive/refs/tags/3.3.1.tar.gz & \
    fetch plugins/swipe              https://github.com/johndoh/roundcube-swipe/archive/refs/tags/0.6.tar.gz & \
    fetch plugins/show_folder_size   https://github.com/jfcherng-roundcube/plugin-show-folder-size/archive/refs/tags/0.7.22.tar.gz & \
    fetch plugins/quota              https://github.com/jfcherng-roundcube/plugin-quota/archive/55c0f3295e4db3c0f4ae6425ce498e58163695a7.tar.gz & \
    fetch plugins/persistent_login   https://github.com/texxasrulez/persistent_login/archive/refs/tags/1.0.3.tar.gz & \
    fetch plugins/identity_switch    https://github.com/toteph42/identity_switch/archive/refs/tags/3.0.5.tar.gz & \
    fetch plugins/advanced_search    https://github.com/texxasrulez/advanced_search/archive/refs/tags/3.7.tar.gz & \
    fetch plugins/account_details    https://github.com/texxasrulez/account_details/archive/refs/tags/5.0.0.tar.gz & \
    fetch plugins/message_highlight  https://github.com/texxasrulez/message_highlight/archive/refs/tags/1.0.5.tar.gz & \
    fetch plugins/authres            https://github.com/pimlie/authres_status/archive/refs/tags/0.7.1.tar.gz & \
    fetch plugins/thunderbird_labels https://github.com/mike-kfed/rcmail-thunderbird-labels/archive/refs/tags/v1.6.2.tar.gz & \
    fetch plugins/responses          https://github.com/random-cuber/responses/archive/refs/tags/1.3.13.tar.gz & \
    fetch plugins/contextmenu_folder https://github.com/random-cuber/contextmenu_folder/archive/refs/tags/2.0.2.tar.gz & \
    fetch plugins/easy_unsubscribe   https://github.com/SS88UK/roundcube-easy-unsubscribe/archive/b3ef43f9211cc32c2738c34e3dc1de60c9fc1aa3.tar.gz & \
    fetch plugins/rcguard            https://github.com/dsoares/roundcube-rcguard/archive/refs/tags/1.3.2.tar.gz & \
    # Skins pinned to commit SHAs (not moving master/main) for reproducible
    # builds — bump these deliberately. SHAs captured 2026-06-16.
    fetch skins/larry        https://github.com/roundcube/larry/archive/03ccd350bc1035378798468396d824c282b28d7b.tar.gz & \
    fetch skins/classic      https://github.com/roundcube/classic/archive/790857d8f5ec85c6057132b2e075bf263d2630d5.tar.gz & \
    fetch skins/elastic-dark https://github.com/tborychowski/elastic-dark/archive/025201f605d817f6ff117ee7ce8910aa0b7511ba.tar.gz & \
    fetch skins/elastic2025  https://github.com/bijanbina/Elastic2025/archive/e54548a6feb339849288ee4bbe456c459112f70d.tar.gz & \
    wait ;\
    # ---- quota plugin: guard undefined 'percent' key ----
    # jfcherng plugin-quota reads $args['percent'] in quota_message() even when
    # the IMAP server returns no QUOTA (unlimited mailbox) and the key is unset,
    # spamming "Undefined array key percent" PHP warnings. Default to 0.
    sed -ri "s/\\\$args\\['percent'\\] >= \\\$percent/(\\\$args['percent'] ?? 0) >= \\\$percent/" \
        plugins/quota/quota.php ;\
    # Local custom skins staged by the COPY above (drop README/thumbnail-only
    # cruft is fine; both extend elastic which is present).
    cp -a /usr/local/share/roundcube-skins/gmail      skins/gmail ;\
    cp -a /usr/local/share/roundcube-skins/outlook365 skins/outlook365 ;\
    rm -rf /usr/local/share/roundcube-skins ;\
    # One optimized autoload generation for the whole install (the per-plugin
    # `composer upgrade` loop was redundant — plugins ship their own deps via
    # the core composer.json, and re-solving 16× was the build's slowest step).
    # Authoritative classmap: best runtime perf on a read-only image where the
    # code never changes (no per-request filesystem stat; -a implies --optimize).
    composer -n dump-autoload --classmap-authoritative --no-dev ;\
    # ---- wire php-fpm config ----
    rm -f "/etc/php/${PHPVERSION}/fpm/pool.d/www.conf.dpkg-dist" ;\
    printf '\ninclude=/var/roundcube/config/phpfpm.conf.override\n' \
        >> "/etc/php/${PHPVERSION}/fpm/pool.d/www.conf" ;\
    sed -ri \
        -e 's@^;?\s*error_log\s*=.*@error_log = /proc/self/fd/2@' \
        -e 's@^;?\s*pid\s*=.*@;pid = (disabled: --nodaemonize)@' \
        -e 's@^;?\s*daemonize\s*=.*@daemonize = no@' \
        "/etc/php/${PHPVERSION}/fpm/php-fpm.conf" ;\
    # ---- php.ini upload limits (match phpfpm.conf pool settings) ----
    sed -ri \
        -e 's@^upload_max_filesize\s*=.*@upload_max_filesize = 25M@' \
        -e 's@^post_max_size\s*=.*@post_max_size = 32M@' \
        "/etc/php/${PHPVERSION}/fpm/php.ini" ;\
    # ---- Snuffleupagus: give the CLI SAPI an empty rulebook ----
    # The package symlinks the SP extension into BOTH fpm/ and cli/ conf.d, but
    # only the FPM pool sets sp.configuration_file (via php_admin_value). The CLI
    # scripts bootstrap runs (initdb/gc/deluser) therefore load SP with no
    # rulebook -> "No configuration specified via sp.configuration_file" warning.
    # SP has no on/off flag (only sp.configuration_file), so point the CLI at an
    # EMPTY rules file: loads cleanly, applies zero rules (CLI is trusted
    # bootstrap, not request-facing -- it does not need request hardening, and
    # the request rulebook could block legitimate CLI DB ops).
    : > "/etc/php/${PHPVERSION}/php-snuffleupagus/cli-empty.rules" ;\
    printf 'sp.configuration_file=/etc/php/%s/php-snuffleupagus/cli-empty.rules\n' "${PHPVERSION}" \
        > "/etc/php/${PHPVERSION}/cli/conf.d/99-snuffleupagus-cli.ini" ;\
    # ---- s6-overlay (rootless PID1 supervisor) ----
    # Fetch the noarch + per-arch tarballs and unpack to /. dpkg arch -> s6 arch.
    S6_ARCH="$(dpkg --print-architecture)" ;\
    case "${S6_ARCH}" in amd64) S6_ARCH=x86_64 ;; arm64) S6_ARCH=aarch64 ;; armhf) S6_ARCH=arm ;; esac ;\
    curl -fsSL -o /tmp/s6-noarch.tar.xz "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-noarch.tar.xz" ;\
    curl -fsSL -o /tmp/s6-arch.tar.xz   "https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}/s6-overlay-${S6_ARCH}.tar.xz" ;\
    tar -C / -Jxpf /tmp/s6-noarch.tar.xz ;\
    tar -C / -Jxpf /tmp/s6-arch.tar.xz ;\
    rm -f /tmp/s6-noarch.tar.xz /tmp/s6-arch.tar.xz ;\
    chmod 0755 /etc/s6-overlay/s6-rc.d/php-fpm/run \
               /etc/s6-overlay/s6-rc.d/angie/run \
               /etc/s6-overlay/s6-rc.d/fpm-watch/run \
               /etc/s6-overlay/scripts/init-bootstrap.sh ;\
    # ---- strip cruft: build tooling, app dev/test/docs, vendor tests/docs ----
    cd "${INSTALLDIR}" ;\
    rm -rf installer .ci .tx .git* .travis.yml CHANGELOG.md UPGRADING INSTALL \
           LICENSE README.md SECURITY.md tests public_html/index.html index.html \
           plugins/*/.git* plugins/*/tests plugins/*/.github ;\
    # `|| true`: -prune+rm makes find revisit deleted dirs and exit non-zero,
    # which would trip `set -e`; the deletion still happens.
    find vendor -type d \( -iname tests -o -iname test -o -iname doc -o -iname docs \
           -o -iname examples -o -iname '.github' \) -prune -exec rm -rf {} + || true ;\
    find vendor plugins -type f \( -iname '*.md' -o -iname '*.dist' -o -iname '.gitignore' \
           -o -iname '.gitattributes' -o -iname 'phpunit*.xml*' -o -iname '*.map' \) -delete || true ;\
    # Keep curl: the runtime healthcheck + fpm-watch use it (loopback healthz).
    apt-get purge -y git git-man unzip xz-utils ;\
    apt-get autoremove -y ;\
    rm -f /usr/bin/composer ;\
    # NB: /root/.composer/cache is a BuildKit cache MOUNT — removing the
    # mountpoint itself errors "Device or resource busy", and it never lands in
    # the image anyway. Only clear what is actually on the layer.
    rm -rf /root/.cache /var/lib/apt/lists/* /tmp/* \
           /etc/apt/sources.list.d/ondrej-ppa.list ;\
    # ---- single non-root runtime user + ownership (one chown pass) ----
    addgroup --system --gid 10001 roundcube ;\
    adduser  --system --uid 10001 --gid 10001 --no-create-home \
             --disabled-login --home "${INSTALLDIR}" roundcube ;\
    mkdir -p /var/roundcube/config ;\
    : > /var/roundcube/config/phpfpm.conf.override ;\
    chown -R roundcube:roundcube "${INSTALLDIR}" /var/roundcube /etc/angie \
             "/etc/php/${PHPVERSION}" /etc/s6-overlay ;\
    find "${INSTALLDIR}" -type d -exec chmod 0550 {} + ;\
    find "${INSTALLDIR}" -type f -exec chmod 0440 {} + ;\
    chmod 0550 "${INSTALLDIR}"/bin/*.sh ;\
    chmod 0750 /var/roundcube/config ;\
    chmod -R u+rX,go-rwx /etc/angie "/etc/php/${PHPVERSION}/fpm" ;\
    # ---- strip any leftover setuid/setgid bits (defence in depth) ----
    find / -xdev -type f \( -perm -4000 -o -perm -2000 \) -exec chmod -s {} + 2>/dev/null || true

WORKDIR ${INSTALLDIR}

# Run UNPRIVILEGED with ROOTLESS s6. s6-overlay is PID1 (reaps + restarts the
# longruns) but runs as the roundcube uid; S6_READ_ONLY_ROOT=1 + a writable /run
# tmpfs let it operate on the read-only rootfs under cap_drop: [ALL]. angie binds
# :8080 (no CAP_NET_BIND_SERVICE), nothing setuids. Writable mounts (/run, /tmp,
# the config volume) MUST be pre-owned roundcube:roundcube.
USER roundcube:roundcube
EXPOSE 8080

# S6_READ_ONLY_ROOT: rootfs is read-only, so s6 lays its scratch under /run.
# WAIT_FOR_SERVICES_MAXTIME=0: wait indefinitely for the init oneshot.
# IF_STAGE2_FAILS=2: a failed init brings the whole container down (fail fast).
ENV     S6_KEEP_ENV=1 \
        S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
        S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
        S6_READ_ONLY_ROOT=1

# Liveness+readiness via the loopback healthz vhost (angie :8181 -> /fpm-ping ->
# pool "pong"). The container STOPSIGNAL stays SIGTERM (s6 traps it and brings
# the services down; each service's ./down-signal=SIGQUIT does the graceful stop).
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD /healthcheck.sh || exit 1

ENTRYPOINT ["/init"]
