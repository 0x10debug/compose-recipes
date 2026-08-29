#!/usr/bin/env bash
# lib/backup-hooks.sh — Database-aware backup hooks for mb recipes
# Sourced by mb and scripts/backup-hook-exec.sh. Do not execute directly.
#
# Provides pre-backup and post-backup hooks so database services inside a
# compose suite can be dumped before a backup run and cleaned up afterwards.
# The typical flow is:
#
#   backup-kit (or any Restic wrapper) calls:
#     1. backup_hook_pre  <service>   → dumps DB to a temp file/dir
#     2. <runs restic backup>           → picks up the dump + live volumes
#     3. backup_hook_post <service>   → removes the temp dump
#
# Service type is detected by, in order of precedence:
#   1. Docker label  backup.hook.type=<postgres|mysql|mariadb|redis|mongo|sqlite>
#   2. Image name pattern match (postgres, mysql, mariadb, redis, mongo, sqlite)
#   3. Compose service name pattern match
#
# All hooks honour MB_BACKUP_DRY_RUN=1 (or --dry-run via the exec script): they
# print the command they would run instead of executing it, and emit a
# synthetic dump path so downstream tooling can be wired up in dry-run mode.

# ── Configuration ────────────────────────────────────────────────────────────

# Where temp dumps are written. Kept outside /data so Restic doesn't pick the
# same file up twice under two paths. Override via MB_BACKUP_OUTPUT_DIR.
MB_BACKUP_OUTPUT_DIR="${MB_BACKUP_OUTPUT_DIR:-/var/tmp/compose-backup-hooks}"

# Log directory. Writable by root (mb runs as root for /data access).
MB_BACKUP_LOG_DIR="${MB_BACKUP_LOG_DIR:-/var/log/compose-backup-hooks}"

# Dry-run flag. Set MB_BACKUP_DRY_RUN=1 to preview without touching anything.
MB_BACKUP_DRY_RUN="${MB_BACKUP_DRY_RUN:-0}"

# Default compose file used by discover when --config is omitted.
MB_BACKUP_COMPOSE_FILE="${MB_BACKUP_COMPOSE_FILE:-compose.yml}"

# Docker label conventions (see docs/backup-hooks.md).
#   backup.hook=pre-post        → opt this service into pre+post hooks
#   backup.hook.type=<engine>   → override engine detection
#   backup.hook.db=<name>       → database name (postgres/mysql/mongo)
#   backup.hook.user=<user>     → override DB user
#   backup.hook.path=<path>     → sqlite file path inside the container

# ── Internal helpers ─────────────────────────────────────────────────────────

# _mb_backup_log <message>
#   Append a timestamped line to the hook log. Best-effort: if the log dir
#   isn't writable (e.g. non-root on macOS), the message is silently dropped.
_mb_backup_log() {
    local msg="$*"
    mkdir -p "$MB_BACKUP_LOG_DIR" 2>/dev/null || return 0
    printf '[%s] %s\n' "$(date '+%Y-%m-%dT%H:%M:%S%z')" "$msg" \
        >> "${MB_BACKUP_LOG_DIR}/backup-hooks.log" 2>/dev/null || true
}

# _mb_backup_dry_run
#   Returns 0 (true) when running in dry-run mode.
_mb_backup_dry_run() {
    [ "${MB_BACKUP_DRY_RUN:-0}" = "1" ]
}

# _mb_backup_run <cmd...>
#   Execute a command, or just print it under dry-run.
_mb_backup_run() {
    if _mb_backup_dry_run; then
        mb_detail "[dry-run] $*"
        return 0
    fi
    mb_detail "exec: $*"
    "$@"
}

# _mb_backup_container_for <service> <compose_file>
#   Resolve the running container name for a compose service. compose sets
#   container_name= when present, otherwise the project-prefixed name is used.
_mb_backup_container_for() {
    local service="$1" compose_file="$2"
    local project
    project=$(basename "$(cd "$(dirname "$compose_file")" && pwd)")
    # Prefer an explicit container_name from the compose file.
    local cname
    cname=$(docker compose -f "$compose_file" config --no-interpolate 2>/dev/null \
        | awk -v svc="$service" '
            /^  [a-zA-Z0-9_-]+:[[:space:]]*$/ {
                gsub(/[[:space:]:]/,"",$0); cur=$0
            }
            /container_name:/ && cur==svc {
                sub(/.*container_name:[[:space:]]*/,""); gsub(/["'"'"']/,""); print; exit
            }
        ')
    if [ -n "$cname" ]; then
        echo "$cname"
    else
        echo "${project}-${service}-1"
    fi
}

# _mb_backup_label <container> <label>
#   Print the value of a Docker label, or empty if unset.
_mb_backup_label() {
    local container="$1" label="$2"
    docker inspect --format="{{ index .Config.Labels \"$label\" }}" "$container" 2>/dev/null || true
}

# _mb_backup_compose_label <service> <label> <compose_file>
#   Print the value of a backup.hook.* label declared in the compose file
#   itself (so detection works without a running container). Returns empty if
#   the label is absent or the compose file can't be parsed.
_mb_backup_compose_label() {
    local service="$1" label="$2" compose_file="$3"
    [ -f "$compose_file" ] || return 0
    docker compose -f "$compose_file" config --no-interpolate 2>/dev/null \
        | awk -v svc="$service" -v want="$label" '
            # Top-level service key: 2-space indent, "name:"
            /^  [A-Za-z0-9_.-]+:[[:space:]]*$/ {
                gsub(/^  |:.*$/, "", $0); cur=$0; in_labels=0; next
            }
            # labels: block header
            /^    labels:[[:space:]]*$/ && cur==svc { in_labels=1; next }
            # Any other 4-space-indented key ends the labels block
            /^    [A-Za-z]/ && in_labels { in_labels=0 }
            # Label entry: 6-space indent "key: value"
            in_labels && /^      [A-Za-z0-9_.-]+:/ {
                line=$0
                sub(/^      /, "", line)
                key=line; sub(/:.*$/, "", key)
                val=line; sub(/^[^:]*:[[:space:]]*/, "", val)
                gsub(/^["'"'"']|["'"'"']$/, "", val)
                if (key==want) { print val; exit }
            }
        '
}

# _mb_backup_image <container>
#   Print the container's image name (lowercased) for pattern matching.
_mb_backup_image() {
    local container="$1"
    docker inspect --format='{{.Config.Image}}' "$container" 2>/dev/null | tr '[:upper:]' '[:lower:]'
}

# ── Engine detection ─────────────────────────────────────────────────────────

# mb_backup_detect_type <service> [compose_file]
#   Print the detected database engine for a service: postgres|mysql|mariadb|
#   redis|mongo|sqlite|unknown. Detection order: Docker label > image > name.
mb_backup_detect_type() {
    local service="$1"
    local compose_file="${2:-$MB_BACKUP_COMPOSE_FILE}"
    local container
    container=$(_mb_backup_container_for "$service" "$compose_file")

    # 1. Explicit Docker label wins (running container first, then compose file).
    if [ -n "$container" ]; then
        local labeled
        labeled=$(_mb_backup_label "$container" "backup.hook.type")
        if [ -n "$labeled" ]; then
            echo "$labeled"
            return 0
        fi
    fi
    local compose_labeled
    compose_labeled=$(_mb_backup_compose_label "$service" "backup.hook.type" "$compose_file")
    if [ -n "$compose_labeled" ]; then
        echo "$compose_labeled"
        return 0
    fi

    # 2. Image name pattern.
    local image=""
    if [ -n "$container" ]; then
        image=$(_mb_backup_image "$container")
    fi
    # Fall back to the image declared in compose (works without a running container).
    if [ -z "$image" ] && [ -f "$compose_file" ]; then
        image=$(docker compose -f "$compose_file" config --no-interpolate 2>/dev/null \
            | awk -v svc="$service" '
                /^  [a-zA-Z0-9_-]+:[[:space:]]*$/ {
                    gsub(/[[:space:]:]/,"",$0); cur=$0
                }
                /image:/ && cur==svc {
                    sub(/.*image:[[:space:]]*/,""); gsub(/["'"'"']/,""); print; exit
                }
            ' | tr '[:upper:]' '[:lower:]')
    fi

    case "$image" in
        *postgres*|*pgsql*) echo "postgres"; return 0 ;;
        *mariadb*)          echo "mariadb"; return 0 ;;
        *mysql*)            echo "mysql";   return 0 ;;
        *redis*)            echo "redis";   return 0 ;;
        *mongo*)            echo "mongo";   return 0 ;;
        *sqlite*)           echo "sqlite";  return 0 ;;
    esac

    # 3. Service name pattern (last resort).
    case "$service" in
        *postgres*|*pgsql*|*psql*) echo "postgres"; return 0 ;;
        *mariadb*)                 echo "mariadb"; return 0 ;;
        *mysql*)                   echo "mysql";   return 0 ;;
        *redis*)                   echo "redis";   return 0 ;;
        *mongo*)                   echo "mongo";   return 0 ;;
        *sqlite*)                  echo "sqlite";  return 0 ;;
    esac

    echo "unknown"
    return 1
}

# ── Pre-backup: dump each engine ─────────────────────────────────────────────

# mb_backup_hook_pre <service> [compose_file]
#   Dump the service's database to MB_BACKUP_OUTPUT_DIR and print the dump path
#   on stdout (so the caller can feed it to Restic). Returns 1 on failure or
#   when the engine is unknown.
mb_backup_hook_pre() {
    local service="$1"
    local compose_file="${2:-$MB_BACKUP_COMPOSE_FILE}"

    if [ -z "$service" ]; then
        mb_error "backup_hook_pre: service name required"
        return 1
    fi

    local engine
    engine=$(mb_backup_detect_type "$service" "$compose_file") || engine="unknown"

    mkdir -p "$MB_BACKUP_OUTPUT_DIR" 2>/dev/null || true
    local container
    container=$(_mb_backup_container_for "$service" "$compose_file")

    local stamp
    stamp=$(date '+%Y%m%dT%H%M%SZ')
    local outdir="${MB_BACKUP_OUTPUT_DIR}/${service}-${stamp}"
    _mb_backup_run mkdir -p "$outdir"

    mb_step "pre-backup: $service ($engine)"
    _mb_backup_log "pre-backup START service=$service engine=$engine container=$container"

    case "$engine" in
        postgres) _mb_backup_dump_postgres "$service" "$container" "$outdir" "$compose_file" ;;
        mysql)    _mb_backup_dump_mysql   "$service" "$container" "$outdir" "mysql" "$compose_file" ;;
        mariadb)  _mb_backup_dump_mysql   "$service" "$container" "$outdir" "mariadb" "$compose_file" ;;
        redis)    _mb_backup_dump_redis   "$service" "$container" "$outdir" "$compose_file" ;;
        mongo)    _mb_backup_dump_mongo   "$service" "$container" "$outdir" "$compose_file" ;;
        sqlite)   _mb_backup_dump_sqlite  "$service" "$container" "$outdir" "$compose_file" ;;
        *)
            mb_error "Unknown database engine for service: $service"
            _mb_backup_log "pre-backup FAIL service=$service reason=unknown-engine"
            return 1
            ;;
    esac

    # Record the dump dir so post-backup can clean it up even if the caller
    # loses the returned path. Skip in dry-run (no real dump was produced).
    if ! _mb_backup_dry_run; then
        echo "$outdir" > "${MB_BACKUP_OUTPUT_DIR}/${service}.last"
    fi
    echo "$outdir"
    _mb_backup_log "pre-backup OK service=$service dump=$outdir"
    mb_success "pre-backup dump ready: $outdir"
}

# _mb_backup_dump_postgres <service> <container> <outdir> <compose_file>
_mb_backup_dump_postgres() {
    local service="$1" container="$2" outdir="$3" compose_file="$4"
    local db user
    db=$(_mb_backup_label "$container" "backup.hook.db")
    [ -z "$db" ] && db=$(_mb_backup_compose_label "$service" "backup.hook.db" "$compose_file")
    db="${db:-${POSTGRES_DB:-postgres}}"
    user=$(_mb_backup_label "$container" "backup.hook.user")
    [ -z "$user" ] && user=$(_mb_backup_compose_label "$service" "backup.hook.user" "$compose_file")
    user="${user:-${POSTGRES_USER:-postgres}}"
    local dump="${outdir}/${service}.sql"

    if _mb_backup_dry_run; then
        mb_detail "[dry-run] docker exec $container pg_dump -U $user -d $db > $dump"
        echo "$dump"
        return 0
    fi

    if ! docker exec "$container" pg_dump -U "$user" -d "$db" > "$dump" 2>/dev/null; then
        mb_error "pg_dump failed for $service (container=$container db=$db)"
        return 1
    fi
    mb_detail "pg_dump → $dump ($(wc -c < "$dump" | tr -d ' ') bytes)"
    echo "$dump"
}

# _mb_backup_dump_mysql <service> <container> <outdir> <flavor> <compose_file>
_mb_backup_dump_mysql() {
    local service="$1" container="$2" outdir="$3" flavor="$4" compose_file="$5"
    local db user pw
    db=$(_mb_backup_label "$container" "backup.hook.db")
    [ -z "$db" ] && db=$(_mb_backup_compose_label "$service" "backup.hook.db" "$compose_file")
    db="${db:-${MYSQL_DATABASE:-}}"
    user=$(_mb_backup_label "$container" "backup.hook.user")
    [ -z "$user" ] && user=$(_mb_backup_compose_label "$service" "backup.hook.user" "$compose_file")
    user="${user:-${MYSQL_USER:-root}}"
    pw="${MYSQL_PASSWORD:-${MYSQL_ROOT_PASSWORD:-}}"
    local dump="${outdir}/${service}.sql"
    local extra=()
    [ -n "$pw" ] && extra+=(--password="$pw")

    if _mb_backup_dry_run; then
        mb_detail "[dry-run] docker exec $container mysqldump -u $user ${db:---all-databases} > $dump"
        echo "$dump"
        return 0
    fi

    local target="$db"
    [ -z "$target" ] && target="--all-databases"
    if ! docker exec "$container" mysqldump -u "$user" "${extra[@]}" "$target" > "$dump" 2>/dev/null; then
        mb_error "mysqldump failed for $service (container=$container db=${db:-all})"
        return 1
    fi
    mb_detail "$flavor dump → $dump ($(wc -c < "$dump" | tr -d ' ') bytes)"
    echo "$dump"
}

# _mb_backup_dump_redis <service> <container> <outdir> <compose_file>
_mb_backup_dump_redis() {
    local service="$1" container="$2" outdir="$3" compose_file="$4"
    local dump="${outdir}/${service}.rdb"

    if _mb_backup_dry_run; then
        mb_detail "[dry-run] docker exec $container redis-cli BGSAVE; copy dump.rdb → $dump"
        echo "$dump"
        return 0
    fi

    # Trigger a background save and wait for it to finish.
    docker exec "$container" redis-cli BGSAVE >/dev/null 2>&1 || {
        mb_error "redis BGSAVE failed for $service (container=$container)"
        return 1
    }
    local waited=0
    while [ "$waited" -lt 60 ]; do
        local last_save
        last_save=$(docker exec "$container" redis-cli LASTSAVE 2>/dev/null | tr -dc '0-9')
        sleep 1
        local now_save
        now_save=$(docker exec "$container" redis-cli LASTSAVE 2>/dev/null | tr -dc '0-9')
        if [ -n "$last_save" ] && [ -n "$now_save" ] && [ "$now_save" -gt "$last_save" ]; then
            break
        fi
        waited=$((waited + 1))
    done

    # Copy the RDB out of the container. Default Redis data dir is /data.
    local rdb_path="/data/dump.rdb"
    [ -n "$container" ] && rdb_path=$(_mb_backup_label "$container" "backup.hook.path")
    [ -z "$rdb_path" ] && rdb_path=$(_mb_backup_compose_label "$service" "backup.hook.path" "$compose_file")
    rdb_path="${rdb_path:-/data/dump.rdb}"
    if ! docker cp "${container}:${rdb_path}" "$dump" 2>/dev/null; then
        mb_error "redis docker cp failed for $service (tried ${container}:${rdb_path})"
        return 1
    fi
    mb_detail "redis RDB → $dump ($(wc -c < "$dump" | tr -d ' ') bytes)"
    echo "$dump"
}

# _mb_backup_dump_mongo <service> <container> <outdir> <compose_file>
_mb_backup_dump_mongo() {
    local service="$1" container="$2" outdir="$3" compose_file="$4"
    local db
    db=$(_mb_backup_label "$container" "backup.hook.db")
    [ -z "$db" ] && db=$(_mb_backup_compose_label "$service" "backup.hook.db" "$compose_file")
    db="${db:-${MONGO_DB:-}}"
    local dumpdir="${outdir}/${service}-mongo"
    local extra=()
    [ -n "$db" ] && extra+=(--db "$db")

    if _mb_backup_dry_run; then
        mb_detail "[dry-run] docker exec $container mongodump ${extra[*]} --archive > ${dumpdir}.archive"
        echo "${dumpdir}.archive"
        return 0
    fi

    if ! docker exec "$container" mongodump "${extra[@]}" --archive > "${dumpdir}.archive" 2>/dev/null; then
        mb_error "mongodump failed for $service (container=$container db=${db:-all})"
        return 1
    fi
    mb_detail "mongodump → ${dumpdir}.archive ($(wc -c < "${dumpdir}.archive" | tr -d ' ') bytes)"
    echo "${dumpdir}.archive"
}

# _mb_backup_dump_sqlite <service> <container> <outdir> <compose_file>
_mb_backup_dump_sqlite() {
    local service="$1" container="$2" outdir="$3" compose_file="$4"
    local db_path
    db_path=$(_mb_backup_label "$container" "backup.hook.path")
    [ -z "$db_path" ] && db_path=$(_mb_backup_compose_label "$service" "backup.hook.path" "$compose_file")
    db_path="${db_path:-${SQLITE_PATH:-/data/${service}/${service}.db}}"
    local dump="${outdir}/${service}.db"

    if _mb_backup_dry_run; then
        mb_detail "[dry-run] docker cp ${container}:${db_path} → $dump"
        echo "$dump"
        return 0
    fi

    if ! docker cp "${container}:${db_path}" "$dump" 2>/dev/null; then
        mb_error "sqlite docker cp failed for $service (tried ${container}:${db_path})"
        return 1
    fi
    mb_detail "sqlite copy → $dump ($(wc -c < "$dump" | tr -d ' ') bytes)"
    echo "$dump"
}

# ── Post-backup: cleanup + optional verification ─────────────────────────────

# mb_backup_hook_post <service> [compose_file]
#   Remove the temp dump produced by the matching pre-backup call. When
#   MB_BACKUP_VERIFY=1, also sanity-check the dump before deleting it.
mb_backup_hook_post() {
    local service="$1"
    local compose_file="${2:-$MB_BACKUP_COMPOSE_FILE}"

    if [ -z "$service" ]; then
        mb_error "backup_hook_post: service name required"
        return 1
    fi

    local last_file="${MB_BACKUP_OUTPUT_DIR}/${service}.last"
    local dumpdir=""
    [ -f "$last_file" ] && dumpdir=$(cat "$last_file")

    mb_step "post-backup: $service"
    _mb_backup_log "post-backup START service=$service dump=$dumpdir"

    if [ -z "$dumpdir" ] || [ ! -e "$dumpdir" ]; then
        mb_warn "No dump found for $service (expected $dumpdir). Nothing to clean."
        _mb_backup_log "post-backup SKIP service=$service reason=no-dump"
        return 0
    fi

    # Optional integrity check before deletion.
    if [ "${MB_BACKUP_VERIFY:-0}" = "1" ] && ! _mb_backup_dry_run; then
        if ! _mb_backup_verify "$service" "$dumpdir" "$compose_file"; then
            mb_error "Verification failed for $service — keeping dump at $dumpdir"
            _mb_backup_log "post-backup VERIFY-FAIL service=$service dump=$dumpdir"
            return 1
        fi
        mb_detail "verified: $dumpdir"
    fi

    _mb_backup_run rm -rf "$dumpdir"
    _mb_backup_run rm -f "$last_file"
    _mb_backup_log "post-backup OK service=$service cleaned=$dumpdir"
    mb_success "post-backup cleanup done: $dumpdir"
}

# _mb_backup_verify <service> <dumpdir> <compose_file>
#   Lightweight integrity check. For SQL dumps, confirm the file is non-empty
#   and contains expected markers. For archives/RDB, just confirm non-empty.
_mb_backup_verify() {
    local service="$1" dumpdir="$2" compose_file="$3"
    local engine
    engine=$(mb_backup_detect_type "$service" "$compose_file") || engine="unknown"

    if [ ! -s "$dumpdir" ]; then
        mb_error "dump is empty: $dumpdir"
        return 1
    fi

    case "$engine" in
        postgres|mysql|mariadb)
            # SQL dumps should contain at least one CREATE or INSERT statement.
            if ! grep -Eqi 'CREATE|INSERT|COPY' "$dumpdir" 2>/dev/null; then
                mb_error "SQL dump missing expected statements: $dumpdir"
                return 1
            fi
            ;;
        redis|mongo|sqlite)
            # Binary formats — just confirm the file has content.
            ;;
        *)
            ;;
    esac
    return 0
}

# ── Discovery ────────────────────────────────────────────────────────────────

# mb_backup_hook_discover [compose_file]
#   Scan a compose.yml for database services and print a table:
#     SERVICE | ENGINE | IMAGE | CONTAINER | DB | HOOK-LABEL
#   Services are identified by image/name patterns OR an explicit
#   backup.hook=pre-post label on the running container.
mb_backup_hook_discover() {
    local compose_file="${1:-$MB_BACKUP_COMPOSE_FILE}"

    if [ ! -f "$compose_file" ]; then
        mb_error "compose file not found: $compose_file"
        return 1
    fi

    mb_step "Discovering backup-eligible services in: $compose_file"
    echo ""
    printf '%-18s %-10s %-28s %-22s %-14s %s\n' \
        "SERVICE" "ENGINE" "IMAGE" "CONTAINER" "DB" "HOOK-LABEL"
    printf '%-18s %-10s %-28s %-22s %-14s %s\n' \
        "-------" "------" "-----" "---------" "--" "----------"

    local found=0
    # List services from the compose file (handles profiles gracefully).
    local services
    services=$(docker compose -f "$compose_file" config --services 2>/dev/null) || {
        mb_warn "could not parse compose file: $compose_file"
        return 1
    }

    for svc in $services; do
        local engine container image db hook_label
        engine=$(mb_backup_detect_type "$svc" "$compose_file") || engine="unknown"
        [ "$engine" = "unknown" ] && continue
        container=$(_mb_backup_container_for "$svc" "$compose_file")
        image=$(docker compose -f "$compose_file" config --no-interpolate 2>/dev/null \
            | awk -v s="$svc" '
                /^  [a-zA-Z0-9_-]+:[[:space:]]*$/ {gsub(/[[:space:]:]/,"",$0); cur=$0}
                /image:/ && cur==s {sub(/.*image:[[:space:]]*/,""); gsub(/["'"'"']/,""); print; exit}
            ')
        # Prefer running-container labels, fall back to compose-file labels.
        db=$(_mb_backup_label "$container" "backup.hook.db")
        [ -z "$db" ] && db=$(_mb_backup_compose_label "$svc" "backup.hook.db" "$compose_file")
        hook_label=$(_mb_backup_label "$container" "backup.hook")
        [ -z "$hook_label" ] && hook_label=$(_mb_backup_compose_label "$svc" "backup.hook" "$compose_file")
        printf '%-18s %-10s %-28s %-22s %-14s %s\n' \
            "$svc" "$engine" "${image:-(none)}" "${container:-(stopped)}" \
            "${db:-(default)}" "${hook_label:-(none)}"
        found=$((found + 1))
    done

    echo ""
    if [ "$found" -eq 0 ]; then
        mb_warn "No database services detected in $compose_file"
    else
        mb_info "$found database service(s) found"
        mb_detail "Tag services with labels: backup.hook=pre-post, backup.hook.type=<engine>"
    fi
    return 0
}

# ── Batch helpers ────────────────────────────────────────────────────────────

# mb_backup_hook_pre_all [compose_file]
#   Run pre-backup for every discovered database service. Prints each dump path
#   on its own line; the caller can collect them for Restic.
mb_backup_hook_pre_all() {
    local compose_file="${1:-$MB_BACKUP_COMPOSE_FILE}"
    local services
    services=$(docker compose -f "$compose_file" config --services 2>/dev/null) || return 1
    local rc=0
    for svc in $services; do
        local engine
        engine=$(mb_backup_detect_type "$svc" "$compose_file") || engine="unknown"
        [ "$engine" = "unknown" ] && continue
        mb_backup_hook_pre "$svc" "$compose_file" || rc=1
    done
    return $rc
}

# mb_backup_hook_post_all [compose_file]
#   Run post-backup cleanup for every discovered database service.
mb_backup_hook_post_all() {
    local compose_file="${1:-$MB_BACKUP_COMPOSE_FILE}"
    local services
    services=$(docker compose -f "$compose_file" config --services 2>/dev/null) || return 1
    local rc=0
    for svc in $services; do
        local engine
        engine=$(mb_backup_detect_type "$svc" "$compose_file") || engine="unknown"
        [ "$engine" = "unknown" ] && continue
        mb_backup_hook_post "$svc" "$compose_file" || rc=1
    done
    return $rc
}
