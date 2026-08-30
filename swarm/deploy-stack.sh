#!/usr/bin/env bash
# swarm/deploy-stack.sh — Docker Swarm stack deployment wrapper
#
# Wraps `docker stack deploy` with validation, env-file support, and dry-run.
#
# Usage:
#   ./swarm/deploy-stack.sh --stack-name mystack --config-file swarm/stack-example.yml
#   ./swarm/deploy-stack.sh --stack-name mystack --config-file swarm/stack-example.yml --dry-run
#   ./swarm/deploy-stack.sh --stack-name mystack --config-file swarm/stack-example.yml --env-file .env
#   ./swarm/deploy-stack.sh -h, --help
#
# Options:
#   --stack-name NAME   Swarm stack name (required)
#   --config-file FILE  Path to the stack YAML file (required)
#   --env-file FILE     Env file to load before deploying (optional)
#   --dry-run           Show what would be deployed without executing
#   --prune             Remove services that are no longer referenced
#   -h, --help          Show this help

set -euo pipefail

# ── Resolve repo root so the lib can be sourced from anywhere ────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_DIR}/lib/common.sh"

# ── Help ─────────────────────────────────────────────────────────────────────

deploy_stack_help() {
    cat <<'HELP'
deploy-stack — deploy a Docker Swarm stack

USAGE:
    ./swarm/deploy-stack.sh --stack-name NAME --config-file FILE [OPTIONS]

OPTIONS:
    --stack-name NAME   Swarm stack name (required)
    --config-file FILE  Path to the stack YAML file (required)
    --env-file FILE     Env file to load before deploying (optional)
    --dry-run           Show what would be deployed without executing
    --prune             Remove services no longer referenced in the file
    -h, --help          Show this help

EXAMPLES:
    # Dry-run — preview
    ./swarm/deploy-stack.sh --stack-name mystack --config-file swarm/stack-example.yml --dry-run

    # Deploy with env file
    ./swarm/deploy-stack.sh --stack-name mystack --config-file swarm/stack-example.yml --env-file .env

    # Deploy and prune orphaned services
    ./swarm/deploy-stack.sh --stack-name mystack --config-file swarm/stack-example.yml --prune

HELP
}

# ── Parse args ───────────────────────────────────────────────────────────────

stack_name=""
config_file=""
env_file=""
dry_run=false
prune=false

while [ $# -gt 0 ]; do
    case "$1" in
        --stack-name)  stack_name="$2"; shift 2 ;;
        --config-file) config_file="$2"; shift 2 ;;
        --env-file)    env_file="$2"; shift 2 ;;
        --dry-run)     dry_run=true; shift ;;
        --prune)       prune=true; shift ;;
        -h|--help)     deploy_stack_help; exit 0 ;;
        *) mb_die "Unknown option: $1 (run with --help for usage)" ;;
    esac
done

[ -z "$stack_name" ] && mb_die "--stack-name is required (run with --help for usage)"
[ -z "$config_file" ] && mb_die "--config-file is required (run with --help for usage)"

if [ ! -f "$config_file" ]; then
    mb_die "Config file not found: $config_file"
fi

# ── Checks ───────────────────────────────────────────────────────────────────

mb_check_docker

# Verify Swarm is active
if ! docker info --format '{{.Swarm.LocalNodeState}}' 2>/dev/null | grep -q "active"; then
    mb_die "Docker Swarm is not active on this node. Initialize with: docker swarm init"
fi

# ── Load env file ────────────────────────────────────────────────────────────

if [ -n "$env_file" ]; then
    if [ ! -f "$env_file" ]; then
        mb_die "Env file not found: $env_file"
    fi
    mb_info "Loading env file: $env_file"
    set -a
    # shellcheck disable=SC1090
    source "$env_file"
    set +a
fi

# ── Resolve config file to absolute path ─────────────────────────────────────

config_abs="$(cd "$(dirname "$config_file")" && pwd)/$(basename "$config_file")"

# ── Show what will be deployed ───────────────────────────────────────────────

mb_step "Deploying Swarm stack: $stack_name"
mb_detail "Config file: $config_abs"

# List services defined in the stack file
mb_info "Services in stack file:"
if mb_check_command docker; then
    # docker stack deploy can validate the file; use docker compose config for
    # a quick service list (stack files are a superset of compose files)
    docker compose -f "$config_abs" config --services 2>/dev/null | sed 's/^/    /' || \
        mb_warn "Could not parse config file (may use Swarm-only features)"
fi

# Show current stack state if it exists
if docker stack ls --format '{{.Name}}' 2>/dev/null | grep -q "^${stack_name}$"; then
    mb_info "Existing stack found — this will be an update:"
    docker stack services "$stack_name" --format '    {{.Name}}\t{{.Replicas}}\t{{.Image}}' 2>/dev/null || true
else
    mb_info "No existing stack '$stack_name' — this will be a new deployment"
fi

# ── Dry-run ──────────────────────────────────────────────────────────────────

if [ "$dry_run" = true ]; then
    mb_info "[dry-run] Would run: docker stack deploy -c $config_abs $stack_name"
    [ "$prune" = true ] && mb_info "[dry-run] Would also pass --prune"
    exit 0
fi

# ── Deploy ───────────────────────────────────────────────────────────────────

mb_info "Deploying..."
deploy_args=(docker stack deploy -c "$config_abs")
[ "$prune" = true ] && deploy_args+=(--prune)
deploy_args+=(--with-registry-auth)
deploy_args+=("$stack_name")

"${deploy_args[@]}" 2>&1 | sed 's/^/    /'

# ── Verify ───────────────────────────────────────────────────────────────────

echo ""
mb_info "Stack services:"
docker stack services "$stack_name" --format 'table {{.Name}}\t{{.Replicas}}\t{{.Image}}\t{{.Ports}}' 2>/dev/null | sed 's/^/    /' || true

mb_success "Stack '$stack_name' deployed"
echo ""
mb_info "Check task status:"
mb_detail "docker stack ps $stack_name"
mb_detail "docker stack services $stack_name"
