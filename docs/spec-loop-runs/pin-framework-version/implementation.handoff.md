# Implementation handoff — `pin-framework-version`

## 1. Implementation plan

1. `[Run PIN-01 happy-path dry-run resolve against the exact pin string in
   docker/mcp.Dockerfile:14]` -> verify: exit `0` and `Would install` output contains
   `neo4j-agent-memory-0.2.0`.
2. `[Run PIN-01 failure-path dry-run resolve against a non-existent version (==99.0.0)
   on the same extras]` -> verify: exit non-`0` and output contains `Could not find a
   version that satisfies the requirement`.
3. `[Compare PIN-01's result to docker/mcp.Dockerfile:14's current pin]` -> verify:
   `git diff -- docker/mcp.Dockerfile` before/after this pass is empty (no Dockerfile
   edit made, since PIN-01 passed on `0.2.0`).
4. `[Read litellm/config.yaml's model entries and compare against
   docs/SPECIFICATION.md:527-529 and :634-641]` -> verify: no contradiction found; no
   `litellm/config.yaml` edit made.
5. `[Clean up scratch install directories used by steps 1–2]` -> verify: `git status
   --porcelain` shows no leftover `pip-verify-scratch`/`pip-scratch` directory.

No dependency ordering beyond sequence above; all steps are read-only/verification
except the (not-triggered) conditional Dockerfile edit in step 3's branch.

## 2. Changed files

**None.** PIN-01 passed on the existing pin (`0.2.0`), so per PIN-02's expected
observable outcome ("if PIN-01 passes, no `docker/mcp.Dockerfile` change is required")
and the handoff's role-boundary note, no file was modified. `docker/mcp.Dockerfile`,
`litellm/config.yaml`, and `docs/SPECIFICATION.md` are all untouched by this
implementation pass (confirmed below).

## 3. Decision log

- Chose to run the PIN-01 dry-run scratch directory as `./pip-verify-scratch` (the
  exact path named in the specification handoff's mechanical-check table and
  Verification method text), over using the `pip-scratch/` name that literally matches
  `.gitignore:17`, because the handoff's mechanical check explicitly specifies
  `--target=./pip-verify-scratch` twice (§2 PIN-01 Verification method and §3 table)
  and the directory is deleted immediately after each run regardless of gitignore
  coverage, so the name mismatch has no observable effect (reversible, no contract
  impact) — see "Blocking spec defects" below for the minor inconsistency this
  surfaced (the handoff's own text incorrectly asserts `pip-verify-scratch` "is
  git-ignored via `.gitignore:<pip-scratch/ line>`", which is not literally true since
  the patterns differ).
- Chose not to create a `docs/SPECIFICATION.md` edit resolving §10's caveat or moving
  the item to "Resolved," over doing so directly, because the handoff's Explicit scope
  and Role-boundary note both state this is exclusively Reconciliation's (gate 6)
  responsibility — following the handoff's explicit instruction, not a discretionary
  choice.
- Chose not to touch `litellm/config.yaml` for PIN-03, over adding a comment
  documenting the "floating fact" policy, because the handoff's Expected observable
  outcome explicitly states this slice "makes no attempt to hard-pin ... and no config
  change expected" — the check is read-only by definition of the requirement.

## 4. Evidence bundle

| Requirement | Evidence | Result |
|---|---|---|
| **PIN-01 (happy path)** — `pip install --dry-run --target=./pip-verify-scratch "neo4j-agent-memory[mcp,sentence-transformers,openai]==0.2.0"` exits `0` and names `neo4j-agent-memory-0.2.0` in "Would install". | Command run from repo root, 2026-07-14. Raw output tail:<br>`EXIT_CODE=0`<br>`Would install Authlib-1.7.2 Jinja2-3.1.6 MarkupSafe-3.0.3 PyJWT-2.13.0 PyYAML-6.0.3 ... fastmcp-2.14.7 ... mcp-1.28.1 ... neo4j-6.2.0 neo4j-agent-memory-0.2.0 ... openai-2.45.0 ... sentence-transformers-5.6.0 ... torch-2.13.0 ... uvicorn-0.51.0 websockets-16.1`<br>(140 packages total in the "Would install" line; `grep -c "^Would install"` on the captured log = 1 matching line containing the full set, no resolution-conflict errors present in the 385-line log.) | **PASS** |
| **PIN-01 (failure path)** — same command with `==99.0.0` exits non-`0` and reports "Could not find a version that satisfies the requirement". | Command run from repo root immediately after the happy path, same extras, 2026-07-14. Raw output:<br>`EXIT_CODE=1`<br>`ERROR: Could not find a version that satisfies the requirement neo4j-agent-memory==99.0.0 (from versions: 0.0.1, 0.0.2, 0.0.3a1, 0.0.3, 0.0.4, 0.0.5, 0.1.0, 0.1.1, 0.1.2, 0.2.0, 0.2.1, 0.4.0, 0.5.0)`<br>`ERROR: No matching distribution found for neo4j-agent-memory==99.0.0` | **PASS** (proves the check has real discriminating power — not vacuously green) |
| **PIN-02** — `git diff -- docker/mcp.Dockerfile` is empty since PIN-01 passed on `0.2.0`. | `git diff -- docker/mcp.Dockerfile` run after both PIN-01 checks and scratch-dir cleanup, 2026-07-14: **empty output** (command produced no diff text). Current Dockerfile line 14 read directly:<br>`RUN pip install --no-cache-dir "neo4j-agent-memory[mcp,sentence-transformers,openai]==0.2.0"` — matches the exact pin string PIN-01 confirmed resolves. | **PASS** |
| **PIN-02 (scope)** — `git diff -- docs/SPECIFICATION.md` produced *by this implementation stage* is empty (any edit there is a process defect). | `git status --porcelain` before this pass already showed `M docs/SPECIFICATION.md` (pre-existing modification from prior, unrelated spec-loop slices in this repo's history, not from any command run in this implementation pass). No `edit`/`create` tool call was made against `docs/SPECIFICATION.md` during this implementation pass — zero write operations issued against that path. | **PASS** (no incremental edit attributable to this slice's implementation) |
| **PIN-03** — `litellm/config.yaml` model entries are internally consistent with §10's "floating fact, re-verified per run" policy (`docs/SPECIFICATION.md:527-529`, `:634-641`); no code output required or made. | Read `litellm/config.yaml`: `claude` → `openai/gpt-4o-mini` via GitHub Models; `claude-anthropic` → `anthropic/claude-sonnet-4-5`; `claude-mock` → `anthropic/claude-sonnet-4-5` with a `mock_response`. Read `docs/SPECIFICATION.md:527-529`: "The Anthropic model id is now treated as a **floating fact, re-verified per run**... — `litellm/config.yaml` currently pins `anthropic/claude-sonnet-4-5`." Read `docs/SPECIFICATION.md:634-641` ("Resolved: production Anthropic model id updated..."): confirms the prior `claude-3-5-sonnet-latest` was replaced with `claude-sonnet-4-5` and the id is "treated as a floating fact to be re-verified per run rather than an immutable literal." Both spec passages describe exactly what the config file contains — no contradiction. `git diff -- litellm/config.yaml`: empty. | **PASS** |

## 5. Blocking spec defects

None blocking. One minor, non-blocking inconsistency noted for awareness (does not
affect the outcome since the scratch dir is deleted after every run regardless):
the specification handoff's PIN-01 Verification method text asserts the
`./pip-verify-scratch` target directory "is git-ignored via `.gitignore:<pip-scratch/
line>`," but `.gitignore:17` literally reads `pip-scratch/`, which does not glob-match
a directory literally named `pip-verify-scratch`. This has no observable effect here
(the directory was created and removed within this same pass and never committed), so
it was not escalated as a blocking defect — recorded here only so it isn't silently
lost, per SPEC_LOOP.md's "every discovery lands in the spec" principle. Reconciliation
may fold a one-line note into the framework-pin caveat text at gate 6 if desired, but
this implementation pass does not touch `docs/SPECIFICATION.md`.

## 6. Summary of outcome

**CONFIRM-NO-CHANGE**, empirically reproduced: PIN-01's happy path resolves cleanly
(exit `0`, `neo4j-agent-memory-0.2.0` present, ~140 packages, no conflicts) and its
failure path genuinely fails (exit `1`, `Could not find a version that satisfies the
requirement`) on the same extras with a non-existent version, proving the check has
real discriminating power. `docker/mcp.Dockerfile` therefore required no edit
(`git diff` empty); `litellm/config.yaml` is internally consistent with §10's
floating-fact model-id policy and also required no edit. No `docs/SPECIFICATION.md`
edit was made by this implementation pass — that remains Reconciliation's (gate 6)
responsibility per the handoff's explicit role-boundary note.
