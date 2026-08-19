---
description: "GateSpec gated plan: concrete per-decision approval, requirements-basis chaining, safe resume, and explicit design approval."
handoffs:
  - label: Create Tasks
    agent: speckit.tasks
    prompt: Break the approved plan into tasks, then run analyze before implement.
    send: true
scripts:
  sh: ../../scripts/bash/setup-plan.sh --json
  ps: ../../scripts/powershell/setup-plan.ps1 -Json
---

## User Input

```text
$ARGUMENTS
```

Recognized workflow flags are `--revise` and `--restart`. Reject unknown flags,
reject using both together, and consider remaining non-empty input.

## Step 0: Requirements Gate and peer hooks

Run before any planning write:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh spec
```

Failure blocks planning. A truly unmarked auto-track spec exits silently; in
that case explain that gated plan requires a GateSpec spec and stop unless the
user explicitly starts the gated requirements flow.

Inspect `.specify/extensions.yml` and run other extensions' `before_plan`
hooks in declared order, skipping every `speckit.gatespec.*` hook (the inline
gate above already covers GateSpec). Respect required/optional failures. Run
peer `after_plan` hooks only after successful Design approval.

## Step 1: load context, constraints, and resume state

Verify `.specify/scripts/bash/setup-plan.sh` exists, then run `{SCRIPT}` from
repository root and parse FEATURE_SPEC, IMPL_PLAN, SPECS_DIR, and BRANCH. If
the required script or fields are missing, stop before writing. Read the approved spec fully. Re-read the current
constitution, project `.gatespec/constraints.md`, and user constraints, but
use the spec's frozen `## Constraint Basis` as the requirements contract.
If the current constitution/project-policy hashes invalidate that contract,
stop and return to `__SPECKIT_COMMAND_GATESPEC_SPECIFY__`. A changed personal
constraints file is warning-only until requirements is run with
`--refresh-constraints`.

Compute the approved spec content hash using the same scoped formula and write
it once as `**Requirements Content-SHA256**` in plan.md. This is a load-bearing
chain: never copy the Gate Approval hash field as a substitute.

Resume behavior:

- No plan or an untouched setup output: initialize once from the GateSpec plan
  template at
  `.specify/extensions/gatespec/templates/gatespec-plan-template.md`.
- Draft: continue in place without recopying the template.
- Valid Approved-Design with a valid Implementation Review Contract and no
  flag: keep every design artifact read-only and hand off to native tasks.
- Approved-Design created before this contract existed must not hand off. There
  is no legacy bypass: automatically archive tasks and non-archive review
  contents, apply the existing `--revise` semantics (Draft status, cleared Gate
  Approval, preserved baseline), add the contract, and require diff-only Design
  re-approval before regenerating native tasks.
- `--revise`: archive existing `tasks.md` and `.gatespec/reviews/`, change plan
  Status to Draft, clear Gate Approval, retain a baseline, and use diff-only
  re-approval.
- `--restart`: archive plan.md, research.md, data-model.md, contracts/,
  quickstart.md, tasks.md, and the non-archive contents of `.gatespec/reviews/`
  under `.gatespec/archive/<timestamp>-restart/`, then initialize a fresh
  GateSpec plan. Do not alter the approved spec or recursively archive an
  existing archive.

Any spec re-approval makes a plan with the old Requirements hash stale. Archive
tasks and current reviews, then re-plan; never continue executing stale tasks
or trust their receipts.

## Step 2: approve design decisions one at a time

Extract every non-trivial design decision. For each, present and wait before
the next:

1. Context citing FRs, constraint sources, and repository facts.
2. At least two options, each grounded in a concrete command session, file
   tree, request/flow trace, or field failure; state trade-offs as observable
   behavior.
3. Constraint result per option. A constitution `MUST` conflict is not
   approvable without a separate constitution amendment; a `SHOULD` deviation
   needs a recorded reason; a GateSpec constraint exemption needs an explicit
   approval in this Decision Log.
4. A 1–2 sentence recommendation.
5. The user's explicit choice, recorded under exact heading
   `### D<n>: <topic>` with one `**Approved**: <choice> (YYYY-MM-DD)`.

Use unique numeric IDs. If no non-trivial decision exists, write exactly one:

```markdown
- None — <specific reason no non-trivial design decision was required>
```

## Step 3: fill plan and design attachments

Follow upstream Phase 0/1 artifact formats. The six core Design Detailing
dimensions are mandatory, exact, and unique: thread/concurrency; object
lifetime/ownership; modules/classes; internal APIs/interactions; external
behavior contracts; setup/runtime/teardown. Constraints may add dimensions
but cannot remove, rename, or replace these six. Each needs substantive text
or `N/A — <reason>` / `无额外约束 — <原因>`.

Ensure every FR has a technical home and every design element traces to an FR
or approved decision. Remove unapproved gold-plating. Conduct an implementer's
walkthrough using only spec + design artifacts; close every non-trivial fork
with a Decision Log approval or bounded Implementation Freedom. quickstart.md
must provide a runnable end-to-end validation path for each P1 story.

Fill the exact mandatory `## Implementation Review Contract`. Keep protocol
version `1` and the fixed Review Root, task-review, isolation, parallel, Git,
and remediation values from the template. Select actual Required Checkpoints:
`REV-FOUNDATION`, one `REV-US<n>` per implemented user-story phase, and exactly
one final `REV-FINAL`. Give every ID exactly one non-empty Checkpoint Test
Mapping row and provide non-empty Final Validation. A mapping cell is one line
and cannot contain a raw `|`; wrap pipelines or multi-command validation in an
executable script and map the checkpoint to that script. The contract requires
native tasks to end each corresponding phase with a non-`[P]` row containing:

```text
GateSpec review checkpoint <REV-ID>: run speckit.gatespec.review-implementation --scope <REV-ID>; require .gatespec/reviews/<REV-ID>/seal.md before continuing.
```

The executor must join same-phase disjoint work before such a row and cannot
cross it without the matching PASS seal. Checkpoint commits stay local and are
never pushed. REV-FINAL covers the complete feature, not an aggregation of
stage verdicts.

Immediately before the final summary, internally compare spec.md, plan.md,
research.md, data-model.md, contracts/, and quickstart.md for terminology,
interfaces, constraints, traceability, and contradictions. Resolve findings
or obtain the appropriate decision approval. Do **not** call upstream analyze
during plan: native analyze belongs after tasks, when tasks.md exists.

## Step 4: Design approval

Present at most 20 lines: technical approach, approved decisions, explicit
implementation freedoms, validation approach, and mandatory “what I am least
confident about”. Wait for unambiguous approval. Changes produce a diff-only
re-approval round.

On explicit approval only:

1. Set `**Status**: Approved-Design (YYYY-MM-DD)`.
2. Ensure `## Gate Approval` is the unique final H2 and contains only the user
   approval date and lowercase Content-SHA256 fields.
3. Hash exactly the content before Gate Approval using sha256sum, with macOS
   `shasum -a 256` fallback.
4. Run `check-gate.sh design <feature-dir>` and resolve every structural error.

Run peer `after_plan` hooks, report completion, then follow the unchanged native
sequence: `__SPECKIT_COMMAND_TASKS__` → `__SPECKIT_COMMAND_ANALYZE__` →
`__SPECKIT_COMMAND_IMPLEMENT__`. Required GateSpec hooks structurally check the
native tasks, obtain a fresh-context task-review receipt after analyze, verify
that receipt before implement, and require the explicit REV-FINAL receipt after
implement. GateSpec adds no tasks or implement replacement.
