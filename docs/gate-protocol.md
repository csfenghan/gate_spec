# GateSpec 0.2.0 Gate Protocol

This document defines the contract implemented by the three public commands,
two fixed hook entries, artifact templates, and `check-gate.sh`.

## Architecture

GateSpec is a parallel gated path, not an upstream replacement:

```text
auto:   speckit.specify ─→ speckit.plan ─┐
                                         ├→ speckit.tasks → speckit.analyze → speckit.implement
gated:  gatespec.specify ─→ gatespec.plan┘
```

Line 1 of a gated spec is exactly `<!-- path: gatespec -->`. If the marker is
absent everywhere, checks return zero without output. If it appears anywhere
except line 1, the artifact is corrupt and fails. This dispatch is the
load-bearing dual-track boundary.

Approval is a snapshot, not a state machine. Prompt rules produce artifacts;
one portable Bash checker validates deterministic structure and hashes.

## Constraint Basis

Both phases automatically read project constitution, project
`.gatespec/constraints.md`, and user `~/.gatespec/constraints.md`, in that
descending priority. `Constraint Basis` freezes each source hash, all effective
rules, and every conflict resolution. A constraint conclusion that changes the
feature must also appear in an FR, scenario, Assumption, or scope boundary.

- A constitution `MUST` conflict may be shown as an option but cannot be
  approved. Constitution amendment is an independent operation.
- A constitution `SHOULD` deviation needs a recorded reason.
- Either GateSpec constraints layer may be exempted only by an explicit feature
  decision; design exemptions also appear in the Decision Log.
- User-constraints drift after Requirements approval warns but does not mutate
  the snapshot. `--refresh-constraints` reopens Requirements. Constitution or
  project-policy drift forces re-approval.

## Requirements protocol

Repository facts are discovered. Unknown decisions are divided into blocking
and proposed-default classes, with a cheap user veto: any default can be pulled
into a full one-at-a-time discussion.

Each blocking call presents context, 2–4 mutually exclusive choices, constraint
results, and a recommendation, then waits. Proposed defaults are shown once and
batch-approved. These are the first two feature-content approval mechanisms.
If the user asks to proceed with a blocking item unresolved, the Draft is
preserved and the session pauses. Once blocking/default work is complete, the
Draft is written without a fourth “write it” approval.

Empty sections have fixed semantics:

```markdown
## Clarifications
- None — <reason>
## Approved Defaults
- None — <reason>
```

Before final review, each conclusion is landed in the body and a fresh-eyes
adversarial read checks contradictions, terminology, and hidden guesses. Every
FR has one definition in Functional Requirements and at least one reference
inside an Acceptance Scenario; every Acceptance Scenario references a defined
FR.

The third approval mechanism is explicit approval of a ≤20-line Requirements
summary containing “what I am least confident about”. Revisions show only the
diff since the last reviewed content.

## Design protocol

The Requirements Gate passes before planning. The plan records
`Requirements Content-SHA256`, computed over the approved spec before its Gate
Approval H2. Any spec re-approval invalidates an old plan.

Every non-trivial decision uses an exact `### D<n>: <topic>` block and presents
at least two concrete scenarios (command, file tree, flow trace, or failure
picture), observable trade-offs, constraint results, and a recommendation.
The chosen option is recorded once with a date. No-decision designs record:

```markdown
- None — <reason no non-trivial decision exists>
```

The six exact core Design Detailing dimensions are concurrency, object
lifetime/ownership, modules/classes, internal API interactions, external
behavior contracts, and setup/runtime/teardown. Each has substantive content
or `N/A — <reason>`; constraints may only add dimensions.

An implementer's walkthrough closes every unsigned fork as an approved decision
or bounded Implementation Freedom. Bidirectional traceability prevents orphan
FRs and unapproved design. quickstart provides an end-to-end path per P1 story.
Immediately before summary, the agent internally checks spec, plan, research,
data model, contracts, and quickstart for consistency. It does not invoke
upstream analyze early; analyze follows native tasks.

## Safe reruns

| State/flag | Required behavior |
|---|---|
| Draft, no flag | Continue in place; never recopy the template. |
| Valid Approved artifact | Read-only; hand off to the next phase. |
| `--revise` | Archive tasks, reopen Draft, preserve baseline, diff re-approve. |
| `--restart` | Archive phase/downstream artifacts, then rebuild template. |
| `--refresh-constraints` | Recompute spec basis and enter revision flow. |

Invalid approval metadata is never auto-repaired. Restart/revision archives
stale tasks so old execution work cannot silently survive a new basis.

## Snapshot format

`## Gate Approval` occurs exactly once, is the final H2, and contains only:

```markdown
- **Approved by user**: YYYY-MM-DD
- **Content-SHA256**: `<lowercase 64-hex>`
```

The Status approval date must agree. The digest is computed exactly as:

```bash
sed '/^## Gate Approval/,$d' artifact.md | sha256sum
# macOS: ... | shasum -a 256
```

## Machine-check boundary

Requirements checks cover the line-1 marker; unique mandatory sections;
clarification/default formats; residual/template markers; unique, scoped FR
definitions; scenario references; approval structure/date/hash; and warning-only
vague wording.

Design includes Requirements, then checks an exact Requirements hash chain,
unique exact D-blocks (D1 cannot consume D10), zero-decision syntax, six exact
unique dimensions and N/A reasons, mandatory upstream sections, template
remnants, and approval snapshot.

Semantic sufficiency, self-consistency, concrete option quality, and
gold-plating remain prompt self-checks plus human summary approval.

## Hook contract

`before_plan` is permanently bound to `check-requirements`; `before_tasks` is
permanently bound to `check-design`. The manual `check [spec|design]` may infer
a default only for interactive use. Gated commands execute peer extensions'
same-phase before/after hooks while excluding `speckit.gatespec.*`, preventing
self-recursion and retaining extension interoperability.
