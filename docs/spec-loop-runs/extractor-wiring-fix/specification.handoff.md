# Specification handoff: `extractor-wiring-fix`

**Correction note (gate-1 amendment):** This handoff was amended to fix a `contradictory_requirement` defect — REQ-1's "Expected observable outcome" originally assigned `SPECIFICATION.md` edits to the Implementation stage, but such edits are reserved exclusively for Reconciliation (gate 6). This amendment reassigns the spec edits to Reconciliation; the CODE-level formalization (adopting the env-mirror workaround via code-level comments) remains Implementation's deliverable.

## 1. Slice

**id:** `extractor-wiring-fix`
**Outcome:** Formally record the env-mirror workaround for `create_llm_extractor()`'s
`NAM_LLM__*`-ignoring bug as the adopted (KEEP), not accidental, wiring — and
independently re-check, with a concrete Cypher-level evidence check, whether
`llm-smoke`'s mock-path PASS genuinely exercised the extractor's entity-creation
logic or only message persistence + proxy routing — then reconcile the two
currently-contradictory `SPECIFICATION.md` §10 bullets that both discuss this.

## 2. Normalized requirements

### REQ-1 — Adopt the env-mirror workaround as the recorded wiring strategy (KEEP)

- **Trigger:** This slice is executed.
- **Preconditions:** The workaround already ships and is proven working:
  `docker-compose.yml:45-59` sets `NAM_LLM__PROVIDER`/`NAM_LLM__MODEL`/`NAM_LLM__API_KEY`
  *and* mirrors `OPENAI_API_KEY: ${NAM_LLM__API_KEY:-change-me}` (line 53) and
  `NAM_EXTRACTION__LLM_MODEL: ${NAM_LLM__MODEL:-claude}` (line 59), with inline comments
  (lines 47-49, 56-58) already explaining *why* — because
  `create_llm_extractor()` reads `OPENAI_API_KEY` directly via the `openai` SDK and
  defaults `ExtractionConfig.llm_model` to `gpt-4o-mini`, never deriving either from
  `NAM_LLM__*`. `docker/mcp.Dockerfile:13` pins
  `neo4j-agent-memory[mcp,sentence-transformers,openai]==0.2.0` (the `openai` extra
  is part of the workaround). `SPECIFICATION.md:562-577` and `:640-645` already
  document the framework bug and the workaround, citing the vendored-source finding
  from `prod-anthropic-verify`. **The vendored package source itself is not present
  in this checkout** (`pip-scratch/` contains only the `mcp` SDK's dependency tree —
  no `neo4j_agent_memory` package — confirmed by directory listing); this requirement
  therefore relies on the documented finding in §10, not a re-read of the source.
- **Expected observable outcome (Implementation stage):** Formal adoption of the
  env-mirror workaround via code-level evidence: the comments already present in
  `docker-compose.yml:48-51` and `:56-59` (explaining *why* the mirror is necessary)
  and in `docker/mcp.Dockerfile` (documenting the `openai` extra) confirm the
  workaround is intentionally documented at the code level, not a silent duplication.
  Diff `docker-compose.yml`/`docker/mcp.Dockerfile` to confirm these comments are
  present and functional changes are zero — this signals code-level adoption of the
  workaround strategy.
  
  **NOTE: Edits to `SPECIFICATION.md` (adding a "Decision of record" bullet and moving
  the `extractor-wiring-fix` item from Open to Resolved) are REASSIGNED to the
  Reconciliation stage (gate 6) and must NOT be performed by Implementation.** The
  spec amendments are documented separately for Reconciliation to land them once
  REQ-2's independent evidence is in hand.
- **Failure behaviour:** If a future change deletes the `OPENAI_API_KEY` /
  `NAM_EXTRACTION__LLM_MODEL` mirror lines believing them to be redundant with
  `NAM_LLM__*` (since the vendored package is pinned and unpatched), the defined,
  documented failure is: `create_llm_extractor()` falls back to an unset
  `OPENAI_API_KEY` and the hardcoded `gpt-4o-mini` default, and the extraction stage
  errors or silently no-ops depending on how `memory_store_message` swallows
  per-stage extraction exceptions (per `SPECIFICATION.md:648-649`). This failure mode
  will be stated verbatim in the recorded decision during Reconciliation so it is
  not rediscovered.
- **Verification method (Implementation):** Diff `docker-compose.yml`/`docker/mcp.Dockerfile`
  against their current state to confirm zero functional changes and that the inline
  comments documenting the workaround's purpose remain present and intact.
- **Reconciliation deliverable (gate 6):** Add to `SPECIFICATION.md` §10 (Resolved items)
  a "Decision of record" bullet (styled like the existing GitHub-Models decision-of-record)
  stating explicitly: the env-mirror (`OPENAI_API_KEY`/`NAM_EXTRACTION__LLM_MODEL` mirroring
  `NAM_LLM__*`) is the **adopted, intentional** wiring for `create_llm_extractor()`, not a
  latent duplication bug. Move the `extractor-wiring-fix` item from "Open items" to "Resolved
  items" and fix the contradictory `weak_verification` text (once REQ-2 evidence confirms the
  mock path yields zero entity nodes, the spec should state precisely that `llm-smoke`'s R2/R4
  prove message persistence, proxy routing, and semantic search only — not structured entity
  extraction, which is proven by `prod-anthropic-verify` alone). Include the failure-behaviour
  statement above in the decision bullet.
- **Traces to:** §10 `extractor-wiring-fix` open item (`SPECIFICATION.md:562-577`,
  `:640-645`).

### REQ-2 — Resolve the `weak_verification` flag against `llm-smoke`'s mock-path R2

- **Trigger:** Re-checking whether `llm-smoke`'s mock-path PASS for R2 (and by
  extension AC-C6/AC-G3/AC-G2, per `SPECIFICATION.md:646-651`) genuinely exercised
  the extractor's LLM call path, or only message persistence.
- **Preconditions:**
  - `litellm/config.yaml:14` configures `claude-mock`'s `mock_response` as the fixed,
    non-JSON string `"mock-ok: llm-smoke local response"`.
  - `create_llm_extractor()`'s `LLMEntityExtractor` stage (wired via the
    `OPENAI_API_KEY`/`NAM_EXTRACTION__LLM_MODEL` mirror, REQ-1 above) expects a
    structured (JSON-like) completion it can parse into entity/event nodes — the
    POLE+O pattern (`Entity`/`Event`/`Location`/`Object`/`Time` nodes via `MENTIONS`
    edges) documented in `SPECIFICATION.md`'s `github-models-llm-backend`
    resolved-item bullet, which used a *real*, JSON-capable completion.
  - `docs/spec-loop-runs/llm-smoke/verification.report.yaml`'s R2 evidence only
    checked for the `Message` node itself with a verbatim `content` field
    (`"Neo4j node found for marker ... with verbatim content field"`) — it did not
    check for any `MENTIONS`-linked entity node, so it cannot distinguish "extraction
    ran and produced structured entities" from "extraction stage failed/no-opped and
    only the base message write succeeded."
  - `SPECIFICATION.md` currently contains **two contradictory statements** about this:
    line 570 claims the concern is already "resolved" by reasoning from
    `prod-anthropic-verify`'s real-backend evidence, while line 651 says it "is not
    yet independently confirmed and must be re-checked as part of
    `extractor-wiring-fix`." This requirement exists to close that contradiction with
    a concrete check rather than more reasoning-by-analogy.
- **Expected observable outcome:** A direct Cypher read against the running Neo4j
  instance, executed immediately after an `llm-smoke`-style `memory_store_message`
  call made against the mock (`claude-mock`) backend for a fresh unique marker,
  queries for entity/event nodes `MENTIONS`-linked from that message's node
  (e.g. `MATCH (m:Message {content: $marker_content})-[:MENTIONS]->(e) RETURN
  labels(e), e`, mirroring the bolt-read approach in `scripts/llm_smoke.py`). The
  query's actual result (node count and labels present/absent) is recorded verbatim
  as new evidence in this slice's verification report — this is the fact that
  resolves the flag, not further inference. **Predicted (not assumed) result,
  recorded here so the check is falsifiable:** because `claude-mock`'s
  `mock_response` is a fixed plain string, not machine-parseable JSON, the
  extractor is expected to fail to parse it into entities, so **zero** `MENTIONS`-
  linked entity nodes are expected for the mock-path marker. If that is what the
  query shows, `SPECIFICATION.md` is corrected to state precisely that
  `llm-smoke`'s R2/R4 PASS proves message persistence, proxy routing, and semantic
  search over the raw stored content only — **not** successful structured entity
  extraction, which remains proven only by `prod-anthropic-verify`'s real-backend
  run against GitHub Models.
- **Failure behaviour:** If the query instead finds genuine, distinct `MENTIONS`-
  linked entity nodes for the mock-path marker (the extractor successfully parsed or
  degraded-gracefully mapped the fixed mock string into entities), that is the
  defined alternate outcome: the original "resolved by reasoning" claim
  (`SPECIFICATION.md:570-578`) stands and is kept, and the "not yet independently
  confirmed" bullet (`:646-651`) is the one edited to record confirmation. Either
  way, the result — not a restatement of prior reasoning — is what gets written back,
  closing the loop per `docs/SPEC_LOOP.md`'s gate 6 (a note that changes neither code
  nor spec is not feedback).
- **Verification method:** Run the Cypher query above against a fresh
  `memory_store_message` call over `claude-mock` (clean-state preferred:
  `docker compose down -v` → fresh `up`, mirroring `llm-smoke`'s own reproduction
  method), capture the raw query output as the evidence item (not a summary), and
  record `result: pass|fail` with that evidence in `verification.report.yaml`. This
  supersedes the original R2 check's scope (message-node existence only) as the
  authoritative check for *entity-extraction* exercise; it does not replace or
  re-run R1/R3/R4 of `llm-smoke`, which are out of scope here (see §4).
- **Traces to:** §10 `weak_verification` flag against `llm-smoke`
  (`SPECIFICATION.md:646-651`); §9 AC-G2 (LLM-triggering persistence,
  `SPECIFICATION.md` §9).

## 3. Verification criteria

| Req | Single mechanical check (gate 4/5) | Pass condition |
|-----|--------------------------|-----------------|
| REQ-1 (Implementation) | Diff `docker-compose.yml`/`docker/mcp.Dockerfile` against current state; confirm inline comments explaining the env-mirror workaround are present; confirm zero functional changes. | Zero functional (non-comment/doc) diff in both files; comments documenting the workaround's purpose remain intact. |
| REQ-1 (Reconciliation, gate 6) | Grep `SPECIFICATION.md` for a "Decision of record" bullet naming the env-mirror workaround as adopted, and confirm no residual "open"/"still open as a framework hygiene item" phrasing remains for this item. | Decision-of-record bullet present under Resolved items with failure-mode statement; open-item bullet removed or rephrased as closed. |
| REQ-2 | Run the `MENTIONS`-edge Cypher query against a fresh mock-path `memory_store_message` call; capture raw output verbatim. | Evidence item present in `verification.report.yaml` for a distinct check id (e.g. `R2b`), `defect_type` resolved either to `pass` (with raw query evidence attached) — no requirement is marked `pass` without that verbatim evidence, per `docs/SPEC_LOOP.md`'s evidence-bundle rules. |

## 4. Explicit scope

**In scope (Implementation, gate 4/5):**
- Formal adoption of the env-mirror workaround as the intentional wiring strategy,
  demonstrated through code-level evidence: confirming the explanatory comments in
  `docker-compose.yml` and `docker/mcp.Dockerfile` are present and documenting the
  workaround's purpose, with zero functional changes to the files.
- Adding a targeted, mock-path Cypher check for `MENTIONS`-linked entity nodes to
  independently resolve the `weak_verification` flag against `llm-smoke`'s R2.

**In scope (Reconciliation, gate 6):**
- Recording the KEEP decision (env-mirror workaround = adopted wiring) in
  `SPECIFICATION.md`, moving the `extractor-wiring-fix` code-hygiene item from Open
  to Resolved, with a Decision-of-record bullet and failure-behaviour statement.
- Reconciling the two currently-contradictory §10 bullets
  (`SPECIFICATION.md:570-578` vs `:646-651`) into one consistent statement, backed by
  the new evidence from REQ-2 (explicitly stating that `llm-smoke`'s mock path proves
  message persistence and semantic search only, not structured entity extraction).

**Out of scope:**
- Editing `docs/SPECIFICATION.md` during the Implementation stage (gate 4/5) — such
  edits are reserved exclusively for Reconciliation (gate 6).
- Changing the LLM provider/GitHub Models configuration (`litellm/config.yaml`'s
  `claude`/`claude-anthropic` model entries), embeddings configuration, or any
  network/egress topology (`llm-egress-net`, `db-net`, `llm-net`) — these are owned by
  `github-models-llm-backend`/`prod-anthropic-verify` and untouched here.
- Patching the vendored `neo4j-agent-memory==0.2.0` package (the PATCH option) —
  not pursued; see §5, this is the Class-3 rationale for choosing KEEP.
- Changing `litellm/config.yaml`'s `claude-mock` `mock_response` content to make it
  JSON-shaped/entity-parseable purely to force a different REQ-2 result — the mock's
  current fixed-string shape is what REQ-2 investigates as-is; altering it to game
  the check would itself be a `weak_verification` regression.
- The real-Anthropic positive-completion path (separately tracked, low priority,
  blocked on credential type — unrelated to this slice).

## 5. Unresolved decisions

None — cleared at gate 2.

The KEEP vs PATCH code-hygiene choice was evaluated against the Class 1/2/3
procedure and resolved as **Class 3** (decide-and-record), not Class 1:
- *Reversibility test:* choosing KEEP now does not foreclose a later PATCH — the
  vendored package pin and the env-mirror are both still in place either way; this is
  a two-way door.
- *Blast-radius test:* the choice is internal-only (build/deploy configuration); it
  changes no externally observable contract, MCP tool surface, or public API.
- Recommendation: **KEEP** the env-mirror workaround as the supported wiring.
  Rationale: it is already shipped, verified working end-to-end against both a mock
  backend (`llm-smoke`) and a real backend (`github-models-llm-backend`,
  `prod-anthropic-verify`); patching a pinned third-party package
  (`neo4j-agent-memory==0.2.0`) at build time is comparatively fragile (a pip
  post-install patch/wrapper can silently break or diverge on the next version bump,
  and there is no local copy of the vendored source in this checkout to patch against
  — confirmed absent from `pip-scratch/`), for a purely cosmetic/hygiene gain.

## 6. Recorded facts & safe choices

- **Fact (Class 2):** The vendored `neo4j_agent_memory` package source is not present
  anywhere in this checkout for direct inspection — `pip-scratch/` contains only the
  `mcp` SDK's transitive dependency tree (confirmed via directory listing; no
  `neo4j_agent_memory` or `neo4j-agent-memory` directory found). This slice therefore
  relies on the documented finding already recorded in `SPECIFICATION.md:562-567`
  (from `prod-anthropic-verify`'s prior read of the vendored source) rather than a
  fresh read.
- **Fact (Class 2):** `litellm/config.yaml:14` configures `claude-mock`'s
  `mock_response` as the fixed plain string `"mock-ok: llm-smoke local response"` —
  not JSON. This is the concrete basis for REQ-2's falsifiable prediction (zero
  entity nodes expected from the mock path) rather than a restatement of the prior
  slice's reasoning-by-analogy.
- **Fact (Class 2):** `docker-compose.yml:45-59` and `docker/mcp.Dockerfile:13`
  already carry inline comments explaining the workaround's purpose; REQ-1's
  "Decision of record" outcome formalizes this in `SPECIFICATION.md` rather than
  introducing new comments, since the comments already meet the "not mistaken for a
  bug" bar at the code level.
- **Safe choice (Class 3):** Chose to reuse `scripts/llm_smoke.py`'s existing bolt-read
  pattern (direct Cypher query via the `neo4j` driver) for REQ-2's new check, rather
  than inventing a new tool or MCP-level assertion, because it is the established,
  already-working evidence-gathering mechanism for this exact stack
  (`docs/spec-loop-runs/llm-smoke/verification.report.yaml` R2/R4) — reversible, no
  contract impact, follows existing convention.
