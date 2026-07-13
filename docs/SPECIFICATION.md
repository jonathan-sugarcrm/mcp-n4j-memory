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
- a **LiteLLM proxy** whose production backend is **Anthropic** and whose local smoke
  backend may be a mock LiteLLM response, for all LLM calls, and
- a **local, offline embedder** (the framework's in-process sentence-transformers model),

…and to enforce the network segmentation constraints below.

### Goals

- G1 — Expose the framework's **16 MCP endpoints** (`--profile extended`) unchanged, so
  existing clients bind to the same tool names.
- G2 — Persist all memory in a **local, dockerized Neo4j** knowledge graph (bolt backend).
- G3 — Route every framework LLM call (extraction, preference detection, observation
  summarization) through the **LiteLLM proxy**; production traffic is served by
  Anthropic behind the proxy, while local smoke tests may use a LiteLLM mock backend.
  The MCP server never calls Anthropic directly.
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
| C6 | Backend LLM is Anthropic in production | LiteLLM is configured with an Anthropic-backed production model and may also expose a mock-backed local smoke model; the framework is pointed at the proxy, never at Anthropic. |
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
   (MCP http/sse)                  │    mcp     │  neo4j-agent-memory[mcp,sentence-transformers]
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

1. **`mcp` image** (`docker/mcp.Dockerfile`) — installs
   `neo4j-agent-memory[mcp,sentence-transformers]` (pinned), bakes the embedding model for
   offline use, and launches the framework console script (`neo4j-agent-memory mcp serve`)
   with only accepted serve flags.
2. **`llm-proxy` config** (`litellm/config.yaml`) — one Anthropic-backed production
   model, key from env, plus an optional mock-backed local smoke model with no provider key.
3. **`docker-compose.yml`** — authored at the repository root; defines the three services,
   two segmented networks, and the neo4j volume.
4. **Configuration** — `.env` / compose env that points the framework at Neo4j via
   `NEO4J_*`, routes LLM calls to the proxy via `NAM_LLM__*` + `OPENAI_BASE_URL`, and
   selects the local embedder and offline embedding mode; Dockerfile `CMD` selects the
   transport and profile.
5. **Docs & smoke tests** — this spec, a README, and a scripted end-to-end check of the
   16 tools against the running stack.

## 4. Configuration mapping

The framework's console script (`neo4j-agent-memory`) is the integration surface; the MCP
server is launched with its `mcp serve` subcommand. For `neo4j-agent-memory==0.2.0`, the
accepted serve flags are `--uri`, `--user`, `--password`, `--database`, `--transport`,
`--host`, `--port`, `--profile`, `--session-strategy`, `--user-id`,
`--observation-threshold`, and `--no-auto-preferences`. LLM and embedding configuration is
not exposed as serve flags; it is read by the framework's `MemorySettings` from env.

| Concern | Framework flag / env | Value we set |
|---------|----------------------|--------------|
| Command | console script + subcommand | `neo4j-agent-memory mcp serve` |
| Neo4j | `NEO4J_URI`, `NEO4J_USER`, `NEO4J_PASSWORD`, `NEO4J_DATABASE` (also accepted as `--uri`, `--user`, `--password`, `--database`) | `bolt://neo4j:7687`, `neo4j`, `<secret>`, `neo4j` |
| Transport | Dockerfile `CMD` flags `--transport`, `--host`, `--port` | `http`, `0.0.0.0`, `8080` |
| HTTP path | FastMCP streamable HTTP default | `/mcp` |
| Tool profile | Dockerfile `CMD` flag `--profile` | `extended` (16 tools) |
| LLM provider/model | `NAM_LLM__PROVIDER`, `NAM_LLM__MODEL` | `openai`, `claude` for production or `claude-mock` for local smoke (OpenAI-compatible → LiteLLM) |
| LLM base URL | `OPENAI_BASE_URL` | `http://llm-proxy:4000/v1` |
| LLM key | `NAM_LLM__API_KEY` | LiteLLM virtual key |
| Embedder | `NAM_EMBEDDING__PROVIDER`, `NAM_EMBEDDING__MODEL` | `sentence_transformers`, `BAAI/bge-small-en-v1.5` (local, offline) |
| Embed dims | `NAM_EMBEDDING__DIMENSIONS` | `384` |
| Embedder offline mode | `HF_HUB_OFFLINE`, `TRANSFORMERS_OFFLINE` | `1`, `1` so the runtime loads the baked model cache and never reaches Hugging Face |
| Session strategy | `--session-strategy` | `per_conversation` (default) |

> **LLM routing:** we use the framework's OpenAI-compatible settings
> (`NAM_LLM__PROVIDER=openai`, `NAM_LLM__MODEL=<LiteLLM model name>`,
> `NAM_LLM__API_KEY=<virtual key>`) plus `OPENAI_BASE_URL=http://llm-proxy:4000/v1`,
> rather than configuring Anthropic directly in `mcp`. This guarantees the framework talks
> only to the proxy (satisfying C5/C6). For production, LiteLLM maps `claude` to the real
> Anthropic model and injects `ANTHROPIC_API_KEY`, which exists **only** in `llm-proxy`.
> For local `llm-smoke`, `NAM_LLM__MODEL=claude-mock` uses LiteLLM `mock_response`; the
> same proxy route and virtual key are used, but no provider secret is required.

The Anthropic API key lives **only** in `llm-proxy`'s environment. The `mcp` service holds a
LiteLLM virtual key, not the Anthropic key. At runtime the `mcp` service also sets
`HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1` so the baked `BAAI/bge-small-en-v1.5`
embedder cache is used with no Hugging Face network access.

## 5. LiteLLM proxy config

`litellm/config.yaml` (illustrative):

```yaml
model_list:
  - model_name: claude                         # production model name
    litellm_params:
      model: anthropic/claude-3-5-sonnet-latest
      api_key: os.environ/ANTHROPIC_API_KEY
  - model_name: claude-mock                    # local/offline llm-smoke model name
    litellm_params:
      model: openai/mock-local-smoke
      mock_response: >
        {\"entities\":[],\"relationships\":[],\"preferences\":[],\"summary\":\"local mock llm-smoke response\"}
general_settings:
  master_key: os.environ/LITELLM_MASTER_KEY    # the virtual key mcp presents
```

The proxy exposes an OpenAI-compatible `/v1/chat/completions`. Only the model(s) listed here
are reachable; there is no route from the proxy to Neo4j. Production uses the
Anthropic-backed `claude` entry and a real `ANTHROPIC_API_KEY` supplied only to
`llm-proxy`. The `llm-smoke` slice may set `NAM_LLM__MODEL=claude-mock` and use the
mock-backed entry, so no provider secret is needed. In both modes `mcp` presents only the
LiteLLM virtual key (`NAM_LLM__API_KEY == LITELLM_MASTER_KEY`) and never talks to
Anthropic directly, preserving C5/C6 isolation.

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
| `NAM_LLM__PROVIDER` | mcp | `openai` (OpenAI-compatible provider routed to LiteLLM). |
| `NAM_LLM__MODEL` | mcp | `claude` for production, or `claude-mock` for local `llm-smoke` (LiteLLM model name). |
| `NAM_LLM__API_KEY` | mcp | LiteLLM virtual key (== `LITELLM_MASTER_KEY`). |
| `OPENAI_BASE_URL` | mcp | `http://llm-proxy:4000/v1`. |
| `NAM_EMBEDDING__PROVIDER` | mcp | `sentence_transformers`. |
| `NAM_EMBEDDING__MODEL` | mcp | `BAAI/bge-small-en-v1.5`. |
| `NAM_EMBEDDING__DIMENSIONS` | mcp | `384`. |
| `HF_HUB_OFFLINE` | mcp | `1`; forces Hugging Face libraries to use the baked model cache at runtime. |
| `TRANSFORMERS_OFFLINE` | mcp | `1`; prevents transformer model downloads at runtime. |
| `MCP_TRANSPORT` / `MCP_HOST` / `MCP_PORT` | compose/env template only | Currently not consumed by `neo4j-agent-memory mcp serve`; transport/host/port are supplied by Dockerfile `CMD` flags. Retained only until cleanup removes the dead env wiring. |
| `LITELLM_MASTER_KEY` | llm-proxy | Virtual key it accepts. |
| `ANTHROPIC_API_KEY` | **llm-proxy only** | Real Anthropic credential. |

The current `mcp serve` CLI has no `--llm`, `--llm-api-base`, `--embedding`, or
`--backend` flags. LLM/embedder settings come from the nested `NAM_*` env vars above, using
`__` as the nested delimiter; the OpenAI-compatible base URL comes from `OPENAI_BASE_URL`.
[`.env.example`](../.env.example) is the authoritative template for every variable above;
real secrets never enter VCS.

## 8. Deployment

- The authored root `docker-compose.yml` defines:
  - `neo4j` — official image, `NEO4J_PLUGINS=["apoc"]`, named data volume, on `db-net`,
    healthcheck on bolt.
  - `llm-proxy` — LiteLLM image, mounts `litellm/config.yaml`, reads `ANTHROPIC_API_KEY`
    and `LITELLM_MASTER_KEY`, on `llm-net`; local smoke may use a mock-backed model that
    needs no provider credential.
  - `mcp` — built from `docker/mcp.Dockerfile`, on `db-net` + `llm-net`, `depends_on`
    neo4j (healthy) and llm-proxy, publishes `:8080`.
  - Networks `db-net` and `llm-net` declared `internal` where practical; the neo4j/mcp
    ports are host-mapped only for local dev.
- Startup order: neo4j healthy → llm-proxy up → mcp `neo4j-agent-memory mcp serve …`.
- Local dev without docker: run Neo4j + LiteLLM, export env,
  `uvx --from "neo4j-agent-memory[mcp,sentence-transformers]" neo4j-agent-memory mcp serve …`
  (documented in the README).

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

> **Slice status:** the `docker-compose` slice statically verified compose authoring
> (AC-DC1/2/3: static parts of AC-C1..C5 plus AC-G4). The `stack-up` runtime sub-slice
> runtime-verified **AC-C1** at the DB/container layer (named `neo4j-data` volume survives
> a Neo4j restart) and **AC-C5** plus the DB↔LLM-proxy half of **AC-G4** (both negative
> reachability probes fail). The `mcp-image-up` slice runtime-verified **AC-C3**, **AC-G1**,
> the `mcp`-bridge half of **AC-G4**, and the standalone **AC-C7** baked-embedder load
> (384-dim vector). The `llm-smoke` slice runtime-verified, from a clean state, **AC-C6/AC-G3**
> proxy routing/isolation via the LiteLLM `claude-mock` mock backend (mock completion recorded
> in `llm-proxy` logs; `mcp` holds no `ANTHROPIC_API_KEY` and has no direct Anthropic egress —
> both `llm-net`/`db-net` confirmed `internal: true`), the LLM-triggering persistence portion
> of **AC-G2** (`memory_store_message` via the mock route produced a node found by a direct
> Neo4j bolt read), and **AC-G5** semantic vector search (a token-disjoint paraphrase query
> returned the stored hit against the runtime offline embedder). All four are runtime-
> reproduced, not static-only. The positive proof that production traffic is served by real
> Anthropic remains deferred to a credentialed production environment with a real
> `ANTHROPIC_API_KEY` supplied only to `llm-proxy`.

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

#### AC-C6 — Backend LLM is reached only via the proxy
- **Trigger:** A framework operation that issues an LLM call (e.g. entity extraction during
  `memory_store_message`) runs.
- **Preconditions:** LiteLLM lists an Anthropic-backed production model and may list a
  mock-backed local smoke model; the framework's `NAM_LLM__PROVIDER=openai`,
  `NAM_LLM__MODEL=<LiteLLM model name>`, `NAM_LLM__API_KEY=<virtual key>`, and
  `OPENAI_BASE_URL=http://llm-proxy:4000/v1` point it at the proxy. `ANTHROPIC_API_KEY`
  exists **only** in the `llm-proxy` environment; local `llm-smoke` may use the mock model
  and therefore needs no provider key.
- **Expected observable outcome:** The request appears in `llm-proxy` logs and the `mcp`
  container holds no Anthropic credential. In local `llm-smoke`, the proxy may serve the
  request from LiteLLM `mock_response`; in production/keyed verification, the same route is
  served by the Anthropic-backed model.
- **Failure behaviour:** With no valid virtual key or proxy route, the LLM call fails at the
  proxy; `mcp` can never fall back to calling Anthropic directly (it has no key or egress).
- **Verification method:** Config lint asserts the production Anthropic model is key-sourced
  from env and the local mock model has no provider key; environment assertion that
  `ANTHROPIC_API_KEY` is unset in `mcp`; tool smoke sequence against the mock model, then
  confirm the LLM call is recorded in `llm-proxy` logs. A separate production-only check with
  a real `ANTHROPIC_API_KEY` confirms the Anthropic-backed positive path.

#### AC-C7 — Embedder is local and offline
- **Trigger:** The `mcp` container starts and loads the embedding model.
- **Preconditions:** The embedding model is baked into the `mcp` image at build time;
  `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1` are set in the running `mcp` service.
- **Expected observable outcome:** The embedder loads from the baked cache and produces a
  384-dim vector with no outbound network request.
- **Failure behaviour:** If the model is not present locally, load fails at startup rather than
  attempting a network download.
- **Verification method:** Offline-model load with egress blocked; assert successful runtime
  load from the baked cache and a 384-dim embedding.

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
- **Preconditions:** The `NEO4J_*` wiring from §4 is in effect, pointing the framework at the
  local Neo4j bolt endpoint; the LLM-triggering store path is routed through LiteLLM and may
  use the mock model for local smoke.
- **Expected observable outcome:** The stored content materialises as node(s) in the Neo4j
  graph, readable via a direct bolt query.
- **Failure behaviour:** A misconfigured backend surfaces as a store error or an empty
  direct-query result; the criterion fails.
- **Verification method:** Tool smoke sequence using `memory_store_message` against the mock
  LLM model; assert the written node exists via a direct bolt `graph_query` / cypher read.
  The check must also mechanically exercise the failure branch, not merely assert it in
  prose: rerun with Neo4j wiring broken (e.g. `NEO4J_URI` pointed at an unreachable/wrong
  port, or the correct port with a wrong password) and assert that `memory_store_message`
  returns an error, or — if the tool call itself does not surface one — that a direct bolt
  read for the same unique marker finds no matching node. A verification pass that never
  runs this broken-wiring case is not sufficient evidence for this criterion. (Supports
  **AC-C1**.)

#### AC-G3 — Every LLM call is routed through the proxy
- **Trigger:** Any framework LLM operation (extraction, preference detection, summarization)
  runs.
- **Preconditions:** Same as AC-C6 preconditions; local smoke may use the mock-backed LiteLLM
  model instead of the Anthropic-backed production model.
- **Expected observable outcome:** The call is observed in `llm-proxy` logs; no LLM traffic
  originates directly from `mcp` to the Anthropic API. Local smoke proves routing/isolation;
  a keyed production environment separately proves the real Anthropic-backed response path.
- **Failure behaviour:** `mcp` has no Anthropic key or egress, so a mis-route fails the call at
  the proxy rather than silently reaching Anthropic.
- **Verification method:** Same as **AC-C6** mock-friendly routing/isolation verification
  method. The real-Anthropic positive path is production-only and deferred until a real key is
  supplied to `llm-proxy`.

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
- **Preconditions:** Runtime AC-C7 holds: the `mcp` service has the baked
  `BAAI/bge-small-en-v1.5` model and sets `HF_HUB_OFFLINE=1` and
  `TRANSFORMERS_OFFLINE=1`; the Neo4j vector index is created by the framework.
- **Expected observable outcome:** `memory_search` returns semantically relevant results for a
  query that shares no exact tokens with the stored text, proving embeddings + vector index
  work end to end.
- **Failure behaviour:** If embedding or indexing is broken, semantic search returns no/random
  results and the criterion fails.
- **Verification method:** Tool smoke sequence stores content, asserts the running server can
  create 384-dim embeddings from the offline baked model, then runs `memory_search` with a
  paraphrase query sharing no exact tokens with the stored text and asserts a relevant hit.

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
  currently in code: `neo4j-agent-memory[mcp,sentence-transformers]==0.2.0`
  (`docker/mcp.Dockerfile`) and
  `anthropic/claude-3-5-sonnet-latest` (`litellm/config.yaml`) — both must be confirmed
  before merge.
- **Real-Anthropic positive path remains deferred to production.** `llm-smoke` runtime-
  verified AC-C6/AC-G3 routing/isolation and the LLM-triggering portions of AC-G2/AC-G5 using
  the LiteLLM `claude-mock` mock backend (see §9 slice-status and "Resolved items" below). The
  one remaining gap is proving the production `claude` model actually serves a real
  Anthropic-backed completion; that requires a real `ANTHROPIC_API_KEY` supplied only to
  `llm-proxy` and is deferred to a credentialed production-like environment before merge.
- **Cleanup dead MCP transport env:** `docker-compose.yml` and `.env.example` still set
  `MCP_TRANSPORT`, `MCP_HOST`, and `MCP_PORT`, but the current `neo4j-agent-memory mcp serve`
  CLI does not read those env vars; Dockerfile `CMD` flags supply transport/host/port.
  Remove the dead env wiring or introduce an explicit wrapper if env-driven transport
  remains desired.
- Optionally externalize the embedder into its own container on an `embed-net` if the `mcp`
  image size or CPU cost becomes a concern.
- Optional host-level egress rules so only `llm-proxy` can reach the internet (beyond docker
  network scoping).

### Resolved items

- **Resolved in `llm-smoke`: AC-C6/AC-G3 proxy routing/isolation and the LLM-triggering
  portions of AC-G2/AC-G5 are runtime-verified.** LiteLLM's `claude-mock` `mock_response`
  model gives a compatible local backend with no provider secret in `mcp`; a clean-state
  rerun (`docker compose down -v` → fresh `up`) reproduced the mock completion, the absent
  `ANTHROPIC_API_KEY`, the blocked direct Anthropic egress, the persisted Neo4j node, and the
  token-disjoint paraphrase search hit. See §9 slice-status. Only the real-Anthropic positive
  path remains open (bullet above).
- **Resolved in `llm-smoke`: AC-G2's Verification method now forces the failure branch.**
  Verification found the prior wording only asserted the failure behaviour in prose; §9.2
  AC-G2 now requires a rerun with broken Neo4j wiring (wrong port/password) asserting
  `memory_store_message` errors or the direct bolt read finds no node, so a passing check can
  no longer mask silently-broken persistence (`weak_verification` defect, routed to gate 1 /
  §9 Verification method).
- **Resolved in `mcp-image-up`: deferred `mcp` image ENTRYPOINT defect.** The image now uses
  `ENTRYPOINT ["neo4j-agent-memory", "mcp", "serve"]`, installs the
  `sentence-transformers` extra needed by the baked embedder, and starts with only accepted
  serve flags (`--transport`, `--host`, `--port`, `--profile`). The obsolete
  `--backend`, `--llm`, `--llm-api-base`, and `--embedding` flags are no longer part of the
  durable spec.
