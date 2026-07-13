# Slice

- **id:** `docker-compose`
- **Outcome:** Author `docker-compose.yml` so static compose rendering defines the local Neo4j, LiteLLM proxy, and MCP services with persistent Neo4j storage, segmented networks, approved local-dev ports, and correct env/secret wiring.

# Normalized requirements

## AC-DC1 — Compose declares the required service and persistence topology

- **Trigger:** `docker compose config --format json` is evaluated from the repository root.
- **Preconditions:** `docker-compose.yml`, `docker/mcp.Dockerfile`, `litellm/config.yaml`, and `.env.example` exist; `.env` values may be supplied by the operator before runtime.
- **Expected observable outcome:** The rendered compose config contains exactly the services `neo4j`, `llm-proxy`, and `mcp`; `neo4j` uses an official Neo4j image, declares `NEO4J_PLUGINS=["apoc"]`, has a healthcheck, and mounts a named volume to `/data`; `llm-proxy` uses a LiteLLM image and mounts `./litellm/config.yaml`; `mcp` builds from `docker/mcp.Dockerfile` and depends on `neo4j` and `llm-proxy`.
- **Failure behaviour:** If any required service, build/image, config mount, healthcheck, dependency, or Neo4j named data volume is absent or malformed, the static config assertion exits non-zero; runtime persistence proof remains unverified until the later `stack-up` slice.
- **Verification method:** Run the `AC-DC1` Python assertion in the verification criteria against `docker compose config --format json`.
- **Traces to:** G2, G6, C1, C2.

## AC-DC2 — Static network segmentation makes MCP the only bridge

- **Trigger:** `docker compose config --format json` is evaluated from the repository root.
- **Preconditions:** The compose file declares `db-net` and `llm-net` networks.
- **Expected observable outcome:** Both `db-net` and `llm-net` are rendered with `internal: true`; `neo4j` is attached only to `db-net`; `llm-proxy` is attached only to `llm-net`; `mcp` is attached to both networks and no other declared service bridges them.
- **Failure behaviour:** If `neo4j` and `llm-proxy` share any network, either network is not internal, or a service other than `mcp` bridges both networks, the static config assertion exits non-zero; reachability probes are deferred to the later `stack-up` slice.
- **Verification method:** Run the `AC-DC2` Python assertion in the verification criteria against `docker compose config --format json`.
- **Traces to:** G4, C3, C4, C5.

## AC-DC3 — Static port and LLM credential wiring matches the contract

- **Trigger:** `docker compose config --format json` is evaluated from the repository root.
- **Preconditions:** `.env.example` lists `NEO4J_*`, `NAM_LLM`, `NAM_LLM_API_KEY`, `NAM_EMBEDDING`, `MCP_*`, `LITELLM_MASTER_KEY`, and `ANTHROPIC_API_KEY`; `litellm/config.yaml` defines the proxy model.
- **Expected observable outcome:** Rendered published host ports are limited to Neo4j `7474`/`7687`, MCP `8080`, and optional LiteLLM `4000`; `mcp` receives Neo4j env, `NAM_LLM=openai/claude`, `NAM_LLM_API_KEY`, `NAM_EMBEDDING=BAAI/bge-small-en-v1.5`, and MCP transport env, but not `ANTHROPIC_API_KEY`; `llm-proxy` receives `LITELLM_MASTER_KEY` and `ANTHROPIC_API_KEY`; `neo4j` receives `NEO4J_AUTH` or equivalent password wiring; `mcp` command/entrypoint includes `--llm-api-base http://llm-proxy:4000/v1` unless inherited from the Dockerfile command.
- **Failure behaviour:** If an unapproved host port is published, `ANTHROPIC_API_KEY` is present in `mcp`, proxy credentials are missing from `llm-proxy`, or the MCP LLM base URL cannot be found in compose or the Dockerfile command, the static assertion exits non-zero; proxy log proof is deferred to the later `stack-up` slice.
- **Verification method:** Run the `AC-DC3` Python assertion in the verification criteria against `docker compose config --format json` plus `docker/mcp.Dockerfile`.
- **Traces to:** G3, C4, C6, compose-visible part of AC-C6.

# Verification criteria

## AC-DC1 mechanical check

```bash
docker compose config --format json | python3 -c '
import json, sys
c=json.load(sys.stdin); s=c.get("services",{}); assert set(s)=={"neo4j","llm-proxy","mcp"}, set(s)
assert "neo4j" in s["neo4j"].get("image","").lower()
env=s["neo4j"].get("environment",{}) or {}; assert "apoc" in str(env.get("NEO4J_PLUGINS", env.get("NEO4JLABS_PLUGINS", ""))).lower()
assert s["neo4j"].get("healthcheck"), "neo4j healthcheck missing"
vols=s["neo4j"].get("volumes",[]) or []; assert any((v if isinstance(v,str) else v.get("target"))=="/data" for v in vols), vols
named=[(v if isinstance(v,str) else v.get("source","")) for v in vols]; assert any(x and not x.startswith(".") and not x.startswith("/") for x in named), named
assert "litellm" in s["llm-proxy"].get("image","").lower()
lv=s["llm-proxy"].get("volumes",[]) or []; assert any("litellm/config.yaml" in str(v) for v in lv), lv
build=s["mcp"].get("build"); assert build and "docker/mcp.Dockerfile" in str(build), build
deps=s["mcp"].get("depends_on",{}) or {}; assert {"neo4j","llm-proxy"}.issubset(set(deps if isinstance(deps,list) else deps.keys())), deps
'
```

## AC-DC2 mechanical check

```bash
docker compose config --format json | python3 -c '
import json, sys
c=json.load(sys.stdin); nets=c.get("networks",{}); svc=c.get("services",{})
for n in ("db-net","llm-net"): assert nets.get(n,{}).get("internal") is True, (n,nets.get(n))
def nset(name): return set((svc[name].get("networks") or {}).keys() if isinstance(svc[name].get("networks"),dict) else (svc[name].get("networks") or []))
assert nset("neo4j")=={"db-net"}, nset("neo4j")
assert nset("llm-proxy")=={"llm-net"}, nset("llm-proxy")
assert nset("mcp")=={"db-net","llm-net"}, nset("mcp")
bridges=[name for name in svc if {"db-net","llm-net"}.issubset(nset(name))]; assert bridges==["mcp"], bridges
assert nset("neo4j").isdisjoint(nset("llm-proxy"))
'
```

## AC-DC3 mechanical check

```bash
docker compose config --format json | python3 -c '
import json, pathlib, re, sys
c=json.load(sys.stdin); svc=c.get("services",{})
def env(name):
    e=svc[name].get("environment",{}) or {}
    return dict(x.split("=",1) for x in e) if isinstance(e,list) else e
def ports(name):
    out=[]
    for p in svc[name].get("ports",[]) or []:
        out.append(str(p.get("published", p)) if isinstance(p,dict) else str(p).split(":")[-2 if str(p).count(":") else -1].split("/")[0])
    return set(out)
allowed={"neo4j":{"7474","7687"},"mcp":{"8080"},"llm-proxy":{"4000"}}
for name in svc: assert ports(name).issubset(allowed.get(name,set())), (name,ports(name))
me=env("mcp"); le=env("llm-proxy"); ne=env("neo4j")
for k in ("NEO4J_URI","NEO4J_USER","NEO4J_PASSWORD","NEO4J_DATABASE","NAM_LLM","NAM_LLM_API_KEY","NAM_EMBEDDING","MCP_TRANSPORT","MCP_HOST","MCP_PORT"): assert k in me, (k,me)
assert me.get("NAM_LLM")=="openai/claude" and me.get("NAM_EMBEDDING")=="BAAI/bge-small-en-v1.5"
assert "ANTHROPIC_API_KEY" not in me
for k in ("LITELLM_MASTER_KEY","ANTHROPIC_API_KEY"): assert k in le, (k,le)
assert any(k in ne for k in ("NEO4J_AUTH","NEO4J_PASSWORD")), ne
cmd=" ".join(map(str, svc["mcp"].get("command",[]) if isinstance(svc["mcp"].get("command"),list) else [svc["mcp"].get("command","")]))
dockerfile=pathlib.Path("docker/mcp.Dockerfile").read_text()
assert "http://llm-proxy:4000/v1" in cmd or "http://llm-proxy:4000/v1" in dockerfile
'
```

# Explicit scope

## In scope

- Authoring `docker-compose.yml` for the three services `neo4j`, `llm-proxy`, and `mcp`.
- Declaring the two segmented internal networks `db-net` and `llm-net`.
- Declaring the named Neo4j data volume and mounting it at `/data`.
- Static compose wiring for service dependencies, builds/images, healthcheck presence, config mounts, env variables, and approved local-dev host ports.
- Static config lint using `docker compose config --format json` and deterministic assertions.

## Out of scope

- Bringing the full stack up, pulling images, building images, or proving containers reach healthy/running state.
- Runtime reachability probes for `mcp → neo4j`, `mcp → llm-proxy`, `neo4j ↛ llm-proxy`, and `llm-proxy ↛ neo4j`.
- MCP tool smoke tests, persistence-after-restart proof, proxy log inspection, Anthropic call execution, and offline embedding model load.
- Changing `docker/mcp.Dockerfile`, `litellm/config.yaml`, `.env.example`, application code, smoke tests, or documentation other than this handoff.

# Unresolved decisions

None — cleared at gate 2.

# Recorded facts & safe choices

## Class 2 facts

- The durable spec requires a local dockerized Neo4j with a named volume, compose-orchestrated services, MCP on both networks, DB/proxy on separate networks, and Anthropic only behind LiteLLM. Citation: `docs/SPECIFICATION.md` lines 35-46 and 59-65.
- The runtime topology names `db-net`, `llm-net`, `neo4j`, `llm-proxy`, and `mcp`; only `mcp` belongs to both networks. Citation: `docs/SPECIFICATION.md` lines 67-100.
- The compose-owned slice is explicitly `docker-compose.yml — the three services, two segmented networks, the neo4j volume`. Citation: `docs/SPECIFICATION.md` lines 113-120.
- Required MCP wiring includes Bolt Neo4j env, `openai/claude`, `http://llm-proxy:4000/v1`, LiteLLM virtual key, local embedder, and MCP HTTP `0.0.0.0:8080`. Citation: `docs/SPECIFICATION.md` lines 121-174 and `.env.example`.
- Deployment notes require `neo4j` official image with APOC, named data volume, bolt healthcheck, `llm-proxy` mounting `litellm/config.yaml`, and `mcp` built from `docker/mcp.Dockerfile` depending on Neo4j and LiteLLM. Citation: `docs/SPECIFICATION.md` lines 191-207.
- `docker/mcp.Dockerfile` already exposes `8080`, launches `mcp serve`, and includes `--llm-api-base http://llm-proxy:4000/v1`, `--profile extended`, `--backend bolt`, and the local embedding model. Citation: `docker/mcp.Dockerfile`.
- `litellm/config.yaml` defines a single `claude` model backed by `anthropic/claude-3-5-sonnet-latest` and reads `ANTHROPIC_API_KEY` plus `LITELLM_MASTER_KEY` from the environment. Citation: `litellm/config.yaml`.
- `.env.example` lists the required Neo4j, MCP, LiteLLM, and Anthropic variables and states that `ANTHROPIC_API_KEY` is for `llm-proxy` only. Citation: `.env.example`.
- No `docker-compose.yml` exists yet in the repository root. Citation: repository root file match for `docker-compose.yml` returned no matches.
- Docker and Compose v2 are available, so static config lint is runnable here: `docker --version` returned `Docker version 28.0.0`; `docker compose version` returned `Docker Compose version v2.33.0`. Citation: environment command output in this Stage 1 run.

## Class 3 safe choices

- Chose to group the compose-visible parts of AC-C1/AC-C2 into AC-DC1 because both are proven by one static topology assertion and runtime start/persistence proof is explicitly deferred.
- Chose to group AC-C3/AC-C5/AC-G4 into AC-DC2 because network membership and internal-network declarations are statically checkable, while reachability probes belong to the later `stack-up` slice.
- Chose to treat LiteLLM host port `4000` as optional but allow-listed because the topology marks it optional and AC-C4 allows it as a documented local-dev port; this is reversible and does not weaken the no-unapproved-ports check.
- Chose to accept the MCP `--llm-api-base` from either compose command or the existing Dockerfile command because the compose file may inherit the Dockerfile `CMD`; this preserves the same observable container command wiring without forcing duplication.
