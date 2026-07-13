# Implementation handoff — docker-compose

## 1. Implementation plan

- [Author `docker-compose.yml` with `neo4j`, `llm-proxy`, and `mcp` services, Neo4j named `/data` volume, official Neo4j image/APOC/healthcheck, LiteLLM image/config mount, and MCP build/dependencies] -> verify: `docker compose config` and AC-DC1 mechanical check.
- [Declare `db-net` and `llm-net` as internal networks and attach only `mcp` to both] -> verify: AC-DC2 mechanical check.
- [Wire approved host ports and service environments, keeping `ANTHROPIC_API_KEY` only on `llm-proxy` and deterministic MCP LLM/embed defaults] -> verify: AC-DC3 mechanical check plus failure-path sanity mutation.
- [Write this implementation handoff with commands, raw outputs, decisions, and blocking defects] -> verify: file exists at `docs/spec-loop-runs/docker-compose/implementation.handoff.md`.

## 2. Changed files

- `docker-compose.yml` — implements AC-DC1, AC-DC2, and AC-DC3 compose topology, network, volume, port, build/image, dependency, and env wiring.
- `docs/spec-loop-runs/docker-compose/implementation.handoff.md` — required Stage 2 output artifact for AC-DC1, AC-DC2, and AC-DC3 evidence.

## 3. Decision log

- Chose `${VAR:-default}` compose defaults over bare `${VAR}` interpolation because rendered static config must deterministically satisfy AC-DC3 when no shell `.env` values are supplied; this is reversible and preserves operator override behaviour.
- Chose `neo4j:5` over a more specific patch tag because the requirement only mandates an official Neo4j image with APOC; this follows the existing local Neo4j development note and has no static contract impact.
- Chose `ghcr.io/berriai/litellm:main-stable` because it is a LiteLLM image and matches the required LiteLLM proxy role; the exact tag is reversible and not constrained by the handoff.
- Chose to publish LiteLLM host port `4000` because AC-DC3 explicitly allows it as optional and local-dev useful; removing it later remains reversible.
- Chose `NEO4J_AUTH: neo4j/${NEO4J_PASSWORD:-change-me}` over separate Neo4j password-only wiring because AC-DC3 accepts `NEO4J_AUTH` and this is the standard official Neo4j container contract.
- Chose `depends_on.neo4j.condition: service_healthy` and `depends_on.llm-proxy.condition: service_started` over list-form dependencies because AC-DC1 only requires both dependencies and the health-aware Neo4j dependency is safer without changing the static service contract.
- Chose not to duplicate the MCP Dockerfile command in compose because `docker/mcp.Dockerfile` already includes `--llm-api-base http://llm-proxy:4000/v1`, and AC-DC3 explicitly permits inherited Dockerfile command wiring.

## 4. Evidence

All commands were run from repository root: `/home/jrawlinson/.repositories/jonathan-sugarcrm/mcp-n4j-memory`.

### Static render

Command:

```bash
docker compose config
```

Output:

```text
name: mcp-n4j-memory
services:
  llm-proxy:
    command:
      - --config
      - /app/config.yaml
      - --host
      - 0.0.0.0
      - --port
      - "4000"
    environment:
      ANTHROPIC_API_KEY: change-me
      LITELLM_MASTER_KEY: change-me
    image: ghcr.io/berriai/litellm:main-stable
    networks:
      llm-net: null
    ports:
      - mode: ingress
        target: 4000
        published: "4000"
        protocol: tcp
    volumes:
      - type: bind
        source: /home/jrawlinson/.repositories/jonathan-sugarcrm/mcp-n4j-memory/litellm/config.yaml
        target: /app/config.yaml
        read_only: true
        bind:
          create_host_path: true
  mcp:
    build:
      context: /home/jrawlinson/.repositories/jonathan-sugarcrm/mcp-n4j-memory
      dockerfile: docker/mcp.Dockerfile
    depends_on:
      llm-proxy:
        condition: service_started
        required: true
      neo4j:
        condition: service_healthy
        required: true
    environment:
      MCP_HOST: 0.0.0.0
      MCP_PORT: "8080"
      MCP_TRANSPORT: http
      NAM_EMBEDDING: BAAI/bge-small-en-v1.5
      NAM_LLM: openai/claude
      NAM_LLM_API_KEY: change-me
      NEO4J_DATABASE: neo4j
      NEO4J_PASSWORD: change-me
      NEO4J_URI: bolt://neo4j:7687
      NEO4J_USER: neo4j
    networks:
      db-net: null
      llm-net: null
    ports:
      - mode: ingress
        target: 8080
        published: "8080"
        protocol: tcp
  neo4j:
    environment:
      NEO4J_AUTH: neo4j/change-me
      NEO4J_PLUGINS: '["apoc"]'
    healthcheck:
      test:
        - CMD-SHELL
        - cypher-shell -u neo4j -p "change-me" 'RETURN 1' || exit 1
      timeout: 5s
      interval: 10s
      retries: 10
      start_period: 30s
    image: neo4j:5
    networks:
      db-net: null
    ports:
      - mode: ingress
        target: 7474
        published: "7474"
        protocol: tcp
      - mode: ingress
        target: 7687
        published: "7687"
        protocol: tcp
    volumes:
      - type: volume
        source: neo4j-data
        target: /data
        volume: {}
networks:
  db-net:
    name: mcp-n4j-memory_db-net
    internal: true
  llm-net:
    name: mcp-n4j-memory_llm-net
    internal: true
volumes:
  neo4j-data:
    name: mcp-n4j-memory_neo4j-data
```

Exit code: `0`

### AC-DC1 — happy path

Command:

```bash
docker compose config --format json | python3 -c '<AC-DC1 mechanical check from specification.handoff.md>'
printf 'EXIT_CODE=%s\n' "$?"
```

Output:

```text
AC-DC1 happy
EXIT_CODE=0
```

### AC-DC1 — failure-path sanity

Command:

```bash
docker compose config --format json \
  | python3 -c 'import json,sys; c=json.load(sys.stdin); c["services"]["neo4j"]["volumes"]=[]; json.dump(c, sys.stdout)' \
  | python3 -c '<AC-DC1 mechanical check from specification.handoff.md>'
printf 'EXIT_CODE=%s\n' "$?"
```

Output:

```text
AC-DC1 failure sanity (remove neo4j volumes)
Traceback (most recent call last):
  File "<string>", line 7, in <module>
AssertionError: []
EXIT_CODE=1
```

### AC-DC2 — happy path

Command:

```bash
docker compose config --format json | python3 -c '<AC-DC2 mechanical check from specification.handoff.md>'
printf 'EXIT_CODE=%s\n' "$?"
```

Output:

```text
AC-DC2 happy
EXIT_CODE=0
```

### AC-DC2 — failure-path sanity

Command:

```bash
docker compose config --format json \
  | python3 -c 'import json,sys; c=json.load(sys.stdin); c["services"]["neo4j"]["networks"]["llm-net"]={}; json.dump(c, sys.stdout)' \
  | python3 -c '<AC-DC2 mechanical check from specification.handoff.md>'
printf 'EXIT_CODE=%s\n' "$?"
```

Output:

```text
AC-DC2 failure sanity (attach neo4j to llm-net)
Traceback (most recent call last):
  File "<string>", line 6, in <module>
AssertionError: {'db-net', 'llm-net'}
EXIT_CODE=1
```

### AC-DC3 — happy path

Command:

```bash
docker compose config --format json | python3 -c '<AC-DC3 mechanical check from specification.handoff.md>'
printf 'EXIT_CODE=%s\n' "$?"
```

Output:

```text
AC-DC3 happy
EXIT_CODE=0
```

### AC-DC3 — failure-path sanity

Command:

```bash
docker compose config --format json \
  | python3 -c 'import json,sys; c=json.load(sys.stdin); c["services"]["mcp"]["environment"]["ANTHROPIC_API_KEY"]="leaked"; json.dump(c, sys.stdout)' \
  | python3 -c '<AC-DC3 mechanical check from specification.handoff.md>'
printf 'EXIT_CODE=%s\n' "$?"
```

Output:

```text
AC-DC3 failure sanity (add ANTHROPIC_API_KEY to mcp)
Traceback (most recent call last):
  File "<string>", line 17, in <module>
AssertionError
EXIT_CODE=1
```

## 5. Blocking spec defects

None.

## Appendix A — exact embedded check commands executed

The per-requirement command lines above use placeholders only to avoid duplicating the long script in each subsection. The exact command batch executed for the happy path was:

```bash
set +e
printf 'AC-DC1 happy\n'
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
printf 'EXIT_CODE=%s\n' "$?"
printf 'AC-DC2 happy\n'
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
printf 'EXIT_CODE=%s\n' "$?"
printf 'AC-DC3 happy\n'
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
printf 'EXIT_CODE=%s\n' "$?"
```

The exact command batch executed for the failure-path sanity checks was:

```bash
set +e
printf 'AC-DC1 failure sanity (remove neo4j volumes)\n'
docker compose config --format json | python3 -c 'import json,sys; c=json.load(sys.stdin); c["services"]["neo4j"]["volumes"]=[]; json.dump(c, sys.stdout)' | python3 -c '
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
printf 'EXIT_CODE=%s\n' "$?"
printf 'AC-DC2 failure sanity (attach neo4j to llm-net)\n'
docker compose config --format json | python3 -c 'import json,sys; c=json.load(sys.stdin); c["services"]["neo4j"]["networks"]["llm-net"]={}; json.dump(c, sys.stdout)' | python3 -c '
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
printf 'EXIT_CODE=%s\n' "$?"
printf 'AC-DC3 failure sanity (add ANTHROPIC_API_KEY to mcp)\n'
docker compose config --format json | python3 -c 'import json,sys; c=json.load(sys.stdin); c["services"]["mcp"]["environment"]["ANTHROPIC_API_KEY"]="leaked"; json.dump(c, sys.stdout)' | python3 -c '
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
printf 'EXIT_CODE=%s\n' "$?"
```
