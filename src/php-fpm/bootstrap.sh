#!/bin/sh

echo "[PHP-FPM] This docker image can be found on https://hub.docker.com/u/eilandert or https://github.com/myguard-labs/dockerized"

chmod 777 /dev/stdout

if [ -n "${TZ}" ]; then
    rm /etc/timezone /etc/localtime
    echo "${TZ}" > /etc/timezone
    ln -s /usr/share/zoneinfo/${TZ} /etc/localtime
fi

FIRSTRUN="/etc/php/${PHPVERSION}/fpm/php-fpm.conf"
if [ ! -f ${FIRSTRUN} ]; then
    echo "[PHP-FPM] no configs found, populating default configs to /etc/php/${PHPVERSION}"
    cp -r /etc/php.orig/* /etc/php/
fi

FIRSTRUN="/etc/nullmailer/defaultdomain"
if [ ! -f ${FIRSTRUN} ]; then
    echo "[PHP-FPM] no configs found, populating default configs to /etc/nullmailer"
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
php-fpm${PHPVERSION} -v
php-fpm${PHPVERSION} -t

exec /usr/sbin/php-fpm${PHPVERSION} -F
