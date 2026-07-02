# syntax=docker/dockerfile:1.7
FROM alpine:latest
LABEL org.opencontainers.image.authors="eilandert"
LABEL org.opencontainers.image.source="https://github.com/myguard-labs/dockerized"

LABEL maintainer="Thijs Eilander <eilander@myguard.nl>"

COPY --chmod=0755 bootstrap.sh /bootstrap.sh
RUN set -ex ;\
    apk update ;\
    apk upgrade ;\
    apk add --no-cache certbot tzdata ;\
    apk del alpine-keys apk-tools ;\
    rm -rf /var/cache/apk/* /lib/apk/db /usr/src/* ;\
    chmod +x /bootstrap.sh

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 CMD test -f /tmp/healthy && find /tmp/healthy -mmin -10 | grep -q . || exit 1

CMD ["/bootstrap.sh"]

