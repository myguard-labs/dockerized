# syntax=docker/dockerfile:1.7
FROM    eilandert/debian-base:stable
LABEL org.opencontainers.image.authors="eilandert"
LABEL org.opencontainers.image.source="https://github.com/myguard-labs/dockerized"

LABEL   maintainer="Thijs Eilander <eilander@myguard.nl>"
ENV     DEBIAN_FRONTEND="noninteractive"
ENV     TZ=Europe/Amsterdam
COPY --chmod=0755 bootstrap.sh /bootstrap.sh
COPY    ssh-createkeys.sh /ssh-createkeys.sh
COPY    syslog-ng.conf /etc/syslog-ng

RUN set -ex ;\
    apt-get update ;\
    apt-get -y --no-install-recommends install \
      aptly \
      ca-certificates \
      cron \
      curl \
      gpg-agent \
      inotify-tools \
      less \
      libnginx-mod-http-fancyindex \
      nginx-minimal \
      openssh-server \
      rsync \
      syslog-ng-core \
      tzdata \
      vim ;\
    chmod +x /bootstrap.sh ;\
    chmod 644 /etc/syslog-ng/syslog-ng.conf ;\
    chmod 755 /etc/syslog-ng/conf.d 2>/dev/null || true ;\
    mkdir -p /run/sshd && rm -f /etc/motd ;\
    groupadd -g 1010 aptly ;\
    useradd -u 1010 -g 1010 aptly -s /bin/bash -d /aptly ;\
    rm -f /etc/ssh/ssh_host_rsa_key* /etc/ssh/ssh_host_dsa_key* \
          /etc/ssh/ssh_host_ecdsa_key* /etc/ssh/ssh_host_ed25519_key* ;\
    # sshd hardening + crypto come from the openssh package's own config (trusted,
    # maintained upstream) — we do NOT layer our own sshd_config.d here. Also drop
    # the base image's UNOWNED, stale (2021) 10-algorithms-ciphers.conf: it pinned
    # KexAlgorithms to diffie-hellman-group-exchange-sha256 only, disabling PQC
    # (mlkem/sntrup) and curve25519. Removing it lets the package defaults win.
    rm -f /etc/ssh/sshd_config.d/10-algorithms-ciphers.conf ;\
    addgroup ssh-users && usermod -L -a -G ssh-users aptly ;\
    # Make `docker exec -it <id> bash` land as the unprivileged aptly user
    # instead of root. Guards: only for interactive shells, only once (no
    # re-entry loop), and skippable via APTLY_ROOT_SHELL=1 or `-u root`. \
    printf '%s\n' \
        '# Drop interactive root exec sessions to the unprivileged aptly user.' \
        'if [ -z "${APTLY_NO_DROP:-}" ] && [ -z "${APTLY_ROOT_SHELL:-}" ] \' \
        '   && [ "$(id -u)" = "0" ] && case "$-" in *i*) true;; *) false;; esac; then' \
        '    export APTLY_NO_DROP=1' \
        '    exec runuser -u aptly -- bash -l' \
        'fi' \
        >> /root/.bashrc ;\
    cp -rp /etc/ssh /etc/ssh.orig ;\
    cp -rp /etc/nginx /etc/nginx.orig ;\
    apt-get -y autoremove && apt-get -y autoclean && rm -rf /var/lib/apt/lists/*

COPY examples /aptly.orig/examples
COPY --chmod=0755 aptly-queue-worker.sh /usr/local/bin/aptly-queue-worker.sh
COPY --chmod=0755 ensure-queue-worker.sh /usr/local/bin/ensure-queue-worker.sh
COPY nginx.conf /etc/nginx/nginx.conf

VOLUME /etc/ssh
WORKDIR /aptly
EXPOSE 22
EXPOSE 80

# nginx serves the published repo on :80; sshd is the long-running process.
# Probe the webroot when nginx is enabled, otherwise confirm sshd is listening.
HEALTHCHECK --interval=30s --timeout=5s --start-period=15s --retries=3 \
    CMD curl -fsS --max-time 3 -o /dev/null http://127.0.0.1:80/ \
        || pgrep -x sshd >/dev/null || exit 1

CMD [ "/bootstrap.sh" ]
