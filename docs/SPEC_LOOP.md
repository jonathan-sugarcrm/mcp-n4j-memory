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
| 5 | **Verify** | Slice + criteria | Run each criterion's stated **Verification method** — the *smallest* check that proves it (compose config lint, isolation assertion, tool smoke test — see spec §9). Exercise the failure behaviour, not just the happy path. | Every gate-1 criterion is demonstrably met by its verification method, or a defect is logged. |
| 6 | **Feed back** | Defects + discoveries | Fold each defect/discovery into `SPECIFICATION.md` (tighten a row, resolve/append an Open question, correct §4 wiring). Then pick the next slice → gate 1. | Spec now reflects reality; no discovery left only in chat or a todo. |

## Gate 2 clarification policy

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
- **Open questions block their dependents, not the whole loop.** Log, ask, and pick a
  slice that doesn't depend on the answer.
- **No new design docs.** Feedback edits the existing spec sections. This file and the
  spec are the only two documents.

## Slice backlog

The current pass's slices live in the `todos` table (derived from spec §3.3 "the thin
delta"), ordered by `todo_deps`. Query ready work with:

```sql
SELECT t.* FROM todos t WHERE t.status = 'pending' AND NOT EXISTS (
  SELECT 1 FROM todo_deps d JOIN todos p ON d.depends_on = p.id
  WHERE d.todo_id = t.id AND p.status != 'done');
```
