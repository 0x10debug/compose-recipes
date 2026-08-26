# RAG Setup Guide

This guide walks through configuring retrieval-augmented generation (RAG) on the
ai-automation suite. It covers Qdrant collection creation, embedding model
selection, document chunking, the n8n workflow, Flowise RAG, and hybrid search.

The suite already ships everything you need: Qdrant for vector storage, Ollama
for local embeddings and generation, n8n for orchestration, and Flowise as a
no-code alternative. No new containers or ports are required — RAG reuses the
existing ai-automation services.

## Overview

```
 Document ──chunk──▶ embed ──▶ Qdrant collection
                                   ▲
 Query ───embed──▶ Qdrant search ──┘
                       │
                       ▼ top-k chunks
                   prompt + LLM ──▶ answer
```

## 1. Create the Qdrant Collection

A Qdrant collection fixes the vector dimensionality at creation time, so you
must decide on an embedding model **before** inserting any points. Use the
provided `init-qdrant.sh` script:

```bash
# Local embeddings (768-dim, no API key)
./init-qdrant.sh --model ollama --collection rag_docs

# OpenAI embeddings (1536-dim, requires OPENAI_API_KEY)
./init-qdrant.sh --model openai --collection rag_docs
```

The script configures:

| Parameter | Value | Purpose |
|-----------|-------|---------|
| `vectors.size` | 768 / 1536 | Must match the embedding model output |
| `vectors.distance` | Cosine | Standard for normalized text embeddings |
| `hnsw_config.m` | 16 | Edges per node in the HNSW graph |
| `hnsw_config.ef_construct` | 100 | Index build search width |
| `optimizers_config.indexing_threshold` | 20000 | Points before indexing kicks in |

The script is idempotent. Pass `--recreate` to drop and rebuild a collection
(for example when switching embedding models, which changes the dimensionality).

## 2. Choose an Embedding Model

| Model | Runtime | Dimension | API Key | Data leaves VPS | Best for |
|-------|---------|-----------|---------|-----------------|----------|
| `nomic-embed-text` | Ollama (local) | 768 | No | No | Privacy, offline, cost zero |
| `text-embedding-3-small` | OpenAI API | 1536 | Yes | Yes | Best quality, low cost |

**Recommendation: start with `nomic-embed-text`.** It keeps all data on the VPS,
needs no API key, and is good enough for most knowledge-base RAG. Move to OpenAI
only if retrieval quality on your specific corpus is insufficient.

Pull the Ollama embedding model:

```bash
docker exec ollama ollama pull nomic-embed-text
```

For OpenAI, export your key in the shell where you run the embedding step, and
ensure the n8n/Flowise credential is configured with it.

> **Dimensionality is fixed per collection.** You cannot mix 768-dim and
> 1536-dim vectors in the same collection. To switch models, recreate the
> collection with `init-qdrant.sh --model <new> --recreate` and re-embed all
> documents.

## 3. Document Chunking Strategy

Chunking turns long documents into retrieval-sized pieces. The suite's
`rag/embed-documents.sh` and the n8n template both default to:

| Parameter | Default | When to change |
|-----------|---------|----------------|
| Chunk size | 1000 chars | Lower (600–800) for dense factual docs; higher (1200–1500) for narrative |
| Overlap | 150 chars | Raise to 200–250 if answers often span chunk boundaries |

Guidelines:

- **Character splits** are simple and work for plain text. The shipped scripts
  break on the nearest whitespace to the boundary so chunks do not cut mid-word.
- **Sentence-aware splits** improve quality for prose. In n8n, use a Code node
  with a sentence boundary regex; in Flowise, use the RecursiveCharacterTextSplitter.
- **Markdown / code-aware splits** preserve structure (headers, code fences).
  Prefer these for technical documentation.
- **Overlap** prevents losing a sentence that straddles two chunks. 10–20% of
  the chunk size is a reasonable range.

Chunk size trades off against the LLM context window: retrieved chunks plus the
question must fit in the prompt. With `llama3.1` (128k context) this is rarely
an issue, but smaller models may need fewer / smaller chunks.

## 4. Embed Documents

### Option A — Shell script (reference implementation)

```bash
# Embed the bundled sample documents
./rag/embed-documents.sh --model nomic-embed-text --collection rag_docs

# Embed your own documents
./rag/embed-documents.sh --dir /path/to/your/docs --collection rag_docs \
  --chunk-size 1000 --chunk-overlap 150
```

The script chunks each `.txt` file, calls the Ollama embeddings API per chunk,
and upserts points into Qdrant with payload `{source, chunk, text}`. It needs
only `curl`, `jq`, and `awk` — no Python.

### Option B — n8n workflow

Import [`n8n-workflows/rag-template.json`](../n8n-workflows/rag-template.json)
and POST documents to the `rag-ingest` webhook. See
[`n8n-workflows/README.md`](../n8n-workflows/README.md).

### Option C — Flowise

In Flowise, create a Vector Store node pointing at Qdrant (`http://qdrant:6333`,
collection `rag_docs`) with the Ollama embedder, then use the Document Loader +
Text Splitter nodes to ingest files. See section 6 below.

## 5. n8n Workflow Configuration

The template (`rag-template.json`) provides two webhooks:

| Webhook | Path | Input | Output |
|---------|------|-------|--------|
| Ingest | `POST /webhook/rag-ingest` | `{"text": "...", "source": "..."}` | upserts chunks into Qdrant |
| Query | `POST /webhook/rag-query` | `{"question": "..."}` | LLM answer grounded in retrieved context |

After importing:

1. Confirm the Ollama model names (`nomic-embed-text`, `llama3.1`) match what
   you pulled.
2. Confirm the Qdrant collection name (`rag_docs`) matches what
   `init-qdrant.sh` created.
3. Activate the workflow.
4. Test with `curl` (examples in the workflow README).

To use OpenAI embeddings instead, swap the Ollama embed nodes for the OpenAI
embeddings node and recreate the collection at 1536-dim.

## 6. Flowise RAG Configuration

Flowise offers a drag-and-drop RAG builder. A minimal chatflow:

1. **Chat Model** → Ollama, model `llama3.1`, base URL `http://ollama:11434`.
2. **Embeddings** → Ollama, model `nomic-embed-text`, base URL `http://ollama:11434`.
3. **Vector Store** → Qdrant, URL `http://qdrant:6333`, collection `rag_docs`.
4. **Text Splitter** → Recursive Character, chunk size 1000, overlap 150.
5. **Document Loader** → Text File / PDF / Web URL, connected to the splitter,
   then to the vector store (ingest mode).
6. **Conversational Retrieval QA Chain** → connects Chat Model + Vector Store;
   this is the query-time chain that retrieves and generates.

Save the chatflow, then use the API or the embedded chat widget to ask
questions. Flowise handles the chunk/embed/store/retrieve/generate loop in the
UI without writing code.

## 7. Hybrid Search (Vector + Keyword)

Pure vector search can miss exact matches for rare proper nouns, identifiers,
or error codes that embedding models underweight. Hybrid search combines dense
vector retrieval with keyword filtering.

### Qdrant payload filter (simple)

Add a `filter` clause to the search request that matches the `text` payload
field against a keyword:

```json
{
  "vector": [0.12, -0.04, ...],
  "filter": {
    "should": [
      { "field": { "key": "text", "type": "text" }, "condition": { "match": { "any": ["Qdrant", "HNSW"] } } }
    ]
  },
  "limit": 4
}
```

This narrows the candidate set to chunks containing the keywords, then ranks
them by vector similarity.

### Qdrant sparse vectors (advanced, v1.10+)

Qdrant supports sparse vectors for BM25-style scoring alongside dense vectors.
You store both a dense and a sparse vector per point and query with both,
letting Qdrant fuse the results. This gives true hybrid ranking but requires a
sparse vector producer (e.g. a BM25 tokenizer). For most knowledge bases the
payload filter above is sufficient and far simpler.

### In n8n

Add a `filter` object to the Qdrant Search HTTP Request body, built from
keywords extracted from the question (a Code node can split the question into
terms and build the filter JSON).

### In Flowise

Use the Qdrant node's metadata filter input, or chain a keyword filter
component before the retrieval node.

## 8. Operations Cheatsheet

```bash
# Collection count
curl -s http://localhost:6333/collections/rag_docs/points/count | jq

# Search by vector (replace with a real embedding)
curl -s -X POST http://localhost:6333/collections/rag_docs/points/search \
  -H 'Content-Type: application/json' \
  -d '{"vector": [0.1, ...], "limit": 4, "with_payload": true}' | jq

# Delete a collection (rebuild from scratch)
curl -X DELETE http://localhost:6333/collections/rag_docs

# Recreate via script
./init-qdrant.sh --model ollama --collection rag_docs --recreate
```

## 9. Troubleshooting

| Symptom | Likely cause | Fix |
|---------|--------------|-----|
| `embedding is null` from Ollama | model not pulled | `docker exec ollama ollama pull nomic-embed-text` |
| Qdrant 400 on upsert | vector size mismatch | recreate collection with matching `--model` |
| Search returns nothing | collection empty | run `embed-documents.sh` or the ingest webhook |
| LLM ignores context | prompt not grounded | ensure the Build Prompt node injects retrieved chunks |
| Slow ingest | ef_construct too high | lower `hnsw_config.ef_construct` on (re)create |
