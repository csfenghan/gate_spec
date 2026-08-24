---
description: "GateSpec manual check: validate requirements, design, optional Source Design, tasks/reviews, or final acceptance."
---

## User Input

```text
$ARGUMENTS
```

Accept one of `spec`, `design`, `source`, `tasks-structure`, `task-review`,
`implementation-review [REV-ID]`, or `acceptance`. If omitted, use `design`
when plan.md exists and `spec` otherwise. `source` is conditional and silently
succeeds when its authoritative entry is absent; `acceptance` always requires
the final bound record for a marked GateSpec feature. Never infer a review or
acceptance mode. The optional REV-ID is accepted only with
`implementation-review` and defaults to `REV-FINAL`.

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
`__SPECKIT_COMMAND_GATESPEC_PLAN__`; Source findings return through
`__SPECKIT_COMMAND_GATESPEC_SOURCE_DESIGN__`; review findings use a new fresh
round with at most two remediation rounds. Acceptance is written only by
`__SPECKIT_COMMAND_GATESPEC_ACCEPT_IMPLEMENTATION__` after explicit user
acceptance.
