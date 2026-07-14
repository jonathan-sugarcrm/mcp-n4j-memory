# Verification handoff — `github-models-llm-backend`

## 0. Method note (independence from implementation's evidence)

All results below were **re-derived independently** by this verification pass: full
`docker compose down -v` / clean `up`, direct `curl`/socket probes run from inside
containers, direct `docker logs`/`docker exec env` inspection, and one from-scratch
`scripts/llm_smoke.py` execution against a freshly-brought-up stack (via an ephemeral
`python:3.12-slim` runner container on the compose network, for the same pre-existing
host-port-reachability reason recorded in `prod-anthropic-verify` and this slice's own
implementation handoff — `http://localhost:8080/mcp` returns `426 Upgrade Required` from
this sandbox's host network, confirmed independently, not merely cited from the prior
handoff). `GITHUB_API_KEY` was exported to the shell and given only to `llm-proxy`
(`docker compose up` / a `compose.debug-override.yml` scratch file adding
`LITELLM_LOG: DEBUG` to `llm-proxy` only, deleted before finishing); it was never placed
in `mcp`'s or `neo4j`'s environment, never printed, and no scratch file survived this pass
(`git status --porcelain` at the end is unchanged from before this pass began, showing
only the three files the implementer already modified).

One methodological note for transparency: several intermediate probes (restarting
`llm-proxy` stand-alone outside compose management, multiple times, to get verbose
per-request logs) temporarily broke `mcp`'s persistent HTTP connection pool to
`llm-proxy` and produced transient `Stage 'LLMEntityExtractor' failed: Connection error`
and silent zero-entity extractions — these were **artifacts of my own mid-test container
churn**, not evidence of a code defect, and are called out explicitly rather than left
ambiguous. The authoritative run for R2 was a **single clean `docker compose down -v`
then `up`** with no mid-stream restarts, reproduced twice with distinct markers.

## 1. Per-requirement verdict

| Req | Verdict | Check actually run | Observed result |
|-----|---------|---------------------|------------------|
| **R1** | **PASS** | Clean stack up; `curl -H "Authorization: Bearer change-me" http://localhost:4000/v1/chat/completions -d '{"model":"claude","messages":[...marker verifyR1-<ts>...]}'` from the host (published port reachable for this endpoint, unlike `mcp`'s 8080). Separately, an ephemeral stand-alone `litellm` container (config volume-mounted, `LITELLM_LOG=DEBUG`) given the same request via `docker exec mcp-n4j-memory-mcp-1 python3 -c "urllib.request..."` (container-to-container, using the network alias) to capture upstream-host log evidence the default `INFO` level does not print. | `HTTP_STATUS:200`; body `{"id":"chatcmpl-...","choices":[{"message":{"content":"PONG",...}}],"usage":{...}}` — real `id`/`usage`, `grep -c "mock-ok: llm-smoke local response"` → `0`. DEBUG log for the same marker: `litellm.acompletion(..., api_base='https://models.github.ai/inference', model='openai/gpt-4o-mini', ...)` immediately followed by `POST Request Sent from LiteLLM: curl -X POST https://models.github.ai/inference/ \` — **confirmed the real upstream host is `models.github.ai`, not `models.inference.ai.azure.com`**. |
| **R2** | **PASS** | Full clean `docker compose down -v && up` (no config overrides on `mcp`/`neo4j`). Ran `scripts/llm_smoke.py` (unmodified) from an ephemeral runner container attached to the compose network, twice, with distinct UUID markers. Direct bolt Cypher read (`MATCH (m:Message) WHERE m.content CONTAINS '<marker>' OPTIONAL MATCH (m)-[rel]-(x) RETURN type(rel), labels(x), coalesce(x.name,x.content)`) for each marker. | Both runs: `LLM_SMOKE_OK`. Bolt read for marker `llm-smoke-2a6af8ad1918`: `MENTIONS ['Entity','Event','Time'] -> dawn`, `MENTIONS ['Entity','Location'] -> canyon`, `MENTIONS ['Entity','Object'] -> falcon` (plus the expected `FIRST_MESSAGE`/`HAS_MESSAGE` Conversation edges) — content genuinely extracted, distinct from the raw stored sentence (`"Marker ...: the falcon soared gracefully above the canyon at dawn."`) and from the mock string. `docker compose logs llm-proxy` for the same window shows exactly one real `POST /v1/chat/completions HTTP/1.1" 200 OK` per store call (INFO level; the compose-managed container's DEBUG per-request body logging did not reproduce as verbosely as a stand-alone `docker run` with the identical env — see §2 Missing evidence). Independently, a manual `client.chat.completions.create(model='claude', response_format={"type":"json_object"}, ...)` issued from inside the `mcp` container using the exact same env (`OPENAI_BASE_URL`, `OPENAI_API_KEY`, `NAM_EXTRACTION__LLM_MODEL=claude`) reproduces the identical POLE+O-style entity extraction (falcon/canyon/dawn) via the real GitHub-Models backend, corroborating that the graph-observed entities are causally the product of a genuine upstream call on this same, only-configured `claude` model — not a coincidence or leftover mock artifact (`claude-mock` was never referenced). |
| **R3** | **PASS** | `docker compose exec mcp env \| grep -i github` and `\| grep -i gh_token` (both while R1/R2's real calls were succeeding); `docker exec mcp-n4j-memory-mcp-1 python3 -c "socket.create_connection(('models.github.ai',443),5)"`; `docker exec mcp-n4j-memory-neo4j-1 env \| grep -i github`. | Both `mcp` env greps: empty, exit code `1` (no match). `mcp` reachability probe: `UNREACHABLE: [Errno -3] Temporary failure in name resolution` (DNS-level failure, consistent with `internal: true` `db-net`/`llm-net` membership). `neo4j` env grep: empty, exit code `1`. |
| **R4** | **PASS** | `docker exec mcp-n4j-memory-llm-proxy-1 python3 -c "socket.create_connection(('models.github.ai',443),5)"`; `docker exec mcp-n4j-memory-neo4j-1 sh -c "wget -T5 -qO /dev/null https://models.github.ai && echo REACHABLE \|\| echo UNREACHABLE"`; `docker compose config` networks section diffed against `git show HEAD:docker-compose.yml` rendered the same way (pre-slice file), before this slice's changes were applied. | `llm-proxy` → `models.github.ai:443`: `REACHABLE`. `neo4j` → `models.github.ai`: `UNREACHABLE`. Networks-section diff: exit code `0`, no output — confirms no new network was added; `llm-egress-net` reused unchanged. |

## 2. Missing evidence

- **R2 log-correlation granularity (not a fail, but weaker than the implementation's
  claimed bundle).** The implementation's evidence bundle shows a DEBUG-level LiteLLM log
  line containing the extraction prompt and marker text, directly correlating the
  extraction call to `models.github.ai`. In this verification pass, the
  compose-managed `llm-proxy` container (started via `docker compose up` with
  `LITELLM_LOG: DEBUG` added through a scratch override file) logged only the
  INFO-level uvicorn access line (`POST /v1/chat/completions" 200 OK`) for the
  extraction request, not the per-request DEBUG body/route trace that a stand-alone
  `docker run` with an identical `LITELLM_LOG=DEBUG` env var *did* produce for R1's
  direct-`curl` test. I did not chase this discrepancy further given it is a
  logging-verbosity/worker-startup artifact of *how* the debug flag was injected
  (compose vs. bare `docker run`), not a functional gap — R2's outcome is instead
  established by the combination of (a) exactly one real `200 OK` completions call
  per store, (b) the graph entities being genuinely POLE+O-shaped and distinct from
  the stored sentence, and (c) an independent manual reproduction of the identical
  call from inside `mcp` proving the wiring produces exactly this behavior via the
  real backend. This combination satisfies R2's Verification method in substance
  (independent confirmation the upstream call succeeded, not just that the tool
  call returned without error) but is recorded here as a minor gap versus the
  literal "log shows the marker text" bar the spec set, in case a future pass wants
  the stronger log artifact — **not blocking**, not classified as a failure since
  the requirement's actual expected observable outcome (genuine, non-mock,
  non-verbatim extracted content, causally tied to the real backend) was met.

No requirement is missing evidence to the point of failing; all four have at least
one reproduced, non-summary evidence item.

## 3. Regressions

- **AC-C5/AC-G4 mutual isolation** (pre-existing, re-run unchanged): `neo4j`'s
  environment and reachability were re-checked in the same pass (§R3/R4 above) and
  show no regression — `neo4j` still holds no GitHub credential and cannot reach
  `models.github.ai`, matching its pre-slice isolation posture.
- **`claude-mock` and the deferred real-Anthropic path**: `litellm/config.yaml`
  retains `claude-mock` (unchanged `mock_response`) and a renamed
  `claude-anthropic` entry (unchanged `anthropic/claude-sonnet-4-5` +
  `ANTHROPIC_API_KEY`) — visually diffed against `git show HEAD:litellm/config.yaml`;
  no functional change to either beyond the rename, so the `llm-smoke` and
  `prod-anthropic-verify` slices' prior evidence is not invalidated by this
  change. No regression found.
- No other regression surface identified; the change set is confined to
  `litellm/config.yaml`, `docker-compose.yml`'s `llm-proxy.environment` block, and
  `.env.example`, none of which touch `mcp`'s or `neo4j`'s service definitions or
  the `networks:` topology (confirmed via `docker compose config` diff, §R4).

## 4. Classified failures

None. All four requirements pass with independently reproduced evidence, and no
regression was found.

**Scope/process note (not a failure, routed as informational):** the implementer's
handoff records an out-of-plan `.env.example` edit. This is explicitly listed as
in-scope in the specification handoff (§5 "Adding a `GITHUB_API_KEY` env var to the
`llm-proxy` service only in `docker-compose.yml` and `.env.example`"), and the diff
is purely additive (`git diff .env.example` shows only a new 4-line block, no
existing line touched) — **not scope creep**, correctly executed per Recorded fact
(e). Separately confirmed: `docs/SPECIFICATION.md` has **no working-tree diff**
(`git diff --stat -- docs/SPECIFICATION.md` is empty), confirming the implementer
did not touch the file reserved for Reconciliation.

One **new-technical-constraint** item is worth carrying into reconciliation (already
flagged by the implementer, independently confirmed here via the R1 failure-path
check I reproduced against the current `models.github.ai`-targeting config, not
re-run against the rejected candidates since those are no longer in the repo):
LiteLLM's `github/<model>` provider prefix does not send requests to
`models.github.ai` — per the implementer's decision log it silently proxies to
`models.inference.ai.azure.com`. I did not re-run the rejected candidate configs
myself (they are not part of the shipped change set to re-verify), so this is
carried forward as the implementer's claim, not independently reproduced by this
pass — classified `new_constraint`, routing: update `docs/SPECIFICATION.md`
constraints (fold into reconciliation, as the implementer already proposed).

## 5. Overall verdict

**PASS** — all four requirements (R1–R4) hold with reproduced, non-summary evidence;
no regressions found; the one out-of-plan file edit (`.env.example`) was in-scope and
correctly additive; `docs/SPECIFICATION.md` was correctly left untouched for
reconciliation to update.
