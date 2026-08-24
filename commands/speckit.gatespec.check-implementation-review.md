---
description: "GateSpec fixed hook/manual check: require a current implementation-review PASS seal."
---

## User Input

```text
$ARGUMENTS
```

Accept either no input or exactly `--scope <REV-ID>`, where REV-ID is listed
in the approved plan's Required Checkpoints. No input means `REV-FINAL`, which
is the fixed `after_implement` behavior. Reject every other argument.

Resolve the current feature directory from `.specify/feature.json` and run:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh implementation-review <feature-dir> <REV-ID>
```

Exit zero with no report when the checker is silent (an unmarked upstream
feature). Otherwise reproduce its result verbatim. Failure leaves the matching
checkpoint blocked even if its local checkbox is present; a REV-FINAL failure
prevents the native implement completion report. Never create, revert, or
repair request, verdict, seal, source, tasks, or approval content from this
command. Candidate rollback belongs only to the precommit coordinator flow.

For Protocol v2 this also verifies epoch, Task-Handoff, Source/IA/preserved
bindings, the IA blob in Subject-Commit, Original-Baseline cumulative ancestry,
raw Final-Delta-SHA256, and—when Source is enabled—the exact equality of actual
product paths with Source Change Manifest plus IA paths. Semantic conformance
still comes from the fresh reviewer. This priority-10 after hook is followed by
the priority-20 whole-delivery acceptance hook; REV-FINAL PASS alone is not
GateSpec completion.
