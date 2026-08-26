# Implementation Plan: [FEATURE]

**Branch**: `[###-feature-name]` | **Date**: [DATE] | **Spec**: [link]

**Status**: Draft

**Input**: Feature specification from `/specs/[###-feature-name]/spec.md`

**Requirements Content-SHA256**: `[approved spec content hash]`

**Design Evidence Schema**: 1

**Delivery Estimate Schema**: 1

<!--
  GATESPEC GATE FIELDS (do not remove):
  - **Status** transitions: Draft → Approved-Design (YYYY-MM-DD).
    Set ONLY by explicit user approval of the plan summary / diff round.
  - Any post-approval edit MUST revert Status to Draft and re-approve.
  - This template keeps every upstream plan-template section intact so core
    speckit.tasks / speckit.implement can consume it unchanged.
-->

## Summary

[Extract from feature spec: Primary outcome, retained baseline, design intent, current-to-target change boundary, and technical approach from research]

<!--
  GATESPEC: Do not copy the Requirements Scope Contract or create another scope
  table here. Its approved bytes are already bound by Requirements
  Content-SHA256. Every design element instead traces to a non-deferred CAP and
  an FR, while preserving Retained baseline. Activating a deferred CAP, adding
  external behavior, or changing the Primary outcome requires specify --revise.
-->

## Delivery Estimate *(gatespec: mandatory)*

<!--
  GATESPEC: Re-estimate the complete feature from inspected modules, callers,
  generated inputs/outputs, build wiring, and test surface. Use exact
  non-negative `lower..upper` ranges. Production code includes handwritten
  runtime code, headers, protocol/schema, config, and build/packaging logic;
  exclude tests, specification/review metadata, pure documentation, and only
  reproducibly generated outputs. Generated exclusions use
  `generated: output/path <- source/path via generator`.
  Relation is `within`, `expanded`, or `reduced`. For a legacy approved
  Requirements artifact with no estimate, use `not-applicable` and explain.
-->

- **Production additions**: `[lower..upper]`
- **Production churn**: `[lower..upper]`
- **Production files**: `[lower..upper]`
- **Estimate basis**: [inspected modules, callers, analogous diffs, and uncertainty]
- **Production path basis**: [repository-relative production path families separated by semicolons]
- **Excluded paths**: [path pattern — exclusion reason; generated: output/path <- source/path via generator]
- **Confidence**: [low, medium, or high — concise reason]
- **Requirements estimate relation**: `[within|expanded|reduced]`
- **Requirements estimate rationale**: [why Design stayed within or changed the Requirements estimate]

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
  GATESPEC: One block per design choice that required individual human
  approval. Engineering determinations belong in Design Detailing/research;
  deferred safe choices belong in Implementation Freedoms. The gate fails
  while any D<n> block has an empty **Approved** field.
  Rules for each block:
  - Adaptive batches are conversational only; each block remains one separately
    approved decision with its stable D<n> ID
  - One shared human-recognizable scenario comes before technical references
  - ≥2 viable options apply to that same scenario; forbidden or dominated
    alternatives are never used as foils
  - Each option states observable consequences before mechanisms; FRs,
    constraints, paths, and flow evidence come last in Technical basis
  - **Approved** filled with the user's explicit choice + date
-->

### D1: [plain-language decision question]

- **Scenario**: [actor, initial state, trigger, and observable outcome or failure]
- **Fixed boundary**: [approved behavior or higher-priority constraint this choice cannot reopen]
- **Why this needs you**: [material consequence on which reasonable humans may prefer different answers]
- **Options**:
  - A. [same-scenario observable result and trade-off] — mechanism: [technical approach]; constraint result: [result]
  - B. [same-scenario observable result and trade-off] — mechanism: [technical approach]; constraint result: [result]
- **Recommendation**: [A/B] — [reason]
- **Technical basis**: [FRs, prior decisions, constraints, repository facts, paths, or flow trace]
- **Approved**: [choice] ([YYYY-MM-DD])

<!-- If no design choice required individual human approval, replace the D1 example with:
- None — <specific reason no design choice required individual human approval>
-->

## Design Detailing *(gatespec: mandatory)*

<!--
  GATESPEC: Every dimension MUST have substantive content OR an explicit
  "N/A — <one-line reason>". Silent omission fails the gate.
  A populated dimension MUST use all exact child fields shown for that
  dimension. Core facts stay in plan.md; attachment references add evidence
  rather than replacing them. Diagrams are optional.
  Record reasoned engineering determinations under their applicable dimensions;
  they do not receive D<n> IDs or individual approval fields.
  Constraints may add dimensions, but cannot delete, rename, or replace the
  six core dimensions below.
-->

1. **Thread / concurrency model**:
   - **Execution contexts**: [existing and planned threads/processes/event loops, owners, and affinity]
   - **Cross-context flow**: [directed control/data handoffs, queues, cancellation, and backpressure]
   - **Synchronization contract**: [primitives or serialization plus ordering, race/deadlock, and shutdown guarantees]
   - **Technical basis**: [non-deferred CAP/FR/D/constraint, inspected repository anchors, and attachment references]
2. **Object lifetimes & ownership**:
   - **Owned resources**: [key objects/buffers/handles and their current/planned owners]
   - **Lifetime flow**: [creation, share/borrow/copy/move rules, destruction order, and failure cleanup]
   - **Resource contract**: [material allocation, reclamation, memory/buffer bounds, or explicit no-extra-constraint reason]
   - **Technical basis**: [non-deferred CAP/FR/D/constraint, inspected repository anchors, and attachment references]
3. **Key modules & classes**:
   - **Repository anchors**: [inspected existing modules, entry points, and types forming the integration surface]
   - **Change map**: [each key existing/modified/new element, responsibility, boundary, and deliberately unchanged neighbor]
   - **Dependency contract**: [directed callers/callees and allowed or prohibited dependency directions]
   - **Technical basis**: [non-deferred CAP/FR/D/constraint, inspected repository anchors, and attachment references]
4. **Key internal APIs & interactions**:
   - **Existing entry points**: [actual symbols or protocols consumed by the design]
   - **Core contract skeleton**:
     ```[language]
     [key type/interface/function declarations only; no implementation bodies]
     ```
   - **Primary interaction**: [ordered main success and principal failure flows with execution context on material hops]
   - **Semantic contract**: [inputs, outputs, errors, pre/postconditions, thread affinity, and ownership]
   - **Technical basis**: [non-deferred CAP/FR/D/constraint, inspected repository anchors, and attachment references]
5. **External interface behavior contracts**:
   - **Affected surfaces**: [new/changed/unchanged API, CLI, configuration, event, or schema surfaces]
   - **Behavior contract**: [externally observable success, error, timing, retry, or idempotency behavior]
   - **Compatibility contract**: [versioning, migration, fallback, and explicitly preserved behavior]
   - **Technical basis**: [non-deferred CAP/FR/D/constraint, inspected repository anchors, and attachment references]
6. **Setup / runtime / teardown phase interactions**:
   - **States & owner**: [states, transition authority, and owning component]
   - **Phase flow**: [ordered setup, runtime, and teardown interactions]
   - **Failure / recovery contract**: [partial startup, rollback, retry, cancellation, and cleanup behavior]
   - **Technical basis**: [non-deferred CAP/FR/D/constraint, inspected repository anchors, and attachment references]

## Implementation Freedoms *(gatespec: include if any)*

<!--
  GATESPEC: Non-trivial choices deliberately left to implementation time.
  Anything not approved in the Decision Log, determined with rationale in
  Design Detailing/research, or bounded here is a silent gap — the
  implementer's walkthrough must have found none remaining.
-->

- [choice left open] — constraints: [boundaries the implementer must respect]

## Implementation Review Contract *(gatespec: mandatory)*

<!--
  GATESPEC: This contract is approved as Design content and is consumed by
  native speckit.tasks / speckit.implement plus GateSpec hook checks.
  Protocol 2 supports optional Source Design, execution epochs, IA snapshots,
  raw final delta, and final delivery acceptance. A legacy approved Protocol 1
  Plan remains valid only while Source Design is not enabled.
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

- **Protocol Version**: `2`
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
│   ├── source-design.md # Optional authoritative Source Design entry
│   └── source-design/   # Optional Source Design shards
├── tasks.md             # Phase 2 output (speckit.tasks - NOT created by plan)
└── .gatespec/
    ├── reviews/          # REV-SOURCE/TASKS/implementation receipts
    ├── execution-state.md
    ├── implementation-adjustments.md
    ├── revalidations/    # Source revision preservation evidence
    └── acceptance.md     # Explicit final delivery acceptance
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
