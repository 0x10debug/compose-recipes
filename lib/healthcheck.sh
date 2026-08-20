#!/usr/bin/env bash
# lib/healthcheck.sh — Health-check helpers for mb recipes
# Sourced by mb and all suite scripts. Do not execute directly.
#
# These functions complement the per-service `healthcheck:` blocks defined in
# each compose.yml. They let the operator (or the `mb` CLI) wait for a deployed
# suite to reach a healthy state after `docker compose up -d`, and to inspect
# the health of individual containers from the host.

# ── Single-container health status ───────────────────────────────────────────

# mb_health_status <container_name>
#   Prints the Docker health status of a container: starting | healthy |
#   unhealthy | none (no healthcheck defined) | missing (container not found).
mb_health_status() {
    local container="$1"
    if ! docker inspect "$container" >/dev/null 2>&1; then
        echo "missing"
        return 1
    fi
    local status
    status=$(docker inspect --format='{{if .State.Health}}{{.State.Health.Status}}{{else}}none{{end}}' "$container" 2>/dev/null)
    echo "${status:-none}"
}

# mb_health_wait <container_name> [timeout_seconds]
#   Blocks until the container reports "healthy" or the timeout elapses.
#   Returns 0 if healthy, 1 on timeout or if the container has no healthcheck
#   (status "none") / does not exist.
mb_health_wait() {
    local container="$1"
    local timeout="${2:-120}"
    local elapsed=0
    local status

    # Fast path: already healthy.
    status=$(mb_health_status "$container") || { mb_warn "Container not found: $container"; return 1; }
    [ "$status" = "healthy" ] && return 0
    [ "$status" = "none" ] && { mb_warn "No healthcheck defined for: $container"; return 1; }

    mb_detail "Waiting for $container to become healthy (timeout ${timeout}s)..."
    while [ "$elapsed" -lt "$timeout" ]; do
        sleep 3
        elapsed=$((elapsed + 3))
        status=$(mb_health_status "$container") || { mb_warn "Container disappeared: $container"; return 1; }
        case "$status" in
            healthy)
                mb_success "$container is healthy (${elapsed}s)"
                return 0
                ;;
            unhealthy)
                mb_warn "$container is unhealthy after ${elapsed}s"
                return 1
                ;;
            starting)
                # keep waiting
                ;;
            none|missing)
                mb_warn "Cannot check health of $container (status: $status)"
                return 1
                ;;
        esac
    done
    mb_warn "Timed out waiting for $container after ${timeout}s (last status: $status)"
    return 1
}

# ── Suite-level health aggregation ───────────────────────────────────────────

# mb_health_wait_suite <suite> [timeout_seconds]
#   Waits for every running container belonging to a deployed suite to become
#   healthy. Containers without a healthcheck are skipped (with a warning).
#   Returns 0 only if all checkable containers are healthy.
mb_health_wait_suite() {
    local suite="$1"
    local timeout="${2:-180}"
    local deploy_dir="${MB_DEPLOY_DIR}/${suite}"
    local failures=0
    local checked=0

    if [ ! -d "$deploy_dir" ]; then
        mb_warn "Suite not deployed: $suite ($deploy_dir not found)"
        return 1
    fi

    # List running containers for this project (compose sets project=label).
    local project
    project=$(basename "$deploy_dir")
    local containers
    containers=$(docker compose -f "${deploy_dir}/compose.yml" --project-name "$project" ps -q 2>/dev/null \
        | xargs -r docker inspect --format='{{.Name}}' 2>/dev/null \
        | sed 's|^/||')

    if [ -z "$containers" ]; then
        mb_warn "No running containers found for suite: $suite"
        return 1
    fi

    mb_step "Checking health of suite: $suite"
    for c in $containers; do
        local status
        status=$(mb_health_status "$c") || { mb_warn "  $c — missing"; failures=$((failures + 1)); continue; }
        case "$status" in
            healthy)
                mb_success "  $c — healthy"
                checked=$((checked + 1))
                ;;
            none)
                mb_detail "  $c — no healthcheck (skipped)"
                ;;
            starting|unhealthy)
                # Try to wait for it.
                if mb_health_wait "$c" "$timeout"; then
                    checked=$((checked + 1))
                else
                    failures=$((failures + 1))
                fi
                ;;
            *)
                mb_warn "  $c — unknown status: $status"
                failures=$((failures + 1))
                ;;
        esac
    done

    if [ "$failures" -gt 0 ]; then
        mb_error "$failures container(s) failed health check for suite: $suite"
        return 1
    fi
    mb_success "All checkable containers healthy for suite: $suite ($checked checked)"
    return 0
}

# ── Host-side fallback probes ────────────────────────────────────────────────
# Use these when a container has no Docker healthcheck or when probing from
# the host (e.g. through a reverse proxy).

# mb_health_tcp <host> <port> [timeout_seconds]
#   Returns 0 if a TCP connection to host:port succeeds.
mb_health_tcp() {
    local host="$1" port="$2" timeout="${3:-5}"
    if mb_check_command nc; then
        nc -z -w "$timeout" "$host" "$port" >/dev/null 2>&1
    elif mb_check_command timeout; then
        timeout "$timeout" bash -c "echo > /dev/tcp/${host}/${port}" >/dev/null 2>&1
    else
        bash -c "echo > /dev/tcp/${host}/${port}" >/dev/null 2>&1
    fi
}

# mb_health_http <url> [timeout_seconds]
#   Returns 0 if the URL returns a 2xx/3xx HTTP status. Tries curl first, then
#   wget. Follows redirects.
mb_health_http() {
    local url="$1" timeout="${2:-5}"
    if mb_check_command curl; then
        curl -LfsS --max-time "$timeout" -o /dev/null "$url"
    elif mb_check_command wget; then
        wget -q --spider --timeout="$timeout" "$url"
    else
        mb_die "Neither curl nor wget is available for HTTP health check"
    fi
}

# mb_health_report [suite]
#   Prints a one-line-per-container health summary. If <suite> is omitted, all
#   running containers are listed.
mb_health_report() {
    local suite="${1:-}"
    local containers
    if [ -n "$suite" ]; then
        local deploy_dir="${MB_DEPLOY_DIR}/${suite}"
        local project
        project=$(basename "$deploy_dir")
        containers=$(docker compose -f "${deploy_dir}/compose.yml" --project-name "$project" ps -q 2>/dev/null \
            | xargs -r docker inspect --format='{{.Name}}' 2>/dev/null | sed 's|^/||')
    else
        containers=$(docker ps --format '{{.Names}}')
    fi

    if [ -z "$containers" ]; then
        mb_warn "No running containers to report on."
        return 0
    fi

    printf '%-28s %-12s %s\n' "CONTAINER" "HEALTH" "STATUS"
    for c in $containers; do
        local status health
        status=$(mb_health_status "$c" 2>/dev/null || echo "missing")
        health=$(docker inspect --format='{{.State.Status}}' "$c" 2>/dev/null || echo "unknown")
        printf '%-28s %-12s %s\n' "$c" "$status" "$health"
    done
}
