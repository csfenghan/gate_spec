---
description: "GateSpec gated plan: scenario-first human decisions, recorded engineering determinations, safe resume, and explicit design approval."
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

## Step 2: approve design decisions in adaptive batches

Before asking, make one complete discovery pass over the approved Requirements,
constraints, existing Draft design artifacts, and relevant repository facts.
Run independent read-only searches in parallel when supported. Classify every
known design fork into exactly one conversational bucket:

1. **Human decision** — at least two viable options satisfy approved
   Requirements and constitution `MUST` rules, and a reasonable product owner,
   operator, maintainer, or affected user could prefer either because it changes
   visible behavior, scope, data/security/privacy, compatibility, measurable
   cost/performance, an expensive or irreversible boundary, or an approvable
   constraint trade-off.
2. **Engineering determination** — Requirements already fix the observable
   outcome and Design must commit to a mechanism to close a cross-component
   contract, or one option is strictly simpler without a worse material
   consequence. Select the safest simplest compliant mechanism and record it
   with rationale in the applicable Design Detailing dimension and, when useful,
   research.md. It gets no `D<n>` ID and no individual `Approved` field.
3. **Implementation Freedom** — multiple externally equivalent compliant
   options remain, no approved artifact depends on the exact mechanism, and the
   choice is safe to defer. Record the choice and exact bounds in the existing
   section.

An option conflicting with approved Requirements or a constitution `MUST` is
excluded rather than offered as a foil. A `SHOULD` deviation or GateSpec
constraint exemption may be offered only with its reason/consequence and is
high risk. If fewer than two viable options remain, use an engineering
determination; when “do not build/change scope” is a genuine alternative,
return that higher-level choice to Requirements. When classification is
uncertain, use a human decision. The user may cheaply request `explain <topic>`
or `discuss <topic>` at any point; expose the rationale or promote the item to a
human decision without creating a workflow flag or fourth approval mechanism.

Build an ephemeral dependency graph only for human decisions; never persist the
graph, classification inventory, or batch state as a workflow artifact.
Decision A depends on B when any B choice can change A's existence, scenario,
options, recommendation, or constraint result. If independence is uncertain,
add the dependency. Collapse a dependency cycle into one composite decision
whose options are coherent design bundles. Re-derive and reclassify the
inventory on resume and after every answer.

Assign unique, monotonically increasing `D<n>` IDs only when a human decision
is first presented. Preserve every accepted ID and continue after the greatest
ID; never renumber a resumed Draft. An unanswered legacy card may be
reclassified: explain the change, move its substance to Design Detailing or
Implementation Freedoms, remove any unresolved placeholder, and never reuse
its retired ID.

Mark a human decision **complex** when it has 3–4 viable options, crosses
multiple modules, Design Detailing dimensions, or external contracts, or needs
a multi-step flow, failure, or migration explanation. Mark it **high risk**
when it grants a constraint exemption or constitution SHOULD deviation,
controls irreversible or data-migration behavior, affects
security/privacy/compliance, or breaks an external compatibility contract. Use
the higher classification when unsure. A normal card costs one unit; any
complex or high-risk card consumes the full four-unit cognitive budget and is
the only decision card in its round. A batch contains at most four normal cards
and total load at most four.

Choose only from the unresolved human-decision frontier. Prefer cards sharing
one actor or operational journey; present fewer rather than mix unrelated
mental contexts. Within a coherent set, prefer decisions that unlock the most
downstream decisions, then P1/external behavior, then discovery order.

Start each batch with one compact progress line containing resolved and
currently-known **human decision** counts, this batch's IDs, and the number of
dependency-blocked human topics. Do not count engineering determinations or
Implementation Freedoms as decisions. On first inventory and whenever a bucket
changes, add a compact bucket-count digest and state that any topic can be
expanded or promoted.

For each platform-neutral Markdown decision card, include in this exact
cognitive order:

1. `D<n>` plus a plain-language question understandable without identifiers.
2. **Scenario** — the affected actor, initial state, trigger, and observable
   outcome or field failure.
3. **Fixed boundary** — what approved Requirements or higher-priority
   constraints already decide and this card cannot reopen.
4. **Why this needs you** — the concrete consequence on which reasonable humans
   could prefer different answers.
5. **Options** — 2–4 viable mutually exclusive options applied to the same
   scenario. State observable result/trade-off first, then technical mechanism
   and constraint result. Never include a dominated or forbidden foil.
6. **Recommendation** — 1–2 sentences, after all options.
7. **Technical basis** — FRs, prior decisions, constraint sources, repository
   facts, file trees, or flow traces last rather than as the comprehension entry.
8. When applicable, `⚠ High risk — explicit D<n>=<choice> authorization
   required; batch recommendation shortcuts do not cover this decision`, plus
   the concrete reason.

The card is self-contained only when deleting Technical basis identifiers still
leaves enough information to explain the situation, alternatives, and human
consequences. Rewrite or split a card that fails this test before presenting it.

Wait for the batch response. Accept an ID mapped to an option letter, exact
option label, or `recommended`, for example `D1=A; D2=recommended`. “Accept all
recommendations in this batch” answers every non-high-risk card in the current
batch only. Every high-risk card requires its explicit `D<n>` choice; this is
the normal individual-decision approval mechanism, not a fourth mechanism.

Validate all answers as a set before writing. Record each unambiguous,
unaffected choice under exact heading `### D<n>: <topic>` with one
`**Approved**: <choice> (YYYY-MM-DD)`. Preserve unanswered IDs and put them
first in the next batch, refilling remaining capacity with newly eligible
independent decisions. If choices conflict or introduce a cross-cutting
constraint, retain unaffected approvals and turn only the conflict into a
reconciliation decision; never choose or revise an option automatically. A
constitution MUST conflict is not recorded.

Honor cheap, non-persistent controls such as `split D2`, `ask one next round`,
or `next round at most N` (1–4). A deferred human decision remains unresolved
and blocks Design approval while other independent decisions may continue.
Batch grouping and triage buckets are conversational only and are never stored
as workflow state.

If no design choice requires individual human approval, write exactly one:

```markdown
- None — <specific reason no design choice required individual human approval>
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
as an approved human decision, a reasoned engineering determination in Design
Detailing/research.md, or a bounded Implementation Freedom. If the walkthrough
discovers a new fork or a human-relevant consequence hidden in another bucket,
reclassify it and present any resulting decision in the next legal batch.
quickstart.md
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
interfaces, constraints, traceability, contradictions, and bucket correctness.
Confirm no human-relevant fork was hidden as an engineering determination or
Implementation Freedom. Resolve findings or obtain the appropriate decision
approval. Do **not** call upstream analyze during plan: native analyze belongs
after tasks, when tasks.md exists.

## Step 4: Design approval

Present at most 20 lines: technical approach, approved human decisions,
material engineering determinations, explicit implementation freedoms,
validation approach, and mandatory “what I am least confident about”. Remind
the user that any determination/freedom may still be promoted before approval.
Wait for unambiguous approval. Changes produce a diff-only re-approval round.

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
