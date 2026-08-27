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

An active or unaccepted Protocol 1/2 feature fails closed and returns through
`gatespec.plan --revise`; only a complete Accepted legacy delivery is
historical, and it never reaches task validation. For Protocol 3, require the
three exact closure headings in the canonical order before the first `## Phase`
and allow only the fixed Mode field/table/blank lines described below.

```markdown
## GateSpec Checkpoint Closure *(gatespec: mandatory)*

| Checkpoint | Contract refs | Production tasks | Verification tasks |
|---|---|---|---|

## GateSpec Prior Review Closure *(gatespec: mandatory)*

| Finding-SHA256 | Source verdict | Required-before | Remediation tasks |
|---|---|---|---|

## GateSpec Test Control Closure *(gatespec: mandatory)*

- **Mode**: `none|isolated`

| Control | Verification gap / production invariant | Test-only surface | Production touchpoint | Allowed effect / lifetime | Build switch / validator | Consumer tasks/tests | Default-build proof task |
|---|---|---|---|---|---|---|---|
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
Spec/Plan/Design-Attachments and v3 Source basis has one row. Require the raw
complete-item SHA-256, exact feature-relative verdict path plus `#B<NN>`, an
actual Required Checkpoint, and concrete remediation task IDs that occur no
later than it. Tasks/epoch/handoff changes do not make an otherwise matching
finding stale, and a matrix row does not prove remediation.

Test Control Closure uses Mode `none` or `isolated`. Mode `none` has exactly the
eight-cell all-`none` row and no TC ID. Mode `isolated` has one row per
monotonic TC-### registration and no `none` row. Each row names one verification
gap/production invariant. Test-only surface and Production touchpoint cells use
canonical comma+space `repo/path::symbol`; repository paths are slash-normalized
and reject a leading dash, empty/`.`/`..` components, repeated/trailing slash,
whitespace, and shell metacharacters. Symbols are nonempty whitespace-free
declaration locators; common operator spellings such as `operator[]` and
`operator=` are valid, while Markdown/list delimiters are forbidden. Every surface path is under a source
root ending `/src/testonly` and uses terminal `testonly` namespace/module or a
leading `TestOnly`/`test_only` symbol unless the Plan's exact Requirements-copied
`source-root` or `language-marker` TCE provides the replacement. Each row has
one precise production touchpoint; one allowed typed declarative per-instance
RAII effect/lifetime; one dedicated positive switch (canonical
`*_ENABLE_TEST_HOOKS`, or the exact safe `[A-Za-z_][A-Za-z0-9_]*`
`switch-identifier` replacement) and the
canonical cell `NAME_ENABLE_TEST_HOOKS @ wiring/path @
validator/testonly-path`, except that `switch-identifier` and
`validator-path-marker` TCEs replace only their respective tokens while
preserving the three-part `switch @ wiring @ validator` tuple. The validator is
tracked regular non-symlink Bash (100644 or 100755) with canonical `testonly`
naming or its exact approved marker replacement; concrete
consumer tasks/tests; and one default-build proof task. All referenced tasks
exist, are non-checkpoints, preserve task order, and occur by the responsible
checkpoint. Validator wiring tasks explicitly provide only
`bash <validator> --gatespec-lane default-off|explicit-on`, omit the option in default-off, set
it ON only in explicit-on, run the same normal tests in both lanes, add
hook-consuming tests in ON, and produce canonical output.
This hook checks the declared structure; fresh review still rejects fake namespace isolation,
echo validators, hidden/runtime switches, and violations
of the non-exemptable floor after applying any exact semantic TCE replacement.

Require the Plan's eight canonical policy fields and approved/legacy-none TCE
body to be present and provenance-valid. No task, Closure row, or refinement
may create/change/delete/broaden a TCE or pre-register one in Requirements.
Apply only the named replacement; all unmentioned rules and the non-exemptable
registration/default-OFF/no-runtime/full-elision/Bash-lane/current-output/
named-consumer/no-orphan/removal/evidence lifecycle floor remain canonical.

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
