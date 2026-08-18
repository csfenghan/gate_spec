---
description: "GateSpec internal fixed hook: validate native tasks and implementation-review checkpoints."
---

Resolve the current feature directory from `.specify/feature.json` and run:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh tasks-structure <feature-dir>
```

Exit zero with no report when the checker is silent (an unmarked upstream
feature). On failure, print its diagnostics verbatim and stop the surrounding
`speckit.tasks` command before its completion report. This hook is structural:
it never edits or regenerates tasks.md, adds a checkpoint, or manufactures a
review artifact. Repair task generation through the approved plan contract and
rerun native tasks.
