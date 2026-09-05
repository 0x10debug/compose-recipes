#!/usr/bin/env bash
# scripts/validate-compose.sh — Validate every suite and template compose file.
#
# Suite files are validated directly. Template files contain {{placeholder}}
# tokens by design, so they are rendered with unique dummy values first and
# the rendered result is validated. Exits non-zero if any file fails.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
RENDERED="/tmp/mb-rendered-compose.yml"

render_template() {
    python3 - "$1" > "$RENDERED" <<'PYEOF'
import re, sys

text = open(sys.argv[1]).read()
seen = {}

def sub(m):
    tok = m.group(1)
    if tok not in seen:
        u = tok.upper()
        if u.endswith('_CONTAINER_PORT'):
            seen[tok] = '80'
        elif u.endswith('_PORT'):
            seen[tok] = '8080'
        elif u.endswith('_IMAGE'):
            seen[tok] = 'nginx:alpine'
        elif u.endswith('_NAME_UPPER'):
            seen[tok] = 'APP%d' % len(seen)
        elif u.endswith('_NAME'):
            seen[tok] = 'app%d' % len(seen)
        else:
            seen[tok] = 'val%d' % len(seen)
    return seen[tok]

print(re.sub(r'\{\{([A-Za-z_0-9]+)\}\}', sub, text))
PYEOF
}

count=0
failed=0
while IFS= read -r -d '' f; do
    case "$f" in
        */templates/*)
            render_template "$f"
            target="$RENDERED"
            ;;
        *)
            target="$f"
            ;;
    esac
    if docker compose -f "$target" config -q; then
        echo "OK $f"
        count=$((count + 1))
    else
        echo "FAIL $f"
        failed=$((failed + 1))
    fi
done < <(find "$ROOT" \( -name 'compose.yml' -o -name 'docker-compose.yml' \) -not -path '*/.git/*' -print0)

echo "compose config: $count valid, $failed failed"
[ "$failed" -eq 0 ]
