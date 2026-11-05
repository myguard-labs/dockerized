#!/bin/bash
#
# aptly-queue-worker.sh — serialise every repo include + publish through one
# worker so concurrent builds never race on the published index.
#
# THE PROBLEM THIS SOLVES
#   aptly's `publish update` rewrites Packages/Packages.gz/Packages.bz2/Release/
#   InRelease NON-atomically into the live tree. When two uploads publish the
#   same dist near-simultaneously — or a build's pbuilder chroot runs
#   `apt-get update` mid-publish — apt sees a half-written index and aborts with
#   "File has unexpected size. Mirror sync in progress?". Per-repo flock in
#   process-incoming.sh only serialised WRITES to the same dist; it did not
#   serialise across dists, and nothing serialised the reader.
#
# THE MODEL
#   Builds drop a job dir under $QUEUE_DIR named
#       <epoch>-<pid>-<pkg>-<dist>-<arch>/
#   containing the .changes + payload, then atomically create a `.ready` marker
#   INSIDE it (the build writes <dir>/.uploading first, fills it, then renames
#   to <dir>/.ready). This worker watches $QUEUE_DIR with inotify, picks ready
#   jobs in TIMESTAMP order (the epoch prefix), and runs process-incoming.sh on
#   them ONE AT A TIME. Because a single worker processes the whole queue, every
#   include+publish is strictly serial regardless of how many builds upload at
#   once. A global flock guards against a second worker ever starting.
#
#   The worker writes the result back into the job dir so the build can poll it:
#       <dir>/.done    (exit 0; contains "0")
#       <dir>/.failed  (contains the non-zero exit code)
#   plus <dir>/worker.log with the full process-incoming output. The build
#   waits for .done/.failed and propagates the exit code, so callers still get
#   real pass/fail just like the old synchronous path. The build removes its own
#   job dir after reading the result; the worker also reaps stale dirs.
#
set -euo pipefail

QUEUE_DIR="${APTLY_QUEUE_DIR:-/aptly/queue}"
PROC="${APTLY_PROCESS_INCOMING:-/aptly/bin/process-incoming.sh}"
WORKER_LOCK="/tmp/aptly-queue-worker.lock"
STALE_HOURS="${APTLY_QUEUE_STALE_HOURS:-24}"

mkdir -p "${QUEUE_DIR}"

# Single-worker guard: if another worker holds the lock, exit quietly.
exec 8>"${WORKER_LOCK}"
if ! flock -n 8; then
    echo "[queue-worker] another worker already running; exiting" >&2
    exit 0
fi

log() { echo "[queue-worker $(date -u +%FT%TZ)] $*"; }

# inotifywait inherits fd 8 (the single-instance lock). If the worker dies
# without killing it, the orphaned inotifywait keeps the lock held — so the next
# worker exits "another worker already running" and the queue stalls forever
# (pgrep/fuser don't reveal it; only /proc/<pid>/fd does). Track the child and
# kill it on any exit so the lock always releases with the worker.
WATCH_PID=""
# Kill the tracked child AND sweep any inotifywait we parented — the tracked PID
# can be stale/empty at the instant a signal lands (between iterations), so a
# pkill -P backstop guarantees no inotifywait orphan survives holding the lock.
cleanup() {
    [ -n "${WATCH_PID}" ] && kill "${WATCH_PID}" 2>/dev/null
    pkill -P $$ inotifywait 2>/dev/null
    true
}
trap cleanup EXIT INT TERM

# Source package from a job name: <epoch>-<pid>-<pkg>-<dist>-<arch>. pkg may
# contain dashes (openssl-nginx), so it is everything between the pid and the
# dist; dist and arch are single tokens. A truncated pkg breaks the delete in
# process-incoming.sh: old versions pile up, or another source gets removed.
job_spkg() {
    printf '%s\n' "$1" | awk -F- '{s=$3; for(i=4;i<=NF-2;i++) s=s"-"$i; print s}'
}

# Process one job dir. Reads its .ready, derives DIST/REPO/SPKG from the
# directory name (epoch-pid-pkg-dist-arch), runs process-incoming.sh against the
# job dir, and writes .done/.failed back. Never aborts the worker on a job
# failure — a bad upload must not stop the queue.
process_job() {
    local jobdir="$1"
    local name; name=$(basename "${jobdir}")

    # Already handled (race between inotify event and the scan loop)?
    [ -e "${jobdir}/.done" ] || [ -e "${jobdir}/.failed" ] && return 0
    [ -e "${jobdir}/.ready" ] || return 0          # not finished uploading yet

    local spkg dist
    spkg=$(job_spkg "${name}")
    dist=$(printf '%s\n' "${name}" | awk -F- '{print $(NF-1)}')
    # REPO defaults to DIST but honour an explicit override file (openssl3 etc.)
    local repo="${dist}"
    [ -f "${jobdir}/.repo" ] && repo=$(cat "${jobdir}/.repo")

    log "processing ${name} (spkg=${spkg} dist=${dist} repo=${repo})"
    local rc=0
    SPKG="${spkg}" DIR="${jobdir}" DIST="${dist}" REPO="${repo}" \
        CREATE=yes DELETE=YES \
        "${PROC}" "${dist}" "${repo}" >"${jobdir}/worker.log" 2>&1 || rc=$?

    # Guard the result write: a build that timed out may have reaped its own job
    # dir mid-publish. Without the -d check the bare redirect fails and, under
    # `set -e`, kills the whole worker (queue then silently stalls until a human
    # notices). The -d test + 2>/dev/null + ||log keeps the worker alive.
    if [ "${rc}" -eq 0 ]; then
        [ -d "${jobdir}" ] && echo "0" > "${jobdir}/.done" 2>/dev/null || log "WARN result-write skipped ${name}"
        log "OK ${name}"
    else
        [ -d "${jobdir}" ] && echo "${rc}" > "${jobdir}/.failed" 2>/dev/null || log "WARN result-write skipped ${name}"
        log "FAILED ${name} (exit ${rc}) — see ${jobdir}/worker.log"
    fi
}

# Drain: process every ready job in timestamp (filename) order, oldest first.
# Loops until no ready-and-unhandled job remains, so jobs that arrived while we
# were busy are still picked up without waiting for a fresh inotify event.
drain_queue() {
    local progressed=1
    while [ "${progressed}" -eq 1 ]; do
        progressed=0
        local d
        # Sort by name → epoch prefix → arrival order.
        while IFS= read -r d; do
            [ -d "${d}" ] || continue
            [ -e "${d}/.ready" ] || continue
            [ -e "${d}/.done" ] || [ -e "${d}/.failed" ] && continue
            process_job "${d}"
            progressed=1
        done < <(find "${QUEUE_DIR}" -mindepth 1 -maxdepth 1 -type d | sort)
    done
}

# Reap job dirs the build never cleaned up (crashed mid-poll). Only dirs that
# already have a result and are older than STALE_HOURS, so we never delete a job
# a build is still reading.
reap_stale() {
    find "${QUEUE_DIR}" -mindepth 1 -maxdepth 1 -type d -mmin +$((STALE_HOURS*60)) \
        \( -name '*' \) 2>/dev/null | while IFS= read -r d; do
        if [ -e "${d}/.done" ] || [ -e "${d}/.failed" ]; then
            log "reaping stale ${d##*/}"
            rm -rf -- "${d}"
        fi
    done
}

log "started; watching ${QUEUE_DIR} (proc=${PROC})"

# Process anything already queued before we attach the watch (jobs that landed
# while the worker was down).
drain_queue
reap_stale

# Event loop. PERSISTENT monitor (-m): the previous one-shot inotifywait was
# re-armed AFTER drain_queue, so any .ready created in the window between drain
# finishing and the next inotifywait starting was MISSED — the job then sat
# unprocessed until the *next* build's event flushed it (builds appeared to
# hang). With -m the watch never stops, so no event can fall in a re-arm gap.
#
# close_write fires when a build finishes writing .ready; moved_to fires on the
# atomic .ready.tmp→.ready rename; create covers plain creation. We drain once
# up-front to catch jobs that landed while arming, then on every event line. The
# `read -t 30` gives an idle tick so reap_stale runs and a missed event (should
# be impossible with -m, but belt-and-suspenders) is bounded to 30s of lag.
# Event loop. The previous one-shot inotifywait was re-armed only AFTER
# drain_queue, so a .ready created in the gap between drain finishing and the
# next inotifywait starting was MISSED — the job sat until the next build's
# event flushed it (builds appeared to hang). Fix without a persistent monitor
# (FIFO/-m proved fragile under `set -e`): use a SHORT timeout so the worker
# self-drains every WATCH_INTERVAL seconds no matter what, bounding worst-case
# lag to that interval even if an event is missed. inotifywait still gives near-
# instant wakeups on the common path.
WATCH_INTERVAL="${APTLY_QUEUE_POLL:-5}"
while true; do
    inotifywait -q -t "${WATCH_INTERVAL}" -e close_write -e moved_to -e create \
        -r "${QUEUE_DIR}" >/dev/null 2>&1 &
    WATCH_PID=$!
    wait "${WATCH_PID}" 2>/dev/null || true
    WATCH_PID=""
    drain_queue
    reap_stale
done
