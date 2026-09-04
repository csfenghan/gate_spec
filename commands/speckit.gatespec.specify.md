---
description: "GateSpec gated specify: scenario-first human decisions, frozen constraint basis, safe resume, and explicit requirements approval."
handoffs:
  - label: Gated Technical Plan
    agent: speckit.gatespec.plan
    prompt: Create a gated plan for the approved spec.
---

## User Input

```text
$ARGUMENTS
```

Recognized workflow flags are `--refresh-constraints`, `--revise`, and
`--restart`; all remaining text is the feature description. Reject unknown
flags and reject `--restart` combined with either revision flag.
Consider non-empty user input before proceeding.

## Non-negotiable rules

1. Never infer an unapproved human-relevant decision. Classify unknowns as a
   blocking human decision, a proposed default, or a technical matter deferred
   to Design. Facts discoverable from the repository are looked up, not asked.
2. Inventory approval-eligible blocking decisions and their dependencies before
   asking. Present only a current-frontier batch of 1–4 pairwise-independent
   decisions within the cognitive-load budget below. Every decision has 2–4
   viable mutually exclusive options, one shared scenario, a recommendation,
   and the applicable constraint result, and requires its own explicit answer.
3. The user approves feature content in exactly three ways: individual
   decision answers, one batch approval of proposed defaults, and final
   approval of the compressed artifact summary/diff.
4. A user saying “done”, “proceed”, or equivalent while any blocking item is
   unresolved pauses the command. Preserve the Draft and present the next
   legal unresolved batch; never seal it.
5. Once all blocking items and defaults are resolved, write/update the Draft
   automatically. Do not require a separate “write it” confirmation.
6. Establish one concrete Primary outcome before admitting scope. Complete that
   outcome with the smallest sufficient delivery; adjacent improvements are
   deferred by default and never receive item-by-item approval invitations.
7. Requirements records capabilities, observable semantics, lifecycle,
   compatibility, and verifiable quantity/timing/resource/thread-affinity/
   ownership constraints. Design is the first stage allowed to create names for
   new or changed APIs, functions, types, fields, namespaces/packages, internal
   thread components, queues/tasks/algorithms/data structures, or source paths,
   and to fix signatures, parameter types, overloads, and return types.
8. Treat every concrete solution in the user's request as transient input.
   Extract its Requirements-level intent, then discard the prospective names and
   declarations; never preserve the sketch in Input or a sidecar artifact.

## Step 0: run peer extension hooks

Inspect `.specify/extensions.yml` and execute registered `before_specify`
hooks in their declared order. Skip every hook whose command begins with
`speckit.gatespec.` so GateSpec never calls itself. Respect each hook's
`optional` behavior and stop on a required hook failure. After successful
approval, do the same for `after_specify` hooks.

## Step 1: resolve or create safely

Resolve `.specify/feature.json` (`feature_directory`) first. If no current
feature exists, create `<prefix>-<2-4-word-action-noun>` under `specs/`, using
`.specify/init-options.json` numbering (`timestamp` or next three-digit
`sequential`), copy
`.specify/extensions/gatespec/templates/gatespec-spec-template.md` (never the
upstream resolution-stack template), and persist pretty or compact valid JSON
in feature.json.

If a current GateSpec spec exists:

- Draft: continue in place. Never recopy the template or discard answers.
- Valid Approved-Requirements and no workflow flag: keep it read-only, report
  that it is approved (including any user-constraint drift warning and the
  `--refresh-constraints` option). If it is a legacy approval without Scope
  Contract Schema 1, the Requirements gate blocks Design and requires
  `--revise` unless a checked task, implementation-review receipt, or real
  production delta proves implementation is already underway. Progressed
  legacy delivery is warning-only and remains byte-for-byte read-only. If it
  is a legacy approval without Requirements Abstraction Schema 1, block Design
  and require `--revise` unless a checked implementation task, implementation-
  review receipt, real production delta, or valid Accepted delivery shows that
  implementation is already underway or complete. A progressed/Accepted legacy
  spec remains byte-for-byte read-only with a warning; do not retrofit or scan
  its historical wording as Schema 1. If it is a legacy approval without
  Delivery Estimate Schema 1, warn without
  editing it; Design must add the first estimate. A legacy Approved
  Requirements artifact without `### Test Control Policy Exceptions` also
  remains read-only and deterministically means TCE Mode `none`; a Protocol 3
  Plan may write the canonical none copy during `plan --revise`. Any desired
  TCE requires Requirements `--revise` and explicit high-risk approval. Then hand off to
  `__SPECKIT_COMMAND_GATESPEC_PLAN__`.
- `--revise`: archive Source Design, `tasks.md`, current reviews,
  revalidations, execution state, IA, and acceptance before editing; change
  Status to Draft, clear Gate Approval, preserve the prior approved snapshot
  for a diff, and use diff-only re-approval.
- `--restart`: archive spec.md plus existing plan/design/downstream artifacts
  (`plan.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`,
  `tasks.md`, current reviews/revalidations, execution state, IA, and
  acceptance) under the
  feature's `.gatespec/archive/<timestamp>-restart/`, then rebuild spec.md from
  the template. Never recursively archive an existing archive.

Archive before overwriting or moving any artifact. An invalid Approved
artifact is not read-only: report the gate failure and require `--revise` or
`--restart`; never repair approval fields automatically.

## Step 2: derive and freeze the Constraint Basis

Automatically read, when present, in this precedence order:

1. project constitution: `.specify/memory/constitution.md` (highest),
2. project constraints: `.gatespec/constraints.md`,
3. user constraints: `~/.gatespec/constraints.md` (lowest).

Compute a lowercase SHA-256 for each present source. Merge rules explicitly:
record every conflict, the winning source, any allowed deviation, and the
final effective wording in spec.md `## Constraint Basis`. Requirement-impacting
conclusions must also land in an FR, Acceptance Scenario, Assumption, or scope
boundary; Constraint Basis alone is not self-containment.

Keep the `## Constraint Basis` heading and its five template field labels
exactly in English. Also keep its mandatory nested
`### Test Control Policy Exceptions *(gatespec: mandatory)*` section. If no
higher-priority effective constraint requires a different language,
write every human-readable field value in Simplified Chinese. Preserve `absent`,
paths, SHA-256 values, API names, and code identifiers verbatim. If a
higher-priority language rule wins, record that conflict and its resolution
explicitly.

- An option conflicting with a constitution `MUST` is not a selectable option.
  Explain why it was excluded; amend the constitution in a separate
  user-directed operation before it can enter a later decision.
- A constitution `SHOULD` may be deviated from only with a recorded reason.
- Project/user GateSpec constraints may be exempted only by an explicit user
  decision recorded in Clarifications. A Test Control policy deviation uses
  only the dedicated TCE table and rules below; Plan copies its approved result
  and engineering consequences without asking again.
- After Requirements approval the snapshot is frozen. A user-constraints hash
  change is warning-only; use `--refresh-constraints` to reopen and replace the
  snapshot. A project constitution change forces requirements re-approval.
  Treat a changed project constraints file as project policy and likewise
  reopen approval. Archive stale Source/tasks, reviews/revalidations,
  execution state, IA, and acceptance before reopening.

`--refresh-constraints` implies the `--revise` diff flow and recomputes all
three sources. Never append personal constraints into the constitution.

## Step 3: inventory and clarify in adaptive batches

Before asking, make one complete discovery pass over the request, approved or
Draft artifact, constraints, and relevant repository facts. Run independent
read-only searches in parallel when the platform supports it. Classify every
known unknown into exactly one conversational bucket:

1. **Blocking human decision** — at least two viable options satisfy all
   frozen `MUST` rules, and a reasonable product owner, operator, maintainer,
   or affected user could prefer either because it changes scope, workflow,
   visible behavior, data handling, security/privacy, compatibility, measurable
   cost/performance, irreversible risk, or an approvable constraint trade-off.
2. **Proposed default** — a routine non-blocking detail has a safe conventional
   answer and no material reason for individual discussion.
3. **Technical matter deferred to Design** — the unknown changes only an
   implementation mechanism and has no Requirements-level consequence.

In the same pass, first write one unique, specific Primary outcome in terms of
the participant, current state, trigger, and one observable result delivered
now. Requirements stay at the level of concrete user workflow, external
behavior, and retained restrictions. Source files, classes, threads, and other
implementation choices remain Design matters and never create a capability
row by themselves. A verifiable constraint such as one internal execution
thread per instance serializing a stated task set is Requirements-level even
though the thread's name and implementation are not. Existing-system
compatibility anchors and indispensable external standard or wire identifiers
may remain, but they never instantiate a prospective code interface.

Before classifying scope or decisions, isolate any user-supplied implementation
proposal. Do not quote it into `spec.md`, retain it in `$ARGUMENTS` form, or save
it in research, notes, or another cross-stage file. Translate it into capability
and observable semantics. These mappings are normative examples:

- `Submit(...) -> Result<RequestHandle>` becomes “submission does not wait for
  remote completion; the caller can synchronously distinguish acceptance from
  rejection; accepted work provides per-request cancellation.”
- `WorkerThread` becomes “each instance has exactly one internal execution
  thread, which serially performs the agreed task set.”
- `Cancel()` becomes “the caller can request cancellation of accepted work and
  receives one deterministic terminal outcome.”

Apply the same transformation to every prospective API/function/class/enum/
field/namespace/package/source-path name, parameter or return type, overload or
complete declaration, and named internal thread/queue/task/algorithm/data
structure. Preserve only the capability, observable success/error and terminal-
state semantics, lifecycle/compatibility effect, and verifiable resource,
timing, affinity, or ownership constraint that motivated it.

The canonical Test Control policy is a universal engineering boundary, not
feature scope and not a per-hook human choice. Requirements names the
observable production invariant and executable success/failure outcome; it
never requests a concrete testing overload/parameter/getter/state,
`/src/testonly` surface, hook switch, validator, path::symbol, or TC-###.
Protocol 3 Design freezes the canonical policy plus any valid Requirements TCE
overlay, and native tasks later registers an exact control, if any, after
proving the invariant is otherwise unreachable. No hook receives individual
approval.

Default the mandatory TCE subsection to exact Mode `none` and its sole
five-cell all-`none` row. A deviation is legal only when at least two viable
Requirements options exist, the user explicitly selects it in a high-risk
`R<n>` card presented alone, and the concluded Clarification states the
replacement and consequence. Then use Mode `approved` and continuous
`TCE-001...` rows. `Rule` is exactly one of `source-root`, `language-marker`,
`formal-api`, `switch-identifier`, `control-model`, `touchpoint-shape`, or
`validator-path-marker`; the decision cell is the one existing `R<n>` ID.
Several rows may cite the same single bundled high-risk decision.
Each row gives a precise replacement source-auditable mechanism and its reason
and consequence. It may override only that named semantic rule, never infer a
wildcard exception or pre-register a concrete control, path::symbol,
touchpoint, switch, wiring, validator, or consumer.
The canonical table header names this column
`Replacement source-auditable mechanism`. The Protocol 3
structural/lifecycle floor remains non-exemptable.

No TCE may weaken native-task-only registration, Closure/Audit/manifest/
evidence/hash schemas, or isolated-clone lifecycle. It also cannot weaken the
dedicated explicit opt-in default-OFF switch, runtime/umbrella-trigger ban,
complete OFF elision, Bash two-lane validation, same normal tests plus ON
consumers, current-clone output derivation/no-literal-or-echo rule, named-gap
and real-consumer requirements, orphan ban, or removal boundary. Every
replacement must remain compatible with that floor. Design, Source, tasks,
IA, and reviewers cannot create, change, delete, or broaden a TCE; a newly
needed deviation returns through `gatespec.specify --revise` and fresh
Requirements approval.

Apply this counterfactual admission test to each capability that is actually in
view:

1. If removing it makes the Primary outcome fail, admit it as `core`.
2. Otherwise, if the user explicitly requested it in the same delivery, admit
   it as `committed`.
3. Otherwise, if an effective `MUST` requires it, admit it as `constraint`.
4. Otherwise record it, when material, as `deferred`: it is outside this
   delivery and is not a promise to implement it later.

Do not expose the CAP ID or admission vocabulary in conversation. Do not
proactively enumerate neighboring features. Record or discuss an adjacent
capability only when the user raised it, the original request has reasonable
scope ambiguity, or Design is likely to introduce it accidentally unless the
boundary is explicit. An AI-discovered improvement that is unnecessary for the
Primary outcome is deferred by default without an individual question. A user
can still challenge any admission before the final Requirements approval.

As part of that same pass, identify independently deliverable capabilities
that can also be validated alone. When at least one reasonable split preserves
useful standalone value and materially changes delivery scope, present merge versus
one or more concrete split boundaries as an ordinary blocking `R<n>` decision.
State what each deliverable contains and what the user receives first. Do not
create sibling specs automatically. A decision to split narrows this feature's
Requirements now; a later split discovered after approval returns through
`--revise`. If no reasonable independent split exists, record no decision.

Technology choice alone never makes an item blocking. A conflicting or
requirement-violating candidate is excluded rather than used as a foil. If
fewer than two viable options remain, record the fixed Requirements consequence
or defer the mechanism to Design; when “do not build/change scope” is a genuine
alternative, ask that higher-level decision instead. When classification is
uncertain, use a blocking human decision. The user can cheaply veto any bucket
with natural language such as `discuss <topic>`; promote it to a decision or
pull a default into full discussion without creating stored workflow state.

Requirements decision cards compare semantic consequences only. If every
option preserves capability, observable behavior, compatibility, lifecycle,
and measurable constraints and differs only in a prospective name, signature,
parameter/return type, overload, declaration, class structure, algorithm, or
source layout, ask nothing at Requirements: defer the fork to Design. An
explicit user request for one such shape does not make that shape `committed`;
only the extracted capability may enter the Scope Contract.

Build an ephemeral dependency graph for blocking human decisions; never persist
it, the classification inventory, or batch state as a new workflow artifact.
Decision A depends on B when any choice for B can change A's existence,
scenario, options, recommendation, or constraint result. If independence is
uncertain, add the dependency. Collapse a dependency cycle into one composite
decision whose options are coherent bundles. On resume, re-derive the inventory
from repository artifacts and facts.

Assign a stable `R<n>` when a blocking decision is first presented and retain
it in later batches while conversation context is available. For an existing
Draft, do not rewrite concluded Clarifications that lack IDs. Choose the next
number as one greater than both the number of existing concluded Q/A entries
and the greatest existing `R<n>`. Record an accepted answer as
`- Q: [R<n>] ... → A: ...` under a dated Clarifications session.
Preserve every accepted ID. If an unanswered legacy card is reclassified,
explain the change and never reuse its retired ID when that assignment remains
recoverable from the conversation or Draft; never persist a separate ID ledger.

For batch sizing, mark a decision **complex** when it has 3–4 viable options,
spans multiple FR groups/artifacts/external contracts, or requires a multi-step
flow, failure, or migration explanation. Mark it **high risk** when it grants a
constraint exemption or constitution SHOULD deviation, controls irreversible
or data-migration behavior, affects security/privacy/compliance, or breaks an
external compatibility contract. Use the higher classification when unsure.
A normal card costs one unit; any complex or high-risk card consumes the full
four-unit cognitive budget and is the only decision card in its round. A batch
contains at most four normal cards and total load at most four.

Choose cards only from the unresolved dependency frontier. Prefer cards sharing
one actor or user journey; present fewer rather than mix unrelated mental
contexts. Within a coherent set, prefer items that unlock the most downstream
decisions, then P1/external behavior, then discovery order.

Before the cards, show one compact progress line containing the Requirements
status when useful, resolved/currently-known **human decision** counts, and this
batch's IDs and topics. Mention a dependency-blocked topic only when it helps
explain why it comes later; do not report a raw dependency count. Do not count
defaults or technical matters as decisions. Report the other bucket counts only
on the first inventory or after a material reclassification, in one compact
sentence that preserves the user's ability to request discussion.
A hash-only refresh is not progress. A resumed answer recap, unchanged
constraint hash, or successful or absent hook stays out of the decision
introduction unless it requires user action or changes the available choices.

Present each platform-neutral Markdown decision as an engineering scenario,
not as a labeled questionnaire. Use this conversational shape:

1. A `### R<n>: <plain-language question>` heading understandable without
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
choice; provide full repository, constraint, and identifier detail on
`explain R<n>` or `explain <topic>`. This expansion is evidence, not another
approval mechanism.

The card remains self-contained: without opening cited artifacts, a reader can
restate the situation, decision boundary, alternatives, and human consequences.
Rewrite or split a card that fails this test. When applicable, append the
explicit warning
`⚠ High risk — explicit R<n>=<choice> authorization required; batch recommendation shortcuts do not cover this decision`
and its concrete reason; high-risk authorization is the exception that must
remain visibly separate.

For a scope decision, describe the current workflow, its one concrete gap, and
the existing burden or behavior the minimum sufficient option deliberately
retains. A broader option must state which external interface, caller flow, or
compatibility behavior changes. Never show CAP classifications, source paths,
classes, threads, or per-option LOC in the Requirements card. Recommend the
smallest option that fully delivers the Primary outcome; “more complete”,
“more elegant”, or “more extensible” is not by itself a reason to expand this
delivery.

Wait for the batch response. Accept an ID mapped to an option letter, exact
option label, or `recommended`, for example `R1=A; R2=recommended`. “Accept all
recommendations in this batch” explicitly answers every non-high-risk card in
the current batch only. It never answers a high-risk card or approves defaults.
A high-risk `R<n>` choice is still the existing individual-decision approval
mechanism, not a fourth approval mechanism.

Validate the response as a set before writing. Record every unambiguous answer
whose validity is unaffected by another answer. Preserve unanswered IDs and
put them first in the next batch, then refill unused capacity with newly
eligible independent cards. If answers conflict or introduce a cross-cutting
constraint, keep unaffected answers and turn only the conflict into an
explicit reconciliation decision; never choose or revise an option
automatically. A constitution MUST conflict remains unapprovable and is not
recorded.

Honor cheap, non-persistent controls such as `split R2`, `ask one next round`,
or `next round at most N` (1–4). They affect only the named/current next round
and do not create a workflow flag or stored preference. A user may also defer a
card; it remains unresolved and blocks final approval, while other independent
work may continue.

Present all proposed defaults exactly once as the existing numbered defaults
table. The defaults table may occupy one normal card in a blocking-decision
batch only when every row is independent of every unresolved and concurrently
presented decision; it never shares a round with a complex or high-risk card.
Otherwise defer it. It always requires its own explicit
batch approval such as “approve defaults”. A decision shortcut never approves
it. Pulled-out rows receive new `R<n>` IDs and re-enter the blocking inventory.
Record approved rows with `✅ YYYY-MM-DD`.

Use these exact empty states when applicable (a blank section never passes):

```markdown
- None — <specific reason no blocking clarification was required>
- None — <specific reason no non-blocking default was required>
```

## Step 4: write and self-check the Draft

After all blocking/default items are resolved, fill the existing Draft's
upstream sections: User Scenarios & Testing, Requirements, Success Criteria,
and Assumptions. Acceptance Scenario lines each carry `(covers FR-xxx)`;
every unique FR is defined exactly once in Functional Requirements and has at
least one scenario. Remove all template examples and residual markers.

Replace the raw request with exactly one normalized
`**Input**: Requirements intent: ...` line and write exact
`**Requirements Abstraction Schema**: 1` once. Never preserve a `User
description` Input or create a sidecar containing the discarded solution
sketch. The normalized intent is semantic prose subject to the same abstraction
rules as the Requirements body.

Write exact `**Scope Contract Schema**: 1` and one `## Scope Contract`. Record
Primary outcome, canonical Core completion SC refs, and Retained baseline
(including `None — <reason>` when nothing material is retained). The table has
one stable `CAP-###` row for each material in-view capability and uses only
`core`, `committed`, `constraint`, or `deferred`. Every current FR and SC maps
to at least one non-deferred CAP; every non-deferred CAP maps at least one FR
and one SC; every Core completion SC belongs to a core CAP; deferred rows use
exactly `none` for Spec refs. A constraint CAP must cite a real effective MUST
in its rationale rather than laundering an engineering preference. CAP IDs do not enter tasks Closure:
downstream closure remains CAP → FR/SC → task.

Perform a fresh-eyes adversarial read for contradictions, terminology drift,
hidden guesses, and misclassification. Map every clarification, default, and
effective constraint to the body. Confirm technical-only matters did not become
Requirements choices and no human-relevant consequence was hidden as a default
or deferral. Validate the TCE subsection: Mode `none` has only the exact
all-`none` row; Mode `approved` has continuous TCE IDs, allowlisted Rule tokens,
one real concluded `R<n>` per row, precise replacement/consequence cells, no
concrete hook registration, and no relaxation of the non-exemptable floor.
Resolve findings in the text or return/promote the affected item to the
inventory and present the next legal batch.

Perform a separate abstraction audit over Input, Clarifications, Approved
Defaults, Scope Contract, User Scenarios & Testing, Requirements, Success
Criteria, and Assumptions. Remove prospective API/function/class/enum/field/
namespace/package/source-path names; signatures, parameter/return types,
overloads, declarations; and named internal threads, queues, task types,
algorithms, and data structures. For every statement prove all three:

1. the requirement remains true after arbitrary renaming of every prospective
   code symbol;
2. at least two implementation shapes can satisfy it; and
3. its acceptance result can be described without inspecting a prospective
   source declaration.

An existing-system anchor or indispensable external standard/wire identifier is
allowed only when its role is explicit and it does not instantiate the new
interface. The checker catches only high-confidence textual shapes; investigate
every located warning and either establish such an allowed anchor or remove the
prospective identifier. A clean checker result does not prove this semantic
audit.

Estimate the complete approved feature and write exact
`**Delivery Estimate Schema**: 1` plus one `## Delivery Estimate`. Use
non-negative `lower..upper` intervals for Production additions, Production
churn, and Production files. Churn means additions + deletions. Production
code includes handwritten runtime code, headers, protocols/schema,
configuration, and build/packaging logic. Exclude tests, specification/review
metadata, pure documentation, and reproducibly generated outputs. A generated
output may be excluded only as
`generated: <output path> <- <source path> via <generator>`; otherwise count it
as production. Record the capability/analogy basis, production path families,
all exclusions, and a candid confidence with reason. Requirements may use a
wide range and low confidence. There is no size, file-count, or checkpoint
limit: disclosure enables the user's existing scope approval or split choice.

Then run:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh spec <feature-dir>
```

The command is expected to fail on Draft approval fields; every other failure
must be resolved before summary approval.

## Step 5: Requirements approval

Present at most 20 lines: Primary outcome, retained baseline, P1 stories, key
decisions, approved defaults, explicitly committed delivery items, important
deferred capabilities, all three Delivery Estimate ranges and confidence,
material technical matters explicitly deferred to Design, TCE Mode and any
approved TCE IDs/rules (without soliciting per-hook approval), and the mandatory
line “what I am least confident about”. Make clear that this one normal
Requirements summary approval accepts both the Scope Contract and disclosed
whole-feature size; neither adds another approval mechanism. Remind the user
that any admission or classification can still be challenged before approval.
The summary is also Requirements-semantic content: do not reintroduce any
discarded prospective identifier, signature, type, or source shape.
Wait for unambiguous approval. On requested
changes, update the Draft and show only the diff since the previously shown
version.

On explicit approval only:

1. Set `**Status**: Approved-Requirements (YYYY-MM-DD)`.
2. Ensure `## Gate Approval` is the unique final H2 and contains only:
   `- **Approved by user**: YYYY-MM-DD` and
   `- **Content-SHA256**: \`<lowercase 64-hex>\``.
3. Hash exactly everything before that H2 with
   `sed '/^## Gate Approval/,$d' spec.md | sha256sum` (macOS fallback:
   `shasum -a 256`).
4. Run the requirements checker and do not report completion unless it passes.

Post-approval edits always use Draft + diff re-approval. Report the feature
path and risks, run peer `after_specify` hooks, then hand off to
`__SPECKIT_COMMAND_GATESPEC_PLAN__`.
