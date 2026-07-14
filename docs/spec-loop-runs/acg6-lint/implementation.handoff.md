# Implementation handoff — slice `acg6-lint`

## 1. Implementation plan

1. `[Create scripts/check_thin_delta.sh implementing Check A (inventory) + Check B
   (pattern lint) per specification.handoff.md §4]` -> verify: LINT-01 (clean-repo happy
   path, exit 0).
2. `[chmod +x scripts/check_thin_delta.sh]` -> verify: script is directly executable via
   `./scripts/check_thin_delta.sh` and via `bash scripts/check_thin_delta.sh`.
3. `[Plant a violation file outside the allow-list, git-add it, run the lint, assert
   non-zero exit naming the file, then remove it and re-run]` -> verify: LINT-02
   (fail-then-recover path).
4. `[Confirm scripts/llm_smoke.py's real neo4j import / MATCH clause is not flagged]` ->
   verify: raw grep shows 3 pattern matches in that file, yet the full lint run reports 0
   violations (exact-path allow-list proven to work, not just asserted).

No dependencies between steps beyond strict ordering (script must exist before it can be
run/tested).

## 2. Changed files

| Path | Reason |
|------|--------|
| `scripts/check_thin_delta.sh` | New file. Implements the AC-G6 thin-delta lint (Check A: `git ls-files` inventory vs. owned-delta allow-list; Check B: memory-engine import / Cypher-clause-opener pattern scan with the `scripts/llm_smoke.py` exact-path exception), per specification.handoff.md §4. Traces to LINT-01 and LINT-02. |

No other files were touched. `docs/SPECIFICATION.md` was **not** edited (out of scope per
the handoff's explicit boundary — reserved for Reconciliation/gate 6). Note:
`docs/SPECIFICATION.md` was already modified in the working tree before this session
started (pre-existing, unrelated local diff) — left untouched by this slice.

## 3. Decision log

- Chose to add `scripts/check_thin_delta.sh` itself as an exact-path allow-list entry
  (Check A) over leaving it unlisted, because once this script is committed it becomes a
  tracked file like any other; without self-allow-listing, the lint would immediately flag
  its own file as "unexpected" the moment it's added to git, which is a self-inconsistent
  outcome the handoff's F2 inventory (captured pre-slice) couldn't have anticipated.
  Reversible/no-contract-impact: it's an internal allow-list entry, not an externally
  observable behavior change.
- Chose to allow-list `docs/`, `.agents/`, `.github/`, `.vscode/` as directory *prefixes*
  (rather than enumerating every file under them) because the handoff's F2 fact explicitly
  characterizes `docs/**` as "process/spec documentation, not an application artifact" that
  is tracked but out of the lint's concern, and the same reasoning extends to the other
  meta/config directories already enumerated in F2's 15-file inventory (skill docs, IDE
  config, CI-adjacent instructions). This follows the handoff's own classification rather
  than inventing a new one — no product/contract impact, purely an internal scan-scope
  choice.
- Chose `grep -nE` with a single combined pattern
  (`import neo4j|from neo4j|GraphDatabase|MATCH \(|MERGE \(|CREATE \(`) over one `grep`
  invocation per pattern because it is the minimal-dependency, single-pass way to satisfy
  "pure bash + git + grep, no new deps" while producing per-line violation output; no
  observable behavior difference from running the patterns separately.
- Chose to test the failure path by `git add`-ing the planted probe file (not just leaving
  it untracked) because the specification handoff's own LINT-02 verification method
  explicitly requires this ("`git add` it (lint scans tracked/staged files)"), and the
  script scans `git ls-files`, which only reports tracked/staged paths — an untracked probe
  would silently pass through both checks without exercising the failure behavior at all.

## 4. Evidence bundle

| Requirement | Evidence | Result |
|-------------|----------|--------|
| **LINT-01** — script exits `0` on the clean repo, prints a single-line summary, no violation lines. | Command: `bash scripts/check_thin_delta.sh; echo "EXIT:$?"` (run twice: once before the LINT-02 cycle, once immediately after removing the planted probe — both reproduced below). Run 1 (pre-plant):<br>`thin-delta: OK (54 files scanned, 0 violations)`<br>`EXIT:0`<br>Run 2 (post-plant-removal, reproduced fresh):<br>`thin-delta: OK (54 files scanned, 0 violations)`<br>`EXIT:0` | **PASS** |
| **LINT-02** — planting a disallowed file with a memory-engine import and a Cypher clause makes the lint exit non-zero and name the exact file; removing it restores exit `0`. | Planted `scripts/_lint_probe.py` containing:<br>`from neo4j import GraphDatabase`<br>`    q = "MATCH (n) RETURN n"`<br>staged with `git add scripts/_lint_probe.py`, confirmed present via `git ls-files \| grep probe` → `scripts/_lint_probe.py`.<br>Ran `bash scripts/check_thin_delta.sh; echo "EXIT:$?"` → raw output:<br>`inventory: scripts/_lint_probe.py unexpected file outside the owned-delta allow-list`<br>`pattern: scripts/_lint_probe.py:1 matches memory-engine import or Cypher clause opener (from neo4j import GraphDatabase)`<br>`pattern: scripts/_lint_probe.py:4 matches memory-engine import or Cypher clause opener (   q = "MATCH (n) RETURN n")`<br>`thin-delta: FAIL (55 files scanned, 3 violation(s))`<br>`EXIT:1`<br>Removed via `git reset scripts/_lint_probe.py && rm -f scripts/_lint_probe.py`, confirmed `git status --short` no longer lists it, then re-ran the lint (see LINT-01 Run 2 above) → `EXIT:0`. | **PASS** |
| **False-positive guard on `scripts/llm_smoke.py`** (explicitly called out by the handoff as the one legitimate exception to verify). | Raw `grep -nE '^[[:space:]]*(import neo4j\|from neo4j)\|GraphDatabase\|MATCH \(\|MERGE \(\|CREATE \(' scripts/llm_smoke.py` → shows 3 real matches:<br>`37:from neo4j import GraphDatabase`<br>`87:    driver = GraphDatabase.driver(`<br>`93:                "MATCH (n) WHERE n.content CONTAINS $marker "`<br>Yet the full lint run (LINT-01, both runs above) reports `0 violations` — proving the exact-path allow-list actively suppresses these 3 would-be matches rather than the file simply never containing the pattern. | **PASS** |

## 5. Blocking spec defects

None. The handoff's five-field criteria (LINT-01, LINT-02), allow-list (F2), pattern set,
and the `scripts/llm_smoke.py` exception were all directly implementable with no
ambiguity, contradiction, or empty field. The one gap the handoff's F2 inventory could not
have covered — the lint script's own path becoming a new tracked file — was resolved as a
Class 3 safe choice (§3, decision log) rather than reported as a defect, since it changes
no externally observable behavior and is reversible.
