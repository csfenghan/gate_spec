---
description: "GateSpec gated specify: clarify through one-at-a-time questioning with recommendations, zero auto-inference, explicit user approval before the spec is final."
handoffs:
  - label: Gated Technical Plan
    agent: speckit.gatespec.plan
    prompt: Create a gated plan for the approved spec.
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Core Philosophy (read first — everything below follows from it)

1. **Never guess.** Anything the user has not confirmed stays an explicit
   `[NEEDS CLARIFICATION: ...]` marker or a proposed default in the
   Approved Defaults table. "Make an informed guess" is FORBIDDEN in this
   command, no matter how obvious the answer seems.
2. **Facts are looked up, not asked.** If a question can be answered by
   reading the codebase, config, or environment — answer it yourself and
   state what you found. Only *decisions* go to the user.
3. **The user approves, you propose.** Every question carries your
   recommendation with reasoning, so the user can answer with one word.
4. **One decision at a time.** Never present multiple blocking questions at
   once. Walk the decision tree branch by branch, resolving dependencies
   in order.
5. **No approval, no spec.** Do not write spec content into the file until
   the user has confirmed shared understanding. Chat is not spec.

## Setup

1. **Generate a concise short name** (2-4 words, action-noun format) for the
   feature from the feature description, e.g. "config-hotreload".

2. **Create the feature directory** following the upstream resolution rules:
   - Specs live under `specs/` unless the user explicitly provides
     `SPECIFY_FEATURE_DIRECTORY`.
   - Check `.specify/init-options.json` for `feature_numbering`:
     `"timestamp"` → `YYYYMMDD-HHMMSS` prefix; `"sequential"` or absent →
     next available 3-digit number after scanning `specs/`.
   - Directory name: `<prefix>-<short-name>`; set
     `SPECIFY_FEATURE_DIRECTORY=specs/<directory-name>`.
   - `mkdir -p SPECIFY_FEATURE_DIRECTORY`
   - Copy `.specify/extensions/gatespec/templates/gatespec-spec-template.md`
     to `SPECIFY_FEATURE_DIRECTORY/spec.md` (use THIS template by explicit
     path — never the resolution-stack `spec-template`, which belongs to the
     upstream auto track).
   - Persist to `.specify/feature.json`:
     `{ "feature_directory": "<resolved feature dir>" }`

3. **Load constraints** (both, if present; project constitution wins on
   conflict):
   - `.specify/memory/constitution.md` (or `/memory/constitution.md`)
   - `~/.gatespec/constraints.md` (user-level standing constraints)

## Clarification Protocol (grilling-style)

Scan the feature description and the codebase context for unknowns. Split
them into two classes:

- **Blocking** — the answer changes scope, data structures, interfaces,
  technology choices, or user-visible behavior. Multiple reasonable
  interpretations with different implications exist.
- **Non-blocking** — wording, formatting, routine configuration, or details
  with a safe conventional default.

### Blocking unknowns: one at a time

For each blocking unknown, in decision-tree dependency order:

1. State **context** (what you found, with file:line if from the codebase).
2. Ask **exactly one** question, offering 2-4 mutually exclusive options.
3. Give your **recommendation** with 1-2 sentences of reasoning, including
   any constitution/constraints check result.
4. **Wait** for the user's answer. "yes"/"recommended" accepts your
   recommendation.
5. Record the outcome; only then proceed to the next question.

Keep asking until the decision tree is exhausted or the user signals
"done / 够了 / proceed". Never batch blocking questions.

### Non-blocking unknowns: batch defaults table

Present ONCE, after blocking questions (or when the user asks to move on):

```markdown
以下 N 项建议默认值，无异议回"过"；要展开讨论的说编号：
| # | 项 | 建议默认 |
|---|-----|---------|
| 1 | ... | ... |
任何一项都可以要求展开为完整决策讨论。
```

Items the user pulls out become blocking questions (one at a time).

### Record everything

Every accepted answer — blocking or default — goes into working memory for
the spec's `## Clarifications` (as `### Session YYYY-MM-DD` with
`- Q: ... → A: ...` entries) and `## Approved Defaults` rows.

## Writing the Spec

Only after the user confirms shared understanding ("写吧 / 可以了 / approve"):

1. Fill the template's upstream sections (User Scenarios & Testing,
   Requirements, Success Criteria, Assumptions) with the confirmed content.
   - User stories: prioritized, independently testable, acceptance scenarios
     tagged `(covers FR-xxx)` so every FR is referenced by ≥1 scenario.
   - Requirements: testable, unambiguous, technology-agnostic.
   - Success criteria: measurable, user-focused.
2. **Self-containment mapping** (mandatory): walk every entry in
   `## Clarifications` and every `## Approved Defaults` row, and point to
   where its conclusion lands in the body (FR, scenario, assumption). Any
   conclusion with no landing spot MUST be written into the body now. A
   reader who never saw this conversation must be able to implement from
   spec.md alone.
3. **Fresh-eyes adversarial read** (mandatory): re-read the whole spec as
   an implementer who never participated in this conversation. Hunt for:
   internal contradictions, terminology drift (same thing, two names),
   places where you would have to guess. Resolve every finding in the text,
   or present it to the user for explicit acceptance. Log findings as a
   final `### Session` entry in `## Clarifications`.
4. **Vague-word lint** (warning): flag occurrences of unquantified wording
   ("fast", "friendly", "reasonable", "尽量", "合理", ...) to the user.

## Approval (the Requirements Gate)

1. Present a summary of **at most 20 lines**: the goal (≤3 lines), P1 user
   stories, the key decisions made, explicit scope boundaries, and —
   mandatory — **"what I am least confident about"** (the one spot most
   worth the user's scrutiny).
2. Wait for explicit approval. Silence, "looks good"-adjacent ambiguity, or
   a change request is NOT approval. If the user requests changes: apply
   them, and present ONLY the diff since the last shown version.
3. On explicit approval:
   - Set `**Status**: Approved-Requirements (YYYY-MM-DD)`
   - Fill `## Gate Approval`:
     - `**Approved by user**: YYYY-MM-DD`
     - `**Content-SHA256**`: compute exactly:
       `sed '/^## Gate Approval/,$d' spec.md | sha256sum | cut -d' ' -f1`
       (fallback `shasum -a 256`)
4. **Post-approval edits**: any later change to spec.md (by anyone) MUST
   first revert Status to Draft, present the diff, and re-approve. The hash
   makes drift machine-detectable — never bypass it.

## Done When

- [ ] All blocking decisions answered by the user, one at a time, recorded
- [ ] Non-blocking defaults batch-approved (or pulled out and discussed)
- [ ] spec.md complete: upstream sections intact, Clarifications conclusions
      all landed in body, fresh-eyes read findings resolved
- [ ] User explicitly approved the ≤20-line summary
- [ ] Status set, Content-SHA256 recorded
- [ ] Completion reported: feature dir, spec path, open risks; suggest
      `__SPECKIT_COMMAND_GATESPEC_PLAN__` as the next step
