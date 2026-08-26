# n8n RAG Workflow Template

This directory contains an importable n8n workflow that implements a complete
retrieval-augmented generation (RAG) loop on top of the ai-automation suite:
document ingest (chunk → embed → store) and query (embed → search → generate).

## Template

| File | Description |
|------|-------------|
| `rag-template.json` | Two-webhook workflow: `rag-ingest` and `rag-query` |

### Ingest path (`POST /rag-ingest`)

```
Ingest Webhook → Chunk Document → Ollama Embed → Qdrant Upsert
```

Send a JSON body:

```json
{ "text": "Your document text here...", "source": "handbook.md" }
```

The Code node splits the text into ~1000-character chunks with 150 characters
of overlap, the Ollama node embeds each chunk with `nomic-embed-text`, and the
HTTP Request node upserts the points into the `rag_docs` Qdrant collection.

### Query path (`POST /rag-query`)

```
Query Webhook → Embed Query → Qdrant Search → Build Prompt → LLM Generate
```

Send a JSON body:

```json
{ "question": "What services are in the ai-automation suite?" }
```

The workflow embeds the question, searches Qdrant for the top 4 similar chunks,
stitches them into a prompt with the question, and asks `llama3.1` to answer
using only the retrieved context.

## Prerequisites

1. The ai-automation suite is running:

   ```bash
   docker compose up -d
   ```

2. The Ollama models are pulled:

   ```bash
   docker exec ollama ollama pull nomic-embed-text   # embedding model
   docker exec ollama ollama pull llama3.1            # generation model
   ```

3. The Qdrant collection exists (768-dim for `nomic-embed-text`):

   ```bash
   ./init-qdrant.sh --model ollama --collection rag_docs
   ```

4. n8n can reach Ollama and Qdrant over the `mb-proxy` network. The compose file
   already sets `OLLAMA_HOST=http://ollama:11434` and `QDRANT_URL=http://qdrant:6333`.

## Import

1. Open the n8n editor at `http://<host>:5678`.
2. Click **Import from File** (or drag the JSON onto the canvas).
3. Select `rag-template.json`.
4. Review the node parameters:
   - **Ollama Embed** / **Embed Query** / **LLM Generate**: confirm the model
     names match what you pulled.
   - **Qdrant Upsert** / **Qdrant Search**: confirm the collection name
     (`rag_docs`) matches what `init-qdrant.sh` created.
5. Save the workflow. Activate it with the toggle in the top-right.

## Usage

Once active, the two webhooks are served by n8n. With the default
`WEBHOOK_URL=http://localhost:5678`:

```bash
# Ingest a document
curl -X POST http://localhost:5678/webhook/rag-ingest \
  -H 'Content-Type: application/json' \
  -d '{"text":"The ai-automation suite bundles n8n, Ollama, Qdrant and Flowise.","source":"overview.txt"}'

# Ask a question
curl -X POST http://localhost:5678/webhook/rag-query \
  -H 'Content-Type: application/json' \
  -d '{"question":"Which services are in the ai-automation suite?"}'
```

## Adapting the Template

- **Switch to OpenAI embeddings**: replace the Ollama embed nodes with the
  OpenAI embeddings node, set the model to `text-embedding-3-small`, and
  recreate the Qdrant collection with `--model openai` (1536-dim). See
  [docs/rag-setup.md](../docs/rag-setup.md).
- **Chunk size**: edit the `chunkSize` and `overlap` constants in the
  `Chunk Document` Code node.
- **Retrieval count**: change the `limit` in the Qdrant Search node.
- **Hybrid search**: add a keyword filter to the Qdrant Search body using the
  `filter` field; see the Qdrant docs and [docs/rag-setup.md](../docs/rag-setup.md).

## Notes

- The template uses `n8n-nodes-base.ollama` (the built-in Ollama node). If your
  n8n version does not ship it, install the `n8n-nodes-ollama` community node,
  or replace the embed/generate nodes with HTTP Request nodes calling
  `http://ollama:11434/api/embeddings` and `http://ollama:11434/api/generate`.
- Point IDs in the template are derived from `$runIndex + 1`, which is fine for
  a single ingest run. For production, use UUIDs or a deterministic hash to
  avoid collisions across multiple ingests.
