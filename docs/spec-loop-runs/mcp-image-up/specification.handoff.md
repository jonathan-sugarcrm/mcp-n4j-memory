# Slice

`mcp-image-up` — make the `mcp` image buildable/startable with the real `neo4j-agent-memory mcp serve` CLI, then runtime-verify the non-LLM criteria that require the `mcp` image: MCP-to-peer reachability, the 16-tool extended surface, MCP bridge membership, and offline local embeddings.

# Normalized requirements

## Requirement 1 — Built image uses the real framework MCP CLI and accepted serve options

- **Trigger:** Build the `mcp` image from `docker/mcp.Dockerfile`, then inspect/run the image CLI.
- **Preconditions:** The image consumes `neo4j-agent-memory==0.2.0`; no real `ANTHROPIC_API_KEY` is required for this requirement; any command/default flags used to start the image must be accepted by `neo4j-agent-memory mcp serve --help`.
- **Expected observable outcome:**
  - `docker build -f docker/mcp.Dockerfile -t <mcp-image> .` completes.
  - The built image's configured entrypoint invokes the real console script path `neo4j-agent-memory mcp serve` rather than a nonexistent `mcp` console script.
  - `docker run --rm --entrypoint neo4j-agent-memory <mcp-image> mcp serve --help` exits 0 and shows the accepted options for the installed wheel.
  - Starting the image does not fail due to unsupported serve flags.
- **Failure behaviour:** If the console script or a serve option is wrong, the CLI exits non-zero (for example, executable not found or `No such option`) and the image is not accepted as runnable.
- **Verification method:** Build the image, inspect `.Config.Entrypoint`, run `neo4j-agent-memory mcp serve --help` inside the image, and run the image/compose service far enough to prove Click does not reject its startup flags.
- **Traces to:** G1, C2, C7; spec §3.3 says the owned `mcp` image launches `neo4j-agent-memory mcp serve` and bakes the embedding model (docs/SPECIFICATION.md:113-117); §10 records the current ENTRYPOINT defect and required console-script invocation (docs/SPECIFICATION.md:394-399).

## Requirement 2 — Running `mcp` reaches both peers and exposes exactly the extended tool set

- **Trigger:** Bring up the compose stack using the built `mcp` image, then run reachability probes from inside the `mcp` container and an MCP `list_tools` call against the running server.
- **Preconditions:**
  - `neo4j` is running on `db-net`; `llm-proxy` is running/listening on `llm-net` with placeholder secrets acceptable because no LLM call is made.
  - `mcp` is attached to both `db-net` and `llm-net` and starts with `--profile extended`.
  - Because host port 8080 is occupied in the current environment, verification must avoid publishing 8080 or override it to an alternate host port; probes may run from inside containers.
  - The previously verified `neo4j`↔`llm-proxy` isolation half of AC-G4 remains the companion evidence; this slice verifies only the `mcp` bridge half.
- **Expected observable outcome:**
  - From inside `mcp`, TCP connect to `neo4j:7687` succeeds.
  - From inside `mcp`, TCP/HTTP connect to `llm-proxy:4000` succeeds.
  - An MCP client `list_tools` call returns exactly these 16 names, with no missing, renamed, or extra tools: `memory_search`, `memory_get_context`, `memory_store_message`, `memory_add_entity`, `memory_add_preference`, `memory_add_fact`, `memory_get_conversation`, `memory_list_sessions`, `memory_get_entity`, `memory_export_graph`, `memory_create_relationship`, `memory_start_trace`, `memory_record_step`, `memory_complete_trace`, `memory_get_observations`, `graph_query`.
- **Failure behaviour:** If `mcp` is missing either network, the corresponding peer probe fails; if the wrong profile/options are used, `list_tools` returns fewer/different tools and the check fails.
- **Verification method:** With the stack running, execute deterministic in-container connect probes from `mcp` to `neo4j:7687` and `llm-proxy:4000`, then use a real MCP client (for FastMCP HTTP, `fastmcp.Client("http://<host>:<port>/mcp")`) to call `list_tools()` and compare the sorted returned names to the exact 16-name set above.
- **Traces to:** AC-C3 / C3 (docs/SPECIFICATION.md:260-267), AC-G1 / G1 (docs/SPECIFICATION.md:319-327), AC-G4 / G4 mcp-bridge half (docs/SPECIFICATION.md:349-358), and the §3.2 tool list (docs/SPECIFICATION.md:100-106).

## Requirement 3 — The local embedder is baked and works offline with a 384-dimensional vector

- **Trigger:** Start/run the built `mcp` image with outbound egress blocked and load the configured local sentence-transformers model.
- **Preconditions:** The image contains the dependencies and cached model files needed for `BAAI/bge-small-en-v1.5`; runtime is configured to use the sentence-transformers/local embedder, not an external embedding provider; the verification command blocks egress and sets offline mode (for example `HF_HUB_OFFLINE=1` / `TRANSFORMERS_OFFLINE=1`).
- **Expected observable outcome:** Inside the egress-blocked container, loading `BAAI/bge-small-en-v1.5` from local files succeeds and embedding a probe string returns a vector with length exactly `384`.
- **Failure behaviour:** If the model or dependency is absent, or if loading tries to download, the offline load/embedding command exits non-zero and the criterion fails closed.
- **Verification method:** Run the built image with network disabled/egress blocked and execute a Python probe that imports the framework's sentence-transformers embedder (or `sentence_transformers.SentenceTransformer` against the baked cache), loads `BAAI/bge-small-en-v1.5` in offline mode, embeds a fixed string, and asserts `len(vector) == 384`.
- **Traces to:** AC-C7 / C7 (docs/SPECIFICATION.md:306-315), G5 local/offline embedder goal (docs/SPECIFICATION.md:43-44), and §3.1's baked offline model statement (docs/SPECIFICATION.md:96-98).

# Verification criteria

- **R1 image/CLI check:** `docker build -f docker/mcp.Dockerfile -t <mcp-image> .` succeeds; `docker image inspect <mcp-image>` shows entrypoint beginning `neo4j-agent-memory mcp serve`; `docker run --rm --entrypoint neo4j-agent-memory <mcp-image> mcp serve --help` exits 0; the service startup command uses only options accepted by that help output.
- **R2 reachability/tools check:** Start the stack without binding host `8080` (or bind MCP to an alternate host port). From `mcp`, assert connects to `neo4j:7687` and `llm-proxy:4000` both succeed. Then run an MCP `list_tools` client call against the running transport and assert the returned sorted tool names equal the 16-name set in Requirement 2 exactly.
- **R3 offline embedder check:** Run the built image with egress blocked/offline env set and assert a local load of `BAAI/bge-small-en-v1.5` produces an embedding vector whose length is `384`; no network access is permitted during this runtime check.

# Explicit scope

## In scope

- Fixing `docker/mcp.Dockerfile` so the built image's ENTRYPOINT uses `neo4j-agent-memory mcp serve`.
- Correcting any `mcp serve` startup flags/env wiring that are proven incompatible with `neo4j-agent-memory==0.2.0`, so the service can start for non-LLM checks.
- Ensuring the image installs the dependencies needed to bake/load `BAAI/bge-small-en-v1.5` locally and offline.
- Running non-LLM runtime checks for AC-C3, AC-G1, AC-G4's `mcp`-bridge half, and AC-C7.
- Avoiding or overriding the occupied host port `8080` during verification.

## Out of scope

- AC-C6, AC-G3, and any LLM-triggering portions of AC-G2/AC-G5 that require a real `ANTHROPIC_API_KEY`.
- Re-verifying the already-covered `neo4j`↔`llm-proxy` negative isolation half of AC-G4, except as referenced companion evidence.
- Implementing custom memory logic, custom Cypher memory operations, or changing the framework's MCP tool implementations.
- Editing `docs/SPECIFICATION.md` in this stage.
- Changing LiteLLM's real Anthropic model choice beyond what is necessary to keep placeholder/non-LLM startup checks running.

# Unresolved decisions

None — cleared at gate 2.

# Recorded facts & safe choices

## Class 2 facts — investigated technical facts

- The installed wheel exposes console script `neo4j-agent-memory = neo4j_agent_memory.cli:main`; there is no `mcp` console script. Citation: `neo4j-agent-memory==0.2.0` wheel `neo4j_agent_memory-0.2.0.dist-info/entry_points.txt`, confirmed by Gate-2 wheel inspection; spec §10 records the same defect (docs/SPECIFICATION.md:394-399).
- The real serve subcommand path is `neo4j-agent-memory mcp serve`. `neo4j-agent-memory --help` lists the `mcp` command, and `neo4j-agent-memory mcp serve --help` exits 0. Citation: Gate-2 command `PYTHONPATH=.spec-loop-work/site .spec-loop-work/site/bin/neo4j-agent-memory mcp serve --help`.
- Accepted `mcp serve` options in `neo4j-agent-memory==0.2.0` are: `--uri`, `--user`, `--password`, `--database`, `--transport [stdio|sse|http]`, `--host`, `--port`, `--profile [core|extended]`, `--session-strategy [per_conversation|per_day|persistent]`, `--user-id`, `--observation-threshold`, and `--no-auto-preferences`. Citation: wheel source `neo4j_agent_memory/cli/main.py` lines 690-760 from Gate-2 inspection and installed CLI help output.
- The current Dockerfile CMD includes unsupported options for this wheel: `--backend`, `--llm`, `--llm-api-base`, and `--embedding`; those names do not appear in `mcp serve --help`, so the service would fail if startup reaches Click parsing. Citation: current Dockerfile (docker/mcp.Dockerfile:29-37) compared with the Gate-2 CLI help fact above.
- `NEO4J_URI`, `NEO4J_USER`, `NEO4J_PASSWORD`, and `NEO4J_DATABASE` are read directly by `mcp serve` Click options; `MCP_USER_ID` is also read for `--user-id`. Citation: wheel source `neo4j_agent_memory/cli/main.py` lines 690-748 from Gate-2 inspection.
- `MCP_TRANSPORT`, `MCP_HOST`, and `MCP_PORT` are not Click env vars for the `neo4j-agent-memory mcp serve` command; transport/host/port must be passed as flags unless another wrapper maps those env vars. Citation: wheel source `neo4j_agent_memory/cli/main.py` lines 714-729 from Gate-2 inspection; current compose sets those env vars at docker-compose.yml:46-48.
- `MemorySettings` uses env prefix `NAM_` with nested delimiter `__`; flat `NAM_EMBEDDING=BAAI/bge-small-en-v1.5` is parsed as the complex `embedding` field and errors in the package config loader, while `NAM_EMBEDDING__PROVIDER=sentence_transformers`, `NAM_EMBEDDING__MODEL=BAAI/bge-small-en-v1.5`, and `NAM_EMBEDDING__DIMENSIONS=384` load as intended. Citation: wheel source `neo4j_agent_memory/config/settings.py` lines 490-505 and Gate-2 config-loader probe; current compose/env use flat `NAM_EMBEDDING` at docker-compose.yml:45 and .env.example:13.
- The wheel's `mcp serve` path constructs `MemorySettings` and exposes FastMCP transports `stdio`, `sse`, and `http`; FastMCP's default streamable HTTP path is `/mcp`, while SSE path is `/sse`. Citation: wheel source `neo4j_agent_memory/mcp/server.py` lines 205-266 from Gate-2 inspection; FastMCP 2.14.7 settings probe showed `streamable_http_path=/mcp`, `sse_path=/sse`.
- A FastMCP client can mechanically list tools with `fastmcp.Client("http://<host>:<port>/mcp")` and `await client.list_tools()` for the `http` transport. Citation: Gate-2 inspection of FastMCP 2.14.7 `Client` signature and `Client.list_tools()` implementation.
- The framework's extended profile registers exactly the same 16 tool function names as spec §3.2. Citation: wheel source `neo4j_agent_memory/mcp/_tools.py` function definitions from Gate-2 inspection and spec tool list (docs/SPECIFICATION.md:100-106).
- `BAAI/bge-small-en-v1.5` has hidden size `384`, matching the expected embedding dimension. Citation: Hugging Face model config `https://huggingface.co/BAAI/bge-small-en-v1.5/raw/main/config.json` returned `"hidden_size": 384` during Gate-2 investigation.
- Current `docker/mcp.Dockerfile` installs only `neo4j-agent-memory[mcp]==0.2.0`, but that extra does not include `sentence-transformers`; the `sentence-transformers` dependency is provided by the wheel's `sentence-transformers` or `full` extras. Citation: Dockerfile install line (docker/mcp.Dockerfile:10-16) and wheel `METADATA` `Provides-Extra: mcp` / `Provides-Extra: sentence-transformers` from Gate-2 inspection.
- A probe build of the current image reaches the bake step and fails with `ModuleNotFoundError: No module named 'sentence_transformers'`. Citation: Gate-2 command `docker build --progress=plain -f docker/mcp.Dockerfile -t mcp-n4j-memory:mcp-image-up-probe .` output at Dockerfile line 16.
- Docker daemon and compose are available in the current environment (`ServerVersion=28.0.0`, compose `2.33.0`). Citation: Gate-2 `docker info` / `docker compose version` probe.
- Host port 8080 is occupied by an unrelated `graphmind-mcp` container mapping `127.0.0.1:8080->8080/tcp`, so this slice's verification must not require publishing host 8080. Citation: Gate-2 `docker ps --format '{{.Names}} {{.Ports}}'` probe.
- No real `ANTHROPIC_API_KEY` is present in this agent environment, and the in-scope checks do not require one because they do not trigger an LLM call. Citation: Gate-2 environment probe and spec §10 LLM blocker note (docs/SPECIFICATION.md:400-403).

## Class 3 safe choices — recorded rationale

- Chose to verify AC-G1 via FastMCP's Python client rather than raw JSON-RPC/curl because it is a reversible test-harness choice with no product contract impact and uses the server's installed transport library directly.
- Chose to avoid/override host port 8080 during verification rather than stopping `graphmind-mcp` because this is a reversible environment accommodation and avoids disturbing an unrelated container.
- Recommended decomposition if Stage 2 cannot finish a single verified pass: first fix/build the `mcp` image and prove R1+R3, then run compose reachability/list_tools for R2. This is a process decomposition only; it does not change product behaviour or acceptance criteria, and is justified by the current build failure plus heavyweight torch/sentence-transformers/model bake cost.
