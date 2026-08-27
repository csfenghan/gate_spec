---
description: "GateSpec internal fixed hook: run the Design Gate for the current feature."
---

Resolve the current feature directory from `.specify/feature.json` and run:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh design <feature-dir>
```

Exit zero with no report when the checker is silent (auto track). On failure,
print its diagnostics verbatim and stop the surrounding command. Never switch
to requirements-only mode based on whether plan.md happens to exist. Every
active Plan must be Protocol 3 with Delivery Estimate, Design Evidence, the
eight-field Test Control Policy, the exact approved or legacy-none Requirements
Test Control Policy Exceptions copy, and Implementation Review Contract. An
active/unaccepted Protocol 1/2 Plan fails closed to `gatespec.plan --revise`
regardless of apparent progress; only a complete Accepted legacy delivery is
immutable history and it never hands off new tasks.
Plan must not copy a Scope Contract table: its Requirements content hash binds
the single approved contract in spec.md.
