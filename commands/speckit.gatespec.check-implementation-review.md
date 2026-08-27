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

An active or unaccepted Protocol 1/2 feature fails closed and requires
`gatespec.plan --revise`; only a valid Accepted legacy delivery remains
historical. For Protocol v3 this also verifies epoch, Task-Handoff, Source/IA/preserved
bindings, the canonical Policy plus exact approved/legacy-none Requirements
TCE copy, the IA blob in Subject-Commit, Original-Baseline cumulative ancestry,
raw Final-Delta-SHA256, and—when Source is enabled—the exact equality of actual
paths with Source Change Manifest plus IA paths plus the validated registered
Test Control Subject Manifest object paths that actually changed in the bound
delta. Unchanged members of a recursively bound test-only tree remain in the
Subject manifest but not in the changed-path equality. A registered touchpoint/wiring file only
admits its declared hook delta. Semantic conformance
still comes from the fresh reviewer. Every verdict must include the canonical
Test Control Audit with exact cumulative Test Control scale. REV-FINAL in
isolated mode additionally requires the bound
Test Control Subject Manifest and the two same-round canonical evidence files;
mode none requires the three exact `not-applicable` values. This priority-10
after hook is followed by
the priority-20 whole-delivery acceptance hook; REV-FINAL PASS alone is not
GateSpec completion.
