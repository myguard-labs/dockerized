#!/bin/sh

echo "[NGINX] Find documentation for this Docker image at https://deb.myguard.nl/nginx-dockerized/"
echo "[NGINX] For information about the NGINX packages, please visit https://deb.myguard.nl/nginx-modules/"

# Set timezone
if [ -n "${TZ}" ]; then
    rm -f /etc/timezone /etc/localtime
    echo "${TZ}" > /etc/timezone
    ln -s /usr/share/zoneinfo/${TZ} /etc/localtime
fi

# If there are no configfiles, copy them
FIRSTRUN="/etc/nginx/nginx.conf"
if [ ! -f ${FIRSTRUN} ]; then
    echo "[NGINX] Default configurations are being copied to /etc/nginx and /etc/modsecurity as no existing configs were found."
    cp -r /etc/nginx.orig/* /etc/nginx/
fi

cp -r /etc/modsecurity.orig/* /etc/modsecurity/

# Snakeoil fallback: the bundled default vhost listens on :443 using the
# self-signed snakeoil cert so the container serves HTTPS out-of-the-box with
# no certs mounted. Regenerate it if the ssl-cert package didn't (or a
# read-only layer dropped it). Mount real certs + your own vhost for production.
if [ ! -f /etc/ssl/certs/ssl-cert-snakeoil.pem ] || [ ! -f /etc/ssl/private/ssl-cert-snakeoil.key ]; then
    if command -v make-ssl-cert >/dev/null 2>&1; then
        make-ssl-cert generate-default-snakeoil --force-overwrite 2>/dev/null || true
    fi
fi

#check if PHP is installed, else skip the whole block
if [ -n "${PHPVERSION}" ]; then

    FIRSTRUN="/etc/nullmailer/defaultdomain"
    if [ ! -f ${FIRSTRUN} ]; then
    echo "[NGINX] Default configurations are being copied to /etc/nullmailer as no existing configs were found."
        cp -r /etc/nullmailer.orig/* /etc/nullmailer
    fi

    #fix some weird issue with nullmailer
    find /var/spool/nullmailer -type f -name "core" -delete
    rm -f /var/spool/nullmailer/trigger
    /usr/bin/mkfifo /var/spool/nullmailer/trigger
    /bin/chmod 0622 /var/spool/nullmailer/trigger
    /bin/chown -R mail:mail /var/spool/nullmailer/ /etc/nullmailer
    runuser -u mail /usr/sbin/nullmailer-send 1>/var/log/nullmailer.log 2>&1 &

    if [ ! -x /run/php ]; then
        mkdir -p /run/php
        chown phpfpm:www-data /run/php
        chmod 750 /run/php
    fi

    COMPOSERPATH="/usr/bin/composer"
    if [ ! -f ${COMPOSERPATH} ]; then
        cd /tmp
        php composer-setup.php --quiet
        mv composer.phar ${COMPOSERPATH}
    fi
fi

# Refresh static helper files from the .orig copy. Wrapped in test guards
# so a partial /etc/nginx.orig (e.g. an upstream package without scripts/
# or snippets/) doesn't error out on an unmatched glob.
[ -f /etc/nginx.orig/mime.types ] && cp -p /etc/nginx.orig/mime.types /etc/nginx/mime.types
[ -f /etc/nginx.orig/nginx.conf-packaged ] && cp -p /etc/nginx.orig/nginx.conf-packaged /etc/nginx/nginx.conf-packaged
[ -f /etc/nginx.orig/nginx.conf-original ] && cp -p /etc/nginx.orig/nginx.conf-original /etc/nginx/nginx.conf-original
if [ -d /etc/nginx.orig/scripts ] && [ -n "$(ls -A /etc/nginx.orig/scripts 2>/dev/null)" ]; then
    mkdir -p /etc/nginx/scripts
    cp -p /etc/nginx.orig/scripts/. /etc/nginx/scripts/ 2>/dev/null || cp -rp /etc/nginx.orig/scripts/* /etc/nginx/scripts/
fi
if [ -d /etc/nginx.orig/snippets ] && [ -n "$(ls -A /etc/nginx.orig/snippets 2>/dev/null)" ]; then
    mkdir -p /etc/nginx/snippets
    cp -rp /etc/nginx.orig/snippets/* /etc/nginx/snippets/
fi

# Make sure all available modules are available outside of docker and remove modules which aren't there (anymore)
mkdir -p /etc/nginx/modules-available
rm -f /etc/nginx/modules-available/*
if [ -d /usr/share/nginx/modules-available ] && [ -n "$(ls -A /usr/share/nginx/modules-available 2>/dev/null)" ]; then
    cp -rp /usr/share/nginx/modules-available/* /etc/nginx/modules-available/
fi

#reorder modules and symlink them to /usr/share/nginx/modules-enabled
chmod +x /etc/nginx/scripts/reorder-modules.sh
/etc/nginx/scripts/reorder-modules.sh

#check if PHP is installed, else skip the whole block
# PHPBLOCK
if [ -n "${PHPVERSION}" ]; then

    SETPHP=0
    startphp()
    {
        # set PHPVERSION for MULTI mode
        PHPVERSION="$1"
        FIRSTRUN="/etc/php/${PHPVERSION}/fpm/php-fpm.conf"
        if [ ! -f ${FIRSTRUN} ]; then
            echo "[NGINX] Default PHP configurations are being copied to /etc/php/${PHPVERSION} as no existing PHP configs were found."
            mkdir -p /etc/php/${PHPVERSION}
            cp -r /etc/php.orig/${PHPVERSION}/* /etc/php/${PHPVERSION}
        fi
        php-fpm${PHPVERSION} -v 2>&1 | grep -v Zend | grep -v Copy
        php-fpm${PHPVERSION} -t
        service php${PHPVERSION}-fpm restart 1>/dev/null 2>&1 &
        SETPHP=1
    }

    cp -rn /etc/php.orig/* /etc/php

    #SINGLE PHP IMAGES
    if [ "${MODE}" = "FPM" ] && [ ! "${MODE}" = "MULTI" ]; then
        startphp "${PHPVERSION}"
    fi
    #MULTI PHP IMAGES
    if [ "${MODE}" = "MULTI" ] && [ "${PHP56}" = "YES" ]; then
        startphp "5.6"
    fi
    if [ "${MODE}" = "MULTI" ] && [ "${PHP72}" = "YES" ]; then
        startphp "7.2"
    fi
    if [ "${MODE}" = "MULTI" ] && [ "${PHP74}" = "YES" ]; then
        startphp "7.4"
    fi
    if [ "${MODE}" = "MULTI" ] && [ "${PHP80}" = "YES" ]; then
        startphp "8.0"
    fi
    if [ "${MODE}" = "MULTI" ] && [ "${PHP81}" = "YES" ]; then
        startphp "8.1"
    fi
    if [ "${MODE}" = "MULTI" ] && [ "${PHP82}" = "YES" ]; then
        startphp "8.2"
    fi
    if [ "${MODE}" = "MULTI" ] && [ "${PHP83}" = "YES" ]; then
        startphp "8.3"
    fi
    if [ "${MODE}" = "MULTI" ] && [ "${PHP84}" = "YES" ]; then
        startphp "8.4"
    fi
    if [ "${MODE}" = "MULTI" ] && [ "${PHP85}" = "YES" ]; then
        startphp "8.5"
    fi
    if [ "${PHPVERSION}" = "MULTI" ] && [ "${SETPHP}" = 0 ]; then
        echo "[NGINX] --->"
        echo "[NGINX] ---> You have obtained the MULTI-PHP version of the Docker, however..."
        echo "[NGINX] ---> No environment variable for PHP56, PHP74, PHP80, PHP81, PHP82, PHP83, PHP84, or PHP85 has been set"
        echo "[NGINX] ---> Uncertain of the next steps, the process will now exit..."
        echo "[NGINX] --->"
        exit
    fi
fi
# /PHPBLOCK

if [ -n "${MODULES}" ]; then
    NGX_MODULES="${MODULES}"
fi

if [ ! -n "${NGX_MODULES}" ]; then
    if [ ! -e "/etc/nginx/modules/enabled/.quiet" ]; then
        echo "[NGINX] --->"
	echo "[NGINX] ---> Without NGX_MODULES defined in the environment, all modules will be initialized"
        echo "[NGINX] ---> This may lead to issues, reduced performance, or failure to start"
        echo "[NGINX] ---> It's advised to define NGX_MODULES or manually remove entries from /etc/nginx/modules-enabled"
	echo "[NGINX] ---> Removing mod-http-lua.conf and mod-stream-lua.conf, as those requires additional configuration to start"
        echo "[NGINX] ---> To suppress this message and behaviour please touch /etc/nginx/modules-enabled/.quiet"
        echo "[NGINX] --->"
        rm -f /etc/nginx/modules-enabled/50-mod-http-lua.conf
        rm -f /etc/nginx/modules-enabled/50-mod-stream-lua.conf
    fi
fi

nginx -V 2>&1 | grep -v configure | grep -v SNI
echo "[NGINX] Verifying configurations using the command nginx -t"
# Fatal: a broken config must abort the boot with a clear message rather than
# letting `exec nginx` crash into a cryptic restart loop.
if ! nginx -t; then
    echo "[NGINX] --->"
    echo "[NGINX] ---> FATAL: nginx -t failed — the configuration is invalid (see the error above)."
    echo "[NGINX] ---> Fix your mounted /etc/nginx config and restart the container. Aborting boot."
    echo "[NGINX] --->"
    exit 1
fi

# ---- TLS session-ticket key rotation (forward secrecy) -------------------
# nginx.conf enables ssl_session_tickets; without a rotating key the ticket
# key is fixed for the life of the master, weakening forward secrecy. Generate
# one now and rotate it in the 24h loop below. Only relevant if a server block
# references it via `ssl_session_ticket_key /run/nginx/ticket.key;`.
TICKET_KEY=/run/nginx/ticket.key
mkdir -p /run/nginx 2>/dev/null || true
if [ ! -f "${TICKET_KEY}" ]; then
    openssl rand 80 > "${TICKET_KEY}" 2>/dev/null && chmod 0600 "${TICKET_KEY}" || true
fi

echo "[NGINX] This docker is set to reload every 24 hours to pick up new SSL certificates and rotate the TLS ticket key."
# Test the config before each reload — never reload a broken config over a
# running master (that would either fail silently or leave stale state).
while [ 1 ]; do
    sleep 1d
    # Rotate the TLS session-ticket key (forward secrecy) before the reload.
    [ -d /run/nginx ] && openssl rand 80 > "${TICKET_KEY}.tmp" 2>/dev/null \
        && chmod 0600 "${TICKET_KEY}.tmp" && mv -f "${TICKET_KEY}.tmp" "${TICKET_KEY}" || true
    if /usr/sbin/nginx -t 2>/dev/null; then
        /usr/sbin/nginx -s reload
    else
        echo "[NGINX] ---> 24h reload SKIPPED: nginx -t failed, config is broken; keeping the running config. Fix it and reload manually."
        /usr/sbin/nginx -t 2>&1 | sed 's/^/[NGINX] ---> /'
    fi
done &

# Setup the MALLOC of choice.
# Resolve allocator SONAMEs using this image's native loader cache.
case "${MALLOC:-jemalloc}" in
    mimalloc) malloc_lib=libmimalloc-secure.so.3 ;;
    none)     malloc_lib= ;;
    *)        malloc_lib=libjemalloc.so.2 ;;
esac
unset LD_PRELOAD
if [ -n "$malloc_lib" ]; then
    LD_PRELOAD="$(ldconfig -p 2>/dev/null | awk -v lib="$malloc_lib" '$1 == lib { print $NF; exit }')"
fi
if [ -n "${LD_PRELOAD:-}" ]; then
    export LD_PRELOAD
else
    unset LD_PRELOAD
fi
# End allocator selection.

exec /usr/sbin/nginx -g 'daemon off;'
