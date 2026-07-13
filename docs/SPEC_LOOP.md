# Specification Loop

> The repeatable process a coding agent runs to turn `SPECIFICATION.md` into working
> software **one bounded slice at a time**. The goal is a *tight loop*, not a bigger spec.
> Each pass touches the smallest amount that can be verified, then feeds what it learned
> back into the spec. The spec shrinks in uncertainty as code grows.

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
| 1 | **Understand** | `SPECIFICATION.md` | Restate the outcome for the chosen slice as 1–3 falsifiable acceptance criteria. | Criteria are testable and trace to a Goal/Constraint (`G*`/`C*`). |
| 2 | **Gap-check** | Slice + spec | List what you'd have to *assume* to build it. Each assumption is either resolved from the spec or logged to **§Open questions** and asked. | Zero unresolved blocking assumptions remain. |
| 3 | **Propose** | Resolved slice | Write **one** `todo` (bounded: a single file/service/check) with its acceptance criteria in the description; add `todo_deps` for ordering. | Slice is small enough to verify in one pass; deps recorded. |
| 4 | **Execute** | The `todo` | Implement only that slice. Set the todo `in_progress` → `done`. | Change is complete and self-contained; nothing unrelated touched. |
| 5 | **Verify** | Slice + criteria | Run the *smallest* check that proves the criteria (compose config lint, isolation assertion, tool smoke test — see spec §9). | Every gate-1 criterion is demonstrably met, or a defect is logged. |
| 6 | **Feed back** | Defects + discoveries | Fold each defect/discovery into `SPECIFICATION.md` (tighten a row, resolve/append an Open question, correct §4 wiring). Then pick the next slice → gate 1. | Spec now reflects reality; no discovery left only in chat or a todo. |

## Invariants

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
