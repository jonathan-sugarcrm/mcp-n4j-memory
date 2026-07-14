# Reconciliation handoff — `prod-anthropic-verify`

## 0. Authorship note

All edits to `docs/SPECIFICATION.md` described below were authored by this
Reconciliation stage (gate 6), per the single-writer rule in
`.agents/skills/spec-loop/reconciliation-agent/SKILL.md` — Stages 1–3 never mutate
`SPECIFICATION.md`. No other stage touched it for this slice (confirmed: the
implementation handoff explicitly states "`docs/SPECIFICATION.md` was deliberately
**not** touched — that is Reconciliation's job").

## 1. Overall verdict handled

Verification's overall verdict was **FAIL** (R1 not achieved). Per human-operator
direction, this is closed as a **partial close**: R2/R3/R4 are folded into the spec
as verified; R1 is folded in as an explicitly-scoped, precisely-diagnosed open item
rather than left ambiguous. The loop is closed for this slice (code cleaned up, spec
updated, next slices named) even though the slice's headline outcome (a real
positive completion) remains unmet — that residual is routed forward as its own
future slice, not silently dropped.

**New root cause (confirmed by the operator, supersedes the implementation/
verification handoffs' "external account-tier rate limit" theory):** the credential
at `~/.secrets/anthropic.env` is a **claude.ai / Claude Code OAuth token, not an
Anthropic API key**. LiteLLM's `anthropic/` provider authenticates to
`api.anthropic.com` with an API key (`sk-ant-api…`) and cannot use an OAuth bearer
token. The `429`s observed during verification were upstream rejections consistent
with this, not proof of account-tier throttling. Routing/isolation (R2/R3/R4) are
proven regardless, because reaching Anthropic's servers at all (even to receive a
`404`/`429`) required a genuine, correctly-routed, correctly-isolated request. The
secret value itself was never referenced, printed, or stored anywhere by this stage.

## 2. Code cleanup done (gate-6 fold-into-code)

- **`docker-compose.yml`**: reverted `--detailed_debug` from the `llm-proxy`
  `command:` array (was added as a one-off debugging aid during verification;
  flagged by verification finding #4 as an undocumented, more-verbose/more-sensitive
  logging posture change that should not ship). The `llm-egress-net` network change
  (D1/Option A) is **kept** — it is the legitimate, independently-reproduced R4
  deliverable (verification re-derived `docker compose config` topology and
  reachability probes from a clean rebuild).
- **Left as-is** (not reverted, not further edited here): `docker/mcp.Dockerfile`'s
  `openai` pip extra, `docker-compose.yml`'s `OPENAI_API_KEY`/
  `NAM_EXTRACTION__LLM_MODEL` additions on `mcp`, and `litellm/config.yaml`'s model-id
  change. These are real, load-bearing fixes (without them R1/R2 could not be
  exercised, and nothing using model `claude` — mock or real — would work), but two
  of them are out of this slice's scope and are split into their own slice (§4)
  rather than silently absorbed; the model-id change is retroactively accepted and
  recorded in the spec (§3 below) since it is a genuine external fact-lifecycle
  correction, not scope creep.

## 3. `docs/SPECIFICATION.md` edits made (diff summary)

| Section | Change | Finding answered |
|---------|--------|-------------------|
| §3.1 Runtime topology | Diagram prose now documents the real `llm-egress-net` network (non-internal, `llm-proxy`-only; `db-net`/`llm-net` unchanged) as the actual mechanism giving `llm-proxy` its Anthropic egress route, replacing a previously aspirational/unqualified statement. | R4 PASS (routing correction, §4/§3 wiring accuracy per skill). |
| §5 LiteLLM proxy config | Illustrative YAML's model id updated `claude-3-5-sonnet-latest` → `claude-sonnet-4-5`; added a note that the id is a floating fact re-verified per run, not a pinned literal. | Verification finding #3 (`contradictory_requirement` — stale grounding fact / out-of-scope-looking-but-necessary edit), retroactively blessed. |
| §9 slice-status (top of §9) | Added a paragraph recording `prod-anthropic-verify`'s runtime-verified routing/isolation (R2/R3/R4: `llm-egress-net`, `mcp` key/egress absence, non-mock Anthropic `request_id` evidence) and precisely restating R1's status and root cause (OAuth token vs. API key), replacing the old generic "deferred to a credentialed production environment" line. | R1 FAIL / missing_evidence (finding #1) — precision fix; R2/R3/R4 PASS. |
| §9.1 AC-C6 Verification method | Added the OAuth-vs-API-key precondition/caveat directly to the criterion's verification method, citing `prod-anthropic-verify` R1 evidence (genuine `429`/`404`, not a routing defect). | Requested "tighten AC-C6/AC-G3 verification-method wording" instruction; also closes the ambiguity that made R1 unverifiable as literally worded (finding #1 routing: "add evidence criteria... make it evaluable"). |
| §9.2 AC-G3 Verification method | Same OAuth-vs-API-key caveat added, cross-referencing AC-C6. | Same as above. |
| §10 Open questions | (a) Model-id placeholder line updated to reflect current `openai` extra + floating-fact treatment. (b) "Real-Anthropic positive path" bullet rewritten with the precise, confirmed blocker (OAuth token, not a key) instead of the vague "credentialed production environment" wording. (c) Host-egress bullet annotated to note `llm-egress-net` now provides the docker-network-level version. (d) New bullet added naming `extractor-wiring-fix` as a needed next slice, describing the `create_llm_extractor()` gap and its scope. | Findings #1, #2 (superseded/refined per operator), #5, #6. |
| §10 Resolved items | Four new entries appended: (1) AC-C6/AC-G3 routing/isolation verified against a real credential; (2) production model id updated (retired id confirmed via genuine Anthropic 404); (3) R1 positive-completion explicitly recorded as **not yet resolved**, with the precise credential-type blocker (kept in Resolved items as a "recorded precisely" entry per the skill's requirement that every result move code or spec — this is the spec-side landing of the FAIL, not a false "resolved"); (4) extractor-wiring gap split out to its own slice, with the `weak_verification` flag against the prior `llm-smoke` slice recorded per finding #7's caveat and finding #5's note. | Findings #1 (routed to spec + open item, not silently passed), #3, #5, #6, #7. |

No other sections were touched. No new documents were created (`reconciliation.handoff.md`
is the only new file, per contract).

## 4. Defects/findings folded — routing table

| # | Verification finding | Type | Where folded |
|---|----------------------|------|----------------|
| 1 | R1 literal outcome never observed; root cause **updated by operator** to OAuth-token-not-API-key (supersedes the "account rate limit" theory in the verification handoff). | `missing_evidence` → now precisely diagnosed, not a vague "unverifiable" | §9 slice-status; AC-C6/AC-G3 Verification method; §10 open item + Resolved-items entry (3). Routed to: **no code fix possible in this repo** (external credential-type constraint) — this is the correct terminal state per the classification table's "requirement cannot be verified in this environment" path: evidence criteria tightened (credential-type precondition made explicit) so a future re-run with a correct API key is directly evaluable. |
| 2 | Account-level Anthropic rate limit (from verification's original theory). | `new_constraint` (as originally classified) | **Superseded, not folded as a permanent constraint** — the operator's confirmed root cause (OAuth token) fully explains the observed `429`s without invoking a separate rate-limit theory, so no `§2 Constraints` row was added for "rate-limited account." This avoids recording an unverified/incorrect constraint in the durable spec. |
| 3 | `litellm/config.yaml` model-id change crossed an explicit "out of scope" fence, but was necessary (stale id, genuine 404). | `contradictory_requirement` | §5 (illustrative config updated + floating-fact note), §10 Resolved items entry (2), §10 open-item model-id bullet. Retroactively blessed as instructed — the "don't touch this" boundary is no longer treated as literal/immutable. |
| 4 | `--detailed_debug` left in `docker-compose.yml` — scope creep / debugging artifact. | `unspecified_behaviour` (scope creep) | **Reverted in code** (§2 above), not folded into the spec — no spec change was needed once the flag is gone. |
| 5 | `OPENAI_API_KEY`/`NAM_EXTRACTION__LLM_MODEL` added to `mcp` to work around `create_llm_extractor()` ignoring `NAM_LLM__API_KEY`/`NAM_LLM__MODEL`; necessary but wrong-slice. | `new_constraint` (necessary fix, wrong slice) | Kept in code (reverting re-blocks the slice); split into new slice `extractor-wiring-fix`, recorded in §10 open items and Resolved-items entry (4). |
| 6 | `openai` pip extra added to `docker/mcp.Dockerfile`, directly coupled to #5. | `new_constraint` (coupled to #5) | Travels with #5 into `extractor-wiring-fix`; same §10 entries. |
| 7 | Only one of two "pre-existing bug fixes" claimed by implementation was actually a code change (informational, not a defect). | informational | No spec/code action needed; noted here so the split-out slice (#5/#6) isn't double-counted as two separate fixes. |

**Loop-closure check:** every classified failure above has moved either the code
(`--detailed_debug` reverted) or the spec (findings #1, #2[superseded], #3, #5, #6
folded into §3.1/§5/§9/§10 as listed) — none was merely noted without a landing.
Finding #1 (R1 itself) is the slice's residual FAIL and is explicitly *not* marked
resolved; it is routed forward as future work (§10 open item + next slice below),
which is the correct terminal state for a requirement that cannot be verified with
the credential currently available.

## 5. Next slice recommendations (priority order)

1. **`extractor-wiring-fix`** (now actionable, no external blocker) — verify/patch
   the `create_llm_extractor()` gap in `neo4j-agent-memory==0.2.0` properly (decide:
   patch the vendored package vs. keep the compose-level `OPENAI_API_KEY` mirror),
   and re-verify whether the prior `llm-smoke` slice's mock-path PASS for
   AC-C6/AC-G3/AC-G2 genuinely exercised the extractor's LLM call path or was
   silently short-circuited by the same wiring gap (`weak_verification` risk flagged
   in §10 Resolved items).
2. **`prod-anthropic-verify` (R1 re-run)** — remains blocked pending a real
   Anthropic **API key** (`sk-ant-api…`) supplied only to `llm-proxy`; not
   actionable until such a key is available. Routing, isolation, and egress
   scoping are already proven (R2/R3/R4) and do not need to be re-verified when
   this re-run happens — only R1's positive-completion outcome needs re-checking.
