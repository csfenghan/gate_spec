# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]

**Status**: Draft

**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

**Requirements Content-SHA256**: `[approved spec content hash]`

<!--
  GATESPEC GATE FIELDS (do not remove):
  - **Status** transitions: Draft → Approved-Design (YYYY-MM-DD).
    Set ONLY by explicit user approval of the plan summary / diff round.
  - Any post-approval edit MUST revert Status to Draft and re-approve.
  - This template keeps every upstream plan-template section intact so core
    speckit.tasks / speckit.implement can consume it unchanged.
-->

## Summary

[Extract from feature spec: primary requirement + technical approach from research]

## Technical Context

**Language/Version**: [e.g., Python 3.11, C++20 or NEEDS CLARIFICATION]

**Primary Dependencies**: [e.g., FastAPI, UIKit or NEEDS CLARIFICATION]

**Storage**: [if applicable, e.g., PostgreSQL, files or N/A]

**Testing**: [e.g., pytest, GoogleTest or NEEDS CLARIFICATION]

**Target Platform**: [e.g., Linux server, iOS 15+ or NEEDS CLARIFICATION]

**Project Type**: [e.g., library/cli/web-service/mobile-app or NEEDS CLARIFICATION]

**Performance Goals**: [domain-specific or NEEDS CLARIFICATION]

**Constraints**: [domain-specific or NEEDS CLARIFICATION]

**Scale/Scope**: [domain-specific or NEEDS CLARIFICATION]

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

[Gates determined from the spec's frozen Constraint Basis: project
constitution > project .gatespec/constraints.md > user
~/.gatespec/constraints.md. Constitution MUST conflicts are not approvable;
SHOULD deviations require reasons; GateSpec-rule exemptions require an
explicit Decision Log approval.]

## Decision Log *(gatespec: mandatory)*

<!--
  GATESPEC: One block per non-trivial decision. The gate fails while any
  block has an empty **Approved** field.
  Rules for each block:
  - Adaptive batches are conversational only; each block remains one separately
    approved decision with its stable D<n> ID
  - ≥2 options, each with a CONCRETE scenario (command session, file tree,
    failure-in-the-field picture) — abstract quality words alone are forbidden
  - Trade-offs stated as observable behavior, recommendation with reason
  - **Approved** filled with the user's explicit choice + date
-->

### D1: [decision topic]

- **Context**: [what forces this decision]
- **Options**:
  - A. [option] — concrete scenario: [what using it looks like]; trade-off: [observable consequence]
  - B. [option] — concrete scenario: [...]; trade-off: [...]
- **Recommendation**: [A/B] — [reason, incl. constitution-constraint check result]
- **Approved**: [choice] ([YYYY-MM-DD])

<!-- If no non-trivial design decision exists, replace the D1 example with:
- None — <specific reason no non-trivial design decision was required>
-->

## Design Detailing *(gatespec: mandatory)*

<!--
  GATESPEC: Every dimension MUST have substantive content OR an explicit
  "N/A — <one-line reason>". Silent omission fails the gate.
  Constraints may add dimensions, but cannot delete, rename, or replace the
  six core dimensions below.
-->

1. **Thread / concurrency model**: [thread ownership, cross-thread data flow, synchronization primitives — or N/A + reason]
2. **Object lifetimes & ownership**: [creation/destruction, ownership semantics (unique/shared/borrowed), destruction ordering — or N/A + reason]
3. **Key modules & classes**: [responsibilities, boundaries, dependency directions]
4. **Key internal APIs & interactions**: [signature-level, call sequencing]
5. **External interface behavior contracts**: [externally visible behavior, error semantics, compatibility]
6. **Setup / runtime / teardown phase interactions**: [state transitions and interactions per phase]

## Implementation Freedoms *(gatespec: include if any)*

<!--
  GATESPEC: Non-trivial choices deliberately left to implementation time.
  Anything NOT listed here and NOT in the Decision Log is a silent gap —
  the implementer's walkthrough must have found none remaining.
-->

- [choice left open] — constraints: [boundaries the implementer must respect]

## Implementation Review Contract *(gatespec: mandatory)*

<!--
  GATESPEC: This contract is approved as Design content and is consumed by
  native speckit.tasks / speckit.implement plus GateSpec hook checks.
  - Replace REV-US<n> with one checkpoint per actual user-story phase.
  - Each Required Checkpoint has exactly one mapping row.
  - A mapping cell is one line and cannot contain a raw `|`; put pipelines or
    multi-command validation in an executable script and name that script.
  - Native tasks must end the corresponding phase with one non-[P] task whose
    description contains this canonical reviewer command and stop condition:
      GateSpec review checkpoint <REV-ID>: run
      speckit.gatespec.review-implementation --scope <REV-ID>; require
      .gatespec/reviews/<REV-ID>/seal.md before continuing.
  - REV-FINAL reviews the complete feature diff and is never satisfied by
    aggregating earlier stage receipts.
-->

- **Protocol Version**: `1`
- **Required Checkpoints**: `[REV-FOUNDATION, REV-US<n>..., REV-FINAL — replace with actual IDs]`
- **Review Root**: `.gatespec/reviews`
- **Task Review**: `REV-TASKS after speckit.analyze; PASS required before speckit.implement`
- **Reviewer Isolation**: `fresh-context-required; manual-new-session-on-unavailable; same-context-forbidden`
- **Parallel Policy**: `same-phase-disjoint-only; join-before-review; cross-checkpoint-forbidden`
- **Git Policy**: `clean-feature-branch; local-checkpoint-commits; no-push`
- **Remediation Limit**: `2`

### Checkpoint Test Mapping

| Checkpoint | Required test command(s) |
|------------|--------------------------|
| REV-FOUNDATION | [exact command(s) that validate the foundation checkpoint] |
| REV-US<n> | [exact command(s) for this user-story checkpoint] |
| REV-FINAL | [exact command(s) for the complete feature] |

- **Final Validation**: `[non-empty end-to-end validation that covers the complete approved feature]`

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (GateSpec plan output)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
├── tasks.md             # Phase 2 output (speckit.tasks - NOT created by plan)
└── .gatespec/
    └── reviews/          # REV-TASKS and implementation request/verdict/seal snapshots
```

### Source Code (repository root)

```text
# [REMOVE IF UNUSED] Option 1: Single project (DEFAULT)
src/
├── models/
├── services/
└── lib/

tests/
├── contract/
├── integration/
└── unit/
```

**Structure Decision**: [Document the selected structure and reference the real
directories captured above]

## Complexity Tracking

> **Fill ONLY if Constitution Check has violations that must be justified**

| Violation | Why Needed | Simpler Alternative Rejected Because |
|-----------|------------|-------------------------------------|
| [e.g., 4th project] | [current need] | [why 3 projects insufficient] |

<!--
  GATESPEC: Written ONLY on explicit user approval. Gate Approval MUST be the
  unique final H2 and contain only the two fields below. `Content-SHA256`
  hashes everything before it.
-->

## Gate Approval *(gatespec: mandatory)*

- **Approved by user**: [YYYY-MM-DD]
- **Content-SHA256**: `[64 hex chars]`
