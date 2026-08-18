---
description: "GateSpec manual check: validate requirements, design, task structure, or review receipts."
---

## User Input

```text
$ARGUMENTS
```

Accept one of `spec`, `design`, `tasks-structure`, `task-review`, or
`implementation-review [REV-ID]`. If omitted, use `design` when plan.md exists
for the resolved feature and `spec` otherwise. Never infer one of the three
review modes: their fixed hook commands select it explicitly. The optional
REV-ID is accepted only with `implementation-review` and defaults to
`REV-FINAL`.

Resolve `.specify/feature.json` (`feature_directory`), preserving paths with
spaces, then run:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh <mode> <feature-dir> [REV-ID]
```

If stdout is empty and exit status is zero, report nothing: this is an
unmarked upstream auto-track feature. Otherwise reproduce the checker result.
A failure blocks the requested downstream phase. Never manufacture Status,
approval dates, verdicts, seals, or hashes to make a check pass. Requirements
or Design content returns through `__SPECKIT_COMMAND_GATESPEC_SPECIFY__` or
`__SPECKIT_COMMAND_GATESPEC_PLAN__`; review findings return through a new
fresh-context review round, with at most two remediation rounds.
