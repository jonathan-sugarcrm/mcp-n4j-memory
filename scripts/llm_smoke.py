#!/usr/bin/env python3
"""llm-smoke sequence: exercises the LLM-triggering store/search path end to end.

Drives the running `mcp` MCP server over its HTTP transport (via `fastmcp.Client`)
and reads Neo4j directly over bolt to prove:

  R2 — `memory_store_message` persists a queryable node in local Neo4j.
  R4 — `memory_search` finds a token-disjoint paraphrase of stored content
       (proves semantic vector search, not exact-token/full-text matching).

R1 (proxy routing/isolation) and R3 (offline embedder env) are asserted
separately via `docker compose logs`/`docker compose exec env` and are not
re-proven here; this script only exercises the store/search request path that
R1's log evidence and R3's offline-load evidence are captured against.

Usage (from repo root, with the compose stack up and ports published):

    python3 scripts/llm_smoke.py \
        --mcp-url http://localhost:8080/mcp \
        --neo4j-uri bolt://localhost:7687 \
        --neo4j-user neo4j \
        --neo4j-password "$NEO4J_PASSWORD"

Exits 0 and prints "LLM_SMOKE_OK" on success. Exits 1 with a diagnostic on
failure (missing node in Neo4j, or paraphrase search returning no hit).
"""

from __future__ import annotations

import argparse
import asyncio
import json
import sys
import uuid

from fastmcp import Client
from neo4j import GraphDatabase


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--mcp-url", default="http://localhost:8080/mcp")
    parser.add_argument("--neo4j-uri", default="bolt://localhost:7687")
    parser.add_argument("--neo4j-user", default="neo4j")
    parser.add_argument("--neo4j-password", required=True)
    parser.add_argument("--neo4j-database", default="neo4j")
    return parser.parse_args()


async def run(args: argparse.Namespace) -> int:
    marker = f"llm-smoke-{uuid.uuid4().hex[:12]}"
    session_id = f"llm-smoke-session-{uuid.uuid4().hex[:8]}"
    # Chosen so the paraphrase query below shares no exact significant token
    # with this sentence (R4 requires token-disjoint paraphrase evidence).
    stored_content = (
        f"Marker {marker}: the falcon soared gracefully above the canyon at dawn."
    )
    paraphrase_query = "A bird glided elegantly over the gorge in early morning."

    print(f"[llm-smoke] marker={marker} session_id={session_id}")

    async with Client(args.mcp_url) as client:
        print("[llm-smoke] calling memory_store_message ...")
        store_result = await client.call_tool(
            "memory_store_message",
            {
                "content": stored_content,
                "role": "user",
                "session_id": session_id,
            },
        )
        print(f"[llm-smoke] store result: {store_result.data!r}")

        print("[llm-smoke] calling memory_search with token-disjoint paraphrase ...")
        search_result = await client.call_tool(
            "memory_search",
            {
                "query": paraphrase_query,
                "session_id": session_id,
                "limit": 10,
                "threshold": 0.5,
            },
        )
        print(f"[llm-smoke] search result: {search_result.data!r}")

    # R2 — direct bolt/Cypher read proving the store call persisted a node.
    driver = GraphDatabase.driver(
        args.neo4j_uri, auth=(args.neo4j_user, args.neo4j_password)
    )
    try:
        with driver.session(database=args.neo4j_database) as session:
            record = session.run(
                "MATCH (n) WHERE n.content CONTAINS $marker "
                "RETURN n LIMIT 1",
                marker=marker,
            ).single()
    finally:
        driver.close()

    if record is None:
        print(f"FAIL: no Neo4j node found containing marker {marker!r} (R2)")
        return 1
    print(f"[llm-smoke] R2 OK: Neo4j node found for marker {marker}: {dict(record['n'])!r}")

    # R4 — assert the paraphrase search surfaced the stored marker/session.
    search_payload = search_result.data
    if isinstance(search_payload, str):
        search_payload = json.loads(search_payload)
    search_blob = json.dumps(search_payload, default=str)
    if marker not in search_blob and session_id not in search_blob:
        print(
            "FAIL: paraphrase search did not return the stored marker/session (R4)\n"
            f"search_blob={search_blob}"
        )
        return 1
    print("[llm-smoke] R4 OK: paraphrase search returned the stored marker/session")

    print("LLM_SMOKE_OK")
    return 0


def main() -> int:
    args = parse_args()
    return asyncio.run(run(args))


if __name__ == "__main__":
    sys.exit(main())
