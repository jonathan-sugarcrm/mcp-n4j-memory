# Specification handoff — slice `acg6-lint`

## 1. Slice

`acg6-lint` — Strengthen AC-G6's verification method (docs/SPECIFICATION.md:508-510) from
a purely-manual "scripted inventory + review" proxy to a deterministic, automatable lint
that mechanically enforces the thin-delta guarantee (no bespoke memory-engine import or
hand-written Cypher-for-memory outside the framework), while correctly excluding the one
legitimate exception already in the repo: the verification bolt read in
`scripts/llm_smoke.py`.

## 2. Normalized requirements

### LINT-01 — Thin-delta lint passes on the current, clean repo state
- **Trigger:** `scripts/check_thin_delta.sh` is run from the repository root (no arguments).
- **Preconditions:**
  - Repo is at its current tracked state (`git ls-files` output as of this handoff — see
    inventory below).
  - The only tracked Python source in the repo is `scripts/llm_smoke.py`
    (`git ls-files -- '*.py'` confirmed to return exactly that one path at investigation
    time — see §6, fact F1).
- **Expected observable outcome:** The script exits `0` and prints a single-line summary
  (e.g. `thin-delta: OK (N files scanned, 0 violations)`). No output line reports a
  violation.
- **Failure behaviour:** N/A for this requirement's happy path — covered by LINT-02.
- **Verification method:** Run `bash scripts/check_thin_delta.sh` from repo root; assert
  exit code `0`; capture stdout as evidence.
- **Traces to:** G6 (`docs/SPECIFICATION.md:47`), AC-G6 (`docs/SPECIFICATION.md:500-510`).

### LINT-02 — Thin-delta lint fails deterministically on a planted violation
- **Trigger:** A file is added to the repo, outside the allow-list defined in §4/§6, that
  either (a) imports a memory-engine driver (`import neo4j` / `from neo4j import ...`) or
  references `GraphDatabase`, or (b) contains a hand-written Cypher clause for memory
  operations (a line matching `MATCH (`, `MERGE (`, or `CREATE (` outside the one allowed
  location). `scripts/check_thin_delta.sh` is then run.
- **Preconditions:** The planted file is not `scripts/llm_smoke.py` (the sole allow-listed
  exception) and is git-tracked (or staged) at scan time, since the lint scans
  `git ls-files`.
- **Expected observable outcome:** The script exits non-zero (`1`) and prints the exact
  offending file path and line number(s) that triggered the failure.
- **Failure behaviour:** This *is* the failure-path exercise — the "failure" is the
  expected, correct outcome. The planted file must be removed after the check so the
  repo returns to its clean, passing state (LINT-01 re-verified).
- **Verification method:** Create a throwaway file (e.g. `docker/_lint_violation_test.py`
  containing `from neo4j import GraphDatabase` and a line `MATCH (n) RETURN n`), `git add`
  it (lint scans tracked/staged files), run `bash scripts/check_thin_delta.sh`, assert
  non-zero exit and that stdout/stderr names `docker/_lint_violation_test.py`. Then
  `git rm --cached` / delete the file and re-run LINT-01's check to confirm it returns to
  exit `0`.
- **Traces to:** G6 (`docs/SPECIFICATION.md:47`), AC-G6 failure behaviour
  (`docs/SPECIFICATION.md:505-506`: "Introduction of custom memory logic ... is treated as
  a spec violation").

## 3. Verification criteria

| Req | Mechanical check | Pass condition |
|-----|-------------------|-----------------|
| LINT-01 | `bash scripts/check_thin_delta.sh; echo $?` on clean repo | Exit code `0`; no violation lines in stdout |
| LINT-02 | Plant violation file → run lint → assert failure → remove file → re-run lint | First run: exit code ≠ `0` and output names the planted file; second run (after removal): exit code `0` |

Both checks together are what AC-G6's verification method (docs/SPECIFICATION.md:508-510)
should invoke going forward; see §5 for the boundary on who may edit that line.

## 4. Explicit scope

**In scope (Implementation stage, gates 3–4):**
- Create `scripts/check_thin_delta.sh` (or equivalent single executable script) that
  performs two checks in one run:
  1. **File-inventory check:** every path returned by `git ls-files` must match one of the
     §3.3-derived allow-list patterns (see §6, fact F2 for the exact list). Any tracked
     file outside the allow-list is reported as a violation.
  2. **Pattern lint:** every tracked file matching `*.py` (and, for forward-compatibility,
     `*.ts`/`*.js`/`*.go` should the delta ever grow one) is scanned for:
     - `import neo4j` / `from neo4j` / `GraphDatabase` (memory-engine driver reference), or
     - a Cypher clause opener for a memory op: `MATCH (`, `MERGE (`, `CREATE (`.
     A match is a violation **unless** the file is the single allow-listed exception,
     `scripts/llm_smoke.py` (permitted because it performs the legitimate verification bolt
     read for AC-G2/R2 — `docs/SPECIFICATION.md` §9, and `scripts/llm_smoke.py:86-93`).
  - Script prints one line per violation (`<check-name>: <path>[:<line>] <reason>`) and a
    final summary line, then exits `0` if zero violations else `1`.
  - Script has no new runtime dependencies (pure `bash` + `git` + `grep`, matching what's
    already available in this environment) so it can run in CI or locally with no install
    step.
- Exercise both the happy path (LINT-01) and the failure path (LINT-02) as evidence in
  `implementation.handoff.md`.

**Out of scope (explicitly NOT for Implementation):**
- **Any edit to `docs/SPECIFICATION.md`.** Rewriting AC-G6's verification method text
  (docs/SPECIFICATION.md:508-510) to reference `scripts/check_thin_delta.sh`, and moving
  the §10 open item (docs/SPECIFICATION.md:513-516) to a resolved/closed state, are
  **Reconciliation-stage actions (gate 6) only**. Implementation must create/modify the
  lint script and nothing else that touches `docs/`.
- Wiring the lint into CI (`.github/workflows/*`) — no workflow files exist in this repo
  today (confirmed: `.github/` contains only `copilot-instructions.md`); adding one is a
  separate concern not required to satisfy AC-G6 and is not requested by this slice.
- Extending the lint to non-Python languages beyond the forward-compatible glob already
  specified — no such files exist today, so nothing to test against.
- Changing the existing framework-provided memory logic (§3.2) — the lint only scans
  **our owned delta** (git-tracked files), never framework/library code (which is not
  vendored — NG2).

## 5. Unresolved decisions

None — cleared at gate 2. The ACCEPT-vs-LINT choice from the §10 open item
(docs/SPECIFICATION.md:513-516) was classified **Class 3** (safe, reversible,
no-external-impact engineering choice), not Class 1: it changes no externally observable
behaviour, contract, or scope — it only strengthens an *internal* verification mechanism
that today already relies on manual review. It is a two-way door (the lint script can be
loosened, tightened, or removed later with no migration cost). See §6 for the recorded
rationale.

## 6. Recorded facts & safe choices

**Class 2 facts (investigated):**
- **F1 — Owned Python is exactly one file.** `git ls-files -- '*.py'` returns only
  `scripts/llm_smoke.py`. It legitimately imports `neo4j`/`GraphDatabase`
  (`scripts/llm_smoke.py:37`) and issues a real Cypher `MATCH` clause
  (`scripts/llm_smoke.py:93`, `"MATCH (n) WHERE n.content CONTAINS $marker "`) as the
  direct-bolt-read verification step for R2 (docs/SPECIFICATION.md §9). This is the
  concrete false-positive case the lint must allow-list, confirming the task's stated
  concern is real and must be handled explicitly, not accidentally avoided.
- **F2 — Full tracked-file inventory (git ls-files, 15 files):**
  `.agents/skills/spec-loop/SKILL.md`,
  `.agents/skills/spec-loop/exercise/comparison-template.md`,
  `.agents/skills/spec-loop/implementation-agent/SKILL.md`,
  `.agents/skills/spec-loop/reconciliation-agent/SKILL.md`,
  `.agents/skills/spec-loop/specification-agent/SKILL.md`,
  `.agents/skills/spec-loop/verification-agent/SKILL.md`, `.env.example`,
  `.github/copilot-instructions.md`, `.gitignore`, `.vscode/mcp.json`, `AGENTS.md`,
  `docker-compose.yml`, `docker/mcp.Dockerfile`, `litellm/config.yaml`,
  `scripts/llm_smoke.py`. (`docs/**` is also tracked but is process/spec documentation,
  not an application artifact — see next fact.) This confirms the owned delta is tiny
  (5 non-meta artifacts: Dockerfile, LiteLLM config, compose file, env example, one smoke
  script) — a scan of this size costs nothing to run on every check.
- **F3 — No CI workflow exists yet.** `.github/` contains only `copilot-instructions.md`;
  there is no `.github/workflows/` directory. The lint therefore has nothing to wire into
  automatically today; it must be runnable as a standalone local command
  (`bash scripts/check_thin_delta.sh`) so AC-G6's verification method can invoke it
  directly, independent of CI.
- **F4 — `docker-compose.yml:8` contains the substring `cypher-shell` (a healthcheck
  command name, not a memory-op Cypher clause: `cypher-shell -u neo4j -p ... 'RETURN 1'`).
  This is a liveness probe, not memory logic, and is not a `.py`/`.ts`/`.js`/`.go` file, so
  it falls outside the pattern-lint's scanned file types and is a non-issue — recorded here
  so Implementation doesn't mistake it for something the lint must special-case.

**Class 3 safe choices (decided and recorded):**
- **Chose LINT over ACCEPT** because the owned delta is small enough (one Python file) that
  a pattern lint costs almost nothing to write, run, and maintain, while it converts AC-G6's
  verification from "relies on review" to "mechanically fails on the exact regression the
  criterion cares about" (a stray memory-engine import/Cypher call) — directly closing the
  §10 gap. Reversible: if it ever proves noisy, it can be deleted with no downstream
  contract effect.
- **Chose a `bash` + `grep` script over a Python script** because the repo has zero
  runtime Python dependencies of its own (the only Python is a smoke-test script that
  depends on `fastmcp`/`neo4j` packages meant for a running stack, not for linting); a
  dependency-free bash script can run in any environment without a venv, following the
  "no bespoke ... logic" spirit of G6 itself.
- **Chose `git ls-files` (not `find`) as the scan source** because it already matches what
  "owned/tracked" means in this repo (untracked scratch, e.g. `pip-scratch/`, is
  `.gitignore`'d — `.gitignore:14`) and requires no additional exclude-list maintenance.
- **Chose to allow-list `scripts/llm_smoke.py` by exact path** (not by heuristic, e.g.
  "files under `scripts/`") because it is the one specific, known, legitimate exception
  today; an exact-path allow-list is the smallest safe carve-out and forces any *new*
  script added later to be deliberately reviewed and added to the allow-list rather than
  silently inheriting an exemption via directory location.
