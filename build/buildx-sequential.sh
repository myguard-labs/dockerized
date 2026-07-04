#!/bin/bash
# Docker buildx SEQUENTIAL builder across 4 dependency layers
# Builds one target at a time (NOT parallel) to maintain order and simplicity

set -e

# Disable buildx fs entitlement prompt. roundcube is the only target with
# external named build-contexts (../roundcube-skin-*); without this, buildx
# prompts "grant requested privileges? [y/N]" on the tty, which backgrounds the
# proc (SIGTTIN) when stdout/stderr are redirected to per-target logs and the
# build fails non-interactively with "ERROR: additional privileges requested".
# See memory/eilandert/dockerized/issues.md (2026-06-11).
export BUILDX_BAKE_ENTITLEMENTS_FS=0

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_warning() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_build() {
    echo -e "${CYAN}[BUILD]${NC} $1"
}

# Format seconds into human readable format (HH:MM:SS)
format_time() {
    local seconds=$1
    local hours=$((seconds / 3600))
    local minutes=$(((seconds % 3600) / 60))
    local secs=$((seconds % 60))
    printf "%02d:%02d:%02d" $hours $minutes $secs
}

# PUSH gate.
#   - Explicit override: PUSH=1 / PUSH=0 in the environment wins.
#   - Default: enabled on the build host (hostname == "build"), disabled elsewhere.
# Set LOAD=1 (mutually exclusive with PUSH) to load images into the local docker
# daemon so they can be `docker run` on a dev box.
PUSH_ARG=""
if [[ -n "${PUSH:-}" ]]; then
    if [[ "$PUSH" == "1" || "$PUSH" == "true" ]]; then
        PUSH_ARG="--push"
        log_info "Push enabled (PUSH=$PUSH)"
    else
        log_info "Push explicitly disabled (PUSH=$PUSH)"
    fi
elif [ "$(uname -n)" == "build" ]; then
    PUSH_ARG="--push"
    log_info "Push enabled (build host)"
else
    log_warning "Running on $(uname -n), push disabled (set PUSH=1 to override)"
fi

if [[ -z "$PUSH_ARG" && "${LOAD:-0}" == "1" ]]; then
    PUSH_ARG="--load"
    log_info "Load enabled — images will be imported into the local docker daemon"
fi

# Ensure all git submodules are present + checked out before anything reads them.
# Several targets bake their source from nested submodules (olefied, mailstrix,
# rspamd-dcc-razor-pyzor); a host with an empty or stale submodule checkout would
# build missing/outdated code. generate.sh (below) reads these trees, so sync
# first and hard-fail if it can't.
#   DOCKERIZED_SUBMODULE_REMOTE=1  → pull each submodule's tracked-branch tip
#                                    (latest code) instead of the recorded pin.
#   DOCKERIZED_NO_SUBMODULE_SYNC=1 → skip entirely (offline builds).
if [[ "${DOCKERIZED_NO_SUBMODULE_SYNC:-0}" != "1" ]]; then
    _SM_ROOT="$(git -C "$(dirname "${BASH_SOURCE[0]}")" rev-parse --show-toplevel 2>/dev/null)"
    if [[ -n "$_SM_ROOT" ]]; then
        _SM_REMOTE=""
        [[ "${DOCKERIZED_SUBMODULE_REMOTE:-0}" == "1" ]] && _SM_REMOTE="--remote"
        log_info "Syncing git submodules (recursive${_SM_REMOTE:+, remote tips})..."
        git -C "$_SM_ROOT" submodule sync --recursive >/dev/null 2>&1 || true
        if ! git -C "$_SM_ROOT" submodule update --init --recursive $_SM_REMOTE; then
            log_error "git submodule update failed — sources may be missing/stale"
            exit 1
        fi
    else
        log_warning "Not a git checkout — skipping submodule sync"
    fi
fi

# Remote aptly sync — track failure so it shows up in the final summary
# instead of silently letting the rest of the run use stale packages.
APTLY_SYNC_OK=1
log_info "Syncing with remote aptly server..."
if ! ssh -p 8889 aptly@192.168.178.3 /aptly/scripts/daily.sh; then
    log_warning "Remote aptly sync failed — continuing with possibly stale packages"
    APTLY_SYNC_OK=0
fi

# Track last run
date > /tmp/dockerized.lastrun

# Generate dockerfiles and prepare other things
log_info "Generating Dockerfiles..."
if ! ./generate.sh; then
    log_error "generate.sh failed"
    exit 1
fi

# Change to parent directory for docker buildx
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR"
cd "$PROJECT_ROOT"

# Persistent build cache directory - shared across all targets and runs
DEFAULT_CACHE_ROOT="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}"
CACHE_DIR="${BUILDX_CACHE_DIR:-$DEFAULT_CACHE_ROOT/dockerized-buildx}"
mkdir -p "$CACHE_DIR"
log_info "Using build cache: $CACHE_DIR"

# Create (or reuse) a named buildx builder. Named so we can clean up exactly
# what we created, and so concurrent runs don't trip over each other.
BUILDER_NAME="${BUILDX_BUILDER:-dockerized-build}"
log_info "Preparing buildx builder: $BUILDER_NAME"
if ! docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
    docker buildx create --name "$BUILDER_NAME" --use >/dev/null
else
    docker buildx use "$BUILDER_NAME"
fi

# NOTE: previously this script ran `docker system prune -f -a` before and
# after the loop. That nukes every image on the host (hostile to anything
# else running on this machine) and forces a full re-pull of the official
# ubuntu/debian bases every run. Cache lives in $CACHE_DIR; let buildkit
# manage its own state. Set DOCKERIZED_PRUNE=1 to opt back in.
if [[ "${DOCKERIZED_PRUNE:-0}" == "1" ]]; then
    log_warning "DOCKERIZED_PRUNE=1 — running 'docker system prune -f -a'"
    docker system prune -f -a 2>/dev/null || true
fi

# Define build targets organized by dependency layer
# PHP versions built: 5.6, 7.4, 8.0, 8.2, 8.4, 8.5
declare -a LAYERS=(
    # Layer 1: Base images (2 targets) - FROM official upstream images only
    "ubuntu-base debian-base"

    # Layer 2: PHP-FPM and Databases - depends on base images
    # Includes: 56, 74, 80, 82, 84, 85, multiphp, mariadb, valkey
    "ubuntu-phpfpm56 debian-phpfpm56 ubuntu-phpfpm74 debian-phpfpm74 ubuntu-phpfpm80 debian-phpfpm80 ubuntu-phpfpm82 debian-phpfpm82 ubuntu-phpfpm84 debian-phpfpm84 ubuntu-phpfpm85 debian-phpfpm85 ubuntu-multiphp debian-multiphp ubuntu-mariadb debian-mariadb ubuntu-valkey debian-valkey"

    # Layer 3: Web servers with PHP - depends on PHP-FPM
    # Includes nginx/angie/apache with: 56, 74, 80, 82, 84, 85
    "ubuntu-nginx-php56 debian-nginx-php56 ubuntu-nginx-php74 debian-nginx-php74 ubuntu-nginx-php80 debian-nginx-php80 ubuntu-nginx-php82 debian-nginx-php82 ubuntu-nginx-php84 debian-nginx-php84 ubuntu-nginx-php85 debian-nginx-php85 ubuntu-nginx-multi debian-nginx-multi ubuntu-angie-php56 debian-angie-php56 ubuntu-angie-php74 debian-angie-php74 ubuntu-angie-php80 debian-angie-php80 ubuntu-angie-php82 debian-angie-php82 ubuntu-angie-php84 debian-angie-php84 ubuntu-angie-php85 debian-angie-php85 ubuntu-angie-multi debian-angie-multi debian-apache-php56 debian-apache-php74 debian-apache-php80 debian-apache-php82 debian-apache-php84 debian-apache-php85 debian-apache-multiphp ubuntu-apache-php56 ubuntu-apache-php74 ubuntu-apache-php80 ubuntu-apache-php82 ubuntu-apache-php84 ubuntu-apache-php85 ubuntu-apache-multiphp"
    
    # Layer 4: Other web servers and services - depends on base images
    "debian-nginx ubuntu-nginx debian-angie ubuntu-angie debian-angie-cms ubuntu-postfix debian-postfix debian-rspamd-git debian-rspamd debian-rspamd-official ubuntu-rspamd debian-rspamd-drp debian-olefied debian-mailstrix debian-dovecot debian-roundcube debian-webtest debian-vimbadmin ubuntu-reprepro debian-sitewarmup alpine-letsencrypt rbldnsd alpine-unbound aptly debian-openssh"
)

echo ""
log_info "========================================="
log_info "SEQUENTIAL BUILD MODE (One target at a time)"
log_info "========================================="
echo ""

FAILED=0
SUCCESS=0
TOTAL_TARGETS=0
CURRENT_TARGET_NUM=0
BUILD_START_TIME=$(date +%s)
declare -a FAILED_TARGETS=()

# Calculate total targets
for LAYER in "${LAYERS[@]}"; do
    for target in $LAYER; do
        TOTAL_TARGETS=$((TOTAL_TARGETS+1))
    done
done

log_info "Total targets to build: $TOTAL_TARGETS"
log_info "Estimated time: ~90-120 minutes (30s-1m per target)"
echo ""

echo "========================================="
log_info "MONITORING:"
echo "========================================="
log_info "Watch progress in another terminal:"
log_info "  tail -f /tmp/buildx-target-*.log"
log_info "Or count completed targets:"
log_info "  ls /tmp/buildx-target-*.log | wc -l"
echo ""

LAYER_NUM=1
for LAYER in "${LAYERS[@]}"; do
    layer_size=0
    for target in $LAYER; do
        layer_size=$((layer_size+1))
    done
    
    echo "========================================="
    log_info "Layer $LAYER_NUM ($layer_size targets)"
    echo "========================================="
    echo ""
    
    TARGET_IN_LAYER=0
    for TARGET in $LAYER; do
        TARGET_IN_LAYER=$((TARGET_IN_LAYER+1))
        CURRENT_TARGET_NUM=$((CURRENT_TARGET_NUM+1))
        TARGET_START_TIME=$(date +%s)
        
        # Progress display
        pct=$((CURRENT_TARGET_NUM * 100 / TOTAL_TARGETS))
        log_build "[$CURRENT_TARGET_NUM/$TOTAL_TARGETS ($pct%)] Layer $LAYER_NUM, Target $TARGET_IN_LAYER/$layer_size: $TARGET"

        # mailstrix needs a non-empty VERSION (Dockerfile.release's
        # `test -n "${VERSION}"` guard). daily.sh normally exports MAILSTRIX_RELEASE,
        # but a direct `buildx-sequential.sh` call (or a gh hiccup) can leave it
        # empty — then bake would pass VERSION="" and the target aborts, counting as
        # a failure. Resolve it here as a self-contained last resort (gh → git tag),
        # and only if BOTH fail skip the target cleanly instead of building broken.
        if [[ "$TARGET" == "debian-mailstrix" ]]; then
            if [[ -z "${MAILSTRIX_RELEASE:-}" ]]; then
                MAILSTRIX_RELEASE="$(gh release view --repo eilandert/mailstrix --json tagName -q .tagName 2>/dev/null | sed 's/^v//')"
                [[ -z "$MAILSTRIX_RELEASE" ]] && \
                    MAILSTRIX_RELEASE="$(git -C "$PROJECT_ROOT/src/mailstrix" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
                export MAILSTRIX_RELEASE
            fi
            if [[ -z "$MAILSTRIX_RELEASE" ]]; then
                log_warning "Skipping $TARGET — could not resolve MAILSTRIX_RELEASE (gh + git tag both empty)"
                continue
            fi
            log_info "  mailstrix VERSION=$MAILSTRIX_RELEASE"
        fi
        
        # Individual log per target
        TARGET_LOG="/tmp/buildx-target-$TARGET.log"
        rm -f "$TARGET_LOG"
        
        # Build single target (30 minute timeout per target)
        if timeout 1800 docker buildx bake -f "$PROJECT_ROOT/docker-bake.hcl" \
        --builder "$BUILDER_NAME" \
        --set "*.cache-from=type=local,src=$CACHE_DIR" \
        --set "*.cache-to=type=local,dest=$CACHE_DIR,mode=max" \
        --progress=plain \
        ${PUSH_ARG} $TARGET > "$TARGET_LOG" 2>&1; then
            
            SUCCESS=$((SUCCESS+1))
            TARGET_ELAPSED=$(($(date +%s) - TARGET_START_TIME))
            log_info "  ✓ SUCCESS ($(format_time $TARGET_ELAPSED))"
            
        else
            EXIT_CODE=$?
            TARGET_ELAPSED=$(($(date +%s) - TARGET_START_TIME))
            if [ $EXIT_CODE -eq 124 ]; then
                log_error "  ✗ TIMEOUT (exceeded 30 minutes / $(format_time $TARGET_ELAPSED))"
            else
                log_error "  ✗ FAILED ($(format_time $TARGET_ELAPSED) exit code: $EXIT_CODE)"
            fi
            
            # Show full log path and error excerpt
            log_error "  Full log: /tmp/buildx-target-$TARGET.log"
            if grep -q "ERROR\|error:" "$TARGET_LOG" 2>/dev/null; then
                log_error "  Error summary:"
                grep -E "(ERROR|error:|FAILED)" "$TARGET_LOG" 2>/dev/null | head -2 | sed 's/^/    /'
            fi
            
            FAILED=$((FAILED+1))
            FAILED_TARGETS+=("$TARGET")
        fi
        echo ""
    done
    
    log_info "Layer $LAYER_NUM: $SUCCESS/$CURRENT_TARGET_NUM targets completed"
    echo ""
    LAYER_NUM=$((LAYER_NUM+1))
done

# Cleanup — only remove the builder we explicitly created above.
# Skip the system-wide image prune; the local cache directory is what matters.
log_info "Cleaning up buildx builder $BUILDER_NAME..."
docker buildx rm "$BUILDER_NAME" 2>/dev/null || true
if [[ "${DOCKERIZED_PRUNE:-0}" == "1" ]]; then
    docker system prune -f -a 2>/dev/null || true
fi

# Surface aptly-sync failure in the final summary too
if [[ "$APTLY_SYNC_OK" == "0" ]]; then
    log_warning "Remote aptly sync FAILED earlier in this run — built packages may be stale."
fi

# Final Summary
echo ""
echo "========================================="
log_info "BUILD COMPLETE"
# Summary - save to file and print
SUMMARY_FILE="/tmp/buildx-summary-$(date +%s).txt"
{
    echo "========================================="
    echo "Build Summary"
    echo "========================================="
    echo "Successful: $SUCCESS/$TOTAL_TARGETS"
    echo "Failed: $FAILED/$TOTAL_TARGETS"
    BUILD_ELAPSED=$(($(date +%s) - BUILD_START_TIME))
    echo "Total Time: $(format_time $BUILD_ELAPSED)"
    echo ""
    
    if [ $SUCCESS -eq $TOTAL_TARGETS ]; then
        echo "✓ All targets built successfully!"
    else
        echo ""
        echo "========================================="
        echo "FAILED TARGETS SUMMARY ($FAILED failures)"
        echo "========================================="
        for i in "${!FAILED_TARGETS[@]}"; do
            target="${FAILED_TARGETS[$i]}"
            echo ""
            echo "[$((i+1))/$FAILED] $target"
            
            # Show error details from log
            TARGET_LOG="/tmp/buildx-target-$target.log"
            if [ -f "$TARGET_LOG" ]; then
                if grep -q "TIMEOUT\|timeout" "$TARGET_LOG" 2>/dev/null; then
                    echo "  └─ Reason: Build timeout (exceeded 30 minutes)"
                    elif grep -q "permission denied" "$TARGET_LOG" 2>/dev/null; then
                    echo "  └─ Reason: Permission denied (Docker daemon access)"
                    elif grep -q "ERROR\|error:" "$TARGET_LOG" 2>/dev/null; then
                    echo "  └─ Error details:"
                    grep -E "(ERROR|error:|FAILED)" "$TARGET_LOG" 2>/dev/null | head -2 | sed 's/^/     /'
                else
                    echo "  └─ See full log: $TARGET_LOG"
                fi
            fi
        done
        echo ""
        echo "========================================="
        echo "To investigate failures, run:"
        echo "  tail -100 /tmp/buildx-target-<target-name>.log"
        echo "========================================="
    fi
} | tee "$SUMMARY_FILE"

echo ""
BUILD_ELAPSED=$(($(date +%s) - BUILD_START_TIME))
echo "========================================="
echo -e "  ${GREEN}Successful${NC}: $SUCCESS/$TOTAL_TARGETS"
echo -e "  ${RED}Failed${NC}: $FAILED/$TOTAL_TARGETS"
echo -e "  ${BLUE}Total Time${NC}: $(format_time $BUILD_ELAPSED)"
echo ""

if [ $SUCCESS -eq $TOTAL_TARGETS ]; then
    log_info "✓ All targets built successfully!"
else
    echo ""
    echo "========================================="
    log_warning "FAILED TARGETS SUMMARY ($FAILED failures)"
    echo "========================================="
    for i in "${!FAILED_TARGETS[@]}"; do
        target="${FAILED_TARGETS[$i]}"
        echo ""
        echo -e "${RED}[$((i+1))/$FAILED]${NC} $target"
        
        # Show error details from log
        TARGET_LOG="/tmp/buildx-target-$target.log"
        if [ -f "$TARGET_LOG" ]; then
            if grep -q "TIMEOUT\|timeout" "$TARGET_LOG" 2>/dev/null; then
                echo "  └─ Reason: Build timeout (exceeded 30 minutes)"
                elif grep -q "permission denied" "$TARGET_LOG" 2>/dev/null; then
                echo "  └─ Reason: Permission denied (Docker daemon access)"
                elif grep -q "ERROR\|error:" "$TARGET_LOG" 2>/dev/null; then
                echo "  └─ Error details:"
                grep -E "(ERROR|error:|FAILED)" "$TARGET_LOG" 2>/dev/null | head -2 | sed 's/^/     /'
            else
                echo "  └─ See full log: $TARGET_LOG"
            fi
        fi
    done
    echo ""
    echo "========================================="
    echo -e "To investigate failures, run:"
    echo "  tail -100 /tmp/buildx-target-<target-name>.log"
    echo "========================================="
    echo ""
fi

echo ""
log_info "Summary saved to: $SUMMARY_FILE"
echo ""

if [ $FAILED -gt 0 ]; then
    exit 1
fi
