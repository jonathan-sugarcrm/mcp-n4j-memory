# Copilot instructions — mcp-n4j-memory

> **Status: starter file.** The repository is currently empty. This file captures the
> *intended* design so early sessions have direction. Update every section as real code
> lands, and delete this note once the project is established.

## What this project is

`mcp-n4j-memory` is a **Model Context Protocol (MCP) server** that exposes a **persistent
memory store backed by Neo4j** (`n4j` = Neo4j). MCP clients (Copilot, Claude, other agents)
connect to it to store and retrieve long-lived "memories" as a knowledge graph:

- **Nodes** represent entities/observations (e.g. a fact, a person, a preference).
- **Relationships** connect them (e.g. `KNOWS`, `RELATES_TO`, `DERIVED_FROM`).
- The graph lets agents recall context across sessions and traverse related memories,
  rather than storing flat key/value text.

The server's public surface is a set of **MCP tools** (e.g. create/search/relate/delete
memory) that clients call over the MCP transport (stdio and/or HTTP).

## Architecture (big picture)

Keep three layers cleanly separated so the graph model and the MCP protocol don't leak into
each other:

1. **MCP layer** — registers tools/resources and validates incoming arguments against a
   schema. This layer speaks MCP and knows nothing about Cypher.
2. **Domain/service layer** — memory operations (create, search, relate, forget). Pure
   application logic; takes plain objects in and out.
3. **Neo4j layer** — a single place that owns the driver/session lifecycle and all Cypher
   queries. Nothing outside this layer should build Cypher strings.

Data flow: `MCP tool call → validate args → service method → Neo4j query → shaped result → MCP response`.

## Conventions to establish (and follow once chosen)

- **All Cypher lives in the Neo4j layer.** Never embed query strings in tool handlers.
- **Always use parameterized Cypher** (`$param`), never string interpolation — this prevents
  injection and lets Neo4j cache query plans.
- **One driver, short-lived sessions.** Create the Neo4j driver once at startup and reuse it;
  open a session per operation and close it (use the driver's managed transaction helpers).
- **Tool inputs are schema-validated** at the MCP boundary; the service layer can assume
  valid input.
- **Config via environment variables**, e.g. `NEO4J_URI`, `NEO4J_USER`, `NEO4J_PASSWORD`,
  `NEO4J_DATABASE`. Never commit credentials; provide a `.env.example`.
- **MCP tool names** should be verb-first and stable (e.g. `create_memory`, `search_memory`,
  `relate_memory`, `delete_memory`) — clients bind to these names.

## Build, test, run

> Fill these in with the exact, verified commands once the toolchain exists, including how to
> run a **single** test. Placeholders below reflect the two most likely stacks.

**If TypeScript/Node (`@modelcontextprotocol/sdk`, `neo4j-driver`):**
- Install: `npm install`
- Build: `npm run build`
- Test (all): `npm test`
- Test (single): `npm test -- <file-or-name-pattern>`
- Run server: `npm start`

**If Python (`mcp`, `neo4j`):**
- Install: `uv sync` (or `pip install -e .`)
- Test (all): `pytest`
- Test (single): `pytest path/to/test_file.py::test_name`
- Run server: `python -m mcp_n4j_memory` (adjust to actual module)

## Local Neo4j for development

Run a local instance before testing anything that touches the graph, e.g.:

```
docker run --rm -p 7474:7474 -p 7687:7687 \
  -e NEO4J_AUTH=neo4j/password neo4j:5
```

Point `NEO4J_URI=bolt://localhost:7687` and matching credentials at it.

## Testing notes

- Unit-test the **service layer** with the Neo4j layer mocked/faked.
- Integration-test Cypher against a **real (or Testcontainers) Neo4j** — mocking the driver
  hides Cypher bugs, which are the most likely failures here.
