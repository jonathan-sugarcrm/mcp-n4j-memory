# Reconciliation handoff: `extractor-wiring-fix`

Consumed **only** `specification.handoff.md`, `implementation.handoff.md`, and
`verification.handoff.md` for this slice. Independently re-derived the edits below from
the Evidence bundle / Independent reproduction log in those three handoffs — the
implementation's proposed §5 text was used as a starting draft, not copied verbatim
without re-derivation (the second edit in particular reframes it to explicitly close the
self-contradiction, which the proposed text alone did not fully do).

## 1. Spec edits made (diff summary)

**File touched:** `docs/SPECIFICATION.md` only (+44/-27 lines). No other file edited.

| Section | What changed | Which finding it answers |
|---|---|---|
| §10 Open items → Resolved items (was `:562-578`, the `create_llm_extractor() wiring gap — reassessed, narrowed but still open` bullet) | **Moved** the item out of Open items entirely and replaced it with a **Decision-of-record** bullet under Resolved items, styled like the existing `github-models-llm-backend` decision-of-record: states the env-mirror (`OPENAI_API_KEY`/`NAM_EXTRACTION__LLM_MODEL` mirroring `NAM_LLM__*`, plus the `openai` pip extra) is the **adopted, intentional** wiring (KEEP over PATCH), records the Class-3 rationale (patching the pinned, source-absent vendored package is fragile vs. an already-proven-working mirror), and states the failure mode verbatim if the mirror lines are ever deleted. Cites the code-level evidence (comments at `docker-compose.yml:48-51`/`:56-59`, `docker/mcp.Dockerfile`, zero functional diff) and explicit Reconciliation authorship. | REQ-1 (implementation handoff's proposed text, re-derived from the Evidence bundle row for REQ-1; resolves verification's `contradictory_requirement` finding F1 by delivering the spec-level deliverable REQ-1 always required). |
| §10 Resolved items (`:640-651`, the `Split out for its own slice: create_llm_extractor() ignores...` bullet, ending in the `weak_verification` flag) | **Split into two bullets.** First bullet trimmed to the framework-bug discovery/split-out fact only, now pointing to the Decision-of-record above instead of repeating it. **Second, new bullet** replaces the old "not yet independently confirmed and must be re-checked" sentence with the now-**proven** fact: a fresh clean-state mock-path `memory_store_message` call plus a direct `MENTIONS`-edge Cypher read found **zero** entity nodes, with a causal `mcp` log line (`Failed to parse LLM response as JSON`), independently reproduced twice (implementation + verification, different markers). States precisely that `llm-smoke`'s mock-path PASS proves persistence + routing + search only, **not** structured extraction, and that extraction is proven only by `github-models-llm-backend`'s real run. Explicitly notes §9's slice-status paragraph and the `llm-smoke` resolved-item bullet already scope their claims to the "persistence portion" of AC-G2 and do not claim mock-path extraction — so no further §9 wording edit was needed. | REQ-2 (PASS, both implementation and verification evidence); closes the two-place self-contradiction the task named (old `:570-578` "resolved by reasoning" vs. old `:646-651` "not yet independently confirmed") — there is now exactly one statement, backed by reproduced evidence, not two conflicting ones. |

**§9 AC-G2/AC-C6/AC-G3 slice-status:** read `:271-278` and the `llm-smoke` resolved-item
bullet (`:653-658`, post-edit line numbers) as part of this pass. **No edit made there** —
both already say "the LLM-triggering *persistence* portion of AC-G2" / "the LLM-triggering
portions of AC-G2/AC-G5", not "extraction", so they were already accurate and did not
assert the thing REQ-2's evidence just disproved. Widening scope here would have been an
unjustified edit; the new §10 bullet cross-references §9 instead of duplicating it.

## 2. Defects/findings folded — where they landed

| Verification finding | Type | Where it landed |
|---|---|---|
| F1 — REQ-1's outcome (a `SPECIFICATION.md` edit) could not be delivered by Implementation because that edit is Reconciliation-only | `contradictory_requirement` | Resolved by this Reconciliation pass actually landing the spec edit: new Decision-of-record bullet under §10 Resolved items (see table above). The spec handoff itself was already amended at gate 1 (per its own correction note) to reassign this deliverable to Reconciliation, so no further gate-1 action is needed — this pass is that reassigned deliverable being executed. |
| REQ-2 PASS — zero `MENTIONS`-linked entities on the mock path, causal JSON-parse-failure log line, independently reproduced | resolves prior `weak_verification` flag | New §10 Resolved-items bullet (see table above), replacing the old "not yet independently confirmed" text with the reproduced fact. |
| Two-place self-contradiction (old `:570-578` vs. old `:646-651`) | spec-authoring defect (stale forward-looking text written before this slice ran) | Both locations rewritten in this pass into one consistent, evidence-backed statement; the premature "this slice's R2 evidence resolves..." wording (which had been written referencing evidence that didn't yet exist) was removed and replaced with the actual evidence now in hand. |

**Loop-closure check:** every result from `verification.handoff.md` moved the spec.
REQ-1's `contradictory_requirement` is resolved by this pass delivering the exact edit the
spec always assigned to Reconciliation (not by further re-scoping gate 1, since gate 1 had
already amended the handoff correctly before this run). REQ-2's PASS and its evidence are
now durably recorded in `SPECIFICATION.md` rather than left only in the verification
handoff. Nothing here is merely noted without a corresponding spec edit — the loop is
closed for this slice.

## 3. Authorship statement

I (Reconciliation, gate 6) authored both `SPECIFICATION.md` edits described above in this
pass. Implementation (gate 4) did not touch `SPECIFICATION.md` — confirmed via its own
handoff §2/§5 and via `git status --short`/`git diff --stat` showing no
`SPECIFICATION.md` change prior to this Reconciliation pass. This satisfies REQ-1's
reassigned provenance requirement (spec edits are Reconciliation-only, evidenced by this
handoff file, per the same authorship-evidence convention used in
`docs/spec-loop-runs/mcp-env-cleanup/reconciliation.handoff.md`).

## 4. Next slice recommendation

Remaining actionable (unblocked) backlog items, in priority order:

1. **`acg6-lint`** — mechanise AC-G6 (currently unclear whether it has an automated,
   evidence-producing check or relies on manual/prose verification only). Unblocked, no
   external credential needed, directly continues this pass's theme of turning
   reasoning-by-analogy/manual checks into reproducible evidence.
2. **`pin-framework-version`** — decide and record whether/how to pin or track
   `neo4j-agent-memory`'s version more precisely, now that this pass has formally adopted
   (not merely tolerated) working around one of its bugs; reduces the risk of a future
   version bump silently changing `create_llm_extractor()`'s behavior underneath the
   env-mirror. Unblocked.

Blocked items (not recommended next, credential-gated):

- **Real-Anthropic positive-completion path (R1)** — blocked on a genuine `sk-ant-api…`
  API key (the available credential is an OAuth token LiteLLM's `anthropic/` provider
  cannot use); scoped only to `llm-proxy` when available.
- **`scope-github-token`** — narrowing the `github-models-llm-backend` verification
  credential from a broad `gh`-CLI OAuth token to a fine-grained PAT scoped to
  `models: read`; blocked on obtaining that PAT.
