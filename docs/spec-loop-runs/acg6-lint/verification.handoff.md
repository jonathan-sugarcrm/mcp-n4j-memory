# Verification handoff — slice `acg6-lint`

## 1. Per-requirement verdict

| Req | Verdict | Check actually run | Observed result |
|-----|---------|---------------------|------------------|
| LINT-01 | **PASS** | `bash scripts/check_thin_delta.sh; echo $?` on the current, clean, tracked repo state. | `thin-delta: OK (54 files scanned, 0 violations)` / `EXIT:0`. Reproduced twice (before and after the LINT-02 cycle), identical output both times. |
| LINT-02 | **PASS** | Planted `scripts/_verify_probe.py` (`from neo4j import GraphDatabase` + `q = "MATCH (n) RETURN n"`), first ran the lint **unstaged** (untracked), then `git add`-ed it and re-ran, then removed it (`git reset` + `rm`) and re-ran once more. | Unstaged: `EXIT:0` (untracked files are invisible to `git ls-files` — the lint's dependence on tracked/staged state, exactly as the spec's LINT-02 precondition states). Staged: exits `1`, names the exact file and both offending lines (`scripts/_verify_probe.py:1` and `:4`), `thin-delta: FAIL (55 files scanned, 3 violation(s))`. Post-removal: back to `EXIT:0`, `54 files scanned, 0 violations`. |
| False-positive guard (`scripts/llm_smoke.py`) | **PASS** | Raw `grep -nE` with the lint's own combined pattern against `scripts/llm_smoke.py`, compared against a full lint run. | Raw grep independently matches 3 lines (`37: from neo4j import GraphDatabase`, `87: GraphDatabase.driver(`, `93: "MATCH (n) WHERE ..."`) — proving the patterns really do fire on this file. The full lint run (LINT-01 above) still reports `0 violations`, proving the exact-path allow-list is what suppresses these matches, not an accidental non-match. |
| Script structure (Check A / Check B present, exact-path allow-list, exit codes, per-violation output) | **PASS** | Read `scripts/check_thin_delta.sh` in full. | Implements Check A (`git ls-files` vs. `allow_dir_prefixes`/`allow_exact_files`) and Check B (`git ls-files` filtered to `*.py|*.ts|*.js|*.go`, `grep -nE` combined pattern, `scripts/llm_smoke.py` exact-path skip) exactly as specified in `specification.handoff.md` §4. Exits `0`/`1` correctly; one line per violation in `<check>: <path>[:<line>] <reason>` form. |
| Scope boundary — `docs/SPECIFICATION.md` untouched by this slice | **PASS** | `git diff docs/SPECIFICATION.md`, `git log --oneline -5`, and `ls -la scripts/check_thin_delta.sh` (mtime). | The only diff in `docs/SPECIFICATION.md` concerns the unrelated `extractor-wiring-fix` slice (env-mirror wiring decision, `create_llm_extractor()`), with no mention of AC-G6, thin-delta, or the lint. That diff pre-dates this slice (present before `check_thin_delta.sh` — created `Jul 14 15:44` — was written, and unrelated in subject matter). This slice's implementation touched exactly one file: `scripts/check_thin_delta.sh`. |

## 2. Missing evidence

None. All five checks above were independently reproduced from the current repo state,
including both the happy path and the failure path (LINT-02), and the failure-path
recovery (return to `EXIT:0` after removing the probe).

## 3. Regressions

None detected. This slice adds one new, additive, non-invoked-elsewhere script
(`scripts/check_thin_delta.sh`); nothing in the existing `docker-compose.yml`,
`litellm/config.yaml`, `scripts/llm_smoke.py`, or `.env.example` was touched (confirmed:
`git status --short` shows those files clean/unmodified by this slice; the only tracked
diff, `docs/SPECIFICATION.md`, belongs to a different, prior slice). No CI wiring exists
to regress (confirmed: no `.github/workflows/` directory).

## 4. Classified findings

Two robustness observations were investigated. Neither rises to a failure of a stated
LINT-01/LINT-02 acceptance criterion — both are recorded as findings for awareness, with
routing per the *Verification-failure classification* table.

### Finding 1 — Untracked/unstaged violations are invisible to the lint (usability characteristic, not a defect)
- **Type:** Unspecified behaviour (already anticipated and documented in the spec
  handoff's LINT-02 precondition — "is git-tracked (or staged) at scan time, since the
  lint scans `git ls-files`"). Not a new discovery; independently reproduced here
  (unstaged probe → `EXIT:0`; staged same probe → `EXIT:1`).
- **Classification:** Not a failure — this is the documented, deliberate scan boundary
  (`git ls-files`), consistent with Class 2 fact F2/F3 in the specification handoff (owned
  delta = tracked files). No routing action required; recorded for completeness per the
  task's request to "note this in your report as a usability characteristic."

### Finding 2 — Pattern lint (Check B) could over-match inside comments/strings, and under-match non-scanned file types
- **Observation:** `pattern_regex` will flag any line containing `MATCH (`, `MERGE (`, or
  `CREATE (` regardless of whether it's inside a comment, a docstring, or a string literal
  unrelated to Cypher (e.g. a code comment discussing SQL `CREATE (`). It also only scans
  `*.py|*.ts|*.js|*.go` — a memory-engine reference inside, say, a `.sh`, `.yaml`, or `.md`
  file (outside the deliberately-excluded `cypher-shell` healthcheck string already noted
  as F4) would not be caught by Check B, though Check A's file-inventory allow-list would
  still catch any genuinely new *file* outside the owned delta.
- **Verified as non-issue for this slice's stated scope:** Confirmed via a live test —
  planting `docs/spec-loop-runs/_probe_dir/sneaky.py` (a `.py` file with real violations)
  *inside* an allow-listed `docs/` prefix directory still triggered Check B failures
  (`EXIT:1`, both lines named) — Check B runs independently of Check A's directory
  allow-list, so disguising a violation under an allow-listed prefix does not evade
  detection for the file types the lint actually scans. Cleaned up after the test.
- **Classification:** `unspecified_behaviour` (Class 3 territory — a reversible,
  internal scan-scope choice already implicitly following the F2/F3 "owned delta is
  Python-only today" fact). Does not violate any stated LINT-01/LINT-02 criterion, since
  no acceptance criterion requires scanning non-code file types or suppressing comment
  false-positives; the specification handoff explicitly scoped Check B to
  `*.py`/`*.ts`/`*.js`/`*.go` (§4) and to "no such files exist today" for other languages.
  **Routing:** no action required to close this slice; worth a note in
  `docs/SPECIFICATION.md`'s §10 (or a follow-up slice) if the codebase later adds
  non-Python/TS/JS/Go memory logic, or if comment-level false positives start appearing in
  practice. Not blocking.

## 5. Overall verdict

**PASS.** LINT-01 and LINT-02 both reproduced with raw command output and exit codes on
the actual repo (not trusted from the implementation handoff); the false-positive guard on
`scripts/llm_smoke.py` was independently confirmed via a raw-grep-vs-lint-run comparison
proving suppression rather than absence of a match; the script's structure was read and
matches the specification's Check A/Check B design; `docs/SPECIFICATION.md` was confirmed
untouched by this slice (the only diff there belongs to the unrelated
`extractor-wiring-fix` slice, pre-dating this one). No regressions, no missing evidence,
no requirement failures. Two minor robustness findings recorded, both classified as
non-blocking (`unspecified_behaviour` / documented-by-design), routed as optional
follow-up notes rather than defects. The repo was left in its original clean state after
all probe files were removed.
