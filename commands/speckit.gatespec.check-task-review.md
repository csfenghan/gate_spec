---
description: "GateSpec internal fixed hook: require a current fresh-context task-review seal before implementation."
---

Resolve the current feature directory from `.specify/feature.json` and run:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh task-review <feature-dir>
```

Exit zero with no report when the checker is silent (an unmarked upstream
feature). On failure, print its diagnostics verbatim and stop before native
implementation writes. Never create, edit, reseal, or reinterpret a review
receipt in this checker entry. A missing, BLOCKED, invalid, or stale REV-TASKS
receipt must return through native analyze and `speckit.gatespec.review-tasks`;
same-context review is forbidden.

For active Protocol v2 the checker also requires a current execution epoch,
committed Task-Handoff, unchanged Original Baseline, current Source/preserved
review bindings, an empty baseline IA log when Source is enabled, and every
feature checklist item complete. After success, read the complete approved
Source bundle and execution/IA baseline before native implementation begins.
This prevents mid-implement checklist prompts; it does not prove reviewer
identity or replace semantic fresh review.
