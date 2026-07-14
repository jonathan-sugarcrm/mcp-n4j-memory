# Verification handoff — `pin-framework-version`

Gate 5 (Verify). Independent re-derivation — nothing in this handoff is taken from the
implementation handoff's claims without being reproduced directly against the repo /
PyPI here, 2026-07-14.

## 1. Per-requirement verdict

| Req | Verdict | Check actually run | Observed result |
|-----|---------|---------------------|------------------|
| PIN-01 (happy path) | **PASS** | `pip install --dry-run --ignore-installed --target=./pip-verify-scratch-check "neo4j-agent-memory[mcp,sentence-transformers,openai]==0.2.0"` | Exit `0`. "Would install" line contains `neo4j-agent-memory-0.2.0` plus `fastmcp-2.14.7`, `sentence-transformers-5.6.0`, `openai-2.45.0` (the three extras' direct deps), ~140 packages, no conflict errors. |
| PIN-01 (failure path) | **PASS** | Same command, target `./pip-verify-scratch-check2`, version `==99.0.0` | Exit `1`. `ERROR: Could not find a version that satisfies the requirement neo4j-agent-memory==99.0.0 (from versions: 0.0.1, 0.0.2, 0.0.3a1, 0.0.3, 0.0.4, 0.0.5, 0.1.0, 0.1.1, 0.1.2, 0.2.0, 0.2.1, 0.4.0, 0.5.0)` — `0.2.0` is present in the available-versions list, proving the check discriminates real breakage rather than passing vacuously. |
| PIN-02 (Dockerfile diff) | **PASS** | `grep -n "neo4j-agent-memory" docker/mcp.Dockerfile` + `git diff -- docker/mcp.Dockerfile` | Line (actual line 13, not 14 as the spec/implementation handoffs cite — see Missing evidence/minor note below) reads exactly `RUN pip install --no-cache-dir "neo4j-agent-memory[mcp,sentence-transformers,openai]==0.2.0"`, matching the pin PIN-01 confirmed resolves. `git diff` output is empty (exit 0, no diff text) — no Dockerfile edit was made, consistent with PIN-01 passing on `0.2.0` as-is. |
| PIN-02 (scope: no SPECIFICATION.md edit by this slice) | **PASS** | `git status --porcelain` + `git diff --stat -- docs/SPECIFICATION.md` + `git diff -- docs/SPECIFICATION.md \| grep -ic "pin-framework-version\|PIN-01\|PIN-02\|PIN-03"` | `git status --porcelain` shows `M docs/SPECIFICATION.md` (pre-existing, unstaged) plus only new untracked dirs `docs/spec-loop-runs/{acg6-lint,extractor-wiring-fix,pin-framework-version}/` and `scripts/check_thin_delta.sh` — none of which are tracked-code edits from this slice. The existing `SPECIFICATION.md` diff (60 insertions / 35 deletions) contains **zero** occurrences of `pin-framework-version`, `PIN-01`, `PIN-02`, or `PIN-03`, confirming it originates from the earlier `extractor-wiring-fix`/`acg6-lint` slices, not this one. No tracked code file (`docker/mcp.Dockerfile`, `litellm/config.yaml`) is modified. |
| PIN-03 (model-id policy consistency) | **PASS** | `grep -n -A2 "model_name:\|model:" litellm/config.yaml` vs `sed -n '520,535p;628,645p' docs/SPECIFICATION.md`; `git diff -- litellm/config.yaml` | `litellm/config.yaml`: `claude` → `openai/gpt-4o-mini` (GitHub Models), `claude-anthropic` → `anthropic/claude-sonnet-4-5`, `claude-mock` → `anthropic/claude-sonnet-4-5` + `mock_response`. §10 (`:527-529`) states the id is "now treated as a **floating fact, re-verified per run**... `litellm/config.yaml` currently pins `anthropic/claude-sonnet-4-5`" — matches verbatim. The "Resolved" item (`:634-641`) confirms the same `claude-3-5-sonnet-latest` → `claude-sonnet-4-5` history and re-states the floating-fact framing. No contradiction found; config has no hard-coded permanence claim. `git diff -- litellm/config.yaml` is empty — no edit made. |

## 2. Missing evidence

None of the five checks lack reproducible evidence — all five were independently
re-run against the live repo/PyPI in this verification pass, not merely read from the
implementation handoff's log.

**Minor citation defect (non-blocking, not a requirement failure):** both the
specification handoff and the implementation handoff cite the pin string as living at
`docker/mcp.Dockerfile:14`. The actual pin is on **line 13** in the current file (the
file has grown a leading comment block since the citation was written). This does not
affect any pass/fail verdict — the pin *content* was verified directly by `grep`, not
by trusting the line number — but it is recorded per SPEC_LOOP.md's "every discovery
lands in the spec" principle. Classified below as `unspecified_behaviour`-adjacent
documentation drift; routed to gate 6 as a citation-only correction, not a code or
verification defect.

## 3. Regressions

None observed. This slice made no tracked-file changes (confirmed via `git status
--porcelain` and per-file `git diff`), so there is no code surface across which a
regression could have been introduced. No broader test suite run was warranted because
the change set is empty by design (CONFIRM-NO-CHANGE outcome).

## 4. Classified findings

| Finding | Type | Routing |
|---|---|---|
| Spec/implementation handoffs cite `docker/mcp.Dockerfile:14`; the pin is actually on line 13 in the current file. | Behaviour is unspecified / minor documentation drift (does not meet the bar of "code violates a requirement" since the pin *content* matches exactly and the line-number citation is not itself a pass/fail criterion). | Gate 6 — Reconciliation may fold a corrected line reference into §10 when it moves this item to "Resolved." No code or verification-method change required. |
| Implementation handoff correctly noted `.gitignore:17`'s pattern (`pip-scratch/`) does not glob-match the `pip-verify-scratch` directory name the spec's Verification method mandates. | Requirement is imprecise but not contradictory — a genuine but non-blocking spec inaccuracy (the gitignore claim was wrong, but the scratch dir was deleted every time regardless, so no build litter resulted; this verification pass also deleted its own `./pip-verify-scratch-check{,2}` dirs). | Gate 1 / §9 Verification method — a future spec revision should correct the `.gitignore` reference or add `pip-verify-scratch*` to `.gitignore` for defense-in-depth, but this is not required to close this slice. |

No `code_violation`, `contradictory_requirement`, `missing_evidence`, `new_constraint`,
or `weak_verification` findings — every requirement passed with reproduced evidence
that ties directly to its criterion.

## 5. Overall verdict

**PASS.** CONFIRM-NO-CHANGE is upheld: PIN-01 resolves cleanly (exit 0,
`neo4j-agent-memory-0.2.0` present) and demonstrably fails on a non-existent version
(exit 1, correct error, `0.2.0` listed among real available versions) — the check has
real teeth. `docker/mcp.Dockerfile`'s pin already matches exactly what PIN-01 verified
and is unchanged (`git diff` empty). `litellm/config.yaml` is internally consistent
with §10's floating-fact model-id policy and is also unchanged. No tracked code file
was touched by this slice's implementation, and the pre-existing `docs/SPECIFICATION.md`
diff on disk predates and is unrelated to this slice (zero references to
pin-framework-version content). Ready for gate 6 (Reconciliation) to fold the
confirmation into §10 (move the "needs confirmation" caveat to "Resolved," citing this
verification pass's evidence) and optionally correct the `:14` → `:13` line citation.
