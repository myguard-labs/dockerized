#!/bin/bash
set -e

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

# Ensure the push is only initiated on build machine
PUSH=""
if [ "$(uname -n)" == "build" ]; then
    PUSH="--push"
    log_info "Push enabled for build machine"
else
    log_warning "Running on $(uname -n), push disabled"
fi

# Remote aptly sync
log_info "Syncing with remote aptly server..."
ssh -p 8889 aptly@192.168.178.3 /aptly/scripts/daily.sh || log_warning "Remote sync failed, continuing anyway"

# Track last run
date > /tmp/dockerized.lastrun

# Generate dockerfiles and prepare other things
log_info "Generating Dockerfiles..."
if ! ./generate.sh; then
    log_error "generate.sh failed"
    exit 1
fi

# Change to parent directory for docker buildx (contexts need to be relative to project root)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
BUILD_DIR="$SCRIPT_DIR"
cd "$PROJECT_ROOT"

# Clean up any existing buildx instances
log_info "Cleaning up buildx..."
docker buildx rm 2>/dev/null || true
docker system prune -f -a

# Create new buildx instance
log_info "Creating buildx instance..."
docker buildx create --use

# Dependency graph (based on FROM in Dockerfiles):
#   Layer 1: ubuntu:* / debian:*-slim  (official upstream images)
#   Layer 2: eilandert/*-base:*        (FROM Layer 1 base images)
#   Layer 3: eilandert/php-fpm:*       (FROM Layer 2 phpfpm images)
#
# Layer 2 includes BOTH phpfpm/db images AND standalone services - they all depend
# only on Layer 1 and can build in parallel, saving the time of a separate Layer 4.

declare -a LAYERS=(
    # Layer 1: Base images - build in parallel
    "resolute noble jammy trixie rolling devel"

    # Layer 2: PHP-FPM, databases, and all standalone services
    "ubuntu-phpfpm56 debian-phpfpm56 ubuntu-phpfpm74 debian-phpfpm74 ubuntu-phpfpm80 debian-phpfpm80 ubuntu-phpfpm82 debian-phpfpm82 ubuntu-phpfpm84 debian-phpfpm84 ubuntu-phpfpm85 debian-phpfpm85 ubuntu-multiphp debian-multiphp ubuntu-mariadb debian-mariadb ubuntu-valkey debian-valkey debian-nginx ubuntu-nginx debian-angie ubuntu-angie ubuntu-postfix debian-postfix debian-rspamd-git debian-rspamd debian-rspamd-official ubuntu-rspamd debian-dovecot debian-roundcube debian-vimbadmin ubuntu-reprepro debian-sitewarmup alpine-letsencrypt rbldnsd alpine-unbound aptly debian-openssh"

    # Layer 3: Web servers with PHP - build in parallel (depends on layer 2)
    "ubuntu-nginx-php56 debian-nginx-php56 ubuntu-nginx-php74 debian-nginx-php74 ubuntu-nginx-php80 debian-nginx-php80 ubuntu-nginx-php82 debian-nginx-php82 ubuntu-nginx-php84 debian-nginx-php84 ubuntu-nginx-php85 ubuntu-nginx-php86 debian-nginx-php85 debian-nginx-php86 ubuntu-nginx-multi debian-nginx-multi ubuntu-angie-php56 debian-angie-php56 ubuntu-angie-php74 debian-angie-php74 ubuntu-angie-php80 debian-angie-php80 ubuntu-angie-php82 debian-angie-php82 ubuntu-angie-php84 debian-angie-php84 ubuntu-angie-php85 ubuntu-angie-php86 debian-angie-php85 debian-angie-php86 ubuntu-angie-multi debian-angie-multi debian-apache-php56 debian-apache-php74 debian-apache-php80 debian-apache-php82 debian-apache-php84 debian-apache-php85 debian-apache-php86 debian-apache-multiphp ubuntu-apache-php56 ubuntu-apache-php74 ubuntu-apache-php80 ubuntu-apache-php82 ubuntu-apache-php84 ubuntu-apache-php85 ubuntu-apache-php86 ubuntu-apache-multiphp"
)

# Persistent build cache directory - shared across all layers and runs
DEFAULT_CACHE_ROOT="${XDG_CACHE_HOME:-${HOME:-/tmp}/.cache}"
CACHE_DIR="${BUILDX_CACHE_DIR:-$DEFAULT_CACHE_ROOT/dockerized-buildx}"
mkdir -p "$CACHE_DIR"
log_info "Using build cache: $CACHE_DIR"


log_info "Starting parallel builds across ${#LAYERS[@]} dependency layers..."
echo ""
FAILED=0
SUCCESS=0
TOTAL_TARGETS=0
LAYER_NUM=1

# Calculate total targets for display
for LAYER in "${LAYERS[@]}"; do
    TARGET_COUNT=$(echo "$LAYER" | wc -w)
    ((TOTAL_TARGETS+=TARGET_COUNT))
done
log_info "Total targets to build: $TOTAL_TARGETS"
echo ""

for LAYER in "${LAYERS[@]}"; do
    TARGET_COUNT=$(echo "$LAYER" | wc -w)
    
    log_info "Building Layer $LAYER_NUM ($TARGET_COUNT targets in parallel)..."
    log_build "Targets: $(echo "$LAYER" | head -c 100)$([ ${#LAYER} -gt 100 ] && echo "...")"
    echo ""
    
    # Create progress log file for this layer
    LAYER_LOG="/tmp/buildx-layer-$LAYER_NUM.log"
    rm -f "$LAYER_LOG"
    
    # Build all targets in this layer with detailed progress
    # --progress=plain shows all build steps and target names
    # We tee to file and pipe to grep to show relevant progress
    if timeout 3600 docker buildx bake -f "$PROJECT_ROOT/docker-bake.hcl" \
    --set "*.cache-from=type=local,src=$CACHE_DIR" \
    --set "*.cache-to=type=local,dest=$CACHE_DIR,mode=max" \
    --progress=plain \
    ${PUSH} $LAYER > "$LAYER_LOG" 2>&1; then
        
        ((SUCCESS+=TARGET_COUNT))
        
        # Count successfully pushed/exported images
        COMPLETED=$(grep -c "DONE\|exporting\|pushing" "$LAYER_LOG" 2>/dev/null || echo "0")
        
        log_info "✓ Layer $LAYER_NUM complete - $TARGET_COUNT targets built"
        log_info "  Progress: $((SUCCESS))/$TOTAL_TARGETS targets completed"
        
    else
        # Check if timeout or actual error
        if [ $? -eq 124 ]; then
            log_error "✗ Build timeout for layer $LAYER_NUM (exceeded 3600s)"
        else
            log_error "✗ Build failed for layer $LAYER_NUM"
        fi
        
        # Show failed target hints
        if grep -q "ERROR\|error:" "$LAYER_LOG" 2>/dev/null; then
            log_error "Error details:"
            grep -E "(ERROR|error:|FAILED)" "$LAYER_LOG" 2>/dev/null | head -5 | sed 's/^/  /'
        fi
        
        ((FAILED+=TARGET_COUNT))
    fi
    
    echo ""
    ((LAYER_NUM++))
done

# Cleanup
log_info "Cleaning up buildx instance..."
docker buildx rm 2>/dev/null || true
docker system prune -f -a

# Summary
echo ""
echo "========================================="
log_info "Build Summary"
echo "========================================="
echo -e "  ${GREEN}Successful${NC}: $SUCCESS"
echo -e "  ${RED}Failed${NC}: $FAILED"
echo -e "  ${YELLOW}Total${NC}: $TOTAL_TARGETS"

if [ $SUCCESS -eq $TOTAL_TARGETS ]; then
    echo ""
    log_info "✓ All targets built successfully!"
else
    echo ""
    log_warning "⚠ Some targets failed. Build logs saved to:"
    for i in $(seq 1 $((LAYER_NUM-1))); do
        if [ -f "/tmp/buildx-layer-$i.log" ]; then
            echo "  /tmp/buildx-layer-$i.log"
        fi
    done
    echo ""
    log_warning "View logs with: tail -f /tmp/buildx-layer-*.log"
fi

echo ""

if [ $FAILED -gt 0 ]; then
    exit 1
fi
