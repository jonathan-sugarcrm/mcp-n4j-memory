#!/usr/bin/env bash
# check_thin_delta.sh — AC-G6 thin-delta lint.
#
# Mechanically enforces the "thin delta" guarantee from docs/SPECIFICATION.md §3.3:
# this repo owns only a small, framework-free delta (compose/config/docs/one smoke
# script) and must never accumulate bespoke memory-engine (Neo4j) driver code or
# hand-written Cypher for memory operations outside the one known, legitimate
# exception (the verification bolt read in scripts/llm_smoke.py).
#
# Two checks, both scanning `git ls-files` (tracked/staged files only):
#   A. Inventory  — every tracked file must match the owned-delta allow-list.
#   B. Pattern    — every tracked *.py/*.ts/*.js/*.go file must not contain a
#                   memory-engine import or a memory-op Cypher clause opener,
#                   except the exact allow-listed path scripts/llm_smoke.py.
#
# Exit 0 when clean, 1 on any violation. Prints one line per violation:
#   <check>: <path>[:<line>] <reason>
#
# Pure bash + git + grep. No new dependencies.

set -u

violations=0

# --- Check A: file inventory allow-list -------------------------------------

# Allow-listed directory prefixes (any file under these paths is permitted).
allow_dir_prefixes=(
  ".agents/"
  ".github/"
  ".vscode/"
  "docs/"
)

# Allow-listed exact file paths.
allow_exact_files=(
  ".env.example"
  ".gitignore"
  "AGENTS.md"
  "docker-compose.yml"
  "docker/mcp.Dockerfile"
  "litellm/config.yaml"
  "scripts/llm_smoke.py"
  "scripts/check_thin_delta.sh"
)

is_allowed_path() {
  local path="$1"
  for prefix in "${allow_dir_prefixes[@]}"; do
    case "$path" in
      "$prefix"*) return 0 ;;
    esac
  done
  for exact in "${allow_exact_files[@]}"; do
    if [ "$path" = "$exact" ]; then
      return 0
    fi
  done
  return 1
}

file_count=0
while IFS= read -r path; do
  [ -z "$path" ] && continue
  file_count=$((file_count + 1))
  if ! is_allowed_path "$path"; then
    echo "inventory: ${path} unexpected file outside the owned-delta allow-list"
    violations=$((violations + 1))
  fi
done < <(git ls-files)

# --- Check B: memory-engine import / Cypher-clause pattern lint -------------

allowlisted_pattern_exception="scripts/llm_smoke.py"

# Patterns that indicate bespoke memory-engine driver usage or hand-written
# Cypher for memory operations.
pattern_regex='^[[:space:]]*(import neo4j|from neo4j)|GraphDatabase|MATCH \(|MERGE \(|CREATE \('

while IFS= read -r path; do
  [ -z "$path" ] && continue
  case "$path" in
    *.py|*.ts|*.js|*.go) ;;
    *) continue ;;
  esac
  if [ "$path" = "$allowlisted_pattern_exception" ]; then
    continue
  fi
  if [ ! -f "$path" ]; then
    continue
  fi
  while IFS=: read -r lineno line; do
    [ -z "$lineno" ] && continue
    echo "pattern: ${path}:${lineno} matches memory-engine import or Cypher clause opener (${line# })"
    violations=$((violations + 1))
  done < <(grep -nE "$pattern_regex" "$path")
done < <(git ls-files)

# --- Summary -----------------------------------------------------------------

if [ "$violations" -eq 0 ]; then
  echo "thin-delta: OK (${file_count} files scanned, 0 violations)"
  exit 0
else
  echo "thin-delta: FAIL (${file_count} files scanned, ${violations} violation(s))"
  exit 1
fi
