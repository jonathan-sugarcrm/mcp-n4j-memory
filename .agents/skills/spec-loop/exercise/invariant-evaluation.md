# Exercise: baseline loop vs invariant-hardened loop (evaluating I1–I6)

Purpose: make the value of the proposed **process invariants measurable**, not asserted.
The first exercise (`comparison-template.md`) tests *role separation*. This one tests a
different axis: given role separation is already in place, do the **invariants** below
cut rework and wasted tokens **without lowering defect detection or reproducibility**?

The invariants under test (each traces to an observed failure in a real run — see
`AGENTS.md` and the cited slices):

| Id | Invariant | Observed failure it targets |
|----|-----------|------------------------------|
| **I1** | Only Reconciliation edits `SPECIFICATION.md`; any requirement touching it is assigned to Reconciliation, enforced as a **spec-stage exit check**. | `mcp-env-cleanup` **and** `extractor-wiring-fix` both emitted a `contradictory_requirement` (spec handoff put a `SPECIFICATION.md` edit in Implementation scope) → verification FAIL + a gate-1 fix agent each. |
| **I2** | **Precondition-type gate** before any expensive stage: cheaply assert the credential/tool/service is the right *kind* and fail fast to `blocked`. | `prod-anthropic-verify` spent ~28% of the session's sub-agent tokens standing up the stack and retrying a real API before the credential was found to be an OAuth token, not an API key. |
| **I3** | **Completion = declared artifacts exist**, not the return message: after each stage assert its output files exist and contain expected markers before advancing. | `g6-reconcile` terminated mid-task having removed a `§10` item but not written the Resolved entry or its handoff; caught only by luck. |
| **I4** | **Amend-then-realign**: when any artifact is amended mid-loop, realign every downstream artifact that cites the changed fact **before** re-verifying. | `mcp-env-cleanup` needed **three** verification passes because an amended spec handoff left a stale, contradicting implementation handoff. |
| **I5** | Implementation stays **inside declared scope**; out-of-scope deltas are flagged as proposals, not silently applied. | `prod-impl` silently added `--detailed_debug`, a model-id bump, and extractor env; the verifier had to triage each. |
| **I6** | **Match stage cost to slice risk**: full 4-context rigor for risky slices (Docker/creds/network); a lighter lane for confirm-only/pure-doc slices, keeping the independent-verify property. | `pin-framework-version` (two `pip --dry-run` calls) consumed ~4 Sonnet contexts. |

Success is **not** "Run B is cheaper." Success is **Run B is cheaper on the metrics I1–I6
target while its defect-detection and reproducibility columns do not regress** (the
guardrail). An invariant set that saves tokens by catching fewer defects has failed this
exercise.

---

## Protocol

### 0. Prepare the two loop variants (the independent variable)

- **Run A — baseline loop.** The four stage SKILLs exactly as they are today, unmodified.
- **Run B — invariant-hardened loop.** The same SKILLs with I1–I6 encoded (e.g. I1/I5 in
  `specification-agent`/`implementation-agent` SKILLs, I2/I3/I4 as steps in
  `SPEC_LOOP.md`, I6 as a stage-cost rule). Record the exact diff used, so the result is
  attributable to the invariants and nothing else.

Freeze everything else: same models per tier, same repo checkout, same operator prompts.

### 1. Use the fixed **trap-slice battery** (the controlled stimulus)

Do not reuse arbitrary backlog slices — their difficulty varies and confounds the result.
Run **both** variants against the *same* six engineered trap slices below. Each trap is
designed so a baseline loop will exhibit exactly one target failure, giving a clean signal.
Record ids under `docs/spec-loop-runs/<trap-id>/{run-a,run-b}/`.

| Trap | Targets | Construction (what makes it a trap) | The mistake a baseline loop makes |
|------|---------|--------------------------------------|-----------------------------------|
| **T1** | I1 | A slice whose only sane outcome is a `SPECIFICATION.md` edit (e.g. "move an existing `§10` open item to Resolved"). No production code changes. | Spec handoff assigns the `SPECIFICATION.md` edit to Implementation → `contradictory_requirement`. |
| **T2** | I2 | A slice gated on an external precondition supplied in the **wrong kind**: e.g. an OAuth token where the tool needs an API key, **or** a dependency service left stopped. | Implementation brings up the full stack / retries the API before discovering the precondition is unusable. |
| **T3** | I3 | Any slice, but the Reconciliation (or any) stage is **artificially truncated** — instruct that agent to stop after producing only its *first* declared output (spec edit) and skip its handoff. | The loop advances / declares done on the self-report, leaving a missing artifact. |
| **T4** | I4 | A slice that legitimately needs a **gate-1 amendment** mid-loop (seed the spec handoff with one wrong fact the verifier must bounce back). | After amendment, the downstream handoff is not realigned → an extra re-verification pass to catch the contradiction. |
| **T5** | I5 | A one-line-fix slice sitting next to an **obvious temptation** (a stray debug flag to remove, a version to bump) that is *out of scope*. | Implementation folds the tempting extra change in silently. |
| **T6** | I6 | A **confirm-only / pure-doc** slice (e.g. "confirm a pinned dependency version resolves; no change expected"). | The loop spends full 4-context Sonnet rigor on a two-command confirmation. |

> Keep the traps in a fixture file (`exercise/trap-slices.md`) with the exact seed text so
> the battery is reproducible run-to-run.

### 2. Execute each trap under both variants

Stages 1→2→3→4, artifact-only handoffs, fresh context per stage — identical orchestration
for A and B. The **only** difference between the columns is the loop variant from step 0.

### 3. Instrument, don't estimate

For every stage invocation, capture from the event log (see `/diagnose` queries):
sub-agent count, tokens, wall-time, and whether it produced its declared artifacts. Count
metrics **from the artifacts and the log**, never from memory or an agent's summary.

### 4. Prove each gate has teeth (mutation test)

An invariant that never fires is untested, not safe. For each, construct the input that
*should* trip it and confirm Run B catches it while Run A does not:

- **I1**: feed a spec handoff that assigns a `SPECIFICATION.md` edit to Implementation →
  Run B's spec-stage exit check must **reject/rewrite** it; Run A must let it through.
- **I2**: supply the wrong-kind credential → Run B must emit `blocked` **before** any stack
  bring-up; Run A must proceed to an expensive failure.
- **I3**: run the truncated stage → Run B must **halt and flag** the missing artifact; Run A
  must advance.
- **I4**: amend upstream → Run B must realign the downstream artifact before re-verify; Run
  A must require a second re-verification to notice.
- **I5**: plant the tempting out-of-scope change → Run B must surface it as a flagged
  proposal (diff stays scoped); Run A must ship it unflagged.
- **I6**: on the confirm-only trap, Run B must use the light lane; verify the
  independent-verify property still holds (a seeded false "confirmation" is still caught).

A gate that cannot be shown to fire on its trigger scores as **unproven** for that
invariant, regardless of token savings.

---

## Scorecard

Fill per trap, then total. Count from artifacts + event log.

### Efficiency metrics (expected to improve in Run B)

| Metric | How to count | Run A (baseline) | Run B (hardened) |
|--------|--------------|:----------------:|:----------------:|
| **Rework loops** | # stage re-runs after a "done"/PASS claim (re-verifications, gate-1 fix agents, artifact-repair agents). | | |
| **Wasted precondition tokens** | Tokens spent by any stage that ran *before* an unusable precondition was detected (T2). | | |
| **Silent partial stages** | # stages advanced past without all declared artifacts present (T3). | | |
| **Re-verification count** | # verification passes beyond the first, per slice (T4). | | |
| **Unflagged out-of-scope diffs** | # code changes outside the spec's in-scope list, applied without a flag (T5). | | |
| **Sub-agent contexts used** | # distinct stage agents dispatched for the confirm-only slice (T6). | | |
| **Total sub-agent tokens** | Sum across all traps. | | |

### Guardrail metrics (must **not** regress in Run B)

| Metric | How to count | Run A | Run B |
|--------|--------------|:-----:|:-----:|
| **Defect detection** | # real defects (spec + impl) surfaced before "done", each verified reproducible. | | |
| **Reproducibility defects** | # declared PASS claims that fail to reproduce from a clean state using only the documented command. | | |
| **Unproven checks (no teeth)** | # pass-criteria never shown able to fail. | | |
| **Escaped defects** | Defects found only after a run declared success. | | |

### Per-invariant verdict

| Invariant | Fired on its trigger in Run B? | Trigger slipped through in Run A? | Net effect (rework/tokens saved) | Verdict |
|-----------|:------------------------------:|:---------------------------------:|----------------------------------|:-------:|
| I1 | | | | pass / fail / unproven |
| I2 | | | | |
| I3 | | | | |
| I4 | | | | |
| I5 | | | | |
| I6 | | | | |

---

## Interpretation (fill after scoring)

- **Did each invariant fire on its trap in Run B and slip through in Run A?**
  (If an invariant did not fire, it is unproven — the exercise did not exercise it, or the
  encoding is inert. Fix the trap or the encoding before claiming the invariant works.)
- **Did the efficiency metrics improve without the guardrail metrics regressing?**
  (The whole hypothesis. If Run B is cheaper but detects fewer defects or reproduces
  worse, the invariants are cutting corners — reject them.)
- **I2 specifically: how many tokens did the precondition gate save vs the observed
  ~28% waste?** Quantify the largest single lever.
- **I6 specifically: did the light lane keep the independent-verify property?**
  (A seeded false confirmation on T6 must still be caught. If the light lane lets a
  vacuous "confirm" pass, I6 is unsafe as written — tighten it.)
- **Any invariant that helped one trap but caused a regression elsewhere?**
  (E.g. an over-eager I5 that blocks a *necessary* in-scope change, or an I2 gate that
  false-positives a usable precondition as blocked. Record these — a good invariant is
  net-positive across the battery, not just on its own trap.)
- **Net:** which invariants are worth encoding permanently, which need reformulation, and
  which showed no measurable effect on this repo's slice profile?

## Expected signal (hypothesis to test, not a guarantee)

- Run B shows **fewer rework loops and re-verifications** — the boundary/amendment defects
  are caught as stage-entry/exit checks instead of surfacing at verification.
- Run B **fails fast on unusable preconditions** — the T2 stack never comes up, converting
  the session's largest observed waste (~28% of sub-agent tokens) into a cheap `blocked`.
- Run B has **zero silent partial stages** — completion is asserted against artifacts.
- Run B's **guardrail columns are equal to Run A's** — defect detection, reproducibility,
  and teeth are preserved. This is the make-or-break: efficiency that costs rigor is a
  regression dressed as a win.
- I6 is the **most likely to backfire** — a light lane can quietly drop the independent
  verifier. Treat any guardrail regression on T6 as a signal to keep full rigor there.
- Null results are informative: an invariant that neither fires nor changes any metric on
  this battery is either inert or targeting a failure this repo won't hit — don't encode
  ceremony that buys nothing.
