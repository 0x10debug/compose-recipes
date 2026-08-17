#!/usr/bin/env bash
# lib/common.sh — Common functions for mb recipes
# Sourced by mb and all suite scripts. Do not execute directly.

set -euo pipefail

# ── Version ──────────────────────────────────────────────────────────────────

MB_RECIPES_VERSION="1.0.0"

# ── Paths ────────────────────────────────────────────────────────────────────

MB_RECIPES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
MB_SUITES_DIR="${MB_RECIPES_DIR}/suites"
MB_DATA_DIR="${MB_DATA_DIR:-/data}"
MB_DEPLOY_DIR="${MB_DEPLOY_DIR:-/opt/mb-recipes}"

# ── Colors ───────────────────────────────────────────────────────────────────

if [ -t 1 ]; then
    MB_RED='\033[0;31m' MB_GREEN='\033[0;32m' MB_YELLOW='\033[0;33m'
    MB_BLUE='\033[0;34m' MB_BOLD='\033[1m' MB_DIM='\033[2m' MB_RESET='\033[0m'
else
    MB_RED='' MB_GREEN='' MB_YELLOW='' MB_BLUE='' MB_BOLD='' MB_DIM='' MB_RESET=''
fi

# ── Logging ──────────────────────────────────────────────────────────────────

mb_step()    { echo -e "\n${MB_BOLD}${MB_BLUE}▶ $*${MB_RESET}"; }
mb_info()    { echo -e "  ${MB_DIM}ℹ${MB_RESET} $*"; }
mb_detail()  { echo -e "  ${MB_DIM}·${MB_RESET} $*"; }
mb_success() { echo -e "  ${MB_GREEN}✓${MB_RESET} $*"; }
mb_warn()    { echo -e "  ${MB_YELLOW}⚠${MB_RESET} $*" >&2; }
mb_error()   { echo -e "  ${MB_RED}✗${MB_RESET} $*" >&2; }
mb_die()     { mb_error "$*"; exit 1; }

# ── Interactive helpers ──────────────────────────────────────────────────────

mb_ask() {
    local prompt="$1" default="${2:-y}"
    local yn
    if [ "$default" = "y" ]; then
        read -rp "$(echo -e "  ${MB_BOLD}?${MB_RESET} ${prompt} [Y/n] ")" yn </dev/tty
        [[ "$yn" =~ ^[Nn]$ ]] && return 1 || return 0
    else
        read -rp "$(echo -e "  ${MB_BOLD}?${MB_RESET} ${prompt} [y/N] ")" yn </dev/tty
        [[ "$yn" =~ ^[Yy]$ ]] && return 0 || return 1
    fi
}

mb_ask_value() {
    local prompt="$1" default="${2:-}"
    local value
    if [ -n "$default" ]; then
        read -rp "$(echo -e "  ${MB_BOLD}?${MB_RESET} ${prompt} [${default}]: ")" value </dev/tty
        echo "${value:-$default}"
    else
        read -rp "$(echo -e "  ${MB_BOLD}?${MB_RESET} ${prompt}: ")" value </dev/tty
        echo "$value"
    fi
}

mb_ask_secret() {
    local prompt="$1"
    local secret
    read -rsp "$(echo -e "  ${MB_BOLD}?${MB_RESET} ${prompt}: ")" secret </dev/tty
    echo "" >&2
    echo "$secret"
}

# ── Checks ───────────────────────────────────────────────────────────────────

mb_check_command() { command -v "$1" >/dev/null 2>&1; }

mb_check_docker() {
    if ! mb_check_command docker; then
        mb_die "Docker is not installed. Run vps-bootstrap first: https://github.com/0x10debug/vps-bootstrap"
    fi
    if ! docker info >/dev/null 2>&1; then
        mb_die "Docker daemon is not running. Start it with: sudo systemctl start docker"
    fi
}

mb_check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        mb_die "This command must be run as root (or with sudo)."
    fi
}

# ── Suite discovery ──────────────────────────────────────────────────────────

mb_list_suites() {
    local found=0
    for dir in "$MB_SUITES_DIR"/*/; do
        [ -d "$dir" ] || continue
        local name
        name=$(basename "$dir")
        local desc=""
        if [ -f "${dir}compose.yml" ]; then
            # Try to extract description from suite README
            if [ -f "${dir}README.md" ]; then
                desc=$(head -1 "${dir}README.md" | sed 's/^# *//')
            fi
            echo "${name}|${desc}"
            found=$((found + 1))
        fi
    done
    return $found
}

mb_suite_exists() {
    local suite="$1"
    [ -f "${MB_SUITES_DIR}/${suite}/compose.yml" ]
}

mb_suite_deployed() {
    local suite="$1"
    [ -f "${MB_DEPLOY_DIR}/${suite}/.deployed" ]
}

# ── Random generation ────────────────────────────────────────────────────────

mb_gen_password() {
    local length="${1:-32}"
    # Use /dev/urandom for cryptographically secure random
    LC_ALL=C tr -dc 'a-zA-Z0-9' < /dev/urandom | head -c "$length"
}

mb_gen_uuid() {
    cat /proc/sys/kernel/random/uuid 2>/dev/null || uuidgen 2>/dev/null || python3 -c "import uuid; print(uuid.uuid4())"
}
