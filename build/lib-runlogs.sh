#!/bin/bash
# Per-run log hygiene and proxy pre-flight for buildx-sequential.sh.
# Sourced, not executed; every function takes explicit paths so ci/ can test it.

# Remove every per-target log left by a previous run, so `tail -f
# <dir>/buildx-target-*.log` only ever shows the current run.
clear_target_logs() {
    local dir="$1"
    rm -f -- "$dir"/buildx-target-*.log
}

# Remove the logs of targets that built successfully; failed targets keep
# theirs, so after a run the directory lists exactly what needs a look.
prune_success_logs() {
    local dir="$1"
    shift
    local target
    for target in "$@"; do
        rm -f -- "$dir/buildx-target-$target.log"
    done
}

# Print the HTTP proxy the docker CLI injects into every build
# (proxies.default.httpProxy in $DOCKER_CONFIG/config.json), or nothing.
docker_build_proxy() {
    local config="${DOCKER_CONFIG:-$HOME/.docker}/config.json"
    [[ -r "$config" ]] || return 0
    jq -r '.proxies.default.httpProxy // empty' "$config" 2>/dev/null || true
}

# Succeed when the proxy URL accepts a TCP connection (or no proxy is set).
# With the proxy down every apt step fails as "Unable to connect", so the
# caller aborts before spending a run on misleading per-target failures.
check_build_proxy() {
    local url="$1" hostport host port
    [[ -n "$url" ]] || return 0
    hostport="${url#*://}"
    hostport="${hostport%%/*}"
    hostport="${hostport##*@}"
    host="${hostport%:*}"
    port="${hostport##*:}"
    if [[ "$host" == "$hostport" || "$hostport" == *"]" ]]; then
        host="$hostport"
        port=80
    fi
    host="${host#[}"
    host="${host%]}"
    if [[ -z "$host" || ! "$port" =~ ^[0-9]+$ ]]; then
        echo "malformed build proxy URL: $url" >&2
        return 1
    fi
    # shellcheck disable=SC2016  # $1/$2 expand in the child shell
    if ! timeout 5 bash -c 'exec 3<>"/dev/tcp/$1/$2"' _ "$host" "$port" 2>/dev/null; then
        echo "build proxy $host:$port is not reachable" >&2
        return 1
    fi
}
