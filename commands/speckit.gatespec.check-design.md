---
description: "GateSpec internal fixed hook: run the Design Gate for the current feature."
---

Resolve the current feature directory from `.specify/feature.json` and run:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh design <feature-dir>
```

Exit zero with no report when the checker is silent (auto track). On failure,
print its diagnostics verbatim and stop the surrounding command. Never switch
to requirements-only mode based on whether plan.md happens to exist. A legacy
Approved Design without Delivery Estimate blocks before tasks unless checked
tasks, implementation-review metadata, or a product-code delta proves
implementation progress; progressed legacy delivery is warning-only.
Plan must not copy a Scope Contract table: its Requirements content hash binds
the single approved contract in spec.md.
