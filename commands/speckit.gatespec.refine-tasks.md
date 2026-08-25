---
description: "GateSpec internal fixed hook: audit and refine native tasks into a complete, reviewable closure contract."
---

## User Input

```text
$ARGUMENTS
```

Accept no input. This is the priority-10 `after_tasks` hook. It may refine the
native task plan, but it is not another task generator or approval mechanism.

## Entry and write boundary

1. Resolve the current feature directory from `.specify/feature.json`, quote
   every path, and run the Design and conditional Source gates. Exit zero with
   no report and no write when their checker result is the silent unmarked
   upstream case. Otherwise require current Approved Requirements, Approved
   Design, and, when enabled, Approved Source Design plus REV-SOURCE.
2. Require a regular non-symlink `tasks.md` produced by native
   `speckit.tasks`. Read the approved spec, plan, design attachments, complete
   Source bundle when enabled, task file, and eligible prior REV-TASKS receipts
   fully before deciding any edit.
3. The only persistent path this command may create or modify is that exact
   `tasks.md`. Never edit spec.md, plan.md, an attachment, Source, a review
   request/verdict/seal, execution state, IA, acceptance, archive, product
   source, tests, build files, Git index/history, branches, or remotes. Never
   create a commit or push. Record repository status before and after and stop
   if this hook causes any other path delta.
4. Branch on receipt state before probing the full task-review gate:
   - If a REV-TASKS seal exists, run
     `check-gate.sh task-review <feature-dir>`. On success keep every byte
     read-only and return. In particular, a full current legacy PASS whose bound
     tasks predate both closure matrices is a grandfathered no-op; do not
     invalidate its seal merely to add metadata. On failure, make no task edit.
     A partial or malformed Closure beside a seal is corrupted handoff metadata,
     not a task-local gap and never qualifies for grandfathering or `--retask`;
     preserve all bytes and direct the user to
     `__SPECKIT_COMMAND_GATESPEC_PLAN__ --restart` for the existing lossless
     archive and Design re-approval path. Any other malformed/orphan sealed
     chain likewise blocks with its checker diagnostics.
   - If an unsealed round-02 verdict exists, run
     `check-gate.sh retask-eligible <feature-dir>`. On success leave tasks
     read-only and direct the user to
     `__SPECKIT_COMMAND_GATESPEC_PLAN__ --retask`; on failure print its
     diagnostics and stop.
   - With no seal and no round-02 verdict, do not call full `task-review` before
     Closure exists. Treat no review as the normal first cycle. Validate any
     current round-00/01 request/verdict pairs directly as a complete canonical
     BLOCKED chain while building the prior-finding inventory below; an orphan,
     PASS-without-seal, stale binding, or malformed receipt blocks. Only then
     continue the task-only refinement.

All valid task checklist rows must still be unchecked. A checked task or any
evidence that product implementation began blocks refinement rather than being
renumbered or reclassified.

## Basis-matching prior findings

Build one read-only prior-finding inventory from:

- the current `.gatespec/reviews/REV-TASKS/` round chain; and
- every `.gatespec/archive/*-retask/reviews/REV-TASKS/` round chain.

Do not consult restart, revise, Source-revision, or other archive classes.
Validate each request and verdict schema, binding, and self-hash before using
it. A BLOCKED verdict is relevant only when its request's
Spec-Content-SHA256, Plan-Content-SHA256, and
Design-Attachments-SHA256 equal the current approved basis and, for Protocol
v2, its Source-Design-Content-SHA256 equals the current Source value. Protocol,
tasks-definition, execution epoch, Task Handoff, preserved-review, IA, and Git
review fields do not make an otherwise equal design basis current or stale;
never trust them as a substitute for those four basis bindings.

Within each relevant verdict's `## Blockers`, treat every complete Markdown
`- BLOCKER: ...` list item, including its continuation bytes, as one finding.
Number items in source order as `B01`, `B02`, and so on. Its identity is the
lowercase SHA-256 of the exact raw UTF-8 bytes of the complete item. Retain its
feature-relative verdict path and append `#B<NN>`. Do not deduplicate equal
text from distinct source items and do not infer closure from a changed task
hash.

## Fixed exhaustive audit

Audit the entire current task plan, not only lines implicated by a prior
finding. Complete each category in this order:

1. **Type completeness** — every new or changed type, state, enum, schema,
   field, wire/config representation, conversion, and compatibility edge has
   the tasks needed to make it usable; a declaration or model note is not
   mistaken for a complete runtime change.
2. **Declaration, definition, and build closure** — every affected declaration
   has its definition/implementation and every required build target,
   dependency, code-generation, registration, packaging, install, or
   configuration update is explicit.
3. **API consumer closure** — each changed internal or external API identifies
   all in-scope callers, consumers, adapters, mocks, and compatibility paths
   that must change; do not stop at the producer.
4. **Producer-to-test closure** — every behavior producer, error/failure path,
   boundary condition, and approved validation has an executable verification
   task that reaches it. A test file task must name what it proves.
5. **Lifecycle closure** — setup, startup, steady state, cancellation,
   backpressure, partial failure, recovery/rollback, teardown, cleanup,
   ownership/resource release, and concurrency ordering from the approved
   design all have implementation and verification where applicable.
6. **Earliest-checkpoint closure** — place each obligation and each prior
   remediation at the earliest checkpoint where it can be implemented and
   verified. No later phase may claim work needed by an earlier checkpoint.
7. **Path, symbol, dependency, and parallel safety** — every action names a
   precise repository-relative path and, where code is changed, the relevant
   symbol or structural target; ordering is executable; every `[P]` task is
   disjoint in files, symbols, generated outputs, state, and prerequisites.
8. **Artifact trace closure** — cover every FR-###, SC-###, approved D<n>,
   recorded engineering determination, bounded Implementation Freedom, user
   story/acceptance and failure scenario, contract/test mapping, and Design
   Evidence Schema 1 dimension without inventing scope. With Source enabled,
   also cover every approved SD<n>, SD-F/SD-U/SD-FLOW/SD-ALG/SD-FAIL/SD-TEST
   ID and every Source Change Manifest path.
9. **Prior-blocker closure** — inspect every basis-matching finding
   independently, identify concrete remediation tasks, and confirm those tasks
   close the full finding by its required checkpoint. A restatement, matrix
   row, new hash, or unrelated task is not remediation evidence.

## Refinement outcomes

Classify each audit gap before writing:

- A **task-local gap** is resolvable without changing or choosing among
  approved Requirements, Design, or Source alternatives. Repair all such gaps
  automatically in `tasks.md`: add or rewrite executable production and
  verification tasks, synchronize paths/symbols/dependencies/phases, rebuild
  both closure tables, then renumber every checklist task monotonically as
  `T001`, `T002`, ... in file order and update every task reference. Do one
  coherent whole-file pass; do not leave partial numbering or a finding-only
  patch.
- A **Requirements or human-choice gap** blocks and routes to
  `__SPECKIT_COMMAND_GATESPEC_SPECIFY__ --revise`; a **Design gap** blocks and
  routes to `__SPECKIT_COMMAND_GATESPEC_PLAN__ --revise`; a **Source gap** when
  Source is enabled blocks and routes to
  `__SPECKIT_COMMAND_GATESPEC_SOURCE_DESIGN__ --revise`. State the exact
  missing/contradictory boundary. Never edit an approved artifact, invent a
  human answer, widen an Implementation Freedom, or disguise a material Source
  departure as a task.

## Mandatory closure sections

Use
`.specify/extensions/gatespec/templates/gatespec-task-closure-template.md` as
the schema. In `tasks.md`, these exact sections are the final two H2 sections
before the first `## Phase` heading, in this order, with no duplicate:

```markdown
## GateSpec Checkpoint Closure *(gatespec: mandatory)*

| Checkpoint | Contract refs | Production tasks | Verification tasks |
|---|---|---|---|
| REV-FOUNDATION | FR-001, SC-001 | T001, T002 | T003 |

## GateSpec Prior Review Closure *(gatespec: mandatory)*

| Finding-SHA256 | Source verdict | Required-before | Remediation tasks |
|---|---|---|---|
| none | none | none | none |
```

Replace the example row. Checkpoint rows are exactly the Plan's Required
Checkpoints in declared order. A row's interval is every non-checkpoint task
after the preceding checkpoint (or the first task for the first row) and before
that row's phase-final checkpoint. Across Production tasks and Verification
tasks, list every non-checkpoint T### exactly once and in tasks.md order.
Production may be the literal `none`; Verification contains at least one task.
Use only `, ` between multiple task IDs.

Contract refs use exact artifact IDs, never ranges, prose aliases, or invented
umbrella IDs. Within each cell remove duplicates, C-sort bytewise, and join
with `, `. Across the table cover every FR-###, SC-###, and approved D<n>; with
Source enabled also cover every approved SD<n> and every SD-* ID. Map a ref to
the earliest checkpoint at which its obligation is closed and verifiable.

When the prior-finding inventory is empty, Prior Review Closure contains
exactly the one `| none | none | none | none |` body row. Otherwise it contains
no `none` row and exactly one row per inventory item: raw-item SHA-256, its
feature-relative `<verdict>#B<NN>` source, one actual Required Checkpoint as
`Required-before`, and one or more concrete non-checkpoint remediation T### IDs
separated by `, `. Every remediation task must occur no later than
Required-before; the row is navigation and traceability, never proof of
closure.

After any rewrite, restart all nine audit categories from the beginning against
the final bytes. Confirm task IDs, task references, both matrices, checkpoint
intervals, and prior findings again, then run
`check-gate.sh tasks-structure <feature-dir>`. Do not return success until the
checker passes and repository status proves that this hook changed only
`tasks.md`.
