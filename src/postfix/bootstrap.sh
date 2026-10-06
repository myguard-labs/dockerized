#!/bin/sh

echo "[POSTFIX] This docker image can be found on https://hub.docker.com/u/eilandert and https://github.com/myguard-labs/dockerized"

# Resolve allocator SONAMEs using this image's native loader cache.
case "${MALLOC:-mimalloc}" in
    jemalloc) malloc_lib=libjemalloc.so.2 ;;
    none)     malloc_lib= ;;
    *)        malloc_lib=libmimalloc-secure.so.3 ;;
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


if [ -n "${TZ}" ]; then
    rm -f /etc/timezone /etc/localtime
    echo "${TZ}" > /etc/timezone
    ln -s /usr/share/zoneinfo/${TZ} /etc/localtime
fi

FIRSTRUN="/etc/postfix/main.cf"
if [ ! -f ${FIRSTRUN} ]; then
    echo "[POSTFIX] main.cf not found, populating default configs to /etc/postfix"
    echo "[POSTFIX] applying myguard hardened defaults (TLSv1.2+, PFS, PQ KEM)"
    mkdir -p /etc/postfix
    cp -r /etc/postfix.orig/* /etc/postfix/
fi

if [ -n "${SYSLOG_HOST}" ]; then
    mkdir -p /etc/syslog-ng/conf.d
    echo "destination dst { syslog(\"${SYSLOG_HOST}\" transport(\"udp\")); };" > /etc/syslog-ng/conf.d/remote.conf
    echo "log { source(s_sys); destination(dst); };" >> /etc/syslog-ng/conf.d/remote.conf
    syslog-ng --no-caps
    postconf -# maillog_file
    echo "[POSTFIX] Output is set to remote syslog at ${SYSLOG_HOST}"
else
    rm -f /etc/syslog-ng/conf.d/remote.conf
    postconf maillog_file=/dev/stdout
fi

chown postfix:postfix -R /var/lib/postfix

#echo "Automaticly reloading configs everyday to pick up new ssl certificates"
while [ 1 ]; do sleep 1d; postfix reload; done &

echo -n "Starting Postfix "; postconf mail_version | cut -d" " -f3

exec postfix start-fg
