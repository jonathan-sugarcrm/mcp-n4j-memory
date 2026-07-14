# Implementation handoff: `extractor-wiring-fix`

Consumed **only** `docs/spec-loop-runs/extractor-wiring-fix/specification.handoff.md`.

## 1. Implementation plan

1. `[REQ-1] Verify the env-mirror comments already meet the "not mistaken for a bug"
   bar in docker-compose.yml/docker/mcp.Dockerfile, per the handoff's stated
   precondition -> verify: read the exact lines cited (docker-compose.yml:45-59,
   docker/mcp.Dockerfile:13) and confirm no functional/comment change is needed.`
2. `[REQ-1] Record the KEEP decision content as a proposed "Decision of record" +
   Resolved-item text (see §5 below) for gate 6/Reconciliation to apply to
   SPECIFICATION.md -> verify: text is self-contained, traces to the exact
   §10 lines it replaces, and states the failure behaviour verbatim as required.`
3. `[REQ-2] Bring the stack up clean (docker compose down -v -> up --build) with
   NAM_LLM__MODEL=claude-mock and no real provider credentials -> verify:
   docker compose ps shows neo4j healthy, mcp healthy.`
4. `[REQ-2] Run a fresh memory_store_message call for a unique marker over the
   mock backend, then run the MENTIONS-edge Cypher query from inside the mcp
   container (same db-net/llm-net as the running services) -> verify: raw query
   output captured verbatim, plus db.labels()/db.relationshipTypes()/count(n)
   as corroborating evidence, plus mcp container logs for the extraction stage.`
5. `[REQ-2] Tear down (docker compose down -v) and remove all scratch files
   created for this check -> verify: git status --short shows no scratch files,
   no .env, and no diff to docker-compose.yml/docker/mcp.Dockerfile.`

## 2. Changed files

**None.** No file was modified as part of REQ-1 or REQ-2's code/config scope.

- REQ-1's expected observable outcome is a `SPECIFICATION.md` edit (a "Decision of
  record" bullet + moving the open item to Resolved). Per this agent's operating
  boundary for this run, `docs/SPECIFICATION.md` is **out of scope for the
  Implementation stage** — it is reserved for Reconciliation (gate 6). This is
  recorded as a **blocking spec/process conflict** in §5 below, not silently
  resolved; the exact proposed text is provided there, unapplied, for gate 6 to
  land verbatim (or amend) once it independently confirms the same evidence.
- `docker-compose.yml` / `docker/mcp.Dockerfile`: read, not edited. The handoff's
  own precondition states the clarifying comments (lines 47-49, 56-58 in
  docker-compose.yml; the extract comment above `docker/mcp.Dockerfile:13`) already
  exist and already meet the "not mistaken for a bug" bar (handoff §6, third
  bullet). Confirmed verbatim in this run (see Evidence bundle, REQ-1). No
  additional comment was needed or added.
- A local, untracked `.env` (mock-path credentials only, no real API keys) and a
  scratch Cypher-check script were created solely to drive the REQ-2 empirical
  check and were deleted before completion (see Evidence bundle, REQ-2, cleanup
  step). Neither is a repository change; `git status --short` is clean of both
  post-run, confirmed below.

## 3. Decision log

- Chose to run REQ-2's `memory_store_message` call and the `MENTIONS` Cypher
  check **from inside the running `mcp` container** (via `docker compose exec`)
  rather than from the host, because host port 8080 is occupied by an unrelated
  container (`graphmind-mcp`) in this shared multi-tenant environment and this
  compose stack's `mcp` service was consequently not reachable at
  `localhost:8080` on the host (confirmed: `docker compose port mcp 8080` →
  "no port 8080/tcp for container"). The `mcp` container already has `fastmcp`
  and the `neo4j` driver installed (it needs them to run itself) and sits on the
  same `db-net`/`llm-net` as `neo4j`, so this is a same-stack, same-network
  substitution for `scripts/llm_smoke.py`'s host-side invocation — reversible,
  no contract impact, doesn't touch any tracked file.
- Chose to write the scratch check script to the repo root
  (`scratch_check_script.py`, later deleted) rather than `/tmp`, per this run's
  environment constraint against writing to `/tmp`, then `docker cp` it into the
  container — reversible, no contract impact.
- Chose to also capture `CALL db.labels()`/`db.relationshipTypes()`/`count(n)`
  and the `mcp` container's stage-failure log line as corroborating evidence
  alongside the exact `MENTIONS`-edge query the handoff specifies, because the
  handoff's own Verification method says to capture "the query's actual result
  ... recorded verbatim as new evidence" and the additional reads make the zero
  result unambiguous (zero because the relationship type doesn't exist at all,
  not a query-shape artifact) — this is corroboration, not a substitute for the
  specified query, which was run and captured first.
- Chose local, non-secret placeholder credentials for `.env`
  (`NAM_LLM__API_KEY`/`LITELLM_MASTER_KEY` = a fixed local string, `GITHUB_API_KEY`/
  `ANTHROPIC_API_KEY` = `change-me`) since REQ-2 explicitly only requires the
  `claude-mock` model (no upstream credential reaches an external provider) —
  follows the handoff's own explicit-scope exclusion of the real-provider path.

## 4. Evidence bundle

| Requirement | Evidence | Result |
|---|---|---|
| **REQ-1** — env-mirror KEEP: comments at `docker-compose.yml:45-59` and `docker/mcp.Dockerfile` already explain the workaround; zero functional diff expected. | `git status --short` after the full run shows no changes to `docker-compose.yml` or `docker/mcp.Dockerfile`; `git diff --stat` is empty for tracked files. Verbatim comment text confirmed present at read time: <br>`docker-compose.yml:47-51`: `"# The framework's LLMEntityExtractor stage uses the openai SDK directly / # and reads OPENAI_API_KEY (not NAM_LLM__API_KEY) when no api_key is / # passed explicitly. Must match llm-proxy's LITELLM_MASTER_KEY so the / # openai client can authenticate to the proxy (this is the LiteLLM / # virtual key, never the real ANTHROPIC_API_KEY)."` <br>`docker-compose.yml:56-58`: `"# The framework's ExtractionConfig.llm_model (default gpt-4o-mini) is a / # separate setting from NAM_LLM__MODEL and is not derived from it; must / # be set explicitly so the LLMEntityExtractor stage requests the same / # model configured on llm-proxy."` <br>`docker/mcp.Dockerfile` (above the pip install line): `"# Install neo4j-agent-memory framework with MCP support, the local embedding / # backend, and the openai extra (OpenAI-compatible client used to call the / # LiteLLM proxy for the LLMEntityExtractor stage during memory_store_message)."` | **PASS** (mechanical check: comments present, zero functional diff) — but see §5 blocking defect: the `SPECIFICATION.md` write-back itself is deferred to gate 6, not executed here. |
| **REQ-2** — falsifiable mock-path entity-extraction re-check: predicted **zero** `MENTIONS`-linked entity nodes for a fresh mock-path marker. | Full raw session, reproducible via `docker compose up -d --build` with `NAM_LLM__MODEL=claude-mock` then, from inside the `mcp` container: <br>`STORE_RESULT: {"stored": true, "type": "message", "id": "50caa2ca-0a42-4fe4-8fb8-5c5f5a3aa4c8", "session_id": "extractor-wiring-fix-session-43d0ca0b"}` <br>`MESSAGE_NODE:` (Message node found, labels `['Message']`, `content: 'Marker extractor-wiring-fix-9d9778c0b0b0: the falcon soared gracefully above the canyon at dawn.'`) <br>Exact query run: `MATCH (m)-[:MENTIONS]->(e) WHERE m.content CONTAINS $marker RETURN labels(e) as labs, e ORDER BY labs` → Neo4j driver returned a **GQL notification**: `"warn: relationship type does not exist. The relationship type \`MENTIONS\` does not exist. Verify that the spelling is correct."` → `MENTIONS_ENTITIES_COUNT: 0` → `MENTIONS_ENTITIES_RAW: []` <br>Corroborating whole-database reads (same clean-state run): `ALL_LABELS: [{'label': 'Conversation'}, {'label': 'Message'}, {'label': 'Entity'}, {'label': 'Preference'}, {'label': 'Fact'}, {'label': 'ReasoningTrace'}, {'label': 'ReasoningStep'}, {'label': 'Tool'}, {'label': 'ToolCall'}, {'label': 'User'}, {'label': 'ConsolidationRun'}, {'label': 'MemoryReadAudit'}]` (schema declares `Entity` but none were created); `ALL_REL_TYPES: [{'relationshipType': 'HAS_MESSAGE'}, {'relationshipType': 'FIRST_MESSAGE'}]` (no `MENTIONS` type exists anywhere in the DB); `TOTAL_NODES: 2` (only the `Conversation` + `Message` node for this call). <br>Root-cause log line, `docker compose logs mcp`: `"Stage 'LLMEntityExtractor' failed: Failed to parse LLM response as JSON: Expecting value: line 1 column 1 (char 0)"` (also `SpacyEntityExtractor`/`GLiNEREntityExtractor` failed for missing optional deps, confirming `LLMEntityExtractor` was the only extraction path wired via the env-mirror, and it failed specifically on JSON-parsing the fixed mock string). | **PASS** — prediction confirmed: **zero** `MENTIONS`-linked entity nodes for the mock-path marker, with a direct causal log line proving *why* (JSON-parse failure on the fixed non-JSON `mock_response`), not just an absence. This resolves the `weak_verification` flag: `llm-smoke`'s mock-path R2 PASS proved message persistence + proxy routing only, **not** structured entity extraction. |

**Failure-behaviour exercise (REQ-2's defined alternate outcome):** the handoff's
failure behaviour for REQ-2 is "the query instead finds genuine, distinct
`MENTIONS`-linked entity nodes" — this was not what occurred (see PASS above), so
the alternate branch was not taken; the `weak_verification` prediction held. The
contrasting **real-backend** positive case (non-mock, GitHub Models) is not
re-run here per the handoff's explicit permission ("you may cite that evidence
rather than fully re-run if the handoff permits") — it is already evidenced in
`SPECIFICATION.md`'s `github-models-llm-backend` resolved-item bullet ("a full
`memory_store_message` → real GitHub-Models extraction → direct Neo4j bolt read
produced genuine, distinct POLE+O-style entities ... via `MENTIONS` edges").

**Teardown evidence:** `docker compose down -v` output shows
`mcp-n4j-memory-neo4j-1 Removed`, `mcp-n4j-memory_neo4j-data Removed`, all three
networks removed; `git status --short` immediately after shows no scratch files
(`scratch_check_script.py`, `.env`) and no diff to any tracked file, only the new
`docs/spec-loop-runs/extractor-wiring-fix/` artifact directory.

## 5. Blocking spec defects / process conflict

**One conflict, not a spec defect — flagged for gate 6, not guessed past:**

REQ-1's "Expected observable outcome" literally specifies an edit to
`SPECIFICATION.md` (a new "Decision of record" bullet, moving the open item to
Resolved). This agent's operating instructions for this run explicitly exclude
`docs/SPECIFICATION.md` from the Implementation stage's edit scope ("reserved for
Reconciliation/gate 6"). Rather than silently editing the reserved file (which
would violate the isolation contract in the other direction) or silently
skipping REQ-1's outcome, this is recorded as a role-boundary conflict and the
exact text is prepared below, unapplied, for Reconciliation to land (verbatim or
amended) once it independently reviews this evidence bundle:

> **Proposed "Decision of record" (for `SPECIFICATION.md` §10, replacing the
> `:562-577` open-item bullet, moving it to Resolved items):**
>
> "**Resolved in `extractor-wiring-fix`: the env-mirror workaround
> (`OPENAI_API_KEY`/`NAM_EXTRACTION__LLM_MODEL` mirroring `NAM_LLM__*`, plus the
> `openai` pip extra in `docker/mcp.Dockerfile`) is the adopted, intentional
> wiring for `create_llm_extractor()`, not a latent duplication bug.** KEEP was
> chosen over patching the vendored, pinned `neo4j-agent-memory==0.2.0` package:
> patching a pinned third-party package at build time is comparatively fragile
> (can silently break or diverge on the next version bump, and no local copy of
> the vendored source exists in this checkout to patch against) for a purely
> cosmetic/hygiene gain; the workaround is already shipped and proven working
> end-to-end against a real backend (GitHub Models, see below). **Recorded
> failure mode if these lines are ever deleted as believed-redundant:**
> `create_llm_extractor()` falls back to an unset `OPENAI_API_KEY` and the
> hardcoded `gpt-4o-mini` default, and the extraction stage errors or silently
> no-ops depending on how `memory_store_message` swallows per-stage extraction
> exceptions."
>
> **Proposed correction to the `weak_verification` flag (replacing/reconciling
> `:570-578` vs `:646-651`):**
>
> "**Resolved in `extractor-wiring-fix`: the `weak_verification` flag against
> `llm-smoke`'s mock-path R2 is confirmed, not dismissed.** A fresh clean-state
> `memory_store_message` call over `claude-mock` was made and a direct Cypher
> read (`MATCH (m)-[:MENTIONS]->(e) WHERE m.content CONTAINS $marker RETURN
> labels(e), e`) found **zero** `MENTIONS`-linked entity nodes — the
> `MENTIONS` relationship type does not exist anywhere in the fresh database at
> all (confirmed via `db.relationshipTypes()`), and the `mcp` container's logs
> show `Stage 'LLMEntityExtractor' failed: Failed to parse LLM response as
> JSON: Expecting value: line 1 column 1 (char 0)` — a direct causal
> explanation, not just an absence. `llm-smoke`'s mock-path PASS for
> AC-C6/AC-G3/AC-G2 therefore proves message persistence, proxy routing, and
> semantic search over the raw stored content only — **not** successful
> structured entity extraction. Structured extraction remains proven only by
> `github-models-llm-backend`'s real-GitHub-Models run, which produced genuine,
> distinct POLE+O-style entities via `MENTIONS` edges over the same wiring."

This text is a proposal, not applied — gate 6 (Reconciliation) owns
`SPECIFICATION.md` and should independently re-derive its verdict from the
Evidence bundle above rather than trust this summary, per `SPEC_LOOP.md`'s
evidence-bundle rules.

No other blocking spec defects. REQ-2's criteria, preconditions, and
verification method were all directly executable as written; no field was
empty or contradictory.
