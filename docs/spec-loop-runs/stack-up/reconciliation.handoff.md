# Reconciliation handoff — stack-up

## Spec edits made

- **§3.3 / §4 / §7 / §8 command wiring** → clarified that the executable console script is `neo4j-agent-memory` and the MCP server command is `neo4j-agent-memory mcp serve`, including the local-dev `uvx --from "neo4j-agent-memory[mcp]" neo4j-agent-memory mcp serve …` form → answers the non-blocking `mcp serve` specification ambiguity.
- **§9 slice-status note** → recorded that `stack-up` runtime-verified AC-C1 at the DB/container layer and AC-C5 plus the DB↔LLM-proxy half of AC-G4; recorded the remaining `mcp`-image/runtime and Anthropic-key-dependent criteria as deferred → answers the PASS findings and preserves pending scope.
- **§10 open questions / future work** → added the deferred `docker/mcp.Dockerfile` ENTRYPOINT correction with wheel-metadata evidence and added the real-`ANTHROPIC_API_KEY` precondition for LLM-dependent runtime verification → answers both future-slice defects/blockers.

## Defects folded

| Verification finding | Where it landed in the spec |
|---|---|
| STK-C1 PASS: named `neo4j-data` volume survived a Neo4j restart at DB/container layer. | §9 slice-status note. |
| STK-C5-G4 PASS: `neo4j` and `llm-proxy` cannot reach each other; DB↔LLM half of AC-G4 proven. | §9 slice-status note. |
| Spec ambiguity: text said `mcp serve`, but the wheel exposes console script `neo4j-agent-memory` with `mcp serve` as its subcommand. | §3.3, §4, §7, §8 command wording. |
| Implementation defect: `docker/mcp.Dockerfile` uses `ENTRYPOINT ["mcp", "serve"]`; wheel metadata has no `mcp` console script. | §10 deferred `mcp` image ENTRYPOINT defect. |
| Class-1 blocker: AC-C6/AC-G3 and LLM-triggering AC-G2/AC-G5 checks need a real Anthropic key. | §9 slice-status note and §10 LLM-dependent runtime verification blocker. |

## Loop routing

| Future-slice defect / blocker | Route |
|---|---|
| `docker/mcp.Dockerfile` ENTRYPOINT must change from `ENTRYPOINT ["mcp", "serve"]` to the `neo4j-agent-memory mcp serve` console-script invocation. | Stage 2 of the future `mcp-image-up` slice. |
| §4/§8 command wording was clarified to the real CLI; future `mcp`-image criteria should consume that corrected contract. | Stage 1 of the future `mcp-image-up` slice. |
| Anthropic-key blocker for AC-C6/AC-G3 and LLM-triggering AC-G2/AC-G5 runtime checks. | Stage 1 of a later `llm-smoke` slice, after a real `ANTHROPIC_API_KEY` is available. |

## Next slice

Recommend **`mcp-image-up`**: build and run the `mcp` image, fix the ENTRYPOINT, and runtime-verify AC-C3, AC-G1, the `mcp`-bridge half of AC-G4, and AC-C7 offline embedder without needing an Anthropic key; leave AC-C6/AC-G3 and LLM-triggering AC-G2/AC-G5 for a final **`llm-smoke`** slice.
