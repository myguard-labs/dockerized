# syntax=docker/dockerfile:1.7
FROM alpine:3.20 AS build
LABEL org.opencontainers.image.authors="eilandert"
LABEL org.opencontainers.image.source="https://github.com/myguard-labs/dockerized"

RUN apk update && apk upgrade && \
    apk add --no-cache git gcc musl-dev pkgconfig zlib-dev zlib-static \
        libev-dev libevent-static make cmake wget

RUN mkdir -p /opt && cd /opt && \
    git clone https://github.com/rspamd/rbldnsd && \
    cd rbldnsd && \
    sed -i '/.*DEFAULT_LIBRARY_PATHS.*/a set(CMAKE_FIND_LIBRARY_SUFFIXES .a ${CMAKE_FIND_LIBRARY_SUFFIXES})' CMakeLists.txt && \
    CC="gcc -O3 -fPIE -static-pie" cmake . && \
    make && \
    strip rbldnsd && \
    addgroup -S -g 1000 rbldns && \
    adduser -S -G rbldns -u 1000 rbldns

# Zone file lives in the build context.
COPY badhosts.zone /zones/badhosts.zone

FROM scratch
LABEL org.opencontainers.image.authors="eilandert"
LABEL org.opencontainers.image.source="https://github.com/myguard-labs/dockerized"

COPY --from=build /etc/passwd /etc/group /etc/
COPY --from=build /opt/rbldnsd/rbldnsd /opt/rbldnsd
COPY --from=build /zones/badhosts.zone /zones/badhosts.zone

EXPOSE 53/udp
EXPOSE 53/tcp

HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 CMD pgrep -x rbldnsd > /dev/null && dig @127.0.0.1 +time=2 +tries=1 +short test.example > /dev/null 2>&1 || exit 1

CMD ["/opt/rbldnsd","-w","/zones","-b","0.0.0.0/53","-vv","-a","-f","-n","-q","rbl.mailscreen.nl:ip4set:badhosts.zone"]
