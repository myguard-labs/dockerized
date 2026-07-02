# syntax=docker/dockerfile:1.7
# =====================================================================
#  ViMbAdmin  --  Debian / Angie-minimal / PHP-FPM 8.5
# =====================================================================
#  Single-purpose, hardened image for the modernised ViMbAdmin fork
#  (https://github.com/eilandert/ViMbAdmin):
#    * FROM eilandert/debian-base (trixie-slim + deb.myguard.nl repo + hardening)
#    * angie-minimal  (no modsecurity/lua/brotli -- the panel is guarded by a
#      native positive-security vhost instead)
#    * php8.5-fpm with only the extensions ViMbAdmin needs
#    * Snuffleupagus with the app's audited vimbadmin-strict ruleset
#    * code owned root:root (read-only to the web/php users); only the var/
#      and configs/ volumes are writable -> runs fine with `read_only: true`
#  All Angie config lives in one file: angie.conf.
#  Deploy guide: ./README.md
# =====================================================================

FROM    docker.io/eilandert/debian-base:stable

LABEL   org.opencontainers.image.authors="eilandert" \
        org.opencontainers.image.title="ViMbAdmin" \
        org.opencontainers.image.description="ViMbAdmin (modernised fork) on Angie-minimal + PHP-FPM 8.5" \
        org.opencontainers.image.source="https://github.com/myguard-labs/dockerized" \
        org.opencontainers.image.url="https://hub.docker.com/r/eilandert/vimbadmin" \
        org.opencontainers.image.vendor="MyGuard"

ENV     DEBIAN_FRONTEND=noninteractive \
        PHPVERSION=8.5 \
        INSTALL_PATH=/opt/vimbadmin \
        VIMBADMIN_GIT=https://github.com/eilandert/ViMbAdmin.git \
        APPLICATION_ENV=docker

# s6-overlay (PID1 process supervisor) — supervises php-fpm + angie so a dead
# FPM master is respawned in ~1s instead of staying dead silently. Runs ROOTLESS
# here (the container is USER 997:33, read-only rootfs, cap_drop ALL): the
# S6_* env below disables the root-only init stages (fix-attrs / user creation)
# and points s6's scratch at the writable /run mount.
ARG     S6_OVERLAY_VERSION=3.2.1.0
COPY    s6-rc.d/ /etc/s6-overlay/s6-rc.d/
COPY --chmod=0755 s6-scripts/init-bootstrap.sh /etc/s6-overlay/scripts/init-bootstrap.sh

RUN --mount=type=cache,target=/var/cache/apt,sharing=locked \
    --mount=type=cache,target=/var/lib/apt,sharing=locked \
    set -eux ;\
    rm -f /etc/apt/apt.conf.d/docker-clean ;\
    # PHP 8.5 from the ondrej mirror on our edge repo (fleet convention);
    # angie + php-snuffleupagus from the signed deb.myguard.nl repo (debian-base).
    echo "deb [trusted=yes] http://edge.deb.myguard.nl:8888/mirror/ondrej-php ${DIST} main" > /etc/apt/sources.list.d/ondrej-php.list ;\
    apt-get update ;\
    apt-get install -y --no-install-recommends \
      angie-minimal \
      php8.5-fpm php8.5-cli php8.5-mysql php8.5-mbstring php8.5-intl \
      php8.5-xml php8.5-gd php8.5-curl php8.5-bcmath php8.5-zip php8.5-gmp \
      php8.5-apcu \
      php8.5-snuffleupagus \
      bzip2 xz-utils \
      git ca-certificates ;\
    # ---- s6-overlay (PID1 supervisor) — fetch noarch + this build's arch ----
    # deb images build dual-arch (amd64+arm64); pick the matching tarball.
    case "$(dpkg --print-architecture)" in \
      amd64) S6_ARCH=x86_64 ;; \
      arm64) S6_ARCH=aarch64 ;; \
      *) echo "unsupported arch for s6-overlay" >&2 ; exit 1 ;; \
    esac ;\
    # No curl/wget in this image (it ships none on purpose — the healthcheck
    # uses PHP fsockopen). PHP is always present, so fetch the tarballs with it.
    # S6_OVERLAY_VERSION is a build ARG and S6_ARCH a shell var; interpolate both
    # into the URL in the shell, before PHP sees the string.
    S6_BASE="https://github.com/just-containers/s6-overlay/releases/download/v${S6_OVERLAY_VERSION}" ;\
    php -r "copy('${S6_BASE}/s6-overlay-noarch.tar.xz','/tmp/s6-noarch.tar.xz') or exit(1);" ;\
    php -r "copy('${S6_BASE}/s6-overlay-${S6_ARCH}.tar.xz','/tmp/s6-arch.tar.xz') or exit(1);" ;\
    tar -C / -Jxpf /tmp/s6-noarch.tar.xz ;\
    tar -C / -Jxpf /tmp/s6-arch.tar.xz ;\
    rm -f /tmp/s6-noarch.tar.xz /tmp/s6-arch.tar.xz ;\
    chmod 0755 /etc/s6-overlay/s6-rc.d/php-fpm/run \
               /etc/s6-overlay/s6-rc.d/angie/run \
               /etc/s6-overlay/s6-rc.d/queue-runner/run \
               /etc/s6-overlay/scripts/init-bootstrap.sh ;\
    # Dedicated unprivileged FPM user (pool runs as phpfpm; socket group
    # www-data so Angie can reach it). ondrej packages don't create it.
    groupadd -r phpfpm 2>/dev/null || true ;\
    useradd  -r -g phpfpm -G www-data -s /usr/sbin/nologin -d /nonexistent phpfpm 2>/dev/null || true ;\
    # ---- fetch the modernised fork + install deps ---------------------
    git clone --depth 1 "${VIMBADMIN_GIT}" "${INSTALL_PATH}" ;\
    cd "${INSTALL_PATH}" ;\
    # Composer: verify the installer against the published SHA-384 first.
    php -r "copy('https://getcomposer.org/installer','/tmp/c.php');" ;\
    EXPECTED="$(php -r "copy('https://composer.github.io/installer.sig','/tmp/c.sig'); echo trim(file_get_contents('/tmp/c.sig'));")" ;\
    ACTUAL="$(php -r "echo hash_file('sha384','/tmp/c.php');")" ;\
    [ "${EXPECTED}" = "${ACTUAL}" ] || { echo 'composer installer checksum mismatch' >&2; exit 1; } ;\
    php /tmp/c.php --quiet --install-dir=/usr/local/bin --filename=composer ;\
    composer install --prefer-dist --no-dev --no-interaction --optimize-autoloader --apcu-autoloader ;\
    # ---- Doctrine proxies --------------------------------------------
    # Prod runs autogen_proxies=0 on a read-only rootfs, so the proxy classes
    # must be present on disk before the first request. They are no longer
    # committed to the fork (they drifted from the entities); generate them
    # here from the XML mappings. The script needs no database.
    php bin/generate-proxies.php ;\
    # ---- Snuffleupagus -----------------------------------------------
    # Keep the ruleset TEMPLATE on a read-only image path. bootstrap copies it
    # into the writable var/ volume and injects a per-deployment secret_key, so
    # /etc stays read-only-friendly. The package already loads the extension
    # via mods-available; the FPM pool points sp.configuration_file at the
    # runtime copy (see the sed below).
    install -D -m 0644 "${INSTALL_PATH}/contrib/snuffleupagus/vimbadmin-strict.list" \
        /usr/share/vimbadmin/vimbadmin-strict.list ;\
    # Disable Snuffleupagus for the CLI SAPI entirely. SP only needs to harden
    # the web (FPM) surface; the CLI runs trusted local scripts (vimbtool,
    # bootstrap, cron queue runner). Leaving the extension enabled in CLI
    # without a rulebook emits a "no sp.configuration_file" warning on every
    # invocation, and pointing it at the runtime ruleset would fatal during the
    # bootstrap secret_key generation. Removing the CLI conf.d symlink avoids
    # both: no warning, no fatal, FPM protection unchanged.
    rm -f /etc/php/8.5/cli/conf.d/*snuffleupagus*.ini ;\
    # ---- PHP-FPM pool: the fork's hardened pool ----------------------
    rm -f /etc/php/8.5/fpm/pool.d/www.conf ;\
    install -D -m 0644 "${INSTALL_PATH}/contrib/php-fpm/vimbadmin.conf" \
        /etc/php/8.5/fpm/pool.d/vimbadmin.conf ;\
    # The pool ships sp.configuration_file at the bare-metal path
    # (/etc/php/8.5/php-snuffleupagus/...). In this image bootstrap materialises
    # the ruleset (with a per-deploy secret_key) into the writable var/ volume,
    # so repoint the pool's php_admin_value at that runtime copy. The pool's
    # php_admin_value overrides any conf.d setting, so it MUST be correct here
    # -- a wrong path makes SP fatal on every request (worker exit 255).
    sed -i "s#^php_admin_value\[sp.configuration_file\].*#php_admin_value[sp.configuration_file] = ${INSTALL_PATH}/var/vimbadmin-strict.list#" \
        /etc/php/8.5/fpm/pool.d/vimbadmin.conf ;\
    # The container runs UNPRIVILEGED (compose user: phpfpm:www-data, cap_drop
    # ALL). A non-root FPM master cannot setuid/setgid, and php-fpm errors if a
    # pool sets user/group while the master isn't root. Comment them out -- the
    # workers inherit the container's phpfpm:www-data identity. The listen.*
    # socket-ownership lines stay (chown of the socket to the same uid is a
    # no-op and does not need CAP_CHOWN).
    sed -i -E "s#^([[:space:]]*(user|group)[[:space:]]*=)#; \1#" \
        /etc/php/8.5/fpm/pool.d/vimbadmin.conf ;\
    # Master FPM error_log -> tmpfs path (ondrej default /var/log/php8.5-fpm.log
    # sits on the read-only rootfs).
    sed -i 's#^error_log = .*#error_log = /var/log/php-fpm/fpm.log#' /etc/php/8.5/fpm/php-fpm.conf ;\
    # ---- OPcache: the image code is immutable, so skip stat() on every
    # include (validate_timestamps=0). Pure shared-memory cache (no file_cache)
    # -> read-only rootfs safe. JIT left OFF (no buffer) on purpose: the panel
    # is I/O-bound, JIT buys nothing here and has bitten us elsewhere.
    # (Doctrine maps via XML, not annotations, so docblocks aren't load-bearing;
    # save_comments left at the default 1 as a harmless safe default.)
    # Sizing measured on the warm image (preload set = ~1977 scripts, ~61 MB
    # opcode + ~12 MB interned). memory_consumption 112 / interned 16 leaves
    # headroom for the runtime stragglers + compiled Smarty templates;
    # max_accelerated_files 6007 (prime) >> the ~2050 real scripts (20000 just
    # wasted hash-table memory). preload compiles the whole tree into SHM at FPM
    # master start so workers never compile on the first request.
    { echo 'opcache.enable=1' ;\
      echo 'opcache.enable_cli=0' ;\
      echo 'opcache.memory_consumption=112' ;\
      echo 'opcache.interned_strings_buffer=16' ;\
      echo 'opcache.max_accelerated_files=6007' ;\
      echo 'opcache.validate_timestamps=0' ;\
      echo 'opcache.save_comments=1' ;\
      echo 'opcache.preload=/opt/vimbadmin/preload.php' ;\
      echo 'opcache.preload_user=phpfpm' ; } \
        > /etc/php/8.5/fpm/conf.d/99-opcache-tuning.ini ;\
    # ---- APCu: persistent Doctrine metadata/query cache (was ArrayCache =
    # per-request only). Anonymous mmap (no mmap_file_mask) -> RO-rootfs safe.
    # Measured real use ~0.4 MB metadata + classmap/result caches (a few MB
    # peak); 16M is ample (64M was ~15x over).
    { echo 'apc.enabled=1' ;\
      echo 'apc.shm_size=16M' ;\
      echo 'apc.enable_cli=0' ; } \
        > /etc/php/8.5/fpm/conf.d/99-apcu-tuning.ini ;\
    # ---- app config template (no secret baked) -----------------------
    # Seed the runtime config verbatim from the app's flat application.ini.dist.
    # The image bakes NO overrides: the fork's .dist already carries the sane
    # container defaults (dark skin, server-side pagination ON, doctrine2cache
    # 'auto' → picks APcu since ext-apcu is installed). It is served at the
    # domain root; if you proxy the panel on a sub-path that strips its prefix
    # (e.g. /vimbadmin/), set resources.frontController.baseUrl in YOUR mounted
    # application.ini, else assets/links resolve to the proxy root (unstyled).
    cp application/configs/application.ini.dist application/configs/application.ini ;\
    mv application/configs application/configs.orig ;\
    # ---- bake the build commit so the app can show it at runtime -----
    # The image ships no .git (stripped just below) and var/ is a writable
    # volume at runtime (would shadow a baked file), so write the HEAD SHA to a
    # read-only file at the APP ROOT. ViMbAdmin_Version::gitCommit() reads it
    # for the Maintenance tab + the "newer commit?" check.
    git -C "${INSTALL_PATH}" rev-parse HEAD > "${INSTALL_PATH}/GIT_COMMIT" 2>/dev/null || true ;\
    # ---- strip everything the running image doesn't need -------------
    # app cruft + the contrib sources (SP ruleset already installed from there)
    rm -rf "${INSTALL_PATH}/.git" "${INSTALL_PATH}/contrib" \
           "${INSTALL_PATH}/tests" "${INSTALL_PATH}/doc" "${INSTALL_PATH}/docs" \
           "${INSTALL_PATH}/CHANGELOG" "${INSTALL_PATH}"/*.md "${INSTALL_PATH}/.github" ;\
    # vendor docs / tests / VCS / CI metadata
    find "${INSTALL_PATH}/vendor" -type d \( -iname docs -o -iname doc -o -iname test -o -iname tests -o -iname examples -o -iname '.github' \) -prune -exec rm -rf {} + 2>/dev/null || true ;\
    find "${INSTALL_PATH}/vendor" -type f \( -iname '*.md' -o -iname '*.dist' -o -iname 'phpunit*' -o -iname '.gitignore' -o -iname '.gitattributes' \) -delete 2>/dev/null || true ;\
    # composer + build tools no longer needed at runtime
    rm -f /usr/local/bin/composer ;\
    apt-get -y purge git ;\
    apt-get -y autoremove --purge ;\
    apt-get -y clean ;\
    # docs / man / locale / info (belt + braces; debian-base path-excludes most)
    rm -rf /usr/share/doc/* /usr/share/man/* /usr/share/info/* /usr/share/groff/* \
           /usr/share/lintian/* /usr/share/linda/* ;\
    find /usr/share/locale -mindepth 1 -maxdepth 1 -type d ! -name 'en*' -exec rm -rf {} + 2>/dev/null || true ;\
    # ---- remove ALL apt repositories + lists (no apt at runtime) -----
    rm -rf /etc/apt/sources.list /etc/apt/sources.list.d/* /var/lib/apt/lists/* \
           /var/cache/apt/* /root/.composer /root/.cache /tmp/* ;\
    # ---- codebase READ-ONLY to web/php; only var/ + configs writable -
    chown -R root:root "${INSTALL_PATH}" ;\
    chmod -R go-w "${INSTALL_PATH}" ;\
    install -d -m 0750 -o phpfpm -g www-data \
        "${INSTALL_PATH}/var" "${INSTALL_PATH}/var/templates_c" \
        "${INSTALL_PATH}/var/cache" "${INSTALL_PATH}/var/log" \
        "${INSTALL_PATH}/var/bruteforce" "${INSTALL_PATH}/application/configs" ;\
    chown -R phpfpm:www-data "${INSTALL_PATH}/var" "${INSTALL_PATH}/application/configs" ;\
    # ---- make the shared template dir traversable by the unprivileged
    # runtime user. `COPY --chmod=0644` created /usr/share/vimbadmin as 0644
    # (no execute bit), so non-root (USER phpfpm) cannot traverse it to read
    # the SP ruleset template -> bootstrap failed with "Permission denied".
    # Set 0755 on the dir, 0644 on the files.
    chmod 0755 /usr/share/vimbadmin ;\
    chmod 0644 /usr/share/vimbadmin/* ;\
    # ---- strip any leftover setuid/setgid bits ----------------------
    find / -xdev -type f \( -perm -4000 -o -perm -2000 \) -exec chmod -s {} + 2>/dev/null || true

# Our Angie config replaces the package default (copied AFTER install so it
# doesn't collide with the angie-common conffile during dpkg setup).
COPY    angie.conf            /etc/angie/angie.conf

WORKDIR /opt/vimbadmin
EXPOSE  8080

# Run UNPRIVILEGED. PID1 (bootstrap -> fpm master + angie master) is phpfpm,
# gid www-data, so the container needs NO root and runs with cap_drop: [ALL].
# Angie binds :8080 (>=1024, no CAP_NET_BIND_SERVICE); FPM/angie workers
# inherit this identity (no setuid). The writable volumes MUST be pre-owned
# phpfpm:www-data on the host (compose/README).
USER    phpfpm:www-data

# s6-overlay rootless config. The container runs as USER 997:33 with a read-only
# rootfs and cap_drop ALL, so s6's default root-only init stages must be off:
#   S6_READ_ONLY_ROOT   — copy the run-time scratch into the writable /run mount
#                         instead of trying to write the read-only rootfs.
#   *_USER=0 / *_GROUPS — s6 makes no chown/chmod (fix-attrs) calls it can't do.
#   S6_KEEP_ENV         — pass PHPVERSION/INSTALL_PATH/APPLICATION_ENV through to
#                         the run scripts + init-bootstrap.
#   MAXTIME=0           — never time out waiting for the (DB-dependent) oneshot.
#   STAGE2_FAILS=2      — a failed init aborts the container (don't serve broken).
ENV     S6_KEEP_ENV=1 \
        S6_READ_ONLY_ROOT=1 \
        S6_CMD_WAIT_FOR_SERVICES_MAXTIME=0 \
        S6_BEHAVIOUR_IF_STAGE2_FAILS=2 \
        S6_FIX_ATTRS_HIDDEN=1 \
        S6_VERBOSITY=1

# Dependency-free TCP probe: the image ships no curl/wget/nc and uses dash
# (no /dev/tcp), but PHP is always present. fsockopen the listening angie. With
# s6 supervising FPM, a respawning master keeps angie:8080 answering; a master
# that cannot recover (broken config) lets angie 502 and ages the pool out.
HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD php -r '$f=@fsockopen("127.0.0.1",8080,$e,$s,3);exit($f?0:1);' || exit 1

# s6-svscan is PID1 (handles SIGTERM → ordered shutdown; it forwards SIGQUIT to
# angie via s6-rc.d/angie/down-signal). Container STOPSIGNAL is therefore SIGTERM.
STOPSIGNAL SIGTERM
ENTRYPOINT ["/init"]
