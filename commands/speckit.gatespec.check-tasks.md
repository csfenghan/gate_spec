---
description: "GateSpec internal fixed hook: validate native tasks, closure matrices, and implementation-review checkpoints."
---

Resolve the current feature directory from `.specify/feature.json` and run:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh tasks-structure <feature-dir>
```

Exit zero with no report when the checker is silent (an unmarked upstream
feature). On failure, print its diagnostics verbatim and stop the surrounding
`speckit.tasks` command before its completion report. This hook is structural:
it never edits or regenerates tasks.md, adds a checkpoint, closes a finding, or
manufactures a review artifact. Task-local failures return through the
priority-10 `speckit.gatespec.refine-tasks` pass and native tasks; an artifact
gap returns to the gated phase named in the diagnostic.

Except for a still-current grandfathered REV-TASKS PASS that binds legacy
tasks without the matrices, require these exact headings to be the final two H2
sections before the first `## Phase`, in this order, and allow only their table
and blank lines inside each section:

```markdown
## GateSpec Checkpoint Closure *(gatespec: mandatory)*

| Checkpoint | Contract refs | Production tasks | Verification tasks |
|---|---|---|---|

## GateSpec Prior Review Closure *(gatespec: mandatory)*

| Finding-SHA256 | Source verdict | Required-before | Remediation tasks |
|---|---|---|---|
```

Checkpoint body rows must equal the Plan Required Checkpoints in order. Each
row terminates one strict non-checkpoint task interval. Across Production tasks
and Verification tasks, every non-checkpoint T### occurs exactly once;
Production may be `none`, Verification is nonempty, and IDs preserve tasks.md
order with canonical `, ` separators. Contract refs are known original artifact
IDs, de-duplicated and C-sorted within a cell, never ranges, and collectively
cover every FR-###, SC-###, and approved D<n>. A ref may occur at more than one
checkpoint; mechanical coverage is not proof that its placement or tasks are
semantically sufficient. CAP-### never appears in Closure; Scope Contract
coverage remains the CAP → FR/SC → task chain and is judged semantically by
REV-TASKS.

Prior Review Closure is exactly the all-`none` row when no basis-matching
BLOCKER exists. Otherwise there is no `none` row and every BLOCKER item from
the current REV-TASKS chain and every `*-retask` archive with the current
Spec/Plan/Design-Attachments and v2 Source basis has one row. Require the raw
complete-item SHA-256, exact feature-relative verdict path plus `#B<NN>`, an
actual Required Checkpoint, and concrete remediation task IDs that occur no
later than it. Tasks/epoch/handoff changes do not make an otherwise matching
finding stale, and a matrix row does not prove remediation.

When Source Design is enabled, additionally require the current
`**Source-Design-Content-SHA256**`, at least one corresponding SD-* ref and a
precise repository-relative path on every non-checkpoint task, plus complete
matrix and task coverage of every approved SD<n>, every
SD-F/SD-U/SD-FLOW/SD-ALG/SD-FAIL/SD-TEST ID, and every Source Change Manifest
path. This remains structural; earliest-checkpoint placement, executable
closure, and semantic sufficiency belong to fresh REV-TASKS.

Aggregate estimate drift is handled by the preceding task refinement and the
fresh REV-TASKS semantic review: reaching 25% upper-bound growth or discovering
a new production path family returns to Design revision. This structural hook
does not infer LOC from task prose or impose a size limit.
