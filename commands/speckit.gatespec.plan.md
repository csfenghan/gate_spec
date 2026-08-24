---
description: "GateSpec gated plan: scenario-first human decisions, recorded engineering determinations, safe resume, and explicit design approval."
handoffs:
  - label: Add Source Design
    agent: speckit.gatespec.source-design
    prompt: Add the optional reviewed source-level sub-contract before native tasks.
    send: true
  - label: Skip to Native Tasks
    agent: speckit.tasks
    prompt: Skip optional Source Design, create native tasks, then run analyze before implement.
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

The current structured design-evidence contract is identified by the exact
field `**Design Evidence Schema**: 1`. If a plan declares another non-empty
schema version, stop rather than downgrade or guess how to rewrite it.

Resume behavior:

- No plan or an untouched setup output: initialize once from the GateSpec plan
  template at
  `.specify/extensions/gatespec/templates/gatespec-plan-template.md`.
- Draft: continue in place without recopying the template. If it predates
  Design Evidence Schema 1, add the field and restructure Design Detailing in
  place from repository facts and existing attachments; preserve every D ID,
  answer, and unaffected design statement.
- Valid Approved-Design with a valid Implementation Review Contract and no
  flag, plus Design Evidence Schema 1: keep every design artifact read-only and
  offer exactly two next steps—`__SPECKIT_COMMAND_GATESPEC_SOURCE_DESIGN__` or
  native `__SPECKIT_COMMAND_TASKS__`. Do not select Source Design implicitly.
- Approved-Design created before the Implementation Review Contract or Design
  Evidence Schema 1 existed must not hand off. There is no legacy bypass:
  automatically archive tasks and non-archive review contents, apply the
  existing `--revise` semantics (Draft status, cleared Gate Approval, preserved
  baseline), add the missing contract/evidence without rewriting unaffected
  decisions, and require one diff-only Design re-approval before regenerating
  native tasks.
- `--revise`: archive existing Source bundle, `tasks.md`, current reviews,
  revalidations, execution state, IA, and acceptance, change plan Status to
  Draft, clear Gate Approval, retain a baseline, and use diff-only re-approval.
- `--restart`: archive plan.md, research.md, data-model.md, contracts/,
  quickstart.md, tasks.md, reviews, revalidations, execution state, IA, and
  acceptance
  under `.gatespec/archive/<timestamp>-restart/`, then initialize a fresh
  GateSpec plan. Do not alter the approved spec or recursively archive an
  existing archive.

Any spec re-approval makes a plan with the old Requirements hash stale. Archive
tasks and current reviews, then re-plan; never continue executing stale tasks
or trust their receipts.

## Step 2: approve design decisions in adaptive batches

Before asking, make one complete discovery pass over the approved Requirements,
constraints, existing Draft design artifacts, and relevant repository facts.
Inspect the actual integration surface: existing entry points, modules/types,
call and dependency directions, execution contexts, object/resource ownership,
and setup/runtime/teardown conventions. Distinguish inspected current facts
from proposed names and mechanisms; never present an invented current symbol as
repository evidence.
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

Start each batch with one compact progress line containing the Design status
when useful, resolved/currently-known **human decision** counts, and this
batch's IDs and topics. Mention a dependency-blocked topic only when it helps
explain why it comes later; do not report a raw dependency count. Do not count
engineering determinations or Implementation Freedoms as decisions. Report the
other bucket counts only on the first inventory or after a material
reclassification, in one compact sentence that preserves the user's ability to
request expansion or promotion.
A hash-only refresh is not progress. A resumed answer recap, unchanged
constraint hash, or successful or absent hook stays out of the decision
introduction unless it requires user action or changes the available choices.

Present each platform-neutral Markdown decision as an engineering scenario,
not as a labeled questionnaire. Use this conversational shape:

1. A `### D<n>: <plain-language question>` heading understandable without
   artifact identifiers.
2. One to three short prose paragraphs describing the concrete current state,
   trigger, affected caller/operator/system, observable outcome or failure, and
   the decision boundaries. Use domain-native roles and actions.
   Keep relevant technical vocabulary intact: APIs, threads, lifecycle,
   protocol, state, and error terms must not become consumer analogies. Do not
   invent a click, button, page, or other UI proxy unless the feature itself has
   that UI.
3. When useful, one natural bridge sentence such as “This needs to determine
   whether ...”; it is prose, not a required field.
4. Two to four direct `- **A**: ...` option bullets applied to the same scenario.
   Mark the recommended bullet `- **A (Recommended)**: ...`. State observable
   behavior and trade-offs first, then only the mechanism needed to distinguish
   the options. Exclude dominated or forbidden foils.
5. One final natural recommendation sentence after the options, including any
   material caveat the user must understand.

Do not render standalone `Scenario`, `Fixed boundary`, `Why this needs you`,
`Options`, `Recommendation`, or `Technical basis` labels in the conversation.
Integrate fixed boundaries and decision-relevant evidence into the scenario,
options, or recommendation instead. If every option has the same constraint
result, state it once only when material rather than repeating it per option.
Put a citation next to a claim only when that source materially affects the
choice; provide full FR, prior-decision, constraint, repository, path, and flow
detail on `explain D<n>` or `explain <topic>`. This expansion is evidence, not
another approval mechanism.

The card remains self-contained: without opening cited artifacts, a reader can
restate the situation, decision boundary, alternatives, and human consequences.
Rewrite or split a card that fails this test. When applicable, append the
explicit warning
`⚠ High risk — explicit D<n>=<choice> authorization required; batch recommendation shortcuts do not cover this decision`
and its concrete reason; high-risk authorization is the exception that must
remain visibly separate.

Wait for the batch response. Accept an ID mapped to an option letter, exact
option label, or `recommended`, for example `D1=A; D2=recommended`. “Accept all
recommendations in this batch” answers every non-high-risk card in the current
batch only. Every high-risk card requires its explicit `D<n>` choice; this is
the normal individual-decision approval mechanism, not a fourth mechanism.

Validate all answers as a set before writing. Normalize each unambiguous,
unaffected conversational choice into the existing structured Decision Log
block under exact heading `### D<n>: <topic>`, retaining the `Scenario`, `Fixed
boundary`, `Why this needs you`, `Options`, `Recommendation`, `Technical basis`,
and one `**Approved**: <choice> (YYYY-MM-DD)` field. The conversational shape
does not change the artifact schema, and existing structured D blocks remain
valid and are not rewritten merely for presentation. Preserve unanswered IDs
and put them first in the next batch, refilling remaining capacity with newly
eligible independent decisions. If choices conflict or introduce a
cross-cutting constraint, retain unaffected approvals and turn only the
conflict into a reconciliation decision; never choose or revise an option
automatically. A constitution MUST conflict is not recorded.

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
but cannot remove, rename, or replace these six. Write exact
`**Design Evidence Schema**: 1` once near the Requirements content hash.

Each core dimension is either one inline `N/A — <specific reason>` /
`无额外约束 — <具体原因>` or the exact structured child fields in the template:

1. Thread/concurrency records execution contexts and affinity, directed
   cross-context control/data flow, synchronization or serialization,
   ordering, cancellation/backpressure, and race/deadlock/shutdown guarantees.
2. Lifetime/ownership records key objects, buffers, handles, or other
   resources; creation and owner; sharing/borrowing/copy/move rules; failure
   cleanup, reclamation order, and material memory/resource bounds. Do not
   invent low-level allocation detail that has no design consequence.
3. Modules/classes records inspected repository anchors and entry points, then
   labels every key target element `existing`, `modified`, or `new`, with its
   responsibility, unchanged boundary, and allowed/prohibited dependency
   directions.
4. Internal APIs/interactions records actual existing entry points, a
   language-native skeleton of key types/interfaces/functions without
   implementation bodies, the primary success flow and principal failure flow
   in call order, and input/output/error/thread-affinity/ownership semantics.
   Use the smallest labeled pseudocode needed only when declarations and flow
   cannot express a core state, concurrency, or algorithm invariant. If no
   executable contract changes, use `N/A — <reason>` for the skeleton field.
5. External contracts records affected API/CLI/config/event/schema surfaces,
   externally observable success and error behavior, and compatibility,
   migration, fallback, timing, retry, or idempotency rules when applicable.
6. Lifecycle records states and their owner, setup/runtime/teardown ordering,
   plus partial-startup, recovery, rollback, cancellation, and cleanup behavior
   when applicable.

Every populated dimension ends with `Technical basis` that cites the relevant
FRs, approved D IDs, constraints, inspected repository anchors, and exact
research/data-model/contracts references. References supplement rather than
replace the core fact: do not write only “see research.md”. Keep relationships
directional and explicit enough that a later documentation tool can derive a
component or sequence view without choosing an architecture. An ordered text
flow or `A -> B`/`A → B` edges are sufficient; Mermaid and other diagrams are
optional. This is design evidence, not a per-file edit list or production-ready
implementation draft.

Ensure every FR has a technical home and every design element traces to an FR
or approved decision. Remove unapproved gold-plating. Conduct an implementer's
walkthrough using only spec + design artifacts; close every non-trivial fork
as an approved human decision, a reasoned engineering determination in Design
Detailing/research.md, or a bounded Implementation Freedom. If the walkthrough
discovers a new fork or a human-relevant consequence hidden in another bucket,
reclassify it and present any resulting decision in the next legal batch.
quickstart.md
must provide a runnable end-to-end validation path for each P1 story.

Then conduct a review-source completeness walkthrough. A fresh reader using
only the approved Requirements, plan, and design attachments must be able to
reconstruct the design intent and change boundary; current-to-target component
integration; core contracts and primary success/failure interactions; thread,
ownership/resource, external behavior, and lifecycle rules; and the rationale
and trace for each. If doing so would require a new design choice or material
inference, close that gap as a human decision, engineering determination, or
bounded Implementation Freedom before approval. Never render an Implementation
Freedom as if the contract skeleton had already fixed it.

Fill the exact mandatory `## Implementation Review Contract`. Keep protocol
version `2` and the fixed Review Root, task-review, isolation, parallel, Git,
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

Present at most 20 lines: technical approach and current-to-target change
boundary, primary runtime flow, material concurrency/ownership rules, approved
human decisions, material engineering determinations, explicit implementation
freedoms, validation approach, and mandatory “what I am least confident
about”. Remind the user that any determination/freedom may still be promoted
before approval. Wait for unambiguous approval. Changes produce a diff-only
re-approval round.

On explicit approval only:

1. Set `**Status**: Approved-Design (YYYY-MM-DD)`.
2. Ensure `## Gate Approval` is the unique final H2 and contains only the user
   approval date and lowercase Content-SHA256 fields.
3. Hash exactly the content before Gate Approval using sha256sum, with macOS
   `shasum -a 256` fallback.
4. Run `check-gate.sh design <feature-dir>` and resolve every structural error.

Run peer `after_plan` hooks and report completion. Offer
`__SPECKIT_COMMAND_GATESPEC_SOURCE_DESIGN__` (optional source-level contract)
and `__SPECKIT_COMMAND_TASKS__` (skip it) as explicit alternatives. Both paths
converge unchanged at native `__SPECKIT_COMMAND_TASKS__` →
`__SPECKIT_COMMAND_ANALYZE__` → `__SPECKIT_COMMAND_IMPLEMENT__`. Required
GateSpec hooks check native tasks, obtain fresh REV-TASKS, automate fresh
implementation checkpoints, require REV-FINAL, and finally invoke
`__SPECKIT_COMMAND_GATESPEC_ACCEPT_IMPLEMENTATION__` for one whole-delivery
user acceptance. GateSpec does not replace upstream tasks/analyze/implement.
