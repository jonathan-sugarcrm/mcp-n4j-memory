# Spec-loop run artifacts

Handoff artifacts for the (retired) separated-role review workflow. One folder per
slice, named by slice id. Each stage writes exactly one artifact here; downstream stages
consume only these files — never a prior stage's chat or reasoning.

```
docs/spec-loop-runs/<slice-id>/
├── specification.handoff.md     # stage 1 (specification-agent)
├── implementation.handoff.md    # stage 2 (implementation-agent)
├── verification.handoff.md      # stage 3 (verification-agent)
└── reconciliation.handoff.md    # stage 4 (reconciliation-agent)
```

For the single-vs-separated exercise, Run A (single agent) output goes under
`<slice-id>/run-a-single/`; the separated Run B uses the files above directly.
