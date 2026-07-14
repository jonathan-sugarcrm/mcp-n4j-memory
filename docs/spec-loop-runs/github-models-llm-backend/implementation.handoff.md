# Implementation handoff — `github-models-llm-backend`

## 1. Implementation plan

1. `litellm/config.yaml`: retarget `claude` model_name's `litellm_params` to a
   GitHub-Models-backed entry (empirically resolve the exact `model`/`api_base`
   string), rename the existing Anthropic entry to `claude-anthropic`, keep
   `claude-mock` untouched -> verify: `curl` through the running proxy with
   `model: claude` returns HTTP 200 with a non-mock body and logs show a
   `models.github.ai` upstream call.
2. `docker-compose.yml`: add `GITHUB_API_KEY: ${GITHUB_API_KEY:-change-me}` to
   the `llm-proxy` service environment only (no change to `mcp`/`neo4j`) ->
   verify: `docker compose exec mcp env | grep -i github` is empty; the proxy
   authenticates successfully to GitHub Models.
3. `.env.example`: document `GITHUB_API_KEY` under a new "GitHub Models
   credential: llm-proxy ONLY" section, mirroring the existing Anthropic
   pattern -> verify: visual diff shows only an additive block, no existing
   line changed.
4. Runtime verification (R1-R4): bring the full stack up with
   `GITHUB_API_KEY` exported to the shell (never written to a tracked file),
   run the mechanical checks in specification.handoff.md §4, tear down
   cleanly -> verify: evidence bundle below.

## 2. Changed files

| Path | Reason |
|------|--------|
| `litellm/config.yaml` | R1: retargeted `claude` model_name's `litellm_params` from `anthropic/claude-sonnet-4-5` to `openai/gpt-4o-mini` with `api_base: https://models.github.ai/inference` and `api_key: os.environ/GITHUB_API_KEY`, so `mcp`'s existing `NAM_LLM__MODEL=claude` default now serves a real GitHub-Models completion with zero `mcp`-side changes. Renamed the previous Anthropic entry to `claude-anthropic` (kept, unused, for the still-deferred real-Anthropic path) per Recorded fact (b)-option-(i). `claude-mock` untouched. |
| `docker-compose.yml` | R1/R3: added `GITHUB_API_KEY: ${GITHUB_API_KEY:-change-me}` to the `llm-proxy` service's `environment` block only — `mcp` and `neo4j` service definitions are untouched, preserving the proxy-only credential boundary. |
| `.env.example` | R1 scope item "Adding a `GITHUB_API_KEY` env var... in `docker-compose.yml` and `.env.example`": added a `GITHUB_API_KEY=change-me` line under a new "GitHub Models credential: llm-proxy ONLY" comment block, mirroring the existing `ANTHROPIC_API_KEY` pattern, per Recorded fact (e). No literal secret value committed. |

No other files were touched. `scripts/llm_smoke.py` was reused unmodified per
the spec's explicit scope (it does not assert which backend served the call —
that evidence comes from `llm-proxy` logs, exactly as documented in the
script's own docstring).

**Verification-only scratch artifacts (not part of the change set, not
committed):** a temporary `compose.verify-override.yml` (added `18080:8080`
host port for `mcp` to avoid a pre-existing host port-8080 conflict from an
unrelated container in this shared sandbox, and `LITELLM_LOG: DEBUG` on
`llm-proxy` — the default `INFO` log level does not print the outbound
upstream host, so DEBUG was needed to produce the `models.github.ai` log
evidence R1/R2 require). This file was deleted before finishing; it never
altered `docker-compose.yml` itself. An ephemeral `python:3.12-slim` container
(`llm-smoke-runner`, attached to the compose `db-net`/`llm-net` networks) was
used to run `scripts/llm_smoke.py`, because the host's published `mcp` port
was not actually reachable in this sandbox (same pre-existing networking
quirk recorded in `docs/spec-loop-runs/prod-anthropic-verify/implementation.handoff.md`
line 32) — this container was removed after use.

## 3. Decision log

- Chose **candidate (c)** — `model: openai/gpt-4o-mini` with an explicit
  `api_base: https://models.github.ai/inference` — over candidates (a)
  `github/openai/gpt-4o-mini` and (b) `github/gpt-4o-mini`, because empirical
  testing showed: (a) fails with `400 Unknown model: openai/gpt-4o-mini`
  (LiteLLM's `github/` provider does not accept a publisher-prefixed id); (b)
  returns a real `200` but LiteLLM's `github/` provider silently routes it to
  `https://models.inference.ai.azure.com` (confirmed via `LITELLM_LOG=DEBUG`
  logs), not `models.github.ai` — which would satisfy R1's happy-path
  completion but **not** its literal verification method ("`docker compose
  logs llm-proxy` ... must show an outbound call to a `models.github.ai`
  host"); only (c) produces a `200` **and** logs an outbound call to
  `https://models.github.ai/inference/` verbatim. Reversible — swapping
  `litellm_params` again requires no `mcp`-side or contract change.
- Chose **option (i)** from Recorded fact (b) — retarget the existing
  `claude` model_name in place, rename the current Anthropic entry to
  `claude-anthropic` — over option (ii) (new `github-gpt4o` name + `mcp` env
  default change), per the spec's explicit recommendation: zero `mcp`-side env
  changes needed, `NAM_LLM__MODEL`/`NAM_EXTRACTION__LLM_MODEL` defaults
  (`docker-compose.yml`) were left untouched. Reversible — `mcp` only ever
  references the LiteLLM `model_name` string, never the upstream provider.
- Chose to supply `GITHUB_API_KEY` to the shell environment only
  (`export GITHUB_API_KEY="$GH_TOKEN"` immediately before each `docker compose
  up`), never persisting it to `.env`, `docker-compose.yml`, or any tracked
  file, per the mandatory credential-safety instruction and Recorded fact (d).
  No-contract-impact, reversible.
- Chose an ephemeral, untracked `compose.verify-override.yml` (deleted before
  finishing) to (a) remap `mcp`'s host port to `18080:8080` around a
  pre-existing, unrelated port-8080 conflict in this shared sandbox, and (b)
  temporarily set `LITELLM_LOG=DEBUG` on `llm-proxy` to make the upstream host
  visible in `docker compose logs`, over editing the committed
  `docker-compose.yml`. Both are verification-execution details with zero
  effect on the shipped config; reversible; no contract impact. This mirrors
  the "safe, reversible, verification-only" pattern already used in
  `docs/spec-loop-runs/prod-anthropic-verify/implementation.handoff.md` (its
  own ephemeral-runner-container choice, same rationale class).
- Chose to reuse `scripts/llm_smoke.py` from an ephemeral container attached
  to the compose network by container name, instead of the host's published
  port, because (as in `prod-anthropic-verify`) the host port mapping was not
  reachable from this sandbox's shell. No code or config change resulted;
  purely a verification-execution detail.

## 4. Evidence bundle

| Requirement | Evidence | Result |
|-------------|----------|--------|
| **R1** — happy path: `llm-proxy` exposes a working GitHub-Models-backed `claude` model | `curl -H "Authorization: Bearer ****" http://localhost:4000/v1/chat/completions -d '{"model":"claude","messages":[{"role":"user","content":"marker r1verify1784035821 - reply with the single word PONG"}]}'` → `HTTP_STATUS:200`, body: `{"id":"chatcmpl-E1XVYFkppQiLWRkmlj8aUUqi5DkPj",...,"choices":[{"message":{"content":"PONG",...}}],"usage":{"completion_tokens":3,"prompt_tokens":23,"total_tokens":26,...}}` — real `id`/`usage`, not the mock string (`grep -c "mock-ok: llm-smoke local response" r1-response.txt` → `0`). Correlated `docker compose logs llm-proxy` (DEBUG level, verification-only) for the same marker: `litellm.acompletion(... api_base='https://models.github.ai/inference' ... model='openai/gpt-4o-mini', messages=[{'role':'user','content':'marker r1verify1784035821 ...'}] ...)` immediately followed by `POST Request Sent from LiteLLM: curl -X POST https://models.github.ai/inference/ \` | **PASS** |
| **R1** — failure path: wrong model string/`api_base` for the `github/` provider | Candidate (a) `model: github/openai/gpt-4o-mini` → `HTTP_STATUS:400`, body: `{"error":{"message":"litellm.BadRequestError: GithubException - Unknown model: openai/gpt-4o-mini. Received Model Group=claude\nAvailable Model Group Fallbacks=None","code":"400"}}`. Candidate (b) `model: github/gpt-4o-mini` returned `200` but its DEBUG log showed the request went to `https://models.inference.ai.azure.com` (not `models.github.ai`), which would not satisfy R1's literal log-evidence check — recorded as the reason (b) was rejected in favor of (c). | **PASS** (failure mode reproduced and distinguished from the working config) |
| **R2** — happy path: `memory_store_message` extraction served by a genuine GitHub-Models completion | `python3 scripts/llm_smoke.py --mcp-url http://mcp-n4j-memory-mcp-1:8080/mcp --neo4j-uri bolt://mcp-n4j-memory-neo4j-1:7687 --neo4j-user neo4j --neo4j-password change-me` (run from an ephemeral container on the compose network) → final line `LLM_SMOKE_OK`; marker `llm-smoke-1ada46889802`. Correlated `docker compose logs llm-proxy` for the same marker/window: the extraction request body (`"content": "... POLE+O data model ... ## Text to Analyze\nMarker llm-smoke-1ada46889802: the falcon soared gracefully above the canyon at dawn. ..."`) sent via `litellm.acompletion(..., api_base='https://models.github.ai/inference', model='openai/gpt-4o-mini', ...)` followed by `POST Request Sent from LiteLLM: curl -X POST https://models.github.ai/inference/ \`. Direct bolt read (via the same ephemeral container) of nodes linked to the stored `Message` node: `MATCH (m:Message) WHERE m.content CONTAINS 'llm-smoke-1ada46889802' MATCH (m)-[rel]-(x) RETURN type(rel), labels(x), coalesce(x.name,x.content)` → `MENTIONS ['Entity','Event','Time'] -> dawn`, `MENTIONS ['Entity','Location'] -> canyon`, `MENTIONS ['Entity','Object'] -> falcon` — structured entities distinct from the verbatim stored sentence and from the mock string. | **PASS** |
| **R2** — failure-mode independence check (upstream call verified independently of tool-level success) | Per the requirement's own failure-behaviour note, the tool call succeeding alone would be `weak_verification`; the `llm-proxy` DEBUG log (above) independently shows the actual upstream POST to `models.github.ai/inference` for the exact extraction prompt containing marker `llm-smoke-1ada46889802`, correlating tool-level success with a real upstream call rather than trusting the tool return value alone. | **PASS** |
| **R3** — isolation: `mcp` holds no GitHub token and cannot reach GitHub Models | `docker compose exec mcp env \| grep -i github` → empty (exit code 1, no match). `docker compose exec mcp env \| grep -i gh_token` → empty (exit code 1). Reachability probe (host had no `curl`; used Python, already present in the `mcp` image, for an equivalent TCP-connect check): `docker compose exec mcp python3 -c "import socket; socket.create_connection(('models.github.ai',443),5)"` → `UNREACHABLE: [Errno -3] Temporary failure in name resolution` (DNS-level failure, consistent with `mcp` being attached only to the `internal: true` `db-net`/`llm-net` networks). `neo4j` env: `docker compose exec neo4j env \| grep -i github` → empty (exit code 1). This was run immediately after R1/R2's real calls succeeded, i.e. concurrently with a working GitHub-Models path. | **PASS** |
| **R4** — `llm-proxy`-only egress to GitHub Models, no new network | `docker compose exec llm-proxy python3 -c "import socket; socket.create_connection(('models.github.ai',443),5); print('REACHABLE')"` → `REACHABLE` (llm-proxy has no `curl`; its own Python interpreter, already present in the litellm image, was used for an equivalent TCP-connect check). `docker compose exec neo4j sh -c "wget -T 5 -q -O /dev/null https://models.github.ai && echo REACHABLE \|\| echo UNREACHABLE"` (neo4j has no `curl`/`python3`; used `wget`, already present in the neo4j image) → `UNREACHABLE`. `docker compose config` networks section diffed against the pre-slice `docker-compose.yml` (`git show HEAD:docker-compose.yml`) → `diff` exit code `0` (no output, no differences) — confirms no new network was added; `llm-egress-net` reused unchanged. | **PASS** |

## 5. Blocking spec defects

None that blocked implementation. One **discrepancy worth flagging for
reconciliation** (not blocking, since it was resolved by the spec's own
Recorded fact (a) empirical-resolution mechanism, but the *actual* technical
behaviour differs from what an incautious reading of "the `github/` provider"
might assume): LiteLLM's documented `github/<model>` provider prefix
(candidates (a)/(b)) does **not** send requests to `models.github.ai` at
all — it silently proxies to `https://models.inference.ai.azure.com` (Azure
AI Inference, GitHub Models' underlying backend), which still returns a
genuine non-mock completion but would fail R1's literal verification method
("`docker compose logs llm-proxy` ... must show an outbound call to a
`models.github.ai` host"). This slice resolved it via candidate (c) — an
explicit `api_base` override — which does hit `models.github.ai/inference`
verbatim and is what's shipped in `litellm/config.yaml`. Recorded here as a
**new technical constraint discovered** (LiteLLM's `github/` provider prefix
routes to `models.inference.ai.azure.com`, not `models.github.ai`) for
reconciliation to fold into `docs/SPECIFICATION.md` per the
Verification-failure classification table (`defect_type: new_constraint`).

## 6. Credential handling note

The verification `GITHUB_API_KEY` was supplied only via
`export GITHUB_API_KEY="$GH_TOKEN"` in the shell immediately before each
`docker compose up`/`run` invocation, and only ever appears in
`docker-compose.yml` as the interpolation reference `${GITHUB_API_KEY:-change-me}`
on the `llm-proxy` service. It was never printed, echoed, logged, or written
to any tracked file; all evidence files in this handoff were checked
(`grep -i "gh_token\|ghp_\|github_pat_"`) and contain no token material. Per
Recorded fact (d), this token is a broad `gh`-CLI OAuth token acceptable only
for this one-off local verification pass — anything persistent should use a
fine-grained PAT scoped to `models: read` instead.
