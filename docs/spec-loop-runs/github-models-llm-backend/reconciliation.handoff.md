# Reconciliation handoff — `github-models-llm-backend`

**Authored by:** the Reconciliation agent (stage 4 / gate 6). Per the isolation contract,
this stage is the **only** one permitted to edit `docs/SPECIFICATION.md`; the edits described
below were made by this stage, not by Specification, Implementation, or Verification (which
correctly left the file untouched — confirmed by verification.handoff.md §4: "`docs/
SPECIFICATION.md` has no working-tree diff ... confirming the implementer did not touch the
file reserved for Reconciliation").

## 1. Overall verdict carried forward

**PASS** — R1–R4 all independently reproduced from a clean state (verification.handoff.md §5).
No classified failures; no regressions. The loop closes with spec edits only (no code-fix
routing required).

## 2. Spec edits made (diff summary)

| § | What changed | Answers |
|---|---|---|
| §9 slice-status paragraph | Appended a new paragraph documenting `github-models-llm-backend`: retargeted `claude` model_name to GitHub Models (`openai/gpt-4o-mini` + explicit `api_base: https://models.github.ai/inference` + `api_key: os.environ/GITHUB_API_KEY`); records the real `200` completion and real `memory_store_message` extraction evidence; states the routing/isolation guarantees are unchanged but now proven with a *real, completing* backend; explicitly narrows the still-open item to the **Anthropic-specific** positive path; records the `github/` vs `models.github.ai`/`models.inference.ai.azure.com` new constraint. | R1–R4 happy-path evidence; the "unverifiable requirement → add evidence" and "new constraint" routings. |
| §9.1 AC-C6 Verification method | Generalized wording from "the production Anthropic model" / "a real `ANTHROPIC_API_KEY`" to "the production model" / "the provider credential (`ANTHROPIC_API_KEY` / `GITHUB_API_KEY`, depending on which production model is active)"; added the GitHub Models real-completion evidence sentence; kept the Anthropic-specific deferred-path sentence verbatim (still true); added the `github/` prefix new-constraint sentence. | Verification's suggested wording generalization (task item 3); the `new_constraint` finding. |
| §9.2 AC-G3 Failure behaviour + Verification method | Generalized "no Anthropic key or egress" → "no provider key or egress for any production model"; Verification method now states `github-models-llm-backend` closed the *general* real-completion path via GitHub Models, and narrows the remaining deferred item to real-**Anthropic** specifically. | Same as AC-C6 above (AC-C6/AC-G3 share verification method per spec). |
| §10 open item ("Real-Anthropic positive completion…") | Renamed/narrowed to "Real-*Anthropic*-specific positive completion remains deferred", with an explicit forward-reference that the *general* real-backend question is now resolved; added a closing sentence downgrading its priority now that GitHub Models provides a working production backend. | Reflects that `prod-anthropic-verify`'s exact blocker (needs `sk-ant-api…`) is unchanged, but is no longer the only path to a real backend. |
| §10 new open item: constraint | Added "New constraint: LiteLLM's `github/<model>` provider prefix does not reach `models.github.ai`" — documents the Azure AI Inference silent-redirect behaviour and the required `openai/<model>` + explicit `api_base` workaround, so it isn't rediscovered. | The implementer's/verifier's `defect_type: new_constraint` finding (specification.handoff §5 "Blocking spec defects"; implementation.handoff §3 decision log; verification.handoff §4). |
| §10 new open item: security | Added a SECURITY item: this pass used a broad `gh`-CLI OAuth token as `GITHUB_API_KEY`; any persistent/production use must switch to a fine-grained PAT scoped to `models: read`, supplied to `llm-proxy` only. | implementation.handoff §6 "Credential handling note". |
| §10 `extractor-wiring-fix` item | Rewrote: kept the underlying framework bug description (unchanged, still true), but reassessed severity — this slice's R2 evidence (genuine end-to-end extraction via the existing `OPENAI_API_KEY`/`NAM_EXTRACTION__LLM_MODEL` workaround, confirmed by a manual in-container reproduction) **resolves the `weak_verification` concern** previously raised against `llm-smoke`: the extractor's LLM call path is genuinely exercised, both here and in the mock path, via the same workaround wiring. The item is downgraded from a verification-confidence risk to a code-hygiene item (whether to patch the vendored package instead of duplicating `NAM_LLM__*` via `OPENAI_API_KEY`) and its priority lowered. | task item 4 ("reassess ... honestly based on the evidence"); resolves the open `weak_verification` flag under "Resolved items". |
| §10 Resolved items — new entry (topmost) | Added "Resolved in `github-models-llm-backend`: a real, completing, non-mock LLM backend now works end-to-end through the proxy" — full evidence summary (real `200` + real extraction + isolation re-confirmed + no new network), the decision-of-record (explicit `api_base`, not `github/` prefix), the security note, and the GitHub-Models-free-tier production-scale caveat requested in the task constraints. | Moves the "real LLM positive-completion path" open item to RESOLVED (task item 2, first bullet); records the decision-of-record as a `new_constraint` (task item 2, second bullet); records the SECURITY note (task item 2, third bullet). |

No other sections were touched. No new documents were created besides this handoff.

## 3. Defects/findings folded → where they landed

| Verification finding | Classification | Landed in spec at |
|---|---|---|
| R1–R4 happy-path evidence (real GitHub Models completion + real extraction + isolation + no new network) | requirement met, evidence bundle | §9 slice-status paragraph; §9.1 AC-C6 / §9.2 AC-G3 Verification method |
| LiteLLM `github/<model>` prefix silently routes to `models.inference.ai.azure.com`, not `models.github.ai` | `new_constraint` | §9 slice-status paragraph; §9.1 AC-C6 Verification method; §10 open item; §10 Resolved-items decision-of-record |
| Broad `gh`-CLI OAuth token used for verification; production needs a scoped `models:read` PAT | `new_constraint` (operational/security) | §10 open item (SECURITY); §10 Resolved-items entry |
| `extractor-wiring-fix` weak_verification flag against `llm-smoke` | test-passes-but-outcome-was-uncertain, now resolved by stronger evidence | §10 `extractor-wiring-fix` item rewritten; "Resolved items" cross-reference retained |
| Real-Anthropic positive path still blocked on `sk-ant-api…` credential (unchanged fact) | unspecified/still-open (Class 1, credential availability) | §9 slice-status paragraph; §9.1 AC-C6 / §9.2 AC-G3 Verification method; §10 open item (narrowed + deprioritized) |
| Verification's minor "R2 log-correlation granularity" gap (compose-managed DEBUG log less verbose than a bare `docker run`) | not classified as a failure by Verification (substance met via independent triangulation) | Not folded as a spec change — correctly not a defect; no spec ambiguity was exposed, so no edit was needed for it specifically. |

Every result has moved either the spec (all findings above) or was explicitly confirmed as
not requiring a code or spec change (the R2 log-verbosity note, which Verification itself
classified as non-blocking and not a failure). No result was left as a bare note.

## 4. Next slice(s), priority order

1. **`github-token-scope-hardening`** — swap the broad `gh`-CLI OAuth token for a
   fine-grained GitHub PAT scoped to `models: read` only in any persisted/shared
   configuration (e.g. CI secrets, a shared dev `.env`), and re-verify R1/R3/R4 still hold
   with the narrower token. Highest priority: closes the SECURITY item recorded in §10 before
   this configuration is used anywhere beyond a one-off local pass.
2. **`extractor-wiring-fix`** (downgraded scope) — now a code-hygiene-only item: decide
   whether to patch the vendored `neo4j-agent-memory` package so `create_llm_extractor()`
   honours `NAM_LLM__API_KEY`/`NAM_LLM__MODEL` directly, instead of perpetuating the
   `OPENAI_API_KEY`/`NAM_EXTRACTION__LLM_MODEL` duplication. **Is it moot?** Not fully — the
   duplication still works correctly (re-confirmed this pass) and is not blocking anything,
   so this slice is optional cleanup rather than a verification-confidence fix; it can be
   deferred indefinitely without risk, unlike before this pass.
3. **`prod-anthropic-verify` (real-Anthropic path) — lowest priority, opportunistic only.**
   Close only if/when a genuine `sk-ant-api…` Anthropic API key becomes available; GitHub
   Models now provides a fully working, supported production backend, so this is no longer
   blocking any other capability — it only completes symmetry with the originally-scoped
   Anthropic-specific criterion wording.
