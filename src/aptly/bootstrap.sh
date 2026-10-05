#!/bin/bash

if [ -n "${TZ}" ]; then
    rm -f /etc/timezone /etc/localtime
    echo "${TZ}" > /etc/timezone
    ln -sfr /usr/share/zoneinfo/${TZ} /etc/localtime
fi

if [ -n "${SYSLOG_HOST}" ]; then
    mkdir -p /etc/syslog-ng/conf.d
    echo "destination dst { syslog(\"${SYSLOG_HOST}\" transport(\"udp\")); };" > /etc/syslog-ng/conf.d/remote.conf
    echo "log { source(s_sys); destination(dst); };" >> /etc/syslog-ng/conf.d/remote.conf
    syslog-ng --no-caps
fi


# NOTE: /etc/nginx is NOT a volume — our single nginx.conf is baked in by the
# Dockerfile COPY, so there is no first-run "restore default config" step. (A
# restore from /etc/nginx.orig would copy the BASE config, dropping fancyindex
# and the repo server block — so we must never do that here.)

# If you bind /etc/ssh the dir will be empty, so place a new copy
if [ ! -f "/etc/ssh/sshd_config" ];
then
    rm -rf /etc/ssh/*
    cp -rp /etc/ssh.orig/* /etc/ssh
fi
install -D -m 0644 /usr/local/share/aptly/sshd-key-only.conf /etc/ssh/sshd_config.d/01-key-only.conf
chage -M -1 aptly
#create sshd keys if needed (absent on first run)
bash /ssh-createkeys.sh 1>/dev/null
chmod 600 /etc/ssh/*key
chown root:root -R /etc/ssh

mkdir -p /aptly
chown aptly:aptly /aptly

if [ ! -f /aptly/.aptly.conf ]; then
    runuser -u aptly -- aptly config show 1>/dev/null 2>&1
    sed -i s/"\.aptly"/repo/ /aptly/.aptly.conf
    chown aptly:aptly /aptly/.aptly.conf
fi

if [ ! -d /aptly/.gnupg ]; then
    mkdir -p /aptly/.gnupg
    chown aptly:aptly /aptly/.gnupg
fi
# gpg refuses to use a homedir that is group/other accessible
chmod 700 /aptly/.gnupg

if [ ! -d /aptly/.ssh ]; then
    mkdir -p /aptly/.ssh
    chown aptly:aptly /aptly/.ssh
fi
# sshd refuses pubkey auth if ~/.ssh is not 0700 and authorized_keys not 0600
chmod 700 /aptly/.ssh
chown aptly:aptly /aptly/.ssh
[ -f /aptly/.ssh/authorized_keys ] && chmod 600 /aptly/.ssh/authorized_keys

if [ ! -d /aptly/repo ]; then
    mkdir -p /aptly/repo
fi

if [ ! -d /aptly/incoming ]; then
    mkdir -p /aptly/incoming
else
    rm -rf /aptly/incoming/*
fi

if [ ! -d /aptly/examples ]; then
    mkdir -p /aptly/examples
fi
cp -rp /aptly.orig/examples/* /aptly/examples/

# /aptly is a bind mount (survives rebuild), so a `[ ! -f ]` guard would pin the
# OLD process-incoming.sh forever and silently drop image fixes (e.g. the
# arch-scoped delete). Refresh unconditionally from the image copy — the image
# is source of truth. A prior copy is backed up once per boot for rollback.
mkdir -p /aptly/bin
if [ -f /aptly/bin/process-incoming.sh ]; then
    cp -p /aptly/bin/process-incoming.sh "/aptly/bin/process-incoming.sh.bak-boot-$(date +%s)" 2>/dev/null || true
fi
cp -rp /aptly/examples/process-incoming.sh /aptly/bin/process-incoming.sh
chmod +x /aptly/bin/process-incoming.sh

# ensure-queue-worker.sh: the enqueue path calls /aptly/bin/ensure-queue-worker.sh
# to restart the worker on demand if it died (see includes.sh aptly_process_incoming).
# Always refresh from the image copy so fixes ship on rebuild.
cp -p /usr/local/bin/ensure-queue-worker.sh /aptly/bin/ensure-queue-worker.sh
chmod +x /aptly/bin/ensure-queue-worker.sh

# Queue dir for the serialising worker (one publish at a time — see
# aptly-queue-worker.sh). Builds drop jobs here; the worker drains them.
mkdir -p /aptly/queue
chown aptly:aptly /aptly/queue

# Own the top-level + working dirs only. A recursive chown of the whole
# /aptly/repo/public pool (multi-GB, already aptly-owned) every boot is slow and,
# backgrounded, would race the queue-worker start below. The dirs created above
# are already chowned; just fix the top level non-recursively.
chown aptly:aptly /aptly /aptly/repo /aptly/bin /aptly/queue /aptly/incoming /aptly/examples 2>/dev/null || true

if [ ! "${CLEANDBONSTART}" = "NO" ];
then
    echo "[APTLY] Cleaning DB"
    runuser -u aptly -- aptly db cleanup
fi

if [ ! "${STARTNGINX}" = "NO" ];
then
    # Fail loudly if the config is broken instead of "restarting" into a dead
    # nginx — the healthcheck's sshd fallback would otherwise mask it and the
    # repo would silently serve nothing (this bit us with a missing module load).
    if ! nginx -t; then
        echo "[NGINX] FATAL: config test failed; not starting nginx" >&2
        exit 1
    fi
    service nginx restart 1>/dev/null
fi

service cron start

# Start the aptly queue worker as the unprivileged aptly user. It serialises
# every repo include + publish so concurrent builds can't produce a
# half-written index ("File has unexpected size"). setsid detaches it from the
# bootstrap shell so it survives as a long-running daemon; it self-guards with a
# flock so a duplicate start is a no-op. Toggle off with STARTQUEUEWORKER=NO.
if [ ! "${STARTQUEUEWORKER}" = "NO" ]; then
    echo "[APTLY] Starting queue worker"
    runuser -u aptly -- setsid bash -c \
        '/usr/local/bin/aptly-queue-worker.sh >> /aptly/queue-worker.log 2>&1' &
fi

dockerid=$(hostname)
echo "[APTLY] Shell into this docker (drops to aptly): docker exec -it $dockerid bash"
echo "[APTLY] Need root?  docker exec -it -u root $dockerid bash   (or set APTLY_ROOT_SHELL=1)"

exec /usr/sbin/sshd -D
