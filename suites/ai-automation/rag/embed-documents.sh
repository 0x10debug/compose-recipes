#!/usr/bin/env bash
# embed-documents.sh — Example: chunk + embed text documents into Qdrant using
# the Ollama `nomic-embed-text` model (local, no API key needed).
#
# This is a minimal, dependency-light reference implementation. It splits each
# .txt file into fixed-size chunks, generates an embedding per chunk via the
# Ollama embeddings API, and upserts the points into a Qdrant collection.
#
# For production scale, prefer the n8n RAG workflow template
# (../n8n-workflows/rag-template.json) or Flowise, which handle chunking
# strategies, metadata, and retrieval in a managed UI.
#
# Prerequisites:
#   - ai-automation suite running (docker compose up -d)
#   - Ollama embedding model pulled:
#       docker exec ollama ollama pull nomic-embed-text
#   - Qdrant collection created:
#       ./init-qdrant.sh --model ollama --collection rag_docs
#
# Usage:
#   ./embed-documents.sh                                   # embed ./sample-documents/*.txt
#   ./embed-documents.sh --dir /path/to/docs --collection rag_docs
#   ./embed-documents.sh --chunk-size 800 --chunk-overlap 120
#   OLLAMA_URL=http://ollama:11434 QDRANT_URL=http://qdrant:6333 ./embed-documents.sh
#
# Requires: curl, jq, awk, base64. No Python needed.

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────────────────────

OLLAMA_URL="${OLLAMA_URL:-http://localhost:11434}"
QDRANT_URL="${QDRANT_URL:-http://localhost:6333}"
COLLECTION="${RAG_COLLECTION:-rag_docs}"
EMBED_MODEL="${OLLAMA_EMBED_MODEL:-nomic-embed-text}"
DOCS_DIR=""
CHUNK_SIZE=1000        # characters per chunk
CHUNK_OVERLAP=150      # character overlap between consecutive chunks
LLM_MODEL="${OLLAMA_LLM_MODEL:-llama3.1}"

DEFAULT_DOCS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/sample-documents"

# ── Arg parsing ───────────────────────────────────────────────────────────────

usage() {
  cat <<'USAGE'
embed-documents.sh — Chunk and embed .txt documents into Qdrant (Ollama embeddings).

USAGE:
  ./embed-documents.sh [OPTIONS] [--dir DIR]

OPTIONS:
  --dir DIR            Directory of .txt files to embed. Default: ./sample-documents
  --collection NAME    Qdrant collection. Default: rag_docs (or $RAG_COLLECTION)
  --chunk-size N       Chunk size in characters. Default: 1000
  --chunk-overlap N    Overlap between chunks in characters. Default: 150
  --model NAME         Ollama embedding model. Default: nomic-embed-text (or $OLLAMA_EMBED_MODEL)
  -h, --help           Show this help.

ENV:
  OLLAMA_URL           Default: http://localhost:11434
  QDRANT_URL           Default: http://localhost:6333
USAGE
}

while [ $# -gt 0 ]; do
  case "$1" in
    --dir)           DOCS_DIR="$2"; shift 2 ;;
    --collection)    COLLECTION="$2"; shift 2 ;;
    --chunk-size)    CHUNK_SIZE="$2"; shift 2 ;;
    --chunk-overlap) CHUNK_OVERLAP="$2"; shift 2 ;;
    --model)         EMBED_MODEL="$2"; shift 2 ;;
    -h|--help)       usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
done

[ -n "$DOCS_DIR" ] || DOCS_DIR="$DEFAULT_DOCS_DIR"

# ── Preflight ─────────────────────────────────────────────────────────────────

for cmd in curl jq awk base64; do
  command -v "$cmd" >/dev/null || { echo "ERROR: $cmd is required." >&2; exit 1; }
done

echo "Ollama URL    : $OLLAMA_URL"
echo "Qdrant URL    : $QDRANT_URL"
echo "Collection    : $COLLECTION"
echo "Embed model   : $EMBED_MODEL"
echo "Chunk size    : $CHUNK_SIZE chars (overlap $CHUNK_OVERLAP)"
echo "Documents dir : $DOCS_DIR"
echo ""

# Verify the embedding model is available in Ollama.
if ! curl -fsS "$OLLAMA_URL/api/tags" | jq -e --arg m "$EMBED_MODEL" \
    '.models[] | select(.name | startswith($m))' >/dev/null 2>&1; then
  echo "ERROR: embedding model '$EMBED_MODEL' not found in Ollama." >&2
  echo "       Pull it with: docker exec ollama ollama pull $EMBED_MODEL" >&2
  exit 1
fi

# Verify the Qdrant collection exists.
if ! curl -fsS "$QDRANT_URL/collections/$COLLECTION" >/dev/null 2>&1; then
  echo "ERROR: Qdrant collection '$COLLECTION' does not exist." >&2
  echo "       Create it with: ./init-qdrant.sh --model ollama --collection $COLLECTION" >&2
  exit 1
fi

shopt -s nullglob
DOC_FILES=("$DOCS_DIR"/*.txt)
if [ ${#DOC_FILES[@]} -eq 0 ]; then
  echo "ERROR: no .txt files found in $DOCS_DIR" >&2
  exit 1
fi

# ── Chunking helper ───────────────────────────────────────────────────────────
# Splits text on whitespace boundaries near CHUNK_SIZE, with CHUNK_OVERLAP of
# trailing context carried into the next chunk. Pure awk, no Python.

chunk_text() {
  awk -v size="$CHUNK_SIZE" -v overlap="$CHUNK_OVERLAP" '
    {
      text = text $0 "\n"
    }
    END {
      len = length(text)
      pos = 1
      idx = 0
      while (pos <= len) {
        end = pos + size - 1
        if (end > len) end = len
        # try to break on a whitespace near the boundary
        if (end < len) {
          for (b = end; b > pos + size/2; b--) {
            ch = substr(text, b, 1)
            if (ch == " " || ch == "\n" || ch == "\t") { end = b - 1; break }
          }
        }
        chunk = substr(text, pos, end - pos + 1)
        gsub(/\r/, "", chunk)
        if (length(chunk) > 0) {
          idx++
          print idx "\t" chunk
        }
        pos = end - overlap + 1
        if (pos <= (end - overlap)) pos = end + 1   # safety: always advance
      }
    }
  '
}

# ── Embed + upsert loop ───────────────────────────────────────────────────────

POINT_ID=1
TOTAL_POINTS=0

for doc in "${DOC_FILES[@]}"; do
  doc_name="$(basename "$doc")"
  echo "Processing: $doc_name"

  # Read file and chunk it.
  mapfile -t CHUNKS < <(chunk_text < "$doc")
  chunk_count=${#CHUNKS[@]}
  echo "  chunks: $chunk_count"

  for line in "${CHUNKS[@]}"; do
    # line format: "<idx>\t<chunk text>"
    idx="${line%%$'\t'*}"
    chunk="${line#*$'\t'}"

    [ -n "$chunk" ] || continue

    # Build the Ollama embeddings request. The prompt is the chunk text.
    # We use jq to safely JSON-encode the chunk.
    embed_req=$(jq -n --arg m "$EMBED_MODEL" --arg p "$chunk" \
      '{model: $m, prompt: $p}')

    # Call Ollama embeddings API.
    embedding_json=$(curl -fsS "$OLLAMA_URL/api/embeddings" -d "$embed_req")
    embedding=$(echo "$embedding_json" | jq -c '.embedding')
    [ "$embedding" != "null" ] || { echo "  ERROR: no embedding returned for chunk $idx" >&2; continue; }

    # Build Qdrant upsert payload. We store the source doc name, chunk index,
    # and the raw chunk text as payload so retrieval can return provenance.
    payload=$(jq -n \
      --argjson id "$POINT_ID" \
      --argjson vector "$embedding" \
      --arg doc "$doc_name" \
      --argjson idx "$idx" \
      --arg text "$chunk" \
      '{points: [{id: $id, vector: $vector, payload: {source: $doc, chunk: $idx, text: $text}}]}')

    # Upsert into Qdrant.
    curl -fsS -X PUT "$QDRANT_URL/collections/$COLLECTION/points?wait=true" \
      -H "Content-Type: application/json" -d "$payload" >/dev/null

    POINT_ID=$((POINT_ID + 1))
    TOTAL_POINTS=$((TOTAL_POINTS + 1))
  done
  echo "  done."
done

echo ""
echo "Embedded $TOTAL_POINTS chunks from ${#DOC_FILES[@]} document(s) into '$COLLECTION'."
echo ""
echo "Test retrieval:"
echo "  curl -s $QDRANT_URL/collections/$COLLECTION/points/count | jq"
echo ""
echo "Query a similar chunk (semantic search):"
echo "  See docs/rag-setup.md for the search + LLM generation flow."
