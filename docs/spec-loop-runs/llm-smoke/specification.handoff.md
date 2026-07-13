# Specification handoff — llm-smoke

## Slice

`llm-smoke` — prove the LLM-dependent runtime path is locally runnable through LiteLLM with a compatible mock backend, while preserving production Anthropic isolation and proving persistence plus semantic search with the runtime offline embedder.

## Normalized requirements

### R1 — LLM routing and isolation are proxy-only; real Anthropic positive path is production-only

- **Trigger:** A framework operation that issues an LLM call runs, using `memory_store_message` as the smoke trigger.
- **Preconditions:** The stack is configured with `NAM_LLM__PROVIDER=openai`, `OPENAI_BASE_URL=http://llm-proxy:4000/v1`, `NAM_LLM__API_KEY` equal to the LiteLLM virtual key accepted as `LITELLM_MASTER_KEY`, and `NAM_LLM__MODEL=claude-mock` for local smoke. `litellm/config.yaml` exposes a mock-backed model with `mock_response` and a production Anthropic-backed model whose `ANTHROPIC_API_KEY` is present only in `llm-proxy`, not `mcp`.
- **Expected observable outcome:** The LLM-triggering request succeeds locally via the LiteLLM proxy, is recorded in `llm-proxy` logs, and `mcp` has no Anthropic credential or direct Anthropic route. The local smoke proves routing/isolation; proving the production response is served by real Anthropic is deferred to a credentialed environment.
- **Failure behaviour:** If the virtual key, model route, or proxy base URL is wrong, the LLM call fails at LiteLLM and `mcp` does not fall back to Anthropic because it has no Anthropic key and must not have direct Anthropic egress.
- **Verification method:** Run the llm smoke sequence against `NAM_LLM__MODEL=claude-mock`, then assert (1) `docker compose logs llm-proxy` contains the completion request/model evidence, (2) `docker compose exec mcp env` has no `ANTHROPIC_API_KEY`, and (3) an egress assertion from `mcp` to Anthropic API host(s) fails or is absent by network policy. Separately, in production only, rerun with `NAM_LLM__MODEL=claude` and a real `ANTHROPIC_API_KEY` supplied only to `llm-proxy`.
- **Traces to:** AC-C6, AC-G3, C5, C6, G3, G4.

### R2 — LLM-triggering store path persists nodes in local Neo4j

- **Trigger:** The smoke client calls `memory_store_message` with content that triggers extraction through the mock LLM route.
- **Preconditions:** R1 routing is configured; `NEO4J_URI=bolt://neo4j:7687`, `NEO4J_USER`, `NEO4J_PASSWORD`, and `NEO4J_DATABASE` point the framework at the local compose Neo4j service.
- **Expected observable outcome:** The store call completes and queryable node(s) representing the stored content are present in Neo4j via a direct bolt/Cypher read.
- **Failure behaviour:** If LLM extraction, database wiring, or persistence fails, `memory_store_message` returns an error or the direct bolt read returns no matching node; the criterion fails.
- **Verification method:** In the llm smoke sequence, store a unique message via `memory_store_message`; then use a direct Neo4j bolt/Cypher read to assert at least one node containing the unique stored text/session marker exists.
- **Traces to:** AC-G2, C1, G2.

### R3 — Runtime offline embedder loads the baked model and produces 384-dimensional vectors

- **Trigger:** The running `mcp` server initializes or first needs an embedding for store/search.
- **Preconditions:** The `mcp` image has baked `BAAI/bge-small-en-v1.5`; the running `mcp` service sets `NAM_EMBEDDING__PROVIDER=sentence_transformers`, `NAM_EMBEDDING__MODEL=BAAI/bge-small-en-v1.5`, `NAM_EMBEDDING__DIMENSIONS=384`, `HF_HUB_OFFLINE=1`, and `TRANSFORMERS_OFFLINE=1`.
- **Expected observable outcome:** The running server loads the baked model from cache, does not attempt a Hugging Face download, and uses 384-dimensional embeddings for vector-backed memory operations.
- **Failure behaviour:** If the baked model is missing or the offline env is not set, startup/first embedding fails rather than downloading from the network.
- **Verification method:** Assert the rendered compose/runtime environment for `mcp` contains `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1`; run the llm smoke store/search path with network egress blocked or logs inspected for no Hugging Face access; assert embeddings/vector index use dimension 384 (via framework output, Neo4j vector index metadata, or a direct embedding probe inside the running server image).
- **Traces to:** AC-C7, AC-G5, C7, G5.

### R4 — Semantic vector search returns a paraphrase hit with no exact-token overlap

- **Trigger:** After R2 stores content and R3 has embedded it locally, the smoke client calls `memory_search` with a paraphrase query.
- **Preconditions:** The stored text and paraphrase query are chosen so the query shares no exact significant tokens with the stored text; Neo4j vector index is created by the framework; local embedder is running offline in `mcp`.
- **Expected observable outcome:** `memory_search` returns a relevant hit for the stored content, proving the local embedder and Neo4j vector index work end to end.
- **Failure behaviour:** If embeddings, vector indexing, or search wiring is broken, `memory_search` returns no hit or an irrelevant hit; the criterion fails.
- **Verification method:** Store a unique semantically clear sentence, then search with a token-disjoint paraphrase and assert the top results include the stored memory/session marker. The assertion must fail if exact-token/full-text matching is the only working path.
- **Traces to:** AC-G5, C7, G5.

## Verification criteria

- **R1:** A mock-backed `memory_store_message` LLM call is visible in `llm-proxy` logs; `mcp` env lacks `ANTHROPIC_API_KEY`; `mcp` has no direct Anthropic egress. The real-Anthropic positive path is not required locally.
- **R2:** A unique `memory_store_message` payload is found as node data through a direct Neo4j bolt/Cypher read after the store call completes.
- **R3:** The running `mcp` service has `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1`, loads the baked `BAAI/bge-small-en-v1.5` model, and produces/uses 384-dimensional embeddings without Hugging Face network access.
- **R4:** `memory_search` with a paraphrase sharing no exact significant tokens with the stored text returns the relevant stored memory/session marker.

## Explicit scope

### In scope

- Specifying the LiteLLM mock-backed local smoke model (for example `claude-mock`) as a compatible backend for llm-smoke.
- Specifying the compatible llm key: `NAM_LLM__API_KEY` must be the LiteLLM virtual key accepted as `LITELLM_MASTER_KEY`; no provider secret is needed for the mock path.
- Proxy routing/isolation evidence for AC-C6/AC-G3 using the mock backend.
- Persistence evidence for an LLM-triggering `memory_store_message` via direct Neo4j read.
- Runtime offline embedder evidence and semantic vector search paraphrase evidence.

### Out of scope

- Editing implementation files such as `litellm/config.yaml`, `docker-compose.yml`, `.env.example`, Dockerfiles, smoke scripts, or application code in this stage.
- Running Docker, running smoke tests, or judging whether implementation currently passes.
- Proving a real Anthropic-backed completion without a real `ANTHROPIC_API_KEY`; that is explicitly deferred to a credentialed production-like environment.
- Reworking framework internals, MCP tool semantics, entity extraction prompt shape, or Neo4j schema.

## Unresolved decisions

None — cleared at gate 2.

## Recorded facts & safe choices

### Class-2 facts (investigated, with citations)

- The current environment has no `ANTHROPIC_API_KEY`; only unrelated `DD_API_KEY` is set among checked keys. Citation: environment check run in this stage reported `ANTHROPIC_API_KEY=unset`, `DD_API_KEY=set`, `LITELLM_MASTER_KEY=unset`, `NAM_LLM__API_KEY=unset`.
- LiteLLM supports `mock_response` for completion calls and returns a response without calling LLM APIs. Citation: LiteLLM docs at `https://docs.litellm.ai/docs/completion/mock_requests` state mock responses return without calling the LLM APIs.
- Existing compose wiring gives `llm-proxy` `LITELLM_MASTER_KEY` and `ANTHROPIC_API_KEY`, while `mcp` gets `NAM_LLM__API_KEY` and `OPENAI_BASE_URL=http://llm-proxy:4000/v1`. Citation: `docker-compose.yml:25-26`, `docker-compose.yml:45-46`.
- Existing compose wiring sets the local embedder provider/model/dimensions on `mcp` but does not yet set `HF_HUB_OFFLINE` or `TRANSFORMERS_OFFLINE`. Citation: `docker-compose.yml:47-49` and absence of those names from the compose grep; `.env.example:15-17` similarly lists provider/model/dimensions only.
- The `mcp` image bakes `BAAI/bge-small-en-v1.5` at build time with `SentenceTransformer`. Citation: `docker/mcp.Dockerfile:15`.
- The current LiteLLM config has only the production `claude` model backed by Anthropic and uses `LITELLM_MASTER_KEY` as the proxy virtual key. Citation: `litellm/config.yaml:1-7`.
- The revised durable spec now describes `claude-mock`, `mock_response`, the virtual-key relationship, and runtime offline embedder env. Citation: `docs/SPECIFICATION.md:175-194`, `docs/SPECIFICATION.md:211-218`, `docs/SPECIFICATION.md:335-349`, `docs/SPECIFICATION.md:354-356`, `docs/SPECIFICATION.md:415-423`.

### Class-3 safe choices (decided, with rationale)

- Chose a separate `claude-mock` LiteLLM model name over reusing `claude` because it keeps production Anthropic routing and local mock routing explicit and reversible without changing the public MCP tool surface.
- Chose `NAM_LLM__API_KEY == LITELLM_MASTER_KEY` as the compatible llmkey because it follows the existing proxy virtual-key convention and avoids introducing any provider secret into `mcp`.
- Chose to make `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1` required runtime env for `mcp` because the model is already baked into the image and these flags make the no-network property mechanically verifiable.
- Chose a token-disjoint paraphrase assertion for AC-G5 because it distinguishes semantic vector search from exact-token/full-text matching without changing product behavior.
