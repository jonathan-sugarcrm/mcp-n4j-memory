# Baseline findings — loop-efficiency invariants (I1–I6)

Companion to `invariant-evaluation.md`. Records the **baseline (Run-A) metrics** measured
from a real multi-slice session and the **extrapolated improvement** per invariant, which
motivated adopting I1–I6 as gate exit-conditions in `docs/SPEC_LOOP.md`.

- **Source:** one session's event log — 6 spec-loop slices, **56.07M sub-agent tokens**
  (≈ 9.34M tokens/slice). Figures are sub-agent tokens only (main-thread excluded).
- **Method:** six parallel probes, each computing its metric from the log and proving its
  hardened gate fires on a trap fixture (mutation/teeth test). All gates fired.

## Baseline per invariant

| Inv | Target failure (where observed) | Baseline cost | Incidence |
|-----|----------------------------------|---------------|-----------|
| **I1** single-writer | spec handoff assigns a `SPECIFICATION.md` edit to Implementation → `contradictory_requirement` + gate-1 fix agent (`mcp-env-cleanup`, `extractor-wiring-fix`) | **277,167 tok** (2 fix agents) | 2 of 6 slices |
| **I2** precondition gate | wrong-*kind* credential (OAuth token, not API key) → full stack brought up + API retried before detection (`prod-anthropic-verify`) | **13,168,003 tok = 23.5% of session** | 1 of 2 credentialed slices |
| **I3** artifact-completion | stage truncated — produced only part of its declared artifacts (`g6-reconcile`) | **646,001 tok** recovery (1.09M total for one stage) | 1 of 24 stages |
| **I4** amend-then-realign | amended upstream artifact left a stale, contradicting downstream one → extra re-verifications (`mcp-env-cleanup`, 3 passes) | **1,572,863 tok** (2 extra passes) | 1 of 6 slices |
| **I5** scope discipline | implementation applied out-of-scope changes silently (`prod-impl`: `--detailed_debug`, model-id bump, extractor env) | verifier triage overhead | 3 diffs in 1 slice |
| **I6** stage-cost | confirm-only slice ran full 4-context Sonnet rigor (`pin-framework-version`) | **2,664,549 tok** (LIGHT lane saves ~60%) | 1 of 6 slices |

## Extrapolated improvement

| Inv | Cost per occurrence | Extrapolated (per 10 slices) | Type |
|-----|--------------------:|------------------------------:|------|
| **I2** | 13.17M tok | tail-risk — see note | one-time / catastrophic |
| **I6** | ~1.6M tok saved | ~2.67M | recurring |
| **I4** | 1.57M tok | ~2.62M (overlaps I1) | recurring* |
| **I3** | 0.65M tok | ~1.08M | recurring |
| **I1** | 0.14M tok/occ | ~0.46M | recurring* |
| **I5** | not token-bucketed | avoided triage + escaped-bug risk | recurring |

- **Structural (recurring) total — I1+I3+I4+I6 ≈ 6.83M tok per 10 slices ≈ 7.3% of
  workload** — durable, near-zero gate cost (each gate is a ~5-line check).
- **I2 is a tail-risk guard**, not a per-slice rate: magnitude fixed and large (≈ one
  wrecked slice), frequency uncertain. Observed 1 wrong-kind credential in 2 credentialed
  slices; per-10-slice value ranges ~2.6M (rare, 1-in-50) to ~22M (1-in-6) to dominant
  (1-in-2). Adopt regardless — the check is trivial and the downside is catastrophic.
- **I1 ↔ I4 overlap:** the extra re-verifications (I4) were *caused* by an I1-class boundary
  defect. Treat the boundary family (I1+I4) as ~2.6–3.1M/10 slices combined, not additive.

## Caveats

Single-session sample (n=6 slices); sub-agent tokens only; `r1-retry` had no discrete
record, making I2's 23.5% a conservative floor. These are **Run-A baselines + isolated
gate prototypes**, not a full Run-B end-to-end trap battery — the definitive verdict
(including the must-not-regress guardrail columns: defect detection, reproducibility) needs
a Run-B pass per `invariant-evaluation.md`.

## Adoption

All six are encoded as gate exit-conditions in `docs/SPEC_LOOP.md` §"Loop-efficiency
invariants (I1–I6)", with I1 also in `specification-agent/SKILL.md` and I1/I2/I5 in
`implementation-agent/SKILL.md`.
