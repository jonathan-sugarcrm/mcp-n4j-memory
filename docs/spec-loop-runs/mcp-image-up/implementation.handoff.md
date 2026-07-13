# Implementation handoff — mcp-image-up

## Implementation plan

1. `[fix-dockerfile] -> verify: docker image inspect shows ENTRYPOINT ["neo4j-agent-memory","mcp","serve"], CMD contains only accepted serve flags, and the install line includes the sentence-transformers extra needed by the bake step.`
2. `[build-image] -> verify: docker build -q -f docker/mcp.Dockerfile -t mcp-n4j-memory:mcp-image-up-impl . exits 0 and returns an image digest.`
3. `[verify-r1-cli] -> verify: run the installed help command, inspect ENTRYPOINT/CMD, show an unsupported flag is rejected, and run the configured startup far enough to show failure is not Click option rejection.`
4. `[verify-r3-offline-embedder] -> verify: docker run --network none with HF_HUB_OFFLINE=1 and TRANSFORMERS_OFFLINE=1 loads BAAI/bge-small-en-v1.5 locally and asserts vector length 384; a missing offline model exits non-zero.`
5. `[verify-r2-runtime] -> verify: docker compose -p mcp-image-up-impl starts the stack with MCP host port overridden to 127.0.0.1:18080, in-container probes connect to neo4j:7687 and llm-proxy:4000, FastMCP list_tools returns the exact 16-name set, and failure probes show missing network/profile cases fail.`
6. `[cleanup-and-handoff] -> verify: docker compose -p mcp-image-up-impl down -v completes, the temporary compose override is removed, and this handoff records raw evidence.`

## Changed files

- `docker/mcp.Dockerfile` — R1/R3: installs `neo4j-agent-memory[mcp,sentence-transformers]==0.2.0`, bakes the local model, starts with `neo4j-agent-memory mcp serve`, and removes unsupported serve flags.
- `docker-compose.yml` — R2/R3: replaces invalid flat `NAM_LLM`/`NAM_EMBEDDING` container config with nested `NAM_*` env consumed by `MemorySettings`; adds OpenAI-compatible base URL pointing at `llm-proxy` for placeholder/non-LLM startup wiring.
- `.env.example` — R2/R3: documents the same nested LLM and embedding env wiring using placeholder values only.
- `docs/spec-loop-runs/mcp-image-up/implementation.handoff.md` — required Stage-2 artifact for this slice.

## Decision log

- Chose `neo4j-agent-memory[mcp,sentence-transformers]==0.2.0` over `neo4j-agent-memory[full]==0.2.0` because the handoff identifies the specific missing extra and the narrower extra is reversible with lower dependency blast radius.
- Chose to keep Neo4j connection flags out of CMD and rely on `NEO4J_*` env because the handoff records those Click env vars as accepted/read directly, and this keeps CMD limited to transport/profile flags.
- Chose a socket-based Docker healthcheck over the prior `/sse` URL check because FastMCP HTTP uses `/mcp`; a TCP readiness check is an internal healthcheck choice with no public contract impact.
- Chose nested `NAM_LLM__PROVIDER`/`NAM_LLM__MODEL`/`NAM_LLM__API_KEY` over flat `NAM_LLM` because runtime evidence showed flat `NAM_LLM` is rejected by `MemorySettings` before startup.
- Chose `OPENAI_BASE_URL=http://llm-proxy:4000/v1` with placeholder key over changing LiteLLM model semantics because no LLM call is in scope and the value is reversible startup wiring for the existing proxy.
- Chose to create a temporary override file at `docs/spec-loop-runs/mcp-image-up/compose.impl.override.yml` instead of copying the compose file because Docker resolves relative bind mounts against compose file paths; the override only changed MCP host port and was removed during cleanup.
- Chose host port `127.0.0.1:18080:8080` over stopping the existing `graphmind-mcp` container on 8080 because this is a reversible verification-only environment accommodation.
- Chose in-container Python socket probes over adding utilities such as `nc` because Python is already present in the MCP image and this avoids changing dependencies for tests.
- Chose FastMCP's Python client inside the running MCP container over a host-installed client because the image already includes FastMCP and this avoids host dependency assumptions.
- Chose a temporary core-profile sidecar container to prove wrong-profile failure behavior because it exercises the same built image without modifying the compose service under test.
- Chose to keep the built image `mcp-n4j-memory:mcp-image-up-impl` after cleanup because retaining the verified image is useful for Stage 3 reproduction; the compose stack, volumes, networks, and temporary override file were removed.

## Evidence

### R1 — Built image uses the real framework MCP CLI and accepted serve options

#### Build command/output

Command:

```sh
docker build -q -f docker/mcp.Dockerfile -t mcp-n4j-memory:mcp-image-up-impl .
```

Output:

```text
2026/07/13 16:40:23 in: []string{}
2026/07/13 16:40:23 Parsed entitlements: []
sha256:04380fcbeb8150346d449b25ba0b2e7e9736bdb9c3289ab3697f819940e1dbf3
<shellId: build-mcp-quiet completed with exit code 0>
```

#### Entrypoint/CMD, help, unsupported flag, and startup smoke

Command:

```sh
printf 'ENTRYPOINT/CMD inspect:\n' && \
  docker image inspect mcp-n4j-memory:mcp-image-up-impl --format 'Entrypoint={{json .Config.Entrypoint}} Cmd={{json .Config.Cmd}}' && \
printf '\nserve help excerpt:\n' && \
  docker run --rm --entrypoint neo4j-agent-memory mcp-n4j-memory:mcp-image-up-impl mcp serve --help | sed -n '1,80p' && \
printf '\nunsupported flag check:\n' && \
  docker run --rm --entrypoint neo4j-agent-memory mcp-n4j-memory:mcp-image-up-impl mcp serve --backend bolt 2>&1; printf 'unsupported_exit=%s\n' "$?" && \
printf '\nconfigured startup smoke filtered (no Click unsupported option expected):\n' && \
set -o pipefail; timeout 12 docker run --rm -e NEO4J_URI=bolt://127.0.0.1:1 -e NEO4J_PASSWORD=change-me mcp-n4j-memory:mcp-image-up-impl 2>&1 | grep -E 'FastMCP|No such option|ConnectionError|Neo4j service unavailable'; status=${PIPESTATUS[0]}; printf 'startup_exit=%s\n' "$status"
```

Output:

```text
ENTRYPOINT/CMD inspect:
Entrypoint=["neo4j-agent-memory","mcp","serve"] Cmd=["--transport","http","--host","0.0.0.0","--port","8080","--profile","extended"]

serve help excerpt:
/usr/local/lib/python3.12/site-packages/fastmcp/server/auth/providers/jwt.py:10: AuthlibDeprecationWarning: authlib.jose module is deprecated, please use joserfc instead.
It will be compatible before version 2.0.0.
  from authlib.jose import JsonWebKey, JsonWebToken
Usage: neo4j-agent-memory mcp serve [OPTIONS]

  Start the MCP server for Claude Desktop and other MCP hosts.

  The server exposes memory tools, resources, and prompts via the Model
  Context Protocol. Use stdio transport for Claude Desktop or SSE/HTTP for
  network deployments.

  Examples:
      # Start with stdio transport (for Claude Desktop)
      neo4j-agent-memory mcp serve --password mypassword

      # Start with SSE transport on port 8080
      neo4j-agent-memory mcp serve --transport sse --port 8080

      # Start with core profile (fewer tools, less context overhead)
      neo4j-agent-memory mcp serve --profile core

Options:
  --uri TEXT                      Neo4j connection URI.
  --user TEXT                     Neo4j username.
  --password TEXT                 Neo4j password (or NEO4J_PASSWORD env var).
  --database TEXT                 Neo4j database name.
  --transport [stdio|sse|http]    MCP transport type (default: stdio).
  --host TEXT                     Host for network transports.
  --port INTEGER                  Port for network transports.
  --profile [core|extended]       Tool profile: core (6 tools) or extended (16
                                  tools).
  --session-strategy [per_conversation|per_day|persistent]
                                  Session identity strategy.
  --user-id TEXT                  User ID for per_day/persistent session
                                  strategies.
  --observation-threshold INTEGER
                                  Token threshold for observational memory
                                  compression.
  --no-auto-preferences           Disable automatic preference detection.
  --help                          Show this message and exit.

unsupported flag check:
/usr/local/lib/python3.12/site-packages/fastmcp/server/auth/providers/jwt.py:10: AuthlibDeprecationWarning: authlib.jose module is deprecated, please use joserfc instead.
It will be compatible before version 2.0.0.
  from authlib.jose import JsonWebKey, JsonWebToken
Usage: neo4j-agent-memory mcp serve [OPTIONS]
Try 'neo4j-agent-memory mcp serve --help' for help.

Error: No such option '--backend'.
exit status 2
unsupported_exit=2

configured startup smoke filtered (no Click unsupported option expected):
│                                FastMCP 2.14.7                                │
│                          ✨ FastMCP 3.0 is coming!                           │
    raise ConnectionError(f"Neo4j service unavailable: {e}") from e
neo4j_agent_memory.core.exceptions.ConnectionError: Neo4j service unavailable: Couldn't connect to 127.0.0.1:1 (resolved to ('127.0.0.1:1',)):
startup_exit=1
<shellId: r1-startup-compact completed with exit code 0>
```

### R2 — Running `mcp` reaches both peers and exposes exactly the extended tool set

#### Compose start with alternate MCP host port

Command:

```sh
cat > docs/spec-loop-runs/mcp-image-up/compose.impl.override.yml <<'YAML'
services:
  mcp:
    image: mcp-n4j-memory:mcp-image-up-impl
    ports: !override
      - "127.0.0.1:18080:8080"
YAML
docker compose -f docker-compose.yml -f docs/spec-loop-runs/mcp-image-up/compose.impl.override.yml config --format yaml | sed -n '/mcp:/,/^[a-z]/p'
docker compose -p mcp-image-up-impl -f docker-compose.yml -f docs/spec-loop-runs/mcp-image-up/compose.impl.override.yml up -d --build
```

Output:

```text
mcp:
    build:
      context: /home/jrawlinson/.repositories/jonathan-sugarcrm/mcp-n4j-memory
      dockerfile: docker/mcp.Dockerfile
    environment:
      MCP_HOST: 0.0.0.0
      MCP_PORT: "8080"
      MCP_TRANSPORT: http
      NAM_EMBEDDING__DIMENSIONS: "384"
      NAM_EMBEDDING__MODEL: BAAI/bge-small-en-v1.5
      NAM_EMBEDDING__PROVIDER: sentence_transformers
      NAM_LLM__API_KEY: change-me
      NAM_LLM__MODEL: claude
      NAM_LLM__PROVIDER: openai
      NEO4J_DATABASE: neo4j
      NEO4J_PASSWORD: change-me
      NEO4J_URI: bolt://neo4j:7687
      NEO4J_USER: neo4j
      OPENAI_BASE_URL: http://llm-proxy:4000/v1
    image: mcp-n4j-memory:mcp-image-up-impl
    networks:
      db-net: null
      llm-net: null
    ports:
      - mode: ingress
        host_ip: 127.0.0.1
        target: 8080
        published: "18080"
        protocol: tcp
 mcp  Built
 Network mcp-image-up-impl_db-net  Creating
 Network mcp-image-up-impl_db-net  Created
 Network mcp-image-up-impl_llm-net  Creating
 Network mcp-image-up-impl_llm-net  Created
 Volume "mcp-image-up-impl_neo4j-data"  Creating
 Volume "mcp-image-up-impl_neo4j-data"  Created
 Container mcp-image-up-impl-neo4j-1  Creating
 Container mcp-image-up-impl-llm-proxy-1  Creating
 Container mcp-image-up-impl-llm-proxy-1  Created
 Container mcp-image-up-impl-neo4j-1  Created
 Container mcp-image-up-impl-mcp-1  Creating
 Container mcp-image-up-impl-mcp-1  Created
 Container mcp-image-up-impl-llm-proxy-1  Starting
 Container mcp-image-up-impl-neo4j-1  Starting
 Container mcp-image-up-impl-neo4j-1  Started
 Container mcp-image-up-impl-llm-proxy-1  Started
 Container mcp-image-up-impl-neo4j-1  Waiting
 Container mcp-image-up-impl-neo4j-1  Healthy
 Container mcp-image-up-impl-mcp-1  Starting
 Container mcp-image-up-impl-mcp-1  Started
<shellId: compose-up completed with exit code 0>
```

#### Runtime startup evidence after nested LLM config fix

Command:

```sh
docker compose -p mcp-image-up-impl -f docker-compose.yml -f docs/spec-loop-runs/mcp-image-up/compose.impl.override.yml up -d --build mcp && sleep 8 && \
docker compose -p mcp-image-up-impl -f docker-compose.yml -f docs/spec-loop-runs/mcp-image-up/compose.impl.override.yml ps && \
printf '\nmcp logs tail:\n' && \
docker compose -p mcp-image-up-impl -f docker-compose.yml -f docs/spec-loop-runs/mcp-image-up/compose.impl.override.yml logs --no-color --tail=80 mcp
```

Output:

```text
NAME                            IMAGE                                 COMMAND                  SERVICE     CREATED              STATUS                            PORTS
mcp-image-up-impl-llm-proxy-1   ghcr.io/berriai/litellm:main-stable   "docker/prod_entrypo…"   llm-proxy   About a minute ago   Up About a minute                 
mcp-image-up-impl-mcp-1         mcp-n4j-memory:mcp-image-up-impl      "neo4j-agent-memory …"   mcp         9 seconds ago        Up 8 seconds (health: starting)   
mcp-image-up-impl-neo4j-1       neo4j:5                               "tini -g -- /startup…"   neo4j       About a minute ago   Up About a minute (healthy)       

mcp logs tail:
mcp-1  | /usr/local/lib/python3.12/site-packages/fastmcp/server/auth/providers/jwt.py:10: AuthlibDeprecationWarning: authlib.jose module is deprecated, please use joserfc instead.
mcp-1  | It will be compatible before version 2.0.0.
mcp-1  |   from authlib.jose import JsonWebKey, JsonWebToken
mcp-1  | [07/13/26 15:43:48] INFO     Starting MCP server                  server.py:2580
mcp-1  |                              'neo4j-agent-memory' with transport                
mcp-1  |                              'http' on http://0.0.0.0:8080/mcp                  
mcp-1  | INFO:     Started server process [1]
mcp-1  | INFO:     Waiting for application startup.
mcp-1  | INFO:     Application startup complete.
mcp-1  | INFO:     Uvicorn running on http://0.0.0.0:8080 (Press CTRL+C to quit)
<shellId: compose-restart-mcp completed with exit code 0>
```

#### Happy-path peer reachability and exact list_tools check

Command:

```sh
printf 'mcp bridge happy-path probes:\n' && \
docker compose -p mcp-image-up-impl -f docker-compose.yml -f docs/spec-loop-runs/mcp-image-up/compose.impl.override.yml exec -T mcp python - <<'PY'
import socket
for host, port in [('neo4j', 7687), ('llm-proxy', 4000)]:
    with socket.create_connection((host, port), timeout=5):
        print(f'connect {host}:{port} OK')
PY
printf '\nlist_tools exact-set check:\n' && \
docker compose -p mcp-image-up-impl -f docker-compose.yml -f docs/spec-loop-runs/mcp-image-up/compose.impl.override.yml exec -T mcp python - <<'PY'
import asyncio
from fastmcp import Client
expected = sorted([
    'memory_search', 'memory_get_context', 'memory_store_message', 'memory_add_entity',
    'memory_add_preference', 'memory_add_fact', 'memory_get_conversation', 'memory_list_sessions',
    'memory_get_entity', 'memory_export_graph', 'memory_create_relationship', 'memory_start_trace',
    'memory_record_step', 'memory_complete_trace', 'memory_get_observations', 'graph_query',
])
async def main():
    async with Client('http://127.0.0.1:8080/mcp') as client:
        tools = await client.list_tools()
    names = sorted(t.name for t in tools)
    print('returned_names=', names)
    print('expected_names=', expected)
    print('exact_match=', names == expected)
    assert names == expected
asyncio.run(main())
PY
```

Output:

```text
mcp bridge happy-path probes:
connect neo4j:7687 OK
connect llm-proxy:4000 OK

list_tools exact-set check:
/usr/local/lib/python3.12/site-packages/fastmcp/server/auth/providers/jwt.py:10: AuthlibDeprecationWarning: authlib.jose module is deprecated, please use joserfc instead.
It will be compatible before version 2.0.0.
  from authlib.jose import JsonWebKey, JsonWebToken
returned_names= ['graph_query', 'memory_add_entity', 'memory_add_fact', 'memory_add_preference', 'memory_complete_trace', 'memory_create_relationship', 'memory_export_graph', 'memory_get_context', 'memory_get_conversation', 'memory_get_entity', 'memory_get_observations', 'memory_list_sessions', 'memory_record_step', 'memory_search', 'memory_start_trace', 'memory_store_message']
expected_names= ['graph_query', 'memory_add_entity', 'memory_add_fact', 'memory_add_preference', 'memory_complete_trace', 'memory_create_relationship', 'memory_export_graph', 'memory_get_context', 'memory_get_conversation', 'memory_get_entity', 'memory_get_observations', 'memory_list_sessions', 'memory_record_step', 'memory_search', 'memory_start_trace', 'memory_store_message']
exact_match= True
```

#### Missing-network failure probes

Command:

```sh
printf 'missing-network failure probes:\n' && \
printf 'only db-net -> llm-proxy:4000\n' && \
docker run --rm --network mcp-image-up-impl_db-net --entrypoint python mcp-n4j-memory:mcp-image-up-impl -c "import socket; socket.create_connection(('llm-proxy',4000), timeout=3)" 2>&1; printf 'only_db_to_llm_exit=%s\n' "$?" && \
printf 'only llm-net -> neo4j:7687\n' && \
docker run --rm --network mcp-image-up-impl_llm-net --entrypoint python mcp-n4j-memory:mcp-image-up-impl -c "import socket; socket.create_connection(('neo4j',7687), timeout=3)" 2>&1; printf 'only_llm_to_neo4j_exit=%s\n' "$?"
```

Output:

```text
missing-network failure probes:
only db-net -> llm-proxy:4000
Traceback (most recent call last):
  File "<string>", line 1, in <module>
  File "/usr/local/lib/python3.12/socket.py", line 841, in create_connection
    for res in getaddrinfo(host, port, 0, SOCK_STREAM):
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/socket.py", line 978, in getaddrinfo
    for res in _socket.getaddrinfo(host, port, family, type, proto, flags):
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
socket.gaierror: [Errno -3] Temporary failure in name resolution
exit status 1
only_db_to_llm_exit=1
only llm-net -> neo4j:7687
Traceback (most recent call last):
  File "<string>", line 1, in <module>
  File "/usr/local/lib/python3.12/socket.py", line 841, in create_connection
    for res in getaddrinfo(host, port, 0, SOCK_STREAM):
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/socket.py", line 978, in getaddrinfo
    for res in _socket.getaddrinfo(host, port, family, type, proto, flags):
               ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
socket.gaierror: [Errno -3] Temporary failure in name resolution
exit status 1
only_llm_to_neo4j_exit=1
<shellId: r2-probes completed with exit code 0>
```

#### Wrong-profile failure behaviour

Command:

```sh
docker rm -f mcp-image-up-impl-core >/dev/null 2>&1 || true && \
docker run -d --name mcp-image-up-impl-core --network mcp-image-up-impl_db-net \
  -e NEO4J_URI=bolt://neo4j:7687 -e NEO4J_USER=neo4j -e NEO4J_PASSWORD=change-me -e NEO4J_DATABASE=neo4j \
  -e NAM_LLM__PROVIDER=openai -e NAM_LLM__MODEL=claude -e NAM_LLM__API_KEY=change-me \
  -e NAM_EMBEDDING__PROVIDER=sentence_transformers -e NAM_EMBEDDING__MODEL=BAAI/bge-small-en-v1.5 -e NAM_EMBEDDING__DIMENSIONS=384 \
  mcp-n4j-memory:mcp-image-up-impl --transport http --host 0.0.0.0 --port 8081 --profile core && \
sleep 8 && docker logs --tail=20 mcp-image-up-impl-core && \
docker exec -i mcp-image-up-impl-core python - <<'PY'
import asyncio
from fastmcp import Client
extended = sorted([
    'memory_search', 'memory_get_context', 'memory_store_message', 'memory_add_entity',
    'memory_add_preference', 'memory_add_fact', 'memory_get_conversation', 'memory_list_sessions',
    'memory_get_entity', 'memory_export_graph', 'memory_create_relationship', 'memory_start_trace',
    'memory_record_step', 'memory_complete_trace', 'memory_get_observations', 'graph_query',
])
async def main():
    async with Client('http://127.0.0.1:8081/mcp') as client:
        tools = await client.list_tools()
    names = sorted(t.name for t in tools)
    print('core_profile_names=', names)
    print('extended_expected_names=', extended)
    print('exact_match=', names == extended)
    assert names == extended
asyncio.run(main())
PY
printf 'core_profile_extended_assert_exit=%s\n' "$?"; docker rm -f mcp-image-up-impl-core >/dev/null 2>&1 || true
```

Output:

```text
wrong-profile core list_tools failure-path check:
1c711b3c53c5cbfe59065a512d4d3d02450e6eadb95be017b40a0f6de99f5a32
│                                FastMCP 2.14.7                                │
│                            https://gofastmcp.com                             │
│                                                                              │
│                    🖥  Server:      neo4j-agent-memory                        │
│                    🚀 Deploy free: https://fastmcp.cloud                     │
│                                                                              │
╰──────────────────────────────────────────────────────────────────────────────╯
╭──────────────────────────────────────────────────────────────────────────────╮
│                          ✨ FastMCP 3.0 is coming!                           │
│       Pin `fastmcp < 3` in production, then upgrade when you're ready.       │
╰──────────────────────────────────────────────────────────────────────────────╯


[07/13/26 15:44:27] INFO     Starting MCP server                  server.py:2580
                             'neo4j-agent-memory' with transport                
                             'http' on http://0.0.0.0:8081/mcp                  
INFO:     Started server process [1]
INFO:     Waiting for application startup.
INFO:     Application startup complete.
INFO:     Uvicorn running on http://0.0.0.0:8081 (Press CTRL+C to quit)
/usr/local/lib/python3.12/site-packages/fastmcp/server/auth/providers/jwt.py:10: AuthlibDeprecationWarning: authlib.jose module is deprecated, please use joserfc instead.
It will be compatible before version 2.0.0.
  from authlib.jose import JsonWebKey, JsonWebToken
core_profile_names= ['memory_add_entity', 'memory_add_fact', 'memory_add_preference', 'memory_get_context', 'memory_search', 'memory_store_message']
extended_expected_names= ['graph_query', 'memory_add_entity', 'memory_add_fact', 'memory_add_preference', 'memory_complete_trace', 'memory_create_relationship', 'memory_export_graph', 'memory_get_context', 'memory_get_conversation', 'memory_get_entity', 'memory_get_observations', 'memory_list_sessions', 'memory_record_step', 'memory_search', 'memory_start_trace', 'memory_store_message']
exact_match= False
Traceback (most recent call last):
  File "<stdin>", line 17, in <module>
  File "/usr/local/lib/python3.12/asyncio/runners.py", line 195, in run
    return runner.run(main)
           ^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/asyncio/runners.py", line 118, in run
    return self._loop.run_until_complete(task)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/asyncio/base_events.py", line 691, in run_until_complete
    return future.result()
           ^^^^^^^^^^^^^^^
  File "<stdin>", line 16, in main
AssertionError
exit status 1
core_profile_extended_assert_exit=1
<shellId: r2-core-fail completed with exit code 0>
```

### R3 — The local embedder is baked and works offline with a 384-dimensional vector

#### Offline happy path and missing-model failure path

Command:

```sh
printf 'offline embedder happy path:\n' && \
docker run -i --rm --network none --entrypoint python -e HF_HUB_OFFLINE=1 -e TRANSFORMERS_OFFLINE=1 mcp-n4j-memory:mcp-image-up-impl - <<'PY'
from sentence_transformers import SentenceTransformer
model = SentenceTransformer('BAAI/bge-small-en-v1.5', local_files_only=True)
vec = model.encode('mcp image offline embedding probe')
print('vector_length=', len(vec))
assert len(vec) == 384
PY
printf 'happy_exit=%s\n' "$?" && \
printf '\noffline missing-model failure path:\n' && \
docker run -i --rm --network none --entrypoint python -e HF_HUB_OFFLINE=1 -e TRANSFORMERS_OFFLINE=1 mcp-n4j-memory:mcp-image-up-impl - <<'PY'
from sentence_transformers import SentenceTransformer
SentenceTransformer('BAAI/definitely-missing-local-model-for-spec-loop', local_files_only=True)
PY
printf 'missing_model_exit=%s\n' "$?"
```

Output:

```text
offline embedder happy path:

Loading weights:   0%|          | 0/199 [00:00<?, ?it/s]
Loading weights:  78%|███████▊  | 155/199 [00:00<00:00, 1543.51it/s]
Loading weights: 100%|██████████| 199/199 [00:00<00:00, 1877.69it/s]
vector_length= 384
happy_exit=0

offline missing-model failure path:
Traceback (most recent call last):
  File "/usr/local/lib/python3.12/site-packages/transformers/utils/hub.py", line 437, in cached_files
    hf_hub_download(
  File "/usr/local/lib/python3.12/site-packages/huggingface_hub/utils/_validators.py", line 88, in _inner_fn
    return fn(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/huggingface_hub/file_download.py", line 1013, in hf_hub_download
    return _hf_hub_download_to_cache_dir(
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/huggingface_hub/file_download.py", line 1165, in _hf_hub_download_to_cache_dir
    _raise_on_head_call_error(head_call_error, force_download, local_files_only)
  File "/usr/local/lib/python3.12/site-packages/huggingface_hub/file_download.py", line 1855, in _raise_on_head_call_error
    raise LocalEntryNotFoundError(
huggingface_hub.errors.LocalEntryNotFoundError: Cannot find the requested files in the disk cache and outgoing traffic has been disabled. To enable hf.co look-ups and downloads online, set 'local_files_only' to False.

The above exception was the direct cause of the following exception:

Traceback (most recent call last):
  File "<stdin>", line 2, in <module>
  File "/usr/local/lib/python3.12/site-packages/sentence_transformers/util/decorators.py", line 41, in wrapper
    return func(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sentence_transformers/sentence_transformer/model.py", line 188, in __init__
    super().__init__(
  File "/usr/local/lib/python3.12/site-packages/sentence_transformers/base/model.py", line 216, in __init__
    modules, self.module_kwargs = self._load_modules(
                                  ^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sentence_transformers/base/model.py", line 991, in _load_modules
    return self._load_default_modules(model_name_or_path, **load_kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sentence_transformers/sentence_transformer/model.py", line 1066, in _load_default_modules
    transformer_model = Transformer(
                        ^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sentence_transformers/util/decorators.py", line 87, in wrapper
    return func(*args, **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sentence_transformers/base/modules/transformer.py", line 639, in __init__
    config, is_peft_model = self._load_config(model_name_or_path, backend, config_kwargs)
                            ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/sentence_transformers/base/modules/transformer.py", line 1671, in _load_config
    return AutoConfig.from_pretrained(model_name_or_path, **config_kwargs), False
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/transformers/models/auto/configuration_auto.py", line 376, in from_pretrained
    config_dict, unused_kwargs = PreTrainedConfig.get_config_dict(pretrained_model_name_or_path, **kwargs)
                                 ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/transformers/configuration_utils.py", line 711, in get_config_dict
    config_dict, kwargs = cls._get_config_dict(pretrained_model_name_or_path, **kwargs)
                          ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/transformers/configuration_utils.py", line 766, in _get_config_dict
    resolved_config_file = cached_file(
                           ^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/transformers/utils/hub.py", line 293, in cached_file
    file = cached_files(path_or_repo_id=path_or_repo_id, filenames=[filename], **kwargs)
           ^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/local/lib/python3.12/site-packages/transformers/utils/hub.py", line 513, in cached_files
    raise OSError(
OSError: We couldn't connect to 'https://huggingface.co' to load the files, and couldn't find them in the cached files.
Check your internet connection or see how to run the library in offline mode at 'https://huggingface.co/docs/transformers/installation#offline-mode'.
exit status 1
missing_model_exit=1
<shellId: r3-checks-stdin completed with exit code 0>
```

### Cleanup evidence

Command:

```sh
docker compose -p mcp-image-up-impl -f docker-compose.yml -f docs/spec-loop-runs/mcp-image-up/compose.impl.override.yml down -v && \
rm -f docs/spec-loop-runs/mcp-image-up/compose.impl.override.yml && \
docker image inspect mcp-n4j-memory:mcp-image-up-impl --format 'kept_image={{.RepoTags}} id={{.Id}}'
```

Output:

```text
 Container mcp-image-up-impl-mcp-1  Stopping
 Container mcp-image-up-impl-mcp-1  Stopped
 Container mcp-image-up-impl-mcp-1  Removing
 Container mcp-image-up-impl-mcp-1  Removed
 Container mcp-image-up-impl-llm-proxy-1  Stopping
 Container mcp-image-up-impl-neo4j-1  Stopping
 Container mcp-image-up-impl-llm-proxy-1  Stopped
 Container mcp-image-up-impl-llm-proxy-1  Removing
 Container mcp-image-up-impl-llm-proxy-1  Removed
 Container mcp-image-up-impl-neo4j-1  Stopped
 Container mcp-image-up-impl-neo4j-1  Removing
 Container mcp-image-up-impl-neo4j-1  Removed
 Volume mcp-image-up-impl_neo4j-data  Removing
 Network mcp-image-up-impl_db-net  Removing
 Network mcp-image-up-impl_llm-net  Removing
 Volume mcp-image-up-impl_neo4j-data  Removed
 Network mcp-image-up-impl_llm-net  Removed
 Network mcp-image-up-impl_db-net  Removed
kept_image=[mcp-n4j-memory:mcp-image-up-impl] id=sha256:effa27a23cb7f191588e9a02aa197a20c2212c88671e91b27dbc5119e1d41a5b
<shellId: cleanup completed with exit code 0>
```

## Blocking spec defects

None.
