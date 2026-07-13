# Verification handoff — stack-up

## Per-requirement verdict

| Requirement | Verdict | Check actually run | Observed result |
|---|---|---|---|
| STK-C1 — Neo4j data survives a container restart | PASS | With `NEO4J_PASSWORD=change-me LITELLM_MASTER_KEY=change-me ANTHROPIC_API_KEY=change-me`, ran `docker compose -p spec-loop-verify-stackup config --format json` and parsed it for `neo4j-data` volume mounted at `/data` plus `bolt://neo4j:7687`; started only `neo4j` and `llm-proxy`; waited for Neo4j healthy; wrote `(:SpecLoopProbe {id:"stk-c1-verify-20260713T131205", value:"written-before-restart"})` using in-container `cypher-shell`; ran `docker compose -p spec-loop-verify-stackup restart neo4j`; waited healthy; re-queried by id. Failure behaviour: rendered `docs/spec-loop-runs/stack-up/docker-compose.verify-mutated-volume.yml` with the `/data` volume renamed and ran the same config assertion. | Config showed `{'type': 'volume', 'source': 'neo4j-data', 'target': '/data'}` and `('mcp', 'NEO4J_URI', 'bolt://neo4j:7687')`. Re-query after restart returned `"stk-c1-verify-20260713T131205", "written-before-restart"`. Mutated-volume assertion exited `1` with `AssertionError: neo4j-data named volume not mounted at /data`, proving the missing/renamed named-volume failure path fails before runtime. |
| STK-C5-G4 — Neo4j and LiteLLM cannot reach each other | PASS | Parsed `docker compose -p spec-loop-verify-stackup config --format json` for network membership: `neo4j` only on `db-net`, `llm-proxy` only on `llm-net`, both networks internal, no shared networks. With both services running, first confirmed `llm-proxy` listened on `127.0.0.1:4000` inside its own container and Neo4j was healthy, then ran `neo4j` container probe `timeout 5 bash -lc "</dev/tcp/llm-proxy/4000"` and `llm-proxy` container probe `python -c 'import socket; socket.create_connection(("neo4j", 7687), timeout=5)'`. Failure behaviour: rendered a mutated compose with a shared network and ran the same no-shared-network assertion. | Config showed `neo4j networks=['db-net']`, `llm-proxy networks=['llm-net']`, both `internal=True`, and `shared networks=[]`. Runtime probes both failed: `neo4j -> llm-proxy:4000` failed with DNS error and exit `1`; `llm-proxy -> neo4j:7687` failed with `socket.gaierror: [Errno -3] Temporary failure in name resolution` and exit `1`. The checks have teeth because the target services/probe runtimes were live (`llm-proxy` local port check exited `0`, Neo4j accepted Cypher), and the probe scripts explicitly treat exit `0` as an isolation violation. Mutated shared-network assertion exited `1` with `AssertionError: neo4j and llm-proxy share a network`. |

## Missing evidence

None for the two in-scope requirements. Both verification methods were re-run independently, and both had failure behaviour exercised with temporary mutated compose files that were removed.

## Regressions

- `git --no-pager status --short` showed only the untracked `docs/spec-loop-runs/stack-up/` artifact directory; no source, compose, or configuration files were modified by the implementation slice.
- Final `docker compose -p spec-loop-verify-stackup config --format json >/dev/null` rendered cleanly.
- Cleanup verified no containers or volumes remained with names beginning `spec-loop-verify-stackup`; temporary mutated compose files were removed.

## Specification defects

- No blocking specification defects for STK-C1 or STK-C5-G4: both criteria are evaluable without a judgement call and trace to the stated constraints/goals.
- Non-blocking future-slice spec defect/ambiguity: `docs/SPECIFICATION.md` describes launching `mcp serve`, but the `neo4j-agent-memory==0.2.0` wheel exposes only the `neo4j-agent-memory = neo4j_agent_memory.cli:main` console script and contains `mcp serve` as a subcommand. Route to stage 1 for the deferred MCP-image slice; this does not affect this slice.

## Implementation defects

- No blocking implementation defects for STK-C1 or STK-C5-G4.
- Non-blocking future-slice implementation defect: `docker/mcp.Dockerfile` uses `ENTRYPOINT ["mcp", "serve"]`, while the PyPI wheel metadata for `neo4j-agent-memory==0.2.0` has no `mcp` console script (`has_mcp_console_script=False`) and does have `neo4j-agent-memory`. Route to stage 2 after the deferred MCP-image spec is corrected; this does not affect this slice.

## Overall verdict

PASS for the in-scope `stack-up` sub-slice. STK-C1 and STK-C5-G4 both passed with independently reproduced evidence, failure behaviour was exercised, no in-scope regressions were found, and verification cleanup completed.
