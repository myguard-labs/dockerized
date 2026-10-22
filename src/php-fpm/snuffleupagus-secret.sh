#!/bin/sh
# Give each container its own Snuffleupagus secret_key.
#
# The php*-snuffleupagus postinst fills in the key at package install, which
# in an image means build time: every container of a published image would
# share it. The image build puts the package placeholder back, and the
# bootstraps call this after populating /etc/php. A key that is already set
# (a mounted /etc/php, or an earlier start) is kept and reused, because all
# rulebooks of one host must share the same key.
#
# Usage: snuffleupagus-secret [php-config-root]   (default /etc/php)

set -eu

ROOT="${1:-/etc/php}"
PLACEHOLDER='YOU _DO_ NEED TO CHANGE THIS WITH SOME RANDOM CHARACTERS.'

files=$(grep -lF "${PLACEHOLDER}" "${ROOT}"/*/php-snuffleupagus/*.rules 2>/dev/null) || exit 0

key=$(sed -n 's/^sp\.global\.secret_key("\([^"]*\)");.*/\1/p' \
        "${ROOT}"/*/php-snuffleupagus/*.rules 2>/dev/null \
      | grep -vxF "${PLACEHOLDER}" | grep -x '[A-Za-z0-9]\{32,\}' | head -n 1) || true
if [ -z "${key}" ]; then
    key=$(tr -dc 'A-Za-z0-9' < /dev/urandom | head -c 64)
    echo "[PHP] generated Snuffleupagus secret_key"
fi
[ "${#key}" -ge 32 ] || { echo "[PHP] FATAL: could not obtain a Snuffleupagus secret_key" >&2; exit 1; }

for f in ${files}; do
    sed -i "s/YOU _DO_ NEED TO CHANGE THIS WITH SOME RANDOM CHARACTERS\./${key}/g" "${f}"
done
