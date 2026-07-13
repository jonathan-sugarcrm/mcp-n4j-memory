# mcp-n4j-memory — Technical Specification

> Status: **Draft v2**. This document is the contract the implementation must satisfy.
> It is written before code so the architecture and configuration are agreed up front.
> Update it as decisions change; it should never lag the code.
>
> **v2 change:** we **leverage the [`neo4j-labs/agent-memory`](https://github.com/neo4j-labs/agent-memory)
> framework** to do the heavy lifting instead of writing our own memory engine. This project
> is therefore a **deployment + configuration** layer, not a from-scratch reimplementation.

## 1. Purpose

`mcp-n4j-memory` packages the `neo4j-agent-memory` framework into a **self-hosted,
dockerized agent-memory system** with strict network isolation. It exposes the framework's
persistent, graph-native memory over the **Model Context Protocol (MCP)** so MCP clients
(Copilot, Claude, Cursor, other agents) can store and recall long-lived "memories" as a
Neo4j knowledge graph.

We do **not** reimplement the MCP tools, the POLE+O graph model, entity extraction, entity
resolution, or embeddings — the framework already ships all of these. Our job is to wire the
framework to:

- a **local, dockerized Neo4j** (self-hosted **bolt** backend),
- a **LiteLLM proxy** whose only backend is **Anthropic**, for all LLM calls, and
- a **local, offline embedder** (the framework's in-process sentence-transformers model),

…and to enforce the network segmentation constraints below.

### Goals

- G1 — Expose the framework's **16 MCP endpoints** (`--profile extended`) unchanged, so
  existing clients bind to the same tool names.
- G2 — Persist all memory in a **local, dockerized Neo4j** knowledge graph (bolt backend).
- G3 — Route every framework LLM call (extraction, preference detection, observation
  summarization) through the **LiteLLM proxy → Anthropic**; the MCP server never calls
  Anthropic directly.
- G4 — Enforce **network segmentation**: the DB and the LLM proxy can never reach each
  other; only the MCP server may reach both.
- G5 — Produce embeddings from a **local, offline embedder** (no external embedding
  provider), feeding the framework's Neo4j vector index for semantic search.
- G6 — Keep the delta we own **thin and declarative**: container images, a compose file,
  a LiteLLM config, and env — no bespoke memory logic.

### Non-goals (v1)

- NG1 — The hosted **NAMS** backend and the 4 NAMS-only "platinum" tools (we use `bolt`).
- NG2 — Forking or vendoring the framework. We consume it as a pinned dependency.
- NG3 — Multi-tenant scoping, background enrichment (Wikipedia/Diffbot), geospatial,
  GPU inference (v1 embedder targets CPU with a small 384-dim model).

## 2. Constraints (from the requester)

| # | Constraint | How the design meets it |
|---|-----------|--------------------------|
| C1 | Local database | Neo4j runs as a local docker container; data on a named volume. |
| C2 | Dockerized | Every service (neo4j, llm-proxy, mcp) is a container orchestrated by `docker-compose`. |
| C3 | MCP has links to DB **and** the LLM proxy | The `mcp` service is attached to both the `db-net` and `llm-net` docker networks. |
| C4 | All services firewalled | No service publishes to the public internet by default; only explicitly mapped host ports for local dev. Inter-service traffic is confined to internal docker networks. |
| C5 | LLM proxy firewalled from DB and vice versa | `neo4j` is only on `db-net`; `llm-proxy` is only on `llm-net`. They share **no** network and cannot route to each other. |
| C6 | Backend LLM is Anthropic | LiteLLM is configured with a single Anthropic-backed model; the framework is pointed at the proxy, never at Anthropic. |
| C7 | Local embedder | The framework's **in-process** sentence-transformers embedder (offline model baked into the `mcp` image); no embedding traffic leaves the host. |

## 3. Architecture

### 3.1 Runtime topology

```
                 ┌──────────────────────── db-net (internal) ─────────────┐
                 │                                                          │
   host :7474/  ─┼─▶  neo4j  ◀── bolt ──┐                                   │
   :7687         │   (memory graph +     │                                  │
                 │    vector index)      │                                  │
                 └───────────────────────┼──────────────────────────────────┘
                                         │
   host :8080  ─────────────────▶ ┌──────┴─────┐
   (MCP http/sse)                  │    mcp     │  neo4j-agent-memory[mcp]
                                   │  server    │  + in-process embedder (offline)
                                   └──────┬─────┘
                 ┌───────────────────────┼──────────────────────────────────┐
                 │                        │                                  │
   host :4000   ─┼─▶  llm-proxy  ◀── http ┘        ── https ──▶  Anthropic   │
   (optional)    │   (LiteLLM)                                    API        │
                 └──────────────────── llm-net (internal) ──────────────────┘
```

- `neo4j` ∈ {`db-net`}
- `llm-proxy` ∈ {`llm-net`}
- `mcp` ∈ {`db-net`, `llm-net`}  ← the only bridge
- `neo4j` ∩ `llm-proxy` networks = ∅ → satisfies **C5**.

The embedder runs **inside** the `mcp` process (sentence-transformers), so embedding never
crosses a network boundary. Only `llm-proxy` has an egress route to the public Anthropic
API; `neo4j` and `mcp` have no reason to reach the internet, and the embedder's model is
baked into the `mcp` image at build time so it runs fully offline.

### 3.2 What the framework provides (we consume, not build)

- The FastMCP server and the **16-tool** extended surface (`memory_search`,
  `memory_get_context`, `memory_store_message`, `memory_add_entity`, `memory_add_preference`,
  `memory_add_fact`, `memory_get_conversation`, `memory_list_sessions`, `memory_get_entity`,
  `memory_export_graph`, `memory_create_relationship`, `memory_start_trace`,
  `memory_record_step`, `memory_complete_trace`, `memory_get_observations`, `graph_query`).
- The POLE+O graph schema, constraints, full-text **and** vector indexes.
- Multi-stage entity/relationship extraction, preference detection, entity resolution,
  observation/reflection summarization.
- The bolt storage layer (`MemoryClient` + `MemoryIntegration`) and the read-only
  `graph_query` guard.

### 3.3 What we own (the thin delta)

1. **`mcp` image** (`docker/mcp.Dockerfile`) — installs `neo4j-agent-memory[mcp]` (pinned),
   bakes the embedding model for offline use, and launches `mcp serve` with the right flags.
2. **`llm-proxy` config** (`litellm/config.yaml`) — one Anthropic-backed model, key from env.
3. **`docker-compose.yml`** — the three services, two segmented networks, the neo4j volume.
4. **Configuration** — `.env` / compose env that pins backend=bolt, points the framework's
   LLM at the proxy, and selects the local embedder + profile.
5. **Docs & smoke tests** — this spec, a README, and a scripted end-to-end check of the
   16 tools against the running stack.

## 4. Configuration mapping

The framework's `mcp serve` CLI (and env vars) is the integration surface. Key wiring:

| Concern | Framework flag / env | Value we set |
|---------|----------------------|--------------|
| Backend | `--backend` / `NAM_BACKEND` | `bolt` |
| Neo4j | `--uri`/`NEO4J_URI`, `--user`/`NEO4J_USER`, `--password`/`NEO4J_PASSWORD`, `--database`/`NEO4J_DATABASE` | `bolt://neo4j:7687`, `neo4j`, `<secret>`, `neo4j` |
| Transport | `--transport`, `--host`, `--port` | `http` (or `sse`), `0.0.0.0`, `8080` |
| Tool profile | `--profile` | `extended` (16 tools) |
| LLM provider | `--llm` / `NAM_LLM` | `openai/claude` (OpenAI-compatible → LiteLLM) |
| LLM base URL | `--llm-api-base` | `http://llm-proxy:4000/v1` |
| LLM key | `--llm-api-key` / `NAM_LLM_API_KEY` | LiteLLM virtual key |
| Embedder | `--embedding` / `NAM_EMBEDDING` | `BAAI/bge-small-en-v1.5` (local, offline) |
| Embed dims | `--embedding-dimensions` | `384` (only if not in the defaults table) |
| Session strategy | `--session-strategy` | `per_conversation` (default) |

> **LLM routing:** we use an **OpenAI-compatible** provider string (`openai/claude`) plus
> `--llm-api-base` pointing at LiteLLM, rather than `anthropic/...` directly. This guarantees
> the framework talks only to the proxy (satisfying C5/C6); LiteLLM maps the `claude` model
> to the real Anthropic model and injects `ANTHROPIC_API_KEY`, which exists **only** in the
> `llm-proxy` service.

The Anthropic API key lives **only** in `llm-proxy`'s environment. The `mcp` service holds a
LiteLLM virtual key, not the Anthropic key.

## 5. LiteLLM proxy config

`litellm/config.yaml` (illustrative):

```yaml
model_list:
  - model_name: claude                       # the name the framework requests
    litellm_params:
      model: anthropic/claude-3-5-sonnet-latest
      api_key: os.environ/ANTHROPIC_API_KEY
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY   # the virtual key mcp presents
```

The proxy exposes an OpenAI-compatible `/v1/chat/completions`. Only the model(s) listed here
are reachable; there is no route from the proxy to Neo4j.

## 6. Data & endpoint surface

Owned by the framework; see its docs and `docs/reference-notes.md` for a captured snapshot
of the 16 tool signatures. We do not redefine them. The POLE+O taxonomy (Person, Object,
Location, Event, Organization) and `UPPER_SNAKE_CASE` relationship types apply as shipped.

## 7. Configuration (env vars, our compose)

| Var | Consumed by | Purpose |
|-----|-------------|---------|
| `NEO4J_PASSWORD` | neo4j, mcp | DB auth (required). |
| `NEO4J_URI` | mcp | `bolt://neo4j:7687`. |
| `NEO4J_USER` / `NEO4J_DATABASE` | mcp | `neo4j` / `neo4j`. |
| `NAM_LLM` | mcp | `openai/claude`. |
| `NAM_LLM_API_KEY` | mcp | LiteLLM virtual key (== `LITELLM_MASTER_KEY`). |
| `NAM_EMBEDDING` | mcp | `BAAI/bge-small-en-v1.5`. |
| `MCP_TRANSPORT` / `MCP_HOST` / `MCP_PORT` | mcp | `http` / `0.0.0.0` / `8080` (passed to `mcp serve`). |
| `LITELLM_MASTER_KEY` | llm-proxy | Virtual key it accepts. |
| `ANTHROPIC_API_KEY` | **llm-proxy only** | Real Anthropic credential. |

`--llm-api-base` has no env var in the framework CLI, so it is passed as a flag in the `mcp`
container command. A `.env.example` documents every variable; real secrets never enter VCS.

## 8. Deployment

- `docker-compose.yml`:
  - `neo4j` — official image, `NEO4J_PLUGINS=["apoc"]`, named data volume, on `db-net`,
    healthcheck on bolt.
  - `llm-proxy` — LiteLLM image, mounts `litellm/config.yaml`, reads `ANTHROPIC_API_KEY`
    and `LITELLM_MASTER_KEY`, on `llm-net`.
  - `mcp` — built from `docker/mcp.Dockerfile`, on `db-net` + `llm-net`, `depends_on`
    neo4j (healthy) and llm-proxy, publishes `:8080`.
  - Networks `db-net` and `llm-net` declared `internal` where practical; the neo4j/mcp
    ports are host-mapped only for local dev.
- Startup order: neo4j healthy → llm-proxy up → mcp `mcp serve …`.
- Local dev without docker: run Neo4j + LiteLLM, export env, `uvx "neo4j-agent-memory[mcp]"
  mcp serve …` (documented in the README).

## 9. Verification / testing

Because the engine is a third-party framework, our tests target **wiring and isolation**,
not memory internals:

- **Config lint** — compose config validates; LiteLLM config parses.
- **Network isolation assertions** — from `mcp`, both `neo4j:7687` and `llm-proxy:4000` are
  reachable; from `neo4j`, `llm-proxy` is **unreachable**, and vice versa (scripted checks).
- **Smoke test** — bring the stack up; exercise a representative subset of the 16 tools over
  the MCP transport (e.g. `memory_store_message` → `memory_search` → `memory_get_entity` →
  `graph_query`) and assert data lands in Neo4j and embeddings/vector search work.
- **Offline embedder check** — the embedding model loads with no network access.

## 10. Open questions / future work

- Pin the exact framework version and Anthropic model id (needs confirmation).
- Optionally externalize the embedder into its own container on an `embed-net` if the `mcp`
  image size or CPU cost becomes a concern.
- Optional host-level egress rules so only `llm-proxy` can reach the internet (beyond docker
  network scoping).
