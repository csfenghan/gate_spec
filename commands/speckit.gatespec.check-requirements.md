---
description: "GateSpec internal fixed hook: run the Requirements Gate for the current feature."
---

Resolve the current feature directory from `.specify/feature.json` and run:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh spec <feature-dir>
```

Exit zero with no report when the checker is silent (auto track). On failure,
print its diagnostics verbatim and stop the surrounding command. Never switch
to design mode based on whether plan.md happens to exist. A legacy approved
Requirements artifact without Delivery Estimate is warning-only and remains
immutable; the next Design supplies the first estimate. A legacy Approved
Requirements artifact without Scope Contract blocks before Design and requires
`gatespec.specify --revise` unless checked tasks, implementation-review
metadata, or a real production delta proves implementation progress; progressed
legacy delivery is warning-only and read-only.
