# Implementation handoff — stack-up

## Implementation plan

1. [STK-C1 config proof] -> verify: render compose config and assert Neo4j maps named volume `neo4j-data` to `/data` and includes `bolt://neo4j:7687`.
2. [STK-C1 failure proof] -> verify: run the same config assertion against a deleted-after-use mutated compose copy with the `/data` volume renamed; assertion exits non-zero.
3. [STK-C1 runtime proof] -> verify: start only `neo4j` and `llm-proxy`, wait for Neo4j healthy, write one test node via in-container `cypher-shell`, restart `neo4j`, wait healthy again, and re-query the node.
4. [STK-C5-G4 config proof] -> verify: render compose config and assert `neo4j` is only on `db-net`, `llm-proxy` is only on `llm-net`, both networks are internal, and there is no shared network.
5. [STK-C5-G4 runtime proof] -> verify: run in-container probes from `neo4j` to `llm-proxy:4000` and from `llm-proxy` to `neo4j:7687`; both probes show non-zero exits and errors.
6. [cleanup] -> verify: `docker compose -p spec-loop-stack-up down -v` removes containers, networks, and the test volume.

## Changed files

- `docs/spec-loop-runs/stack-up/implementation.handoff.md` — Stage 2 output artifact with plan, decisions, evidence, and blocking defects for STK-C1 and STK-C5-G4.

No source, compose, or configuration files were changed. A temporary mutated compose file was created at `docs/spec-loop-runs/stack-up/docker-compose.mutated.yml` for the STK-C1 failure-behaviour check and deleted before exit.

## Decision log

- Chose `docker compose -p spec-loop-stack-up` over the default project name because an explicit project name isolates containers, networks, and volumes and has no contract impact.
- Chose to start only `neo4j` and `llm-proxy` because the handoff scope excludes the heavy `mcp` image and this is reversible slice execution.
- Chose inline dummy environment values (`NEO4J_PASSWORD=change-me LITELLM_MASTER_KEY=change-me ANTHROPIC_API_KEY=change-me`) over writing a `.env` because no real LLM call is in scope, placeholders are non-secret, and avoiding a persisted env file reduces cleanup risk.
- Chose not to override host port publishes because preflight showed no listeners or published containers on 7474, 7687, or 4000; using the repo compose file directly follows the existing configuration.
- Chose Python JSON assertions over text greps for compose config because structured assertions are deterministic, reversible, and do not change repo behaviour.
- Chose a temporary mutated compose copy under the slice run directory over editing `docker-compose.yml` because it proves STK-C1 failure behaviour without damaging the real compose file.
- Chose direct in-container `cypher-shell` over host bolt access because the handoff requires direct Neo4j proof and in-container execution avoids host-network assumptions.
- Chose Bash `/dev/tcp` with `timeout` for the `neo4j`-side reachability probe because it was available in the Neo4j image and requires no package installation.
- Chose Python `socket.create_connection` for the `llm-proxy`-side reachability probe because Python is available in the LiteLLM image and requires no package installation.
- Chose not to run optional positive controls because the required config assertions already prove same-network membership, the runtime negative probes produced concrete DNS failures, and optional controls are not required by the handoff.
- Chose `docker compose down -v` over leaving the stack running because the handoff explicitly requires cleanup and the named volume contains only test data.

## Evidence

### Environment and port preflight

Command:

```bash
cd /home/jrawlinson/.repositories/jonathan-sugarcrm/mcp-n4j-memory && set -o pipefail
printf '### git status before\n'
git --no-pager status --short
printf '\n### docker versions\n'
docker --version && docker compose version
printf '\n### host port listeners 7474 7687 4000\n'
(ss -ltnp 'sport = :7474' || true) 2>&1
(ss -ltnp 'sport = :7687' || true) 2>&1
(ss -ltnp 'sport = :4000' || true) 2>&1
printf '\n### docker ps published ports 7474 7687 4000\n'
docker ps --format 'table {{.Names}}\t{{.Image}}\t{{.Ports}}' | (head -n 1; grep -E '(:7474|:7687|:4000)' || true)
```

Output:

```text
### git status before
?? docs/spec-loop-runs/stack-up/

### docker versions
Docker version 28.0.0, build f9ced58
Docker Compose version v2.33.0

### host port listeners 7474 7687 4000
State Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
State Recv-Q Send-Q Local Address:Port Peer Address:PortProcess
State Recv-Q Send-Q Local Address:Port Peer Address:PortProcess

### docker ps published ports 7474 7687 4000
NAMES               IMAGE                              PORTS
```

### STK-C1 — config happy path and failure behaviour

Command:

```bash
cd /home/jrawlinson/.repositories/jonathan-sugarcrm/mcp-n4j-memory && set -o pipefail
export NEO4J_PASSWORD=change-me LITELLM_MASTER_KEY=change-me ANTHROPIC_API_KEY=change-me
printf '### STK-C1 config assertion command\n'
printf '%s\n' "docker compose -p spec-loop-stack-up config --format json | python3 -c '<assert neo4j-data:/data and bolt://neo4j:7687>'"
docker compose -p spec-loop-stack-up config --format json | python3 -c '
import json, sys
cfg=json.load(sys.stdin)
neo=cfg["services"]["neo4j"]
vols=neo.get("volumes", [])
print("neo4j volumes:")
for v in vols:
    print(v)
if not any(v.get("source") == "neo4j-data" and v.get("target") == "/data" and v.get("type") == "volume" for v in vols):
    raise SystemExit("ASSERTION FAILED: neo4j-data named volume is not mounted at /data")
uris=[]
for svc_name, svc in cfg.get("services", {}).items():
    env=svc.get("environment", {}) or {}
    if isinstance(env, dict):
        for k, val in env.items():
            if k == "NEO4J_URI" or str(val).startswith("bolt://"):
                uris.append((svc_name, k, val))
print("bolt URI entries:")
for item in uris:
    print(item)
if not any(val == "bolt://neo4j:7687" for _, _, val in uris):
    raise SystemExit("ASSERTION FAILED: bolt://neo4j:7687 not rendered")
print("ASSERTION PASSED: neo4j-data:/data and bolt://neo4j:7687 present")
'
printf '\n### STK-C1 failure behaviour mutated config assertion command\n'
printf '%s\n' "python3 - <<'PY' ... write docs/spec-loop-runs/stack-up/docker-compose.mutated.yml with neo4j-data:/data renamed ...; docker compose -f docker-compose.mutated.yml config --format json | python3 -c '<same assertion>'"
python3 - <<'PY'
from pathlib import Path
src = Path('docker-compose.yml').read_text()
mut = src.replace('- neo4j-data:/data', '- renamed-neo4j-data:/data').replace('  neo4j-data:', '  renamed-neo4j-data:')
Path('docs/spec-loop-runs/stack-up/docker-compose.mutated.yml').write_text(mut)
PY
set +e
docker compose -p spec-loop-stack-up-mutated -f docs/spec-loop-runs/stack-up/docker-compose.mutated.yml config --format json | python3 -c '
import json, sys
cfg=json.load(sys.stdin)
vols=cfg["services"]["neo4j"].get("volumes", [])
print("neo4j volumes:")
for v in vols:
    print(v)
if not any(v.get("source") == "neo4j-data" and v.get("target") == "/data" and v.get("type") == "volume" for v in vols):
    raise SystemExit("ASSERTION FAILED: neo4j-data named volume is not mounted at /data")
print("ASSERTION PASSED: neo4j-data:/data present")
'
status=$?
set -e
printf 'mutated_config_assertion_exit=%s\n' "$status"
rm -f docs/spec-loop-runs/stack-up/docker-compose.mutated.yml
exit 0
```

Output:

```text
### STK-C1 config assertion command
docker compose -p spec-loop-stack-up config --format json | python3 -c '<assert neo4j-data:/data and bolt://neo4j:7687>'
neo4j volumes:
{'type': 'volume', 'source': 'neo4j-data', 'target': '/data', 'volume': {}}
bolt URI entries:
('mcp', 'NEO4J_URI', 'bolt://neo4j:7687')
ASSERTION PASSED: neo4j-data:/data and bolt://neo4j:7687 present

### STK-C1 failure behaviour mutated config assertion command
python3 - <<'PY' ... write docs/spec-loop-runs/stack-up/docker-compose.mutated.yml with neo4j-data:/data renamed ...; docker compose -f docker-compose.mutated.yml config --format json | python3 -c '<same assertion>'
ASSERTION FAILED: neo4j-data named volume is not mounted at /data
neo4j volumes:
{'type': 'volume', 'source': 'renamed-neo4j-data', 'target': '/data', 'volume': {}}
mutated_config_assertion_exit=1
```

### STK-C1 — runtime persistence across restart

Command:

```bash
cd /home/jrawlinson/.repositories/jonathan-sugarcrm/mcp-n4j-memory && set -o pipefail
export NEO4J_PASSWORD=change-me LITELLM_MASTER_KEY=change-me ANTHROPIC_API_KEY=change-me
printf '### compose ps before STK-C1 runtime\n'
docker compose -p spec-loop-stack-up ps
printf '\n### STK-C1 write node via cypher-shell\n'
printf '%s\n' "docker compose -p spec-loop-stack-up exec -T neo4j cypher-shell -u neo4j -p change-me 'MERGE (n:SpecLoopProbe {id:\"stk-c1-20260713T130433\"}) SET n.value=\"written-before-restart\" RETURN n.id AS id, n.value AS value'"
docker compose -p spec-loop-stack-up exec -T neo4j cypher-shell -u neo4j -p change-me 'MERGE (n:SpecLoopProbe {id:"stk-c1-20260713T130433"}) SET n.value="written-before-restart" RETURN n.id AS id, n.value AS value'
printf '\n### restart neo4j\n'
printf '%s\n' 'docker compose -p spec-loop-stack-up restart neo4j'
docker compose -p spec-loop-stack-up restart neo4j
printf '\n### wait neo4j healthy after restart\n'
for i in $(seq 1 60); do
  status=$(docker inspect -f '{{.State.Health.Status}}' spec-loop-stack-up-neo4j-1 2>&1) || status="inspect_failed:$status"
  printf 'neo4j_health_attempt=%s status=%s\n' "$i" "$status"
  [ "$status" = healthy ] && break
  sleep 5
done
[ "$status" = healthy ] || { echo 'neo4j did not become healthy after restart'; exit 1; }
printf '\n### STK-C1 re-query after restart\n'
printf '%s\n' "docker compose -p spec-loop-stack-up exec -T neo4j cypher-shell -u neo4j -p change-me 'MATCH (n:SpecLoopProbe {id:\"stk-c1-20260713T130433\"}) RETURN n.id AS id, n.value AS value'"
docker compose -p spec-loop-stack-up exec -T neo4j cypher-shell -u neo4j -p change-me 'MATCH (n:SpecLoopProbe {id:"stk-c1-20260713T130433"}) RETURN n.id AS id, n.value AS value'
```

Output:

```text
### compose ps before STK-C1 runtime
NAME                             IMAGE                                 COMMAND                  SERVICE     CREATED          STATUS                    PORTS
spec-loop-stack-up-llm-proxy-1   ghcr.io/berriai/litellm:main-stable   "docker/prod_entrypo…"   llm-proxy   43 seconds ago   Up 39 seconds             
spec-loop-stack-up-neo4j-1       neo4j:5                               "tini -g -- /startup…"   neo4j       43 seconds ago   Up 39 seconds (healthy)   

### STK-C1 write node via cypher-shell
docker compose -p spec-loop-stack-up exec -T neo4j cypher-shell -u neo4j -p change-me 'MERGE (n:SpecLoopProbe {id:"stk-c1-20260713T130433"}) SET n.value="written-before-restart" RETURN n.id AS id, n.value AS value'
id, value
"stk-c1-20260713T130433", "written-before-restart"

### restart neo4j
docker compose -p spec-loop-stack-up restart neo4j
 Container spec-loop-stack-up-neo4j-1  Restarting
 Container spec-loop-stack-up-neo4j-1  Started

### wait neo4j healthy after restart
neo4j_health_attempt=1 status=starting
neo4j_health_attempt=2 status=starting
neo4j_health_attempt=3 status=starting
neo4j_health_attempt=4 status=starting
neo4j_health_attempt=5 status=healthy

### STK-C1 re-query after restart
docker compose -p spec-loop-stack-up exec -T neo4j cypher-shell -u neo4j -p change-me 'MATCH (n:SpecLoopProbe {id:"stk-c1-20260713T130433"}) RETURN n.id AS id, n.value AS value'
id, value
"stk-c1-20260713T130433", "written-before-restart"
```

### STK-C5-G4 — config and negative reachability probes

Command:

```bash
cd /home/jrawlinson/.repositories/jonathan-sugarcrm/mcp-n4j-memory && set -o pipefail
export NEO4J_PASSWORD=change-me LITELLM_MASTER_KEY=change-me ANTHROPIC_API_KEY=change-me
printf '### STK-C5-G4 compose network assertion command\n'
printf '%s\n' "docker compose -p spec-loop-stack-up config --format json | python3 -c '<assert neo4j only db-net, llm-proxy only llm-net, both internal, no shared network>'"
docker compose -p spec-loop-stack-up config --format json | python3 -c '
import json, sys
cfg=json.load(sys.stdin)
services=cfg["services"]
networks=cfg["networks"]
neo_nets=set(services["neo4j"].get("networks", {}).keys())
llm_nets=set(services["llm-proxy"].get("networks", {}).keys())
print("neo4j networks:", sorted(neo_nets))
print("llm-proxy networks:", sorted(llm_nets))
print("db-net internal:", networks["db-net"].get("internal"))
print("llm-net internal:", networks["llm-net"].get("internal"))
print("shared networks:", sorted(neo_nets & llm_nets))
if neo_nets != {"db-net"}:
    raise SystemExit("ASSERTION FAILED: neo4j is not only on db-net")
if llm_nets != {"llm-net"}:
    raise SystemExit("ASSERTION FAILED: llm-proxy is not only on llm-net")
if networks["db-net"].get("internal") is not True or networks["llm-net"].get("internal") is not True:
    raise SystemExit("ASSERTION FAILED: db-net and llm-net are not both internal")
if neo_nets & llm_nets:
    raise SystemExit("ASSERTION FAILED: neo4j and llm-proxy share a network")
print("ASSERTION PASSED: network membership is isolated")
'
printf '\n### STK-C5-G4 neo4j -> llm-proxy:4000 probe\n'
printf '%s\n' "docker compose -p spec-loop-stack-up exec -T neo4j bash -lc 'timeout 5 bash -lc \"</dev/tcp/llm-proxy/4000\"'"
set +e
docker compose -p spec-loop-stack-up exec -T neo4j bash -lc 'timeout 5 bash -lc "</dev/tcp/llm-proxy/4000"'
neo_to_llm=$?
set -e
printf 'neo4j_to_llm_probe_exit=%s\n' "$neo_to_llm"
if [ "$neo_to_llm" -eq 0 ]; then echo 'ISOLATION VIOLATION: neo4j connected to llm-proxy:4000'; exit 1; fi
printf '\n### STK-C5-G4 llm-proxy -> neo4j:7687 probe\n'
printf '%s\n' "docker compose -p spec-loop-stack-up exec -T llm-proxy python -c 'import socket; socket.create_connection((\"neo4j\", 7687), timeout=5)'"
set +e
docker compose -p spec-loop-stack-up exec -T llm-proxy python -c 'import socket; socket.create_connection(("neo4j", 7687), timeout=5)'
llm_to_neo=$?
set -e
printf 'llm_to_neo4j_probe_exit=%s\n' "$llm_to_neo"
if [ "$llm_to_neo" -eq 0 ]; then echo 'ISOLATION VIOLATION: llm-proxy connected to neo4j:7687'; exit 1; fi
```

Output:

```text
### STK-C5-G4 compose network assertion command
docker compose -p spec-loop-stack-up config --format json | python3 -c '<assert neo4j only db-net, llm-proxy only llm-net, both internal, no shared network>'
neo4j networks: ['db-net']
llm-proxy networks: ['llm-net']
db-net internal: True
llm-net internal: True
shared networks: []
ASSERTION PASSED: network membership is isolated

### STK-C5-G4 neo4j -> llm-proxy:4000 probe
docker compose -p spec-loop-stack-up exec -T neo4j bash -lc 'timeout 5 bash -lc "</dev/tcp/llm-proxy/4000"'
bash: line 1: llm-proxy: Temporary failure in name resolution
bash: line 1: /dev/tcp/llm-proxy/4000: Invalid argument
exit status 1
neo4j_to_llm_probe_exit=1

### STK-C5-G4 llm-proxy -> neo4j:7687 probe
docker compose -p spec-loop-stack-up exec -T llm-proxy python -c 'import socket; socket.create_connection(("neo4j", 7687), timeout=5)'
Traceback (most recent call last):
  File "<string>", line 1, in <module>
    import socket; socket.create_connection(("neo4j", 7687), timeout=5)
                   ~~~~~~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.13/socket.py", line 844, in create_connection
    for res in getaddrinfo(host, port, 0, SOCK_STREAM):
               ~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^
  File "/usr/lib/python3.13/socket.py", line 981, in getaddrinfo
    for res in _socket.getaddrinfo(host, port, family, type, proto, flags):
               ~~~~~~~~~~~~~~~~~~~^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^^
socket.gaierror: [Errno -3] Temporary failure in name resolution
exit status 1
llm_to_neo4j_probe_exit=1
```

### Cleanup

Command:

```bash
cd /home/jrawlinson/.repositories/jonathan-sugarcrm/mcp-n4j-memory && set -o pipefail
export NEO4J_PASSWORD=change-me LITELLM_MASTER_KEY=change-me ANTHROPIC_API_KEY=change-me
printf '### cleanup command\n'
printf '%s\n' 'docker compose -p spec-loop-stack-up down -v'
docker compose -p spec-loop-stack-up down -v
printf '\n### compose ps after cleanup\n'
docker compose -p spec-loop-stack-up ps -a
printf '\n### project volumes after cleanup\n'
docker volume ls --filter label=com.docker.compose.project=spec-loop-stack-up --format '{{.Name}}'
```

Output:

```text
### cleanup command
docker compose -p spec-loop-stack-up down -v
 Container spec-loop-stack-up-neo4j-1  Stopping
 Container spec-loop-stack-up-llm-proxy-1  Stopping
 Container spec-loop-stack-up-llm-proxy-1  Stopped
 Container spec-loop-stack-up-llm-proxy-1  Removing
 Container spec-loop-stack-up-llm-proxy-1  Removed
 Container spec-loop-stack-up-neo4j-1  Stopped
 Container spec-loop-stack-up-neo4j-1  Removing
 Container spec-loop-stack-up-neo4j-1  Removed
 Volume spec-loop-stack-up_neo4j-data  Removing
 Network spec-loop-stack-up_db-net  Removing
 Network spec-loop-stack-up_llm-net  Removing
 Volume spec-loop-stack-up_neo4j-data  Removed
 Network spec-loop-stack-up_db-net  Removed
 Network spec-loop-stack-up_llm-net  Removed

### compose ps after cleanup
NAME      IMAGE     COMMAND   SERVICE   CREATED   STATUS    PORTS

### project volumes after cleanup
```

## Blocking spec defects

None.
