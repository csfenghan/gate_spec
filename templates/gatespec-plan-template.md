# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]

**Status**: Draft

**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

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

[Gates determined based on constitution file + user-level constraints
(~/.gatespec/constraints.md). GATESPEC: every option presented in the
Decision Log MUST be checked against these constraints; an option that
violates one must be explicitly flagged as such — never silently dropped.]

## Decision Log *(gatespec: mandatory)*

<!--
  GATESPEC: One block per non-trivial decision. The gate fails while any
  block has an empty **Approved** field.
  Rules for each block:
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

## Design Detailing *(gatespec: mandatory)*

<!--
  GATESPEC: Every dimension MUST have substantive content OR an explicit
  "N/A — <one-line reason>". Silent omission fails the gate.
  The default dimension list below may be extended/overridden via
  ~/.gatespec/constraints.md.
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

## Project Structure

### Documentation (this feature)

```text
specs/[###-feature]/
├── plan.md              # This file (__SPECKIT_COMMAND_PLAN__ command output)
├── research.md          # Phase 0 output
├── data-model.md        # Phase 1 output
├── quickstart.md        # Phase 1 output
├── contracts/           # Phase 1 output
└── tasks.md             # Phase 2 output (speckit.tasks - NOT created by plan)
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

## Gate Approval *(gatespec: mandatory)*

<!--
  GATESPEC: Written ONLY on explicit user approval. `Content-SHA256` is the
  hash of this file with the Gate Approval section blanked out — the design
  gate fails if content drifts after approval.
-->

- **Approved by user**: [YYYY-MM-DD]
- **Content-SHA256**: `[64 hex chars]`
