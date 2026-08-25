<!-- gatespec: source-design -->
# Source Design: [FEATURE]

**Status**: Draft

**Plan Content-SHA256**: `[approved plan content hash]`

<!--
  This optional sub-contract is enabled by this file's existence. Keep the
  marker on line 1. Status transitions only after a fresh REV-SOURCE PASS and
  explicit user approval:
    Draft -> Approved-Source-Design (YYYY-MM-DD)

  The entry file is authoritative. Large details may be split into regular
  Markdown files below contracts/source-design/; every shard is part of both
  Source Design hashes and must be referenced from this entry.

  Before REV-SOURCE, re-estimate aggregate Production additions/churn/files
  from this complete bundle. Return to Plan revision when any upper bound is
  positive from zero, reaches 125% of approved Design, or a production path
  family is absent from Design. This is a review rule, not another stored field
  or approval mechanism.
-->

## Maintainer Scenario

### Shared engineering scenario

[Describe the maintainer, current repository state, triggering change, and the
observable result the implementation must produce.]

### Before

[Describe the current code path, ownership, state, and failure behavior.]

### After

[Describe the target code path and observable boundary without implementation
ambiguity.]

### Success flow

1. [Ordered success step, including the responsible symbol and state change.]

### Failure flow

1. [Ordered principal failure step, including propagation and recovery.]

## Source Decisions

<!--
  Use SD<n> only for a source-level choice with at least two viable options and
  materially different human consequences. Engineering determinations belong
  in the technical sections; equivalent local choices belong in Implementation
  Freedoms. Source decisions reuse normal decision answers and final approval.
-->

### SD1: [plain-language source decision]

- **Scenario**: [one self-contained engineering scenario shared by every option]
- **Fixed boundary**: [approved Requirements/Design boundary that cannot reopen]
- **Options**:
  - A. [observable consequence and trade-off, then mechanism]
  - B. [observable consequence and trade-off, then mechanism]
- **Recommendation**: [A/B and reason]
- **Technical basis**: [Spec/Plan/SD references and inspected repository facts]
- **Approved**: [choice] ([YYYY-MM-DD])

<!-- If no source choice needs human approval, replace SD1 with:
- None — <specific reason no source-level human decision is required>
-->

## Source Change Manifest

<!--
  One SD-F<n> block per complete repository-relative ADD/MODIFY/DELETE/RENAME
  path. For RENAME, Path is the old path and Destination Path is mandatory.
-->

### SD-F1: [change summary]

- **Operation**: `ADD`
- **Path**: `[repository/relative/path.ext]`
- **Destination Path**: `not-applicable`
- **Responsibility**: [what this file owns after the change]
- **Source refs**: [SD-U/SD-FLOW/SD-ALG/SD-FAIL/SD-TEST IDs implemented here]

## Symbols and Contracts

<!--
  One SD-U<n> block for every public, cross-module, critical state/concurrency,
  ownership, or error symbol. Declarations are complete and contain no bodies.
-->

### SD-U1: [symbol or contract]

- **File**: `[repository/relative/path.ext]`
- **Visibility / role**: [public, cross-module, state owner, concurrency, or error]
- **Complete declaration**:

```[language]
[complete type/interface/function declaration without implementation body]
```

- **Inputs / outputs / errors**: [complete semantic contract]
- **Ownership / concurrency**: [owner, lifetime, affinity, synchronization]
- **Compatibility**: [preserved or intentionally changed callers/ABI/schema]

## Calls, Data, State, and Lifecycle

### SD-FLOW1: [flow name]

- **Trigger and owner**: [entry symbol, execution context, and transition authority]
- **Ordered flow**: [caller -> callee, data movement, states, and lifecycle steps]
- **Success result**: [observable result and postconditions]
- **Failure / cancellation**: [propagation, cleanup, retry, and terminal state]
- **Backpressure / ordering**: [queueing, serialization, or reasoned N/A]

## Algorithms and Invariants

### SD-ALG1: [algorithm name]

- **Inputs / outputs**: [types, validation, and results]
- **Steps**: [ordered algorithm steps]
- **Data structures**: [structures and ownership]
- **Invariants**: [properties preserved before, during, and after execution]
- **Complexity**: [time and space bounds]
- **Boundary cases**: [empty, maximum, malformed, partial, and concurrent cases]

## Failure Model

### SD-FAIL1: [failure family]

- **Classification**: [error classes and stable error symbols]
- **Detection**: [where and how failure is detected]
- **Propagation**: [ordered propagation and translation]
- **Retry / recovery**: [policy, limits, idempotency, rollback, and cleanup]
- **Logging / alerting**: [level, fields, rate limits, and alert condition]

## Test Traceability

### SD-TEST1: [test obligation]

- **Requirement refs**: [FR/story/SC identifiers]
- **Source refs**: [SD-F/SD-U/SD-FLOW/SD-ALG/SD-FAIL identifiers]
- **Test path**: `[repository/relative/test_path.ext]`
- **Test symbol / scenario**: [exact test symbol or executable scenario]
- **Evidence**: [assertions, failure injection, race/lifecycle checks, or bounds]

## Operational and Cross-Cutting Design

- **Build registration**: [exact target/manifest changes or N/A — reason]
- **Dependencies**: [added/removed/version/direction rules or N/A — reason]
- **Configuration**: [keys/defaults/reload/validation or N/A — reason]
- **Persistence / transactions / migration**: [schema, atomicity, rollback, migration, or N/A — reason]
- **Security**: [trust boundaries, validation, secrets, authorization, or N/A — reason]
- **Performance**: [budgets, complexity, load, memory, and measurement]
- **Compatibility**: [API/ABI/schema/config/data and rollout behavior]
- **Observability**: [logs, metrics, traces, diagnostics, and alerting]

## Implementation Boundaries

### Bounded Implementation Freedoms

- [externally equivalent local choice] — constraints: [precise allowed range]

### Prohibited material boundaries

- External behavior, compatibility, security or performance commitments.
- Module responsibility, dependency direction, or cross-module API.
- State ownership, concurrency, error semantics, schema, or algorithm invariant.

Any uncertain or material departure blocks implementation and requires Source
Design revision; it is not an implementation adjustment.

<!--
  On explicit approval only, replace both pending values. Content-SHA256 is the
  hash of the C-sorted
  <feature-relative-path><TAB><raw-or-filtered-file-SHA256><LF> manifest whose
  entry line hashes this file's exact bytes before Gate Approval and whose
  remaining lines hash every direct regular .md shard under
  contracts/source-design/. Gate Approval is the unique final H2.
-->

## Gate Approval

- **Approved by user**: pending
- **Content-SHA256**: `pending`
