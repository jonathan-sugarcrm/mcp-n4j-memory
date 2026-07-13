# Self-report: docker-compose thin delta

## (a) What I implemented

Implemented `docs/spec-loop-runs/docker-compose/run-a-single/docker-compose.yml` with the three spec-owned services:

- `neo4j`: official `neo4j:5-community`, `NEO4J_PLUGINS=["apoc"]`, local host ports `7474`/`7687`, named `neo4j-data` volume mounted at `/data`, only on `db-net`, bolt healthcheck.
- `llm-proxy`: LiteLLM image, mounts `litellm/config.yaml`, receives only `LITELLM_MASTER_KEY` and `ANTHROPIC_API_KEY`, optional local host port `4000`, only on `llm-net`.
- `mcp`: builds from `docker/mcp.Dockerfile`, receives Neo4j/LiteLLM/framework env, publishes local host port `8080`, depends on healthy Neo4j and started LiteLLM, attached to both `db-net` and `llm-net`.

Also declared the two segmented networks (`db-net`, `llm-net`) with `internal: true` and the named Neo4j volume (`neo4j-data`).

## (b) How I verified it

I did not bring the stack up or pull images. I verified statically with:

```sh
NEO4J_PASSWORD=change-me LITELLM_MASTER_KEY=change-me ANTHROPIC_API_KEY=change-me \
  docker compose -f docs/spec-loop-runs/docker-compose/run-a-single/docker-compose.yml config
```

This rendered successfully. I also ran a JSON assertion over `docker compose config --format json` confirming:

- exactly `neo4j`, `llm-proxy`, and `mcp` services exist;
- `neo4j` is only on `db-net`, `llm-proxy` only on `llm-net`, and `mcp` on both;
- both networks are `internal: true`;
- `neo4j-data` exists and is mounted to `/data`;
- `mcp` uses `bolt://neo4j:7687`, `openai/claude`, and has no `ANTHROPIC_API_KEY`;
- `ANTHROPIC_API_KEY` exists only in `llm-proxy`;
- published ports are the local-dev allow-list on `127.0.0.1`: 7474, 7687, 4000, 8080.

I also parsed `litellm/config.yaml` and confirmed it declares one Anthropic-backed model and reads keys from env.

## (c) PASS/FAIL judgement against relevant §9 ACs

Overall judgement for this compose-authoring slice: **PASS**, with runtime-only criteria explicitly not fully exercised because the task forbids stack startup.

- **AC-C1:** Static compose preconditions satisfied: local Neo4j service, non-remote bolt URI, named data volume. Runtime restart persistence not exercised.
- **AC-C2:** Static satisfied: exactly the three compose services are defined. Runtime `ps` not exercised.
- **AC-C3:** Static satisfied: `mcp` is attached to both required networks. Runtime reachability not exercised.
- **AC-C4:** Static satisfied: only documented local-dev ports are published, bound to `127.0.0.1`; both networks are internal.
- **AC-C5:** Static satisfied: `neo4j` and `llm-proxy` share no network. Runtime negative reachability not exercised.
- **AC-C6:** Static satisfied: LiteLLM has one Anthropic-backed model; `mcp` targets the proxy via existing Dockerfile command/env and has no Anthropic key. Runtime LLM call/log check not exercised.
- **AC-C7:** Static preconditions satisfied by the existing `docker/mcp.Dockerfile` and compose `NAM_EMBEDDING`; offline model load not exercised.
- **AC-G1:** Static precondition satisfied via existing Dockerfile `--profile extended`; runtime `list_tools` not exercised.
- **AC-G2:** Static preconditions satisfied via bolt backend/Neo4j wiring; runtime memory persistence not exercised.
- **AC-G3:** Static proxy-routing preconditions satisfied; runtime proxy log check not exercised.
- **AC-G4:** Static satisfied: only `mcp` bridges `db-net` and `llm-net`; DB and proxy share no network.
- **AC-G5:** Static embedding preconditions satisfied; runtime semantic vector search not exercised.
- **AC-G6:** Satisfied for this slice: the change is declarative compose only, plus this required self-report; no memory-engine code was added.

## (d) Assumptions

- Because the requested output path is under `docs/spec-loop-runs/...`, relative compose paths intentionally climb four directories to the repository root for the MCP build context and LiteLLM config bind mount.
- I treated `llm-proxy` port `4000` as the optional local-dev mapping allowed by §3.1/§8/AC-C4.
- I used required interpolation for secret-like values and supplied dummy values only for static validation.
- I prioritized the spec's static compose-slice assertion that both segmented networks are `internal: true`; runtime egress behavior is left to the future stack-up slice identified in §9.
