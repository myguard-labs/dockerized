#!/bin/sh

echo "[LETSENCRYTPT] This docker image can be found on https://hub.docker.com/u/eilandert or https://github.com/myguard-labs/dockerized"

if [ -n "${TZ}" ]; then
    rm /etc/timezone /etc/localtime
    echo "${TZ}" > /etc/timezone
    ln -s /usr/share/zoneinfo/${TZ} /etc/localtime
fi

while (true)  do certbot renew; sleep 1d; done

