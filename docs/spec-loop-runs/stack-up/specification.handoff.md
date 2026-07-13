# Specification handoff — stack-up

## Slice

`stack-up` bounded first sub-slice: prove the runtime DB-persistence and DB↔LLM-proxy network-isolation subset using only the public `neo4j` and `llm-proxy` images, with no Anthropic call and no `mcp` image build.

## Normalized requirements

### STK-C1 — Neo4j data survives a container restart

- **Trigger:** Start the `neo4j` service, write a test node to Neo4j, restart the `neo4j` container, then query for the same node.
- **Preconditions:** `docker compose config` renders successfully; `docker-compose.yml` binds the named `neo4j-data` volume to Neo4j `/data`; the configured Neo4j URI is a local bolt URI (`bolt://neo4j:7687`) and no external DB URI is used.
- **Expected observable outcome:** The test node written before restart is still queryable after restart, and the rendered config maps Neo4j `/data` to the named `neo4j-data` volume rather than anonymous or container-ephemeral storage.
- **Failure behaviour:** If the named `/data` volume binding is absent, anonymous, or not named `neo4j-data`, the config assertion fails before runtime; if the node is missing after restart, the persistence check exits non-zero.
- **Verification method:** AC-C1 persistence check from spec §9: config lint asserts named volume + bolt non-remote URI; runtime writes a node, `docker restart`/`docker compose restart neo4j`, and re-query returns the node. For this bounded sub-slice, perform the write/re-query directly against Neo4j over bolt/cypher-shell rather than through the MCP tool smoke sequence; the MCP-backed AC-G2 persistence proof is explicitly deferred.
- **Traces to:** C1; supports the DB-persistence part of G2/AC-G2 but does not complete AC-G2.

### STK-C5-G4 — Neo4j and LiteLLM cannot reach each other

- **Trigger:** After starting `neo4j` and `llm-proxy`, run reachability probes from inside `neo4j` toward `llm-proxy:4000` and from inside `llm-proxy` toward `neo4j:7687`.
- **Preconditions:** Rendered compose network membership has `neo4j` only on `db-net`, `llm-proxy` only on `llm-net`, both networks are internal, and the two services share no network.
- **Expected observable outcome:** Both cross-service probes fail to connect: `neo4j → llm-proxy:4000` is unreachable and `llm-proxy → neo4j:7687` is unreachable by connection refusal, DNS failure, or timeout.
- **Failure behaviour:** If either cross-service probe connects, isolation is violated and the check exits non-zero; the stack must not be treated as deployable.
- **Verification method:** AC-C5 / AC-G4 db↔llm half from spec §9: reachability probe `neo4j → llm-proxy:4000` and `llm-proxy → neo4j:7687`, both asserted to fail.
- **Traces to:** C5, G4.

## Verification criteria

- **STK-C1:** `docker compose config` must show `neo4j-data:/data` and `bolt://neo4j:7687`; after a direct Neo4j test-node write and `neo4j` restart, a direct Neo4j query for that node must return exactly the written node.
- **STK-C5-G4:** With `neo4j` and `llm-proxy` running, scripted reachability probes executed from inside each service container must assert both cross-network connections fail: `neo4j` cannot connect to `llm-proxy:4000`, and `llm-proxy` cannot connect to `neo4j:7687`.

## Explicit scope

**In scope**

- Runtime proof of local Neo4j persistence for AC-C1 at the database/container layer.
- Runtime proof of AC-C5 and the DB↔LLM-proxy isolation half of AC-G4.
- Starting only `neo4j` and `llm-proxy` targets, so the pass uses public images and avoids building `docker/mcp.Dockerfile`.
- Recording environmental blockers that affect later `stack-up` sub-slices.

**Out of scope / deferred**

- **AC-C3** and the `mcp → neo4j` / `mcp → llm-proxy` half of **AC-G4**: no Anthropic key required, but requires building/running the heavy `mcp` image.
- **AC-G1** tool exposure: no Anthropic key required for `list_tools`, but requires the `mcp` image and an available MCP host port.
- **AC-C7** offline embedder: no Anthropic key required, but requires the `mcp` image build because the Dockerfile bakes `BAAI/bge-small-en-v1.5` at build time.
- **AC-C6** and **AC-G3** LLM routing: require a valid Anthropic credential because the verification method confirms a real LLM call appears in LiteLLM logs.
- **AC-G2** MCP-backed memory persistence: requires the `mcp` image and the tool smoke sequence; because the required `memory_store_message` path performs extraction, treat it as Anthropic-key-dependent unless the framework is later proven to support a no-LLM store path for this check.
- **AC-G5** semantic vector search: requires the `mcp` image/offline embedder and an end-to-end store/search smoke; because the defined smoke uses stored content and framework extraction, treat it as Anthropic-key-dependent unless a no-LLM semantic-search setup is explicitly specified later.
- §3.3 README and scripted 16-tool smoke-test work: deferred with AC-G1/G2/G5 because it depends on the running MCP server.
- §10 AC-G6 thin-delta mechanisation decision: not part of this runtime stack-up sub-slice.

## Unresolved decisions

- **Class 1 blocker for deferred LLM criteria only — Anthropic credential for runtime smoke.** Legitimate options: (a) provide a valid `ANTHROPIC_API_KEY` securely in the environment or `.env` for the AC-C6/AC-G3/LLM-backed smoke pass, or (b) keep those criteria deferred and run only non-LLM sub-slices. This does not block STK-C1 or STK-C5-G4.

## Recorded facts & safe choices

### Class 2 facts

- The spec marks runtime probes for AC-C1, AC-C3, AC-C5, AC-C6, AC-C7, AC-G1, AC-G2, AC-G3, AC-G4, and AC-G5 as pending in `stack-up`. Citation: `docs/SPECIFICATION.md:223-226`.
- C1 requires local Neo4j data on a named volume; C5 requires `neo4j` and `llm-proxy` to share no network; G4 defines `mcp` as the only bridge. Citations: `docs/SPECIFICATION.md:59-63`, `docs/SPECIFICATION.md:90-93`, `docs/SPECIFICATION.md:340-349`.
- AC-C1's full spec verification says config lint plus a write, Neo4j restart, and re-query; AC-C5/G4's DB↔LLM proof is two negative reachability probes. Citations: `docs/SPECIFICATION.md:230-239`, `docs/SPECIFICATION.md:272-281`, `docs/SPECIFICATION.md:340-349`.
- Current compose defines `neo4j:5`, maps `neo4j-data:/data`, places `neo4j` only on `db-net`, places `llm-proxy` only on `llm-net`, and marks both networks internal. Citations: `docker-compose.yml:2-19`, `docker-compose.yml:21-32`, `docker-compose.yml:60-67`.
- Current compose can render: Gate-2 probe `docker compose config --format json >/dev/null` returned `compose_config=ok`.
- Docker is available and the daemon is running: Gate-2 probe returned `/usr/bin/docker`, Docker `28.0.0`, Compose `v2.33.0`, and `docker info` returned `docker_info=ok` with server version `28.0.0`.
- Host port 8080 is already occupied by an existing container: Gate-2 probe `ss -ltnp 'sport = :8080'` showed `127.0.0.1:8080` listening, and `docker ps --filter publish=8080` showed `name=graphmind-mcp image=graphmind_graphmind ports=127.0.0.1:8080->8080/tcp`.
- No real Anthropic credential is available to this session: Gate-2 probe found `env_ANTHROPIC_API_KEY_present=False` and `dot_env_exists=False`; `.env.example` contains only the placeholder template and warns the key is for `llm-proxy` only. Citation: `.env.example:23-25`.
- LiteLLM config uses one Anthropic-backed `claude` model and sources the real key from `ANTHROPIC_API_KEY`. Citation: `litellm/config.yaml:1-7`.
- The `mcp` image path is heavy: `docker/mcp.Dockerfile` installs `neo4j-agent-memory[mcp]==0.2.0` and bakes the sentence-transformers model during image build. Citation: `docker/mcp.Dockerfile:10-16`.
- PyPI has `neo4j-agent-memory` version `0.2.0`, and the `mcp` extra exists. Gate-2 PyPI probe against `https://pypi.org/pypi/neo4j-agent-memory/0.2.0/json` returned `name=neo4j-agent-memory`, `version=0.2.0`, and `provides_extra=...,mcp,...`.
- The framework wheel exposes console script `neo4j-agent-memory = neo4j_agent_memory.cli:main` and its CLI contains a `mcp serve` subcommand (`neo4j-agent-memory mcp serve` examples in the wheel). The same probe found no `mcp` console script from this package, while the current Dockerfile uses `ENTRYPOINT ["mcp", "serve"]`; resolving that belongs to the deferred `mcp` image sub-slice. Citations: PyPI wheel `neo4j_agent_memory-0.2.0.dist-info/entry_points.txt`; wheel `neo4j_agent_memory/cli/main.py:680-792`; `docker/mcp.Dockerfile:24-37`.

### Class 3 safe choices

- Chose the DB-persistence + DB↔LLM isolation subset first because it is reversible slice selection, verifies in one pass, and avoids both known blockers: missing Anthropic credential and heavy `mcp` image build.
- Chose to treat STK-C1 as a DB-layer AC-C1 proof and defer MCP-backed AC-G2 persistence because AC-C1's tool-smoke wording couples otherwise simple volume persistence to the deferred MCP/LLM path; this narrows scope without changing the public contract.
- Chose not to ask about freeing host port 8080 for this pass because the selected sub-slice does not start/publish `mcp`; record it as a later environment fact instead of a product decision.
