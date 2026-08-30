#!/usr/bin/env bash
# scripts/build-registry.sh — Template registry generator for compose-recipes
#
# Scans every suites/*/compose.yml and builds a machine-readable registry:
# suite name, description, compose path, services, published ports, env vars,
# depends_on, profiles. Used for automated deployment and doc generation.
#
# Usage:
#   ./scripts/build-registry.sh                          # table to stdout
#   ./scripts/build-registry.sh --format json            # JSON to stdout
#   ./scripts/build-registry.sh --format yaml            # YAML to stdout
#   ./scripts/build-registry.sh --format json --output registry.json
#   ./scripts/build-registry.sh --suite home-media       # single suite only
#   ./scripts/build-registry.sh -h, --help
#
# Options:
#   --format FORMAT   Output format: json | yaml | table (default: table)
#   --output FILE     Write to file instead of stdout
#   --suite NAME      Only emit the named suite
#   --dry-run         Show what would be scanned without emitting output
#   -h, --help        Show this help

set -euo pipefail

# ── Resolve repo root so the lib can be sourced from anywhere ────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# shellcheck source=lib/common.sh
source "${REPO_DIR}/lib/common.sh"

# ── Help ─────────────────────────────────────────────────────────────────────

build_registry_help() {
    cat <<'HELP'
build-registry — generate the compose-recipes template registry

USAGE:
    ./scripts/build-registry.sh [OPTIONS]

OPTIONS:
    --format FORMAT   Output format: json | yaml | table (default: table)
    --output FILE     Write to file instead of stdout
    --suite NAME      Only emit the named suite
    --dry-run         Show what would be scanned without emitting output
    -h, --help        Show this help

EXAMPLES:
    ./scripts/build-registry.sh                              # table to stdout
    ./scripts/build-registry.sh --format json                # JSON to stdout
    ./scripts/build-registry.sh --format yaml --output registry.yaml
    ./scripts/build-registry.sh --suite home-media --format json

HELP
}

# ── Parse args ───────────────────────────────────────────────────────────────

format="table"
output_file=""
suite_filter=""
dry_run=false

while [ $# -gt 0 ]; do
    case "$1" in
        --format)  format="$2"; shift 2 ;;
        --output)  output_file="$2"; shift 2 ;;
        --suite)   suite_filter="$2"; shift 2 ;;
        --dry-run) dry_run=true; shift ;;
        -h|--help) build_registry_help; exit 0 ;;
        *) mb_die "Unknown option: $1 (run with --help for usage)" ;;
    esac
done

case "$format" in
    json|yaml|table) ;;
    *) mb_die "Invalid --format: $format (use json | yaml | table)" ;;
esac

# ── JSON helpers (no jq dependency) ──────────────────────────────────────────

# Escape a string for JSON output.
json_escape() {
    # Replace backslash, quote, and control chars; print without trailing newline.
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//$'\t'/\\t}"
    s="${s//$/\\n}"
    printf '%s' "$s"
}

# ── Suite discovery ──────────────────────────────────────────────────────────

# Emit one line per suite: <suite>|<compose_path>|<readme_path>
discover_suites() {
    local dir name
    for dir in "$MB_SUITES_DIR"/*/; do
        [ -d "$dir" ] || continue
        name=$(basename "$dir")
        [ -f "${dir}compose.yml" ] || continue
        if [ -n "$suite_filter" ] && [ "$name" != "$suite_filter" ]; then
            continue
        fi
        local readme=""
        [ -f "${dir}README.md" ] && readme="${dir}README.md"
        printf '%s|%s|%s\n' "$name" "${dir}compose.yml" "$readme"
    done
}

# Extract the first heading line from a README as the description.
suite_description() {
    local readme="$1"
    if [ -z "$readme" ] || [ ! -f "$readme" ]; then
        printf '(no description)'
        return
    fi
    head -1 "$readme" | sed 's/^# *//'
}

# ── Compose parser (awk state machine) ───────────────────────────────────────
# Parses a compose.yml and emits TSV records:
#   SERVICE <name> <image> <profiles>
#   PORT    <service> <host_port> <container_port> <protocol> <bind> <env_var>
#   ENV     <service> <var_name>
#   DEP     <service> <depends_on_service>
#   LABEL   <service> <key> <value>
# We track the current top-level key and the current service name by indentation.

parse_compose() {
    local compose_file="$1"
    # BSD awk (macOS default) does not support the 3-argument match() with
    # capture arrays, so we extract substrings with sub()/split() instead.
    awk '
    BEGIN {
        in_services = 0
        cur_service = ""
        cur_section = ""
    }
    { sub(/\r$/, "") }
    /^[[:space:]]*$/ { next }
    /^[[:space:]]*#/ { next }

    # Top-level key (no leading whitespace)
    /^[^[:space:]]/ {
        key = $0
        sub(/:.*/, "", key)
        cur_section = ""
        in_services = (key == "services") ? 1 : 0
        next
    }

    !in_services { next }

    # Service definition: exactly 2-space indent, not a list item, ends with ":"
    /^  [^[:space:]-]/ {
        line = $0
        if (line ~ /:[[:space:]]*$/ || line ~ /:[[:space:]]*#/) {
            sub(/^  /, "", line)
            sub(/:.*/, "", line)
            gsub(/[[:space:]]/, "", line)
            if (line != "") {
                cur_service = line
                cur_section = ""
            }
        }
        next
    }

    # Section header under a service: 4-space indent, key: (block style)
    /^    [^[:space:]-]/ {
        line = $0
        if (line ~ /:[[:space:]]*$/ || line ~ /:[[:space:]]*#/) {
            sub(/^    /, "", line)
            sub(/:.*/, "", line)
            gsub(/[[:space:]]/, "", line)
            cur_section = line
        } else if (line ~ /:[[:space:]]*\[/) {
            # inline array like "networks: [a, b]" — not a block section
            cur_section = ""
        }
        next
    }

    # List items under a section (6-space indent + "- ")
    /^      - / {
        item = $0
        sub(/^      - /, "", item)
        gsub(/^"|"$/, "", item)

        if (cur_section == "ports") {
            parse_port(item)
        } else if (cur_section == "environment") {
            parse_env(item)
        } else if (cur_section == "depends_on") {
            print "DEP\t" cur_service "\t" item
        } else if (cur_section == "labels") {
            parse_label(item)
        }
        next
    }

    # Map-style entries under environment/labels (6-space indent, "KEY: value")
    # Some suites use "environment:" with map syntax instead of list syntax.
    /^      [A-Za-z0-9_].*:/ {
        if (cur_section == "environment") {
            item = $0
            sub(/^      /, "", item)
            parse_env(item)
            next
        } else if (cur_section == "labels") {
            item = $0
            sub(/^      /, "", item)
            parse_label(item)
            next
        }
    }

    function parse_port(item,    host, cont, proto, bind, envvar, rest, tmp, closeidx) {
        proto = "tcp"
        if (item ~ /\/udp$/) { proto = "udp"; sub(/\/udp$/, "", item) }
        else if (item ~ /\/tcp$/) { proto = "tcp"; sub(/\/tcp$/, "", item) }

        host = ""; cont = ""; bind = "0.0.0.0"; envvar = ""

        # If the host part is a ${VAR:-default} expression, extract it first
        # because it contains colons that would confuse split().
        if (item ~ /^\$\{/) {
            # Find closing brace
            closeidx = index(item, "}")
            if (closeidx > 0) {
                host = substr(item, 1, closeidx)
                rest = substr(item, closeidx + 1)
                # rest is now ":container" or ":ip:host:container" or empty
                sub(/^:/, "", rest)
                # Extract env var name and default from ${VAR:-default}
                tmp = host
                sub(/^\$\{/, "", tmp)
                sub(/[:}].*/, "", tmp)
                envvar = tmp
                tmp = host
                sub(/.*:-/, "", tmp)
                sub(/[}].*/, "", tmp)
                host = tmp
                # rest may be "container" or "ip:host:container"
                if (rest ~ /:/) {
                    split(rest, parts, ":")
                    bind = parts[1]
                    cont = parts[2]
                } else {
                    cont = rest
                }
            }
        } else {
            # No ${...} in host part — safe to split by colon
            n = split(item, parts, ":")
            if (n == 1) { host = parts[1]; cont = parts[1] }
            else if (n == 2) { host = parts[1]; cont = parts[2] }
            else if (n == 3) { bind = parts[1]; host = parts[2]; cont = parts[3] }
        }

        # Container port may also be ${VAR} — take the default
        if (cont ~ /\$\{/) {
            tmp = cont
            sub(/.*:-/, "", tmp)
            sub(/[}].*/, "", tmp)
            cont = tmp
        }
        print "PORT\t" cur_service "\t" host "\t" cont "\t" proto "\t" bind "\t" envvar
    }

    function parse_env(item,    key) {
        if (item ~ /=/) {
            key = item
            sub(/=.*$/, "", key)
            if (key != "") {
                print "ENV\t" cur_service "\t" key
            }
        } else {
            print "ENV\t" cur_service "\t" item
        }
    }

    function parse_label(item,    key, val) {
        if (item ~ /:/) {
            key = item
            sub(/:.*$/, "", key)
            val = item
            sub(/^[^:]*:/, "", val)
        } else if (item ~ /=/) {
            key = item
            sub(/=.*$/, "", key)
            val = item
            sub(/^[^=]*=/, "", val)
        } else {
            key = item; val = ""
        }
        gsub(/^"|"$/, "", key)
        gsub(/^"|"$/, "", val)
        print "LABEL\t" cur_service "\t" key "\t" val
    }
    ' "$compose_file"
}

# ── Build registry into a temp file of TSV records ───────────────────────────

REGISTRY_TMP="$(mktemp -t mb-registry-XXXXXX)"
trap 'rm -f "$REGISTRY_TMP"' EXIT

build_registry_tsv() {
    local suite_line suite_name compose_path readme desc
    while IFS= read -r suite_line; do
        suite_name="${suite_line%%|*}"
        local rest="${suite_line#*|}"
        compose_path="${rest%%|*}"
        readme="${rest#*|}"

        desc=$(suite_description "$readme")

        # Emit SUITE record into the same temp file
        printf 'SUITE\t%s\t%s\t%s\t%s\n' "$suite_name" "$desc" "$compose_path" "$readme" >> "$REGISTRY_TMP"

        # Parse compose and append
        parse_compose "$compose_path" >> "$REGISTRY_TMP"
    done < <(discover_suites)
}

# ── Output formatters ────────────────────────────────────────────────────────

emit_table() {
    mb_step "Template registry"
    echo ""

    local current_suite=""
    local suite_desc=""
    while IFS=$'\t' read -r type rest; do
        case "$type" in
            SUITE)
                current_suite=$(printf '%s' "$rest" | cut -f1)
                suite_desc=$(printf '%s' "$rest" | cut -f2)
                echo ""
                printf "${MB_BOLD}%s${MB_RESET} — %s\n" "$current_suite" "$suite_desc"
                printf "  %-20s %-20s %-10s %-10s %-12s %s\n" "SERVICE" "HOST_PORT" "PROTO" "BIND" "ENV_VAR" "CONTAINER_PORT"
                ;;
            PORT)
                local svc host cont proto bind envvar
                svc=$(printf '%s' "$rest" | cut -f1)
                host=$(printf '%s' "$rest" | cut -f2)
                cont=$(printf '%s' "$rest" | cut -f3)
                proto=$(printf '%s' "$rest" | cut -f4)
                bind=$(printf '%s' "$rest" | cut -f5)
                envvar=$(printf '%s' "$rest" | cut -f6)
                [ -z "$host" ] && host="(none)"
                [ -z "$envvar" ] && envvar="—"
                printf "  %-20s %-20s %-10s %-10s %-12s %s\n" "$svc" "$host" "$proto" "$bind" "$envvar" "$cont"
                ;;
        esac
    done < "$REGISTRY_TMP"
    echo ""
    local count
    count=$(grep -c '^SUITE' "$REGISTRY_TMP" || true)
    mb_info "$count suite(s) in registry"
}

emit_json() {
    local suites_json=""
    local first_suite=true
    local current_suite=""
    local services_json=""
    local first_service=true

    # We iterate and group by suite. Records are ordered: SUITE first, then its
    # SERVICE/PORT/ENV/DEP/LABEL records, then next SUITE.
    local suite_name suite_desc compose_path readme
    local svc_name=""
    local ports_json="" env_json="" dep_json=""

    flush_service() {
        if [ -n "$svc_name" ]; then
            local entry
            entry=$(printf '      {"name":"%s","ports":[%s],"env":[%s],"depends_on":[%s]}' \
                "$(json_escape "$svc_name")" "$ports_json" "$env_json" "$dep_json")
            if [ "$first_service" = true ]; then
                services_json="$entry"
                first_service=false
            else
                services_json="${services_json},${entry}"
            fi
        fi
    }

    flush_suite() {
        flush_service
        svc_name=""
        if [ -n "$current_suite" ]; then
            local entry
            entry=$(printf '  {"name":"%s","description":"%s","compose":"%s","services":[%s]}' \
                "$(json_escape "$current_suite")" "$(json_escape "$suite_desc")" \
                "$(json_escape "$compose_path")" "$services_json")
            if [ "$first_suite" = true ]; then
                suites_json="$entry"
                first_suite=false
            else
                suites_json="${suites_json},${entry}"
            fi
        fi
        services_json=""
        first_service=true
    }

    while IFS=$'\t' read -r type rest; do
        case "$type" in
            SUITE)
                flush_suite
                current_suite=$(printf '%s' "$rest" | cut -f1)
                suite_desc=$(printf '%s' "$rest" | cut -f2)
                compose_path=$(printf '%s' "$rest" | cut -f3)
                ;;
            PORT)
                # If service changed, flush previous
                local p_svc
                p_svc=$(printf '%s' "$rest" | cut -f1)
                if [ -n "$svc_name" ] && [ "$p_svc" != "$svc_name" ]; then
                    flush_service
                    ports_json=""
                    env_json=""
                    dep_json=""
                fi
                svc_name="$p_svc"
                local host cont proto bind envvar
                host=$(printf '%s' "$rest" | cut -f2)
                cont=$(printf '%s' "$rest" | cut -f3)
                proto=$(printf '%s' "$rest" | cut -f4)
                bind=$(printf '%s' "$rest" | cut -f5)
                envvar=$(printf '%s' "$rest" | cut -f6)
                local port_entry
                port_entry=$(printf '{"host":"%s","container":"%s","protocol":"%s","bind":"%s","env_var":"%s"}' \
                    "$(json_escape "$host")" "$(json_escape "$cont")" "$(json_escape "$proto")" \
                    "$(json_escape "$bind")" "$(json_escape "$envvar")")
                if [ -z "$ports_json" ]; then
                    ports_json="$port_entry"
                else
                    ports_json="${ports_json},${port_entry}"
                fi
                ;;
            ENV)
                local e_svc e_var
                e_svc=$(printf '%s' "$rest" | cut -f1)
                e_var=$(printf '%s' "$rest" | cut -f2)
                if [ -n "$svc_name" ] && [ "$e_svc" != "$svc_name" ]; then
                    flush_service
                    ports_json=""
                    env_json=""
                    dep_json=""
                fi
                svc_name="$e_svc"
                local env_entry
                env_entry=$(printf '"%s"' "$(json_escape "$e_var")")
                if [ -z "$env_json" ]; then
                    env_json="$env_entry"
                else
                    env_json="${env_json},${env_entry}"
                fi
                ;;
            DEP)
                local d_svc d_dep
                d_svc=$(printf '%s' "$rest" | cut -f1)
                d_dep=$(printf '%s' "$rest" | cut -f2)
                if [ -n "$svc_name" ] && [ "$d_svc" != "$svc_name" ]; then
                    flush_service
                    ports_json=""
                    env_json=""
                    dep_json=""
                fi
                svc_name="$d_svc"
                if [ -z "$dep_json" ]; then
                    dep_json=$(printf '"%s"' "$(json_escape "$d_dep")")
                else
                    dep_json="${dep_json},$(printf '"%s"' "$(json_escape "$d_dep")")"
                fi
                ;;
        esac
    done < "$REGISTRY_TMP"
    flush_suite

    printf '{"version":"%s","suites":[%s]}\n' "$MB_RECIPES_VERSION" "$suites_json"
}

emit_yaml() {
    printf 'version: "%s"\nsuites:\n' "$MB_RECIPES_VERSION"
    local current_suite=""
    local current_service=""
    local first_suite=true

    while IFS=$'\t' read -r type rest; do
        case "$type" in
            SUITE)
                local name desc compose
                name=$(printf '%s' "$rest" | cut -f1)
                desc=$(printf '%s' "$rest" | cut -f2)
                compose=$(printf '%s' "$rest" | cut -f3)
                printf -- '  - name: "%s"\n' "$name"
                printf '    description: "%s"\n' "$desc"
                printf '    compose: "%s"\n' "$compose"
                printf '    services:\n'
                current_suite="$name"
                current_service=""
                ;;
            PORT)
                local svc host cont proto bind envvar
                svc=$(printf '%s' "$rest" | cut -f1)
                host=$(printf '%s' "$rest" | cut -f2)
                cont=$(printf '%s' "$rest" | cut -f3)
                proto=$(printf '%s' "$rest" | cut -f4)
                bind=$(printf '%s' "$rest" | cut -f5)
                envvar=$(printf '%s' "$rest" | cut -f6)
                if [ "$svc" != "$current_service" ]; then
                    printf '      - name: "%s"\n' "$svc"
                    printf '        ports:\n'
                    current_service="$svc"
                fi
                printf '          - host: "%s"\n' "$host"
                printf '            container: "%s"\n' "$cont"
                printf '            protocol: "%s"\n' "$proto"
                printf '            bind: "%s"\n' "$bind"
                [ -n "$envvar" ] && printf '            env_var: "%s"\n' "$envvar"
                ;;
        esac
    done < "$REGISTRY_TMP"
}

# ── Main ─────────────────────────────────────────────────────────────────────

mb_step "Building template registry"
build_registry_tsv > "$REGISTRY_TMP"

local_count=$(grep -c '^SUITE' "$REGISTRY_TMP" || true)
if [ "$local_count" -eq 0 ]; then
    mb_warn "No suites found in: $MB_SUITES_DIR"
    exit 0
fi

if [ "$dry_run" = true ]; then
    mb_info "[dry-run] Found $local_count suite(s):"
    grep '^SUITE' "$REGISTRY_TMP" | while IFS=$'\t' read -r _ name _; do
        mb_detail "$name"
    done
    exit 0
fi

emit_output() {
    case "$format" in
        table) emit_table ;;
        json)  emit_json ;;
        yaml)  emit_yaml ;;
    esac
}

if [ -n "$output_file" ]; then
    emit_output > "$output_file"
    mb_success "Registry written to: $output_file ($local_count suite(s), format: $format)"
else
    emit_output
fi
