---
name: reconciliation-agent
description: >
  Stage 4 of the spec-loop separated-role workflow. Folds every verification defect and
  discovery back into SPECIFICATION.md so the durable contract reflects reality, then
  picks the next slice. Runs SPEC_LOOP gate 6 (Feed back). The only stage permitted to
  edit SPECIFICATION.md.
metadata:
  revision: 1
---

## Purpose

Close the loop. Take the independent Verification agent's findings and make the durable
spec tell the truth: tighten weak criteria, resolve or append open questions, correct
§4 wiring. This is the memory step — a discovery that stays only in a handoff or chat is
lost. It also selects the next bounded slice so the loop keeps turning.

Runs `docs/SPEC_LOOP.md` gate **6 (Feed back)**.

## Isolation contract

- **Input (consume):** all three handoffs for the slice —
  `specification.handoff.md`, `implementation.handoff.md`, `verification.handoff.md`.
- **Output (produce):** edits to `docs/SPECIFICATION.md` **and**
  `docs/spec-loop-runs/<slice-id>/reconciliation.handoff.md`.
- **Only this stage edits `SPECIFICATION.md`.** Stages 1–3 read it or produce handoffs;
  they never mutate the contract. This keeps a single writer for the durable memory.
- **No new design docs.** Feedback edits existing spec sections only.

## Inputs

- `docs/spec-loop-runs/<slice-id>/specification.handoff.md`
- `docs/spec-loop-runs/<slice-id>/implementation.handoff.md`
- `docs/spec-loop-runs/<slice-id>/verification.handoff.md`
- `docs/SPECIFICATION.md` (the file being reconciled)

## Output

1. **Edits to `docs/SPECIFICATION.md`** — for each verification finding:
   - **Specification defect** → tighten the offending §9 criterion so it becomes
     evaluable, or fix the §4/§3 wiring it exposed.
   - **Open question resolved** → move it out of §10 into the settled section it belongs
     to; **newly surfaced** question → append it to §10.
   - **Implementation defect that revealed a spec ambiguity** → clarify the criterion so
     the ambiguity cannot recur.
2. **`docs/spec-loop-runs/<slice-id>/reconciliation.handoff.md`** with:
   - **Spec edits made** — a short diff summary (section → what changed → which finding
     it answers).
   - **Defects folded** — table: verification finding → where it landed in the spec.
   - **Loop routing** — for any still-open defect, which stage it returns to
     (spec defect → stage 1; implementation defect → stage 2).
   - **Next slice** — the next bounded slice id to feed into stage 1, with one-line
     rationale (from §3.3 "the thin delta").

## Workflow

1. Read the verification handoff; enumerate every defect and discovery.
2. For each, edit the exact `SPECIFICATION.md` section it belongs to (tighten a row,
   resolve/append an §10 question, correct wiring). Do not create parallel docs.
3. If verification's overall verdict was FAIL, record the routing so the blocking stage
   reruns — do not mark the slice done.
4. Pick the next slice and record it.
5. Write the reconciliation handoff.

## Exit-check

- Spec now reflects reality: no discovery left only in chat, a todo, or a handoff.
- Every verification finding is either folded into the spec or explicitly routed back to
  a stage.
- Only `SPECIFICATION.md` (and the reconciliation handoff) were edited — no new docs.
- The next slice is named, so gate 1 can start again.
