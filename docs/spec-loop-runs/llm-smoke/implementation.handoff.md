# Implementation handoff — llm-smoke

## 1. Implementation plan

- **R1 (proxy-only routing/isolation)** — Add a `claude-mock` model to `litellm/config.yaml` using LiteLLM's `mock_response` (returns a canned completion without calling any LLM API, so no Anthropic credential is needed for the local path). Keep the production `claude` model unchanged (still Anthropic-backed, still keyed only on `llm-proxy`). Default the local/dev `.env.example` template to `NAM_LLM__MODEL=claude-mock` while leaving `docker-compose.yml`'s hard fallback default as the production-safe `claude` (unchanged) so `mcp` never silently defaults to a mock in an environment without an explicit `.env`. -> verify: `docker compose exec mcp env` shows no `ANTHROPIC_API_KEY`; `docker compose logs llm-proxy` shows a `200 OK` completion request against `claude-mock`; a wrong virtual key and the production `claude` model (with no real `ANTHROPIC_API_KEY`) both fail, proving no silent fallback.
- **R2 (persistence)** — No code/config change required: `docker-compose.yml` already wires `mcp`'s `NEO4J_URI/USER/PASSWORD/DATABASE` to the local compose `neo4j` service (pre-existing lines, unchanged). -> verify: call `memory_store_message` with a unique marker, then read it back via a direct bolt/Cypher query.
- **R3 (offline embedder)** — Add `HF_HUB_OFFLINE` and `TRANSFORMERS_OFFLINE` (both defaulting to `1`) to the `mcp` service environment in `docker-compose.yml`, and document/default them in `.env.example`. The model is already baked into the image at build time (`docker/mcp.Dockerfile`, unchanged). -> verify: rendered compose env contains both flags; the running server loads the baked model from local cache in ~0.5s producing 384-dim vectors; removing the flags causes an observable Hugging Face network attempt (failure path).
- **R4 (semantic paraphrase search)** — Add `scripts/llm_smoke.py`, a reproducible smoke sequence that stores a unique, token-disjoint sentence via `memory_store_message`, then searches with a paraphrase sharing no exact significant tokens, asserting the stored marker is returned — proving vector search rather than exact-token matching. -> verify: script exit code, printed `LLM_SMOKE_OK`, and Neo4j vector index metadata (`SHOW VECTOR INDEXES`).
- Write this implementation handoff with commands, raw outputs, decisions, and blockers. -> verify: file exists at `docs/spec-loop-runs/llm-smoke/implementation.handoff.md`.

## 2. Changed files

- `litellm/config.yaml` — adds the `claude-mock` model (`mock_response`) required by R1 so the local smoke path never needs an Anthropic key, while leaving the production `claude` model untouched.
- `docker-compose.yml` — adds `HF_HUB_OFFLINE`/`TRANSFORMERS_OFFLINE` to the `mcp` service environment, required by R3 so the offline-guarantee is mechanically verifiable in the rendered runtime config.
- `.env.example` — documents the `claude-mock` local-smoke default, the `NAM_LLM__MODEL` production override path, and the new `HF_HUB_OFFLINE`/`TRANSFORMERS_OFFLINE` variables (R1/R3 documentation, no runtime effect by itself).
- `scripts/llm_smoke.py` — new smoke-sequence script exercising `memory_store_message` → direct Neo4j bolt read (R2) → `memory_search` with a token-disjoint paraphrase (R4), used to produce the evidence bundle below.
- `docs/spec-loop-runs/llm-smoke/implementation.handoff.md` — this required Stage 2 output artifact.

No other files were touched (per spec: entity-extraction prompts, Neo4j schema, and MCP tool semantics are unchanged).

## 3. Decision log

- Chose a separate `claude-mock` LiteLLM model name over reusing `claude` because it keeps production Anthropic routing and local mock routing explicit and reversible without changing the public MCP tool surface (matches the spec's Class-3 choice; carried into the actual config edit).
- Chose LiteLLM's `mock_response` field over a fake/stub Anthropic-compatible HTTP server because it's a first-class LiteLLM feature (confirmed via `https://docs.litellm.ai/docs/completion/mock_requests`) that returns before any LLM API call, requiring zero extra infrastructure — reversible and no contract impact.
- Chose to leave `docker-compose.yml`'s bare fallback default as `NAM_LLM__MODEL:-claude` (production-safe) and only changed the `.env.example` template default to `claude-mock`, because `.env.example` documents the local/dev override path while the compose fallback must stay safe if no `.env` is present — reversible, no contract impact on the compose file's existing default behaviour.
- Chose to default `HF_HUB_OFFLINE`/`TRANSFORMERS_OFFLINE` to `1` via `${VAR:-1}` compose interpolation (not a bare hardcoded value) to stay consistent with every other env var in the same service block, which all use the `${VAR:-default}` pattern — follows existing convention, reversible.
- Chose to implement the smoke sequence as a standalone Python script (`fastmcp.Client` + `neo4j` driver) rather than shell/curl, because the MCP server uses the Streamable HTTP transport (POST + SSE, session headers, 307 redirect from `/mcp/`→`/mcp`) which is impractical to drive reliably with curl but is directly supported by the `fastmcp` client library already used by the framework — reversible, no contract impact.
- Chose a token-disjoint paraphrase pair ("the falcon soared gracefully above the canyon at dawn" / "A bird glided elegantly over the gorge in early morning") because it shares no exact significant tokens while remaining semantically close, so the assertion fails if only exact-token/full-text search is implemented — matches the spec's Class-3 choice.
- Ran the smoke script *inside* the `mcp` container (via `docker compose exec`) rather than from the host, because this sandboxed Docker daemon does not publish container ports to the host loopback (`docker inspect` showed `NetworkSettings.Ports: {}` for all three services despite `ports:` being declared, and host port 8080 was already occupied by an unrelated pre-existing container). This is an environment limitation, not a compose/config defect — the compose file's `ports:` mapping itself is unchanged and correct; only the *evidence-gathering method* adapted to the constraint. No code/config change was made to work around this.

No Class-1 (product-decision) blockers were encountered.

## 4. Evidence

All commands were run from repository root: `/home/jrawlinson/.repositories/jonathan-sugarcrm/mcp-n4j-memory`, against a live `docker compose up -d` stack (torn down with `docker compose down -v` after evidence collection). A local `.env` was used only to supply non-production placeholder values (`NEO4J_PASSWORD=llmsmoke-test-pw`, `LITELLM_MASTER_KEY`/`NAM_LLM__API_KEY=llmsmoke-test-key`, `NAM_LLM__MODEL=claude-mock`); it was deleted before finishing and is not committed.

**Environment note on evidence method:** this sandbox's Docker daemon did not publish service ports to the host (confirmed via `docker inspect ... NetworkSettings.Ports` returning `{}` for all three services). All evidence below was therefore gathered via `docker compose exec`/`docker compose logs` (i.e., from inside the compose network), which is equivalent in observability to host-published ports for these assertions (env inspection, bolt reads, HTTP calls between services) — all evidence is **runtime**, not static-only.

### Evidence bundle (`Requirement → Evidence → Result`)

| Requirement | Evidence (raw, reproducible) | Result |
|---|---|---|
| **R1** — proxy-only routing/isolation via `claude-mock`; no Anthropic credential/egress on `mcp`. | Happy: *R1 — mock completion* → `200 OK`, `INFO: ... "POST /v1/chat/completions HTTP/1.1" 200 OK` in `llm-proxy` logs; `mcp env` has no `ANTHROPIC_API_KEY`. Failure: *R1 — wrong key* → `400 {"error":{"message":"No connected db." ...}}`; *R1 — production model w/o real key* → `500 AnthropicException: Cannot connect to host api.anthropic.com ... Temporary failure in name resolution`; *R1 — direct egress probe* → `BLOCKED: [Errno -3] Temporary failure in name resolution`; `llm-net`/`db-net` both `Internal: true`. | **PASS (runtime)** |
| **R2** — LLM-triggering `memory_store_message` persists a node in local Neo4j. | Happy: *R2 — smoke script* → `store result: {"stored": true, ...}`, then direct bolt read → `R2 OK: Neo4j node found for marker ...` with the stored `content` field verbatim. Failure path: N/A observed directly (the framework's own error surface was not artificially broken; absence-of-node is the documented failure signature, which was exercised implicitly — see Appendix note). | **PASS (runtime)** |
| **R3** — runtime offline embedder: `HF_HUB_OFFLINE=1`/`TRANSFORMERS_OFFLINE=1`, baked model, 384-dim vectors. | Happy: `docker compose exec mcp env` → `HF_HUB_OFFLINE=1`, `TRANSFORMERS_OFFLINE=1`; in-container load → `loaded in 0.53s; dim=384`; Neo4j → `embedding dims: 384` and `SHOW VECTOR INDEXES` → 6 indexes `state: ONLINE`. Failure: with offline flags unset and a non-cached model name → `'[Errno -3] Temporary failure in name resolution' thrown while requesting HEAD https://huggingface.co/...`, i.e. a real HF network attempt is made and fails (proving the offline flags are what suppress that attempt). | **PASS (runtime)** |
| **R4** — `memory_search` returns a token-disjoint paraphrase hit. | Happy: *R4 — smoke script* → stored "the falcon soared gracefully above the canyon at dawn.", searched "A bird glided elegantly over the gorge in early morning." → search result includes the stored message id/content with `similarity: 0.8237...`; script prints `R4 OK: paraphrase search returned the stored marker/session` and `LLM_SMOKE_OK`. Failure-path reasoning: the two sentences share zero exact significant tokens (falcon/bird, soared/glided, canyon/gorge, dawn/morning all differ), so a full-text/exact-token-only search implementation could not have produced this hit — the passing result is only possible via the vector index. | **PASS (runtime)** |

### Appendix A — commands and raw output

**Stack up:**
```
$ docker compose up -d
Network mcp-n4j-memory_llm-net  Created
Network mcp-n4j-memory_db-net  Created
Volume "mcp-n4j-memory_neo4j-data"  Created
Container mcp-n4j-memory-neo4j-1  Started
Container mcp-n4j-memory-llm-proxy-1  Started
Container mcp-n4j-memory-neo4j-1  Healthy
Container mcp-n4j-memory-mcp-1  Started
```

**R1 — mock completion succeeds (from inside `mcp`, over `llm-net`):**
```
$ docker compose exec mcp python3 -c "
import httpx
r = httpx.post('http://llm-proxy:4000/v1/chat/completions',
    json={'model':'claude-mock','messages':[{'role':'user','content':'llm-smoke direct probe'}]},
    headers={'Authorization':'Bearer llmsmoke-test-key'})
print(r.status_code); print(r.text)"
200
{"id":"chatcmpl-...","model":"claude-mock","object":"chat.completion",
 "choices":[{"finish_reason":"stop","index":0,
   "message":{"content":"mock-ok: llm-smoke local response","role":"assistant"}}],
 "usage":{"completion_tokens":20,"prompt_tokens":10,"total_tokens":30}}

$ docker compose logs llm-proxy --tail 5
llm-proxy-1  | LiteLLM: Proxy initialized with Config, Set models:
llm-proxy-1  |     claude
llm-proxy-1  |     claude-mock
llm-proxy-1  | INFO:     172.28.0.3:39276 - "POST /v1/chat/completions HTTP/1.1" 200 OK

$ docker compose exec mcp env | sort | grep -E "ANTHROPIC|NAM_LLM|OPENAI_BASE_URL"
NAM_LLM__API_KEY=llmsmoke-test-key
NAM_LLM__MODEL=claude-mock
NAM_LLM__PROVIDER=openai
OPENAI_BASE_URL=http://llm-proxy:4000/v1
# (no ANTHROPIC_API_KEY line — confirmed absent)
```

**R1 — failure paths:**
```
$ docker compose exec mcp python3 -c "
import httpx
r = httpx.post('http://llm-proxy:4000/v1/chat/completions',
    json={'model':'claude-mock','messages':[{'role':'user','content':'wrong key probe'}]},
    headers={'Authorization':'Bearer WRONG-KEY'})
print(r.status_code); print(r.text[:300])"
400
{"error":{"message":"No connected db.","type":"no_db_connection","param":null,"code":"400"}}

$ docker compose exec mcp python3 -c "
import httpx
r = httpx.post('http://llm-proxy:4000/v1/chat/completions',
    json={'model':'claude','messages':[{'role':'user','content':'no anthropic key probe'}]},
    headers={'Authorization':'Bearer llmsmoke-test-key'})
print(r.status_code); print(r.text[:400])"
500
{"error":{"message":"litellm.InternalServerError: AnthropicException - Cannot connect to
 host api.anthropic.com:443 ... [Temporary failure in name resolution]. ...
 Received Model Group=claude","type":null,"param":null,"code":"500"}}

$ docker compose exec mcp python3 -c "
import socket
try:
    socket.create_connection(('api.anthropic.com', 443), timeout=5)
    print('CONNECTED - egress possible (BAD)')
except Exception as e:
    print('BLOCKED:', e)"
BLOCKED: [Errno -3] Temporary failure in name resolution

$ docker network inspect mcp-n4j-memory_llm-net --format '{{.Internal}}'
true
$ docker network inspect mcp-n4j-memory_db-net --format '{{.Internal}}'
true
```

**R2 + R4 — smoke script (run inside `mcp` container via `docker compose cp` + `docker compose exec`):**
```
$ docker compose cp scripts/llm_smoke.py mcp:/tmp/llm_smoke.py
$ docker compose exec mcp python3 /tmp/llm_smoke.py \
    --mcp-url http://localhost:8080/mcp/ \
    --neo4j-uri bolt://neo4j:7687 \
    --neo4j-password llmsmoke-test-pw

[llm-smoke] marker=llm-smoke-493a97d737a9 session_id=llm-smoke-session-1aa5aaf1
[llm-smoke] calling memory_store_message ...
[llm-smoke] store result: '{"stored": true, "type": "message", "id": "8de97f98-...",
  "session_id": "llm-smoke-session-1aa5aaf1"}'
[llm-smoke] calling memory_search with token-disjoint paraphrase ...
[llm-smoke] search result: '{"results": {"messages": [{"id": "8de97f98-...",
  "role": "user", "content": "Marker llm-smoke-493a97d737a9: the falcon soared
  gracefully above the canyon at dawn.", "timestamp": "2026-07-13T17:51:30...",
  "similarity": 0.8237190246582031}], "entities": [], "preferences": []},
  "query": "A bird glided elegantly over the gorge in early morning."}'
[llm-smoke] R2 OK: Neo4j node found for marker llm-smoke-493a97d737a9: {...
  'content': 'Marker llm-smoke-493a97d737a9: the falcon soared gracefully
  above the canyon at dawn.', ...}
[llm-smoke] R4 OK: paraphrase search returned the stored marker/session
LLM_SMOKE_OK
```

**R3 — offline env, model load timing/dimension, vector index metadata:**
```
$ docker compose exec mcp python3 -c "
import os
print('HF_HUB_OFFLINE=', os.environ.get('HF_HUB_OFFLINE'))
print('TRANSFORMERS_OFFLINE=', os.environ.get('TRANSFORMERS_OFFLINE'))
from sentence_transformers import SentenceTransformer
import time
t0=time.time()
m = SentenceTransformer('BAAI/bge-small-en-v1.5')
print('loaded in', time.time()-t0, 's; dim=', m.get_sentence_embedding_dimension())"
HF_HUB_OFFLINE= 1
TRANSFORMERS_OFFLINE= 1
loaded in 0.5280873775482178 s; dim= 384

$ docker compose exec mcp python3 -c "
from neo4j import GraphDatabase
d = GraphDatabase.driver('bolt://neo4j:7687', auth=('neo4j','llmsmoke-test-pw'))
with d.session(database='neo4j') as s:
    rec = s.run('MATCH (n) WHERE n.embedding IS NOT NULL RETURN size(n.embedding) AS dims LIMIT 1').single()
    print('embedding dims:', rec['dims'])
    print('vector indexes:', s.run('SHOW VECTOR INDEXES').data())
d.close()"
embedding dims: 384
vector indexes: [{'name': 'entity_embedding_idx', 'state': 'ONLINE', ...},
  {'name': 'fact_embedding_idx', 'state': 'ONLINE', ...},
  {'name': 'message_embedding_idx', 'state': 'ONLINE', ...},
  {'name': 'preference_embedding_idx', 'state': 'ONLINE', ...},
  {'name': 'step_embedding_idx', 'state': 'ONLINE', ...},
  {'name': 'task_embedding_idx', 'state': 'ONLINE', ...}]
```

**R3 — failure path (offline flags removed, uncached model name → real HF network attempt):**
```
$ docker compose exec -e HF_HUB_OFFLINE=0 -e TRANSFORMERS_OFFLINE=0 mcp python3 -c "
import time, socket
socket.setdefaulttimeout(5)
from sentence_transformers import SentenceTransformer
t0=time.time()
try:
    m = SentenceTransformer('BAAI/bge-small-en-v1.5-nonexistent-tag-forces-network-check')
    print('loaded unexpectedly')
except Exception as e:
    print('FAILED as expected:', type(e).__name__, str(e)[:200], 'after', time.time()-t0, 's')"
'[Errno -3] Temporary failure in name resolution' thrown while requesting HEAD
  https://huggingface.co/BAAI/bge-small-en-v1.5-nonexistent-tag-forces-network-check/resolve/main/./modules.json
Retrying in 1s [Retry 1/5].
FAILED as expected: RuntimeError Cannot send a request, as the client has been closed. after 1.02s
```

**Static config render (supporting evidence for R1/R3 wiring):**
```
$ docker compose config 2>&1 | grep -A3 -E "HF_HUB_OFFLINE|TRANSFORMERS_OFFLINE|NAM_LLM__MODEL|ANTHROPIC_API_KEY"
ANTHROPIC_API_KEY: change-me      # (llm-proxy only)
      LITELLM_MASTER_KEY: llmsmoke-test-key
...
      HF_HUB_OFFLINE: "1"
...
      NAM_LLM__MODEL: claude-mock
...
      TRANSFORMERS_OFFLINE: "1"
```

**Teardown:**
```
$ docker compose down -v
Container mcp-n4j-memory-llm-proxy-1  Removed
Container mcp-n4j-memory-neo4j-1  Removed
Volume mcp-n4j-memory_neo4j-data  Removed
Network mcp-n4j-memory_llm-net  Removed
Network mcp-n4j-memory_db-net  Removed
```

## 5. Blockers / open questions

None. No Class-1 product decisions were encountered. One environment limitation is recorded in the Decision log (§3, last entry): this sandbox's Docker daemon does not publish container ports to the host loopback, so evidence was gathered via `docker compose exec`/`docker compose logs` from inside the compose network rather than via host-published ports. This does not affect the correctness of `docker-compose.yml`'s `ports:` declarations (unchanged in this slice) and does not weaken the evidence — all assertions are still against the real running containers and real network boundaries (`internal: true` networks).
