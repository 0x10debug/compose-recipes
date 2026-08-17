#!/usr/bin/env bash
# lib/env.sh — .env file generation and validation for suites

# Generate .env from .env.example, filling in defaults and asking for values
mb_env_generate() {
    local suite="$1"
    local suite_dir="${MB_SUITES_DIR}/${suite}"
    local env_example="${suite_dir}/.env.example"
    local env_target="${MB_DEPLOY_DIR}/${suite}/.env"

    if [ ! -f "$env_example" ]; then
        mb_warn "No .env.example found for suite: $suite"
        return 1
    fi

    mkdir -p "${MB_DEPLOY_DIR}/${suite}"

    # Parse .env.example line by line
    while IFS= read -r line || [ -n "$line" ]; do
        # Skip comments and empty lines
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        # Parse KEY=VALUE or KEY=
        local key value
        key="${line%%=*}"
        value="${line#*=}"

        # If value is empty, ask for it or generate
        if [ -z "$value" ]; then
            case "$key" in
                *_PASSWORD|*_SECRET|*_KEY|*_TOKEN)
                    # Auto-generate secrets
                    local generated
                    generated=$(mb_gen_password 32)
                    echo "${key}=${generated}"
                    mb_detail "Generated secret: ${key}"
                    ;;
                *_DOMAIN|*DOMAIN*)
                    # Ask for domain
                    local domain
                    domain=$(mb_ask_value "Enter value for ${key}" "example.com")
                    echo "${key}=${domain}"
                    ;;
                *)
                    # Ask for other values
                    local input
                    input=$(mb_ask_value "Enter value for ${key}" "")
                    if [ -n "$input" ]; then
                        echo "${key}=${input}"
                    else
                        echo "${key}="
                    fi
                    ;;
            esac
        else
            # Use the default value from .env.example
            echo "$line"
        fi
    done < "$env_example" > "$env_target"

    mb_detail ".env written to: $env_target"
    chmod 600 "$env_target"
}

# Validate .env — check required variables are set
mb_env_validate() {
    local suite="$1"
    local env_file="${MB_DEPLOY_DIR}/${suite}/.env"

    if [ ! -f "$env_file" ]; then
        mb_error ".env file not found: $env_file"
        mb_die "Run 'mb recipes deploy ${suite}' first to generate .env"
    fi

    local errors=0
    while IFS= read -r line || [ -n "$line" ]; do
        [[ "$line" =~ ^[[:space:]]*# ]] && continue
        [[ -z "${line// }" ]] && continue

        local key value
        key="${line%%=*}"
        value="${line#*=}"

        if [ -z "$value" ]; then
            mb_warn "Required variable is empty: $key"
            errors=$((errors + 1))
        fi
    done < "$env_file"

    if [ "$errors" -gt 0 ]; then
        mb_die "$errors required variable(s) are empty. Edit $env_file and fill them in."
    fi

    return 0
}

# Load .env into environment
mb_env_load() {
    local suite="$1"
    local env_file="${MB_DEPLOY_DIR}/${suite}/.env"

    if [ ! -f "$env_file" ]; then
        mb_die ".env file not found: $env_file"
    fi

    set -a
    # shellcheck source=/dev/null
    source "$env_file"
    set +a
}
