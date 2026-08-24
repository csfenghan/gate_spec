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
  `--refresh-constraints` option), and hand off to
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
exactly in English. Unless a higher-priority effective constraint requires a
different language, write every human-readable field value in Simplified
Chinese. Preserve `absent`, paths, SHA-256 values, API names, and code
identifiers verbatim. If a higher-priority language rule wins, record that
conflict and its resolution explicitly.

- An option conflicting with a constitution `MUST` is not a selectable option.
  Explain why it was excluded; amend the constitution in a separate
  user-directed operation before it can enter a later decision.
- A constitution `SHOULD` may be deviated from only with a recorded reason.
- Project/user GateSpec constraints may be exempted only by an explicit user
  decision recorded in Clarifications now and later in the plan Decision Log.
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

Technology choice alone never makes an item blocking. A conflicting or
requirement-violating candidate is excluded rather than used as a foil. If
fewer than two viable options remain, record the fixed Requirements consequence
or defer the mechanism to Design; when “do not build/change scope” is a genuine
alternative, ask that higher-level decision instead. When classification is
uncertain, use a blocking human decision. The user can cheaply veto any bucket
with natural language such as `discuss <topic>`; promote it to a decision or
pull a default into full discussion without creating stored workflow state.

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

Perform a fresh-eyes adversarial read for contradictions, terminology drift,
hidden guesses, and misclassification. Map every clarification, default, and
effective constraint to the body. Confirm technical-only matters did not become
Requirements choices and no human-relevant consequence was hidden as a default
or deferral. Resolve findings in the text or return/promote the affected item to
the inventory and present the next legal batch. Run:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh spec <feature-dir>
```

The command is expected to fail on Draft approval fields; every other failure
must be resolved before summary approval.

## Step 5: Requirements approval

Present at most 20 lines: goal (≤3 lines), P1 stories, key decisions, approved
defaults, scope boundaries, material technical matters explicitly deferred to
Design, and the mandatory line “what I am least confident about”. Remind the
user that any classification can still be challenged before approval. Wait for
unambiguous approval. On requested changes, update the Draft and show only the
diff since the previously shown version.

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
