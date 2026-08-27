---
description: "GateSpec optional source-level design: safe enable/resume/revision, fresh review, and explicit whole-design approval."
handoffs:
  - label: Create Native Tasks
    agent: speckit.tasks
    prompt: Generate source-traced tasks from the approved Requirements, Design, and optional Source Design, then run native analyze.
---

## User Input

```text
$ARGUMENTS
```

Accept no input, `--revise`, or `--restart`. Reject mixed, extra, or unknown
flags. Source Design is an optional independent sub-contract enabled solely by
`contracts/source-design.md`; never edit an approved plan to store an enable
switch.

## Step 0: gates and enable eligibility

Resolve the current feature, require an Approved-Requirements spec and
Approved-Design plan, and run `check-gate.sh design`. A silent unmarked feature
is not eligible for gated Source Design. Require an attached local feature
branch; never push, reset, rebase, stash, clean, or rewrite history.
Require Plan Protocol Version 3. An active or unaccepted Protocol 1/2 Plan must
first return through `gatespec.plan --revise`; Source activation cannot upgrade
it. A valid Accepted legacy delivery is immutable history and cannot enable a
new Source contract.

On first enable, inspect existing tasks, checkboxes, reviews, Git history and
the complete worktree delta:

- Before product implementation, Source may be enabled. If tasks.md,
  analyze output, or REV-TASKS already exists but every implementation task is
  untouched, no implementation review exists, and no product path differs from
  the pre-task baseline, archive those artifacts and regenerate them later.
- Any completed implementation task, product/test/build/config diff attributable
  to implementation, IA entry, implementation receipt, or ambiguity about
  whether code work began refuses first enable. Do not relabel existing code as
  Source Design.

Before any overwrite, archive tasks.md, current reviews, IA, execution state,
acceptance, and related non-archive downstream work under a timestamped
`.gatespec/archive/<timestamp>-source-enable/`. Preserve prior archives.
Copy `templates/gatespec-source-design-template.md` exactly once. Initialize
Protocol v3 `.gatespec/execution-state.md` with one self-hashed canonical set:

```markdown
# GateSpec Execution State
- **Protocol-Version**: `3`
- **Execution-Epoch**: `E1`
- **Original-Implementation-Baseline**: `<current pre-implementation commit>`
- **Task-Handoff-Commit**: `pending`
- **Source-Design-Content-SHA256**: `pending`
- **Preserved-Reviews-SHA256**: `not-applicable`
- **Execution-State-SHA256**: `<hash of all prior bytes>`
```

Source activation never changes the Plan protocol; every downstream Source,
task, implementation, and acceptance receipt remains Protocol 3.

## Step 1: resume, revise, or restart safely

- Draft: resume in place without recopying or renumbering SD/SD-* IDs.
- Valid Approved-Source-Design with no flag: keep all Source bytes read-only and
  hand off to native tasks.
- `--restart` before implementation: archive the whole Source bundle,
  REV-SOURCE, tasks/reviews/IA/execution/acceptance, then create a new Draft and
  increment the execution epoch while preserving Original Baseline.
- `--revise`: retain a baseline, return Status/Gate Approval to Draft, archive
  stale Source/downstream artifacts, and use diff-only approval.

If implementation has begun, Source revision is an exceptional blocked exit
from normal implement, never a routine intermediate approval. Keep the first
Original-Implementation-Baseline unchanged. Determine the last PASS Subject.
Save all work after that Subject as a binary patch plus a raw path manifest in
the revision archive, including staged, committed, working-tree and untracked
evidence. Then create a normal compensating commit that restores those paths to
the last safe Subject; do not reset/rebase/stash or erase review history. If a
lossless patch/archive or compensating commit cannot be proven, stop.

Archive the old Source bundle, tasks, reviews, IA, acceptance, and execution
snapshot. Revise/restart Source, obtain fresh REV-SOURCE, and require user diff
approval. Under `.gatespec/revalidations/E<n>/`, issue a fresh self-contained
revalidation request/verdict/seal for every previously preserved PASS Subject
against the new Source hash. C-sort the relative-path/raw-hash manifest into
Preserved-Reviews-SHA256. An item permanently records the epoch in which that
Source revalidation was created, its preserved Subject, and the Source hash it
reviewed. A later task-only retask may advance the active execution epoch while
retaining that immutable evidence if the Source hash and Subject are unchanged;
the active execution state binds the complete raw manifest and never rewrites
an item's epoch. Regenerate tasks and REV-TASKS for the new epoch. Never reapply
the unreviewed patch automatically; new tasks may reintroduce its valid ideas.
REV-FINAL always compares the unchanged Original Baseline to the new final
Subject.

## Step 2: source-level design

Inspect repository source, tests, build/configuration, current Plan attachments,
and exact integration symbols. Fill the complete template, using optional
direct regular `.md` shards under `contracts/source-design/` only when useful.
The entry remains authoritative and references every shard.

For every source-level fork, classify it as:

1. SD<n> human decision: at least two compliant viable choices have materially
   different human consequences;
2. engineering determination: Requirements/Design fix the outcome or one
   mechanism is strictly simpler without a material downside; record rationale
   in the appropriate technical block;
3. bounded Implementation Freedom: externally equivalent local choices with
   exact limits.

Use the existing scenario-first decision answer mechanism and adaptive maximum
of four simple independent cards; complex/high-risk decisions are alone. No new
approval mechanism is introduced. The user may cheaply promote or challenge a
classification.

The Source bundle must contain complete SD-F, SD-U, SD-FLOW, SD-ALG, SD-FAIL,
and SD-TEST blocks plus all operational/cross-cutting areas named by the
template. A not-applicable area needs a concrete reason. List only real
repository-relative paths and complete declarations without bodies. State
bounded IA freedoms and prohibited material boundaries explicitly.

Source Design may identify a verification gap but must not register, name, or
manifest an exact Test Control, `/src/testonly` surface, production hook
touchpoint, `*_ENABLE_TEST_HOOKS` switch, hook wiring, or validator. Those are
task-stage registrations under the Plan's effective canonical-plus-TCE Test
Control Policy. Source Design must not create/change/delete/broaden the copied
TCE overlay; a needed deviation returns to Requirements `--revise`. If a Source
draft contains one, remove it before review; do not seek an SD decision or user
approval for a hook.

Before review, trace every Source element to a non-deferred CAP and FR. Cover
all admitted CAPs through their FR/SC obligations, preserve Retained baseline,
and reject any Source path, symbol, API, flow, or test whose only purpose is a
deferred CAP or adjacent optimization. If Source would activate deferred scope,
add external behavior, change Primary outcome, or remove a retained burden,
return to `__SPECKIT_COMMAND_GATESPEC_SPECIFY__ --revise`; do not disguise the
change as an SD decision, engineering determination, or bounded freedom.

Before requesting review, independently re-estimate whole-feature Production
additions, churn, and files from the complete Source manifest, declarations,
callers, build/configuration work, and test obligations. Compare each new upper
bound with the approved Design upper bound using integer arithmetic:
`new_upper * 100 >= design_upper * 125` is material drift; when the Design
upper bound is zero, any positive new upper bound is material. Exactly 25%
growth blocks; smaller growth does not. Also block when Source introduces a
production path family not covered by Design's Production path basis,
regardless of numeric size. Return to
`__SPECKIT_COMMAND_GATESPEC_PLAN__ --revise` to record the new estimate and
obtain diff-only Design re-confirmation. If the proposed remedy is to split in
a way that changes approved feature scope, return instead to
`__SPECKIT_COMMAND_GATESPEC_SPECIFY__ --revise`. Size by itself is never a
hard rejection; the block exists only to prevent silent estimate drift.

Run `check-gate.sh source-candidate <feature-dir>` until it passes. Then invoke
`__SPECKIT_COMMAND_GATESPEC_REVIEW_SOURCE_DESIGN__`. Same-context review is forbidden.
The Protocol 3 REV-SOURCE request, verdict seal, and reviewed Source contract
carry `Test-Control-Mode`, `Test-Control-Closure-SHA256`,
`Test-Control-Subject-Manifest-SHA256`, `Default-OFF-Evidence-SHA256`, and
`Explicit-ON-Evidence-SHA256` as exact `not-applicable` values: Source can
describe only the verification gap and cannot pre-register task-stage Test
Controls.
REV-SOURCE binds Source-Design-Reviewed-SHA256, whose entry digest excludes the
mutable Status and final Gate Approval while every shard remains raw-hashed.
Both Source manifests use exact
`<feature-relative-path><TAB><raw-or-filtered-file-SHA256><LF>` lines and hash
their C-sorted byte stream.

## Step 3: explicit whole-Source approval

After a current fresh REV-SOURCE PASS, present at most 20 lines: maintainer
scenario, before/after, principal success/failure flows, actual file/symbol/
algorithm/error/test boundary, the estimate recheck result against Design,
source decisions, freedoms, risks, and mandatory “what I am least confident
about”. Include the admitted-CAP coverage, deferred exclusions, and Retained
baseline conservation. Wait for unambiguous user approval. This remains the existing whole-
Source summary approval, not a size-specific approval. Reviewer PASS never
substitutes for it. Requested changes return to Draft and require a new
reviewed hash; a revision shows only the diff.

On explicit approval only:

1. Set `Approved-Source-Design (YYYY-MM-DD)` and the matching user date.
2. Compute Source-Design-Content-SHA256 as the hash of that C-sorted manifest:
   entry uses its exact bytes before Gate Approval; every shard uses raw bytes.
3. Store that value as Gate Approval Content-SHA256 and in execution state;
   recompute the execution-state self-hash. Do not modify the REV-SOURCE
   request/seal: its reviewed hash deliberately excludes Status/Gate Approval.
4. Run `check-gate.sh source <feature-dir>` and resolve every failure.

Handoff choices are native `speckit.tasks` now, or return read-only later.
Native tasks must record the Source content hash and map every non-checkpoint
task to SD-* refs and precise paths. Normal implement has no intermediate user
approval; bounded IA is automatic, while material or uncertain deviation
blocks and exits to this revision flow.
