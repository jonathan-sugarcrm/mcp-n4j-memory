# Specification Loop

> The repeatable process a coding agent runs to turn `SPECIFICATION.md` into working
> software **one bounded slice at a time**. The goal is a *tight loop*, not a bigger spec.
> Each pass touches the smallest amount that can be verified, then feeds what it learned
> back into the spec. The spec shrinks in uncertainty as code grows.

## Prime directive: write evaluable statements, not prose

The loop's job is to convert intent into statements that can be **mechanically checked
true or false**. Descriptive prose is not a requirement; it is a placeholder for one. A
pass has not produced a real acceptance criterion until that criterion could be handed to
someone (or something) with no context and evaluated to pass/fail without a judgement call.

- **Weak (prose):** "The user should be able to manage sessions securely."
- **Better (evaluable):** "Logging out of the parent application invalidates access to the
  embedded widget within 10 seconds across all open tabs."

### Anatomy of a requirement

Every acceptance criterion produced at gate 1 **must** specify all five fields. If a field
cannot be filled, that is a gap — log it at gate 2, don't hand-wave it.

| Field | Question it answers |
|-------|---------------------|
| **Trigger** | What event or action initiates the behaviour? |
| **Preconditions** | What must be true before the trigger for this to apply? |
| **Expected observable outcome** | What changes in a way an outside observer can measure? |
| **Failure behaviour** | What is the defined outcome when the happy path can't complete? |
| **Verification method** | The exact check that proves the outcome (test, assertion, smoke command — see spec §9). |

## Roles of the two artifacts

- **`SPECIFICATION.md`** — the durable contract. The **only** place intent and open
  questions live. The loop *edits* it; it does not spawn parallel design docs.
- **Working state** (`todos` + `todo_deps` in the session DB) — the ephemeral backlog of
  bounded slices for the current pass. Disposable; rebuilt from the spec each session.

## The loop (six gates, one slice per pass)

Run gates in order. A gate may **only** exit when its exit-check passes; otherwise loop
back to the named gate. Never skip ahead to code with an open blocker.

| # | Gate | Input | Do | Exit-check |
|---|------|-------|----|-----------|
| 1 | **Understand** | `SPECIFICATION.md` | Restate the outcome for the chosen slice as 1–3 acceptance criteria, each carrying all five fields (Trigger, Preconditions, Expected observable outcome, Failure behaviour, Verification method). | Each criterion is evaluable pass/fail with no judgement call, and traces to a Goal/Constraint (`G*`/`C*`). |
| 2 | **Gap-check** | Slice + spec | List every unknown needed to fill the five fields, then **classify each** via the *Gate 2 clarification policy* below: investigate technical facts, decide-and-record safe choices, and log only genuine product decisions to **§Open questions** to ask. | Zero unresolved blocking assumptions remain; no criterion has an empty field; every asked item is a product decision. |
| 3 | **Propose** | Resolved slice | Write **one** `todo` (bounded: a single file/service/check) with its acceptance criteria in the description; add `todo_deps` for ordering. | Slice is small enough to verify in one pass; deps recorded. |
| 4 | **Execute** | The `todo` | Implement only that slice. Set the todo `in_progress` → `done`. | Change is complete and self-contained; nothing unrelated touched. |
| 5 | **Verify** | Slice + criteria | Run each criterion's stated **Verification method** — the *smallest* check that proves it (compose config lint, isolation assertion, tool smoke test — see spec §9). Exercise the failure behaviour, not just the happy path. Capture the **evidence bundle** (see below), emit the machine-readable **verification report** (`verification.report.yaml`, see below) proving each requirement, and **classify every failure** via the *Verification-failure classification* table. | Not satisfied by "tests pass." Every gate-1 criterion has a `result` in `verification.report.yaml` backed by reproduced evidence, or a classified failure is logged. |
| 6 | **Feed back** | Defects + discoveries | Fold each classified failure/discovery back into **the code or the spec** per its classified action (never leave it in chat or a todo): tighten a row, resolve/append an Open question, correct §4 wiring, or route a code fix. Then pick the next slice → gate 1. | The loop is **closed**: every result has moved either the code or `SPECIFICATION.md`. Nothing is merely noted. |

## Closing the loop: results must move code or the spec

> A specification loop is **only closed** when the implementation's results can modify
> **either the code or the specification**. A verification result that changes neither is
> not feedback — it is a note, and notes are lost. Gate 6 does not exit until every result
> has landed as a code change or a spec edit.

### Verification-failure classification

Every failure logged at gate 5 **must** be classified into exactly one type below; the
type determines the action gate 6 takes. This replaces "log a defect" with a deterministic
routing so the same failure is always handled the same way — and so a passing test can
never mask an unmet outcome.

| Failure type | Action | Routes to |
|--------------|--------|-----------|
| **Code violates a clear requirement** | Fix the code. | gate 4 (Execute) |
| **Requirement is contradictory** | Fix the specification. | gate 1 / §9 criterion |
| **Requirement cannot be verified** | Add evidence criteria (make it evaluable). | gate 1 / §9 Verification method |
| **New technical constraint discovered** | Update the constraints. | §Constraints (`C*`) |
| **Behaviour is unspecified** | Request a product decision (Class 1). | §Open questions |
| **Test passes but the outcome is unmet** | Improve the verification model. | gate 1 / §9 Verification method |

- The last row is the trap this table exists to close: a green check is **not** proof.
  When observed behaviour contradicts a passing check, the *check* is wrong — strengthen the
  Verification method, do not accept the pass.
- "Fix the code" and "fix the specification" are the only two terminal actions; every other
  row is a step toward one of them. That is what "the loop moves code or spec" means.

## Evidence bundle

Every implementation (gate 4) **must** produce an **evidence bundle** — the raw proof gate
5 re-derives its verdict from. The bundle is a set of `Requirement → Evidence → Result`
triples, one row per gate-1 criterion:

| Requirement | Evidence | Result |
|-------------|----------|--------|
| The criterion id + its Expected observable outcome. | The verbatim artifact that proves it (see below), not a claim of success. | `PASS` / `FAIL` re-derived from the evidence. |

**Evidence may be** (choose the smallest that actually proves the outcome):

- tests,
- command output,
- screenshots,
- API responses,
- performance measurements,
- static analysis,
- deployment observations.

Rules:

- **Raw, not summarized.** "All tests passed" is a claim; the test runner's output is
  evidence. A row whose Evidence is a summary is treated as **missing evidence** (= fail).
- **Covers the failure behaviour too.** Each requirement's bundle must show the defined
  failure outcome was exercised, not only the happy path.
- **Reproducible.** Evidence names the exact command/input so a different agent can re-run
  it. Verification (gate 5) reproduces the bundle rather than trusting it.

> **Worked example:** see the *Evidence bundle* table in
> `docs/spec-loop-runs/docker-compose/implementation.handoff.md` §4 — three requirements,
> each with reproduced happy-path **and** failure-path evidence, marked `PASS` only because
> the failure path shows the check can fail.

## Verification report (machine-readable proof)

> **Prove every requirement, don't just report tests pass.** "The test suite passed" is
> not proof of a requirement unless a listed evidence item ties to that specific
> requirement. Gate 5 must emit a machine-readable serialization of the evidence bundle
> and the failure classification so a consumer (CI, another agent) can decide pass/fail
> without reading prose.

Gate 5 writes `docs/spec-loop-runs/<slice-id>/verification.report.yaml`, one entry per
gate-1 acceptance criterion:

```yaml
slice: <slice-id>
requirements:
  - id: <criterion id>            # e.g. AUTH-01
    result: pass | fail
    evidence:                     # REQUIRED and non-empty when result: pass; each item is one reproduced proof
      - test: <test name>         # any of: test | command | screenshot | api_response | measurement | static_analysis | deployment
      - command: <command run>
    reason: <why it failed>       # REQUIRED when result: fail; omit when pass
    defect_type: <enum>           # REQUIRED when result: fail; omit when pass
overall: pass | fail              # pass only if every requirement is pass
```

**Evidence item keys** are the Evidence-bundle types above: `test`, `command`,
`screenshot`, `api_response`, `measurement`, `static_analysis`, `deployment`.

**`defect_type` enum** maps 1:1 to the *Verification-failure classification* table above,
plus one entry for a pass with no reproduced proof:

| `defect_type` | Corresponds to |
|---------------|-----------------|
| `code_violation` | Code violates a clear requirement → fix code |
| `contradictory_requirement` | Requirement is contradictory → fix spec |
| `missing_evidence` | Requirement cannot be verified, or a claimed pass carries no reproduced evidence → add evidence criteria |
| `new_constraint` | New technical constraint discovered → update constraints |
| `unspecified_behaviour` | Behaviour is unspecified → request a product decision |
| `weak_verification` | Test passes but the outcome is unmet → improve the verification model |

Rules:

- A requirement is `result: pass` **only if** it carries at least one reproduced evidence
  item that ties to that requirement. A `pass` with empty or missing evidence is itself a
  `fail` with `defect_type: missing_evidence` — it does not get to remain a pass.
- Every `fail` entry carries a `reason` and a `defect_type` drawn from the enum above.
- `overall: pass` requires every requirement entry to be `pass`; otherwise `overall: fail`.

> **Worked example:** see `docs/spec-loop-runs/docker-compose/verification.report.yaml` —
> the machine-readable counterpart of `verification.handoff.md`.



> The dominant failure mode of a coding agent is **not** poor implementation — it is
> **silent assumption-making**. This policy makes ambiguity handling *deterministic*: the
> same unknown is classified the same way every time, so the agent neither treats every
> ambiguity as blocking nor freely invents answers. It is the detailed procedure gate 2 runs.

### The three classes of missing information

| Class | Definition | Agent behaviour |
|-------|-----------|-----------------|
| **1 — Missing product decision** | A choice between *legitimate* alternatives that changes observable behaviour, scope, or a contract, and is the **stakeholder's** to make. | **Stop and request a decision.** |
| **2 — Missing technical fact** | A single correct answer discoverable from code, docs, dependencies, or the environment — no stakeholder needed. | **Investigate and report** (with a citation). |
| **3 — Safe implementation choice** | Multiple acceptable answers, but reversible and with no product/contract impact — or already implied by an existing convention. | **Decide and record the rationale.** |

### Deterministic classification procedure

For each unknown, run these steps **in order**; the first match wins. Order matters —
*investigate before you escalate*, and never ask what the repo already answers.

1. **Investigable?** Is there a single correct answer discoverable without a stakeholder
   (in the spec, code, a dependency's docs, or the environment)? → attempt the investigation.
   - Found → **Class 2** (record the fact + citation).
   - Investigation shows there is no single answer, only a genuine either/or → go to 2.
2. **Stakeholder choice with impact?** Does choosing change externally observable behaviour,
   scope, data, or a public contract — **or** is it a one-way door (costly to reverse) — while
   more than one option is legitimate? → **Class 1** (stop and ask).
3. **Otherwise** → **Class 3** (decide and record a one-line rationale).

**Tie-breakers (remove the remaining judgement):**
- *Convention test* — if the spec or an existing repo convention already implies an answer,
  it is a **fact** to follow (Class 2), not a decision.
- *Reversibility test* — two-way door (cheap to change later) leans **Class 3**; one-way door
  (schema/contract/public API/data migration) leans **Class 1**.
- *Blast-radius test* — an internal-only default is **Class 3**; anything externally
  observable is **Class 1**.

### The refinement workflow

1. **Extract explicit requirements** — enumerate what the request literally states; quote the
   source. Do not add unstated scope.
2. **Identify unresolved decisions** — list every unknown needed to fill the five fields for
   the slice's criteria.
3. **Separate decisions from investigable facts** — apply the classification procedure to each
   unknown → {Class 1, Class 2, Class 3}.
4. **Investigate technical facts** — resolve every Class 2 item and cite the source. If an
   investigation reveals a genuine either/or with impact, reclassify it up to Class 1.
5. **Present the smallest decision set** — ask *only* the Class 1 items: deduplicated, batched,
   one decision per question, each with its legitimate options. Class 2 and Class 3 items are
   never asked.
6. **Produce the executable specification** — fold answers + facts + recorded safe choices into
   evaluable five-field criteria (the gate 1 standard), then proceed.

### Smallest-decision-set rules (prevent over-asking)

- **Ask only Class 1.** A question whose answer is investigable (Class 2) or safely
  inferable (Class 3) is a defect.
- **Merge and prune.** Combine questions that share an answer; drop any question whose answer
  stops mattering once an earlier one is decided.
- **Block dependents, not the loop.** A pending decision blocks only the slices that need it;
  pick an independent slice and keep moving (see Invariants).

### Recording safe choices

Every Class 3 choice is recorded where the decision lives (a resolved `§Open questions`
entry, or the todo/criterion), in the form:
`Chose X over Y because <reversible / follows convention / no contract impact>.`
A safe choice with no recorded rationale is treated as a silent assumption — the failure
mode this policy exists to prevent.

### Self-check (how compliance is measured)

An agent applying this policy correctly exhibits:
- **Assumptions:** only Class 3, each with a recorded rationale; **zero** silent product
  assumptions.
- **Questions:** **zero** that were answerable by investigation or an existing convention.
- **Separation:** every asked item is Class 1; every Class 2 item was investigated, not asked.

## Invariants

- **Prose is not a requirement.** No slice enters gate 3 until its criteria are evaluable
  pass/fail with all five fields filled. If it reads like a goal, it's not done at gate 1.
- **One bounded slice per pass.** If a slice can't be verified in a single pass, split it
  at gate 3.
- **Every discovery lands in the spec.** Chat and todos are scratch; `SPECIFICATION.md` is
  the memory. A pass is not `done` until gate 6 has written back.
- **The loop closes only by moving code or spec.** A verification result that changes
  neither is unfinished feedback. Every failure is classified and routed to a code fix or a
  spec edit before the pass is `done`.
- **No requirement without an evidence bundle.** A criterion with no `Requirement → Evidence
  → Result` triple (raw, reproducible) is unverified — treat it as failing, not passing.
- **A passing test is not proof.** If observed behaviour contradicts a green check, fix the
  verification model; never accept the pass.
- **Proof, not green.** A requirement is not met because a test passed; it is met only
  when the verification report carries a reproduced evidence item that ties to it. A pass
  with no evidence is `missing_evidence`.
- **Open questions block their dependents, not the whole loop.** Log, ask, and pick a
  slice that doesn't depend on the answer.
- **No new slice design docs.** Slice feedback edits the existing spec sections rather than
  spawning a parallel design doc; `SPECIFICATION.md` and this loop doc are the only
  slice-level documents. (Process/skill docs under `.agents/skills/spec-loop/` — e.g. the
  stage SKILLs and `exercise/` material — are the loop's own tooling, not slice artifacts,
  and are exempt.)
- **Loop-efficiency invariants (I1–I6) are gate exit-conditions, not options.** See the
  section below; each hardens the loop against a measured, recurring inefficiency.

## Loop-efficiency invariants (I1–I6)

These harden the loop against recurring, **measured** inefficiencies observed across real
runs (baseline evidence and extrapolated savings:
`.agents/skills/spec-loop/exercise/baseline-findings.md`). Each is a gate exit-condition —
a gate may not exit while its invariant is violated.

- **I1 — Single-writer for `SPECIFICATION.md` (gate 1 exit-check).** Only the
  Reconciliation stage (gate 6) edits `docs/SPECIFICATION.md`. Any requirement that entails
  a spec edit (moving a §10 item to Resolved, tightening a criterion) **must** be assigned
  to Reconciliation. A specification handoff that puts a `SPECIFICATION.md` edit in
  Implementation scope is a `contradictory_requirement` defect and does not exit gate 1.
  *(Targets the boundary defect seen in `mcp-env-cleanup` and `extractor-wiring-fix`.)*
- **I2 — Precondition-type gate (before gate 4 Execute).** Before any expensive execution
  (standing up services, external API calls, model completions), cheaply assert every
  precondition — credential, tool, service — is the right *kind*: e.g. an Anthropic API key
  is `sk-ant-api…`, **not** an OAuth `sk-ant-oat…`/`gho_` token; a required service is
  reachable. If a precondition is the wrong kind, mark the slice `blocked` and stop — do
  **not** bring up the stack or retry. *(Targets the ~23.5%-of-session waste in
  `prod-anthropic-verify`, where an OAuth token could never authenticate the API.)*
- **I3 — Completion = declared artifacts exist (between every stage).** A stage is complete
  only when its declared output artifacts exist and are non-empty — Verification needs both
  `verification.handoff.md` **and** `verification.report.yaml`; every other stage needs its
  handoff. The next gate asserts this before proceeding; never advance on a stage's
  self-report alone. *(Targets the truncated `g6-reconcile` that silently skipped its
  handoff.)*
- **I4 — Amend-then-realign (on any mid-loop amendment).** When an upstream artifact is
  amended mid-loop (e.g. a gate-1 correction), realign **every** downstream artifact that
  cites the changed fact *before* re-verifying. A stale downstream handoff contradicting an
  amended upstream one is fixed at the source, not discovered on an extra verification pass.
  *(Targets the triple-verification in `mcp-env-cleanup`.)*
- **I5 — Implementation scope discipline (gate 4 exit-check).** Implementation changes stay
  within the spec handoff's declared in-scope paths. A change outside that set is **not**
  applied silently — it is surfaced as a flagged proposal in the implementation handoff
  ("Out-of-scope observations") for a future slice or a stakeholder decision. *(Targets the
  unflagged `--detailed_debug` / model-id / extractor changes in `prod-anthropic-verify`.)*
- **I6 — Stage-cost calibration (gate 3).** Match stage cost to slice risk. A confirm-only
  or pure-doc slice with **no** risky tag (docker / credentials / network / migration /
  schema-change / prod) may use the **LIGHT** lane; any risky tag ⇒ **FULL** four-context
  rigor; an unreadable/ambiguous risk descriptor defaults to FULL (fail-safe). The LIGHT
  lane's saving comes from exactly **two** moves: (a) merge Specification + Implementation
  into a single cheaper-model (Haiku-tier) context — safe because a confirm-only/pure-doc
  slice carries no interpretation risk — and (b) run the mechanical stages on cheaper
  models. It does **not** collapse the two stages other invariants depend on: the
  independent **Verification** stage stays intact and separate (a vacuous confirmation
  still cannot pass — its verdict is re-derived by a context that did not produce it), and
  **Reconciliation** stays its own stage as the sole writer of `SPECIFICATION.md` (I1).
  Folding away Verify or Reconciliation is never permitted, in either lane.
  *(Targets the 4-Sonnet-context spend on the confirm-only `pin-framework-version`.)*

## Slice backlog

The current pass's slices live in the `todos` table (derived from spec §3.3 "the thin
delta"), ordered by `todo_deps`. Query ready work with:

```sql
SELECT t.* FROM todos t WHERE t.status = 'pending' AND NOT EXISTS (
  SELECT 1 FROM todo_deps d JOIN todos p ON d.depends_on = p.id
  WHERE d.todo_id = t.id AND p.status != 'done');
```
