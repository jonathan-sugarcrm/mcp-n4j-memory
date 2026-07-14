# Implementation handoff — `mcp-env-cleanup`

Consumed only `docs/spec-loop-runs/mcp-env-cleanup/specification.handoff.md`. No other
stage's reasoning was read.

**Correction note (post-gate-1 amendment):** The specification was amended at gate 1 to
split the original REQ-2 into REQ-2a (Implementation: remove dead vars from
`.env.example`) and REQ-2b (Reconciliation, gate 6: exclusively edit
`docs/SPECIFICATION.md` §7/§10). The edit to `docs/SPECIFICATION.md` is authored and
owned by the Reconciliation stage; it is **not** an Implementation deliverable and has
been removed from this handoff's recorded changes (see §2 below). See
`reconciliation.handoff.md` for authorship evidence and final edits to `docs/SPECIFICATION.md`.

## 1. Implementation plan

1. Remove the `MCP_TRANSPORT` / `MCP_HOST` / `MCP_PORT` lines from `docker-compose.yml`'s
   `mcp.environment:` block -> verify: `docker compose config` grepped for the three names
   returns zero matches for the rendered config.
2. Remove the `# --- MCP transport (consumed by: mcp) ---` header and its three var lines
   from `.env.example` -> verify: `grep -n "MCP_TRANSPORT\|MCP_HOST\|MCP_PORT" .env.example`
   returns zero matches.
3. Confirm no runtime regression: `docker compose up -d` the full stack and check `mcp`
   reaches `healthy` and accepts a TCP connection on `8080` -> verify: `docker compose ps`
   + TCP connect, unchanged from pre-cleanup behaviour.

Dependencies: steps 1–2 are independent file edits (no ordering constraint); step 3
depends on steps 1–2 but was run after all edits landed to validate the whole change set
together.

**Note:** The `docs/SPECIFICATION.md` edits (§7 config table row removal, §10 open-item
resolution, and Resolved-items entry) are **not** part of Implementation's scope; these
are reserved exclusively for the Reconciliation stage (REQ-2b, per the gate-1 amendment
to the specification). See `reconciliation.handoff.md` for those edits.

## 2. Changed files

| File | Reason |
|------|--------|
| `docker-compose.yml` | REQ-1 — removed the three dead `mcp.environment:` entries (`MCP_TRANSPORT`, `MCP_HOST`, `MCP_PORT`) so the rendered service config no longer declares unread vars. |
| `.env.example` | REQ-2a — removed the `# --- MCP transport (consumed by: mcp) ---` header and its three var lines so the documented config surface matches actual consumption. |

No other file was touched. `docker/mcp.Dockerfile` (CMD/ENTRYPOINT), the `mcp.ports:`
mapping, and every other env var were left unchanged, per the handoff's explicit
out-of-scope list.

**Note:** The `docs/SPECIFICATION.md` edits (§7 table row, §10 open-item resolution,
and Resolved-items entry) are reserved exclusively for Reconciliation (REQ-2b). See
`reconciliation.handoff.md` for the authorship and final state of those changes.
## 3. Decision log

- Chose to remove the now-empty blank line left by the deleted `.env.example` block by
  collapsing directly from `TRANSFORMERS_OFFLINE=1` to the next section header (no dangling
  double-blank-line), matching the file's existing one-blank-line-between-sections
  convention — reversible, cosmetic only, no contract impact.
- Chose to create a throwaway local `.env` (copied from the edited `.env.example`) solely to
  run `docker compose up`/`docker compose config` for verification, and deleted it afterward
  along with tearing down the stack (`docker compose down -v`) — reversible, leaves no
  residue in the repo or on disk beyond the intended file edits (confirmed via `git status
  --short` showing only the two intended files modified plus this new handoff directory).

**Note:** Decisions about `docs/SPECIFICATION.md` edits (choice of row removal vs. stub,
placement of resolved-items entry) were deferred to the Reconciliation stage (REQ-2b).
See `reconciliation.handoff.md` §2 for those decisions and the reasoning.
## 4. Evidence bundle

| Requirement | Evidence | Result |
|-------------|----------|--------|
| REQ-1 — rendered `mcp` service config contains zero `MCP_TRANSPORT`/`MCP_HOST`/`MCP_PORT` keys | **Command:** `docker compose config 2>&1 \| grep -n "MCP_TRANSPORT\|MCP_HOST\|MCP_PORT"; echo "grep_rc=$?"` → output: `grep_rc=1` (ripgrep/grep convention: exit code 1 = no lines matched). Full rendered `mcp.environment:` block from `docker compose config`: `HF_HUB_OFFLINE: "1"`, `NAM_EMBEDDING__DIMENSIONS: "384"`, `NAM_EMBEDDING__MODEL: BAAI/bge-small-en-v1.5`, `NAM_EMBEDDING__PROVIDER: sentence_transformers`, `NAM_LLM__API_KEY: change-me`, `NAM_LLM__MODEL: claude-mock`, `NAM_LLM__PROVIDER: openai`, `NEO4J_DATABASE: neo4j`, `NEO4J_PASSWORD: change-me`, `NEO4J_URI: bolt://neo4j:7687`, `NEO4J_USER: neo4j`, `OPENAI_BASE_URL: http://llm-proxy:4000/v1`, `TRANSFORMERS_OFFLINE: "1"` — 13 keys, none named `MCP_*`. | PASS |
| REQ-1 — `mcp` still starts, reaches healthy, and serves on `0.0.0.0:8080` unchanged (failure behaviour: if removal broke startup/health/port, revert and reclassify) | **Command sequence:** `docker compose up -d --build` → `Container mcp-n4j-memory-mcp-1  Started`; `sleep 20 && docker compose ps` → `mcp-n4j-memory-mcp-1  ...  Up 36 seconds (healthy)` (neo4j and llm-proxy also up/healthy). `docker compose logs mcp --tail 30` → `INFO Starting MCP server 'neo4j-agent-memory' with transport 'http' on http://0.0.0.0:8080/mcp` then `INFO: Uvicorn running on http://0.0.0.0:8080`. TCP probe: `curl -s -o /dev/null -w "http_code=%{http_code}\n" --max-time 5 http://localhost:8080/` → `http_code=426` (Upgrade Required — expected for a non-MCP-protocol HTTP GET against the FastMCP HTTP transport endpoint, proving the socket accepts and the app responds); `exec 3<>/dev/tcp/localhost/8080` → `TCP connect to localhost:8080 succeeded`. Torn down cleanly afterward: `docker compose down -v` → all 3 containers/2 networks/1 volume `Removed`, no errors. No revert was needed — the vars were confirmed dead, matching the spec's investigation. | PASS |
| REQ-2a — `.env.example` contains zero occurrences of the three var names | **Command:** `grep -n "MCP_TRANSPORT\|MCP_HOST\|MCP_PORT" .env.example` → zero matches (exit code 1 = no lines matched). | PASS |

**Note on REQ-2b (docs/SPECIFICATION.md edits):** The content-level check (grep for the
three var names, all confined to §10 Resolved-items) and the process/provenance check (verify
Reconciliation-stage authorship via `reconciliation.handoff.md`) are documented in the
Reconciliation stage's handoff, not here. See `reconciliation.handoff.md` §4 for REQ-2b
verification evidence.

**Repo-wide sweep (supporting, not a gate-1 requirement):** `grep -rln "MCP_TRANSPORT\|MCP_HOST\|MCP_PORT" .` after the edits still matches prior slices' archived handoffs under `docs/spec-loop-runs/{llm-smoke,docker-compose,mcp-image-up}/*.handoff.md` and their frozen `run-a-single/docker-compose.yml` snapshot — these are historical artifacts from earlier stages, explicitly out of scope (the handoff only requires cleanup of the live `docker-compose.yml` and `.env.example`), and were left untouched.

## 5. Blocking spec defects

None. The handoff's requirements, scope, and verification methods were unambiguous and
fully executable in this environment; Docker was available, so both the `docker compose
config` and `docker compose up` verification methods were run for real rather than recorded
as a limitation.
