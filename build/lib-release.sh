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
# building from that 404s (2026-06-30). Fall back to the nearest git RELEASE tag
# (v<digits>...; the moving prerelease tags `nightly` and `rules-current` are
# reachable and must never win) only when gh is unavailable (no network/auth). Echoes "" if neither resolves; the
# caller decides whether to skip the target (empty VERSION trips
# Dockerfile.release's `test -n "${VERSION}"` guard and fails the build).
resolve_mailstrix_release() {
    local src_dir="$1" ver
    ver="$(gh release view --repo "$MAILSTRIX_GH_REPO" --json tagName -q .tagName 2>/dev/null | sed 's/^v//')"
    if [[ -z "$ver" ]]; then
        ver="$(git -C "$src_dir" describe --tags --abbrev=0 --match 'v[0-9]*' 2>/dev/null | sed 's/^v//')"
    fi
    printf '%s' "$ver"
}

# mailstrix_source_version <src_dir>
# git describe over release tags only (v<digits>..., never the moving `nightly`
# / `rules-current` tags; tag + commit, e.g. v1.2.0-3-gabc1234) baked into the binary's
# main.version ldflag / surfaced on its /version endpoint. Falls back to "dev".
mailstrix_source_version() {
    local src_dir="$1"
    git -C "$src_dir" describe --tags --always --match 'v[0-9]*' 2>/dev/null || echo dev
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

# is_full_sha <ref> -- true only for a 40-hex commit SHA (lowercase).
is_full_sha() {
    [[ "${1:-}" =~ ^[0-9a-f]{40}$ ]]
}

# resolve_mailstrix_main_ref -- echo the current mailstrix main commit SHA, or ""
# when `git ls-remote` fails, returns nothing or returns something that is not a
# 40-hex SHA. The caller must treat "" as unbound, never as a moving ref.
resolve_mailstrix_main_ref() {
    local out
    out="$(git ls-remote "https://github.com/$MAILSTRIX_GH_REPO.git" refs/heads/main 2>/dev/null | cut -f1)" \
        || out=""
    is_full_sha "$out" && printf '%s' "$out"
    return 0
}

# testing_prebuild_decision <push-arg> <force> <main-ref>
# Echo what to do with debian-mailstrix-testing before building:
#   build   -- non-push (ad-hoc) build, or forced: proceed (bake default applies)
#   unbound -- push mode and the ref is not a 40-hex SHA: skip with a warning,
#              never publish an unbound :testing (force does not override this)
#   check   -- push mode, bound ref: skip only if the published image is current
testing_prebuild_decision() {
    local push_arg="$1" force="$2" ref="$3"
    if [[ "$push_arg" != "--push" ]]; then
        echo build
    elif ! is_full_sha "$ref"; then
        echo unbound
    elif [[ "$force" == "1" ]]; then
        echo build
    else
        echo check
    fi
}

# testing_version <main-sha> -- the VERSION baked into :testing (strixd /version
# "version" field and `strixd version`): testing-<first 12 hex of the commit>.
# Must stay in sync with docker-bake.hcl's substr(MAILSTRIX_MAIN_REF, 0, 12).
testing_version() {
    printf 'testing-%s' "${1:0:12}"
}

# verify_testing_identity <main-sha> <image-ref> <platform>...
# After a push: true only when every platform's revision label equals <main-sha>
# (image_built_from) AND a bounded amd64 `docker run` of the pulled image reports
# `strixd testing-<sha12>`. Registry unreachable, mismatch or run failure -> false.
verify_testing_identity() {
    local sha="$1" image="$2" out
    image_built_from "$@" || return 1
    out="$(timeout 180 docker run --rm --pull always --platform linux/amd64 \
        --label "myguard.run=dockerized-testing-identity-$$" \
        --name "dockerized-testing-identity-$$" "$image" version 2>/dev/null)" || return 1
    [[ "$out" == "strixd $(testing_version "$sha")" ]]
}
