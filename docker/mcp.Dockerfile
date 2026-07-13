FROM python:3.12-slim

# Install system dependencies for sentence-transformers and Neo4j driver
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Install neo4j-agent-memory framework with MCP support
# Note: Version must be confirmed (open question in spec §10). Using ==0.2.0 as placeholder.
RUN pip install --no-cache-dir "neo4j-agent-memory[mcp]==0.2.0"

# Bake the offline embedding model into the image at build time (satisfies G5/C7).
# This ensures the model loads with no network access at runtime.
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('BAAI/bge-small-en-v1.5')"

EXPOSE 8080

# Health check to verify MCP server is responsive
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import urllib.request; urllib.request.urlopen('http://localhost:8080/sse').close()" || exit 1

# ENTRYPOINT launches mcp serve with flags from spec §4.
# Environment variables (NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD, NEO4J_DATABASE,
# NAM_LLM, NAM_LLM_API_KEY, NAM_EMBEDDING, MCP_TRANSPORT, MCP_HOST, MCP_PORT) are
# read by the framework from the container environment.
# --llm-api-base has no env var, so it is passed as a literal flag.
ENTRYPOINT ["mcp", "serve"]
CMD ["--backend", "bolt", \
     "--transport", "http", \
     "--host", "0.0.0.0", \
     "--port", "8080", \
     "--profile", "extended", \
     "--llm", "openai/claude", \
     "--llm-api-base", "http://llm-proxy:4000/v1", \
     "--embedding", "BAAI/bge-small-en-v1.5"]
