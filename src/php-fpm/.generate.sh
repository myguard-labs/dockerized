#!/bin/bash
# Generate PHP-FPM Dockerfiles for multiple PHP versions
# Sources config.sh for PHP versions and docker registry settings
# Includes ubuntu and debian variants
# Usage: php-fpm/.generate.sh

set -e

SCRIPTDIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPTDIR"
source ../../build/generate-lib.sh
source ../../build/config.sh

TEMPLATE_PHP="Dockerfile-template.php"
TEMPLATE_HEADER="Dockerfile-template.header"
TEMPLATE_FOOTER="Dockerfile-template.footer"

check_template "$TEMPLATE_PHP" || exit 1
check_template "$TEMPLATE_HEADER" || exit 1
check_template "$TEMPLATE_FOOTER" || exit 1

log_info "Generating PHP-FPM Dockerfiles..."
log_info "  PHP versions: ${PHP_VERSIONS[*]}"
log_info "  Docker registry: ${DOCKER_REGISTRY_PREFIX}"

# Step 1: Generate individual version Dockerfiles
#
# For each PHP version we render the .php template and then, for every
# #removedinphpXY# marker, either strip the line (if this PHP version is
# >= XY, package no longer exists) or strip just the marker tag and keep
# the package line. Previously the marker was only handled for the exact
# version named in a map, which left markers in place for 8.x — apt then
# saw "#removedinphp80#php8.4-json" as a package name and the leading "#"
# turned the rest of the apt-get install line into a shell comment, so
# every package after the first marker silently dropped out. See audit.
# Strip a list of extensions from a PHP package list for a given version.
# Usage: strip_exts <file> <php-version> <ext1> <ext2> ...
# Matches "php<ver>-<ext>" with word boundary so php8.4-memcache doesn't also
# kill php8.4-memcached.
strip_exts() {
    local file="$1" version="$2"
    shift 2
    local ext
    for ext in "$@"; do
        sed -i -E "/[[:space:]]php${version}-${ext}([[:space:]\\\\]|$)/d" "$file"
    done
}

# Ubuntu-only strips: ondrej-noble lacks PECL extras + 8.4+ imap/pspell.
apply_ubuntu_strips() {
    local file="$1" version="$2"
    strip_exts "$file" "$version" "${PHP_UBUNTU_MISSING_EXTS[@]}"
    local ext cutoff
    for ext in "${!PHP_UBUNTU_MISSING_CUTOFF[@]}"; do
        cutoff="${PHP_UBUNTU_MISSING_CUTOFF[$ext]}"
        if version_ge "$version" "$cutoff"; then
            strip_exts "$file" "$version" "$ext"
        fi
    done
}

log_info "  Generating individual PHP versions..."
temp_files=()

for version in "${PHP_VERSIONS[@]}"; do
    temp="Dockerfile-template.generated.php${version}"
    log_info "    PHP $version"

    process_template "$TEMPLATE_PHP" "$temp" "PHPVERSION=$version"

    for marker in "${!PHP_REMOVAL_CUTOFF[@]}"; do
        strip_marker_for_version "$temp" "$version" "$marker" "${PHP_REMOVAL_CUTOFF[$marker]}"
    done

    # Per-version mirror gaps that apply to BOTH distros (so they land on
    # the temp BEFORE concat into the multi Dockerfile).
    if [[ -n "${PHP_VERSION_MISSING_EXTS[$version]:-}" ]]; then
        # shellcheck disable=SC2086  # intentional word splitting
        strip_exts "$temp" "$version" ${PHP_VERSION_MISSING_EXTS[$version]}
    fi

    # Assert no markers leaked through — generator bug if they did.
    # Only match the actual #removedinphpXY# tag form to avoid false hits
    # on the explanatory comment header inside the template.
    if grep -qE '#removedinphp[0-9]+#' "$temp"; then
        log_error "    Leftover #removedinphp...# marker in $temp"
        grep -nE '#removedinphp[0-9]+#' "$temp" >&2
        exit 1
    fi

    temp_files+=("$temp")
done

# The ucf stub wrapped around every PHP install. ucf asks debconf about each
# module .ini it registers (~250 ms each, much slower under QEMU arm64), but a
# fresh install has nothing to ask. A copy of ucf with its debconf block
# disabled runs for this one install; the real ucf is put back after.
# roundcube and vimbadmin carry the same lines; ci/test_ucf_stub.py keeps
# them in sync.
IFS= read -r -d '' UCF_STUB_ON <<'EOF' || true
    ucf_new= ;\
    dpkg-query -W -f='${Status}' ucf 2>/dev/null | grep -q 'ok installed' || { apt-get install -y --no-install-recommends ucf ; ucf_new=1 ; } ;\
    dpkg-divert --local --rename --divert /usr/bin/ucf.real --add /usr/bin/ucf ;\
    sed -e '2i db_stop() { :; }' -e 's|^if \[ -e /usr/share/debconf/confmodule \]; then|if false; then|' /usr/bin/ucf.real > /usr/bin/ucf ;\
    grep -q '^if false; then' /usr/bin/ucf || cp /usr/bin/ucf.real /usr/bin/ucf ;\
    chmod 0755 /usr/bin/ucf ;\
EOF
IFS= read -r -d '' UCF_STUB_OFF <<'EOF' || true
    rm -f /usr/bin/ucf ;\
    dpkg-divert --local --rename --remove /usr/bin/ucf ;\
    [ -z "$ucf_new" ] || apt-mark auto ucf ;\
    test -x /usr/bin/ucf ; test ! -e /usr/bin/ucf.real
EOF

# php_install_run <temp>... prints one install RUN holding every package of
# the given per-version temps, wrapped in the ucf stub. Multi used to get one
# RUN per version, each paying apt and ucf startup again; one RUN halves the
# multi build. The RUN prologue comes from the first temp. Line endings are
# rebuilt here, so a stripped package line can't leave a dangling "\".
php_install_run() {
    UCF_STUB_ON="$UCF_STUB_ON" UCF_STUB_OFF="$UCF_STUB_OFF" awk '
        FNR == 1 { files++; inst = 0 }
        /apt-get install -y --no-install-recommends \\$/ {
            if (inst) { bad = FILENAME ": second install line"; exit }
            inst = 1; seen++
            if (files == 1) install = $0
            next
        }
        !inst { if (files == 1) prologue = prologue $0 "\n"; next }
        /^[[:space:]]*$/ { next }
        {
            line = $0
            sub(/[[:space:]]*\\$/, "", line)
            if (line !~ /^[[:space:]]+php[0-9.]+(-[a-z0-9]+)?$/) { bad = FILENAME ": not a package: " $0; exit }
            pkgs[++n] = line
        }
        END {
            if (bad == "" && seen != files) bad = "missing install line"
            if (bad == "" && n == 0) bad = "no packages"
            if (bad != "") { print "php_install_run: " bad > "/dev/stderr"; exit 1 }
            printf "%s%s", prologue, ENVIRON["UCF_STUB_ON"]
            sub(/apt-get install/, "UCF_FORCE_CONFFNEW=1 apt-get install", install)
            print install
            for (i = 1; i <= n; i++) print pkgs[i] (i < n ? " \\" : " ;\\")
            printf "%s\n", ENVIRON["UCF_STUB_OFF"]
        }' "$@"
}

# write_dockerfile <output> <temp>... = header + one install RUN + footer.
write_dockerfile() {
    local output="$1"
    shift
    {
        cat "$TEMPLATE_HEADER"
        php_install_run "$@"
        cat "$TEMPLATE_FOOTER"
    } > "$output"
}

ubuntu_base="${DOCKER_REGISTRY_PREFIX}/${IMAGE_PREFIX_UBUNTU_BASE}:${UBUNTU_BASE_TAG}"
debian_base="${DOCKER_REGISTRY_PREFIX}/${IMAGE_PREFIX_DEBIAN_BASE}:${DEBIAN_BASE_TAG}"

# Ubuntu-only strips land on a copy of each temp, so Debian keeps its PECL/
# snuffleupagus/imap/pspell packages (the trixie mirror has them).
ubuntu_temps=()
for version in "${PHP_VERSIONS[@]}"; do
    temp="Dockerfile-template.generated.php${version}"
    cp "$temp" "$temp.ubu"
    apply_ubuntu_strips "$temp.ubu" "$version"
    ubuntu_temps+=("$temp.ubu")
done

# Step 2: Build individual Dockerfiles from header + version + footer
log_info "  Building complete Dockerfiles..."
for version in "${PHP_VERSIONS[@]}"; do
    # Normalize version: remove dots (5.6 -> 56, 7.4 -> 74, etc.)
    normalized_version="${version//.}"

    temp="Dockerfile-template.generated.php${version}"
    ubuntu_output="Dockerfile-${normalized_version}-ubu"
    debian_output="Dockerfile-${normalized_version}-deb"

    log_info "    $ubuntu_output"
    write_dockerfile "$ubuntu_output" "$temp.ubu"
    write_dockerfile "$debian_output" "$temp"

    for output in "$ubuntu_output" "$debian_output"; do
        # Set both #PHPVERSION# (env var) and #VERSION# (OCI image.version label)
        safe_sed "#PHPVERSION#" "$version" "$output"
        safe_sed "#VERSION#"    "$version" "$output"

        # Comment out the rm -rf for this PHP version (keep all versions in single Dockerfile potential)
        safe_sed "rm -rf /etc/php/${version}" "#rm -rf /etc/php/${version}" "$output"
    done

    # Replace registry/tag with config values
    safe_sed "eilandert/ubuntu-base:rolling" "$ubuntu_base" "$ubuntu_output"
    safe_sed "eilandert/ubuntu-base:rolling" "$debian_base" "$debian_output"
done

# Step 3: Build multi-PHP Dockerfile
log_info "  Building multi-PHP variant..."
multi_output="Dockerfile-multi-ubu"
multi_debian="Dockerfile-multi-deb"
write_dockerfile "$multi_output" "${ubuntu_temps[@]}"
write_dockerfile "$multi_debian" "${temp_files[@]}"

for output in "$multi_output" "$multi_debian"; do
    safe_sed "#PHPVERSION#" "MULTI" "$output"
    safe_sed "#VERSION#"    "multi" "$output"
    safe_sed "MODE=FPM" "MODE=MULTI" "$output"
    safe_sed "rm -rf /etc/php" "#rm -rf /etc/php" "$output"
done
safe_sed "eilandert/ubuntu-base:rolling" "$ubuntu_base" "$multi_output"
safe_sed "eilandert/ubuntu-base:rolling" "$debian_base" "$multi_debian"

# Step 4: Clean up temp files
rm -f Dockerfile-template.generated.*

log_info "✓ PHP-FPM Dockerfiles generated (${#PHP_VERSIONS[@]} PHP versions + multi + debian variants)"
