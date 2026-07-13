# Exercise: single agent vs separated roles

Purpose: make the value of role separation **measurable**, not asserted. Run the same
slice both ways and fill this scorecard.

## Protocol

1. **Pick one slice** from `docs/SPECIFICATION.md` §3.3. Use the *same* slice for both
   runs. Record its id: `__________`.
2. **Run A — single agent.** One context does interpret → implement → self-judge in a
   single uninterrupted pass. It declares its own pass/fail. Save its output under
   `docs/spec-loop-runs/<slice-id>/run-a-single/`.
3. **Run B — separated roles.** Execute stages 1→2→3→4 with artifact-only handoffs
   (`/specification-agent`, `/implementation-agent`, `/verification-agent`,
   `/reconciliation-agent`), each in a fresh context. Artifacts land in
   `docs/spec-loop-runs/<slice-id>/`.
4. **Record the verification contract for each run.** Alongside its pass/fail claim,
   every run MUST write down the *exact* verification command(s), the working
   directory they were run from, and any env/setup they required. A pass claim that
   omits this is not reproducible and scores as a reproducibility defect (below).
5. **Reproduce each declared PASS from a clean state.** As the independent auditor,
   re-run *only* the verification command each run documented — from a clean checkout,
   with nothing but the env/setup that run wrote down. Anything that then fails, or
   needs an undocumented step, is a reproducibility defect the run masked.
6. **Prove the checks have teeth.** For each pass-criterion, mutate the artifact so the
   check *should* trip (e.g. delete the volume, cross-wire a network, inject a
   forbidden secret) and confirm it exits non-zero. A criterion never shown able to
   fail is unproven — its "pass" may be vacuous.
7. **Score both** with the table below. Count from the artifacts, not from memory.

## Scorecard

| Metric | Definition (how to count) | Run A (single) | Run B (separated) |
|--------|---------------------------|:--------------:|:-----------------:|
| **Defect detection** | # real defects surfaced *before* the slice was called done — count spec defects + implementation defects. Verify each is real (reproducible), not noise. | | |
| **— of which spec defects** | Bad/ambiguous/non-evaluable criteria caught. | | |
| **— of which impl defects** | Code failing a well-formed criterion, caught. | | |
| **Reproducibility defects** | # declared PASS claims that fail to reproduce when an independent party runs the run's *documented* verification command from a clean state (no undocumented env/setup). A PASS that only holds under setup the author silently supplied counts here. | | |
| **Unproven checks (no teeth)** | # pass-criteria whose pass is unproven because the run never demonstrated the check able to *fail* (no mutation / failure-path test). | | |
| **Latent spec-criteria defects** | # criteria that still pass against a deliberately *worse* artifact (a gap that lets a bad config through), found on independent audit. | | |
| **Rework** | # times the slice was reopened after being declared done (each re-run of any stage after a "done" claim). | | |
| **Unsupported assumptions** | # Class-3-or-higher choices made with **no recorded rationale** and/or a pass claimed with **no reproducible evidence**. | | |
| **Escaped defects** | Defects found only *after* the run declared success (e.g. by a later reviewer). Lower is better. | | |

## Interpretation

Fill after scoring:

- **Where did Run A's self-judgement diverge from Run B's independent verdict?**
  (List each requirement where the single agent claimed PASS but the independent
  verifier found FAIL / missing evidence.)
- **Did each declared PASS reproduce from a clean state?**
  (List any PASS that needed env/setup the run never documented — running the *stated*
  command from a fresh checkout fails. This is the self-graded-homework signature: the
  context that wrote the artifact also chose the conditions that made it pass.)
- **Were the pass-criteria proven able to fail?**
  (List criteria that were asserted but never failure-tested — their "pass" could be
  vacuous. A check with teeth was shown to exit non-zero under a targeted bad mutation.)
- **Did any criterion pass a *worse* artifact?**
  (Latent spec-criteria gap: a check that ignores a hardening dimension — e.g. compares
  a port number but not its bind host — and so green-lights a more-exposed config. These
  bound what *any* downstream stage can catch, so route them back to Stage 1.)
- **Which assumptions were silent in Run A but forced into the open in Run B?**
  (These are the ones the artifact boundary made visible.)
- **Net:** did separation raise defect detection and cut rework + unsupported
  assumptions enough to justify its extra passes for this class of slice?

## Expected signal (hypothesis to test, not a guarantee)

- Run B **detects more defects** — an independent verifier finds spec defects Run A
  rationalized away, because Run A's author is the same context that wrote them.
- Run B's PASS is **reproducible from a clean state** and **teeth-proven** — the verifier
  runs the documented command from scratch and mutates the artifact to show each check
  can fail. Run A's self-verification tends to reproduce only under the env its author
  silently supplied, and its checks are often asserted but never failure-tested.
- Run B **reworks less downstream** — assumptions are caught at a handoff boundary
  instead of after "done."
- Run B carries **fewer unsupported assumptions** — anything not written into an
  artifact cannot cross to the next stage, so implicit choices get recorded or die.
- Separation is **not** infallible: it raises verification rigor and reproducibility, but
  Stage-1 criteria quality still bounds what any stage can catch. A latent spec-criteria
  gap (a check blind to some hardening dimension) can escape *both* runs — for a small,
  tightly-specified slice the code often converges either way, and the measurable gains
  show up in verification quality, not the implementation.
- Cost: Run B uses more passes/context. If the scorecard shows no gap for trivial
  slices, that is a legitimate finding — reserve separation for slices where a wrong
  assumption is expensive.
