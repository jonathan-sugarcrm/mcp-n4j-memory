# Specification handoff — `pin-framework-version`

## 1. Slice

`pin-framework-version` — confirm (or correct) the exact `neo4j-agent-memory` version
pin and extras in `docker/mcp.Dockerfile` against the real PyPI package state, and
confirm the Anthropic model-id policy (§10) stays a floating fact rather than a fixed
literal, so the §10 "needs confirmation" caveat on the framework pin can be resolved
with evidence.

## 2. Normalized requirements

### PIN-01 — The pinned `neo4j-agent-memory==0.2.0[mcp,sentence-transformers,openai]` is a real, installable, currently-intended pin

- **Trigger:** A dependency-resolution check is run against the exact pin string
  used in `docker/mcp.Dockerfile:14`:
  `neo4j-agent-memory[mcp,sentence-transformers,openai]==0.2.0`.
- **Preconditions:** Network access to `pypi.org`/`files.pythonhosted.org` is
  available (build-time condition, same as the real Docker build in
  `docker/mcp.Dockerfile:14`).
- **Expected observable outcome:** A dependency resolver (`pip install --dry-run
  --target <scratch-dir> "neo4j-agent-memory[mcp,sentence-transformers,openai]==0.2.0"`)
  exits `0` and its "Would install" line names `neo4j-agent-memory-0.2.0` plus the
  three extras' direct dependencies (`fastmcp` for `mcp`, `sentence-transformers` for
  `sentence-transformers`, `openai` for `openai`) with no resolution conflict.
- **Failure behaviour:** If the resolver exits non-zero (version doesn't exist on
  PyPI, is yanked, or the extras aren't defined on that release), the pin is broken
  and must be corrected to the nearest version that does resolve, or escalated as a
  Class 1 decision if multiple non-obvious candidates exist.
- **Verification method:** Run, from a clean state (no pre-existing scratch dir):
  `pip install --dry-run --target=./pip-verify-scratch
  "neo4j-agent-memory[mcp,sentence-transformers,openai]==0.2.0"` — exit code `0` and
  "Would install ... neo4j-agent-memory-0.2.0 ..." present in output. Immediately
  demonstrate the failure path is real (not vacuously passing) with the same command
  against a version known not to exist, e.g. `==99.0.0` — must exit non-zero with
  `ERROR: Could not find a version that satisfies the requirement`. Delete the scratch
  dir after each run (it is git-ignored via `.gitignore:<pip-scratch/ line>` but must
  not be left as build litter).
- **Traces to:** NG2 (framework consumed as a pinned dependency, not vendored); §10
  open item "Pin the exact framework version... needs confirmation."

### PIN-02 — §10's characterization of the pin as an unconfirmed placeholder is corrected by recorded evidence, without code change if the pin is already correct

- **Trigger:** PIN-01's verification method is run and its result (pass or fail) is
  known.
- **Preconditions:** PIN-01 has produced a definitive pass/fail with raw command
  output as evidence.
- **Expected observable outcome:** If PIN-01 passes, no `docker/mcp.Dockerfile` change
  is required — `0.2.0` was already correct — and the outcome is a documentation-only
  confirmation (§10 item resolved, caveat text removed, evidence cited). If PIN-01
  fails, `docker/mcp.Dockerfile:14`'s version literal is updated to the resolvable
  version identified by PIN-01's investigation, and the same dry-run check is re-run
  against the new literal until it passes.
- **Failure behaviour:** If no single corrected version can be identified without a
  product trade-off (e.g. the newest version drops one of the three required extras,
  or requires a breaking change to how the framework is invoked), that is a Class 1
  decision — log it to Unresolved decisions rather than silently picking a version.
- **Verification method:** Diff `docker/mcp.Dockerfile` before/after (git diff) — it
  must be unchanged if PIN-01 passed on `0.2.0`, or changed only in the version
  literal if PIN-01 failed. Confirm no `docs/SPECIFICATION.md` edit was made by this
  requirement's actor (see Explicit scope — that edit belongs to gate 6).
- **Traces to:** NG2; §10 open item; SPEC_LOOP.md gate-6 rule ("every discovery lands
  in the spec... reconciliation stage owns spec edits").

### PIN-03 — The Anthropic model-id "floating fact" policy stays internally consistent and is not re-pinned by this slice

- **Trigger:** `litellm/config.yaml`'s three model entries (`claude`, `claude-anthropic`,
  `claude-mock`) are inspected against §10's stated policy.
- **Preconditions:** §10 (`docs/SPECIFICATION.md:527-529`) and the "Resolved" item
  documenting the `claude-3-5-sonnet-latest` → `claude-sonnet-4-5` model-id update
  (`docs/SPECIFICATION.md:634-641`) already establish the model id as a
  re-verified-per-run fact, not an immutable literal.
- **Expected observable outcome:** This slice confirms (does not change)
  `litellm/config.yaml`'s current `anthropic/claude-sonnet-4-5` entries are consistent
  with that stated policy, and makes no attempt to hard-pin a specific Anthropic
  model id as part of resolving the framework-version caveat. The two concerns (package
  version pin vs. model id) are kept separable in the handoff so a future run's
  model-id re-verification cannot be confused with this slice's package-pin evidence.
- **Failure behaviour:** If `litellm/config.yaml` and §10's stated policy are found to
  disagree (e.g. config hard-codes a comment claiming permanence), that is logged as a
  discovery for gate 6, not silently fixed here (out of scope; see below).
- **Verification method:** Manual textual comparison: `litellm/config.yaml` model
  entries vs. `docs/SPECIFICATION.md:527-529` and `:634-641` — confirm no contradiction.
  No command produces a numeric result here; this is a documentation-consistency check,
  explicitly scoped to not require or produce a code change.
- **Traces to:** §10 open item (the model-id half of the same bullet); the "Resolved:
  production Anthropic model id updated..." item.

## 3. Verification criteria (mechanical, per requirement)

| Req | Mechanical check | Pass condition |
|-----|-------------------|-----------------|
| PIN-01 | `pip install --dry-run --target=./pip-verify-scratch "neo4j-agent-memory[mcp,sentence-transformers,openai]==0.2.0"` | exit `0`; output contains `neo4j-agent-memory-0.2.0` |
| PIN-01 (failure path) | same command with `==99.0.0` | exit non-`0`; output contains `Could not find a version that satisfies` |
| PIN-02 | `git diff -- docker/mcp.Dockerfile` (before/after implementation) | empty diff if PIN-01 passed on `0.2.0`; version-literal-only diff otherwise |
| PIN-02 (scope) | `git diff -- docs/SPECIFICATION.md` produced by the *implementation* stage | must be empty — any SPECIFICATION.md edit at this stage is a process defect, not this slice's implementation output |
| PIN-03 | Diff `litellm/config.yaml` model ids against §10/Resolved-items text | no contradiction found; no `litellm/config.yaml` edit required or made |

## 4. Explicit scope

**In scope:**
- Verifying, via a real PyPI dependency-resolution check, whether
  `neo4j-agent-memory==0.2.0` with extras `[mcp,sentence-transformers,openai]` is
  installable and intended.
- Correcting `docker/mcp.Dockerfile`'s version literal **only if** the check shows
  `0.2.0` does not resolve (it does — see investigation below — so this branch is not
  expected to trigger, but the requirement covers it for completeness/future re-runs).
- Confirming the Anthropic model-id policy (§10) is internally consistent; no config
  change expected.

**Out of scope:**
- Editing `docs/SPECIFICATION.md` (removing the "needs confirmation" caveat, moving the
  §10 item to "Resolved"). **This is explicitly a Reconciliation-stage (gate 6)
  responsibility, not Implementation.** Implementation may touch only
  `docker/mcp.Dockerfile`, and only if PIN-01 actually fails.
- Changing the LLM/embedding provider configuration (`litellm/config.yaml` model
  routing, `claude`/`claude-anthropic`/`claude-mock` entries) beyond the read-only
  consistency check in PIN-03.
- Changing network topology / compose service wiring.
- Upgrading to a newer `neo4j-agent-memory` release (e.g. `0.5.0`) even though one
  exists — that is a separate, larger slice (potential breaking-change surface across
  the whole framework surface) and not what §10's caveat asks for. See Recorded facts
  below for the evidence this decision rests on.
- Re-pinning or otherwise altering the Anthropic model id literal — §10 already
  resolved that to "floating fact, re-verified per run," and this slice must not
  regress that decision.

## 5. Unresolved decisions

None — cleared at gate 2. (See Recorded facts below: the investigation resolved the
only apparent ambiguity — whether `0.2.0` is stale relative to newer PyPI releases —
as a Class 3 safe choice, not a Class 1 product decision, because upgrading is
reversible-but-large-blast-radius and explicitly out of this slice's scope per the
§10 wording, which asks only to *confirm* the existing pin, not to select a new one.)

## 6. Recorded facts & safe choices

- **Fact (Class 2):** `neo4j-agent-memory==0.2.0` exists on PyPI, is not yanked, and
  was published 2026-05-04T20:27:36Z. Source:
  `curl -s https://pypi.org/pypi/neo4j-agent-memory/0.2.0/json` →
  `info.version == "0.2.0"`, `info.yanked == false`.
- **Fact (Class 2):** All three extras used in the Dockerfile pin are defined on the
  `0.2.0` release's own metadata (not just the current/latest release's): `mcp` →
  `fastmcp<3,>=2.0.0`, `sentence-transformers` → `sentence-transformers>=2.2.0`,
  `openai` → `openai>=1.0.0`. Source: same PyPI JSON endpoint,
  `info.requires_dist` entries tagged `extra == "mcp"` / `"sentence-transformers"` /
  `"openai"`.
- **Fact (Class 2):** A real dependency-resolution dry run
  (`pip install --dry-run --target=<scratch> "neo4j-agent-memory[mcp,sentence-transformers,openai]==0.2.0"`)
  exits `0` and resolves cleanly to `neo4j-agent-memory-0.2.0` plus a full, consistent
  dependency set (fastmcp-2.14.7, sentence-transformers-5.6.0, openai-2.45.0, mcp-1.28.1,
  torch-2.13.0, etc. — 140+ packages, no conflicts reported). Source: command run
  2026-07-14, raw pip output captured; re-run with `==99.0.0` on the same extras
  produces `ERROR: Could not find a version that satisfies the requirement
  neo4j-agent-memory==99.0.0 (from versions: 0.0.1, 0.0.2, 0.0.3a1, 0.0.3, 0.0.4,
  0.0.5, 0.1.0, 0.1.1, 0.1.2, 0.2.0, 0.2.1, 0.4.0, 0.5.0)` and exits `1`, confirming the
  check has real discriminating power (teeth-proven, not vacuously green).
- **Fact (Class 2):** PyPI's full release list for `neo4j-agent-memory` at time of
  investigation is `0.0.1, 0.0.2, 0.0.3a1, 0.0.3, 0.0.4, 0.0.5, 0.1.0, 0.1.1, 0.1.2,
  0.2.0, 0.2.1, 0.4.0, 0.5.0` — the current/latest is `0.5.0` (published
  2026-05-30T23:23:11Z, ~26 days after `0.2.0`). `0.2.0` is therefore **not** the
  newest available version, but it is a real, non-yanked, installable release with the
  needed extras intact.
- **Safe choice (Class 3):** Recommend **CONFIRM-NO-CHANGE** — keep
  `docker/mcp.Dockerfile`'s `==0.2.0` pin as-is, and resolve §10's caveat purely as a
  documentation confirmation (gate 6's job), rather than upgrading to `0.5.0` in this
  slice. Rationale: §10's exact ask is "confirm the pin," not "adopt latest"; jumping
  three minor versions (`0.2.0` → `0.4.0` → `0.5.0`) crosses undocumented changes to a
  framework whose exact CLI/console-script/extras surface this repo depends on
  (`neo4j-agent-memory mcp serve`, `NAM_*` env vars — see
  `docs/SPECIFICATION.md:137-146`) and is a one-way-door-adjacent change in blast
  radius (framework upgrade could alter CLI flags, env var names, or MCP tool
  behaviour) that deserves its own dedicated, separately-verified slice, not a
  side-effect of a version-confirmation pass. This choice is reversible (a future
  slice can still upgrade) and follows the existing convention of treating framework
  upgrades as their own slices (see `extractor-wiring-fix` and `github-models-llm-backend`
  in AGENTS.md/§10 Resolved items, each scoped narrowly to one framework-interaction
  concern at a time).
- **Safe choice (Class 3):** Treat PIN-03 (Anthropic model-id policy check) as a
  read-only consistency confirmation with no code output, per §10's own framing that
  the model id is "now treated as a floating fact... not a fixed literal" — reversible,
  no contract impact, and already the standing convention recorded in the "Resolved:
  production Anthropic model id updated..." item (`docs/SPECIFICATION.md:634-641`).

## Role-boundary note (explicit, for gate 3/4)

Implementation (gate 3–4) may modify **only** `docker/mcp.Dockerfile`, and only in the
branch where PIN-01 actually fails (not expected, per the investigation above).
Implementation **must not** edit `docs/SPECIFICATION.md` under any circumstance —
removing the "needs confirmation" caveat and moving the §10 item to "Resolved" is
Reconciliation's (gate 6) exclusive responsibility, to be done from the verification
evidence this slice produces. If Implementation believes the caveat should be resolved
with no code change (the expected outcome here), it must say so explicitly in
`implementation.handoff.md`'s evidence bundle and stop — it does not touch the spec
itself.
