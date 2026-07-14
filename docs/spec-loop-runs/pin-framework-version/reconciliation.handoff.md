# Reconciliation handoff — `pin-framework-version`

Gate 6 (Feed back). Consumed `specification.handoff.md`, `implementation.handoff.md`,
and `verification.handoff.md` for this slice; edited only `docs/SPECIFICATION.md` and
this handoff, per the reconciliation-agent isolation contract.

## 1. Spec edits made

| Section | Change | Answers |
|---|---|---|
| §10 Open questions | Split the combined "Pin the exact framework version and Anthropic model id (needs confirmation)... must be confirmed before merge" bullet in two. Removed the framework-version half entirely (it is now resolved, see below). Kept and re-stated the Anthropic model-id half as unchanged standing policy ("floating fact, re-verified per run"), adding a clause noting it is unaffected by the framework-version confirmation, so the bullet no longer implies the model id itself was pending. | Verification's overall PASS verdict; PIN-01/PIN-02 evidence that the pin is confirmed correct with no code change; PIN-03's confirmation that the model-id policy is untouched and internally consistent. |
| §10 Resolved items | Added a new top entry: "Resolved in `pin-framework-version` (CONFIRM-NO-CHANGE): the `neo4j-agent-memory[mcp,sentence-transformers,openai]==0.2.0` pin in `docker/mcp.Dockerfile` (line 13) is confirmed correct; no code change was needed." Records the PyPI resolution evidence (happy path + proven failure path), the decision of record to defer upgrading to `0.5.0` to a separate future slice, and cites this reconciliation handoff. | PIN-01 (happy + failure path) and PIN-02 evidence bundles; the Class 3 "defer upgrade" safe choice recorded in the specification handoff §6. |

The line-13-vs-14 citation drift noted by Verification (§2 "Missing evidence") is now
moot in the durable spec: the new Resolved-items entry cites line 13 directly (the
verified, current location), so no stale `:14` reference persists in
`docs/SPECIFICATION.md`. No separate edit was needed to "correct" the old citation
because the old open-questions bullet (which carried no line number) was removed
outright rather than patched.

## 2. Findings folded

| Verification finding | Type | Where it landed |
|---|---|---|
| PIN-01/PIN-02 PASS with reproduced evidence; pin confirmed correct, no code change needed | Open question resolved | §10 moved from Open questions → Resolved items (new entry above) |
| PIN-03 PASS; model-id policy untouched and consistent | Confirmation of existing resolved policy | §10 Open questions bullet re-worded to make clear the model-id half was never in question and remains current policy; no separate action needed since PIN-03 required no code or spec change |
| Citation drift: handoffs cited `docker/mcp.Dockerfile:14`; actual line is 13 | Behaviour is unspecified / documentation drift (non-blocking, not a code or requirement violation) | §10 Resolved items — the new entry cites line 13 directly, so the correct line number is now the durable record; no further action |
| `.gitignore:17` (`pip-scratch/`) does not glob-match the `pip-verify-scratch` scratch-dir name used by the Verification method | Requirement is imprecise, non-blocking | Not folded into this pass — Verification explicitly routed this as "a future spec revision should correct the `.gitignore` reference... but this is not required to close this slice." Left as a low-priority residual for a future `§9 Verification method` touch-up if `pin-framework-version`-style checks recur; not re-opened as a new §10 item since it does not block any dependent slice and the scratch dirs are already deleted every run regardless. |

## 3. Loop routing

Both classified findings from Verification's §4 table were the same non-blocking
"behaviour is unspecified / minor documentation drift" type, routed to gate 6. Both
are now resolved: the line-number citation is corrected at its landing point in the
new Resolved-items entry (moot going forward), and the `.gitignore` pattern note is
explicitly deferred (recorded here, not silently dropped) since it does not gate this
slice's closure. No `code_violation`, `contradictory_requirement`,
`missing_evidence`, `new_constraint`, or `weak_verification` findings were reported,
so no code-fix or constraint-update routing was required this pass.

## 4. Authorship / no-code-change statement

This SPECIFICATION.md edit was authored by the Reconciliation agent (gate 6), the only
stage permitted to edit this file. **Implementation made no code change** — outcome is
CONFIRM-NO-CHANGE: `docker/mcp.Dockerfile`, `litellm/config.yaml`, and (by
Implementation itself) `docs/SPECIFICATION.md` were all left untouched by the
Implementation pass, independently confirmed by Verification's `git diff`/`git status`
checks. The only tracked-file change produced across this whole slice is this
reconciliation pass's edit to `docs/SPECIFICATION.md`.

## 5. Overall verdict

**PASS — loop closed.** Every requirement (PIN-01 happy/failure path, PIN-02 pin-diff +
scope, PIN-03 model-id consistency) passed with independently reproduced evidence from
both Implementation and Verification. The one discovery (framework-version pin
confirmed, §10 caveat resolvable) has moved into the spec (§10 Resolved items); the two
non-blocking documentation-drift findings are folded/deferred as recorded above. No
result from this pass changed neither the code nor the spec — the resolved-item spec
edit is the landing point for the substantive finding, and the two citation-drift notes
are explicitly acknowledged rather than left only in chat/handoffs.

## 6. Backlog status / next slice

**No actionable non-blocked slices remain.** Reviewing §10 Open questions after this
edit:

- **Blocked, not actionable now:** `prod-anthropic-verify`'s remaining item — the
  real-Anthropic R1 positive-completion path — is blocked on supplying a genuine
  `sk-ant-api…` API key (the only credential available is an OAuth token, which cannot
  authenticate to `api.anthropic.com` via LiteLLM's `anthropic/` provider). Cannot
  proceed without that credential being supplied to `llm-proxy` only.
- **Blocked, not actionable now:** the `github-models-llm-backend` security follow-up —
  replacing the broad `gh`-CLI OAuth token used for that slice's verification with a
  fine-grained GitHub PAT scoped to `models: read` only — is blocked on such a
  fine-grained token being available/provisioned.
- **Optional, deliberately deferred (not blocked, but not a bounded thin-delta slice
  right now):**
  - Externalizing the embedder into its own container on `embed-net` (cost/size
    optimization, not a correctness gap).
  - Optional host-level egress rules restricting internet access to `llm-proxy` alone
    (defense-in-depth on top of the existing `llm-egress-net` docker-network scoping).
  - Upgrading `neo4j-agent-memory` from `0.2.0` to `0.5.0` — explicitly deferred by this
    slice's own decision of record (separate, dedicated slice needed given the
    framework's CLI/env-var/MCP-tool-behaviour surface this repo depends on).

No new slice is named as "next" — every currently open item is either blocked on an
external credential/token or is optional, deferred, non-blocking future work with no
dependent slice waiting on it. The loop remains open for whenever a real
`sk-ant-api…` key or a fine-grained `models: read` PAT becomes available, or when the
project chooses to spend a slice on one of the optional deferred items above.
