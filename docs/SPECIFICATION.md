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
API — via a dedicated, non-internal `llm-egress-net` network attached solely to `llm-proxy`
(`db-net`/`llm-net` remain `internal: true`; `mcp`/`neo4j` gain no new network attachment;
confirmed by `prod-anthropic-verify`, R4) — and `neo4j` and `mcp` have no reason to reach the
internet; the embedder's model is baked into the `mcp` image at build time so it runs fully
offline.

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

`litellm/config.yaml` (illustrative — the underlying Anthropic model id is a floating fact,
re-verified per run, not a pinned literal; see §10 open items):

```yaml
model_list:
  - model_name: claude                         # production model name
    litellm_params:
      model: anthropic/claude-sonnet-4-5       # id re-verified per run; was claude-3-5-sonnet-latest (retired)
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
> reproduced, not static-only. The `prod-anthropic-verify` slice runtime-verified, against a
> **real** Anthropic-backed credential, the routing/isolation half of **AC-C6/AC-G3**: the
> `llm-proxy`-only egress grant (a new non-internal `llm-egress-net` network attached solely
> to `llm-proxy`; `db-net`/`llm-net` unchanged, still `internal: true`) lets `llm-proxy` reach
> `api.anthropic.com:443` while `mcp` and `neo4j` remain unreachable to it (DNS fails from
> both); `mcp` holds no `ANTHROPIC_API_KEY` in any rebuild; and genuine, non-mock Anthropic
> server responses (real `request_id`s, zero occurrences of the mock string) prove the real
> credential path was reached end-to-end through the proxy. The one remaining gap is the
> **positive completion** itself: every triggered call returned a genuine Anthropic error
> (`404` pre-fix, `429 rate_limit_error` post-fix) rather than a `200`. The confirmed root
> cause is that the credential available for this verification (`~/.secrets/anthropic.env`)
> is a **claude.ai / Claude Code OAuth token, not an Anthropic API key** — LiteLLM's
> `anthropic/` provider authenticates to `api.anthropic.com` with an API key
> (`sk-ant-api…`) and cannot use an OAuth bearer token, so a real positive completion cannot
> succeed with this credential regardless of egress/routing correctness. AC-C6/AC-G3's real
> Anthropic positive path therefore remains **unverified/deferred**, now pending a genuine
> `sk-ant-api…` Anthropic API key supplied only to `llm-proxy` (not merely "a credentialed
> production environment" as previously stated). The `github-models-llm-backend` slice
> closed this gap generically (not Anthropic-specifically): it retargeted the `claude`
> model_name to **GitHub Models** (LiteLLM `model: openai/gpt-4o-mini`, explicit
> `api_base: https://models.github.ai/inference`, `api_key: os.environ/GITHUB_API_KEY`) — a
> supported, OpenAI-compatible provider reachable with an ordinary GitHub PAT rather than a
> scarce Anthropic API key — and, from a clean state, runtime-verified a genuine `200`
> positive completion end-to-end: a real (non-mock) LiteLLM response with a live `id`/`usage`
> for a direct proxy call, **and** a real `memory_store_message` extraction whose resulting
> graph nodes (`MENTIONS` edges to distinct `Entity`/`Event`/`Location`/`Object`/`Time`
> nodes) are genuinely derived content, not the verbatim stored sentence or the
> `claude-mock` string. The routing/isolation guarantees already proven mock-only in
> `llm-smoke` and with a real-but-non-functional Anthropic credential in
> `prod-anthropic-verify` are unchanged and now proven **with a real, completing backend**:
> `mcp` and `neo4j` hold no GitHub credential and cannot resolve/reach `models.github.ai`
> (DNS failure, `internal: true` `db-net`/`llm-net`), while `llm-proxy` — the only service
> attached to the pre-existing `llm-egress-net` — reaches it over TCP 443; no new network was
> added. The previous Anthropic entry is preserved, renamed `claude-anthropic`, alongside the
> unchanged `claude-mock`. **The real-*Anthropic*-specific positive path remains separately
> deferred** (still needs a genuine `sk-ant-api…` key; see AC-C6/AC-G3 below and §10) — only
> the *general* "does this architecture support a real, completing LLM backend end-to-end"
> question is now closed, via GitHub Models. A confirmed **new constraint**: LiteLLM's bare
> `github/<model>` provider prefix does **not** route to `models.github.ai` — it silently
> proxies to `models.inference.ai.azure.com` (GitHub Models' underlying Azure AI Inference
> backend), which still returns a genuine completion but fails any check asserting the
> `models.github.ai` host specifically. `openai/<model>` + explicit `api_base` is required to
> hit `models.github.ai` verbatim; this is now the shipped configuration.

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
- **Verification method:** Config lint asserts the production model is key-sourced from env
  and the local mock model has no provider key; environment assertion that the provider
  credential (`ANTHROPIC_API_KEY` / `GITHUB_API_KEY`, depending on which production model
  is active) is unset in `mcp`; tool smoke sequence against the mock model, then confirm the
  LLM call is recorded in `llm-proxy` logs. A separate production-only check with a real
  provider credential confirms **the configured LLM provider's** positive path (e.g. GitHub
  Models or Anthropic) — `github-models-llm-backend` closed this for **GitHub Models**: a
  real `GITHUB_API_KEY` (ordinary GitHub PAT) supplied only to `llm-proxy` produced a genuine
  `200` completion, confirmed via a `models.github.ai` upstream log line, with `mcp`/`neo4j`
  independently confirmed to hold no GitHub credential and to be unable to resolve
  `models.github.ai`. The real-**Anthropic** positive path specifically remains deferred:
  it **requires a genuine Anthropic API key** (`sk-ant-api…`, issued for API/console use); a
  claude.ai / Claude Code OAuth bearer token is not accepted by LiteLLM's `anthropic/`
  provider and will not produce a positive completion regardless of routing/egress
  correctness (`prod-anthropic-verify`, R1: confirmed via genuine Anthropic `429`/`404` error
  responses, not a credential-format or routing defect). **New constraint:** LiteLLM's bare
  `github/<model>` provider prefix does not route to `models.github.ai` — it silently proxies
  to `models.inference.ai.azure.com`; use `openai/<model>` with an explicit `api_base` to
  reach `models.github.ai` verbatim (`github-models-llm-backend`).

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
- **Failure behaviour:** `mcp` has no provider key or egress for any production model, so a
  mis-route fails the call at the proxy rather than silently reaching a real provider
  directly.
- **Verification method:** Same as **AC-C6** mock-friendly routing/isolation verification
  method. `github-models-llm-backend` closed the general real-completion path via **GitHub
  Models** (real `200`, real extraction, `mcp`/`neo4j` confirmed credential-less and
  unreachable to `models.github.ai`). The real-**Anthropic** positive path specifically
  remains production-only and deferred until a real Anthropic **API key** (`sk-ant-api…`) —
  not an OAuth token — is supplied to `llm-proxy`; `prod-anthropic-verify` confirmed
  routing/isolation with a real credential but could not close the positive-completion path
  because the only credential available was a claude.ai OAuth token, which Anthropic's API
  rejects for this use.

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
- **Verification method:** Run `bash scripts/check_thin_delta.sh` from the repository root.
  The script mechanises the two checks that can be made evaluable: (a) a file-inventory check
  that every `git ls-files`-tracked path matches the §3.3 owned-delta allow-list, and (b) a
  pattern lint that fails on any tracked `*.py`/`*.ts`/`*.js`/`*.go` file containing a
  memory-engine driver reference (`import neo4j` / `from neo4j` / `GraphDatabase`) or a
  Cypher clause opener for a memory operation (`MATCH (`, `MERGE (`, `CREATE (`), exact-path
  allow-listing the one legitimate exception, `scripts/llm_smoke.py` (its direct-bolt-read
  verification step for R2). Exit `0` = the thin-delta guarantee holds; non-zero names the
  offending file(s)/line(s) and is a spec violation per the failure behaviour above. The
  lint scans `git ls-files`, so an untracked/unstaged file cannot be caught by it — this is
  the check's deliberate scan boundary, not a gap in the criterion. Manual review remains the
  fallback for the residual judgement the lint cannot mechanise (e.g. non-Python/TS/JS/Go
  memory logic, or a pattern match hidden in a comment/string). See
  `docs/spec-loop-runs/acg6-lint/` for the mechanised-check verification pass.

## 10. Open questions / future work

- The Anthropic model id is treated as a **floating fact, re-verified per run** (see
  "Resolved items" below), not a fixed literal — `litellm/config.yaml` currently pins
  `anthropic/claude-sonnet-4-5`; this policy remains current and is unaffected by the
  framework-version confirmation (now resolved, see below).
- **Real-*Anthropic*-specific positive completion remains deferred** (narrowed scope — the
  general "real, completing LLM backend end-to-end" question is now **resolved**, see
  "Resolved items" below), now with a precise, confirmed blocker. `prod-anthropic-verify`
  runtime-verified, with a **real** Anthropic credential, that `llm-proxy` (and only
  `llm-proxy`) can reach `api.anthropic.com`, that `mcp` holds no Anthropic key and cannot
  reach Anthropic even while a real call is in flight, and that the real credential path was
  genuinely exercised (non-mock, Anthropic-issued `request_id`s). The one still-open item is
  R1's literal positive-completion outcome: **the credential at `~/.secrets/anthropic.env` is
  a claude.ai / Claude Code OAuth token, not an Anthropic API key**, and LiteLLM's
  `anthropic/` provider cannot authenticate to `api.anthropic.com` with an OAuth bearer
  token — only a real `sk-ant-api…` key will do. This is blocked on supplying such a key to
  `llm-proxy` only; it is not a routing, isolation, or rate-limit defect in this repo's
  configuration. Lowest priority now that GitHub Models provides a working, supported
  production backend — close only opportunistically, if/when a real `sk-ant-api…` key
  becomes available.
- Optionally externalize the embedder into its own container on an `embed-net` if the `mcp`
  image size or CPU cost becomes a concern.
- Optional host-level egress rules so only `llm-proxy` can reach the internet (beyond docker
  network scoping — `llm-egress-net` now provides the docker-network-level version of this).
- **New constraint: LiteLLM's `github/<model>` provider prefix does not reach
  `models.github.ai`.** Discovered/confirmed in `github-models-llm-backend`: LiteLLM's
  documented `github/<model>` provider prefix silently proxies requests to
  `https://models.inference.ai.azure.com` (GitHub Models' underlying Azure AI Inference
  backend), not `https://models.github.ai`. It still returns a genuine, non-mock completion,
  so a check that only asserts "got a real `200`" would pass on the wrong upstream host — a
  check that must assert `models.github.ai` specifically (as AC-C6/AC-G3 do) will fail
  against `github/<model>`. The shipped, verified configuration instead uses
  `model: openai/gpt-4o-mini` with an explicit `api_base: https://models.github.ai/inference`,
  which does hit `models.github.ai` verbatim. Anyone reconfiguring `litellm/config.yaml` for
  GitHub Models must use the explicit-`api_base` form, not the `github/` prefix, or silently
  lose the "only `models.github.ai`" host guarantee.
- **SECURITY: the `github-models-llm-backend` verification pass used a broad `gh`-CLI OAuth
  token (`GH_TOKEN`) as `GITHUB_API_KEY`, supplied only to the shell/`llm-proxy` and never
  persisted.** This was acceptable for a one-off local verification pass but is **not**
  appropriate for any persistent or production deployment: a broad token can do far more than
  call GitHub Models. Any lasting configuration must instead use a **fine-grained GitHub PAT
  scoped to `models: read` only**, supplied to `llm-proxy`'s environment alone (never to
  `mcp`/`neo4j`), mirroring the existing `ANTHROPIC_API_KEY` isolation pattern.
### Resolved items

- **Resolved in `pin-framework-version` (CONFIRM-NO-CHANGE): the
  `neo4j-agent-memory[mcp,sentence-transformers,openai]==0.2.0` pin in
  `docker/mcp.Dockerfile` (line 13) is confirmed correct; no code change was needed.**
  A real PyPI dependency-resolution dry run (`pip install --dry-run --target=<scratch>
  "neo4j-agent-memory[mcp,sentence-transformers,openai]==0.2.0"`) exits `0` and resolves
  cleanly to `neo4j-agent-memory-0.2.0` plus all three extras' dependencies (`fastmcp`,
  `sentence-transformers`, `openai`; ~140 packages, no conflicts); the same command
  against a non-existent version (`==99.0.0`) correctly fails (`ERROR: Could not find a
  version that satisfies the requirement`, listing the real available versions `0.0.1`
  through `0.5.0`), proving the check has real discriminating power. Both Implementation
  and Verification independently reproduced this from a clean state. **Decision of
  record (Class 3):** `0.2.0` is not the newest release on PyPI (latest is `0.5.0`,
  published ~26 days later), but upgrading is deliberately deferred to a separate,
  dedicated future slice — a framework-version bump is a one-way-door-adjacent change
  in blast radius (potential CLI flag / env-var / MCP tool-behaviour drift across the
  vendored `neo4j-agent-memory` surface this repo depends on) and not what this slice's
  "confirm the pin" ask covers. `docker/mcp.Dockerfile` was left byte-for-byte
  unchanged (`git diff` empty, independently confirmed by Implementation and
  Verification). Authored by Reconciliation (gate 6); see
  `docs/spec-loop-runs/pin-framework-version/reconciliation.handoff.md`.
- **Resolved in `acg6-lint`: AC-G6's mechanisable portion is now enforced by an automated lint.** Chose option (b) (a stricter automatable rule) over merely accepting the file-inventory-plus-review proxy. Added `scripts/check_thin_delta.sh` (pure bash + git + grep, no new deps): Check A asserts every `git ls-files`-tracked path matches the §3.3 owned-delta allow-list; Check B fails on any tracked `*.py`/`*.ts`/`*.js`/`*.go` file containing a memory-engine driver reference (`import neo4j` / `from neo4j` / `GraphDatabase`) or a Cypher clause opener (`MATCH (` / `MERGE (` / `CREATE (`), exact-path allow-listing the one legitimate exception `scripts/llm_smoke.py`. Exit `0` = clean; non-zero names the offending file/line. Independently verified from a clean state: happy path exits `0` (54 files scanned); a planted violation — including one disguised under the allow-listed `docs/` prefix — exits non-zero and names the file; `scripts/llm_smoke.py` is correctly suppressed by the allow-list (the patterns DO match there on a raw grep, so it is suppressed, not accidentally non-matching). AC-G6's Verification method (§9.2) now runs this lint. **Known limitations (recorded so they aren't rediscovered):** the lint scans `git ls-files`, so untracked/unstaged files are invisible to it (deliberate scan boundary); and Check B could over-match a pattern inside a comment/string or miss memory logic in non-scanned file types — manual review remains the fallback for that irreducible residual, which AC-G6 cannot fully mechanise.

- **Resolved in `extractor-wiring-fix`: the env-mirror workaround
  (`OPENAI_API_KEY`/`NAM_EXTRACTION__LLM_MODEL` mirroring `NAM_LLM__*`, plus the `openai`
  pip extra in `docker/mcp.Dockerfile`) is the adopted, intentional wiring for
  `create_llm_extractor()`, not a latent duplication bug.** `prod-anthropic-verify`'s
  implementation discovered, by reading the vendored `neo4j-agent-memory==0.2.0` source,
  that `create_llm_extractor()` never wires `NAM_LLM__API_KEY`/`NAM_LLM__MODEL` into the
  actual extractor client — it silently falls back to a raw `OPENAI_API_KEY` env var and a
  hardcoded `gpt-4o-mini` default. **Decision of record (Class 3, KEEP over PATCH):** the
  env-mirror is kept as the supported wiring rather than patching the pinned, vendored
  `neo4j-agent-memory==0.2.0` package, because patching a pinned third-party package at
  build time is comparatively fragile (can silently break or diverge on the next version
  bump, and no local copy of the vendored source exists in this checkout to patch against)
  for a purely cosmetic/hygiene gain, while the env-mirror is already shipped and proven
  working end-to-end against a real backend (GitHub Models, see below). **Recorded failure
  mode if these lines are ever deleted as believed-redundant:** `create_llm_extractor()`
  falls back to an unset `OPENAI_API_KEY` and the hardcoded `gpt-4o-mini` default, and the
  extraction stage errors or silently no-ops depending on how `memory_store_message`
  swallows per-stage extraction exceptions. Verified via `docker-compose.yml:48-51`/`:56-59`
  and `docker/mcp.Dockerfile`'s inline comments (present, unchanged) and zero functional
  diff to either file. Authored by Reconciliation (gate 6); see
  `docs/spec-loop-runs/extractor-wiring-fix/reconciliation.handoff.md`.

- **Resolved in `github-models-llm-backend`: a real, completing, non-mock LLM backend now
  works end-to-end through the proxy — closing the general "positive real-completion path"
  question left open by `prod-anthropic-verify` (`sk-ant-api…` credential unavailable).**
  Retargeted the `claude` model_name to **GitHub Models**
  (`model: openai/gpt-4o-mini` + `api_base: https://models.github.ai/inference` +
  `api_key: os.environ/GITHUB_API_KEY`, reached only via `llm-proxy` over the pre-existing
  `llm-egress-net`); `mcp`/`neo4j` hold no GitHub credential and cannot resolve/reach
  `models.github.ai` (confirmed via env grep and a DNS-failing reachability probe from
  inside `mcp`, run *while* a real call was in flight). From a clean state
  (`docker compose down -v` → fresh `up`), independently reproduced twice: (a) a direct
  proxy call returns a genuine `200` with a real `id`/`usage`, correlated via
  `llm-proxy` DEBUG logs to an outbound `https://models.github.ai/inference/` POST; (b) a
  full `memory_store_message` → real GitHub-Models extraction → direct Neo4j bolt read
  produced genuine, distinct POLE+O-style entities (`Entity`/`Event`/`Location`/`Object`/
  `Time` nodes via `MENTIONS` edges), not the verbatim stored sentence or the `claude-mock`
  string. **Decision of record:** the default extraction backend for real (non-mock,
  non-Anthropic) verification is GitHub Models `openai/gpt-4o-mini` via an **explicit
  `api_base`**, not LiteLLM's `github/` provider prefix — the latter silently routes to
  `models.inference.ai.azure.com` instead of `models.github.ai` (still a genuine completion,
  but the wrong upstream host for any check asserting `models.github.ai` specifically); see
  the `new_constraint` item above so this isn't rediscovered. The prior Anthropic entry is
  preserved, renamed `claude-anthropic`; `claude-mock` is untouched. The real-*Anthropic*-
  specific positive path (needs a genuine `sk-ant-api…` key) remains separately open and is
  now low priority — see open item above. **Security note:** this pass's verification
  credential was a broad `gh`-CLI OAuth token, acceptable only for the one-off local pass;
  any persistent/production use must switch to a fine-grained PAT scoped to `models: read`
  only, supplied to `llm-proxy` alone (see open item above). GitHub Models' free tier is
  rate-limited and prototyping-grade, not a production-scale SLA — a production deployment
  should budget for this or use a paid/enterprise tier.
- **Resolved in `prod-anthropic-verify`: AC-C6/AC-G3 routing/isolation verified against a
  real Anthropic credential.** A real (non-mock) key exercised the full path: `llm-proxy`
  gained outbound Anthropic reachability via a new, dedicated non-internal `llm-egress-net`
  network attached only to `llm-proxy` (`db-net`/`llm-net` unchanged, still `internal:
  true`; `mcp`/`neo4j` network membership byte-for-byte unchanged — no AC-C4/AC-C5/AC-G4
  regression, probes rerun and unchanged); `mcp` was independently confirmed to hold no
  `ANTHROPIC_API_KEY` and to be unable to reach `api.anthropic.com` even while a real
  Anthropic call from `llm-proxy` was in flight; and the request/response evidence (real,
  distinct Anthropic `request_id`s, zero occurrences of the mock string) proves the real
  credential path was genuinely reached, not the mock short-circuit. See updated §3.1,
  §9 slice-status, AC-C6/AC-G3 above.
- **Resolved: production Anthropic model id updated from the retired
  `claude-3-5-sonnet-latest` to `claude-sonnet-4-5`.** The old id no longer resolves on
  Anthropic's live API (confirmed via a genuine `404 not_found_error` with a real Anthropic
  `request_id`, not a local/litellm error) — an external model-lifecycle fact, not a defect
  in this repo's prior reasoning. `litellm/config.yaml`'s `claude`/`claude-mock` entries were
  updated accordingly; the exact model id is now treated as a floating fact to be
  re-verified per run rather than an immutable literal (see open item above).
- **Not yet resolved (recorded precisely): the real-Anthropic positive-completion path
  (R1) is blocked on credential type, not routing/isolation/rate-limiting.** Every triggered
  call during `prod-anthropic-verify` returned a genuine Anthropic error (`404` pre model-id
  fix, `429 rate_limit_error` post-fix, each with distinct real `request_id`s) rather than a
  `200`. The confirmed root cause: the only credential available
  (`~/.secrets/anthropic.env`) is a claude.ai/Claude Code **OAuth token**, which LiteLLM's
  `anthropic/` provider cannot use to authenticate to `api.anthropic.com` — only a genuine
  `sk-ant-api…` **API key** will. This remains open pending such a key, scoped to
  `llm-proxy` only; see open item above and AC-C6/AC-G3 Verification method.
- **Split out for its own slice: `create_llm_extractor()` ignores `NAM_LLM__API_KEY`/
  `NAM_LLM__MODEL`.** Discovered during `prod-anthropic-verify` and worked around there
  (`OPENAI_API_KEY`/`NAM_EXTRACTION__LLM_MODEL` added to `mcp`'s environment; `openai` pip
  extra added to `docker/mcp.Dockerfile`) only because it fully blocked R1/R2 from being
  exercised at all. This is a distinct, separately-reviewable framework-wiring bug, not part
  of `prod-anthropic-verify`'s network/egress scope. See the `extractor-wiring-fix` Decision
  of record above for the KEEP-vs-PATCH disposition of the wiring itself.
- **Resolved in `extractor-wiring-fix`: the `weak_verification` flag against the prior
  `llm-smoke` slice's mock-path PASS is confirmed, not dismissed by reasoning-by-analogy.**
  A fresh clean-state `memory_store_message` call was made over `claude-mock` and a direct
  Cypher read (`MATCH (m)-[:MENTIONS]->(e) WHERE m.content CONTAINS $marker RETURN
  labels(e), e`) found **zero** `MENTIONS`-linked entity nodes — the `MENTIONS` relationship
  type does not exist anywhere in the fresh database at all (confirmed via
  `db.relationshipTypes()`), and the `mcp` container's logs show `Stage 'LLMEntityExtractor'
  failed: Failed to parse LLM response as JSON: Expecting value: line 1 column 1 (char 0)` —
  a direct causal explanation, not just an absence. Independently reproduced twice (once by
  Implementation, once by Verification, each with its own fresh marker). **`llm-smoke`'s
  mock-path PASS for AC-C6/AC-G3/AC-G2 therefore proves message persistence, proxy routing,
  and semantic search over the raw stored content only — not successful structured entity
  extraction.** Structured entity extraction over the env-mirror wiring is proven only by
  `github-models-llm-backend`'s real-GitHub-Models run, which produced genuine, distinct
  POLE+O-style entities via `MENTIONS` edges over the same wiring (see above). §9's
  slice-status paragraph and the `llm-smoke` resolved-item bullet below already scope their
  claims to "the LLM-triggering *persistence* portion of AC-G2" and do not claim mock-path
  extraction was exercised, so no further §9 wording change was needed beyond this
  reconciliation. Authored by Reconciliation (gate 6); see
  `docs/spec-loop-runs/extractor-wiring-fix/reconciliation.handoff.md`.

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
- **Resolved in `mcp-env-cleanup`: dead `MCP_TRANSPORT`/`MCP_HOST`/`MCP_PORT` env wiring
  removed.** Deleted the three unread vars from `docker-compose.yml`'s `mcp.environment:`
  block, `.env.example`'s "MCP transport" section, and the §7 config table row. Transport,
  host, and port continue to be supplied solely by `docker/mcp.Dockerfile`'s hardcoded
  `CMD` flags (`--transport http --host 0.0.0.0 --port 8080`), which were not modified.
  Runtime regression check (`docker compose up`, `mcp` reaches `healthy`, TCP connect to
  `8080` succeeds) reproduced clean, confirming the vars were genuinely dead.
  Verification (gate 5) additionally found and this slice remediated two **process**
  defects in the *first* draft of the spec handoff, both now folded back here rather than
  left as loose notes: (1) `contradictory_requirement` — the original single REQ-2 asked
  one stage to both land the `.env.example` edit and write `docs/SPECIFICATION.md`,
  crossing the Implementation/Reconciliation boundary; gate 1 re-scoped it into REQ-2a
  (Implementation: `.env.example` only) and REQ-2b (Reconciliation: this `SPECIFICATION.md`
  edit), restoring the single-writer rule in `reconciliation-agent/SKILL.md`.
  (2) `weak_verification` — REQ-2b's verification method was tightened to add an explicit
  process/provenance check (no implementation-stage diff may touch `docs/SPECIFICATION.md`;
  authorship is evidenced by a `reconciliation.handoff.md` entry for the slice), so a
  content-only grep can no longer pass a same-text edit made by the wrong stage. This
  `SPECIFICATION.md` edit (§7 row removal, §10 item resolution) is authored by the
  Reconciliation stage for `mcp-env-cleanup`, satisfying REQ-2b; see
  `docs/spec-loop-runs/mcp-env-cleanup/reconciliation.handoff.md`.
