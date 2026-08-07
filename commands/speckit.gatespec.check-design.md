---
description: "GateSpec internal fixed hook: run the Design Gate for the current feature."
---

Resolve the current feature directory from `.specify/feature.json` and run:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh design <feature-dir>
```

Exit zero with no report when the checker is silent (auto track). On failure,
print its diagnostics verbatim and stop the surrounding command. Never switch
to requirements-only mode based on whether plan.md happens to exist.
