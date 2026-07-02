#!/bin/bash
# =============================================================================
# Dovecot container entrypoint.
#
# Keeps Dovecot's native privilege separation: the root master binds the
# (high) ports, loads the TLS key, then drops the internet-facing pre-auth
# login processes to `dovenull` and the mail processes to `vmail`. The
# container is caged around that root (cap_drop ALL + minimal caps,
# no-new-privileges, read-only rootfs — see docker-compose.yml).
#
# First run with an empty /etc/dovecot seeds the packaged default config plus
# the high-port + TLS-hardening override. Sieve outbound (redirect/vacation/
# notify) goes by SMTP to the Postfix container via `submission_host` — there
# is no local MTA in this image.
# =============================================================================
set -euo pipefail

log() { echo "[DOVECOT] $*"; }
warn() { echo "[DOVECOT] WARNING: $*" >&2; }

AM_ROOT=0; [ "$(id -u)" = "0" ] && AM_ROOT=1

# HOME points at the /tmp tmpfs: both /root and vmail's /nonexistent are
# unwritable under the read-only rootfs, but pyzor/razor and other tools want
# to write a dotfile. /tmp is always a writable tmpfs.
export HOME=/tmp

log "Image src : https://github.com/myguard-labs/dockerized/tree/master/src/dovecot-ubuntu"
log "Docker Hub: https://hub.docker.com/r/eilandert/dovecot"
log "Packages  : https://deb.myguard.nl"
log "Running as: uid=$(id -u) gid=$(id -g) ($([ "${AM_ROOT}" = 1 ] && echo root || echo unprivileged))"
log "---------------------------------------------------------------------------"

# Timezone: set the TZ env var in compose; for wall-clock log timestamps also
# bind-mount the zone file read-only:  /etc/localtime:/etc/localtime:ro
# (the read-only rootfs means we can't write it ourselves). See README.

# ---------------------------------------------------------------------------
# First-run config seeding (failsafe: never clobber an existing config)
# ---------------------------------------------------------------------------
if [ ! -f /etc/dovecot/dovecot.conf ]; then
    log "No dovecot.conf found; seeding packaged default config into /etc/dovecot"
    mkdir -p /etc/dovecot/conf.d
    if [ -d /etc/dovecot.orig ]; then
        cp -a /etc/dovecot.orig/. /etc/dovecot/
    else
        warn "/etc/dovecot.orig template missing; cannot seed config"
    fi
    # High-port override so the unprivileged process can bind every listener.
    # Loaded last (99-) -> overrides the listener ports in 10-master.conf.
    if [ -f /usr/local/share/dovecot/99-unprivileged-ports.conf ]; then
        cp /usr/local/share/dovecot/99-unprivileged-ports.conf \
           /etc/dovecot/conf.d/99-unprivileged-ports.conf
        log "Installed high-port listener override (LMTP 10024 IMAP 10143 IMAPS 10993 POP3 10110 POP3S 10995 Sieve 14190)"
    fi
    if [ -f /usr/local/share/dovecot/90-fts-flatcurve.conf ]; then
        cp /usr/local/share/dovecot/90-fts-flatcurve.conf \
           /etc/dovecot/conf.d/90-fts-flatcurve.conf
        log "Installed FTS flatcurve config"
    fi
    if [ -f /usr/local/share/dovecot/90-drp-sieve.conf ]; then
        cp /usr/local/share/dovecot/90-drp-sieve.conf \
           /etc/dovecot/conf.d/90-drp-sieve.conf
        log "Installed DCC/Razor/Pyzor reporting sieve (Junk-move -> report/revoke)"
    fi
fi

# ---------------------------------------------------------------------------
# Remote syslog (optional). /etc/syslog-ng is a symlink into the /tmp tmpfs, so
# this works even under the read-only rootfs. Seed the config there on first
# run (only if absent), then drop in the runtime remote.conf.
# ---------------------------------------------------------------------------
mkdir -p /tmp/syslog-ng/conf.d
if [ ! -f /tmp/syslog-ng/syslog-ng.conf ] && [ -f /etc/dovecot.orig/syslog-ng/syslog-ng.conf ]; then
    cp /etc/dovecot.orig/syslog-ng/syslog-ng.conf /tmp/syslog-ng/syslog-ng.conf
fi
if [ -n "${SYSLOG_HOST:-}" ]; then
    {
        echo "destination dst { syslog(\"${SYSLOG_HOST}\" transport(\"udp\")); };"
        echo "log { source(s_sys); destination(dst); };"
    } > /tmp/syslog-ng/conf.d/remote.conf
    # Persist/control/pid all default to /var/lib/syslog-ng + /run on the
    # read-only rootfs; redirect them onto the /tmp tmpfs so the daemon starts.
    syslog-ng --no-caps \
        --persist-file=/tmp/syslog-ng/syslog-ng.persist \
        --control=/tmp/syslog-ng/syslog-ng.ctl \
        --pidfile=/tmp/syslog-ng/syslog-ng.pid \
        || warn "syslog-ng failed to start"
    log "Logging forwarded to remote syslog at ${SYSLOG_HOST}"
else
    rm -f /tmp/syslog-ng/conf.d/remote.conf
fi

# NOTE: the old vimbadmin maildir-scan mailbox-size accounting (USE_VIMBADMIN +
# update_mailbox_size.pl) has been removed. Quota usage is now tracked live by
# the quota-clone plugin into the vimbadmin `dovecot_quota` table; ViMbAdmin
# drives any on-demand recalc via the doveadm HTTP API. No cron/script needed.

# ---------------------------------------------------------------------------
# Startup grace + dependency wait (optional). Bounded — never loops forever.
# ---------------------------------------------------------------------------
if [ -n "${SLEEP:-}" ]; then
    log "Sleeping ${SLEEP}s to avoid startup race conditions"
    sleep "${SLEEP}"
fi

i=0
attempts_left=25
while :; do
    i=$((i + 1))
    HOST="$(eval "echo \${WAIT_FOR_${i}:-}")"
    [ -n "${HOST}" ] || break
    if ! wait-for-it.sh "${HOST}" -t 3; then
        warn "${HOST} not reachable yet, retrying"
        i=$((i - 1))
        attempts_left=$((attempts_left - 1))
        if [ "${attempts_left}" -le 0 ]; then
            warn "dependencies never came up; giving up"
            exit 255
        fi
    fi
done

# ---------------------------------------------------------------------------
# Allocator selection — architecture-independent (resolve the multiarch dir,
# don't hardcode x86_64). Falls back to glibc malloc if the lib is absent.
# ---------------------------------------------------------------------------
MULTIARCH="$(dpkg-architecture -qDEB_HOST_MULTIARCH 2>/dev/null || echo '')"
LIBDIR="/usr/lib/${MULTIARCH}"
pick_lib() { for f in "$@"; do [ -e "$f" ] && { echo "$f"; return 0; }; done; return 1; }
case "${MALLOC:-mimalloc}" in
    jemalloc)
        LD_PRELOAD="$(pick_lib "${LIBDIR}/libjemalloc.so.2" /usr/lib/*/libjemalloc.so.2 || true)"
        ;;
    none)
        LD_PRELOAD=""
        ;;
    *)  # mimalloc (default)
        LD_PRELOAD="$(pick_lib "${LIBDIR}/libmimalloc-secure.so" /usr/lib/*/libmimalloc-secure.so || true)"
        ;;
esac
if [ -n "${LD_PRELOAD}" ]; then
    export LD_PRELOAD
    log "Allocator: ${MALLOC:-mimalloc} (${LD_PRELOAD})"
else
    unset LD_PRELOAD
    log "Allocator: glibc malloc (preload lib not found / MALLOC=none)"
fi

# ---------------------------------------------------------------------------
# Daily reload to pick up renewed TLS certs.
# ---------------------------------------------------------------------------
(
    while :; do
        sleep 1d
        dovecot reload || warn "dovecot reload failed"
    done
) &

if command -v pyzor >/dev/null 2>&1; then
    log "Pinging pyzor servers..."
    pyzor ping || warn "pyzor ping failed (non-fatal)"
fi

exec /usr/sbin/dovecot -F
