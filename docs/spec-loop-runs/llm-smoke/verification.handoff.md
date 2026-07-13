# Verification handoff — llm-smoke

## Scope and method

Inputs used, per the gate-5 isolation rule: `specification.handoff.md`, `implementation.handoff.md`,
and the actual repo/running stack. No other slice's handoffs were read.

Reproduction was done **from a clean state**: `.env` had been removed by the environment setup, the
stack was down, and no assumptions were carried over from the implementation handoff's claims. Steps:

1. `cp .env.example .env`, filled in test placeholder secrets (`NEO4J_PASSWORD`, `NAM_LLM__API_KEY`,
   `LITELLM_MASTER_KEY`), left `NAM_LLM__MODEL=claude-mock` (the `.env.example` default).
2. `docker compose up -d --build` — clean build, all three services started, `neo4j` reported healthy.
3. Confirmed the sandbox's known limitation independently: `docker inspect ... NetworkSettings.Ports`
   returned `{}` for all three services (no host publishing), and host port 8080 is occupied by an
   unrelated pre-existing container (`graphmind-mcp`, confirmed via `docker ps`). This matches the
   implementation handoff's documented environment note. Evidence was therefore gathered the same way
   the implementation did — via `docker compose exec`/`docker compose logs` from inside the compose
   network — which observes the real running containers and real network boundaries, not a simulation.
4. Re-ran every check independently (not by pasting the implementation's transcript) with fresh unique
   markers/keys, including the failure paths for each requirement.
5. `docker compose down -v`, deleted the local `.env`. Tree left as found plus the two gate-5 artifacts.

All requirements below are **runtime-reproduced**, not static-only.

## Results

### R1 — LLM routing and isolation are proxy-only — PASS (runtime-reproduced)

- Happy path: `POST /v1/chat/completions` with `model=claude-mock` from inside `mcp` → `200 OK`,
  `choices[0].message.content = "mock-ok: llm-smoke local response"`. `docker compose logs llm-proxy`
  shows `"POST /v1/chat/completions HTTP/1.1" 200 OK`. `docker compose exec mcp env | grep -i anthropic`
  returns nothing — `ANTHROPIC_API_KEY` is confirmed absent from `mcp`.
- Failure path (exercised, not just claimed): wrong virtual key → `400`. Production `claude` model
  requested from `mcp` (which has no real Anthropic key) → `500 AnthropicException: Cannot connect to
  host api.anthropic.com:443 ... Temporary failure in name resolution` — proves no silent fallback to
  a working Anthropic route. Direct egress probe (`socket.create_connection` to `api.anthropic.com:443`
  from inside `mcp`) → `BLOCKED: Temporary failure in name resolution`. Both `llm-net` and `db-net`
  confirmed `Internal: true`.
- Matches the implementation handoff's claimed evidence pattern; independently reproduced with new
  probe calls, not copied output.

### R2 — LLM-triggering store path persists nodes in local Neo4j — PASS (runtime-reproduced)

- Ran `scripts/llm_smoke.py` unmodified inside the `mcp` container against the live stack with a fresh
  unique marker (`llm-smoke-27495683435b`, independent of the implementation's marker). `memory_store_message`
  returned `{"stored": true, ...}`; a direct Neo4j bolt read (`MATCH (n) WHERE n.content CONTAINS $marker`)
  found the node with the verbatim stored content. Script printed `R2 OK` and exited via `LLM_SMOKE_OK`
  (script exit code 0).
- Failure behaviour: the script's own `if record is None: return 1` path is the documented failure
  signature; not separately forced in this pass (same as implementation — a genuine miss would require
  breaking DB wiring, which is out of scope to sabotage). This is a minor gap noted below, not a fail
  (the happy-path node lookup itself is the direct, reproducible proof R2 asks for).

### R3 — Runtime offline embedder loads baked model, 384-dim vectors — PASS (runtime-reproduced)

- `docker compose exec mcp env` shows `HF_HUB_OFFLINE=1` and `TRANSFORMERS_OFFLINE=1`.
- In-container load of `BAAI/bge-small-en-v1.5` completed in ~0.25s (local cache, no network wait) with
  `dim=384`.
- Direct Neo4j read: `MATCH (n) WHERE n.embedding IS NOT NULL RETURN size(n.embedding)` → `384`; `SHOW
  VECTOR INDEXES` → 6 indexes, all `state: ONLINE`.
- Failure path independently exercised: with `HF_HUB_OFFLINE=0`/`TRANSFORMERS_OFFLINE=0` injected via
  `docker compose exec -e ...` and a deliberately uncached model tag, a **real** HF network attempt was
  made (`HEAD https://huggingface.co/...`) and failed with `Temporary failure in name resolution` —
  proving the offline flags are the mechanism suppressing that network attempt, not merely present and
  unused.

### R4 — Semantic vector search returns a paraphrase hit with no exact-token overlap — PASS (runtime-reproduced)

- Same `llm_smoke.py` run stored `"the falcon soared gracefully above the canyon at dawn."` and searched
  `"A bird glided elegantly over the gorge in early morning."` — manually confirmed these two sentences
  share zero exact significant tokens (falcon/bird, soared/glided, canyon/gorge, dawn/morning all differ).
  `memory_search` returned the stored message id/content with `similarity: 0.826`. Script printed `R4 OK`
  and `LLM_SMOKE_OK`.
- The token-disjoint property is the failure-path teeth here: a full-text/exact-token-only search
  implementation could not have produced this hit, so the pass is not achievable by a weaker
  implementation. This satisfies the spec's requirement that "The assertion must fail if exact-token/full-text
  matching is the only working path."

## Regressions

None observed. `docker-compose.yml`'s pre-existing `NEO4J_URI/USER/PASSWORD/DATABASE` wiring for `mcp`,
the production `claude` model in `litellm/config.yaml`, and the `mcp` Dockerfile's baked model are all
unchanged and still function as before (production `claude` route still correctly fails without a real
key, proving isolation is preserved, not broken by the new `claude-mock` addition).

## Specification defects

- **R2's Verification method has a minor evidence gap (not blocking):** the spec's stated verification
  method ("store... then use a direct Neo4j bolt/Cypher read to assert at least one node... exists")
  never actually requires exercising R2's own stated failure behaviour ("If LLM extraction, database
  wiring, or persistence fails, `memory_store_message` returns an error or the direct bolt read returns
  no matching node"). Neither the specification's verification method nor the implementation's evidence
  bundle forces a genuine broken-wiring run to prove the failure branch is real and not just asserted in
  prose. This is a `weak_verification` gap: the happy-path check passing does not yet prove the failure
  branch would be caught. It does not invalidate the reproduced happy-path evidence, so R2 remains a
  PASS on its stated method, but the verification method should be tightened (e.g. require one run
  against a temporarily wrong `NEO4J_URI` port to show `memory_store_message` errors or the bolt read
  returns no node) before this criterion can be considered airtight against silently-broken persistence.
- No other specification defects found. R1, R3, R4's verification methods are each evaluable without a
  judgement call and were reproduced exactly as written (including their failure behaviour).

## Implementation defects

None found. Every claimed evidence item in the implementation handoff was independently reproduced with
fresh inputs (new markers, new key values, new probe calls) rather than trusted from the handoff's
transcript, and every result matched (mock completion succeeds, Anthropic key absent, egress blocked,
Neo4j node persisted, offline embedder loads from cache with 384 dims, offline flags removal causes a
genuine network attempt, paraphrase search returns the token-disjoint hit).

## Failure classification table

| Failure | Type | Action / routing |
|---|---|---|
| R2 verification method doesn't force the failure branch to be exercised | `weak_verification` | Tighten R2's Verification method (gate 1 / §9) to require one run with broken Neo4j wiring showing `memory_store_message` error or empty bolt read, before it can be called airtight. Does not change this pass's PASS verdict for R2, which is based on the method as currently written. |

No `code_violation`, `contradictory_requirement`, `missing_evidence`, `new_constraint`, or
`unspecified_behaviour` failures were found — every requirement's stated verification method was met
with reproduced, non-summarized evidence tied to that specific requirement.

## Overall verdict: **PASS**

All four requirements (R1–R4) pass with independently reproduced runtime evidence, gathered via
`docker compose exec`/`docker compose logs` due to this sandbox's known host-port-publishing
limitation (verified independently, not merely trusted from the implementation handoff). One
non-blocking specification defect (`weak_verification` on R2's method) is logged for gate 6 to fold
back into the spec's §9 Verification method for R2.
