#!/usr/bin/env bash
# lib/network.sh — Docker network management for mb recipes
# Ensures the shared proxy network exists for reverse proxy integration.

# The shared network name — used by network-toolkit's reverse proxy
# and all compose-recipes suites. Applications join this network so
# the reverse proxy can route to them by container name.
MB_PROXY_NETWORK="${MB_PROXY_NETWORK:-mb-proxy}"

mb_network_ensure_proxy() {
    if ! docker network inspect "$MB_PROXY_NETWORK" >/dev/null 2>&1; then
        mb_info "Creating shared proxy network: $MB_PROXY_NETWORK"
        docker network create "$MB_PROXY_NETWORK" >/dev/null 2>&1
        mb_detail "Network created (external reverse proxy can now join)"
    else
        mb_detail "Proxy network already exists: $MB_PROXY_NETWORK"
    fi
}

mb_network_list() {
    echo "  Docker networks:"
    docker network ls --format "    {{.Name}}\t{{.Driver}}\t{{.Scope}}" 2>/dev/null | head -20
}

mb_network_check_proxy() {
    if docker network inspect "$MB_PROXY_NETWORK" >/dev/null 2>&1; then
        return 0
    else
        return 1
    fi
}
