# Verification handoff — mcp-image-up

## Per-requirement verdict

| Requirement | Verdict | Check actually run | Observed result |
|---|---|---|---|
| R1 — Built image uses real framework MCP CLI and accepted serve options | PASS | Built current `docker/mcp.Dockerfile` as `mcp-n4j-memory:verify-mcpimage`; inspected image config; ran `docker run --rm --entrypoint neo4j-agent-memory mcp-n4j-memory:verify-mcpimage mcp serve --help`; ran unsupported `--backend`; ran configured startup against `bolt://127.0.0.1:1`. | Build completed from current Dockerfile. Inspect showed `Entrypoint=["neo4j-agent-memory","mcp","serve"]` and `Cmd=["--transport","http","--host","0.0.0.0","--port","8080","--profile","extended"]`. Help exited `0` and listed accepted serve options. `--backend` exited `2` with `Error: No such option '--backend'`. Configured startup did not show Click/`No such option`; it reached FastMCP then failed with `Neo4j service unavailable` against the intentionally bad URI. |
| R2 — Running `mcp` reaches both peers and exposes exactly extended tools | PASS | Created root-level `compose.verify.override.yml` overriding MCP host port to `127.0.0.1:18081:8080`, suppressing peer host ports, and using `mcp-n4j-memory:verify-mcpimage`; ran `docker compose -p mcp-image-up-verify ... up -d --no-build`; probed sockets from inside `mcp`; used `fastmcp.Client('http://127.0.0.1:8080/mcp')` to call `list_tools()`; exercised missing-network and `--profile core` failure paths. | Stack started; MCP logs showed `Starting MCP server 'neo4j-agent-memory' with transport 'http' on http://0.0.0.0:8080/mcp`. In-container probes printed `connect neo4j:7687 OK` and `connect llm-proxy:4000 OK`. `list_tools` returned exactly the sorted 16 names required, no extras/missing. Missing-network probes each exited `1` with DNS failure. Core profile returned only 6 tools and the exact-extended assertion exited `1`. |
| R3 — Local embedder baked and works offline with 384-dimensional vector | PASS | Ran `docker run --network none` with `HF_HUB_OFFLINE=1 TRANSFORMERS_OFFLINE=1` and `SentenceTransformer('BAAI/bge-small-en-v1.5', local_files_only=True)`; encoded a probe string and asserted `len(vec) == 384`; then tried an unbaked model offline. | Offline happy path loaded from cache and printed `vector_length= 384`, exit `0`. Unbaked model under `--network none` failed closed with `LocalEntryNotFoundError`/`couldn't connect to https://huggingface.co`, exit `1` on rerun. |

## Missing evidence

None. I reproduced each stated verification method and exercised failure behaviour for R1 (`--backend`), R2 (missing network and core profile), and R3 (unbaked model offline).

## Regressions

- `docker compose config --format yaml >/dev/null` exited `0`.
- `git status --short` after cleanup showed changes limited to `.env.example`, `docker-compose.yml`, `docker/mcp.Dockerfile`, and `docs/spec-loop-runs/mcp-image-up/`.
- Root-owned path check `find . -xdev -uid 0 -print` produced no entries.
- Cleanup completed: `docker compose -p mcp-image-up-verify ... down -v` exited `0`; root override `compose.verify.override.yml` removed; verify image tag `mcp-n4j-memory:verify-mcpimage` removed; no `mcp-image-up-verify` containers remained.

## Specification defects

None blocking. R1/R2/R3 are evaluable with mechanical pass/fail checks and trace to stated goals/constraints.

## Implementation defects

None blocking for this slice.

Non-blocking future-slice note: `docker-compose.yml` and `.env.example` still set `MCP_TRANSPORT`, `MCP_HOST`, and `MCP_PORT`, but the verified CLI receives transport/host/port through Dockerfile `CMD` flags rather than those env vars. This did not affect startup because the flags are correct, but the unused env wiring is potentially confusing.

## Overall verdict

PASS. Every in-scope requirement passed with independently reproduced evidence, failure paths were exercised, compose config still renders, cleanup completed, and no regressions or blocking spec/implementation defects were found.
