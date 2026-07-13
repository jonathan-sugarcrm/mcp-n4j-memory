# AGENTS.md — progress log

This file tracks agent-driven progress on this repository. Newest entries first.

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
