# Specification handoff — `github-models-llm-backend`

## 1. Slice

**id:** `github-models-llm-backend`
**Outcome:** Retarget (or add) an `llm-proxy` model that routes real completions to
**GitHub Models** (`models.github.ai/inference`, keyed by a GitHub PAT via LiteLLM's
`github/` provider) instead of Anthropic, so a genuine, non-mock, positive completion
serves `memory_store_message` extraction end-to-end through the proxy — closing the
positive-completion gap `prod-anthropic-verify` left deferred for AC-C6/AC-G3 R1
(docs/SPECIFICATION.md:291-297, :433-437, :486-496), without requiring an
`sk-ant-api…` key, while preserving the existing proxy-only/no-mcp-key/egress-scoped
architecture.

## 2. Grounding (facts read from the repo)

- **`litellm/config.yaml:1-11`**: `model_list` has two entries — `claude` (real,
  `anthropic/claude-sonnet-4-5`, `api_key: os.environ/ANTHROPIC_API_KEY`) and
  `claude-mock` (`mock_response`, no key). `general_settings.master_key` is
  `os.environ/LITELLM_MASTER_KEY`. No `github`-provider entry exists yet.
- **`docker-compose.yml:21-33`** (`llm-proxy` service): environment currently sets
  only `LITELLM_MASTER_KEY` and `ANTHROPIC_API_KEY`; networks are `llm-net` (internal)
  and `llm-egress-net` (non-internal, added by `prod-anthropic-verify` specifically so
  `llm-proxy` — and only `llm-proxy` — can reach the public internet for
  `api.anthropic.com`; comment at line 80-81 already documents this network's purpose
  generically as "reach the public internet", not Anthropic-specific).
- **`docker-compose.yml:35-73`** (`mcp` service): `NAM_LLM__PROVIDER=openai`,
  `NAM_LLM__MODEL=${NAM_LLM__MODEL:-claude}` — the framework's model selection is
  indirection through the LiteLLM `model_name` string, not a provider string; `mcp`
  never talks to a provider directly. `OPENAI_API_KEY: ${NAM_LLM__API_KEY:-change-me}`
  (comment lines 47-52) is the LiteLLM **virtual key**, distinct from any upstream
  provider key — confirms `mcp` holds no provider credential today and this slice
  must preserve that. `NAM_EXTRACTION__LLM_MODEL: ${NAM_LLM__MODEL:-claude}` (lines
  54-58) mirrors `NAM_LLM__MODEL` so the extractor stage requests the same LiteLLM
  `model_name`. **Confirms fact:** selecting a different backend is a config-only
  change (litellm/config.yaml + docker-compose.yml env) — `mcp` needs no code change
  if the existing `model_name` `claude` is reused; only `NAM_LLM__MODEL`/
  `NAM_EXTRACTION__LLM_MODEL` need to change if a *new* `model_name` is chosen instead.
- **`docker-compose.yml:75-85`** (`networks`): `db-net`/`llm-net` are `internal: true`;
  `llm-egress-net` is the only non-internal network, attached solely to `llm-proxy`
  (line 33). Reusing this same network for GitHub Models egress needs no topology
  change — `models.github.ai` is just a different external host reached over the same
  `llm-proxy`-only egress path already granted.
- **`docs/SPECIFICATION.md:267-297`** (§9 slice-status): `llm-smoke` runtime-verified
  AC-C6/AC-G3 routing/isolation via the mock backend; `prod-anthropic-verify` runtime-
  verified routing/isolation with a **real** Anthropic credential but could not close
  the positive-completion path because the only available credential
  (`~/.secrets/anthropic.env`) was a claude.ai/Claude Code **OAuth token**, not an
  `sk-ant-api…` API key, and LiteLLM's `anthropic/` provider rejects OAuth bearer
  tokens. **This slice's R1/R2 supply the positive-completion evidence AC-C6/AC-G3
  still needs, via a different, genuinely-keyable provider — GitHub Models —
  rather than waiting on a real Anthropic API key.**
- **`docs/SPECIFICATION.md:352-375`** (AC-C6) and **`:420-437`** (AC-G3): both already
  state the architecture requirement generically — "a framework operation that issues
  an LLM call... reaches the backend LLM only via the proxy" / "no LLM traffic
  originates directly from `mcp`". Neither AC is worded as Anthropic-specific; both
  are satisfied by any backend reached exclusively through `llm-proxy` with no
  provider key in `mcp`. **Confirms fact:** this slice does not need to edit AC-C6/
  AC-G3's wording, only add runtime evidence via a new provider — reconciliation
  (stage 4) will fold the GitHub-Models evidence into the existing §9 slice-status
  narrative alongside the Anthropic one, not replace it.
- **`docs/SPECIFICATION.md:501-509`, `:536-556`** (§10 open items / resolved items):
  the `extractor-wiring-fix` open item records that the vendored
  `neo4j-agent-memory==0.2.0`'s `create_llm_extractor()` ignores `NAM_LLM__API_KEY`/
  `NAM_LLM__MODEL` and instead reads a raw `OPENAI_API_KEY` env var and
  `NAM_EXTRACTION__LLM_MODEL` (already wired in `docker-compose.yml:47-58` as a
  workaround). **This wiring gap is a pre-existing, separately-tracked defect, not
  something this slice introduces or must fix** — this slice's `NAM_EXTRACTION__LLM_MODEL`
  handling must follow the *same existing workaround pattern* already in place (Class
  2: convention already established, not a new decision).
- **`scripts/llm_smoke.py:1-90+`**: existing store→bolt-read→paraphrase-search driver,
  parameterized by CLI flags, calls `memory_store_message` then `memory_search` and
  reads Neo4j directly; does not assert which backend served the call (that evidence
  comes from `llm-proxy` logs, per the `prod-anthropic-verify` pattern) — reusable
  unmodified to trigger the GitHub-Models-backed extraction call.
- **Operator-supplied facts (already verified, cited per task brief, not
  re-verified destructively here):** a live `curl -H "Authorization: Bearer $GH_TOKEN"`
  `POST https://models.github.ai/inference/chat/completions` with model
  `openai/gpt-4o-mini` returned HTTP 200 with a real completion — confirms the token
  has GitHub Models access and the raw endpoint/model-id combination works outside
  LiteLLM. LiteLLM's own docs (https://docs.litellm.ai/docs/providers/github)
  document a `github/<model>` provider prefix reading `GITHUB_API_KEY` from env and
  supporting function/tool calling, but use older catalog-style model names (e.g.
  `github/Llama-3.2-...`) that do not obviously match the publisher-prefixed
  `openai/gpt-4o-mini` id the live endpoint actually accepts. **This mismatch is the
  slice's primary open technical risk** (see Unresolved decisions / Recorded facts).

## 3. Normalized requirements

### R1 — `llm-proxy` exposes a working GitHub-Models-backed model
- **Trigger:** `llm-proxy` starts with an updated `litellm/config.yaml` model entry
  whose `litellm_params.model` uses the `github/` provider prefix and
  `api_key: os.environ/GITHUB_API_KEY`, and the `llm-proxy` service in
  `docker-compose.yml` is given a `GITHUB_API_KEY` value (env-sourced, not a literal).
- **Preconditions:** Stack is brought up clean (`docker compose down -v` then `up`);
  `llm-egress-net` (existing, non-internal, `llm-proxy`-only) is unchanged and
  reused — no new network is required since `models.github.ai` is reached the same
  way `api.anthropic.com` was; a valid GitHub token with Models access is supplied
  only to `llm-proxy`'s environment (see R3, and Unresolved decisions (b) for which
  token).
- **Expected observable outcome:** A direct call to the proxy's own endpoint —
  `curl -H "Authorization: Bearer $LITELLM_MASTER_KEY" http://localhost:4000/v1/chat/completions -d '{"model": "<chosen model_name>", "messages": [...]}'`
  — returns HTTP `200` with a real, non-mock completion body (an `id`, `choices[0].message.content`,
  and `usage` token counts shaped like an OpenAI-compatible response, not the literal
  string `"mock-ok: llm-smoke local response"`).
- **Failure behaviour:** If the LiteLLM `github/` model string or `api_base` is wrong
  for the `models.github.ai/inference` host, the proxy call fails with a non-200
  (e.g. `400`/`404` model-not-found, or `401`/`403` on a bad token) — this is the
  explicit, expected failure mode while the model-string risk (Unresolved (a)) is
  unresolved, and implementation must show which exact string/`api_base`
  combination produces the `200` rather than merely asserting one works.
- **Verification method:** Direct `curl` against `http://llm-proxy:4000/v1/chat/completions`
  (from inside the compose network or via the published `4000` port) with the chosen
  `model_name`; assert HTTP `200`, a real `id`/`usage` field, and the response body
  does **not** contain the mock string. Additionally `docker compose logs llm-proxy`
  for the same request window must show an outbound call to a `models.github.ai`
  host, not a short-circuited mock response.
- **Traces to:** AC-C6, AC-G3 (docs/SPECIFICATION.md:352-375, :420-437).

### R2 — `memory_store_message` extraction is served by a genuine GitHub-Models completion
- **Trigger:** `memory_store_message` is called against the running `mcp` MCP server
  with `NAM_LLM__MODEL` (and mirrored `NAM_EXTRACTION__LLM_MODEL`) set to the
  `model_name` from R1.
- **Preconditions:** R1 holds (the proxy model is confirmed working stand-alone);
  `mcp`'s environment is otherwise unchanged from the existing wiring
  (`docker-compose.yml:39-63`), including the pre-existing `OPENAI_API_KEY`/
  `NAM_EXTRACTION__LLM_MODEL` extractor-wiring workaround (§10 open item,
  docs/SPECIFICATION.md:501-509) — this slice does not fix that wiring gap, only
  routes through it to a different backend, per explicit scope below.
- **Expected observable outcome:** The tool call completes without error; the Neo4j
  node(s) written for a unique marker contain content that is genuinely extracted
  (i.e., not the raw stored sentence verbatim and not any mock string), and
  `llm-proxy` logs for the same request window show the same `models.github.ai`
  upstream call pattern as R1, correlated by timestamp/marker.
- **Failure behaviour:** If the GitHub-Models call fails (bad model string, bad
  token, network egress blocked), the extraction step fails; per the pre-existing
  `memory_store_message` behaviour (docs/SPECIFICATION.md AC-G2 Verification method),
  a failing per-stage extraction may not surface as a tool-level error — so this
  requirement's verification must independently confirm the *upstream call itself*
  succeeded (via `llm-proxy` logs), not merely that the tool call returned without
  error, to avoid the same `weak_verification` trap flagged against `llm-smoke`
  (docs/SPECIFICATION.md:552-556).
- **Verification method:** Run `scripts/llm_smoke.py` (unmodified) against the
  running stack with the GitHub-Models model configured; assert `LLM_SMOKE_OK`;
  separately `docker compose logs llm-proxy | grep -B5 -A5 <marker-or-timestamp>`
  to confirm a genuine `models.github.ai` upstream call (not mock) for that same
  window; direct bolt read of the stored node to confirm its content is not the
  literal stored sentence or the mock string.
- **Traces to:** AC-G2 (docs/SPECIFICATION.md:401-419), AC-C6, AC-G3.

### R3 — Isolation preserved: `mcp` holds no GitHub token and cannot reach GitHub Models
- **Trigger:** The stack is running with R1/R2's GitHub-Models model configured and
  actively serving requests.
- **Preconditions:** Same as R2.
- **Expected observable outcome:** `docker compose exec mcp env | grep -iE 'github|gh_token'`
  returns empty (no `GITHUB_API_KEY`, `GH_TOKEN`, or equivalent in `mcp`'s
  environment); a reachability probe from inside `mcp` to `models.github.ai` (DNS
  resolution and/or TCP connect on 443) fails/times out, even while a real
  GitHub-Models call from `llm-proxy` is succeeding concurrently; `neo4j`'s
  environment and reachability are likewise unaffected (no new credential, still
  isolated per AC-C5/AC-G4).
- **Failure behaviour:** If `mcp` (or `neo4j`) can resolve/reach `models.github.ai`,
  or holds any GitHub token, isolation is violated regardless of whether R1/R2
  otherwise pass — a working positive-completion path must not come at the cost of
  the proxy-only architecture.
- **Verification method:** `docker compose exec mcp env | grep -i github` (and
  `grep -i gh_token`) asserted empty; `docker compose exec mcp sh -c "curl -m 5 -sS
  -o /dev/null -w '%{http_code}' https://models.github.ai || echo UNREACHABLE"`
  asserted `UNREACHABLE`, run while R2's real call is active; rerun the existing
  AC-C5/AC-G4 reachability probes unchanged to confirm no regression.
- **Traces to:** AC-C6, AC-G3, AC-C5, AC-G4 (docs/SPECIFICATION.md:352-375,
  :420-437, network segmentation criteria).

### R4 — `llm-proxy`-only egress to GitHub Models, reusing the existing egress network
- **Trigger:** Reachability probes are run from `llm-proxy` to `models.github.ai:443`
  and from `mcp`/`neo4j` to the same host.
- **Preconditions:** `llm-proxy` remains attached to `llm-net` (internal) and
  `llm-egress-net` (non-internal, unchanged from `prod-anthropic-verify`); no new
  Docker network is introduced for this slice.
- **Expected observable outcome:** From `llm-proxy`, `models.github.ai:443` is
  reachable (TCP connect / TLS handshake succeeds); from `mcp` and `neo4j`, it is
  unreachable (DNS fails or connection times out, per their unchanged `internal`
  network membership).
- **Failure behaviour:** If `llm-proxy` cannot reach `models.github.ai`, R1/R2 fail
  at the network layer regardless of correct LiteLLM config — this is a distinct
  failure mode from a bad model string and must be distinguished in verification
  (e.g. connection-level failure vs. HTTP 4xx from a reachable host).
  If `mcp`/`neo4j` unexpectedly *can* reach it, isolation is violated (folds into R3).
- **Verification method:** `docker compose exec llm-proxy sh -c "curl -m 5 -sS -o
  /dev/null -w '%{http_code}' https://models.github.ai"` asserted to return an HTTP
  status (reachable); the same probe from `mcp` and `neo4j` asserted `UNREACHABLE`/
  timeout. Rerun `docker compose config` and diff the `networks:` section against
  the pre-slice file to confirm no new network was added.
- **Traces to:** AC-C6, AC-C5, AC-G4.

## 4. Verification criteria (mechanical, per requirement)

| Req | Mechanical check |
|-----|-------------------|
| R1  | `curl` to `http://llm-proxy:4000/v1/chat/completions` with the chosen `model_name` returns HTTP `200`, a non-mock body (real `id`/`usage`), and `docker compose logs llm-proxy` shows a `models.github.ai` upstream call for that request. |
| R2  | `scripts/llm_smoke.py` exits `LLM_SMOKE_OK`; `docker compose logs llm-proxy` shows a correlated genuine `models.github.ai` call (not mock) for the same marker/window; direct bolt read shows extracted (non-verbatim, non-mock) content. |
| R3  | `docker compose exec mcp env \| grep -i github` and `grep -i gh_token` both empty; `mcp`→`models.github.ai` probe returns `UNREACHABLE` while a real call is in flight; `neo4j` environment/reachability unchanged. |
| R4  | `llm-proxy`→`models.github.ai:443` probe reachable; `mcp`/`neo4j`→`models.github.ai:443` probes `UNREACHABLE`; `docker compose config` networks section unchanged (no new network added) vs. pre-slice. |

Each check above only passes when the corresponding Expected observable outcome is
actually met (a non-200 or a mock-shaped body fails R1/R2 even if the tool call
"succeeds"; any reachability or credential leak fails R3/R4 even if R1/R2 pass) —
so a green result cannot mask an unmet outcome.

## 5. Explicit scope

**In scope:**
- Adding/retargeting one `litellm/config.yaml` model entry to route to GitHub Models
  via LiteLLM's `github/` provider (or an `openai/`-compatible entry with an
  `api_base` override pointed at `models.github.ai/inference`, if the `github/`
  provider proves not to target the correct host — see Unresolved (a)).
- Adding a `GITHUB_API_KEY` env var to the `llm-proxy` service only in
  `docker-compose.yml` and `.env.example`.
- Reusing the existing `llm-egress-net` for GitHub Models egress (no new network).
- Reusing/updating `NAM_LLM__MODEL`/`NAM_EXTRACTION__LLM_MODEL` on `mcp` to select
  the new backend (a value change only, per the model-name decision in Unresolved
  decisions / Recorded facts).
- Runtime verification via `scripts/llm_smoke.py` (unmodified) plus `curl`/log/env
  probes, exactly as R1-R4 specify.
- Updating `docs/SPECIFICATION.md` §9 slice-status and §10 (reconciliation stage,
  not this stage) to record the GitHub-Models positive-completion evidence.

**Out of scope:**
- Embeddings/vector search (AC-C7/AC-G5) — untouched by this slice.
- Removing or modifying the existing `claude`/`claude-mock` Anthropic entries in
  `litellm/config.yaml` — they are kept as-is; this slice **adds or retargets**
  one entry, it does not delete the Anthropic path.
- The real-`sk-ant-api…`-Anthropic positive-completion path — remains separately
  deferred exactly as recorded in `docs/SPECIFICATION.md:486-496`; this slice does
  not attempt it and does not change that open item's status.
- Fixing the `create_llm_extractor()` / `NAM_LLM__API_KEY` wiring gap
  (`extractor-wiring-fix`, docs/SPECIFICATION.md:501-509) — this slice follows the
  existing `OPENAI_API_KEY`/`NAM_EXTRACTION__LLM_MODEL` workaround pattern unchanged;
  it does not patch the vendored package or resolve that open item.
- Any change to `db-net`/`llm-net` `internal: true` status or to `neo4j`'s network
  membership.
- Rotating, minting, or persisting a new GitHub PAT as part of this stage — that is
  an implementation-stage/operator action, flagged as a security recommendation
  below, not performed here.

## 6. Unresolved decisions (Class 1 — ask before/at implementation)

None that block starting implementation. Both candidate decisions below were
evaluated against the Class 1/2/3 procedure and resolved to Class 3 (safe,
reversible, internal-only) or flagged as a technical risk to resolve empirically at
implementation time (which is itself a Class-3-style "try and record what worked"
task, not a stakeholder product decision) — see Recorded facts & safe choices.
**If** implementation cannot get any `github/`-prefixed or `api_base`-overridden
LiteLLM config to return a genuine `200` from `models.github.ai` after reasonable
troubleshooting (bad model string, wrong base URL, LiteLLM provider bug), that
outcome itself becomes a **new Class-1 escalation** (a genuine either/or: keep
trying alternate LiteLLM configurations vs. fall back to a raw `openai/`-provider
entry with a manual `api_base`, vs. abandon this slice) — but that is a
verification/implementation-time contingency, not a blocking decision today.

## 7. Recorded facts & safe choices

- **(a) Model-name / `api_base` for LiteLLM → GitHub Models (Class 3, empirical,
  resolved by implementation's runtime experimentation, not by this stage).**
  Rationale for not treating this as Class 1: there is a single technically correct
  answer (whatever string/`api_base` combination the live LiteLLM `github/` provider
  actually accepts against `models.github.ai/inference` for tool-calling completions)
  — it is discoverable by trying it, not a product trade-off between legitimate
  alternatives. Recorded candidates for implementation to try, in order, citing the
  operator's task-brief facts: (1) `model: github/openai/gpt-4o-mini` (mirrors the
  proven-working raw endpoint's publisher-prefixed id under the documented `github/`
  prefix); (2) `model: github/gpt-4o-mini` (matches LiteLLM's documented catalog-name
  style, no publisher prefix); (3) an explicit `api_base:
  https://models.github.ai/inference` override on an `openai/gpt-4o-mini` entry if
  neither `github/` variant reaches the right host. Implementation must record in its
  own handoff which one produced the R1 `200`, since this is presently unknown and is
  this slice's primary technical risk (flagged per task brief).
- **(b) Recommend: retarget the existing `claude` model name, do NOT add a new
  `github` name (Class 3, reversible, no contract impact).** Rationale: `mcp`'s
  compose defaults already point `NAM_LLM__MODEL`/`NAM_EXTRACTION__LLM_MODEL` at
  `claude` (`docker-compose.yml:45,58`); retargeting `claude`'s `litellm_params` to
  the GitHub Models backend means **zero `mcp`-side env changes** are needed beyond
  what's already wired, and directly produces the "real backend serves the
  production model name" evidence AC-C6/AC-G3 want, without introducing a second
  parallel model name for operators to track. This is a two-way door — the model's
  `litellm_params` can be pointed at any backend again later with no schema/contract
  change, since `mcp` only ever references the LiteLLM `model_name` string, never
  the upstream provider. Do **not** delete the current `anthropic/claude-sonnet-4-5`
  wiring; instead, either (i) swap `claude`'s `litellm_params` to the GitHub-Models
  entry and rename the current Anthropic entry to something like `claude-anthropic`
  (kept, unused, for when a real `sk-ant-api…` key arrives), or (ii) add a distinct
  `model_name` (e.g. `github-gpt4o`) for GitHub Models and change `mcp`'s
  `NAM_LLM__MODEL`/`NAM_EXTRACTION__LLM_MODEL` defaults to point at it, keeping
  `claude` reserved for real Anthropic. **Recommendation: option (i)** — reuse the
  `claude` name for the now-working backend, since the immediate goal (per this
  slice's stated GOAL) is a *working* production model called from `mcp`'s existing
  default, and the deferred real-Anthropic path already has its own tracked open
  item and does not need the `claude` name preserved for it. Implementation should
  record which of (i)/(ii) it actually chose in its own decision log, since this
  determines whether `docker-compose.yml`'s `NAM_LLM__MODEL`/
  `NAM_EXTRACTION__LLM_MODEL` defaults need to change at all.
- **(c) Egress network: reuse `llm-egress-net` unchanged, do not create a new
  network (Class 2 — investigated, single correct answer).** `docker-compose.yml:80-82`'s
  comment already documents this network generically as giving `llm-proxy` "a route
  to the public internet" (not Anthropic-specific), and `models.github.ai` is just
  another external host reachable the same way. No new network, no topology change,
  no change to `mcp`/`neo4j` network membership.
- **(d) SECURITY recommendation on the `GH_TOKEN` (Class 3 for *this verification
  pass*; flagged explicitly per task brief, not a blocker).** The operator-confirmed
  `GH_TOKEN` is a broad `gh`-CLI OAuth token (scopes beyond Models access). Using it
  to *verify* R1/R2/R4 in this one-off local pass is an acceptable, reversible,
  low-blast-radius choice (it lives only in the local shell env and, per R3, must
  never be placed in `mcp`'s environment or committed to any file). **Recommendation
  for anything persistent** (i.e., if this GitHub-Models route is kept running
  beyond this verification pass, checked into `.env`/deployed configuration, or used
  outside this single verification session): mint and use a **fine-grained PAT
  scoped to only `models: read`** instead, supplied to `llm-proxy` exactly the way
  `ANTHROPIC_API_KEY` is today (env-sourced, never committed, never given to `mcp`).
  This is a safe-choice/security-hygiene recommendation, not a Class-1 product
  decision — no legitimate alternative to "don't use an overscoped token long-term"
  exists — but implementation must not silently commit or persist `GH_TOKEN` anywhere
  in the repo (docs, `.env.example` literal values, logs) regardless of which token
  is used for the live verification run itself.
- **(e) `.env.example` update (Class 3).** Add a `GITHUB_API_KEY=change-me` line
  documented as "llm-proxy ONLY", mirroring the existing `ANTHROPIC_API_KEY` pattern
  at the bottom of `.env.example`, rather than reusing/renaming the Anthropic
  variable — keeps both provider credentials independently swappable and matches
  the existing per-provider-key convention in the file.
