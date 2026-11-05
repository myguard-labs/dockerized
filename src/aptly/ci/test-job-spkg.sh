#!/bin/bash
# job_spkg must return the whole source package name from a queue job name.
set -euo pipefail

worker="$(dirname "$0")/../aptly-queue-worker.sh"
eval "$(sed -n '/^job_spkg() {$/,/^}$/p' "$worker")"
declare -F job_spkg >/dev/null || { echo "FAIL: job_spkg not found in $worker"; exit 1; }

fail=0
check() {
    local got
    got=$(job_spkg "$1")
    if [ "$got" = "$2" ]; then
        echo "ok: $1 -> $got"
    else
        echo "FAIL: $1 -> '$got', expected '$2'"
        fail=1
    fi
}

check 1762300000-123-nginx-bookworm-amd64 nginx
check 1762300000-123-openssl-nginx-bookworm-amd64 openssl-nginx
check 1762300000-123-modsecurity-crs-trixie-all modsecurity-crs
check 1762300000-123-libfilesys-diskusage-perl-noble-arm64 libfilesys-diskusage-perl
check 1762300000-123-pkg-bookworm-all pkg

# Negative control: the old third-field parse must fail this test's expectation.
old=$(printf '%s\n' 1762300000-123-openssl-nginx-bookworm-amd64 | awk -F- '{print $3}')
if [ "$old" = "openssl-nginx" ]; then
    echo "FAIL: negative control did not truncate"
    fail=1
fi

exit "$fail"
