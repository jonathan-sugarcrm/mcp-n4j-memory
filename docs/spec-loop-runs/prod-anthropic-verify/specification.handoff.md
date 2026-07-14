# Specification handoff — `prod-anthropic-verify`

## 1. Slice

**id:** `prod-anthropic-verify`
**Outcome:** Prove, at runtime from a clean state, that production memory-ingestion
traffic (`memory_store_message` → entity-extraction LLM call) is served by the **real**
Anthropic-backed `claude` model through `llm-proxy`, with a real `ANTHROPIC_API_KEY`
supplied **only** to `llm-proxy`, while `mcp` remains free of any Anthropic credential
or direct Anthropic egress — closing the one item AC-C6/AC-G3 left deferred after
`llm-smoke` (docs/SPECIFICATION.md:267, :460, :472-474).

## 2. Grounding (facts read from the repo)

- **AC-C6** (docs/SPECIFICATION.md:333-345): Trigger = a framework LLM call (e.g.
  extraction during `memory_store_message`). Preconditions include `ANTHROPIC_API_KEY`
  exists *only* in the `llm-proxy` environment. Verification method's last sentence:
  *"A separate production-only check with a real `ANTHROPIC_API_KEY` confirms the
  Anthropic-backed positive path."* — this slice **is** that check.
- **AC-G3** (docs/SPECIFICATION.md:396-408): same preconditions as AC-C6; Verification
  method: *"The real-Anthropic positive path is production-only and deferred until a
  real key is supplied to `llm-proxy`."*
- **§9 slice-status** (docs/SPECIFICATION.md:267-272) and **§10 open item**
  (docs/SPECIFICATION.md:460-465): confirm `llm-smoke` only proved the mock route; the
  real-Anthropic positive proof is the explicit remaining gap this slice closes.
- `litellm/config.yaml:1-9`: model `claude` → `anthropic/claude-3-5-sonnet-latest`,
  `api_key: os.environ/ANTHROPIC_API_KEY`. Model `claude-mock` uses `mock_response`
  and no key. Confirms fact (a) in the task brief.
- `docker-compose.yml:20-27` (`llm-proxy` service): `ANTHROPIC_API_KEY` is read only
  here; `mcp` service block (`docker-compose.yml:29-52`) has no `ANTHROPIC_API_KEY`
  reference anywhere — confirms fact (b).
- `docker-compose.yml:36` (`mcp.environment.NAM_LLM__MODEL: ${NAM_LLM__MODEL:-claude}`):
  the compose-level default is already the production model `claude`. However
  `.env.example:15` sets `NAM_LLM__MODEL=claude-mock` as the *documented* local-smoke
  default — confirms fact (c): for this slice the deployed `.env` must explicitly set
  `NAM_LLM__MODEL=claude` (not rely on `.env.example`'s mock default) so `mcp` selects
  the real route.
- **Network topology / egress finding (fact d):** `docker-compose.yml:59-62` declares
  both `db-net` and `llm-net` with `internal: true`. `llm-proxy` (`docker-compose.yml:
  16-27`) is attached to `llm-net` only; `mcp` is attached to both `db-net` and
  `llm-net`; `neo4j` is attached to `db-net` only. Docker Compose's `internal: true`
  network flag explicitly removes the network's route to the external world (no
  default gateway is configured on that bridge) — containers on an `internal` network
  can reach only other containers on the same network, never the internet. Since
  `llm-proxy`'s only network (`llm-net`) is `internal: true` and it has no other
  network attachment, **`llm-proxy` cannot reach `api.anthropic.com` as the stack is
  currently configured.** This is a genuine blocker for this slice, not a pre-existing
  passing state — **egress finding: NO, llm-proxy cannot currently reach Anthropic**
  (evidence: `docker-compose.yml:59-62` — both networks `internal: true`; `llm-proxy`
  has no other network in `docker-compose.yml:16-27`).
- `scripts/llm_smoke.py:1-121`: existing store→bolt-read→paraphrase-search driver,
  parameterized entirely by CLI flags (`--mcp-url`, `--neo4j-uri`, credentials); it
  calls `memory_store_message` then `memory_search` and asserts a Neo4j node exists.
  It does not itself assert anything about which LLM served the call (that evidence
  comes from `llm-proxy` logs) — it is reusable unmodified to trigger the real
  extraction call for this slice; log-based evidence is gathered separately via
  `docker compose logs llm-proxy`.

## 3. Normalized requirements

### R1 — Real Anthropic-backed completion serves `memory_store_message` extraction
- **Trigger:** `memory_store_message` is called against the running stack with
  `mcp`'s `NAM_LLM__MODEL=claude` and `llm-proxy` holding a real `ANTHROPIC_API_KEY`.
- **Preconditions:** Stack is up from a clean state (`docker compose down -v` then
  `up`); `.env` (or equivalent) sets `NAM_LLM__MODEL=claude` for `mcp`; the real
  Anthropic key from `~/.secrets/anthropic.env` is sourced into the `llm-proxy`
  service's environment only (never into `mcp` or `neo4j`); `llm-proxy` has the
  egress fix from R4 applied so it can reach `api.anthropic.com`.
- **Expected observable outcome:** The `memory_store_message` tool call completes
  successfully (no error), and `llm-proxy` logs show a request routed to model
  `claude` (`anthropic/claude-3-5-sonnet-latest`) with a corresponding upstream
  response — not a `mock_response` short-circuit.
- **Failure behaviour:** If `llm-proxy` cannot reach Anthropic (egress not fixed) or
  the key is invalid, the upstream call fails and `memory_store_message` surfaces an
  error (or the extraction step fails) rather than silently succeeding with no LLM
  content.
- **Verification method:** Run `scripts/llm_smoke.py` (unmodified) against the
  running stack; assert exit code / `LLM_SMOKE_OK`; separately assert (via
  `docker compose logs llm-proxy`) a log entry for the same request window showing
  model `claude` and a non-mock upstream response body.
- **Traces to:** AC-C6, AC-G3.

### R2 — Evidence the REAL model was hit (not the mock)
- **Trigger:** Same `memory_store_message` call as R1.
- **Preconditions:** Same as R1.
- **Expected observable outcome:** `llm-proxy` logs for this request contain upstream
  request/response data characteristic of a genuine Anthropic call (e.g. a
  `POST https://api.anthropic.com/...` upstream call logged by LiteLLM, or a response
  payload with Anthropic-shaped fields such as `id`, `model: claude-3-5-sonnet...`,
  `usage` token counts) and **do not** contain the canned string
  `"mock-ok: llm-smoke local response"` anywhere in the request/response for that
  call. The Neo4j node written for this call's marker reflects genuine extracted
  content, not the literal mock string.
- **Failure behaviour:** If the logged response is (or contains) the literal mock
  string, or no upstream Anthropic call is logged at all, the criterion fails — the
  real path was not exercised.
- **Verification method:** `docker compose logs llm-proxy | grep -A5 -B5 <request
  marker or timestamp>` to isolate the request; assert absence of the mock string
  and presence of Anthropic-response-shaped content; direct bolt read (reusing
  `scripts/llm_smoke.py`'s existing Cypher query pattern) of the stored node and
  assert its content does not equal the mock string.
- **Traces to:** AC-C6, AC-G3.

### R3 — Isolation preserved: `mcp` has no key and no direct Anthropic egress
- **Trigger:** The stack is running with the real key applied (R1 preconditions).
- **Preconditions:** Same as R1; `mcp` environment is inspected while the real call
  in R1 is succeeding.
- **Expected observable outcome:** `docker compose exec mcp env` (or `docker inspect`)
  shows no `ANTHROPIC_API_KEY` variable in the `mcp` container's environment; a
  reachability probe from inside `mcp` to `api.anthropic.com` (DNS resolution and/or
  TCP connect on 443) fails/times out, even though the real Anthropic call from
  `llm-proxy` is succeeding concurrently.
- **Failure behaviour:** If `ANTHROPIC_API_KEY` is present in `mcp`'s environment, or
  `mcp` can reach `api.anthropic.com`, isolation is violated and the criterion fails
  regardless of whether R1 otherwise passes — a real-Anthropic positive path must not
  come at the cost of AC-C6/AC-G3 isolation.
- **Verification method:** `docker compose exec mcp env | grep -i anthropic` asserted
  empty; `docker compose exec mcp sh -c "curl -m 5 -sS -o /dev/null -w '%{http_code}'
  https://api.anthropic.com || echo UNREACHABLE"` (or equivalent nc/DNS probe)
  asserted to fail/`UNREACHABLE`, run while R1's real call is active.
- **Traces to:** AC-C6, AC-G3, AC-C5, AC-G4 (network isolation is not weakened by
  granting `llm-proxy` egress).

### R4 — Any egress change grants outbound Anthropic access to `llm-proxy` ONLY
- **Trigger:** `docker compose config` is evaluated after the egress fix is applied,
  and reachability probes are run from all three services.
- **Preconditions:** The compose topology is modified per Option A (D1 resolution):
  a new non-internal network `llm-egress-net` is added and attached **only** to
  `llm-proxy`; `db-net` and `llm-net` remain `internal: true`; `neo4j` and `mcp`
  gain no new network attachment as part of this change.
- **Expected observable outcome:** `docker compose config` validates; from
  `llm-proxy`, a TCP/HTTPS reachability probe to `api.anthropic.com:443` succeeds;
  from `neo4j` and from `mcp`, the same probe still fails/times out; the pre-existing
  AC-C5 probes (`neo4j`↔`llm-proxy` mutual unreachability) still pass unchanged.
- **Failure behaviour:** If the egress change is implemented in a way that also gives
  `mcp` or `neo4j` a route to the public internet (e.g. by flipping `llm-net` itself
  to non-internal, which `mcp` also sits on), the criterion fails even if R1 passes —
  this is treated as an isolation regression, not an acceptable side effect.
- **Verification method:** Config lint (`docker compose config`); reachability probe
  `llm-proxy → api.anthropic.com:443` asserted to succeed; reachability probes
  `neo4j → api.anthropic.com:443` and `mcp → api.anthropic.com:443` asserted to fail;
  rerun of AC-C5's existing `neo4j ↔ llm-proxy` mutual-unreachability probes asserted
  unchanged (still both fail).
- **Traces to:** AC-C4, AC-C5, AC-G4 (no unintended egress/exposure introduced),
  AC-C6, AC-G3 (real path enabled without weakening isolation).

## 4. Verification criteria (mechanical checks, one per requirement)

| Req | Command |
|-----|---------|
| R1 | 1) `set -a; source ~/.secrets/anthropic.env; set +a` in the shell that runs `docker compose`, so `ANTHROPIC_API_KEY` is only exported to the `llm-proxy` service's env block (do not add it to `mcp`'s environment mapping). 2) Ensure `.env`/shell sets `NAM_LLM__MODEL=claude` (override `.env.example`'s `claude-mock` default). 3) `docker compose down -v && docker compose up -d --build`. 4) `python3 scripts/llm_smoke.py --neo4j-password "$NEO4J_PASSWORD"` — assert stdout ends `LLM_SMOKE_OK` and exit code 0. 5) `docker compose logs llm-proxy \| grep -i "claude-3-5-sonnet"` shows the request for the same run. |
| R2 | `docker compose logs llm-proxy \| grep -c "mock-ok: llm-smoke local response"` must be `0` for this run's request window; `docker compose logs llm-proxy \| grep -E "claude-3-5-sonnet\|anthropic"` must show at least one non-mock entry. Cross-check: bolt read (`cypher-shell` or the pattern in `scripts/llm_smoke.py:88-99`) for the run's marker node, assert its content field is not the literal string `mock-ok: llm-smoke local response`. |
| R3 | `docker compose exec mcp env \| grep -i anthropic` — assert empty output (no match). `docker compose exec mcp sh -c "curl -m 5 -sS -o /dev/null -w '%{http_code}\n' https://api.anthropic.com \|\| echo UNREACHABLE"` — assert output is `UNREACHABLE` or a connection-error indicator, run concurrently with/after a successful R1 run. |
| R4 | `docker compose config` — assert exit 0 (config lint). `docker compose exec llm-proxy sh -c "curl -m 5 -sS -o /dev/null -w '%{http_code}\n' https://api.anthropic.com"` — assert an HTTP status code (reachable). `docker compose exec neo4j sh -c "curl -m 5 -sS -o /dev/null -w '%{http_code}\n' https://api.anthropic.com \|\| echo UNREACHABLE"` and the same from `mcp` — both assert `UNREACHABLE`. Rerun existing AC-C5 probes: `docker compose exec neo4j sh -c "nc -zv -w5 llm-proxy 4000 \|\| echo UNREACHABLE"` and `docker compose exec llm-proxy sh -c "nc -zv -w5 neo4j 7687 \|\| echo UNREACHABLE"` — both still assert `UNREACHABLE`. |

All commands pipe output directly (never redirect to a temp file); no command
writes to `/tmp` per this repo's environment constraints.

## 5. Explicit scope

**In scope:**
- Sourcing the real `ANTHROPIC_API_KEY` (from `~/.secrets/anthropic.env`, host-side
  only) into the `llm-proxy` service's environment exclusively.
- Setting `mcp`'s `NAM_LLM__MODEL=claude` for this verification run.
- A network/egress change limited to granting `llm-proxy` (and only `llm-proxy`)
  outbound reachability to the public Anthropic API.
- Reusing `scripts/llm_smoke.py` unmodified (or documenting why a minimal adaptation
  is needed) to trigger the real completion.
- Log-based and reachability-probe-based evidence collection proving R1–R4.
- Updating `docs/SPECIFICATION.md` §9/§10 bookkeeping once verified (reconciliation
  stage's job, not this stage's — noted for completeness only).

**Out of scope:**
- Changing the embedding/vector-search path (AC-C7/AC-G5) — untouched, already
  verified in `llm-smoke`.
- Removing, replacing, or altering the `claude-mock` model/local-smoke path — it
  remains available for future local smoke runs.
- Any change to `mcp`'s network attachments (`db-net`, `llm-net`) or granting `mcp`
  any new egress.
- Broad host-level firewall/iptables changes beyond what's needed for the
  `llm-proxy`-only egress grant.
- Committing or printing the real `ANTHROPIC_API_KEY` value anywhere (logs, spec,
  handoff files, git history).
- Pinning the exact Anthropic model id / framework version (tracked separately in
  §10's existing open item, docs/SPECIFICATION.md:456-458).

## 6. Resolved decisions (Class 1 — for the record)

### D1 — How should `llm-proxy` be granted outbound Anthropic egress? **RESOLVED: Option A**

The stack currently has **no way** for `llm-proxy` to reach the internet: both
`db-net` and `llm-net` are `internal: true` (`docker-compose.yml:59-62`), and
`llm-proxy` has no other network. This was a genuine architecture decision with
security/isolation impact.

**Option selected: Option A** — Add a new, dedicated non-internal network
(`llm-egress-net`) attached **only** to the `llm-proxy` service. `llm-net` stays
`internal: true` unchanged (still the only path `mcp`↔`llm-proxy` traffic uses).
`llm-proxy` gets a second interface with a real gateway/route to the internet;
`mcp` and `neo4j` are untouched and gain no new network. This is the minimal,
additive change that keeps every existing AC-C4/AC-C5/AC-G4 probe true unchanged
and only adds a new, narrowly-scoped positive probe (R4).

**Rationale:** Option A is the smallest change, keeps `mcp`/`neo4j` network
membership byte-for-byte identical to today, and every existing AC-C4/AC-C5/AC-G4
verification method continues to apply unmodified — only R4's new probes are
additive.

## 7. Recorded facts & safe choices (Class 2 / Class 3)

- **(Class 2)** `llm-proxy` cannot currently reach Anthropic: both networks are
  `internal: true` and `llm-proxy` has no other attachment.
  (`docker-compose.yml:16-27`, `:59-62`.)
- **(Class 2)** `mcp`'s model selection is `NAM_LLM__MODEL`, compose-default already
  `claude` (`docker-compose.yml:36`), but `.env.example` documents `claude-mock` as
  the local-smoke default (`.env.example:15`) — this slice must override it to
  `claude` in whatever `.env`/shell env is used for the verification run.
  (`docker-compose.yml:36`, `.env.example:11-15`.)
- **(Class 2)** `mcp` never references `ANTHROPIC_API_KEY` anywhere in
  `docker-compose.yml` — confirmed by inspection of the full `mcp.environment` block
  (`docker-compose.yml:29-45`).
- **(Class 3)** Reuse `scripts/llm_smoke.py` unmodified as the trigger mechanism
  rather than writing a new script. Chose reuse over a new script because it already
  implements the exact store→bolt-read→search sequence needed to trigger extraction
  and is parameterized by CLI flags with no hardcoded mock assumptions
  (`scripts/llm_smoke.py:1-24`, `:52-121`); reversible (a new script can always be
  added later if reuse proves insufficient).
- **(Class 3)** Evidence for R2's "real model was hit" uses `docker compose logs
  llm-proxy` grep-based assertions (absence of the mock string, presence of
  Anthropic-response-shaped content) rather than requiring LiteLLM's more structured
  request-logging/callback features. Chose the simpler log-grep approach because it
  needs no new LiteLLM config and is sufficient to distinguish a real upstream call
  from the `mock_response` short-circuit already used to prove the opposite in
  `llm-smoke`; reversible/no contract impact.
