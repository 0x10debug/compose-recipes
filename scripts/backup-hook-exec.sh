#!/usr/bin/env bash
# scripts/backup-hook-exec.sh — Standalone wrapper for lib/backup-hooks.sh
#
# Usage:
#   ./scripts/backup-hook-exec.sh pre    --service postgres --config compose.yml
#   ./scripts/backup-hook-exec.sh post   --service postgres
#   ./scripts/backup-hook-exec.sh discover --config compose.yml
#   ./scripts/backup-hook-exec.sh pre    --all --config compose.yml   # batch pre
#   ./scripts/backup-hook-exec.sh post   --all --config compose.yml   # batch post
#
# Options:
#   --service NAME   Compose service to hook (required unless --all)
#   --all            Run the hook for every discovered database service
#   --config FILE    Path to compose.yml (default: ./compose.yml)
#   --output DIR     Dump output directory (default: /var/tmp/compose-backup-hooks)
#   --dry-run        Preview commands without executing them
#   --verify         Verify dump integrity before post-backup cleanup
#   -h, --help       Show this help

set -euo pipefail

# ── Resolve repo root so the lib can be sourced from anywhere ────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_DIR}/lib/common.sh"
# shellcheck source=lib/backup-hooks.sh
source "${REPO_DIR}/lib/backup-hooks.sh"

# ── Help ─────────────────────────────────────────────────────────────────────

backup_hook_exec_help() {
    cat <<'HELP'
backup-hook-exec — run database-aware backup hooks

USAGE:
    ./scripts/backup-hook-exec.sh <action> [OPTIONS]

ACTIONS:
    pre      SERVICE   Dump a service's database before backup (prints dump path)
    post     SERVICE   Clean up the temp dump after backup
    discover           List database services in a compose file
    help               Show this help

OPTIONS:
    --service NAME   Compose service to hook (required unless --all)
    --all            Run the hook for every discovered database service
    --config FILE    Path to compose.yml (default: ./compose.yml)
    --output DIR     Dump output directory (default: /var/tmp/compose-backup-hooks)
    --dry-run        Preview commands without executing them
    --verify         Verify dump integrity before post-backup cleanup
    -h, --help       Show this help

EXAMPLES:
    # Dump one service
    ./scripts/backup-hook-exec.sh pre --service postgres --config compose.yml

    # Clean up after backup
    ./scripts/backup-hook-exec.sh post --service postgres

    # Discover what can be backed up
    ./scripts/backup-hook-exec.sh discover --config suites/ai-automation/compose.yml

    # Batch pre-backup for every database in a suite
    ./scripts/backup-hook-exec.sh pre --all --config compose.yml

    # Preview only
    ./scripts/backup-hook-exec.sh pre --service redis --config compose.yml --dry-run

ENVIRONMENT:
    MB_BACKUP_OUTPUT_DIR   Override default dump directory
    MB_BACKUP_LOG_DIR      Override default log directory
    MB_BACKUP_DRY_RUN      Set to 1 for dry-run
    MB_BACKUP_VERIFY       Set to 1 to verify dumps before cleanup

HELP
}

# ── Parse args ───────────────────────────────────────────────────────────────

action="${1:-help}"
[ "$action" = "-h" ] || [ "$action" = "--help" ] && { backup_hook_exec_help; exit 0; }
shift || true

service=""
all=false
config="${MB_BACKUP_COMPOSE_FILE:-compose.yml}"
output_dir=""
dry_run=false
verify=false

while [ $# -gt 0 ]; do
    case "$1" in
        --service) service="$2"; shift 2 ;;
        --all)     all=true; shift ;;
        --config)  config="$2"; shift 2 ;;
        --output)  output_dir="$2"; shift 2 ;;
        --dry-run) dry_run=true; shift ;;
        --verify)  verify=true; shift ;;
        -h|--help) backup_hook_exec_help; exit 0 ;;
        *) mb_die "Unknown option: $1 (run with --help for usage)" ;;
    esac
done

# Apply overrides into the environment the lib reads.
if [ -n "$output_dir" ]; then
    export MB_BACKUP_OUTPUT_DIR="$output_dir"
fi
if [ "$dry_run" = true ]; then
    export MB_BACKUP_DRY_RUN=1
fi
if [ "$verify" = true ]; then
    export MB_BACKUP_VERIFY=1
fi
export MB_BACKUP_COMPOSE_FILE="$config"

# ── Dispatch ─────────────────────────────────────────────────────────────────

case "$action" in
    pre)
        if [ "$all" = true ]; then
            mb_backup_hook_pre_all "$config"
        else
            [ -z "$service" ] && mb_die "--service NAME is required (or use --all)"
            mb_backup_hook_pre "$service" "$config"
        fi
        ;;
    post)
        if [ "$all" = true ]; then
            mb_backup_hook_post_all "$config"
        else
            [ -z "$service" ] && mb_die "--service NAME is required (or use --all)"
            mb_backup_hook_post "$service" "$config"
        fi
        ;;
    discover)
        mb_backup_hook_discover "$config"
        ;;
    help)
        backup_hook_exec_help
        ;;
    *)
        mb_die "Unknown action: $action (run with --help for usage)"
        ;;
esac
