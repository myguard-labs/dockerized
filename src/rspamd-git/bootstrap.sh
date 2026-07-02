#!/bin/sh

echo "[RSPAMD] This docker image can be found on https://hub.docker.com/u/eilandert and https://github.com/myguard-labs/dockerized"

case ${MALLOC} in
    jemalloc)
        if [ -f /usr/lib/x86_64-linux-gnu/libjemalloc.so.2 ]; then
        export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libjemalloc.so.2
        fi
        ;;
    mimalloc)
        if [ -f /usr/lib/x86_64-linux-gnu/libmimalloc-secure.so ]; then
        export LD_PRELOAD=/usr/lib/x86_64-linux-gnu/libmimalloc-secure.so
        fi
        ;;
    none)
        unset LD_PRELOAD
        ;;
    *)
	unset LD_PRELOAD
        ;;
esac

CHECK="/usr/local/etc/rspamd/rspamd.conf"
if [ -f ${CHECK} ]; then
    echo "YOU HAVE MOUNTED CONFIGS TO /USR/LOCAL/ETC. THIS HAS CHANGED TO /ETC"
    echo "PLEASE CHANGE YOUR MOUNTS INSIDE THE CONTAINER ACCORDINGLY"
    echo "Trying to set a symlink for the time being...."
    ln -s /usr/local/etc/rspamd /etc/rspamd
fi

FIRSTRUN="/etc/rspamd/rspamd.conf"
if [ ! -f ${FIRSTRUN} ]; then
    echo "[RSPAMD] no configs found, populating default configs to /etc/rspamd"
    mkdir -p /etc/rspamd
    cp -r /etc/rspamd.orig/* /etc/rspamd/

    mkdir -p /var/log/rspamd
    mkdir -p /var/lib/rspamd
    mkdir -p /var/run/rspamd

    chown _rspamd:_rspamd -R /var/log/rspamd
    chown _rspamd:_rspamd -R /var/lib/rspamd
    chown _rspamd:_rspamd -R /var/run/rspamd
fi

if [ -n "${TZ}" ]; then
    rm -f /etc/timezone /etc/localtime
    echo "${TZ}" > /etc/timezone
    ln -s /usr/share/zoneinfo/${TZ} /etc/localtime
fi

mkdir -p /etc/rspamd/override.d
if [ -n "${SYSLOG_HOST}" ]; then
    mkdir -p /etc/syslog-ng/conf.d
    echo "destination dst { syslog(\"${SYSLOG_HOST}\" transport(\"udp\")); };" > /etc/syslog-ng/conf.d/remote.conf
    echo "log { source(s_sys); destination(dst); };" >> /etc/syslog-ng/conf.d/remote.conf
    syslog-ng --no-caps
    echo "type = \"syslog\";" > /etc/rspamd/override.d/logging.inc
    echo "[RSPAMD] Output is set to remote syslog at ${SYSLOG_HOST}"
else
    echo "type = \"console\";" > /etc/rspamd/override.d/logging.inc
fi
chown _rspamd:_rspamd -R /var/lib/rspamd

#sleep to avoid race conditions with other dockers like redis
if [ -n "${SLEEP}" ]; then
    sleep ${SLEEP};
fi

# test services
i=0
x=25
while [ 1 ]; do
    i=$(($i+1))
    HOST=$(eval echo \$WAIT_FOR_$i)
    if [ ! -n "${HOST}" ]; then
        break;
    fi
    wait-for-it.sh ${HOST} -t 3
    if [ "$?" -ne 0 ]; then
        echo "... ${HOST} is not reachable, trying again"
        i=$(($i-1))
        x=$(($x-1))
        if [ "${x}" -eq 0 ]; then
            echo "[RSPAMD] Nevermind, this is not going to work out! Goodbye!"
            exit 255;
        fi
    fi
done

#this is set for coredumps
ulimit -c unlimited

echo "[RSPAMD] Starting rspamd..."

exec	/usr/bin/rspamd -f -u _rspamd -g _rspamd;
