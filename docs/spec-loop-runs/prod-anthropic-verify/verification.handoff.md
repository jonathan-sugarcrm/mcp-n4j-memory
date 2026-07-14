# Verification handoff — `prod-anthropic-verify`

## 0. Method note (what was reproduced vs. relied upon)

- **R3, R4:** fully re-derived independently. Stack was rebuilt clean
  (`docker compose down -v && docker compose up -d --build`) **without** sourcing the
  real key (a dummy `ANTHROPIC_API_KEY=change-me` from `.env` defaults is sufficient
  for network-topology and key-isolation probes — no credential exposure risk).
  `docker compose config`, TCP-connect probes from all three services, and the AC-C5
  rerun were executed by this agent, not copied from the implementation handoff.
- **R1, R2:** the real key was **not** re-sourced and no live Anthropic call was
  re-triggered by this agent. The implementation's own evidence already shows a
  **persistent account-level `429 rate_limit_error`** across 7 triggered calls / 28
  underlying requests and two cooldowns (60s, 90s); re-attempting would not produce
  new information, would burn further quota against the same account limit, and adds
  no verification value. Per the task's explicit guidance, this is declined and stated
  here explicitly: **R1/R2's verdicts below rest on the implementation's captured raw
  log excerpts (request/response bodies with real Anthropic `request_id`s), not on an
  independent live re-run.** The key was never printed, logged, or committed by this
  agent (confirmed: `git status`/`grep` show no key material, only variable names, in
  any tracked or new file).

## 1. Per-requirement verdict

| Req | Verdict | Check actually run | Observed result |
|-----|---------|---------------------|------------------|
| R1  | **FAIL** | Re-read implementation's evidence bundle (raw `llm-proxy` log excerpts across 7 triggered `scripts/llm_smoke.py` runs / 28 underlying requests, 2 cooldowns). No independent re-run (see §0). | Every attempt returned a genuine Anthropic `429 rate_limit_error` (real, distinct `request_id`s each time). `memory_store_message`'s extraction stage never completed successfully. The criterion's literal Expected observable outcome ("the tool call completes successfully... with a corresponding upstream response") was **not observed** in any run, by the implementer or by this agent. |
| R2  | **PASS** (evidence-caveated, see §0) | Re-read raw evidence: `grep -c "mock-ok: llm-smoke local response"` = 0 across the run; genuine Anthropic-shaped error bodies with real `request_id` values (`req_011Cd1mWzmzYFZ1gVfTnPYUC`, `req_011Cd1n1MVU6tL7jthfzinr2`, 28 distinct total) present in both the pre-fix `404 not_found_error` and post-fix `429 rate_limit_error` responses. Independently corroborated the plausibility of this evidence by confirming `llm-proxy` has live TCP reachability to `api.anthropic.com:443` (see R4) — the network path the evidence claims was used genuinely exists. | Zero mock-string hits; genuine, Anthropic-issued error envelopes (not litellm-local, not mock) present for every one of the 28 requests. Satisfies R2's "real model was hit, not mock" criterion even though no `200` was ever returned — a `404`/`429` **from Anthropic's own servers** is conclusive proof the real API was reached, per the task's own framing. |
| R3  | **PASS** | Independently rebuilt the stack clean and ran, myself: `docker compose exec mcp env \| grep -i anthropic` (empty, exit 1); `mcp` → `api.anthropic.com` TCP-connect probe (Python `socket.create_connection`, since `curl`/`wget`/`nc` are absent from the `mcp` image). | `grep -i anthropic` on `mcp`'s env: empty (no match). TCP connect from `mcp` to `api.anthropic.com:443`: `UNREACHABLE: [Errno -3] Temporary failure in name resolution` (DNS fails — `mcp` is not on any network with an external route). Matches spec's failure-mode requirement exactly. |
| R4  | **PASS** | Independently ran `docker compose config` (exit 0); TCP-connect probes from `llm-proxy`, `neo4j`, `mcp` to `api.anthropic.com:443`; reran the AC-C5 `neo4j`↔`llm-proxy` mutual-unreachability probes. | `docker compose config`: exit 0, resolved topology exactly as claimed — `llm-proxy` → `{llm-net, llm-egress-net}`, `mcp` → `{db-net, llm-net}` (unchanged), `neo4j` → `{db-net}` (unchanged); `llm-egress-net` is the only non-`internal` network. `llm-proxy → api.anthropic.com:443`: `CONNECT_OK`. `neo4j → api.anthropic.com`: `UNREACHABLE` (wget). `mcp → api.anthropic.com:443`: `UNREACHABLE` (DNS failure). AC-C5 rerun: `neo4j → llm-proxy:4000` `UNREACHABLE`; `llm-proxy → neo4j:7687` `UNREACHABLE` (DNS failure, no route). No regression. |

## 2. Missing evidence

- **R1** has no path to reproducible positive evidence in this environment: the
  blocker is an Anthropic account-level rate limit, external to the repository, and
  re-attempting is explicitly discouraged (quota-burning, no new information). This is
  recorded as `FAIL` / `missing_evidence`, **not** waived to pass — the criterion's
  literal outcome ("completes successfully") was never observed by anyone.
- **R2** rests on the implementation's raw evidence bundle plus this agent's
  independent corroboration of the surrounding network path (R4) and key isolation
  (R3), but the live Anthropic exchange itself was not re-triggered by this agent (see
  §0). This is disclosed rather than hidden; it is graded PASS because the evidence
  presented is raw (verbatim log/error bodies with distinct real `request_id`s), not a
  summary, and the one thing left unverified (whether the implementer's transcript is
  accurate) is not something a repeat live call would newly prove without spending
  more of the same limited account quota.

## 3. Regressions

- None found. AC-C5's `neo4j`↔`llm-proxy` mutual-unreachability probes were rerun
  independently by this agent and are unchanged (both still `UNREACHABLE`). `mcp` and
  `neo4j` network memberships (`docker compose config` output) are byte-for-byte
  identical to pre-slice topology except for the new, additive `llm-egress-net`
  attached only to `llm-proxy`.

## 4. Classified failures

| # | Finding | Type | Reason | Routing action |
|---|---------|------|--------|-----------------|
| 1 | R1's literal "completes successfully" outcome was never observed (implementer or this agent) — every attempt hit a genuine Anthropic account-level `429`. | **missing_evidence** | The criterion as written requires a positive completion; no reproducible positive evidence exists in this environment, and none is obtainable without a different (non-rate-limited) Anthropic account/tier. | Add evidence criteria at gate 1: relax R1's Expected observable outcome to accept "genuine non-mock Anthropic response (200, or a documented transient error class such as 429) with correct routing," since a fully-clean happy-path completion may never be exercisable against a shared/limited-quota account. Do not silently pass a 429 as R1 today. |
| 2 | The account-level Anthropic rate limit itself (persistent across two cooldowns, 7 calls / 28 requests). | **new_constraint** | A previously-unrecorded external constraint (this Anthropic key/account tier cannot sustain even light `memory_store_message` traffic without 429ing) directly limits how R1 can ever be exercised. | Record in `docs/SPECIFICATION.md` §Constraints: "the production-verification Anthropic key is rate-limited at the account level; R1's happy path requires either a higher-tier key or a slower/serialized trigger cadence with backoff, not currently guaranteed by this repo's tooling." |
| 3 | `litellm/config.yaml` model id changed (`claude-3-5-sonnet-latest` → `claude-sonnet-4-5`) for **both** `claude` and `claude-mock` entries, even though spec §5 "Out of scope" explicitly excludes "Pinning the exact Anthropic model id ... (tracked separately in §10's existing open item)." | **contradictory_requirement** | The spec's own Grounding facts recorded the old id as current/live, then explicitly fenced off changing it — but the id was stale (proven by a genuine Anthropic `404 not_found_error`), making the "don't touch this" boundary unsatisfiable as literally written. This is a genuine spec/reality mismatch, not an implementer decision to second-guess it. | Fix the specification: reconciliation should retroactively bless this change (it was necessary — without it, **nothing** using model `claude` works, mock or real) and update §5/§10 to stop treating the literal model id as immutable; record it as a floating fact re-verified per run, per the implementer's own flag. Process note: this should have been raised as a stop-and-report Class 1 item (an explicit scope fence was crossed) rather than silently implemented — acceptable in outcome, not in process. |
| 4 | `--detailed_debug` added to `llm-proxy`'s command and left in `docker-compose.yml`. | **unspecified_behaviour** (scope creep / debugging artifact) | Not required by any R1–R4 verification method (which greps normal-level `docker compose logs`), not mentioned anywhere in the spec, and not reverted after the verification pass. LiteLLM's `--detailed_debug` logs full upstream request/response payloads, which is a materially different (more verbose, more sensitive) logging posture than default — a persistent operational/security posture change disguised as a one-off debugging aid. | **Revert** before this slice merges, or split into its own explicitly-scoped, product-decided change ("should llm-proxy run with detailed debug logging by default, and what's the log-retention/redaction story for request bodies"). Do not ship as an undocumented side effect of a verification slice. |
| 5 | `OPENAI_API_KEY` and `NAM_EXTRACTION__LLM_MODEL` added to `mcp`'s environment in `docker-compose.yml`, to work around a discovered wiring gap in the vendored `neo4j-agent-memory==0.2.0` package (`create_llm_extractor()` ignores `NAM_LLM__API_KEY`/`NAM_LLM__MODEL`). | **new_constraint** (necessary fix, wrong slice) | This is a real, load-bearing fix — without it the extraction stage never attempts a network call at all, so R1/R2 are literally unexercisable — but it is a distinct, separately-reviewable functional bug fix (framework-config wiring), not a network/egress change, which is what this slice's spec scoped (§5 "In scope" lists only key-sourcing, model-env-var, and network changes). It also silently reveals that the **prior** `llm-smoke` slice's mock-path "PASS" may not have exercised real extractor wiring either (flagged by the implementer, not yet confirmed independently here). | **Keep** for now (reverting would re-block this slice entirely and there is no smaller fix), but **split**: open a dedicated slice/PR titled something like `fix-extractor-config-wiring` that (a) documents the wiring gap as a constraint, (b) re-verifies the *prior* `llm-smoke` slice's claims weren't silently broken by the same gap, and (c) considers patching the vendored package properly instead of compose-level env duplication (`OPENAI_API_KEY` mirroring `NAM_LLM__API_KEY` is a maintenance foot-gun — two names for one value, easy to drift). |
| 6 | `openai` pip extra added to `docker/mcp.Dockerfile`. | **new_constraint** (coupled to #5) | Direct, minimal consequence of #5 — `LLMEntityExtractor` needs the `openai` SDK to make the call at all. Not independently reviewable from #5. | Same routing as #5 — travels with it into the split-out slice. Keep as-is until #5 is resolved; no standalone action needed. |
| 7 | Two "pre-existing bug fixes" claimed in the implementation handoff. | (informational — not a defect) | On inspection only **one** was actually fixed in code (item #5/#6, the extractor wiring gap). The second ("`memory_store_message` doesn't surface per-stage extraction failures as tool errors") was only **flagged**, not changed — confirmed by rereading §5 "Blocking spec defects" item 3, which explicitly says "flagged... not resolved as pass/fail." No discrepancy found; implementation handoff's own wording is accurate on this point. | No routing action; noted for the record so reconciliation doesn't double-count it as two code changes. |

## 5. Overall verdict

**FAIL.**

R1 — the slice's headline outcome ("prove a real Anthropic-backed completion serves
`memory_store_message`") — was not achieved and has no path to reproducible positive
evidence in this environment (external account rate limit). R2/R3/R4 pass with
reproduced evidence (R3/R4 independently re-derived by this agent from a clean
rebuild; R2 evidence-caveated per §0). Additionally, three out-of-plan changes
(`litellm/config.yaml` model id, `--detailed_debug`, and the `mcp` extractor-wiring
env vars + `openai` extra) exceed this slice's explicit scope (§5) and must be
resolved by reconciliation before this slice can be considered closed: one should be
reverted (`--detailed_debug`), one should be retroactively accepted with a spec update
(model id), and one is a necessary-but-differently-scoped fix that should be split
into its own slice (extractor wiring + `openai` extra).
