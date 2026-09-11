#!/usr/bin/env bash
# scripts/hardening-lint.sh — Enforce the container hardening baseline.
#
# Every service in every suite compose file must set
#   security_opt: [no-new-privileges:true]
# unless it is on the exception allowlist below (which must match a justified
# row in docs/hardening-matrix.md). Exits non-zero on any violation.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Exceptions: service -> reason. Must mirror docs/hardening-matrix.md.
# (empty today - see the matrix "Exceptions" section)
exceptions=(
    # "suite/service:reason"
)

is_exempt() {
    local svc="$1"
    local entry
    for entry in "${exceptions[@]}"; do
        if [[ "$entry" == "$svc:"* ]]; then
            return 0
        fi
    done
    return 1
}

violations=0
checked=0
while IFS= read -r -d '' f; do
    suite="$(basename "$(dirname "$f")")"
    while IFS=$'\t' read -r name nnp; do
        checked=$((checked + 1))
        if [ "$nnp" != "yes" ]; then
            if is_exempt "${suite}/${name}"; then
                echo "EXEMPT ${suite}/${name}"
            else
                echo "VIOLATION ${suite}/${name}: no security_opt no-new-privileges"
                violations=$((violations + 1))
            fi
        fi
    done < <(python3 - "$f" <<'PYEOF'
import sys, yaml
d = yaml.safe_load(open(sys.argv[1]))
for name, svc in (d.get("services") or {}).items():
    opts = [str(o) for o in (svc.get("security_opt") or [])]
    nnp = "yes" if any("no-new-privileges" in o for o in opts) else "no"
    print(f"{name}\t{nnp}")
PYEOF
)
done < <(find "$ROOT/suites" -name 'compose.yml' -not -path '*/.git/*' -print0)

echo "hardening-lint: $checked services checked, $violations violations"
[ "$violations" -eq 0 ]
