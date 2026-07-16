# mcp-n4j-memory

Self-hosted, dockerized **Model Context Protocol (MCP)** server that exposes persistent,
graph-native agent memory backed by **Neo4j**. It packages the
[`neo4j-agent-memory`](https://github.com/neo4j-labs/agent-memory) framework — this
repository is a **deployment + configuration** layer (compose file, container images,
LiteLLM routing, env), not a from-scratch reimplementation.

MCP clients (Copilot, Claude, Cursor, other agents) connect to the `mcp` service to store
and recall long-lived "memories" as a Neo4j knowledge graph: nodes are entities/observations,
relationships connect them, and a local embedder powers semantic (vector) search.

See [`docs/SPECIFICATION.md`](./docs/SPECIFICATION.md) for the full design contract
(goals, constraints, architecture, verification history).

## Architecture

Three containers, orchestrated by `docker-compose.yml`:

| Service | Role | Networks |
|---|---|---|
| `neo4j` | Local bolt-backed graph database (data on a named volume). | `db-net` (internal) |
| `llm-proxy` | LiteLLM proxy; production backend is Anthropic (or GitHub Models), routed via an OpenAI-compatible API. Only this service can reach the public internet. | `llm-net` (internal), `llm-egress-net` |
| `mcp` | The `neo4j-agent-memory` MCP server (`--profile extended`, 16 tools). Talks to both `neo4j` and `llm-proxy`; uses an in-process, offline sentence-transformers embedder. | `db-net`, `llm-net` |

Network segmentation is enforced so `neo4j` and `llm-proxy` can never reach each other —
only `mcp` is attached to both.

## Prerequisites

- Docker and Docker Compose
- An MCP-capable client (VS Code Copilot Chat, Claude, etc.) if you want to connect a client
  locally — see [`.vscode/mcp.json`](./.vscode/mcp.json) for a Neo4j Cypher dev-tool example
  and [`.mcp.json`](./.mcp.json) for the memory server itself.

## Setup

1. Copy the environment template and fill in secrets:

   ```bash
   cp .env.example .env
   ```

   At minimum set `NEO4J_PASSWORD` and `LITELLM_MASTER_KEY`. For local smoke testing, the
   default `NAM_LLM__MODEL=claude-mock` requires no LLM credential. For a real backend, set
   `NAM_LLM__MODEL=claude` and supply `ANTHROPIC_API_KEY` or `GITHUB_API_KEY` — these are
   consumed by `llm-proxy` **only** and must never be exposed to `mcp` or `neo4j`.

2. Build and start the stack:

   ```bash
   docker compose up -d --build
   ```

3. Wait for `neo4j` to report healthy, then `mcp` will start and listen on `:8080`.

## Connecting an MCP client

The `mcp` service exposes an HTTP MCP endpoint on `http://localhost:8080/mcp`. A ready-to-use
client template is provided at [`.mcp.json`](./.mcp.json) — point your MCP-compatible client
at this file, or copy its `mcpServers` entry into your client's own config.

## Verifying the stack

Run the smoke test, which stores a memory, reads it back directly from Neo4j via bolt, and
confirms semantic (paraphrase) search works:

```bash
python scripts/llm_smoke.py
```

## Configuration reference

All runtime configuration is environment-driven; see [`.env.example`](./.env.example) for
the full list of variables and which service consumes each one. Key groups:

- **Neo4j** (`NEO4J_*`) — consumed by `neo4j` and `mcp`.
- **Framework LLM wiring** (`NAM_LLM__*`, `NAM_EXTRACTION__*`, `OPENAI_*`) — consumed by
  `mcp`; routed through `llm-proxy`, never directly to a model provider.
- **Embedding** (`NAM_EMBEDDING__*`, `HF_HUB_OFFLINE`, `TRANSFORMERS_OFFLINE`) — local,
  offline sentence-transformers embedder baked into the `mcp` image.
- **LiteLLM proxy** (`LITELLM_MASTER_KEY`, `ANTHROPIC_API_KEY`, `GITHUB_API_KEY`) —
  consumed by `llm-proxy` only.

Never commit a real `.env` file or credentials.

## Development notes

- All Cypher and memory-graph logic lives inside the vendored `neo4j-agent-memory`
  framework (pinned in [`docker/mcp.Dockerfile`](./docker/mcp.Dockerfile)) — this repo does
  not embed bespoke Cypher.
- Keep the delta this repo owns thin and declarative (container images, compose, LiteLLM
  config, env) per Goal G6 in the specification; `scripts/check_thin_delta.sh` lints this.
- Design history and verified requirements are tracked in
  [`docs/SPECIFICATION.md`](./docs/SPECIFICATION.md) and
  [`docs/spec-loop-runs/`](./docs/spec-loop-runs/); process log in
  [`AGENTS.md`](./AGENTS.md).
