#!/bin/bash
# Shared release-version resolution for the mailstrix target.
#
# Sourced by build/daily.sh AND build/buildx-sequential.sh so the gh->git
# fallback logic lives in ONE place instead of being copy-pasted (they used to
# drift). See memory/dockerized/issues.md — 2026-06-30 release-timing 404 race,
# 2026-07-12 GitHub owner move eilandert -> myguard-labs.

# Canonical GitHub repo that PUBLISHES mailstrix releases. Moved from
# eilandert/mailstrix -> myguard-labs/mailstrix (2026-07-12). NOTE: the Docker
# Hub image namespace is separate (docker.io/eilandert/mailstrix — the registry
# account, DOCKER_REGISTRY_USER); do not conflate. Override for testing via env.
MAILSTRIX_GH_REPO="${MAILSTRIX_GH_REPO:-myguard-labs/mailstrix}"

# resolve_mailstrix_release <src_dir>
# Echo the version tag (leading 'v' stripped) whose GitHub *release* carries the
# per-arch assets Dockerfile.release pulls. Prefer the latest PUBLISHED release
# via gh — a git tag can exist (or be pushed) before its release+assets are, and
# building from that 404s (2026-06-30). Fall back to the nearest git tag only
# when gh is unavailable (no network/auth). Echoes "" if neither resolves; the
# caller decides whether to skip the target (empty VERSION trips
# Dockerfile.release's `test -n "${VERSION}"` guard and fails the build).
resolve_mailstrix_release() {
    local src_dir="$1" ver
    ver="$(gh release view --repo "$MAILSTRIX_GH_REPO" --json tagName -q .tagName 2>/dev/null | sed 's/^v//')"
    if [[ -z "$ver" ]]; then
        ver="$(git -C "$src_dir" describe --tags --abbrev=0 2>/dev/null | sed 's/^v//')"
    fi
    printf '%s' "$ver"
}

# mailstrix_source_version <src_dir>
# git describe (tag + commit, e.g. v1.2.0-3-gabc1234) baked into the binary's
# main.version ldflag / surfaced on its /version endpoint. Falls back to "dev".
mailstrix_source_version() {
    local src_dir="$1"
    git -C "$src_dir" describe --tags --always 2>/dev/null || echo dev
}

# image_built_from <commit-sha> <image-ref> <platform>...
# True only when <commit-sha> is a full 40-hex SHA, at least one platform is
# required, the published image has every required platform, and each of its
# platforms is labelled org.opencontainers.image.revision=<commit-sha>.
# Anything else (a symbolic ref like "main", an unreachable registry, a
# mixed-revision manifest, a missing architecture, malformed inspect output)
# returns false so the caller builds. buildx-sequential.sh uses it to skip
# rebuilding mailstrix:testing when main has not moved.
image_built_from() {
    local sha="$1" image="$2" inspect_output
    shift 2
    [[ "$sha" =~ ^[0-9a-f]{40}$ ]] || return 1
    (( $# > 0 )) || return 1
    inspect_output="$(docker buildx imagetools inspect "$image" --format '{{json .Image}}' 2>/dev/null)" \
        || return 1
    # A single-platform image is one config object; key it by its own
    # os/architecture[/variant] so it compares like a multi-platform map.
    jq -e --arg sha "$sha" '
        (if has("config")
         then {(.os + "/" + .architecture + (if .variant then "/" + .variant else "" end)): .}
         else . end) as $imgs
        | ($imgs | map(.config.Labels["org.opencontainers.image.revision"] // "") | unique) == [$sha]
          and ($ARGS.positional - ($imgs | keys) | length) == 0' \
        --args "$@" <<<"$inspect_output" >/dev/null 2>&1
}
