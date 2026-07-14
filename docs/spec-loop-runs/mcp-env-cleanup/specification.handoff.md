# Specification handoff — `mcp-env-cleanup`

**Correction note:** This handoff was amended at gate 1 to fix two defects found by the independent verifier (contradictory_requirement and weak_verification). See edits to REQ-2 and §5 below.

## 1. Slice

**Slice id:** `mcp-env-cleanup`

**One-sentence outcome:** Remove the dead `MCP_TRANSPORT`, `MCP_HOST`, and `MCP_PORT`
environment wiring from `docker-compose.yml` and `.env.example` (and the corresponding
row of `docs/SPECIFICATION.md` §7) so the documented config surface matches what the
running `mcp` service actually consumes, with no change to runtime transport/host/port
behaviour (which remains fixed by `docker/mcp.Dockerfile`'s `CMD` flags).

## 2. Investigation findings (grounding)

- `docker-compose.yml:52-54` — the `mcp` service's `environment:` block sets
  `MCP_TRANSPORT: ${MCP_TRANSPORT:-http}`, `MCP_HOST: ${MCP_HOST:-0.0.0.0}`,
  `MCP_PORT: ${MCP_PORT:-8080}`.
- `.env.example:27-29` — documents the same three vars under a `# --- MCP transport
  (consumed by: mcp) ---` comment, defaulting to `http` / `0.0.0.0` / `8080`.
- `docker/mcp.Dockerfile` — `ENTRYPOINT ["neo4j-agent-memory", "mcp", "serve"]` and
  `CMD ["--transport", "http", "--host", "0.0.0.0", "--port", "8080", "--profile",
  "extended"]`. Transport/host/port are supplied as **hardcoded CLI flags**, not read
  from environment. There is no shell wrapper or entrypoint script in this repo that
  forwards `MCP_TRANSPORT`/`MCP_HOST`/`MCP_PORT` into those flags.
- `docker-compose.yml`'s `mcp.ports:` mapping is the literal string `"8080:8080"` — it
  does not interpolate `${MCP_PORT}` either, so even the host port publish is
  independent of the var.
- No source code lives in this repo for the `neo4j-agent-memory` framework (it is
  installed as a pinned pip package, `neo4j-agent-memory[mcp,sentence-transformers]
  ==0.2.0`, in `docker/mcp.Dockerfile`); its CLI (`neo4j-agent-memory mcp serve
  --help`, per prior slices' framework inventory) does not document `MCP_TRANSPORT`,
  `MCP_HOST`, or `MCP_PORT` as recognized environment variables — the framework's own
  env-driven config uses the `NAM_*` prefix (see `docs/SPECIFICATION.md` §7), not `MCP_*`.
- `docs/SPECIFICATION.md:219` (§7 config table) already states, as a recorded fact:
  *"Currently not consumed by `neo4j-agent-memory mcp serve`; transport/host/port are
  supplied by Dockerfile `CMD` flags. Retained only until cleanup removes the dead env
  wiring."*
- `docs/SPECIFICATION.md:464-468` (§10 Open questions) already lists this exact cleanup
  as an open item: *"Cleanup dead MCP transport env... Remove the dead env wiring or
  introduce an explicit wrapper if env-driven transport remains desired."*
- No other file in the repo references `MCP_TRANSPORT`, `MCP_HOST`, or `MCP_PORT`
  (confirmed via a whole-repo grep; only the three locations above and the two
  `docs/SPECIFICATION.md` prose references match).

**Conclusion:** all three vars are confirmed **genuinely dead** — set and documented,
but never read by the running `mcp` process. This is a pure config-cleanup slice; no
runtime behaviour of the `mcp` service depends on them today.

## 3. Normalized requirements

### REQ-1 — Dead env vars removed from runtime wiring

- **Trigger:** `docker compose config` is rendered for the `mcp` service (and, for
  local dev, `docker compose up` brings the stack up).
- **Preconditions:** `docker-compose.yml`'s `mcp.environment:` block no longer declares
  `MCP_TRANSPORT`, `MCP_HOST`, or `MCP_PORT`.
- **Expected observable outcome:** The rendered `mcp` service config (from
  `docker compose config`) contains zero keys named `MCP_TRANSPORT`, `MCP_HOST`, or
  `MCP_PORT`. The stack still builds, and `mcp` still starts, becomes healthy, and
  serves MCP transport on `0.0.0.0:8080` exactly as before (transport/host/port
  continue to be supplied solely by `docker/mcp.Dockerfile`'s `CMD` flags, which are
  explicitly out of scope for this slice and must remain unchanged).
- **Failure behaviour:** If removing the env keys causes `mcp` to fail to start, fail
  its healthcheck, or stop serving on `8080`, that is proof the vars were **not** dead
  and this requirement fails closed — the removal must be reverted and the var
  reclassified as consumed (a spec defect in the §7 table, to be routed back to gate 1).
- **Verification method:** (a) `docker compose config` on the edited
  `docker-compose.yml`, grepped for `MCP_TRANSPORT|MCP_HOST|MCP_PORT`, returns no
  matches for the `mcp` service. (b) `docker compose up -d mcp` (with its
  dependencies) reaches healthy state (`docker compose ps` shows `mcp` as
  `healthy`/`running`) and a TCP connect to `mcp:8080` (or published `localhost:8080`)
  succeeds, unchanged from pre-cleanup behaviour.
- **Traces to:** G6 (thin, declarative delta — no dead/unused config in the owned
  delta) and, as supporting evidence of no behavioural regression, AC-C2 / AC-C4's
  "config lint" verification method (service still present, healthy, and exposes only
  the documented port set). §10 open item "Cleanup dead MCP transport env" is the
  direct source of this requirement (no pre-existing `AC-G*`/`AC-C*` id covers it
  directly; it is a §10-sourced cleanup, cross-traced to G6 as above).

### REQ-2 — Documented config surface matches actual consumption

#### REQ-2a: Implementation stage — remove dead vars from `.env.example`

- **Trigger:** A reader consults `.env.example` to determine which environment
  variables the `mcp` service actually consumes.
- **Preconditions:** `.env.example`'s `# --- MCP transport (consumed by: mcp) ---`
  block and its three var lines are removed by the Implementation stage.
- **Expected observable outcome:** `.env.example` contains zero occurrences of
  `MCP_TRANSPORT`, `MCP_HOST`, or `MCP_PORT`.
- **Failure behaviour:** If any of the three var names remain in `.env.example`, the
  requirement fails.
- **Verification method:** `grep -n "MCP_TRANSPORT\|MCP_HOST\|MCP_PORT" .env.example` —
  the check passes only if there are zero matches.
- **Traces to:** G6 (thin/declarative delta) and the §10 open item "Cleanup dead MCP
  transport env" directly.

#### REQ-2b: Reconciliation stage (gate 6) — update `docs/SPECIFICATION.md` §7 table and §10 items

- **Trigger:** The Reconciliation agent (stage 4, gate 6) reviews and closes the slice
  after Implementation succeeds.
- **Preconditions:** After Implementation lands REQ-1 and REQ-2a, the Reconciliation
  agent edits `docs/SPECIFICATION.md` to:
  - Remove the `MCP_TRANSPORT` / `MCP_HOST` / `MCP_PORT` row from §7's config table
    (since after REQ-1 the vars no longer exist in the stack and the "retained until
    cleanup" row becomes a stale artifact).
  - Remove the §10 open item "Cleanup dead MCP transport env".
  - Add a one-line entry to §10 "Resolved items" recording that the dead wiring was
    removed in this slice.
- **Expected observable outcome:** `docs/SPECIFICATION.md` contains zero occurrences
  of `MCP_TRANSPORT`, `MCP_HOST`, or `MCP_PORT` outside of a single designated §10
  "Resolved items" changelog line for this slice.
- **Failure behaviour:** If any of the three var names remain in a live (non-changelog)
  table/prose row, the requirement fails.
- **Verification method:** Two checks: (1) content check: `grep -n
  "MCP_TRANSPORT\|MCP_HOST\|MCP_PORT" docs/SPECIFICATION.md` — passes only if all
  matches fall strictly within the one §10 "Resolved items" line (verified by manual
  line-context inspection); (2) process/provenance check: confirm that the
  `docs/SPECIFICATION.md` edits are authored by the Reconciliation stage, evidenced
  by an entry in `reconciliation.handoff.md` for this slice (i.e., no implementation-stage
  diff touches `docs/SPECIFICATION.md` — the file remains read-only to Implementation).
- **Traces to:** G6 (thin/declarative delta) and the §10 open item "Cleanup dead MCP
  transport env" directly (reconciliation is the responsible stage for translating
  verified work into the durable specification contract).

## 4. Verification criteria (restated, mechanical)

| Req | Check | Pass condition |
|-----|-------|-----------------|
| REQ-1 | `docker compose config` (rendered `mcp` service) grepped for the three var names | Zero matches |
| REQ-1 | `docker compose up -d` full stack; `docker compose ps` + TCP connect to `mcp:8080` | `mcp` healthy/running; port 8080 accepts a connection, matching pre-change behaviour |
| REQ-2a | `grep -n "MCP_TRANSPORT\|MCP_HOST\|MCP_PORT" .env.example` | Zero matches |
| REQ-2b | `grep -n "MCP_TRANSPORT\|MCP_HOST\|MCP_PORT" docs/SPECIFICATION.md` | All matches confined to one §10 "Resolved items" changelog line (manual context verification) |
| REQ-2b | Reconciliation handoff entry exists and confirms `docs/SPECIFICATION.md` edit authorship | `reconciliation.handoff.md` documents the §7/§10 edits for this slice |

## 5. Explicit scope

**In scope for Implementation (stage 2):**
- Removing the `MCP_TRANSPORT`, `MCP_HOST`, `MCP_PORT` entries from
  `docker-compose.yml`'s `mcp.environment:` block.
- Removing the corresponding three lines (and their comment header, if it becomes
  empty/orphaned) from `.env.example`.
- Confirming (verification only, not a code change) that `mcp` continues to serve on
  `0.0.0.0:8080` via the Dockerfile `CMD` flags, unaffected by the removal.

**In scope for Reconciliation (stage 4, gate 6):**
- Removing the `MCP_TRANSPORT` / `MCP_HOST` / `MCP_PORT` row from
  `docs/SPECIFICATION.md` §7's config table.
- Resolving the §10 "Cleanup dead MCP transport env" open item — moving it to
  "Resolved items" with a one-line note of what was removed and why (per SPEC_LOOP.md
  gate 6's "results must move code or spec").

**Out of scope:**
- Editing `docs/SPECIFICATION.md` (reserved exclusively for Reconciliation/gate 6;
  Implementation must not mutate the contract).
- Any change to `docker/mcp.Dockerfile`'s `CMD`/`ENTRYPOINT` (transport/host/port
  remain hardcoded flags; introducing an env-driven wrapper is explicitly **not** part
  of this slice — see Unresolved decisions below).
- Any other environment variable in `docker-compose.yml` or `.env.example` (e.g.
  `NAM_*`, `NEO4J_*`, `HF_HUB_OFFLINE`, `LITELLM_MASTER_KEY`, `ANTHROPIC_API_KEY`).
- Any change to the `mcp` service's published port mapping (`"8080:8080"` in
  `docker-compose.yml`) — it is already a literal, not `${MCP_PORT}`-derived.
- Any change to §9 acceptance criteria (`AC-C*`/`AC-G*`) beyond what REQ-1/REQ-2 above
  specify; no new `AC-*` id is being minted for this cleanup since none pre-exists and
  none is required by the exit-check (traces to `G6` are sufficient).
- The deferred "real-Anthropic positive path" and any other unrelated §10 open item.

## 6. Unresolved decisions

**None — cleared at gate 2.**

Rationale for why this did not escalate to Class 1: the only plausible either/or is
"remove the dead vars" vs. "keep them and wire an env-driven transport wrapper into
`docker/mcp.Dockerfile`." The slice scope handed to this stage (per the task framing
and the pre-existing §10 wording, which already frames the choice as "remove... **or**
introduce an explicit wrapper if env-driven transport remains desired") explicitly
selects the removal path for this slice and defers the wrapper alternative as a
*separate, not-yet-scoped* future slice. Since the task scope statement fixes this
choice for the current slice, it is not a live product decision within this pass —
there is no legitimate in-slice either/or left to ask a stakeholder about. If a future
slice wants env-driven transport, that is a new slice with its own spec pass, not a
reopening of this one.

## 7. Recorded facts & safe choices

- **Fact (Class 2):** `docker/mcp.Dockerfile`'s `CMD` hardcodes `--transport http
  --host 0.0.0.0 --port 8080`; these flags — not any env var — determine the running
  transport/host/port. Citation: `docker/mcp.Dockerfile` (`CMD` instruction).
- **Fact (Class 2):** The `neo4j-agent-memory` framework's env-driven config uses the
  `NAM_*` prefix (e.g. `NAM_LLM__PROVIDER`, `NAM_EMBEDDING__MODEL`), not `MCP_*`; no
  `MCP_TRANSPORT`/`MCP_HOST`/`MCP_PORT` binding exists in the framework's documented
  interface as captured in `docs/SPECIFICATION.md` §7. Citation:
  `docs/SPECIFICATION.md:219` (existing recorded fact) plus the whole-repo grep in
  §2 above finding no consuming code.
- **Fact (Class 2):** The `mcp` service's `ports:` mapping in `docker-compose.yml` is
  the literal `"8080:8080"`, not `"${MCP_PORT}:${MCP_PORT}"` — so removing
  `MCP_PORT` cannot affect the published host port. Citation: `docker-compose.yml`
  (`mcp.ports:` key).
- **Safe choice (Class 3):** Remove the §7 table row entirely rather than leaving a
  stub/placeholder row. Chose removal over a stub because the row's only content
  ("not consumed... retained only until cleanup") becomes false the instant the vars
  are deleted — leaving it would itself be a fresh case of docs/reality drift, which
  is the exact defect this slice exists to fix. Reversible (a future slice can always
  re-add a row if a wrapper is introduced).
- **Safe choice (Class 3):** Record the removal as a new §10 "Resolved items" entry
  rather than opening a fresh §10 line elsewhere. Chose this because it matches the
  existing pattern already used by prior slices (`llm-smoke`, `docker-compose`) for
  folding closed work back into §10, per `SPEC_LOOP.md` gate 6 and the
  `spec-loop`/`reconciliation-agent` contract. Reversible, no contract impact.
