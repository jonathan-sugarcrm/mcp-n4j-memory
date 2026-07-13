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
4. **Score both** with the table below. Count from the artifacts, not from memory.

## Scorecard

| Metric | Definition (how to count) | Run A (single) | Run B (separated) |
|--------|---------------------------|:--------------:|:-----------------:|
| **Defect detection** | # real defects surfaced *before* the slice was called done — count spec defects + implementation defects. Verify each is real (reproducible), not noise. | | |
| **— of which spec defects** | Bad/ambiguous/non-evaluable criteria caught. | | |
| **— of which impl defects** | Code failing a well-formed criterion, caught. | | |
| **Rework** | # times the slice was reopened after being declared done (each re-run of any stage after a "done" claim). | | |
| **Unsupported assumptions** | # Class-3-or-higher choices made with **no recorded rationale** and/or a pass claimed with **no reproducible evidence**. | | |
| **Escaped defects** | Defects found only *after* the run declared success (e.g. by a later reviewer). Lower is better. | | |

## Interpretation

Fill after scoring:

- **Where did Run A's self-judgement diverge from Run B's independent verdict?**
  (List each requirement where the single agent claimed PASS but the independent
  verifier found FAIL / missing evidence.)
- **Which assumptions were silent in Run A but forced into the open in Run B?**
  (These are the ones the artifact boundary made visible.)
- **Net:** did separation raise defect detection and cut rework + unsupported
  assumptions enough to justify its extra passes for this class of slice?

## Expected signal (hypothesis to test, not a guarantee)

- Run B **detects more defects** — an independent verifier finds spec defects Run A
  rationalized away, because Run A's author is the same context that wrote them.
- Run B **reworks less downstream** — assumptions are caught at a handoff boundary
  instead of after "done."
- Run B carries **fewer unsupported assumptions** — anything not written into an
  artifact cannot cross to the next stage, so implicit choices get recorded or die.
- Cost: Run B uses more passes/context. If the scorecard shows no gap for trivial
  slices, that is a legitimate finding — reserve separation for slices where a wrong
  assumption is expensive.
