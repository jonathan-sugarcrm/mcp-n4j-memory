# AGENTS.md — progress log

This file tracks agent-driven progress on this repository. Newest entries first.

## Spec-loop pass: `prod-anthropic-verify` slice — PARTIAL (R2/R3/R4 verified against real Anthropic; R1 deferred)

Ran one full `docs/SPEC_LOOP.md` pass using the four separated roles (isolated contexts, 
artifact-only handoffs). Goal: provide the positive runtime proof that production 
memory-ingestion traffic is served by the REAL Anthropic model through the LiteLLM proxy 
(the last criterion left unverified after llm-smoke, which used a claude-mock stub). A real 
credential was supplied to llm-proxy only. Routing, isolation, and egress are now verified 
against real Anthropic; the positive completion remains blocked on credential type.

| Stage | Role | Result |
|-------|------|--------|
| 1 | Specification | Scoped R1–R4 against AC-C6/AC-G3. Found a real blocker: both compose networks are `internal: true`, so llm-proxy had no egress to api.anthropic.com. Raised Class-1 decision D1 (how to grant egress); operator chose Option A. |
| 2 | Implementation | Added a new non-internal `llm-egress-net` attached ONLY to llm-proxy (Option A); key sourced into llm-proxy only. Real Anthropic calls reached upstream (genuine request_ids, zero mock strings) but returned account-level errors; also made several out-of-plan changes (model-id bump, --detailed_debug, mcp extractor env, openai pip extra) and flagged two pre-existing extraction bugs. |
| 3 | Verification | Independent judge. Overall FAIL. R2 (real model reached), R3 (mcp key/egress-free), R4 (egress scoped to llm-proxy only, no AC-C5 regression) all PASS, independently reproduced from clean state. R1 NOT verified. Flagged scope creep: revert --detailed_debug; keep model-id (old id 404s) but record as decision; split extractor-wiring fix into its own slice. |
| 4 | Reconciliation | Reverted --detailed_debug; folded R2/R3/R4 PASS + R1 deferral into SPECIFICATION.md §9/§10; recorded model-id decision; split the extractor-wiring fix into a new recommended slice. |

### Requirements outcome
- **R2** — PASS: traffic reaches the real Anthropic API (genuine request_ids, no `mock-ok: llm-smoke local response` string).
- **R3** — PASS: mcp has no ANTHROPIC_API_KEY and cannot resolve/reach api.anthropic.com.
- **R4** — PASS: only llm-proxy gained the non-internal llm-egress-net; mcp/neo4j stay isolated; AC-C5 mutual-unreachability unchanged.
- **R1** — DEFERRED (not verified): no successful real completion produced.

### R1 blocker (root cause)
- The credential supplied is a claude.ai / Claude Code OAuth token, NOT an Anthropic API key. LiteLLM's anthropic/ provider authenticates to api.anthropic.com with an API key (sk-ant-api…) and cannot use an OAuth bearer token, so R1 cannot pass with this credential regardless of correct routing/egress. Closing R1 requires a real sk-ant-api… key supplied only to llm-proxy.

### Changes landed
- `docker-compose.yml` — added non-internal llm-egress-net attached only to llm-proxy (verified R4 egress mechanism); --detailed_debug reverted by Reconciliation.
- `docker/mcp.Dockerfile` — added openai pip extra (load-bearing extractor-wiring fix; split to its own slice for proper verification).
- `litellm/config.yaml` — production Anthropic model id updated from retired claude-3-5-sonnet-latest to a current id (old id 404s on live Anthropic).
- `docs/SPECIFICATION.md` — §9/§10 updated: routing/isolation resolved against real Anthropic; R1 restated as blocked on API-key-vs-OAuth; model-id decision recorded; new extractor-wiring-fix open item (with a weak_verification flag against llm-smoke).
- `docs/spec-loop-runs/prod-anthropic-verify/` — specification, implementation, verification (+ verification.report.yaml), and reconciliation handoffs.

### Next slices recommended
- `extractor-wiring-fix` — now actionable: the framework did not wire NAM_LLM__API_KEY/model into the extractor (pre-existing bug patched via OPENAI_API_KEY/NAM_EXTRACTION__LLM_MODEL/openai extra); needs its own spec-loop pass, and re-checks whether the prior llm-smoke PASS exercised real extractor wiring.
- `prod-anthropic-verify R1 re-run` — blocked pending a genuine sk-ant-api… Anthropic API key supplied only to llm-proxy.

## Spec-loop pass: `mcp-env-cleanup` slice — COMPLETE (loop closed, PASS)

Ran one full `docs/SPEC_LOOP.md` pass using the four separated roles (each isolated
context, artifact-only handoffs) from the `spec-loop` skill. Slice removed dead,
unconsumed MCP transport config (`MCP_TRANSPORT`/`MCP_HOST`/`MCP_PORT`) so the config
surface matches actual runtime behavior. Required one remediation loop after the
independent verifier caught a process/boundary defect.

| Stage | Role | Result |
|-------|------|--------|
| 1 | Specification | Scoped the slice; confirmed all three vars dead (docker-compose.yml env block, .env.example; transport/host/port actually come from hardcoded Dockerfile CMD flags). Amended at gate 1 during remediation to split REQ-2 into REQ-2a/REQ-2b. |
| 2 | Implementation | Removed the three vars from docker-compose.yml (REQ-1) and .env.example (REQ-2a); handoff later corrected so SPECIFICATION.md edits are not an Implementation deliverable. |
| 3 | Verification | Independent judge. First pass FAIL — content PASSED but Implementation had improperly edited docs/SPECIFICATION.md (reserved for Reconciliation). Two further passes narrowed then cleared the defect. Final verdict PASS. |
| 4 | Reconciliation | Adopted/owns the docs/SPECIFICATION.md §7/§10 edits (author of record for REQ-2b); folded the cleanup + defects into the spec; picked next slice. |

### Requirements verified (final PASS)
- **REQ-1** — `MCP_TRANSPORT`/`MCP_HOST`/`MCP_PORT` removed from docker-compose.yml mcp.environment; stack still builds/starts healthy on port 8080 (transport/host/port unchanged, sourced from Dockerfile CMD flags).
- **REQ-2a** — the three vars removed from .env.example (grep: zero live references).
- **REQ-2b** — docs/SPECIFICATION.md §7 dead-var row and §10 open item removed; single permitted §10 resolved-items changelog line remains; edit authored by the Reconciliation stage.

### Process defects found & remediated (value of separated roles)
- **contradictory_requirement** (gate 1) — spec handoff had bundled a gate-6-owned SPECIFICATION.md edit into Implementation's scope; fixed by splitting REQ-2 into REQ-2a (Implementation/.env.example) and REQ-2b (Reconciliation/SPECIFICATION.md).
- **weak_verification** (gate 1) — REQ-2b's grep-only check couldn't detect authorship; added a process/provenance check requiring the SPECIFICATION.md edit be evidenced in reconciliation.handoff.md.
- **handoff_inconsistency** (gate 2 artifact) — implementation.handoff.md still claimed the SPECIFICATION.md edit; corrected so its owned changes are only docker-compose.yml + .env.example, making the handoffs mutually consistent.

### Changes landed
- `docker-compose.yml` — removed `MCP_TRANSPORT`/`MCP_HOST`/`MCP_PORT` from the mcp service environment.
- `.env.example` — removed the MCP transport section and the three vars.
- `docs/SPECIFICATION.md` — removed the §7 table row and §10 open item; added a §10 resolved-items entry (authored by Reconciliation).
- `docs/spec-loop-runs/mcp-env-cleanup/` — specification, implementation, verification (+ verification.report.yaml), and reconciliation handoffs.

### Next slice recommended
`prod-anthropic-verify` — the only remaining unverified criterion (real Anthropic positive path), still blocked pending a real `ANTHROPIC_API_KEY` supplied only to llm-proxy. Non-blocked fallback: pin the exact neo4j-agent-memory framework and Anthropic model versions (§10, no credential needed).

## Spec-loop pass: `llm-smoke` slice — COMPLETE (loop closed)

Ran one full `docs/SPEC_LOOP.md` pass using the four separated roles (each in an
isolated context, artifact-only handoffs) from the `spec-loop` skill.

| Stage | Role | Result |
|-------|------|--------|
| 1 | Specification | Pre-existing. Re-scoped the slice to a LiteLLM `claude-mock` mock backend, removing the real-Anthropic-key blocker for local smoke. |
| 2 | Implementation | 5 files changed; requirements R1–R4 implemented with runtime evidence. |
| 3 | Verification | **PASS** — R1–R4 independently reproduced from a clean state. Found one specification defect (`weak_verification` on R2). No implementation defects. |
| 4 | Reconciliation | Folded PASS results + the R2 defect into `docs/SPECIFICATION.md`; loop closed. |

### Requirements verified (runtime, reproduced from clean state)
- **R1** — LLM routing/isolation is proxy-only: `claude-mock` returns 200 via LiteLLM; `mcp` has no `ANTHROPIC_API_KEY`; egress to Anthropic blocked; no fallback on wrong key.
- **R2** — LLM-triggering `memory_store_message` persists a queryable node in local Neo4j (verified via direct bolt read).
- **R3** — Runtime offline embedder: `HF_HUB_OFFLINE=1`/`TRANSFORMERS_OFFLINE=1`, baked `BAAI/bge-small-en-v1.5` loads from cache, 384-dim vectors, indexes ONLINE.
- **R4** — Semantic vector search returns a token-disjoint paraphrase hit (similarity 0.826).

### Changes landed
- `litellm/config.yaml` — added `claude-mock` model with `mock_response`.
- `docker-compose.yml` — added `HF_HUB_OFFLINE`/`TRANSFORMERS_OFFLINE` to `mcp`.
- `.env.example` — documented `claude-mock` local-smoke default + offline flags.
- `scripts/llm_smoke.py` — new smoke driver (store → bolt read → paraphrase search).
- `docs/SPECIFICATION.md` — §9 slice-status (AC-C6/AC-G3/AC-G2/AC-G5 runtime-verified via mock; real-Anthropic path deferred), §9.2 AC-G2 verification method tightened to force the failure branch, §10 open/resolved items updated.
- `docs/spec-loop-runs/llm-smoke/` — implementation, verification, and reconciliation handoffs + `verification.report.yaml`.

### Next slice recommended
`prod-anthropic-verify` — the only remaining unverified criterion (real Anthropic positive path), pending a credentialed key supplied only to `llm-proxy`.
