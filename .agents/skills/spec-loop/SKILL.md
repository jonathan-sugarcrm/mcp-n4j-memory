---
name: spec-loop
description: >
  A four-stage pipeline that runs one `SPEC_LOOP.md` pass with **no single agent
  context allowed to interpret, implement, and judge the same slice**. Splitting the
  roles removes the dominant failure mode of a lone agent: it grades its own homework
  and confirms its own assumptions.
metadata:
  revision: 2
---
# Spec-Loop: separated-role workflow

A four-stage pipeline that runs one `SPEC_LOOP.md` pass with **no single agent
context allowed to interpret, implement, and judge the same slice**. Splitting the
roles removes the dominant failure mode of a lone agent: it grades its own homework
and confirms its own assumptions.

```
Specification agent   →  Implementation agent  →  Verification agent  →  Reconciliation agent
   (gates 1–2)              (gates 3–4)               (gate 5)              (gate 6)
```

## Why separate the roles

A single uninterrupted context that interprets → builds → judges exhibits
**confirmation bias**: the same reasoning that chose an approach also decides whether
it worked, and silent assumptions made at interpretation time are invisible by
verification time. Separation forces every belief to survive a **context boundary**.

The mechanism that makes this real (not cosmetic):

- **Artifact-only handoff.** Each stage consumes **only the declared output artifact**
  of the prior stage — never its chat, scratch notes, or chain-of-thought. If a fact
  matters downstream it must be *written into the artifact*, or it does not exist.
- **Independent judgement.** The Verification agent is given the specification's
  criteria and the code, and must **re-derive** pass/fail from evidence — it is
  explicitly forbidden from trusting the Implementation agent's own claims.
- **Adversarial-by-role.** Verification reports *both* implementation defects and
  **specification defects** — so a bad spec is caught, not rubber-stamped.

Isolation can be literal separate agents (preferred) or the same model run in fresh
contexts that are handed only the artifact file. Either satisfies the boundary.

## Declared inputs and outputs per stage

Every stage has one input contract and one output artifact. Artifacts for a slice
live in `docs/spec-loop-runs/<slice-id>/`.

| Stage | Role | Input (consumes) | Output artifact | SPEC_LOOP gate |
|-------|------|------------------|-----------------|----------------|
| 1 | **Specification** | `docs/SPECIFICATION.md` + chosen slice id | `specification.handoff.md` | 1–2 (Understand, Gap-check) |
| 2 | **Implementation** | `specification.handoff.md` **only** | `implementation.handoff.md` + code changes | 3–4 (Propose, Execute) |
| 3 | **Verification** | `specification.handoff.md` + `implementation.handoff.md` + the actual repo | `verification.handoff.md` | 5 (Verify) |
| 4 | **Reconciliation** | all three handoffs | edits to `docs/SPECIFICATION.md` + `reconciliation.handoff.md` | 6 (Feed back) |

**Boundary rule:** stage N may read only the artifacts named in its Input column.
Reaching back into a prior stage's reasoning voids the isolation and is a process
defect.

## Artifact contracts (what each handoff MUST contain)

- **`specification.handoff.md`** — normalized requirements (5-field criteria, each
  traced to a `G*`/`C*`); unresolved decisions (open Class-1 questions); verification
  criteria (the exact check per requirement); explicit scope (in / out).
- **`implementation.handoff.md`** — implementation plan; changed files (path + why);
  decision log (every Class-3 safe choice with rationale); evidence (commands run +
  output, per requirement).
- **`verification.handoff.md`** — pass/fail per requirement; missing evidence;
  regressions; specification defects; implementation defects; overall verdict.
- **`reconciliation.handoff.md`** — the spec edits made (diff summary), which
  defects were folded where, and the next slice to pick.

## Running one slice

1. `/specification-agent` with a slice id → writes `specification.handoff.md`. If it
   emits open Class-1 questions, resolve them before stage 2.
2. `/implementation-agent` in a **fresh context** → reads only the spec handoff →
   writes code + `implementation.handoff.md`.
3. `/verification-agent` in a **fresh context** → re-derives pass/fail from evidence →
   writes `verification.handoff.md`.
4. `/reconciliation-agent` → folds every defect/discovery back into
   `docs/SPECIFICATION.md` → writes `reconciliation.handoff.md`.
5. If verification failed, loop back to the stage its defects blame (spec defect →
   stage 1; implementation defect → stage 2), not to the same context that produced them.

## Exercise: single agent vs separated roles

Run the **same slice** two ways and compare, to make the value measurable rather than
asserted.

- **Run A — single agent:** one context does interpret → implement → self-judge in a
  single pass. Record its own pass/fail claim.
- **Run B — separated roles:** the four stages above, artifact-only handoffs.

Score both with `exercise/comparison-template.md`:

| Metric | How measured |
|--------|--------------|
| Defect detection | # real defects (spec + impl) surfaced before "done" |
| Reproducibility | # declared PASS claims that fail to reproduce from a clean state using only the documented verification command |
| Unproven checks | # pass-criteria never shown able to fail (no mutation / failure-path test) |
| Rework | # slices reopened after being called done |
| Unsupported assumptions | # Class-3+ choices made with no recorded rationale / no evidence |

Expected signal: Run B detects more defects (independent verifier finds spec defects
Run A rationalized away), reworks less (assumptions caught at the boundary, not after
merge), and carries fewer unsupported assumptions (each must be written to cross a
handoff). Its PASS is also **reproducible from a clean state** and **teeth-proven**,
whereas a single agent tends to grade its own homework — passing only under env it
silently supplied, with checks it never failure-tested.
