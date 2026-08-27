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
   fully before deciding any edit. Validate the Plan's canonical eight-field
   Test Control Policy and byte-identical approved/legacy-none Requirements TCE
   body before using it; refinement cannot repair an exception mismatch.
3. The only persistent path this command may create or modify is that exact
   `tasks.md`. Never edit spec.md, plan.md, an attachment, Source, a review
   request/verdict/seal, execution state, IA, acceptance, archive, product
   source, tests, build files, Git index/history, branches, or remotes. Never
   create a commit or push. Record repository status before and after and stop
   if this hook causes any other path delta.
4. Branch on receipt state before probing the full task-review gate:
   - If a REV-TASKS seal exists, run
     `check-gate.sh task-review <feature-dir>`. On success keep every byte
     read-only and return. A valid Accepted Protocol 1/2 delivery is historical
     and never reaches this hook. Any active older task set fails closed and
     must return through `gatespec.plan --revise`; refinement and `--retask`
     cannot upgrade it. On failure, make no task edit.
     Protocol 3 has no grandfathered no-op: all three Closure sections are
     mandatory even beside an older clean PASS receipt.
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
3, its Source-Design-Content-SHA256 equals the current Source value. Protocol,
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

For a basis-matching `*-retask` archive, also read its Test Control Closure.
Current Mode and each TC-### ID/surface/touchpoint/effect/switch/wiring/validator
must be identical; only consumer and default-proof task IDs may be rebound to
the new task numbering without changing their consumer/proof meaning. Restore
an accidental task-text drift when unambiguous. If a prior blocker actually
requires adding/removing/changing/renaming/relocating any stable control field,
do not refine or retask it: require `gatespec.plan --revise`, fresh native tasks,
and fresh REV-TASKS.
The Plan's canonical Policy and TCE body are also immutable across retask. A
different TCE first requires `gatespec.specify --revise`, then a revised Plan
and fresh tasks/REV-TASKS.

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
   ID and every Source Change Manifest path. Re-estimate the complete task
   plan's aggregate Production additions, churn, and production-file count
   from its concrete paths/symbols/build work. If any upper bound satisfies
   `new_upper * 100 >= design_upper * 125` (or becomes positive from zero), or
   a production path family is absent from Design's Production path basis, this is a Design
   gap; do not edit tasks to conceal it. Growth below 25% remains task-local
   and does not require re-approval.
9. **Prior-blocker closure** — inspect every basis-matching finding
   independently, identify concrete remediation tasks, and confirm those tasks
   close the full finding by its required checkpoint. A restatement, matrix
   row, new hash, or unrelated task is not remediation evidence.
10. **Test Control closure** — start from every verification task and prove its
   production invariant is reachable through an existing formal product
   contract. When it is not, register only the smallest explicit TC-### control
   allowed by the approved effective Test Control Policy: the canonical eight
   fields plus the exact Requirements TCE overlay copied into Plan. Apply a TCE
   only to its one Rule and its minimum stated replacement; do not infer or
   create/change/delete/broaden an exception. Without a matching TCE, require a
   source root ending `/src/testonly`, terminal `testonly` namespace/module (or
   leading `TestOnly`/`test_only` name), a typed declarative single-purpose
   per-instance RAII one-shot/count/barrier/time/random/fault/observation
   effect, and no formal product testing parameter, option, overload, getter,
   or state. A matching `source-root`, `language-marker`, `formal-api`,
   `control-model`, or `touchpoint-shape` TCE must instead use its precise
   source-auditable replacement. Reject generic callbacks, options bags,
   global mutable state, validation bypasses, duplicated business algorithms,
   placeholders, or an unconsumed control unless that exact semantic rule has
   a valid replacement TCE; named gap, real consumer, no orphan, and removal
   boundary are never exemptable. Require one named consumer and one
   default-build proof task.
   For each hook project, name one dedicated positive switch defaulting OFF:
   canonical `*_ENABLE_TEST_HOOKS`, or the source-auditable identifier from a
   `switch-identifier` TCE. Require one tracked regular non-symlink Bash
   validator whose path/name contains `testonly`, or the marker replacement
   from a `validator-path-marker` TCE; mode 100644 or 100755 is valid. Its only invocation is
   `bash <validator> --gatespec-lane default-off|explicit-on`: default-off omits the option,
   explicit-on sets it ON, both run the same normal tests, ON adds the
   hook-consuming tests, and output is canonical. Runtime activation and
   Debug/`BUILD_TESTING`/umbrella triggers are forbidden; OFF must elide every
   Test Control field, branch, resource, and symbol. Use Mode `none` only after
   proving no such gap exists; use `isolated` otherwise. Do not add a
   speculative hook or ask for per-hook human approval.
   Without a `touchpoint-shape` TCE, every production touchpoint has at most one
   visually contiguous dedicated macro-guard block per affected production
   function; its body has only one test-only call and feeds that result into
   the normal production error/result path. Counting, waiting, fault selection,
   and observer dispatch stay wholly in the registered test-only root
   (canonical `/src/testonly`, or the exact `source-root` replacement). Only
   `touchpoint-shape` may replace guard/call/result/mechanics shape; only
   `source-root` may replace that root. Crossing both requires both Rules;
   `control-model` never authorizes production-side mechanics.
   Validator tasks must freshly enumerate and hash every manifest, coverage,
   and hit value from that clone/lane's actual configure/build/test and present
   install/export/symbol outputs. A literal/precomputed hash, canonical-row
   echo, or omitted output family is not a validator implementation.
   The dedicated explicit opt-in/default-OFF behavior, runtime and umbrella
   trigger ban, full OFF elision, Bash lanes and same-normal-tests contract,
   current-clone derivation, registration/evidence lifecycle, named consumers,
   orphan ban, and removal boundary are the non-exemptable floor. If tasks need
   any other deviation, stop and require `gatespec.specify --revise` followed
   by a revised Plan and fresh native tasks; refinement cannot invent it.

As part of artifact trace closure, use Scope Contract only as the admission
source: every non-deferred CAP must reach executable tasks through its FR/SC
refs, no task may implement a deferred CAP, and Retained baseline must remain
unchanged. CAP IDs themselves do not enter any Closure table; the existing
CAP → FR/SC → task chain is the closure. Any task that adds external behavior,
activates deferred scope, changes Primary outcome, or removes a retained burden
is a Requirements gap and routes to specify revision rather than task repair.

## Refinement outcomes

Classify each audit gap before writing:

- A **task-local gap** is resolvable without changing or choosing among
  approved Requirements, Design, or Source alternatives. Repair all such gaps
  automatically in `tasks.md`: add or rewrite executable production and
  verification tasks, synchronize paths/symbols/dependencies/phases, rebuild
  all three closure sections, then renumber every checklist task monotonically as
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

An estimate-drift Design gap routes specifically to
`__SPECKIT_COMMAND_GATESPEC_PLAN__ --revise` so the aggregate estimate is
updated and diff-only re-confirmed. If the user instead chooses a split that
changes the approved feature boundary, route to
`__SPECKIT_COMMAND_GATESPEC_SPECIFY__ --revise`. There is no automatic split,
LOC limit, per-task estimate, or checkpoint size cap.

A verification gap that meets the frozen canonical-plus-TCE effective policy
is task-local and is registered here without a human decision. A needed seam
that requires a new semantic policy deviation returns through
`gatespec.specify --revise`; never solve it by silently adding a test-shaped
formal product API. Once implementation begins, an undeclared or late control
is not IA: remove it or return through `gatespec.plan --revise` and fresh native
tasks.

## Mandatory closure sections

Use
`.specify/extensions/gatespec/templates/gatespec-task-closure-template.md` as
the schema. In `tasks.md`, these exact sections are the final three H2 sections
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

## GateSpec Test Control Closure *(gatespec: mandatory)*

- **Mode**: `none`

| Control | Verification gap / production invariant | Test-only surface | Production touchpoint | Allowed effect / lifetime | Build switch / validator | Consumer tasks/tests | Default-build proof task |
|---|---|---|---|---|---|---|---|
| none | none | none | none | none | none | none | none |
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

Test Control Closure contains exact `- **Mode**: `none|isolated`` followed by
the fixed eight-column table. `none` has the sole exact row
`| none | none | none | none | none | none | none | none |`. `isolated` has no
none row and continuous TC-001... rows. In each isolated row, Test-only surface
and Production touchpoint are canonical comma+space `repo/path::symbol` lists.
Each repository path is slash-normalized with no leading dash, empty, `.` or
`..` component, repeated/trailing slash, whitespace, or shell metacharacter;
Build switch / validator is exactly
`NAME_ENABLE_TEST_HOOKS @ wiring/path @ validator/testonly-path` under the
canonical rules. A valid `switch-identifier` or `validator-path-marker` TCE
replaces only that tuple token while preserving `switch @ wiring @ validator`; Consumer
tasks/tests is a canonical comma+space list of non-checkpoint T### IDs in file
order; Default-build proof task is exactly one non-checkpoint T###. The prose
cells contain no raw `|`. Every path is repository-relative and canonical as
defined above. The validator path
names `testonly` or uses the exact approved marker replacement, and its implementation task makes it a tracked regular
non-symlink project Bash file with only the two fixed lanes and canonical
subject-bound output.

After any rewrite, restart all ten audit categories from the beginning against
the final bytes. Confirm task IDs, task references, all three Closure sections,
checkpoint intervals, and prior findings again, then run
`check-gate.sh tasks-structure <feature-dir>`. Do not return success until the
checker passes and repository status proves that this hook changed only
`tasks.md`.
