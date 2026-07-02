#!/bin/bash
# Docker base image configuration
# Central source of truth for all dockerized build parameters

# ============================================================================
# DISTRO VERSIONS
# ============================================================================

# Ubuntu LTS / Latest stable to use for base image FROM clause
export UBUNTULTS="resolute"

# Debian stable version to use for base image FROM clause
export DEBIANSTABLE="trixie"

# ============================================================================
# DOCKER BASE IMAGE TAG NAMING
# ============================================================================
# These tags are used when referencing already-built base images in FROM lines
# e.g., FROM eilandert/ubuntu-base:rolling

export UBUNTU_BASE_TAG="rolling"       # Tag for ubuntu-base image
export DEBIAN_BASE_TAG="stable"        # Tag for debian-base image

# ============================================================================
# DOCKER REGISTRY CONFIGURATION
# ============================================================================

export DOCKER_REGISTRY_DOMAIN="docker.io"
export DOCKER_REGISTRY_USER="eilandert"

# Full registry prefix for use in image references
export DOCKER_REGISTRY_PREFIX="${DOCKER_REGISTRY_DOMAIN}/${DOCKER_REGISTRY_USER}"

# ============================================================================
# IMAGE NAME PREFIXES
# ============================================================================

export IMAGE_PREFIX_UBUNTU_BASE="ubuntu-base"
export IMAGE_PREFIX_DEBIAN_BASE="debian-base"
export IMAGE_PREFIX_PHP_FPM="php-fpm"
export IMAGE_PREFIX_NGINX="nginx"
export IMAGE_PREFIX_ANGIE="angie"
export IMAGE_PREFIX_APACHE="apache-phpfpm"

# ============================================================================
# PHP VERSIONS TO BUILD
# ============================================================================
# Used by: php-fpm/.generate.sh, nginx/.generate.sh, apache-phpfpm/.generate.sh

declare -ga PHP_VERSIONS=(5.6 7.4 8.0 8.2 8.4 8.5)

# ============================================================================
# REPOSITORY INFORMATION
# ============================================================================

export GITHUB_REPO_URL="https://github.com/myguard-labs/dockerized"
export GITHUB_REPO_USER="eilandert"

# ============================================================================
# PHP VERSION REMOVAL MARKERS
# ============================================================================
# Used in php-fpm/.generate.sh. The template marks ext lines that disappear
# in a given PHP version with #removedinphpXY# (e.g. #removedinphp80#php-json).
#
# A line tagged "removedinphpXY" must be deleted from every Dockerfile whose
# PHP version is >= X.Y, because the package no longer exists upstream. The
# generator computes this list dynamically from PHP_VERSIONS now — this map
# is kept for documentation / override only.
#
# Threshold for each marker (cutoff version at/above which the line is dropped):
declare -gA PHP_REMOVAL_CUTOFF=(
    [removedinphp72]="7.2"
    [removedinphp74]="7.4"
    [removedinphp80]="8.0"
)

# ============================================================================
# PHP PACKAGES MISSING FROM ondrej-php Ubuntu mirror (resolute)
# ============================================================================
# The deb.myguard.nl ondrej-php mirror is well-stocked for Debian trixie but
# for Ubuntu resolute it ships only the bare php<ver>-<core-ext> packages — no
# PECL extras, no snuffleupagus, and imap/pspell disappear at 8.4+.
# These maps drive Ubuntu-only line strips in src/php-fpm/.generate.sh.

# Extensions absent from the Ubuntu mirror for every PHP version.
declare -ga PHP_UBUNTU_MISSING_EXTS=(
    igbinary
    imagick
    memcache
    memcached
    redis
    zstd
    snuffleupagus
)

# Extensions absent from the Ubuntu mirror starting at a given PHP version.
declare -gA PHP_UBUNTU_MISSING_CUTOFF=(
    [imap]="8.4"
    [pspell]="8.4"
)

# ============================================================================
# PHP PACKAGES MISSING PER VERSION (both distros)
# ============================================================================
# Mirror gaps that apply to single AND multi-distro Dockerfiles, both
# Ubuntu and Debian. Applied on the per-version template chunk before
# concat, so the multi-distro Dockerfile inherits the strip.
declare -gA PHP_VERSION_MISSING_EXTS=(
    [5.6]="igbinary imagick memcache memcached redis zstd snuffleupagus"
    [8.5]="opcache"
)
