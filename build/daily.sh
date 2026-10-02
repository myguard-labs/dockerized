#!/bin/bash
# daily.sh — cron entrypoint for the nightly dockerized image rebuild.
#
# Wraps build/buildx-sequential.sh (builds every target and pushes it). Adds: a
# flock so a run never overlaps a manual or previous run, supply-chain
# provenance (VCS_REF / BUILD_DATE), and a Discord alert to #builds whenever a
# target fails to build.
#
# Cron (host-config/crontabs/eilander.crontab), 12:00 UTC via CRON_TZ=UTC:
#   0 12 * * *  /opt/myguard/dockerized/build/daily.sh \
#                 >>/opt/myguard/packages/log/dockerized-daily.log 2>&1
#
# Manual dry run (no push):  PUSH=0 ./build/daily.sh

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(dirname "$SCRIPT_DIR")"
DISCORD="/opt/myguard/tools/discord-notify.py"
LOCK="/tmp/dockerized-daily.lock"

# Shared mailstrix release-version resolution (gh -> git fallback), also used by
# buildx-sequential.sh — single source of truth.
# shellcheck source=lib-release.sh
source "$SCRIPT_DIR/lib-release.sh"

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
# mailstrix source version (tag+commit) for its main.version ldflag / /version
# endpoint, and the published-release tag Dockerfile.release pulls per-arch
# binaries from. Both via lib-release.sh (gh -> git fallback, see the race
# fixed 2026-06-30). If the release tag comes back empty, buildx-sequential.sh
# skips the mailstrix target itself (empty VERSION would trip its build guard),
# so no SKIP flag needs threading through here — just warn for visibility.
export MAILSTRIX_VERSION="$(mailstrix_source_version "$REPO_DIR/src/mailstrix")"
export MAILSTRIX_RELEASE="$(resolve_mailstrix_release "$REPO_DIR/src/mailstrix")"
# mailstrix:testing builds the current main commit; pin it so the git context
# and the image's revision label agree. Falls back to "main" if unresolved.
MAILSTRIX_MAIN_REF="$(git ls-remote "https://github.com/$MAILSTRIX_GH_REPO.git" refs/heads/main 2>/dev/null | cut -f1)"
export MAILSTRIX_MAIN_REF="${MAILSTRIX_MAIN_REF:-main}"
[[ -z "$MAILSTRIX_RELEASE" ]] && \
    echo "[daily] WARN: could not resolve MAILSTRIX_RELEASE (gh + git describe both empty) — debian-mailstrix will be skipped this run" >&2
echo "[daily] VCS_REF=$VCS_REF BUILD_DATE=$BUILD_DATE MAILSTRIX_VERSION=$MAILSTRIX_VERSION MAILSTRIX_RELEASE=$MAILSTRIX_RELEASE MAILSTRIX_MAIN_REF=$MAILSTRIX_MAIN_REF"

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
    BODY="$(printf '%s\n\nrev %s · full log on build host: /opt/myguard/packages/log/dockerized-daily.log' "$BODY" "$VCS_REF")"
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
