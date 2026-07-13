# mcp-n4j-memory — Technical Specification

> Status: **Draft v2**. This document is the contract the implementation must satisfy.
> It is written before code so the architecture and configuration are agreed up front.
> Update it as decisions change; it should never lag the code.
>
> **How this doc changes:** via the loop in [`SPEC_LOOP.md`](./SPEC_LOOP.md). Each
> implementation pass feeds defects and discoveries back here (tighten a §4 row, resolve or
> append to §10). Discoveries live nowhere else — no parallel design docs.
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
3. **`docker-compose.yml`** — authored at the repository root; defines the three services,
   two segmented networks, and the neo4j volume.
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
container command. [`.env.example`](../.env.example) is the authoritative template for every
variable above; real secrets never enter VCS.

## 8. Deployment

- The authored root `docker-compose.yml` defines:
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

## 9. Verification / testing — acceptance criteria

Because the engine is a third-party framework, our criteria target **wiring and isolation**,
not memory internals. Every criterion below is written to the evaluable, five-field standard
defined in [`SPEC_LOOP.md`](./SPEC_LOOP.md) ("Anatomy of a requirement"): each one states a
**Trigger**, **Preconditions**, **Expected observable outcome**, **Failure behaviour**, and
**Verification method**, and traces to a Constraint (`C*`) or Goal (`G*`). IDs are `AC-C*` /
`AC-G*`. Four underlying checks recur as verification methods and are named once here:

- **Config lint** — `docker compose config` validates and `litellm/config.yaml` parses.
- **Reachability probe** — a scripted TCP/HTTP connect attempt run *from inside* a named
  service container against another service's `host:port`.
- **Tool smoke sequence** — bring the stack up and drive the MCP transport through
  `memory_store_message` → `memory_search` → `memory_get_entity` → `graph_query`.
- **Offline-model load** — start the `mcp` container with egress blocked and load the embedder.

> **Slice status:** the `docker-compose` slice has statically verified compose authoring
> (AC-DC1/2/3: static parts of AC-C1..C5 plus AC-G4). Runtime probes for AC-C1,
> AC-C3, AC-C5, AC-C6, AC-C7, AC-G1, AC-G2, AC-G3, AC-G4, and AC-G5 remain
> pending in the future `stack-up` slice.

### 9.1 Constraint criteria

#### AC-C1 — Database is local and persistent
- **Trigger:** `docker compose up` starts the stack, then `neo4j` is restarted.
- **Preconditions:** A named docker volume is bound to Neo4j's data directory; no external DB
  URI is configured.
- **Expected observable outcome:** A node written before the restart is still queryable after
  it; the data path resolves to the named volume, not container-ephemeral storage.
- **Failure behaviour:** If the named volume is absent, `neo4j` fails to start (fail closed)
  rather than silently using ephemeral storage.
- **Verification method:** Config lint asserts the named volume + bolt (non-remote) URI;
  tool smoke sequence writes a node, `docker restart` neo4j, re-query returns the node.

#### AC-C2 — Every service is a container orchestrated by compose
- **Trigger:** `docker compose config` is evaluated and the stack is brought up.
- **Preconditions:** `docker-compose.yml` defines exactly the `neo4j`, `llm-proxy`, and `mcp`
  services.
- **Expected observable outcome:** All three services are present in the rendered config and
  reach running/healthy state; no service is expected to run outside a container.
- **Failure behaviour:** A missing or malformed service definition makes config lint fail and
  the affected service never starts.
- **Verification method:** Config lint; `docker compose ps` shows all three services up.

#### AC-C3 — MCP is linked to both the DB and the LLM proxy
- **Trigger:** A reachability probe is run from inside the `mcp` container.
- **Preconditions:** `mcp` is attached to both `db-net` and `llm-net`.
- **Expected observable outcome:** From `mcp`, both `neo4j:7687` and `llm-proxy:4000` accept
  the connection.
- **Failure behaviour:** If `mcp` is missing either network, the corresponding probe refuses
  to connect and the criterion fails.
- **Verification method:** Reachability probe from `mcp` to `neo4j:7687` and `llm-proxy:4000`.

#### AC-C4 — All services are firewalled (no default public exposure)
- **Trigger:** `docker compose config` is evaluated.
- **Preconditions:** Internal networks are declared `internal` where practical; only explicit
  local-dev host port mappings exist.
- **Expected observable outcome:** No service publishes to `0.0.0.0` beyond the documented
  local-dev ports (neo4j 7474/7687, mcp 8080, optional llm-proxy 4000); inter-service traffic
  stays on internal docker networks.
- **Failure behaviour:** An unintended `ports:` publish is surfaced by the config assertion and
  fails the check (fail closed) rather than shipping an open port.
- **Verification method:** Config lint asserts the published-port set equals the documented
  allow-list and that internal networks carry `internal: true`.

#### AC-C5 — LLM proxy and DB cannot reach each other
- **Trigger:** Reachability probes are run from `neo4j` and from `llm-proxy`.
- **Preconditions:** `neo4j` is only on `db-net`; `llm-proxy` is only on `llm-net`; the two
  networks share no members.
- **Expected observable outcome:** From `neo4j`, `llm-proxy:4000` is **unreachable**; from
  `llm-proxy`, `neo4j:7687` is **unreachable** (connection refused/timeout).
- **Failure behaviour:** If either probe connects, isolation is violated and the check fails
  the build (fail closed) — the stack must not be considered deployable.
- **Verification method:** Reachability probe `neo4j → llm-proxy:4000` and
  `llm-proxy → neo4j:7687`, both asserted to fail. (Satisfies **G4**; see AC-G4.)

#### AC-C6 — Backend LLM is Anthropic, reached only via the proxy
- **Trigger:** A framework operation that issues an LLM call (e.g. entity extraction during
  `memory_store_message`) runs.
- **Preconditions:** LiteLLM lists a single Anthropic-backed model; the framework's
  `--llm-api-base` points at `http://llm-proxy:4000/v1`; `ANTHROPIC_API_KEY` exists **only** in
  the `llm-proxy` environment.
- **Expected observable outcome:** The request appears in `llm-proxy` logs and is served by the
  Anthropic-backed model; the `mcp` container holds no Anthropic credential.
- **Failure behaviour:** With no valid virtual key or proxy route, the LLM call fails at the
  proxy; `mcp` can never fall back to calling Anthropic directly (it has no key or egress).
- **Verification method:** Config lint asserts a single Anthropic model + key sourced from env;
  environment assertion that `ANTHROPIC_API_KEY` is unset in `mcp`; tool smoke sequence, then
  confirm the LLM call is recorded in `llm-proxy` logs.

#### AC-C7 — Embedder is local and offline
- **Trigger:** The `mcp` container starts and loads the embedding model.
- **Preconditions:** The embedding model is baked into the `mcp` image at build time; the
  container is started with egress blocked.
- **Expected observable outcome:** The embedder loads and produces a 384-dim vector with no
  outbound network request.
- **Failure behaviour:** If the model is not present locally, load fails at startup rather than
  attempting a network download.
- **Verification method:** Offline-model load with egress blocked; assert successful load and a
  384-dim embedding.

### 9.2 Goal criteria

#### AC-G1 — All 16 extended MCP tools are exposed unchanged
- **Trigger:** An MCP client lists tools against the running `mcp` server.
- **Preconditions:** The server is launched with `--profile extended`.
- **Expected observable outcome:** The advertised tool set equals the 16 names in §3.2, with
  unchanged names.
- **Failure behaviour:** A missing/renamed tool means clients bind to a name that no longer
  exists; the check fails and the profile/flags must be corrected.
- **Verification method:** Tool smoke sequence preceded by an MCP `list_tools` call; assert the
  returned names equal the §3.2 set of 16.

#### AC-G2 — Memory persists in the local Neo4j graph (bolt)
- **Trigger:** `memory_store_message` is called, then Neo4j is queried directly over bolt.
- **Preconditions:** `--backend bolt` and the `NEO4J_*` wiring from §4 are in effect.
- **Expected observable outcome:** The stored content materialises as node(s) in the Neo4j
  graph, readable via a direct bolt query.
- **Failure behaviour:** A misconfigured backend surfaces as a store error or an empty
  direct-query result; the criterion fails.
- **Verification method:** Tool smoke sequence; assert the written node exists via a direct
  bolt `graph_query` / cypher read. (Supports **AC-C1**.)

#### AC-G3 — Every LLM call is routed through the proxy
- **Trigger:** Any framework LLM operation (extraction, preference detection, summarization)
  runs.
- **Preconditions:** Same as AC-C6 preconditions.
- **Expected observable outcome:** The call is observed in `llm-proxy` logs; no LLM traffic
  originates directly from `mcp` to the Anthropic API.
- **Failure behaviour:** `mcp` has no Anthropic key or egress, so a mis-route fails the call at
  the proxy rather than silently reaching Anthropic.
- **Verification method:** Same as **AC-C6** verification method (shared check).

#### AC-G4 — Network segmentation holds; only MCP bridges both nets
- **Trigger:** Reachability probes are run from all three services.
- **Preconditions:** Network membership per §3.1 (`neo4j`∈db-net, `llm-proxy`∈llm-net,
  `mcp`∈both).
- **Expected observable outcome:** `mcp` reaches both peers; `neo4j` and `llm-proxy` reach
  neither each other nor cross-net peers.
- **Failure behaviour:** Any cross-net reachability between `neo4j` and `llm-proxy` fails the
  build (fail closed).
- **Verification method:** Combined result of **AC-C3** (mcp→both) and **AC-C5** (db↔llm
  isolation) reachability probes.

#### AC-G5 — Local embedder feeds working vector search
- **Trigger:** Content is stored (embedded locally) and then retrieved via semantic search.
- **Preconditions:** AC-C7 holds; the Neo4j vector index is created by the framework.
- **Expected observable outcome:** `memory_search` returns semantically relevant results for a
  query that shares no exact tokens with the stored text, proving embeddings + vector index
  work end to end.
- **Failure behaviour:** If embedding or indexing is broken, semantic search returns no/random
  results and the criterion fails.
- **Verification method:** Offline-model load (AC-C7) plus tool smoke sequence extended with a
  paraphrase query asserting a relevant hit.

#### AC-G6 — The owned delta stays thin and declarative
- **Trigger:** The repository's owned files are reviewed against §3.3.
- **Preconditions:** The framework is consumed as a pinned dependency (NG2), not vendored.
- **Expected observable outcome:** The owned, non-generated delta is limited to the artifacts
  enumerated in §3.3 (mcp image, LiteLLM config, compose file, env, docs/smoke tests); no
  bespoke memory-engine module exists in the repo or the `mcp` image.
- **Failure behaviour:** Introduction of custom memory logic (Cypher for memory ops, entity
  extraction, embedding code) is treated as a spec violation to be removed or escalated to §10.
- **Verification method:** Scripted inventory asserting the owned source set ⊆ §3.3 artifacts
  and that no module imports/defines memory-engine logic. *(Partly declarative; see §10 — this
  is the weakest-to-mechanise criterion.)*

## 10. Open questions / future work

- **AC-G6 is only partly mechanisable.** "Thin and declarative delta" (G6) has no crisp
  observable outcome; its §9 verification currently relies on a scripted file-inventory proxy
  plus review. Decide whether to (a) accept the proxy check as sufficient, or (b) define a
  stricter, fully automatable rule (e.g. a lint that fails on any memory-engine import or
  Cypher-for-memory outside the framework).
- Pin the exact framework version and Anthropic model id (needs confirmation). Placeholders
  currently in code: `neo4j-agent-memory[mcp]==0.2.0` (`docker/mcp.Dockerfile`) and
  `anthropic/claude-3-5-sonnet-latest` (`litellm/config.yaml`) — both must be confirmed
  before merge.
- Optionally externalize the embedder into its own container on an `embed-net` if the `mcp`
  image size or CPU cost becomes a concern.
- Optional host-level egress rules so only `llm-proxy` can reach the internet (beyond docker
  network scoping).
