# Self-report: docker-compose thin delta (Run A — single agent, repeat)

Single uninterrupted pass: one context interpreted the `docker-compose` slice
(`docs/SPECIFICATION.md` §3.3 / §4 / §7 / §8 / §9), authored the compose file, and
self-judged pass/fail. Spec used exactly as-is.

## (a) What I implemented

`docs/spec-loop-runs/docker-compose/run-a-single/docker-compose.yml` with the three
spec-owned services:

- `neo4j`: official `neo4j:5-community`, `NEO4J_PLUGINS=["apoc"]`, local host ports
  `7474`/`7687` bound to `127.0.0.1`, named `neo4j-data` volume mounted at `/data`, only on
  `db-net`, bolt healthcheck.
- `llm-proxy`: LiteLLM image, mounts `litellm/config.yaml`, receives only
  `LITELLM_MASTER_KEY` and `ANTHROPIC_API_KEY`, optional local host port `4000`, only on
  `llm-net`.
- `mcp`: builds from `docker/mcp.Dockerfile`, receives Neo4j/LiteLLM/framework env,
  publishes local host port `8080`, depends on healthy Neo4j and started LiteLLM, attached
  to both `db-net` and `llm-net`. `--llm-api-base http://llm-proxy:4000/v1` is inherited
  from the Dockerfile `CMD`, not duplicated in compose.

Also declared the two segmented networks (`db-net`, `llm-net`) with `internal: true` and
the named Neo4j volume (`neo4j-data`).

## (b) How I verified it

I did not bring the stack up or pull images (out of scope for this slice). I verified
statically. **Documented verification command** (from repository root):

```sh
NEO4J_PASSWORD=change-me LITELLM_MASTER_KEY=change-me ANTHROPIC_API_KEY=change-me \
  docker compose -f docs/spec-loop-runs/docker-compose/run-a-single/docker-compose.yml config
```

This rendered successfully (exit 0). I also ran a JSON assertion over
`docker compose config --format json` confirming:

- exactly `neo4j`, `llm-proxy`, and `mcp` services exist;
- `neo4j` is only on `db-net`, `llm-proxy` only on `llm-net`, and `mcp` on both;
- both networks are `internal: true`;
- `neo4j-data` exists and is mounted to `/data`;
- `mcp` uses `bolt://neo4j:7687`, `openai/claude`, and has no `ANTHROPIC_API_KEY`;
- `ANTHROPIC_API_KEY` exists only in `llm-proxy`;
- published ports are the local-dev allow-list on `127.0.0.1`: 7474, 7687, 4000, 8080.

## (c) PASS/FAIL judgement against relevant §9 ACs

Overall judgement for this compose-authoring slice: **PASS**, with runtime-only criteria
explicitly not exercised because the task forbids stack startup.

- **AC-C1:** Static preconditions satisfied: local Neo4j, non-remote bolt URI, named data
  volume. Runtime restart persistence not exercised.
- **AC-C2:** Static satisfied: exactly the three compose services are defined. Runtime `ps`
  not exercised.
- **AC-C3:** Static satisfied: `mcp` attached to both required networks. Runtime
  reachability not exercised.
- **AC-C4:** Static satisfied: only documented local-dev ports published, bound to
  `127.0.0.1`; both networks internal.
- **AC-C5:** Static satisfied: `neo4j` and `llm-proxy` share no network. Runtime negative
  reachability not exercised.
- **AC-C6:** Static satisfied: LiteLLM has one Anthropic-backed model; `mcp` targets the
  proxy via existing Dockerfile command/env and has no Anthropic key. Runtime LLM call/log
  not exercised.
- **AC-C7:** Static preconditions satisfied via existing Dockerfile + compose
  `NAM_EMBEDDING`; offline model load not exercised.
- **AC-G1:** Static precondition satisfied via Dockerfile `--profile extended`; runtime
  `list_tools` not exercised.
- **AC-G2:** Static bolt/Neo4j wiring satisfied; runtime persistence not exercised.
- **AC-G3:** Static proxy-routing preconditions satisfied; runtime proxy log not exercised.
- **AC-G4:** Static satisfied: only `mcp` bridges `db-net` and `llm-net`.
- **AC-G5:** Static embedding preconditions satisfied; runtime vector search not exercised.
- **AC-G6:** Satisfied: declarative compose only, plus this self-report; no engine code
  added.

## (d) Assumptions

- Because the output path is under `docs/spec-loop-runs/...`, relative compose paths climb
  four directories to the repository root for the MCP build context and LiteLLM bind mount.
- Treated `llm-proxy` port `4000` as the optional local-dev mapping allowed by §7/§8/AC-C4.
- Used required interpolation (`${VAR:?...}`) for secret-like values and supplied dummy
  values only for static validation.
- Prioritized the static compose assertion that both segmented networks are
  `internal: true`; runtime egress behaviour left to the future `stack-up` slice (§9).
