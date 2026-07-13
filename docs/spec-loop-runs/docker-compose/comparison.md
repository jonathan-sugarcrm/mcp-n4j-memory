# Exercise result — single agent vs separated roles

Slice id: **`docker-compose`** (author `docker-compose.yml`: 3 services, 2 segmented
networks, named neo4j volume). Scored per `.agents/skills/spec-loop/exercise/comparison-template.md`.

- **Run A (single agent):** one context interpreted → implemented → self-judged in a
  single pass. Output: `run-a-single/docker-compose.yml` + `run-a-single/self-report.md`.
  Self-declared verdict: **PASS**.
- **Run B (separated roles):** stages 1→4, artifact-only handoffs. Output: repo-root
  `docker-compose.yml` + `{specification,implementation,verification,reconciliation}.handoff.md`.
  Independent verifier verdict: **PASS**.

All scoring below was produced by an independent audit (orchestrator) that re-ran the
*same* mechanical checks against **both** compose files and inspected each by eye.

## Scorecard

| Metric | Count method | Run A (single) | Run B (separated) |
|--------|--------------|:--------------:|:-----------------:|
| **Defect detection** (real defects surfaced *before* "done") | spec + impl defects the run itself surfaced | **0** | **1** (proved all 3 checks fail-closed via mutation; surfaced 0 residual impl defects) |
| **Reproducibility defects found on independent audit** | issues an outside party hits that the run declared PASS on | **1** (bare `docker compose config` fails — needs env) | **0** (renders bare, exit 0) |
| **Latent spec-criteria defects found on independent audit** | criteria that pass a worse config | **n/a** (no criteria authored) | **1** (AC-DC3 never asserts loopback bind host) |
| **Rework** (slice reopened after "done") | re-runs after a done claim | 0 | 0 |
| **Unsupported assumptions** | Class-3+ choices with no recorded rationale, or a pass claim with no reproducible/teeth-proven evidence | **2** | **0** |
| **Escaped defects** (found only after "success") | lower is better | **1** (non-reproducible render) | **1** (bind-host gap) |

### Evidence

- **Run B renders with zero setup:** `docker compose config --quiet` → exit `0`.
  **Run A does not:** `docker compose -f run-a-single/docker-compose.yml config` →
  `required variable NEO4J_PASSWORD is missing a value` (exit `1`). Run A's self-report
  claims "This rendered successfully" — true only because it silently injected dummy env.
  Run B's Stage-1 spec *required* deterministic bare rendering, so Stage 2 used
  `${VAR:-default}` and the PASS reproduces with no operator setup.
- **Check teeth:** Run B's Stage-3 verifier mutated the file three ways (removed the
  named volume; cross-attached `neo4j` to `llm-net`; injected `ANTHROPIC_API_KEY` into
  `mcp`) and confirmed each assertion exits non-zero — proving the checks can fail. Run A
  wrote assertions over its own file but never failure-tested them, so their "pass" is
  unproven (could be vacuous).
- **Both structurally correct:** with env supplied, Run A's compose passes the same
  AC-DC1/2/3 assertions Run B passes (exactly 3 services; `db-net`/`llm-net` internal &
  disjoint; only `mcp` bridges; allow-listed ports; `ANTHROPIC_API_KEY` absent from
  `mcp`). This slice is small and well-specified, so the *code* converged.

## Where the single agent's self-judgement diverged from independent judgement

- Run A declared **PASS** while its config **cannot be rendered** by
  `docker compose config` without the operator exporting secrets first — the exact "config
  lint validates" verification method in §9. Its self-verification masked this by supplying
  env it never flagged as a prerequisite of the claim. This is the confirmation-bias
  signature: the context that wrote the file also chose the validation conditions that made
  it pass.

## Assumptions forced into the open by the artifact boundary (Run B) vs silent in Run A

- The `${VAR:-default}` vs `${VAR:?required}` choice: in Run B it was a **recorded Class-3
  decision at Stage 1** ("rendered config must deterministically satisfy the checks"), so
  it crossed into implementation as an explicit contract. In Run A the equivalent choice
  (`:?required`) was made silently and only its *symptom* (needs env) appeared, buried in a
  self-report the same agent wrote.

## Honest counter-findings (the separation is not free or perfect)

- **Run A made the safer port choice.** It bound published ports to `127.0.0.1`
  (loopback-only); Run B publishes on the default `0.0.0.0`. Per AC-C4 intent ("no default
  public exposure"), Run A is stricter.
- **Run B's pipeline also missed a spec defect:** AC-DC3 only compares the *published port
  number set*, never the bind host, so Run B's more-exposed `0.0.0.0` config passed its own
  verifier. This is a **specification defect** discovered post-hoc — it routes back to
  **Stage 1** to tighten AC-DC3 to assert loopback binding. (Logged as a follow-up; see
  §Next.)
- **Cost:** Run B used 4 agent passes + 4 handoff artifacts vs Run A's single pass. For a
  slice this small and well-specified, the *implementation* converged either way; the
  measurable gains were in **verification reproducibility and teeth**, not in the code.

## Net conclusion

On this slice both agents produced structurally correct compose files — the code converged
because the slice was small and tightly specified. The value of separation showed up **in
verification quality, not implementation**:

- Run B's PASS is **reproducible with zero setup** and **teeth-proven** (checks demonstrated
  able to fail). Run A's PASS is **non-reproducible** (needs undocumented env) and **unproven**
  (checks never failure-tested) — classic self-graded homework.
- Separation did **not** make the pipeline infallible: it shipped a real spec-criteria gap
  (bind host) that a single sharper reviewer (Run A) happened to avoid. The lesson is that the
  boundary raises *verification rigor and reproducibility*, but criteria quality at Stage 1
  still bounds what any downstream stage can catch.

## Next

- Route the AC-DC3 bind-host gap back to **Stage 1** in the next pass (tighten AC-DC3 to
  assert `127.0.0.1` / non-`0.0.0.0` publishing), then re-run Stages 2–3.
- Recommended next slice remains **`stack-up`** (runtime probes) per the reconciliation
  handoff.
