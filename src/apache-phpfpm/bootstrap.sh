#!/bin/sh

echo "[APACHE-PHPFPM] This docker image can be found on https://hub.docker.com/u/eilandert or https://github.com/myguard-labs/dockerized"

chmod 777 /dev/stdout

if [ -n "${TZ}" ]; then
    rm /etc/timezone /etc/localtime
    echo "${TZ}" > /etc/timezone
    ln -s /usr/share/zoneinfo/${TZ} /etc/localtime
fi

# If there are no configfiles, copy them
FIRSTRUN="/etc/apache2/apache2.conf"
if [ ! -f ${FIRSTRUN} ]; then
    echo "[APACHE-PHPFPM] no configs found, populating default configs to /etc/apache2"
    cp -r /etc/apache2.orig/* /etc/apache2/
fi

FIRSTRUN="/etc/nullmailer/defaultdomain"
if [ ! -f ${FIRSTRUN} ]; then
    echo "[APACHE-PHPFPM] no configs found, populating default configs to /etc/nullmailer"
    cp -r /etc/nullmailer.orig/* /etc/nullmailer
fi

#fix some weird issue with nullmailer
rm -f /var/spool/nullmailer/trigger
rm -f /var/spool/nullermailer/queue/core
/usr/bin/mkfifo /var/spool/nullmailer/trigger
/bin/chmod 0622 /var/spool/nullmailer/trigger
/bin/chown -R mail:mail /var/spool/nullmailer/ /etc/nullmailer
runuser -u mail /usr/sbin/nullmailer-send 1>/var/log/nullmailer.log 2>&1 &

#fix some weird issue with php-fpm
if [ ! -x /run/php ]; then
    mkdir -p /run/php
    chown phpfpm:www-data /run/php
    chmod 750 /run/php
fi

if [ "${MODE}" = "MOD" ]&&[ "${PHPVERSION}" = "MULTI" ]; then
    echo "[APACHE-PHPFPM] You downloaded the MULTI-PHP edition of the docker"
    echo "[APACHE-PHPFPM] MODE=MOD is incompatible with MULTI"
    echo "[APACHE-PHPFPM] Setting MODE=MULTI"
    export MODE="MULTI"
fi

if [ "${PHPVERSION}" = "MULTI" ] && [ ! "${PHP56}" = "YES" ] && [ ! "${PHP72}" = "YES" ] && [ ! "${PHP74}" = "YES" ] && [ ! "${PHP80}" = "YES" ] && [ ! "${PHP81}" = "YES" ] && [ ! "${PHP82}" = "YES" ]; then
    echo "[APACHE-PHPFPM] You downloaded the MULTI-PHP edition of the docker"
    echo "[APACHE-PHPFPM] There is no PHP56 PHP72 PHP74 or PHP80 environment variable specified"
    echo "[APACHE-PHPFPM] exiting...."
    sleep 10
    exit
fi

startphp()
{
    # set PHPVERSION for MULTI mode
    PHPVERSION="$1"

    FIRSTRUN="/etc/php/${PHPVERSION}/fpm/php-fpm.conf"
    if [ ! -f ${FIRSTRUN} ]; then
        echo "[APACHE-PHPFPM] no configs found, populating default configs to /etc/php/${PHPVERSION}"
        mkdir -p /etc/php/${PHPVERSION}
        cp -r /etc/php.orig/${PHPVERSION}/* /etc/php/${PHPVERSION}
    fi

    if [ "${MODE}" = "FPM" ]; then
        a2enconf php${PHPVERSION}-fpm 1>/dev/null 2>&1
    fi

    if [ "${MODE}" = "FPM" ]||[ "${MODE}" = "MULTI" ]; then
        a2dismod php${PHPVERSION} 1>/dev/null 2>&1
        php-fpm${PHPVERSION} -v
        php-fpm${PHPVERSION} -t
        service php${PHPVERSION}-fpm restart 1>/dev/null 2>&1
    fi

    if [ "${MODE}" = "MOD" ]; then
        a2enmod php${PHPVERSION} 1>/dev/null 2>&1
        a2disconf php${PHPVERSION}-fpm 1>/dev/null 2>&1
        a2dismod mpm_event 1>/dev/null 2>&1
        a2enmod mpm_prefork 1>/dev/null 2>&1
        php${PHPVERSION} -v
    fi

}

if [ "${MODE}" = "FPM" ] && [ ! "${MODE}" = "MULTI" ]; then
    startphp "${PHPVERSION}"
elif [ "${MODE}" = "MOD" ]; then
    startphp "${PHPVERSION}"
fi

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


if [ -n "${A2ENMOD}" ]; then
    a2enmod ${A2ENMOD} 1>/dev/null 2>&1
fi

if [ -n "${A2DISMOD}" ]; then
    a2dismod ${A2DISMOD} 1>/dev/null 2>&1
fi

if [ -n "${A2ENCONF}" ]; then
    a2enconf ${A2ENCONF} 1>/dev/null 2>&1
fi

if [ -n "${A2DISCONF}" ]; then
    a2disconf ${A2DISCONF} 1>/dev/null 2>&1
fi

if [ "${CACHE}" = "yes" ]; then
    mkdir -p /var/cache/apache2/mod_cache_disk
    chmod 755 /var/cache/apache2/mod_cache_disk
    chown -R www-data:www-data /var/cache/apache2/mod_cache_disk
    a2enmod cache_disk 1>/dev/null 2>&1
else
    if [ -f /etc/apache2/mods-enabled/cache_disk.load ]; then
        a2dismod cache cache_disk 1>/dev/null 2>&1
    fi
fi

apachectl -v
echo "Checking configs:"
apachectl configtest

if [ -f /etc/apache2/mods-enabled/ssl.load ]; then
    while [ 1 ]; do sleep 1d; apachectl graceful; done &
fi

if [ -f /run/apache2/apache2.pid ]; then
    rm /run/apache2/apache2.pid
fi

case ${MALLOC} in
    jemalloc)
        export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
        ;;
    mimalloc)
        export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libmimalloc-secure.so
        ;;
    *|none)
        unset LD_PRELOAD
        ;;
esac

echo "Starting Apache..."
exec /usr/sbin/apache2ctl -DFOREGROUND

