---
description: "GateSpec manual gate check: run requirements or design validation for the current feature."
---

## User Input

```text
$ARGUMENTS
```

Accept only `spec` or `design`. If omitted, use `design` when plan.md exists
for the resolved feature and `spec` otherwise. This inference is for manual
use only; extension hooks use the fixed commands below.

Resolve `.specify/feature.json` (`feature_directory`), preserving paths with
spaces, then run:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh <mode> <feature-dir>
```

If stdout is empty and exit status is zero, report nothing: this is an
unmarked upstream auto-track feature. Otherwise reproduce the checker result.
A failure blocks the requested downstream phase. Never manufacture Status,
approval dates, or hashes to make a gate pass; content may be repaired, but
approval must return through `__SPECKIT_COMMAND_GATESPEC_SPECIFY__` or
`__SPECKIT_COMMAND_GATESPEC_PLAN__`.
