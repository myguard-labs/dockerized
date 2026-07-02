#!/bin/sh

echo "[UNBOUND] This docker image can be found on https://hub.docker.com/u/eilandert and https://github.com/myguard-labs/dockerized"

UNBOUNDCONF="/config/unbound.conf"
if [ ! -f ${UNBOUNDCONF} ]; then
    echo "[UNBOUND] unbound.conf not found, populating default configs to /config"
    mkdir -p /config
    cp -r config.orig/* /config/
fi

exec /usr/sbin/unbound -c /config/unbound.conf
