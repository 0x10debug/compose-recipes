#!/usr/bin/env bash
# docker-api-query.sh — query the Docker API through the socket-proxy
#
# Verifies that the proxy is filtering correctly: allowed endpoints return
# data, denied endpoints return 403. Run from a container on the same
# mb-socket-proxy network, or from the host if you've published a port
# (not recommended — the proxy is designed to be internal-only).
#
# Usage from a container on mb-socket-proxy:
#   docker run --rm --network mb-socket-proxy \
#     -v "$PWD/docker-api-query.sh:/query.sh:ro" \
#     curlimages/curl:8.11.1 /bin/sh /query.sh
#
# Or via docker compose --profile demo:
#   docker compose --profile demo up docker-api-demo

set -euo pipefail

PROXY_HOST="${SOCKET_PROXY_HOST:-socket-proxy}"
PROXY_PORT="${SOCKET_PROXY_PORT:-2375}"
BASE_URL="http://${PROXY_HOST}:${PROXY_PORT}"

echo "=== Docker Socket-Proxy API Query ==="
echo "Target: ${BASE_URL}"
echo ""

# ── Helper: print HTTP status code for a request ──────────────────────────────

check_endpoint() {
    local method="$1"
    local path="$2"
    local label="$3"

    local status
    status=$(curl -s -o /dev/null -w '%{http_code}' -X "${method}" "${BASE_URL}${path}" 2>/dev/null || echo "000")

    local verdict
    case "${status}" in
        200) verdict="OK (allowed)" ;;
        403) verdict="BLOCKED (denied)" ;;
        404) verdict="NOT FOUND" ;;
        000) verdict="UNREACHABLE" ;;
        *)   verdict="HTTP ${status}" ;;
    esac

    printf "  %-8s %-30s → HTTP %s  %s\n" "${method}" "${path}" "${status}" "${verdict}"
}

# ── Read-only endpoints ───────────────────────────────────────────────────────

echo "── Read-only endpoints ──"
check_endpoint "GET"  "/containers/json"    "list containers"
check_endpoint "GET"  "/info"               "daemon info"
check_endpoint "GET"  "/version"            "daemon version"
check_endpoint "GET"  "/images/json"        "list images"
check_endpoint "GET"  "/networks"           "list networks"
check_endpoint "GET"  "/volumes"            "list volumes"
check_endpoint "GET"  "/system/df"          "disk usage"
echo ""

# ── Write endpoints (should be 403 when POST=0) ───────────────────────────────

echo "── Write endpoints (expect 403 when POST=0) ──"
check_endpoint "POST" "/containers/create"  "create container"
check_endpoint "POST" "/build"              "build image"
check_endpoint "POST" "/commit"             "commit container"
echo ""

# ── Dangerous endpoints ───────────────────────────────────────────────────────

echo "── Dangerous endpoints (expect 403 when EXEC=0) ──"
check_endpoint "POST" "/exec/create"        "exec into container"
check_endpoint "GET"  "/secrets"            "list swarm secrets"
echo ""

echo "=== Done ==="
echo ""
echo "If any endpoint above returned 200 unexpectedly, check your .env —"
echo "you may have enabled more than intended. Review the endpoint reference"
echo "in README.md and disable anything you don't need."
