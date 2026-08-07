---
description: "GateSpec gated specify: one-at-a-time decisions, frozen constraint basis, safe resume, and explicit requirements approval."
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

1. Never infer an unapproved decision. Unknowns remain a blocking question
   or a proposed default. Facts discoverable from the repository are looked
   up, not asked.
2. Ask exactly one blocking decision at a time, with 2–4 mutually exclusive
   options, a recommendation, and the applicable constraint result.
3. The user approves feature content in exactly three ways: individual
   decision answers, one batch approval of proposed defaults, and final
   approval of the compressed artifact summary/diff.
4. A user saying “done”, “proceed”, or equivalent while any blocking item is
   unresolved pauses the command. Preserve the Draft and explain the next
   unresolved item; never seal it.
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
- `--revise`: archive an existing `tasks.md` before editing, change Status to
  Draft, clear Gate Approval, preserve the prior approved snapshot for a diff,
  and use diff-only re-approval.
- `--restart`: archive spec.md plus existing plan/design/downstream artifacts
  (`plan.md`, `research.md`, `data-model.md`, `contracts/`, `quickstart.md`,
  `tasks.md`) under the feature's `.gatespec/archive/<timestamp>-restart/`,
  then rebuild spec.md from the template.

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

- An option conflicting with a constitution `MUST` may be shown but cannot be
  approved. Amend the constitution in a separate user-directed operation first.
- A constitution `SHOULD` may be deviated from only with a recorded reason.
- Project/user GateSpec constraints may be exempted only by an explicit user
  decision recorded in Clarifications now and later in the plan Decision Log.
- After Requirements approval the snapshot is frozen. A user-constraints hash
  change is warning-only; use `--refresh-constraints` to reopen and replace the
  snapshot. A project constitution change forces requirements re-approval.
  Treat a changed project constraints file as project policy and likewise
  reopen approval. Archive stale tasks before reopening.

`--refresh-constraints` implies the `--revise` diff flow and recomputes all
three sources. Never append personal constraints into the constitution.

## Step 3: clarify one decision at a time

Classify each unknown as blocking (changes scope, data, interface, technology,
or visible behavior) or non-blocking (routine detail with a safe conventional
default). The user can veto this classification cheaply by pulling any default
into full discussion.

For each blocking item, in dependency order:

1. State repository facts and the consequence of deciding.
2. Present 2–4 mutually exclusive options and the constraint result for each.
3. Recommend one option in 1–2 sentences.
4. Wait. “recommended” accepts the recommendation.
5. Record `- Q: ... → A: ...` under a dated Clarifications session.

Then present non-blocking items once as a numbered table. A single explicit
batch approval accepts them; pulled-out rows become one-at-a-time decisions.
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
and hidden guesses. Map every clarification, default, and effective constraint
to the body. Resolve findings in the text or ask one decision. Run:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh spec <feature-dir>
```

The command is expected to fail on Draft approval fields; every other failure
must be resolved before summary approval.

## Step 5: Requirements approval

Present at most 20 lines: goal (≤3 lines), P1 stories, key decisions, approved
defaults, scope boundaries, and the mandatory line “what I am least confident
about”. Wait for unambiguous approval. On requested changes, update the Draft
and show only the diff since the previously shown version.

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
