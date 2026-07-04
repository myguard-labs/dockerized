#!/bin/bash
# daily.sh — cron entrypoint for the nightly dockerized image rebuild.
#
# Wraps build/buildx-sequential.sh (builds every target and pushes it). Adds: a
# flock so a run never overlaps a manual or previous run, supply-chain
# provenance (VCS_REF / BUILD_DATE), and a Discord alert to #builds whenever a
# target fails to build.
#
# Cron (host-config/crontabs/eilander.crontab), 12:00 UTC via CRON_TZ=UTC:
#   0 12 * * *  /opt/packages/eilandert/dockerized/build/daily.sh \
#                 >>/opt/packages/log/dockerized-daily.log 2>&1
#
# Manual dry run (no push):  PUSH=0 ./build/daily.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DISCORD="/opt/packages/tools/discord-notify.py"
LOCK="/tmp/dockerized-daily.lock"

cd "$REPO_DIR" || exit 1

# --- single-run guard ----------------------------------------------------------
exec 9>"$LOCK"
if ! flock -n 9; then
    echo "[daily] another dockerized build holds $LOCK — aborting" >&2
    exit 0
fi

echo "============================================================"
echo "[daily] dockerized build start: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "============================================================"

# --- push by default ----------------------------------------------------------
# buildx-sequential.sh only auto-enables push when `uname -n == build`, but the
# build now runs on builder02 (the old "build" host .11 is dead — see
# memory/lessons/reference-aptly-hosts.md). The daily job's whole point is to
# ship, so default PUSH=1 here; override with `PUSH=0 ./build/daily.sh` for a
# local dry run.
export PUSH="${PUSH:-1}"
echo "[daily] PUSH=$PUSH"

# --- supply-chain provenance (consumed by docker-bake.hcl _meta) ---------------
export VCS_REF="$(git -C "$REPO_DIR" rev-parse --short HEAD 2>/dev/null || echo unknown)"
export BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"
# yarad's own source version (its submodule, not the dockerized superrepo) for
# its main.version ldflag / /version endpoint.
export MAILSTRIX_VERSION="$(git -C "$REPO_DIR/src/mailstrix" describe --tags --always 2>/dev/null || echo dev)"
# The tag of the LATEST *published GitHub release* — Dockerfile.release curls the
# per-arch binaries from it, so it must be a release that actually has assets.
# Ask GitHub directly (gh) instead of git describe: a git tag can exist locally
# (or be pushed) before its release is published, and HEAD is often ahead of the
# nearest release tag — both cases made describe point at a tag with no assets,
# so the daily build 404'd (e.g. 2026-06-30: cron ran 12:00 UTC, v1.2.0 release
# published 21:56). gh release view --latest always tracks the real release.
export MAILSTRIX_RELEASE="$(gh release view --repo eilandert/mailstrix --json tagName -q .tagName 2>/dev/null | sed 's/^v//')"
# Fallback to the nearest git tag if gh is unavailable (no network/auth).
[[ -z "$MAILSTRIX_RELEASE" ]] && \
    export MAILSTRIX_RELEASE="$(git -C "$REPO_DIR/src/mailstrix" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//' || echo "")"
# If BOTH gh and git describe came back empty (gh unauth/rate-limited AND no local
# tag), do NOT invoke the mailstrix target with an empty VERSION build-arg —
# Dockerfile.release's `test -n "${VERSION}"` guard would abort mid-build and mark
# the whole daily run failed. Fail loud, skip mailstrix, let the rest build.
SKIP_MAILSTRIX=""
if [[ -z "$MAILSTRIX_RELEASE" ]]; then
    echo "[daily] WARN: could not resolve MAILSTRIX_RELEASE (gh + git describe both empty) — skipping debian-mailstrix this run" >&2
    SKIP_MAILSTRIX=1
    export SKIP_MAILSTRIX
fi
echo "[daily] VCS_REF=$VCS_REF BUILD_DATE=$BUILD_DATE MAILSTRIX_VERSION=$MAILSTRIX_VERSION MAILSTRIX_RELEASE=$MAILSTRIX_RELEASE SKIP_MAILSTRIX=${SKIP_MAILSTRIX:-0}"

# --- run the orchestrator, capturing output for the summary --------------------
RUN_LOG="$(mktemp /tmp/dockerized-daily-run.XXXXXX.log)"
set +e
./build/buildx-sequential.sh 2>&1 | tee "$RUN_LOG"
RC=${PIPESTATUS[0]}
set -e 2>/dev/null || true

# --- pull the summary numbers + failed list out of the captured output ---------
SUMMARY="$(grep -E 'Successful:|Failed:' "$RUN_LOG" | tail -2)"
FAIL_LIST="$(grep -E '✗ (FAILED|TIMEOUT)' "$RUN_LOG" | sed 's/^[[:space:]]*/  /' | head -40)"

echo "[daily] exit=$RC"
echo "$SUMMARY"

# --- notify on any problem (cron has no TTY → discord-notify will send) --------
if [[ "$RC" -ne 0 ]]; then
    BODY="$(printf '%s\n' "$SUMMARY")"
    [[ -n "$FAIL_LIST" ]] && BODY="$(printf '%s\n\n**Build failures:**\n%s' "$BODY" "$FAIL_LIST")"
    BODY="$(printf '%s\n\nrev %s · full log on build host: /opt/packages/log/dockerized-daily.log' "$BODY" "$VCS_REF")"
    python3 "$DISCORD" message "🐳 dockerized daily: build failures" "$BODY" || true
else
    echo "[daily] all targets built + pushed — no alert"
fi

# --- sync Docker Hub long-descriptions from each src/<img>/README.md -----------
# Images were just pushed above; keep every Hub overview page in lock-step with
# its README.md. Non-fatal: a README-sync hiccup must never fail the build job.
if [[ "$PUSH" == 1 ]]; then
    echo "[daily] syncing Docker Hub READMEs"
    "$REPO_DIR/push-dockerhub-readmes.sh" || echo "[daily] README sync failed (non-fatal)" >&2
fi

rm -f "$RUN_LOG"
echo "[daily] done: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
exit "$RC"
