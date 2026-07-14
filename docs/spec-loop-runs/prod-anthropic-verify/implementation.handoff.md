# Implementation handoff — `prod-anthropic-verify`

## 1. Implementation plan

1. `[step] Add llm-egress-net (non-internal), attach to llm-proxy only -> verify: docker compose config shows llm-proxy on {llm-net, llm-egress-net}; mcp/neo4j unchanged` (R4)
2. `[step] Set NAM_LLM__MODEL=claude for mcp at run time (override .env.example's claude-mock default) -> verify: docker compose exec mcp env shows NAM_LLM__MODEL=claude` (R1 precondition)
3. `[step] Source real ANTHROPIC_API_KEY into shell env only, bring stack up clean (`down -v && up -d --build`) -> verify: docker compose exec llm-proxy env has ANTHROPIC_API_KEY; docker compose exec mcp env has none` (R1/R3 precondition)
4. `[step] Run scripts/llm_smoke.py unmodified against the running stack -> verify: stdout ends LLM_SMOKE_OK, exit 0` (R1)
5. `[step] Inspect docker compose logs llm-proxy/mcp for the run window -> verify: non-mock Anthropic-shaped response, absence of mock string, real request_id` (R2)
6. `[step] Probe mcp env + reachability while a real call is in flight -> verify: no ANTHROPIC_API_KEY, DNS/connect failure to api.anthropic.com` (R3)
7. `[step] Probe llm-proxy/neo4j/mcp reachability + rerun AC-C5 probes -> verify: llm-proxy reaches Anthropic, neo4j/mcp don't, neo4j<->llm-proxy still mutually unreachable` (R4)
8. `[step] Tear down (docker compose down -v), remove scratch files -> verify: git status clean except intended source changes` (hygiene)

Two additional bounded fix-steps were required (see §2, §3) because the LLM
extraction call could not reach Anthropic *at all* without them — they are
tightly coupled prerequisites for R1/R2 to be exercisable, not scope creep.

## 2. Changed files

| Path | Reason |
|------|--------|
| `docker-compose.yml` | (a) Added `llm-egress-net` (non-internal) network attached **only** to `llm-proxy`; `db-net`/`llm-net` untouched (`internal: true`); `mcp`/`neo4j` network attachments byte-for-byte unchanged — implements D1/Option A (R4). (b) Added `--detailed_debug` to `llm-proxy`'s command for finer-grained upstream request/response logging needed as R2 evidence (Class 3, see decision log). (c) Added `OPENAI_API_KEY: ${NAM_LLM__API_KEY:-change-me}` and `NAM_EXTRACTION__LLM_MODEL: ${NAM_LLM__MODEL:-claude}` to `mcp`'s environment — required for R1/R2 to be exercisable at all; see decision log for why. |
| `docker/mcp.Dockerfile` | Added the `openai` pip extra to the `neo4j-agent-memory` install (`[mcp,sentence-transformers,openai]`). Without it, `LLMEntityExtractor` fails at import time with "OpenAI package not installed" and the extraction stage never attempts any network call — R1/R2 cannot be exercised without this. |
| `litellm/config.yaml` | Changed both `claude` and `claude-mock` model entries' underlying Anthropic model id from `anthropic/claude-3-5-sonnet-latest` to `anthropic/claude-sonnet-4-5`. The spec-referenced id is no longer live on Anthropic's API (confirmed via genuine `404 not_found_error` from Anthropic itself); this is a Class 2 fact discovered during execution, not an invented requirement — see "Blocking spec defects". |
| `docs/spec-loop-runs/prod-anthropic-verify/implementation.handoff.md` | This artifact. |

`docs/SPECIFICATION.md` was deliberately **not** touched — that is Reconciliation's job per the task boundary.

## 3. Decision log (Class 3 choices)

- Chose reusing `scripts/llm_smoke.py` unmodified (invoked with different `--mcp-url`/`--neo4j-uri` flags) over writing a new script, because the spec explicitly asks for reuse and the script already implements the exact store→bolt-read→search sequence needed; reversible, no contract impact.
- Chose running `scripts/llm_smoke.py` from an ephemeral `python:3.12-slim` container attached to the compose network (`mcp-n4j-memory_db-net`), addressing services by container name, instead of from the host, because the host's port 8080 mapping to `mcp` was not actually reachable in this sandbox (returned a `426 Upgrade Required` unrelated to FastMCP — a pre-existing sandbox networking quirk, not a code defect). Reversible; no code or config change resulted from this, it is purely a verification-execution detail.
- Chose to pin `fastmcp==2.14.7`/`neo4j==6.2.0` into a host-mounted `./pip-scratch` directory (via `pip install --target`, deleted after use) for the ephemeral verification container, because `db-net`/`llm-net` are `internal: true` and the container has no internet access to `pip install` directly; reversible, scratch-only, never committed.
- Chose to add `--detailed_debug` to `llm-proxy`'s command for this verification pass, to get request/response-level log lines distinguishing a genuine Anthropic call from the mock short-circuit, over relying on default INFO-level logs; reversible (single CLI flag), no behavioural/contract impact.
- Chose to add `OPENAI_API_KEY`/`NAM_EXTRACTION__LLM_MODEL` to `mcp`'s environment (both derived from existing `NAM_LLM__*` values already present in `docker-compose.yml`, never introducing a new secret) after discovering, by reading the vendored `neo4j-agent-memory==0.2.0` source inside the running container, that the framework's `create_llm_extractor()` never wires `NAM_LLM__API_KEY`/`NAM_LLM__MODEL` into the actual extractor — it silently falls back to raw `OPENAI_API_KEY` env var and a hardcoded `gpt-4o-mini` default. Without these two additions, the LLM extraction stage fails before ever attempting a network call, so R1/R2 could not be exercised at all. Chose to patch via compose environment (reusing the existing LiteLLM virtual key/model, no new secret) over patching the third-party package, because it's the smaller, reversible, non-invasive fix consistent with "minimum change that satisfies the criteria."
- Chose to update `litellm/config.yaml`'s Anthropic model id from `claude-3-5-sonnet-latest` to `claude-sonnet-4-5` (verified present in litellm's own bundled `litellm.model_cost` table inside the running `llm-proxy` container) after a genuine Anthropic `404 not_found_error` proved the old id no longer resolves. This was the minimal change needed to keep testing the *routing/isolation* contract (which is what R1/R2 actually verify) rather than being blocked by an unrelated, external model-lifecycle event; flagged as a blocking spec defect below since the spec's Grounding section referenced the now-stale id as fact.

## 4. Evidence bundle

### R4 — egress change grants llm-proxy-only Anthropic access

**Evidence (raw, `docker compose config` resolved topology):**
```
llm-proxy -> ['llm-egress-net', 'llm-net']
mcp -> ['db-net', 'llm-net']
neo4j -> ['db-net']

db-net -> internal: True
llm-egress-net -> internal: False
llm-net -> internal: True
```
**Evidence (reachability probes, live stack):**
```
=== R4: llm-proxy CAN reach api.anthropic.com:443 ===
CONNECT_OK

=== R4: neo4j cannot reach api.anthropic.com ===
wget exit=4 (nonzero=expected UNREACHABLE)

=== R3: mcp cannot resolve/reach api.anthropic.com ===
DNS FAILED (expected): [Errno -3] Temporary failure in name resolution
```
(AC-C5 `neo4j`↔`llm-proxy` mutual-unreachability probes were re-run and remained
unchanged — both still fail, consistent with prior `llm-smoke` slice results.)

**Result: PASS.** `mcp`/`neo4j` network membership is byte-for-byte unchanged from
before this slice; only `llm-proxy` gained egress, exclusively via the new
non-internal `llm-egress-net`.

### R3 — Isolation preserved: `mcp` has no key, no egress

**Evidence (raw, captured while real Anthropic traffic from `llm-proxy` was active):**
```
=== R3: mcp has no Anthropic key ===
exit=1 (1=empty=PASS)

=== R3: mcp cannot resolve/reach api.anthropic.com ===
DNS FAILED (expected): [Errno -3] Temporary failure in name resolution
```
**Result: PASS.** No `ANTHROPIC_API_KEY` in `mcp`'s environment at any point across
every rebuild/recreate cycle in this run; DNS resolution to `api.anthropic.com` fails
from inside `mcp`.

### R1 — Real Anthropic-backed completion serves extraction / R2 — non-mock evidence

**Evidence — genuine (non-mock) upstream Anthropic traffic, redacted of the key:**

1. Before the `litellm/config.yaml` model-id fix, a request against the stale model
   id returned a genuine Anthropic error (real `request_id`, not litellm/local):
   ```
   404 not_found_error: {"type":"error","error":{"type":"not_found_error",
   "message":"model: claude-3-5-sonnet-latest"},"request_id":"req_011Cd1mWzmzYFZ1gVfTnPYUC"}
   ```
2. After the fix (model id `claude-sonnet-4-5`), repeated calls (triggered only via
   `scripts/llm_smoke.py` → `memory_store_message`, never via direct manual probing
   after the first cooldown) returned genuine Anthropic rate-limit responses, each
   with a distinct real `request_id`, e.g.:
   ```
   Stage 'LLMEntityExtractor' failed: Failed to extract entities: Error code: 429 -
   {'error': {'message': 'litellm.RateLimitError: AnthropicException -
   {"type":"error","error":{"type":"rate_limit_error","message":"Error"},
   "request_id":"req_011Cd1n1MVU6tL7jthfzinr2"}. Received Model Group=claude
   Available Model Group Fallbacks=None', 'type': 'throttling_error', ...}}
   ```
3. Consolidated final-state counts across the whole run:
   ```
   === mock string never appears ===
   0
   === distinct genuine Anthropic request_ids observed ===
   28
   ```
4. `LLM_SMOKE_OK` was reached on every `scripts/llm_smoke.py` run (storage/search
   path functional throughout); the stored Neo4j node content in every run was the
   real input text (e.g. `"Marker llm-smoke-06a9b329525f: the falcon soared
   gracefully above the canyon at dawn."`), never the mock string.

**Result: PARTIAL / INCONCLUSIVE on the happy-path clause of R1.** Both the `404`
(before the model fix) and the repeated `429`s (after the model fix, with a valid
model id) are genuine, non-mock Anthropic API responses — with real `request_id`
values that only Anthropic's servers issue — proving conclusively that: auth to
Anthropic succeeds with the real key, `llm-proxy` is the only path with that
credential, routing/model-name resolution is correct, and the mock short-circuit is
never hit (R2's core "not the mock" assertion is fully satisfied: PASS). However,
R1's literal expected outcome — "the `memory_store_message` tool call completes
successfully (no error)" for the extraction stage itself — was **not** achieved in
this run: every attempt (7 triggered calls across ~28 real Anthropic requests
including litellm's internal retries) was rejected by Anthropic with a genuine
`429 rate_limit_error`, including after two cooldowns (60s, then 90s). This reads as
an account/key-tier rate limit external to this repo's configuration, not a defect
in the implementation (isolation, routing, and auth are all independently proven
correct by the 404/429 evidence). `memory_store_message` itself never errors to the
caller in either case, by design of the framework's per-stage failure isolation
(a pre-existing, separately-flagged behaviour — see Blocking spec defects).

## 5. Blocking spec defects

1. **Stale Anthropic model id in the spec's Grounding facts.** The spec's Grounding
   section (and `litellm/config.yaml` at read time) recorded
   `anthropic/claude-3-5-sonnet-latest` as the production model id. This id is no
   longer valid on Anthropic's live API (confirmed via a genuine `404
   not_found_error` from Anthropic). This is an external fact-lifecycle issue, not an
   error in the spec's reasoning, but it means R1's verification command
   (`grep -i "claude-3-5-sonnet"` in the logs) as literally written would never match
   post-fix — evidence in this handoff instead greps for `claude-sonnet-4-5`/`anthropic`
   generically. Flag for Reconciliation to decide whether `docs/SPECIFICATION.md`
   should record the model id as a floating/re-verify-per-run fact rather than a
   fixed literal.
2. **R1's "completes successfully (no error)" outcome was not achieved** due to
   persistent real Anthropic account-level rate limiting (genuine `429` on every
   attempt, across two cooldowns). All *other* observable facts required to
   distinguish "genuinely reached and authenticated against Anthropic" from "mock or
   unreachable" are present and unambiguous (real `request_id`s, non-mock content,
   correct isolation). This is reported as evidence, not resolved as pass/fail — that
   judgment belongs to gate 5 (Verification stage), per the isolation contract
   (implementer does not decide pass/fail).
3. **Weak-verification risk carried over from the prior `llm-smoke` slice (per
   `AGENTS.md`)**: reading the vendored `neo4j-agent-memory==0.2.0` source revealed
   that `create_llm_extractor()` never wires `NAM_LLM__API_KEY`/`NAM_LLM__MODEL` into
   the actual OpenAI-compatible client — meaning the LLM extraction call would have
   silently failed (falling back to a missing `OPENAI_API_KEY` / wrong default model)
   in the prior slice's mock-path verification too, without necessarily being
   detected, since `memory_store_message` does not surface per-stage extraction
   failures as tool errors. This is flagged for Reconciliation's awareness; it was
   fixed here (see Changed files) only because it blocked the current slice's ability
   to run at all, not as new scope for this slice's stated outcome.

No other ambiguity or contradiction was found in the specification handoff; all
in-scope items were implementable as written.
