#!/usr/bin/env bash
# init-qdrant.sh — Create Qdrant collections for RAG with two embedding profiles.
#
# Supported embedding models (select via --model):
#   openai   text-embedding-3-small  (1536-dim, requires OPENAI_API_KEY)
#   ollama   nomic-embed-text        (768-dim,  local,  requires Ollama running)
#
# The script is idempotent: if a collection already exists it is left untouched
# unless --recreate is passed, in which case it is deleted and recreated.
#
# Usage:
#   ./init-qdrant.sh --model ollama                       # default collection "rag_docs"
#   ./init-qdrant.sh --model openai --collection my_kb
#   ./init-qdrant.sh --model ollama --recreate            # drop + recreate
#   QDRANT_URL=http://qdrant:6333 ./init-qdrant.sh --model ollama
#
# Run from the repo root or the suite directory. Requires curl + jq.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────

QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
COLLECTION="${RAG_COLLECTION:-rag_docs}"
MODEL="ollama"
RECREATE=false

# ── Embedding model profiles ──────────────────────────────────────────────────
#   dimension : vector size expected by the model
#   distance  : Qdrant distance metric (Cosine is the standard for embeddings)
#   hnsw_m    : number of edges per node in the HNSW graph (16 is a good default)
#   hnsw_ef   : construction search width (higher = better recall, slower build)

declare -A DIMENSION=(
  [openai]=1536
  [ollama]=768
)
declare -A DISTANCE=(
  [openai]="Cosine"
  [ollama]="Cosine"
)
declare -A HNSW_M=(
  [openai]=16
  [ollama]=16
)
declare -A HNSW_EF_CONSTRUCT=(
  [openai]=100
  [ollama]=100
)

# ── Arg parsing ───────────────────────────────────────────────────────────────

usage() {
  cat <<'USAGE'
init-qdrant.sh — Create a Qdrant collection for RAG embeddings.

USAGE:
  ./init-qdrant.sh [--model openai|ollama] [--collection NAME] [--recreate] [--url URL]

OPTIONS:
  --model MODEL        Embedding model profile: openai (1536-dim) or ollama (768-dim). Default: ollama
  --collection NAME    Qdrant collection name. Default: rag_docs (or $RAG_COLLECTION)
  --recreate           Delete the collection first if it exists.
  --url URL            Qdrant base URL. Default: $QDRANT_URL or http://localhost:6333
  -h, --help           Show this help.

EMBEDDING MODELS:
  openai   text-embedding-3-small  1536-dim  (set OPENAI_API_KEY in your environment)
  ollama   nomic-embed-text         768-dim  (pull with: docker exec ollama ollama pull nomic-embed-text)
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --model)      MODEL="$2"; shift 2 ;;
    --collection) COLLECTION="$2"; shift 2 ;;
    --recreate)   RECREATE=true; shift ;;
    --url)        QDRANT_URL="$2"; shift 2 ;;
    -h|--help)    usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

# ── Validate model choice ─────────────────────────────────────────────────────

if [ -z "${DIMENSION[$MODEL]:-}" ]; then
  echo "ERROR: unknown model '$MODEL'. Choose 'openai' or 'ollama'." >&2
  exit 2
fi

DIM="${DIMENSION[$MODEL]}"
DIST="${DISTANCE[$MODEL]}"
M="${HNSW_M[$MODEL]}"
EF="${HNSW_EF_CONSTRUCT[$MODEL]}"

# ── Helpers ───────────────────────────────────────────────────────────────────

qdrant_get() {
  curl -fsS -H "Content-Type: application/json" "$QDRANT_URL$1"
}

qdrant_delete() {
  curl -fsS -X DELETE "$QDRANT_URL$1" -o /dev/null
}

qdrant_put() {
  curl -fsS -X PUT -H "Content-Type: application/json" "$QDRANT_URL$1" -d "$2"
}

# ── Preflight ─────────────────────────────────────────────────────────────────

command -v curl >/dev/null || { echo "ERROR: curl is required." >&2; exit 1; }
command -v jq   >/dev/null || { echo "ERROR: jq is required." >&2;   exit 1; }

echo "Qdrant URL    : $QDRANT_URL"
echo "Collection    : $COLLECTION"
echo "Embedding     : $MODEL ($DIM-dim, $DIST)"
echo "HNSW          : m=$M ef_construct=$EF"
echo ""

# Wait for Qdrant to be reachable (max ~30s).
echo "Checking Qdrant health..."
for _ in $(seq 1 15); do
  if qdrant_get /healthz >/dev/null 2>&1; then
    echo "  Qdrant is healthy."
    break
  fi
  sleep 2
done
qdrant_get /healthz >/dev/null 2>&1 || { echo "ERROR: Qdrant not reachable at $QDRANT_URL" >&2; exit 1; }

# ── Recreate if requested ─────────────────────────────────────────────────────

if [ "$RECREATE" = true ]; then
  if qdrant_get "/collections/$COLLECTION" >/dev/null 2>&1; then
    echo "Deleting existing collection '$COLLECTION' (--recreate)..."
    qdrant_delete "/collections/$COLLECTION"
  fi
fi

# ── Create collection if missing ──────────────────────────────────────────────

if qdrant_get "/collections/$COLLECTION" >/dev/null 2>&1; then
  EXISTING_DIM=$(qdrant_get "/collections/$COLLECTION" | jq -r '.result.config.params.vectors.size // .result.config.params.vectors.default.size // "unknown"')
  echo "Collection '$COLLECTION' already exists (vector size: $EXISTING_DIM)."
  if [ "$EXISTING_DIM" != "$DIM" ]; then
    echo "WARNING: existing vector size ($EXISTING_DIM) != requested ($DIM)." >&2
    echo "         Pass --recreate to rebuild with the new dimension." >&2
  fi
  echo "Nothing to do. Use --recreate to force rebuild."
  exit 0
fi

echo "Creating collection '$COLLECTION'..."

PAYLOAD=$(cat <<JSON
{
  "vectors": { "size": $DIM, "distance": "$DIST" },
  "hnsw_config": { "m": $M, "ef_construct": $EF, "full_scan_threshold": 10000 },
  "optimizers_config": { "default_segment_number": 2, "indexing_threshold": 20000 },
  "on_disk_payload": false,
  "shard_number": 1
}
JSON
)

qdrant_put "/collections/$COLLECTION" "$PAYLOAD"
echo ""

# ── Verify ────────────────────────────────────────────────────────────────────

CREATED_DIM=$(qdrant_get "/collections/$COLLECTION" | jq -r '.result.config.params.vectors.size // .result.config.params.vectors.default.size')
echo "Created collection '$COLLECTION' with vector size: $CREATED_DIM"
[ "$CREATED_DIM" = "$DIM" ] || { echo "ERROR: vector size mismatch after creation." >&2; exit 1; }

echo ""
echo "Done. Next:"
echo "  - Ollama:  docker exec ollama ollama pull nomic-embed-text"
echo "  - OpenAI:  export OPENAI_API_KEY=sk-..."
echo "  - Embed:   ./rag/embed-documents.sh --model $MODEL --collection $COLLECTION"
