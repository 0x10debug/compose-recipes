# AI Automation Suite

A self-hosted AI automation stack: workflow orchestration, local LLM inference, vector search, and a low-code AI flow builder. Inspired by [n8n-io/self-hosted-ai-starter-kit](https://github.com/n8n-io/self-hosted-ai-starter-kit), adapted to the `mb` suite conventions (pinned tags, healthchecks, `mb-proxy` network, unified `/data` volumes).

## What's Included

| App | Purpose | Default Port | Profile |
|-----|---------|--------------|---------|
| n8n | Workflow / agent automation (visual editor + webhooks) | 5678 | default |
| Ollama | Local LLM runtime (Llama 3, Qwen, etc.) | 11434 | default |
| Qdrant | Vector database for RAG / memory | 6333 | default |
| Flowise | Low-code AI flow builder (drag-and-drop LangChain) | 8150 | flowise |

## Architecture

```
                         ┌──────────────┐
                         │  mb-proxy    │  (reverse proxy / TLS)
                         │  network     │
                         └──────┬───────┘
          ┌─────────────────────┼──────────────────────┐
          ▼                     ▼                      ▼
   ┌──────────────┐    ┌──────────────┐       ┌──────────────┐
   │     n8n      │───▶│    Ollama    │       │   Flowise    │
   │  :5678       │    │  :11434      │       │  :8150→3000  │
   │  workflows   │    │  local LLM   │       │  low-code AI │
   └──────┬───────┘    └──────────────┘       └──────┬───────┘
          │                                           │
          │            ┌──────────────┐               │
          └───────────▶│   Qdrant     │◀──────────────┘
                       │  :6333       │
                       │  vector DB   │
                       └──────────────┘
```

- **n8n** orchestrates end-to-end automations and calls Ollama (`OLLAMA_HOST=http://ollama:11434`) and Qdrant (`QDRANT_URL=http://qdrant:6333`) over the shared `mb-proxy` network.
- **Ollama** serves local models from `/data/ollama`; pull a model with `docker exec ollama ollama pull llama3.1`.
- **Qdrant** stores embeddings for retrieval-augmented generation and agent memory.
- **Flowise** (optional, `--profile flowise`) provides a no-code alternative to n8n's AI nodes for LangChain-style flows.

## Quick Start

1. Copy the example env file and fill in your values:

   ```bash
   cp .env.example .env
   # edit .env — set AI_AUTOMATION_DOMAIN, N8N_ENCRYPTION_KEY, FLOWISE_PASSWORD
   ```

2. Create the data directories (see [Data Directories](#data-directories)).

3. Start the core services (n8n + Ollama + Qdrant):

   ```bash
   docker compose up -d
   ```

4. To also start the Flowise builder, use the `flowise` profile:

   ```bash
   docker compose --profile flowise up -d
   ```

5. To start everything at once:

   ```bash
   docker compose --profile all up -d
   ```

6. Pull a first LLM into Ollama:

   ```bash
   docker exec ollama ollama pull llama3.1
   ```

## Data Directories

All persistent data lives under `/data` on the host:

| Path | Service |
|------|---------|
| `/data/n8n` | n8n workflows, credentials, executions |
| `/data/ollama` | Ollama downloaded models |
| `/data/qdrant/storage` | Qdrant collection data |
| `/data/qdrant/snapshots` | Qdrant snapshots |
| `/data/flowise` | Flowise flows, credentials, DB |

## Port Planning

| Service | Host Port | Container Port | Notes |
|---------|-----------|----------------|-------|
| n8n | 5678 | 5678 | n8n default |
| Ollama | 11434 | 11434 | Ollama default |
| Qdrant | 6333 | 6333 | Qdrant default |
| Flowise | 8150 | 3000 | Host port 8150 avoids conflict with dev-environment (Gitea, host 3000) and self-hosted-cloud (Outline, host 3000) |

See [docs/port-allocation.md](../../docs/port-allocation.md) for the global port table.

## Reverse Proxy

This suite sits behind a reverse proxy on the external `mb-proxy` Docker network. Set up TLS termination and route traffic to each service's container port. A common layout:

- `https://ai.example.com/n8n/` → n8n `:5678`
- `https://ai.example.com/flowise/` → Flowise `:8150`
- `https://ai.example.com/qdrant/` → Qdrant `:6333` (consider restricting to internal)

For a ready-made reverse proxy / networking toolkit, see:
https://github.com/0x10debug/network-toolkit

## Boundary with the `ai-workstation` repo

This suite only deploys **server-side, always-on AI automation services** (workflow engine, LLM runtime, vector store, flow builder). It does **not** include:

- GPU driver / CUDA installation — handled by the host OS or `vps-bootstrap`.
- Desktop ML tooling, Jupyter notebooks, or model training pipelines — those belong in the `ai-workstation` repo (interactive / per-user workstations).
- Model fine-tuning or dataset management — also `ai-workstation`.

In short: **compose-recipes/ai-automation = shared services that run 24/7 on the VPS; ai-workstation = interactive per-developer ML environments.** The two repos are complementary and do not overlap.

## Notes

- **GPU**: Ollama runs on CPU by default. To enable GPU acceleration, add `deploy.resources.reservations.devices` to the `ollama` service and install NVIDIA Container Toolkit on the host. See the [Ollama Docker docs](https://github.com/ollama/ollama/blob/main/docs/docker.md).
- **Model size**: Ollama models live in `/data/ollama` and can be large (multi-GB). Ensure the VPS has enough disk.
- **n8n credentials**: `N8N_ENCRYPTION_KEY` encrypts stored credentials. Keep it safe; losing it makes existing credentials unrecoverable.

## RAG (Retrieval-Augmented Generation)

The suite ships everything needed to build a RAG knowledge base on top of
Qdrant + Ollama, with no new containers or ports. Bundled helpers:

| Path | Purpose |
|------|---------|
| [`init-qdrant.sh`](init-qdrant.sh) | Create a Qdrant collection for `nomic-embed-text` (768-dim) or OpenAI `text-embedding-3-small` (1536-dim) |
| [`rag/embed-documents.sh`](rag/embed-documents.sh) | Example: chunk + embed `.txt` files into Qdrant via Ollama |
| [`rag/sample-documents/`](rag/sample-documents/) | Sample `.txt` documents to test the pipeline |
| [`n8n-workflows/rag-template.json`](n8n-workflows/rag-template.json) | Importable n8n workflow: ingest + query RAG loop |
| [`n8n-workflows/README.md`](n8n-workflows/README.md) | Workflow import and usage instructions |
| [`docs/rag-setup.md`](docs/rag-setup.md) | Full RAG configuration guide (collections, embeddings, chunking, Flowise, hybrid search) |

Quick start:

```bash
docker compose up -d
docker exec ollama ollama pull nomic-embed-text
docker exec ollama ollama pull llama3.1
./init-qdrant.sh --model ollama --collection rag_docs
./rag/embed-documents.sh --collection rag_docs
```

Then import `n8n-workflows/rag-template.json` into n8n for a managed ingest +
query loop, or follow [docs/rag-setup.md](docs/rag-setup.md) to configure RAG
in Flowise.
