FROM python:3.12-slim

# Install system dependencies for sentence-transformers and Neo4j driver
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    libssl-dev \
    libffi-dev \
    && rm -rf /var/lib/apt/lists/*

# Install neo4j-agent-memory framework with MCP support and the local embedding backend.
RUN pip install --no-cache-dir "neo4j-agent-memory[mcp,sentence-transformers]==0.2.0"

# Bake the offline embedding model into the image at build time (satisfies G5/C7).
# This ensures the model loads with no network access at runtime.
RUN python -c "from sentence_transformers import SentenceTransformer; SentenceTransformer('BAAI/bge-small-en-v1.5')"

EXPOSE 8080

# Health check to verify the MCP server port is responsive.
HEALTHCHECK --interval=30s --timeout=10s --start-period=5s --retries=3 \
    CMD python -c "import socket; s=socket.create_connection(('127.0.0.1', 8080), 5); s.close()" || exit 1

# ENTRYPOINT launches the real framework MCP server.
# Environment variables (NEO4J_URI, NEO4J_USER, NEO4J_PASSWORD, NEO4J_DATABASE,
# NAM_*) are read by the framework from the container environment.
ENTRYPOINT ["neo4j-agent-memory", "mcp", "serve"]
CMD ["--transport", "http", \
     "--host", "0.0.0.0", \
     "--port", "8080", \
     "--profile", "extended"]
