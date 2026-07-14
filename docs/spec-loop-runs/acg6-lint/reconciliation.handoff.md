# Reconciliation handoff — `acg6-lint`

**Authored by:** the Reconciliation agent (stage 4 / gate 6). Per the isolation contract,
this stage is the **only** one permitted to edit `docs/SPECIFICATION.md`; the edits described
below were made by this stage, not by Specification, Implementation, or Verification (which
correctly left the file untouched — confirmed by implementation.handoff.md §2: "`docs/
SPECIFICATION.md` was **not** edited (out of scope per the handoff's explicit boundary —
reserved for Reconciliation/gate 6)").

## 1. Overall verdict carried forward

**PASS** — LINT-01 and LINT-02 both independently reproduced from a clean state
(verification.handoff.md §5). No classified failures; no regressions. Two minor robustness
findings (untracked-file invisibility, pattern-lint over-match risk) both classified as
non-blocking (documented-by-design). The loop closes with spec edits only (no code-fix
routing required).

## 2. Spec edits made (diff summary)

| § | What changed | Answers |
|---|---|---|
| §9.2 AC-G6 Verification method | Rewritten from prose placeholder to mechanisable form: "Run `bash scripts/check_thin_delta.sh` from the repository root. The script mechanises the two checks that can be made evaluable: (a) a file-inventory check that every `git ls-files`-tracked path matches the §3.3 owned-delta allow-list, and (b) a pattern lint that fails on any tracked `*.py`/`*.ts`/`*.js`/`*.go` file containing a memory-engine driver reference (`import neo4j` / `from neo4j` / `GraphDatabase`) or a Cypher clause opener for a memory operation (`MATCH (`, `MERGE (`, `CREATE (`), exact-path allow-listing the one legitimate exception, `scripts/llm_smoke.py` (its direct-bolt-read verification step for R2). Exit `0` = the thin-delta guarantee holds; non-zero names the offending file(s)/line(s)..." plus a note on scan boundary and residual fallback to manual review. | LINT-01/LINT-02 happy-path and failure-path evidence; the "mechanisable" vs. "residual fallback" boundary (verification.handoff §4, finding 2). |
| §10 Resolved items — new entry (topmost, prepended) | Added "Resolved in `acg6-lint`: AC-G6's mechanisable portion is now enforced by an automated lint. Chose option (b) (a stricter automatable rule) over merely accepting the file-inventory-plus-review proxy. Added `scripts/check_thin_delta.sh` (pure bash + git + grep, no new deps): Check A asserts every `git ls-files`-tracked path matches the §3.3 owned-delta allow-list; Check B fails on any tracked `*.py`/`*.ts`/`*.js`/`*.go` file containing a memory-engine driver reference (`import neo4j` / `from neo4j` / `GraphDatabase`) or a Cypher clause opener (`MATCH (` / `MERGE (` / `CREATE (`), exact-path allow-listing the one legitimate exception `scripts/llm_smoke.py`. Exit `0` = clean; non-zero names the offending file/line. Independently verified from a clean state: happy path exits `0` (54 files scanned); a planted violation — including one disguised under the allow-listed `docs/` prefix — exits non-zero and names the file; `scripts/llm_smoke.py` is correctly suppressed by the allow-list (the patterns DO match there on a raw grep, so it is suppressed, not accidentally non-matching). AC-G6's Verification method (§9.2) now runs this lint. **Known limitations (recorded so they aren't rediscovered):** the lint scans `git ls-files`, so untracked/unstaged files are invisible to it (deliberate scan boundary); and Check B could over-match a pattern inside a comment/string or miss memory logic in non-scanned file types — manual review remains the fallback for that irreducible residual, which AC-G6 cannot fully mechanise." | LINT-01/LINT-02 evidence; the decision-of-record (option b, stricter automatable rule); verification.handoff §4 findings 1 & 2 (scan boundary and over-match risk). |

No other sections were touched. No new documents were created besides this handoff.

## 3. Defects/findings folded → where they landed

| Verification finding | Classification | Landed in spec at |
|---|---|---|
| LINT-01 happy-path evidence (clean repo, exit `0`, 54 files scanned, 0 violations) | requirement met, evidence bundle | §9.2 AC-G6 Verification method ("independently verified from a clean state: happy path exits `0` (54 files scanned)") and §10 Resolved-items entry |
| LINT-02 failure-path evidence (planted violation detected and named, exact line numbers, exit non-zero, then recovery to exit `0`) | requirement met, evidence bundle | §9.2 AC-G6 Verification method / §10 Resolved-items ("a planted violation — including one disguised under the allow-listed `docs/` prefix — exits non-zero and names the file") |
| `scripts/llm_smoke.py` false-positive guard (raw grep shows 3 pattern matches; full lint run reports 0 violations — suppression works, not accidental non-match) | requirement met, evidence bundle | §10 Resolved-items entry ("`scripts/llm_smoke.py` is correctly suppressed by the allow-list (the patterns DO match there on a raw grep, so it is suppressed, not accidentally non-matching)") |
| Untracked/unstaged violations are invisible to the lint (deliberate scan boundary, not a defect) | usability characteristic, documented-by-design (Class 2, fact F2/F3) | §10 Resolved-items known-limitations ("the lint scans `git ls-files`, so untracked/unstaged files are invisible to it (deliberate scan boundary)") |
| Pattern lint (Check B) could over-match inside comments/strings, or under-match non-scanned file types (residual fallback to manual review) | not-a-failure, Class 3 unspecified behaviour, falls within AC-G6's stated residual | §10 Resolved-items known-limitations ("Check B could over-match a pattern inside a comment/string or miss memory logic in non-scanned file types — manual review remains the fallback for that irreducible residual, which AC-G6 cannot fully mechanise") |

Every result has moved either to the spec (all findings above) or was explicitly confirmed as
not requiring a code or spec change (none in this slice). No result was left as a bare note.

## 4. Authorship boundary clarification

- **Implementation** (`acg6-lint` implementation stage): Created `scripts/check_thin_delta.sh`
  only; did **not** touch `docs/SPECIFICATION.md`.
- **Verification** (`acg6-lint` verification stage): Ran the lint against the current repo
  state and confirmed happy/failure paths; did **not** touch `docs/SPECIFICATION.md`.
- **Reconciliation** (this stage, gate 6): Rewrote AC-G6's Verification method in §9.2
  (from prose-only to mechanisable lint invocation) and moved the §10 open item (AC-G6 being
  "only partly mechanisable") to Resolved items with the decision-of-record (option b, lint
  enforcement) and known limitations. **This stage alone edited `docs/SPECIFICATION.md`.**

## 5. Next slice(s), priority order

1. **`pin-framework-version`** — highest priority, unblocked. Confirm and pin the exact
   `neo4j-agent-memory` version (currently a floating dependency in `docker/mcp.Dockerfile`
   with placeholder `==0.2.0`) and the exact production Anthropic model id (currently a
   floating fact, re-verified per run, with placeholder `anthropic/claude-sonnet-4-5` in
   `litellm/config.yaml`). Both must be confirmed/locked before any release or wider
   deployment.

2. **Blocked slices (require external credentials, lower priority):**
   - **`prod-anthropic-verify`** — requires a real `sk-ant-api…` Anthropic API key (not
     available). Deferred opportunistically; GitHub Models now provides a working,
     supported production LLM backend, so this is no longer blocking any capability — it
     only completes symmetry with the originally-scoped Anthropic-specific criterion.
   - **`scope-github-token`** — the `acg6-lint` slice and all prior real-backend
     verifications used a broad `gh`-CLI OAuth token as `GITHUB_API_KEY` for GitHub
     Models, acceptable only for one-off local passes; any persistent/production use must
     swap to a fine-grained GitHub PAT scoped to `models: read` only. Blocked on
     provisioning a scoped token.
