# Reconciliation handoff — mcp-image-up

## Spec edits made

| Section | What changed | Finding answered |
|---|---|---|
| §3.1 / §3.3 | Updated the `mcp` image/runtime description to install `neo4j-agent-memory[mcp,sentence-transformers]`, bake the offline model, and launch `neo4j-agent-memory mcp serve` with only accepted serve flags. | R1/R3 PASS: real console-script entrypoint works; `sentence-transformers` extra is required for the baked embedder. |
| §4 | Replaced false `--backend`, `--llm`, `--llm-api-base`, `--embedding`, and flat `NAM_*` wiring with the real `neo4j-agent-memory==0.2.0` surface: Neo4j via `NEO4J_*`, transport/profile via accepted `mcp serve` flags, HTTP path `/mcp`, LLM via nested `NAM_LLM__*` + `OPENAI_BASE_URL`, embedder via nested `NAM_EMBEDDING__*`. | R1 PASS and handoff facts: the CLI accepts only `--uri --user --password --database --transport --host --port --profile --session-strategy --user-id --observation-threshold --no-auto-preferences`; LLM/embedder settings are `MemorySettings` env, not flags. |
| §7 | Updated env-var table to nested `NAM_LLM__*` / `NAM_EMBEDDING__*`, added `OPENAI_BASE_URL`, and annotated `MCP_TRANSPORT` / `MCP_HOST` / `MCP_PORT` as compose/template-only dead env not consumed by the current CLI. | R2 PASS plus verification cleanup note: compose still sets MCP transport env, but Dockerfile `CMD` flags actually control startup. |
| §8 / §9 criteria | Corrected local-dev install extra and updated AC-C6/AC-G2 preconditions away from nonexistent flags. | Keeps the durable acceptance criteria aligned with the verified runtime wiring. |
| §9 slice-status note | Recorded that `mcp-image-up` runtime-verified AC-C3, AC-G1, the mcp-bridge half of AC-G4, and AC-C7; left only Anthropic-key-dependent AC-C6, AC-G3, and LLM-triggering AC-G2/AC-G5 for `llm-smoke`. | Verification verdict PASS for R2/R3 and explicit out-of-scope LLM criteria. |
| §10 | Removed the deferred ENTRYPOINT defect from open items, added it under resolved items, kept the framework/model confirmation and Anthropic-key blocker open, and added dead MCP transport env cleanup as future work. | R1 PASS resolves the open defect; non-blocking verification note is routed as cleanup. |

## Defects folded

| Verification finding / discovery | Disposition | Spec location |
|---|---|---|
| Deferred `mcp` image ENTRYPOINT defect is fixed. | Folded as resolved; spec now requires `neo4j-agent-memory mcp serve` and accepted flags only. | §3.3, §4, §10 Resolved items |
| Old `--backend`, `--llm`, `--llm-api-base`, `--embedding` flag mapping was false. | Corrected durable configuration mapping and related criteria. | §4, §7, AC-C6, AC-G2 |
| LLM config uses nested `NAM_LLM__*` plus `OPENAI_BASE_URL`; embedder uses nested `NAM_EMBEDDING__*`. | Folded into config mapping and env table. | §4, §7 |
| `sentence-transformers` extra is required for offline model bake/load. | Folded into image description and version placeholder. | §3.1, §3.3, §8, §10 |
| FastMCP HTTP endpoint path is `/mcp`. | Folded into the configuration mapping. | §4 |
| AC-C3, AC-G1, mcp half of AC-G4, and AC-C7 are now runtime-verified. | Folded into the slice-status note. | §9 |
| `MCP_TRANSPORT` / `MCP_HOST` / `MCP_PORT` are set but not consumed by the current CLI. | Annotated in env table and routed as non-blocking cleanup. | §7, §10 |

## Loop routing

| Item | Route | Status |
|---|---|---|
| AC-C6 — Anthropic backend via proxy | Stage 1 of final `llm-smoke` slice | BLOCKED until a real `ANTHROPIC_API_KEY` is securely available to `llm-proxy`. |
| AC-G3 — every LLM call routed through proxy | Stage 1 of final `llm-smoke` slice | BLOCKED on the same real Anthropic credential. |
| LLM-triggering parts of AC-G2 / AC-G5 | Stage 1 of final `llm-smoke` slice | BLOCKED on the same real Anthropic credential. |
| Cleanup dead `MCP_TRANSPORT` / `MCP_HOST` / `MCP_PORT` env wiring | Future cleanup implementation slice (stage 2 after a small stage-1 cleanup criterion) | Non-blocking; current service starts because Dockerfile `CMD` flags supply transport/host/port. |
| Framework version and Anthropic model-id confirmation | Future decision/confirmation before merge | Still open in §10. |

## Next slice

Recommended next slice: `llm-smoke`.

Rationale: it is the final runtime slice needed to verify AC-C6, AC-G3, and the LLM-triggering portions of AC-G2/AC-G5 end to end. It is explicitly blocked in this environment until a real `ANTHROPIC_API_KEY` is supplied securely to `llm-proxy`; placeholder credentials are sufficient only for the non-LLM checks already passed by `mcp-image-up`.
