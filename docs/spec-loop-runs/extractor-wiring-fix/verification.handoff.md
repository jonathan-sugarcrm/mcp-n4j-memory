# Verification handoff: `extractor-wiring-fix`

Consumed: `specification.handoff.md`, `implementation.handoff.md`, and the actual
repository/running stack. All evidence below was **independently reproduced**
in this run (docker rebuilds, fresh `docker compose down -v` → `up`, fresh
markers) — nothing was accepted on the implementer's word alone.

## 1. Per-requirement verdict

| Req | Verdict | Check actually run | Observed result |
|---|---|---|---|
| REQ-1 | **FAIL** (process/boundary defect, not a code defect) | Read `docker-compose.yml:40-62` and `docker/mcp.Dockerfile:1-20` verbatim; ran `git status --short` and `git diff --stat` against the working tree. | Comments at `docker-compose.yml:48-51` and `:56-59`, and above the `pip install` line in `docker/mcp.Dockerfile`, match the implementation's quoted text exactly. `git diff --stat` is empty; `git status --short` shows only the new untracked `docs/spec-loop-runs/extractor-wiring-fix/` directory — zero functional change, confirmed. **However**, REQ-1's own "Expected observable outcome" is only satisfied by an edit to `SPECIFICATION.md` (a "Decision of record" bullet + moving the open item to Resolved). Inspecting `SPECIFICATION.md:562-577`/`:640-651` directly in this run shows **no such edit was made** — the file is byte-for-byte in its pre-slice state (confirmed: `git status --short` shows no `SPECIFICATION.md` change, and the text at those lines still reads "still open as a framework hygiene item" / "is not yet independently confirmed"). REQ-1's own literal pass condition ("Decision-of-record bullet present under Resolved items; open-item bullet removed or rephrased as closed") is therefore objectively **not met by code-stage output**, because the spec handoff itself assigned an outcome only Reconciliation (gate 6) is permitted to perform. This is a specification defect, not an implementation defect — see Classified failures. |
| REQ-2 | **PASS** | Independently reproduced from clean state: `docker compose down -v` → `NAM_LLM__MODEL=claude-mock docker compose up -d --build`; confirmed via `docker compose exec mcp env` that `NAM_LLM__MODEL=claude-mock`, `NAM_EXTRACTION__LLM_MODEL=claude-mock`, and no `GITHUB_API_KEY`/`ANTHROPIC_API_KEY` present; ran a fresh `memory_store_message` call (own unique marker, via `fastmcp.Client` from inside the `mcp` container, since host port 8080 is unpublished — independently confirmed via `docker compose port mcp 8080` → "no port 8080/tcp"); ran the exact `MENTIONS`-edge Cypher query plus `db.labels()`/`db.relationshipTypes()`/`count(n)` corroboration; ran `docker compose logs mcp \| grep -i extract`. | `STORE_RESULT` succeeded (`stored: true`); `MESSAGE_NODE` found with verbatim marker content; `MENTIONS_ENTITIES_COUNT: 0`, `MENTIONS_ENTITIES_RAW: []`; Neo4j itself emitted a GQL notice that the `MENTIONS` relationship type **does not exist at all** in the fresh database; `ALL_REL_TYPES` = `[HAS_MESSAGE, FIRST_MESSAGE]` only; `TOTAL_NODES: 2` (just `Conversation` + `Message`); mcp logs show `Stage 'LLMEntityExtractor' failed: Failed to parse LLM response as JSON: Expecting value: line 1 column 1 (char 0)`. This is an exact match to the implementation's claimed evidence, reproduced independently with a different marker/run. The falsifiable prediction (zero `MENTIONS`-linked entities on the mock path) holds, with the causal mechanism (JSON-parse failure on the fixed non-JSON `mock_response`) directly observed, not inferred. |

## 2. Missing evidence

None for REQ-2 — the evidence bundle was fully reproducible and was reproduced.

For REQ-1, the *mechanical* check (comments present, zero functional diff) has
full evidence and is not in question. What is missing is evidence that REQ-1's
own stated "Expected observable outcome" (the `SPECIFICATION.md` edit) was
delivered — because the spec handoff assigned that deliverable to the
Implementation stage while this run's operating boundary reserves
`SPECIFICATION.md` for Reconciliation only. That is a contradiction in the
requirement itself, not an evidence gap the implementer could have closed.

## 3. Regressions

None found. `docker-compose.yml`, `docker/mcp.Dockerfile`, and `litellm/config.yaml`
are unchanged (`git diff --stat` empty for all tracked files). No other slice's
passing behaviour (network isolation, `llm-smoke` R1/R3/R4, `github-models-llm-backend`,
`prod-anthropic-verify`) was touched or re-run in a way that could regress it —
correctly out of scope per the spec handoff §4, and this run did not exercise or
alter those paths.

## 4. Classified failures

| # | Failure | Type (per `SPEC_LOOP.md` §"Verification-failure classification") | Reasoning | Routing |
|---|---|---|---|---|
| F1 | REQ-1's "Expected observable outcome" and "Verification method" both require an edit to `SPECIFICATION.md` (moving an open item to Resolved, adding a Decision-of-record bullet) as an **Implementation**-stage deliverable. This directly conflicts with the isolation contract that reserves `SPECIFICATION.md` edits for Reconciliation (gate 6) only — the same class of defect previously identified in the `mcp-env-cleanup` slice. No agent operating within the stated role boundaries can satisfy REQ-1 as literally written without either (a) an Implementation-stage agent violating its own role boundary by writing to `SPECIFICATION.md`, or (b) the requirement being left unsatisfied at gate 4/5 by design. | **contradictory_requirement** | The requirement is not ambiguous or under-specified — it is internally consistent with itself but **structurally incompatible** with the SPEC_LOOP role separation (`SPECIFICATION.md` §10/§9 is gate-6-only). A requirement that can only be closed by an action forbidden to the stage assigned to close it is a contradiction between the requirement's own text and the process contract governing which stage may act on it. This is not "cannot be verified" (it is trivially verifiable — grep for the bullet) and not "unspecified behaviour" (the outcome is precisely specified); it is that the *specification itself* assigns an action to the wrong gate. | **gate 1** — the spec handoff for this slice (or the reusable spec-loop template used to generate REQ-1-shaped criteria) must be corrected so that any criterion whose "Expected observable outcome" is a `SPECIFICATION.md` edit is explicitly scoped as a **Reconciliation** (gate 6) deliverable, not an Implementation (gate 4) one — mirroring the fix already required for `mcp-env-cleanup`. Until gate 1 is corrected, REQ-1 cannot exit gate 5 as `pass` on the strength of Implementation-stage evidence alone; the actual `SPECIFICATION.md` edit must be verified separately once Reconciliation lands it. |
| — | (REQ-2) | No failure. | The falsifiable prediction held on independent reproduction, with the causal mechanism directly observed (not summarized). | n/a |

**Confirmation that the implementation correctly deferred, not silently
performed or silently skipped, the SPECIFICATION.md edit:** the implementation
handoff §5 records this exact conflict, proposes the verbatim text for gate 6
to land, and does not touch `SPECIFICATION.md` itself. Independently confirmed
here via `git status --short` (no `SPECIFICATION.md` diff) and by reading the
current file content at the cited lines (still pre-slice). This is the
**correct** behavior given the role-boundary conflict — the defect is in the
requirement's assignment of the edit to the wrong gate, not in how the
implementation handled the conflict.

## 5. Overall verdict

**FAIL** — REQ-2 is a clean, independently-reproduced PASS. REQ-1 fails only
because its own "Expected observable outcome" assigns a `SPECIFICATION.md` edit
to the Implementation stage, which this run's role boundaries (correctly)
reserve for Reconciliation — a `contradictory_requirement` defect in the spec
handoff, not a code defect. This must route back to **gate 1** to re-scope
REQ-1's deliverable boundary before the slice can close; Reconciliation (gate 6)
should still land the proposed `SPECIFICATION.md` text from the implementation
handoff §5 (independently re-derived from the REQ-2 evidence above, not merely
copied), since that text is itself correct and evidence-backed — but the
**loop is not closed** until gate 1 fixes the requirement-authoring defect so
future slices don't reproduce it (this is the third occurrence of this exact
defect class: `mcp-env-cleanup`, and now `extractor-wiring-fix`).

## 6. Independent reproduction log (for audit)

- Stack: fresh `docker compose down -v` → `NAM_LLM__MODEL=claude-mock docker compose up -d --build`; `neo4j` and `mcp` both reported `healthy`.
- Confirmed via `docker compose exec mcp env`: `NAM_LLM__MODEL=claude-mock`, `NAM_EXTRACTION__LLM_MODEL=claude-mock`, `OPENAI_BASE_URL=http://llm-proxy:4000/v1`; no `GITHUB_API_KEY`, no `ANTHROPIC_API_KEY` in the `mcp` environment.
- Confirmed host port 8080 unpublished (`docker compose port mcp 8080` → "no port 8080/tcp for container").
- Ran a scratch script (`verify_scratch_check.py`, repo root, `docker cp`'d into the `mcp` container, never committed) with a fresh unique marker distinct from the implementation's own run.
- `MENTIONS_ENTITIES_COUNT: 0`; Neo4j GQL notice confirms the `MENTIONS` relationship type does not exist in the database at all; `mcp` logs show the identical `LLMEntityExtractor`/JSON-parse failure line.
- Teardown: `docker compose down -v` (all containers/networks/volumes removed); `rm -f verify_scratch_check.py`; `git status --short` afterward shows only the pre-existing `docs/spec-loop-runs/extractor-wiring-fix/` artifact directory — no scratch files, no `.env`, no tracked-file diff.
