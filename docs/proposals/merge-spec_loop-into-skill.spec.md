# Spec: merge `docs/SPEC_LOOP.md` into the `spec-loop` skill

> Status: **Proposed**. This document specifies a future merge; **it performs no merge
> itself**. `docs/SPEC_LOOP.md`, `docs/SPECIFICATION.md`, and every file under
> `.agents/skills/spec-loop/` are unchanged by this document. It follows the same
> evaluable, five-field acceptance-criteria convention defined in `docs/SPEC_LOOP.md`
> so a future pass can execute it without re-deriving intent.
>
> Path rationale: placed under `docs/proposals/` (new directory) rather than editing
> `docs/SPECIFICATION.md` directly, because this is a process/tooling change to how the
> loop's own instructions are packaged, not a change to the `mcp-n4j-memory` product
> contract that `SPECIFICATION.md` governs. Keeping it as a standalone proposal avoids
> mixing a meta-process decision into the product spec's `G*`/`C*` numbering.

## 1. Goal and rationale

Today the spec-loop's process rules exist in **two places**:

- `docs/SPEC_LOOP.md` — the full six-gate process definition: the five-field acceptance
  criteria standard, the evidence bundle, the machine-readable `verification.report.yaml`
  schema, the Gate 2 clarification policy (three classes, deterministic procedure), and
  the loop invariants.
- `.agents/skills/spec-loop/` — a *separated-role execution wrapper* around that same
  loop: four sub-skills (`specification-agent`, `implementation-agent`,
  `verification-agent`, `reconciliation-agent`) plus an `exercise/comparison-template.md`,
  each of which **already quotes, paraphrases, or cites** specific `SPEC_LOOP.md`
  sections by name (e.g. "`SPEC_LOOP.md` §'Evidence bundle'", "the six-type
  `SPEC_LOOP.md` §'Verification-failure classification' table", "the full Gate 2
  clarification policy").

This is a **two-source-of-truth** problem: any future edit to a shared rule (the five
fields, the failure-classification table, the `defect_type` enum, the three
information classes) must currently be made once in `SPEC_LOOP.md` and, if the skill's
paraphrase drifts from it, again in every sub-skill file that paraphrases it. Nothing
today enforces that the two stay in sync. G (rationale) — **consolidate the process
definition into a single canonical location so the skill and the standalone doc cannot
silently diverge**, while preserving the current behaviour of both (a human reading
`docs/SPEC_LOOP.md` and an agent invoking the `spec-loop` skill must both still get the
complete, correct process).

## 2. Canonical location decision

**Decision (Class 1 — product/process decision, recorded here for the future merge
pass to execute, not re-litigate):** the skill directory becomes the **canonical,
single source of truth** for the spec-loop process. Rationale:

- The skill is the form actually *invoked* by agents (`/spec-loop`,
  `/specification-agent`, etc.); a doc that isn't loaded at invocation time is more
  likely to silently drift.
- The skill is already split into role-scoped files (one per gate-pair/stage), which is
  a *better* factoring for the content than one flat `SPEC_LOOP.md` — each sub-skill can
  own exactly the rules its stage needs instead of every reader scanning one long file.
- `SKILL.md`'s `metadata.revision` field gives the skill directory a versioning hook
  `SPEC_LOOP.md` does not have.

Alternative considered and rejected: making `SPEC_LOOP.md` canonical and the skill a
thin pointer into it. Rejected because the skill's per-stage isolation contracts
(`specification-agent/SKILL.md`, etc.) need the relevant subset of each rule
**embedded in their own file** — a downstream stage in the separated-role workflow
consumes only its own artifact/skill file by design (see `SKILL.md` §"Isolation
contract": stage N may read only the artifacts named in its Input column), so a
"thin pointer" back to a *different* document the stage isn't supposed to open would
violate that same isolation contract the skill exists to enforce.

## 3. Content mapping: `SPEC_LOOP.md` sections → skill destination

| `SPEC_LOOP.md` section | Destination file | Disposition |
|---|---|---|
| Title/intro framing ("turn SPECIFICATION.md into working software one slice at a time") | `.agents/skills/spec-loop/SKILL.md` (top, replacing/extending current intro) | Merge — becomes shared framing above the four-stage pipeline diagram. |
| "Prime directive: write evaluable statements, not prose" + "Anatomy of a requirement" (5-field table) | `specification-agent/SKILL.md` §"Output" item 2, and `SKILL.md` §"Artifact contracts" | Merge — already partially duplicated (`specification-agent/SKILL.md` lists the 5 fields); becomes the single full statement, others reference it by heading, not by re-copying prose. |
| "Roles of the two artifacts" (`SPECIFICATION.md` vs `todos`/`todo_deps`) | `SKILL.md` (new "Durable vs ephemeral state" subsection) | Merge — currently absent from the skill; needed context for why only reconciliation-agent edits `SPECIFICATION.md`. |
| "The loop (six gates, one slice per pass)" table | `SKILL.md` §"Declared inputs and outputs per stage" (already maps stages 1–4 to gates 1–6) | Reconcile — `SKILL.md`'s existing table is the authoritative merged form; fold in any gate wording from `SPEC_LOOP.md` not already reflected (e.g. exact Exit-check phrasing per gate) as a per-stage "Exit-check" cross-reference. |
| "Closing the loop: results must move code or the spec" + "Verification-failure classification" table | `reconciliation-agent/SKILL.md` §"Output" item 2 "Loop routing" | Merge — `reconciliation-agent/SKILL.md` already paraphrases the six-type table; replace the paraphrase with the authoritative table copied in full, once, here. |
| "Evidence bundle" (definition + rules + worked-example pointer) | `implementation-agent/SKILL.md` §"Output" item 4 and §"Workflow" item 3 | Merge — same treatment: authoritative full text lives here; `verification-agent/SKILL.md` and `SKILL.md` reference this file by heading instead of re-describing it. |
| "Verification report (machine-readable proof)" (YAML schema + `defect_type` enum + rules) | `verification-agent/SKILL.md` §"Output" (already paraphrases the schema and enum) | Merge — authoritative schema block (the fenced YAML + enum table) moves here verbatim; this becomes the one place the schema is defined. |
| "Gate 2 clarification policy" (three classes, deterministic classification procedure, refinement workflow, smallest-decision-set rules, recording safe choices, self-check) | `specification-agent/SKILL.md` §"Workflow" item 2 | Merge — this is the largest block; `specification-agent/SKILL.md` currently compresses it into a few bullet points. The full policy (all five subsections) moves here as the authoritative version. |
| "Invariants" | `SKILL.md` (new "Invariants" section near the end) | Merge — currently absent from the skill as a standalone list; add verbatim. |
| "Slice backlog" (SQL query against `todos`/`todo_deps`) | `SKILL.md` §"Running one slice" (new step 0, before step 1) | Merge — operational detail missing from the skill today. |

**Canonical-copy rule for the merge pass:** every rule above is copied **once**, into
exactly the destination file listed. Every *other* skill file that currently
paraphrases or partially restates that rule is edited to **cross-reference** the
destination file/heading (e.g. "see `implementation-agent/SKILL.md` §'Evidence
bundle'") instead of re-stating it. This is what "canonical location" means in
practice: one full copy, N pointers.

## 4. Reconciling duplication/overlap between `SPEC_LOOP.md` and the current `SKILL.md`

Overlap exists today in three forms, each with a distinct reconciliation rule:

1. **Verbatim-adjacent duplication** (e.g. the five-field list appears in both
   `SPEC_LOOP.md` and `specification-agent/SKILL.md`): keep the fuller/authoritative
   version (per §3 mapping), delete the shorter duplicate, replace it with a
   cross-reference.
2. **Structural overlap, different granularity** (`SPEC_LOOP.md`'s six-gate table vs.
   `SKILL.md`'s four-stage-to-six-gate table): `SKILL.md`'s stage-oriented table is kept
   as-is (it is the skill's operative table); `SPEC_LOOP.md`'s gate-oriented framing is
   folded in only as much as needed to keep the "why gates 1–2 collapse into stage 1"
   etc. mapping explicit — no separate parallel gate table is retained once merged.
3. **Named references that would become dangling** (every sub-skill's `SPEC_LOOP.md
   §"..."` citation, e.g. `implementation-agent/SKILL.md`'s "see `SPEC_LOOP.md`
   §'Evidence bundle'"): each such citation is rewritten to point at the new in-skill
   location established by §3 (same-file heading if the content now lives in that file,
   or another skill file's heading if it lives there instead).

No content is deleted outright; every `SPEC_LOOP.md` section in §3's mapping table has
exactly one destination, so nothing is dropped, and nothing survives in two full copies.

## 5. Disposition of `docs/SPEC_LOOP.md` after the merge

**Decision (Class 1, recorded for the merge pass):** `docs/SPEC_LOOP.md` becomes a
**short stub** (not deleted outright), for these reasons:

- `docs/SPECIFICATION.md`'s own header links to it (`` [`SPEC_LOOP.md`](./SPEC_LOOP.md) ``)
  and describes it as "the loop" the spec is changed via — an outright deletion would
  break that link and strand the sentence describing the mechanism.
- `docs/spec-loop-runs/docker-compose/implementation.handoff.md` §4 is cited by name
  from `SPEC_LOOP.md`'s "Evidence bundle" section as a worked example; a stub preserves
  discoverability for anyone who still lands on `docs/SPEC_LOOP.md` first (e.g. via an
  old link, a search engine, or a stale local clone) without leaving a 404 or an empty
  file.
- A full removal is a one-way door for any external link or agent memory that still
  names `docs/SPEC_LOOP.md` (blast-radius test in the Gate 2 policy this very document
  is about → leans Class 1/cautious; a stub is the reversible, low-risk choice).

**Stub content requirement:** the stub retains the title, a one-paragraph description
of what the loop is, and a single explicit pointer: "The full process now lives in
`.agents/skills/spec-loop/` (start at `SKILL.md`)." It must **not** duplicate any
five-field list, table, schema, or policy — those are removed from this file entirely
once moved, per §3/§4, to guarantee there is exactly one canonical copy.

Alternative considered and rejected: deleting `docs/SPEC_LOOP.md` entirely. Rejected
per the one-way-door reasoning above; revisit only if a future pass confirms (Class 2,
investigate) that no remaining reference to the file exists anywhere in the repo or in
recorded external links.

## 6. Backward-compatibility / references to handle

The merge pass **must** locate and update every reference to `docs/SPEC_LOOP.md`,
specifically (confirmed present as of this writing by repo search):

| Referencing location | Current reference | Required update |
|---|---|---|
| `docs/SPECIFICATION.md:7` header | `` via the loop in [`SPEC_LOOP.md`](./SPEC_LOOP.md) `` | Keep the link (stub still exists at the same path per §5); no path change needed, but confirm the stub still supports the sentence's claim ("edits it" / "gate 6") after the merge. |
| `docs/SPECIFICATION.md:250` | "the five-field acceptance-criteria standard defined in `[`SPEC_LOOP.md`](./SPEC_LOOP.md)` ('Anatomy of a requirement')" | Keep the link for the same reason; the heading name "Anatomy of a requirement" moves to whichever skill file now owns it (§3 row 2) — if the stub no longer contains a heading of that name, reword this sentence to name the new in-skill location instead of a heading inside the stub. |
| `.agents/skills/spec-loop/SKILL.md:4,13` | Description frontmatter + intro prose: "A four-stage pipeline that runs one `SPEC_LOOP.md` pass..." | Update wording once the loop's definition itself lives in this file (§3 rows 1, 3, 4, 8) — reword to "runs one spec-loop pass" or similar, dropping the file-name citation since the process is now defined here, not fetched externally. |
| `.agents/skills/spec-loop/specification-agent/SKILL.md:20` | "Runs `docs/SPEC_LOOP.md` gates **1 (Understand)** and **2 (Gap-check)**, including the full Gate 2 clarification policy." | Update wording once the Gate 2 policy body lives in this same file (§3 row) — the sentence should say the policy is defined **below**, not fetched from `SPEC_LOOP.md`. |
| `.agents/skills/spec-loop/implementation-agent/SKILL.md:19,49` | "Runs `docs/SPEC_LOOP.md` gates **3 (Propose)** and **4 (Execute)**." and "(see `SPEC_LOOP.md` §'Evidence bundle')" | Same treatment — the evidence-bundle citation becomes a same-file heading reference; drop the gate-number citation to the external file. |
| `.agents/skills/spec-loop/verification-agent/SKILL.md:21,57,67,84` | "Runs `docs/SPEC_LOOP.md` gate **5 (Verify)**", "§'Verification-failure classification'" (×2), "schema and rules in `SPEC_LOOP.md`" | Rewritten to same-file/cross-skill-file headings per §3 (the classification table and the report schema both move into this file per §3, so these become self-references, not citations). |
| `.agents/skills/spec-loop/reconciliation-agent/SKILL.md:19,52` | "Runs `docs/SPEC_LOOP.md` gate **6 (Feed back)**", "per the `SPEC_LOOP.md` §'Verification-failure classification' table" | Rewritten per §3 — the classification table's canonical copy lives in `reconciliation-agent/SKILL.md` itself after the merge, so this becomes a same-file reference; `verification-agent/SKILL.md` cross-references it instead of re-copying it. |
| `docs/spec-loop-runs/docker-compose/implementation.handoff.md:31` | "Worked example of the `SPEC_LOOP.md` §'Evidence bundle' format" | This is a historical run artifact, not part of the skill or the spec — leave unedited; it is a point-in-time record of a past pass and citing the (still-existing, stubbed) file by name remains accurate as a historical pointer. Do not retroactively edit past run artifacts. |
| Any Copilot/agent memory entries mentioning `docs/SPEC_LOOP.md` by path | Not discoverable via repo search (external to this repo's files) | Out of scope for the merge PR itself to edit (memories are edited via the Memory UI, not files); flag in the merge PR description that memories referencing the old path should be reviewed by their owners. |

The reference set above was enumerated by a full-repository text search for the
literal string `SPEC_LOOP.md` across all `.md` files (excluding `.git/`); the merge
pass must re-run this same search against its own HEAD before considering AC-2 (§8)
satisfied, since new references could be added between this document's writing and the
merge PR.

## 7. In scope / out of scope

**In scope for the future merge pass this spec describes:**

- Moving the content per the §3 mapping table into the five skill files.
- Rewriting every internal citation identified in §4/§6 to a same-repo, in-skill
  heading reference.
- Reducing `docs/SPEC_LOOP.md` to the stub described in §5.
- Updating `docs/SPECIFICATION.md`'s header sentence only if the stub can no longer
  literally support it (Class 2 check at merge time; otherwise leave unchanged).
- Bumping `metadata.revision` in every touched `SKILL.md` file (repo convention:
  `SKILL.md` files carry a `metadata.revision` integer; incrementing it signals the
  skill content changed).

**Out of scope (explicitly not covered by the merge this spec describes):**

- Any change to `docs/SPECIFICATION.md`'s Goals/Constraints/§9/§10 content — the merge
  is a process/tooling consolidation, not a product-spec change.
- Any change to `.agents/skills/spec-loop/exercise/comparison-template.md`'s scoring
  methodology — it may gain corrected cross-references (§6) but its metrics/protocol
  are unchanged.
- Deleting `docs/SPEC_LOOP.md` outright (see §5 — stub, not deletion, is the specified
  outcome).
- Renaming the `spec-loop` skill, changing its directory layout, or adding/removing
  sub-skills.
- This document itself performs **no** file moves, edits to `SPEC_LOOP.md`, or edits to
  any skill file — it is a plan only.

## 8. Acceptance criteria (five-field, evaluable)

Each criterion below is written against the **future merge PR**, not against this
specification document. This document's own PR only needs to satisfy §9 ("Acceptance
criteria for this document").

### AC-1 — Every `SPEC_LOOP.md` section has exactly one destination and zero duplicate copies

- **Trigger:** The merge PR is opened for review.
- **Preconditions:** The §3 mapping table in this spec is used as the checklist.
- **Expected observable outcome:** For every row in §3, the referenced content
  (five-field list, gate table, closing-the-loop text, evidence bundle, verification
  report schema, Gate 2 policy, invariants, slice-backlog query) appears in full in
  exactly one file under `.agents/skills/spec-loop/`, and nowhere else does that same
  prose/table appear a second time in full.
- **Failure behaviour:** If any block appears in two files verbatim (or near-verbatim,
  >80% token overlap), the PR is rejected and the duplicate must be replaced with a
  cross-reference before merge.
- **Verification method:** `grep`/diff-based check: for each of the 8 named blocks in
  §3, run a fixed-string search across `.agents/skills/spec-loop/**/*.md` and assert a
  match count of exactly 1 file.

### AC-2 — Every existing `SPEC_LOOP.md` citation in the skill is rewritten, none dangle

- **Trigger:** The merge PR is opened for review.
- **Preconditions:** §6's reference table lists every citation to update.
- **Expected observable outcome:** `grep -rn "SPEC_LOOP.md" .agents/skills/spec-loop/`
  returns zero matches (all in-skill citations now point to in-skill headings).
- **Failure behaviour:** Any remaining match is a dangling/stale cross-reference; PR is
  rejected until it is rewritten or intentionally justified as a link to the stub.
- **Verification method:** `grep -rn "SPEC_LOOP.md" .agents/skills/spec-loop/ | wc -l`
  must output `0`.

### AC-3 — `docs/SPEC_LOOP.md` is reduced to the specified stub, not deleted

- **Trigger:** The merge PR is opened for review.
- **Preconditions:** File `docs/SPEC_LOOP.md` exists at HEAD before the merge PR.
- **Expected observable outcome:** After the merge, `docs/SPEC_LOOP.md` still exists,
  is shorter than its pre-merge line count, contains the literal pointer text
  `.agents/skills/spec-loop/`, and contains none of the 8 §3 content blocks in full.
- **Failure behaviour:** If the file is deleted, or still contains a full copy of any
  §3 block, the PR is rejected.
- **Verification method:** `test -f docs/SPEC_LOOP.md`; `wc -l docs/SPEC_LOOP.md`
  compared against the pre-merge count; `grep -c ".agents/skills/spec-loop"
  docs/SPEC_LOOP.md` returns `>= 1`.

### AC-4 — `docs/SPECIFICATION.md`'s link to `SPEC_LOOP.md` still resolves

- **Trigger:** The merge PR is opened for review.
- **Preconditions:** `docs/SPECIFICATION.md` header links to `./SPEC_LOOP.md`.
- **Expected observable outcome:** The relative link target `docs/SPEC_LOOP.md` still
  exists on disk after the merge (per AC-3), so the link is not broken.
- **Failure behaviour:** If `docs/SPEC_LOOP.md` were removed or renamed, this link
  would 404 in any Markdown renderer; PR is rejected.
- **Verification method:** `test -f docs/SPEC_LOOP.md` (same file check as AC-3,
  re-asserted from the consumer side).

### AC-5 — Every touched `SKILL.md`'s `metadata.revision` is incremented

- **Trigger:** The merge PR is opened for review.
- **Preconditions:** A `SKILL.md` file's content changed as part of the merge.
- **Expected observable outcome:** That file's YAML frontmatter `metadata.revision`
  integer is strictly greater than its value at the PR's base commit.
- **Failure behaviour:** A changed `SKILL.md` with an unchanged `revision` value is
  flagged as a convention violation and blocks merge.
- **Verification method:** For each changed `SKILL.md`, `git diff <base>...<head> --
  <file>` shows a non-empty diff; the `metadata.revision` line's value in `<head>` is
  numerically greater than in `<base>`.

### AC-6 — No product-spec content is touched by the merge PR

- **Trigger:** The merge PR is opened for review.
- **Preconditions:** `docs/SPECIFICATION.md` §§1–10 (Goals, Constraints, wiring,
  acceptance criteria, Open questions) exist at the PR's base commit.
- **Expected observable outcome:** `git diff <base>...<head> -- docs/SPECIFICATION.md`
  is empty, or touches only the single header sentence identified in §6 if the Class 2
  check there determines an update is factually required.
- **Failure behaviour:** Any other change to `docs/SPECIFICATION.md` (a Goal,
  Constraint, §9 criterion, or §10 question) is out of scope (§7) and blocks merge.
- **Verification method:** `git diff <base>...<head> -- docs/SPECIFICATION.md` reviewed
  line-by-line against the allow-list (header sentence only).

## 9. Acceptance criteria for *this* document's own PR

- **Trigger:** This specification document's PR is opened for review.
- **Preconditions:** None (this is the first artifact in the chain).
- **Expected observable outcome:** `git status --short` for the PR's diff shows exactly
  one new file, `docs/proposals/merge-spec_loop-into-skill.spec.md`; no other tracked
  file is modified, and no file under `.agents/skills/spec-loop/` or at
  `docs/SPEC_LOOP.md` / `docs/SPECIFICATION.md` is touched.
- **Failure behaviour:** Any additional changed/staged path other than the new file
  fails this check and the PR must be corrected before merge.
- **Verification method:** `git status --short` run against the PR branch; must show a
  single `A` (added) line for the new file path and nothing else.

## 10. Open questions

- None blocking — this document specifies the merge; the merge pass itself may
  surface Class 1 questions (e.g. exact wording of the `docs/SPECIFICATION.md` header
  sentence if it needs to change) which belong to that future pass, not to this one.
