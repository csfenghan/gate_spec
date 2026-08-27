---
description: "GateSpec fresh-context task review: create and seal REV-TASKS after native analyze."
---

## User Input

```text
$ARGUMENTS
```

Accept either no input (the normal `after_analyze` coordinator path) or exactly
`--request <absolute-round-request-path>` (manual new-session fallback). Reject
all other input. The canonical path must resolve inside the current feature's
exact `.gatespec/reviews/REV-TASKS/` directory and its basename must be
`round-00-request.md`, `round-01-request.md`, or `round-02-request.md`.

## Non-negotiable isolation and ownership

- The spec/plan/tasks author or remediator context may create a request and
  persist the returned adapter output, but MUST NOT judge the request or write
  its own verdict.
- A verdict comes only from the fresh reviewer dispatcher appended to this
  command. Never fall back to review in the current context.
- If fresh dispatch is unavailable, emit `REVIEW BLOCKED`, give the exact
  `--request <absolute-request-path>` invocation for a new top-level session,
  and stop without a verdict or seal.
- The reviewer is read-only for spec, plan, tasks, source, Git, requests, and
  seals. It returns verdict text; the coordinator validates and persists it.
- A BLOCKED reviewer never performs remediation or re-reviews its own fix.
  Native tasks/analyze must remediate, followed by another fresh context.

## Manual `--request` path

This is reviewer-only mode for a user-opened fresh top-level session. Verify
the absolute path is the current feature's REV-TASKS request, then skip every
Coordinator step. Do not create, modify, persist, move, or commit any request,
verdict, seal, task, or source file. Do not alter the primary worktree, index,
branch, or commits, and never push. A test that may write may run only in a
unique isolated temporary checkout (a platform worktree or local clone);
verify it has no tracked delta afterward and remove it. Ephemeral files for
hashing/test output may use `/tmp`; no repository or other persistent file may
be written.
Review under the installed adapter's remaining read-only rules and return only
the exact Verdict Markdown to the user, using `Reviewer-Platform`
`manual-codex` or `manual-claude` as selected by the active dispatcher and
`Isolation` `fresh`. The user carries that text back to the original
coordinator for validation and persistence. Never create a seal or local
commit in manual reviewer mode.

## Coordinator path

1. Resolve `.specify/feature.json` and quote the feature path. Before ordinary
   structure validation, if `round-02-verdict.md` exists and the current
   REV-TASKS seal is absent, run
   `check-gate.sh retask-eligible <feature-dir>` as a receipt/recovery probe.
   On success, create nothing: report that the review budget is exhausted and
   direct the authoring context to
   `__SPECKIT_COMMAND_GATESPEC_PLAN__ --retask`. On failure, print its
   diagnostics verbatim and stop; an orphan, invalid, stale, or implemented
   round-02 state is not normal remediation. Otherwise run
   `check-gate.sh tasks-structure <feature-dir>`. A silent zero result for an
   unmarked upstream feature returns immediately with no writes or report.
   Stop on every failure.
2. Use review ID `REV-TASKS`, scope `TASKS`, and directory
   `<feature>/.gatespec/reviews/REV-TASKS/`. If `check-gate.sh task-review`
   already accepts a current seal, keep all receipt bytes read-only and return.
   Require the approved Plan, execution state, and all current receipts to use
   Protocol 3. An active or unaccepted Protocol 1/2 feature fails closed and
   returns through `gatespec.plan --revise`; only a valid Accepted legacy
   delivery is historical, and it cannot start another review.
3. Select the next round without guessing:
   - no prior files → `00`, Previous-Verdict-SHA256 `none`;
   - a complete prior BLOCKED round → `01` or `02`, chained to that verdict;
   - PASS already sealed → read-only success;
   - round 02 BLOCKED, an orphan file, an invalid chain, or any round beyond 02
     → stop. There are at most two remediation rounds after round 00.
   A remediation request requires a changed normalized tasks definition. Never
   overwrite an earlier request or verdict. For round 02 BLOCKED, report that
   the review budget is exhausted and direct the authoring context to
   `__SPECKIT_COMMAND_GATESPEC_PLAN__ --retask`; do not suggest another tasks
   edit/review round in the current cycle.
4. Compute current hashes using the checker contract: scoped spec/plan content,
   the C-sorted relative-path/TAB/file-hash design-attachment manifest, and
   tasks.md with CRLF normalized and only valid T### `[xX]` progress normalized
   to `[ ]`.
   For v3, exclude the Source bundle from Design-Attachments-SHA256. Reproduce
   Mode and Test-Control-Closure-SHA256 from the exact mandatory task section:
   emit its exact heading plus LF, then each nonblank body line before the next
   H2 in original order after stripping only a terminal CR, with one LF per
   emitted line; hash those bytes.
   Initialize
   execution state before the request. With Source enabled, initialize the IA
   template to its canonical empty state; without Source, IA is
   `not-applicable`. Before round 00 only, create and verify a clean local
   pre-review Task-Handoff commit that contains current approved artifacts,
   Source/REV-SOURCE/revalidations when applicable, tasks.md, empty IA, and the
   execution state while its Task-Handoff-Commit value is still `pending`.
   Record that new OID in the working execution state and recompute its
   self-hash; the later REV-TASKS metadata commit records those final state
   bytes without creating a self-referential commit hash. Keep the unchanged
   Original Baseline/Execution Epoch. Remediation rounds retain that immutable
   handoff OID while changing the bound tasks definition; they do not create a
   second handoff. No implementation path or task progress may enter either
   commit.
5. Write `round-<NN>-request.md` atomically with exactly this Protocol 3
   field/section order. Replace values, omit angle brackets, and hash every raw
   byte before the final Request-SHA256 field. Test-Control-Mode and Closure
   hash are always actual. REV-TASKS has no implementation Subject or lane
   evidence, so the other three Test Control bindings are exactly
   `not-applicable` even in isolated mode.

```markdown
- **Protocol-Version**: `3`
- **Review-ID**: `REV-TASKS`
- **Round**: `<00|01|02>`
- **Scope**: `TASKS`
- **Spec-Content-SHA256**: `<lowercase 64-hex>`
- **Plan-Content-SHA256**: `<lowercase 64-hex>`
- **Design-Attachments-SHA256**: `<lowercase 64-hex; Source excluded>`
- **Tasks-Definition-SHA256**: `<lowercase 64-hex>`
- **Test-Control-Mode**: `<none|isolated>`
- **Test-Control-Closure-SHA256**: `<lowercase 64-hex>`
- **Test-Control-Subject-Manifest-SHA256**: `not-applicable`
- **Default-OFF-Evidence-SHA256**: `not-applicable`
- **Explicit-ON-Evidence-SHA256**: `not-applicable`
- **Execution-Epoch**: `<E1|E2|...>`
- **Source-Design-Content-SHA256**: `<lowercase 64-hex|not-applicable>`
- **Implementation-Adjustments-SHA256**: `<empty IA raw hash|not-applicable>`
- **Task-Handoff-Commit**: `<lowercase commit OID>`
- **Preserved-Reviews-SHA256**: `<lowercase 64-hex|not-applicable>`
- **Implementation-Baseline**: `not-applicable`
- **Base-Commit**: `not-applicable`
- **Subject-Commit**: `not-applicable`
- **Task-IDs**: `none`
- **Changed-Paths-SHA256**: `not-applicable`
- **Final-Delta-SHA256**: `not-applicable`
- **Previous-Verdict-SHA256**: `<none|prior Verdict-SHA256>`

## Required Tests

- Not run — task-plan review

- **Request-SHA256**: `<lowercase 64-hex>`
```

6. Dispatch exactly that absolute request path using the appended or packaged platform
   adapter. Do not send conversation, analysis summaries, suggested findings,
   or a proposed verdict.

## Fresh reviewer judgment

Review the approved Requirements/Design and native tasks from the request
without editing them. A successful structural hook and the three closure sections
are navigation, not proof. Open and inspect the underlying artifacts, every
task, every referenced prior verdict item, and all named paths/symbols. Never
infer semantic closure from a matrix row, trace token, changed tasks hash, test
name, or reviewer assertion.

First validate the exact matrix schemas and navigate every Checkpoint Closure
row in Plan order. For each row, independently verify its actual task interval,
all Contract refs, every Production task, every Verification task, phase-final
checkpoint, mapped required test, dependency boundary, and earliest point at
which each obligation is both implemented and testable. Then navigate every
Prior Review Closure row to the exact `<verdict>#B<NN>` item, reproduce its raw
complete-item SHA-256, validate its current Spec/Plan/Attachments plus v3 Source
basis, and prove that the named remediation tasks close the whole finding no
later than Required-before. The all-`none` row is valid only when exhaustive
search of the current chain and every basis-matching `*-retask` archive finds no
BLOCKER item.

When the current cycle follows `--retask`, compare every basis-matching retask
archive's Test Control Closure. Require identical Mode and TC ID/surface/
touchpoint/effect/switch/wiring/validator fields; only consumer/default-proof
T### rebinding with unchanged meaning is allowed. A control-contract change
cannot close a retask blocker and routes to `gatespec.plan --revise` plus fresh
tasks/REV-TASKS.
Also require the canonical Policy and copied TCE body to remain byte-identical.
A new/changed TCE routes first to `gatespec.specify --revise`, then revised
Plan and fresh tasks/REV-TASKS.

Complete all of these fixed categories even after finding a blocker:

1. type/state/schema completeness and all conversions/compatibility edges;
2. declaration-to-definition/implementation plus build, dependency,
   generation, registration, packaging, install, and configuration closure;
3. changed-API producer plus every in-scope caller, consumer, adapter, mock,
   and compatibility path;
4. every behavior/error/boundary producer to executable tests that actually
   reach and distinguish it;
5. setup/startup/runtime/cancellation/backpressure/failure/recovery/rollback/
   teardown, ownership/resource cleanup, and concurrency/order closure;
6. earliest-checkpoint placement for each contract and prior remediation;
7. precise real paths and symbols, executable dependencies, independently
   testable phases, and race-free `[P]` scopes;
8. complete trace for every FR, story/scenario, SC, approved D, engineering
   determination, bounded Implementation Freedom, Design Evidence Schema 1
   component/API/flow/thread/resource/external/lifecycle contract, test
   mapping, and checkpoint; independently re-estimate aggregate Production
   additions, churn, and production files from concrete task paths/symbols/
   build work, blocking to `gatespec.plan --revise` when any upper bound is
   positive from an approved zero or satisfies
   `new_upper * 100 >= design_upper * 125`, or when a production path family
   is absent from Design's Production path basis; values below 25% continue;
   and
9. every basis-matching prior BLOCKER, including repeated or reintroduced
   findings, with concrete closure rather than hash churn or restatement.
10. the complete Test Control Closure: independently prove Mode, each TC-###
   verification gap and production invariant, exact test-only surface and
   production touchpoint, allowed effect/lifetime, switch/wiring/validator,
   consumer, and default-build proof task. First validate the Plan's canonical
   eight-field policy plus its byte-identical approved/legacy-none Requirements
   TCE body. Apply a TCE only to its one allowlisted Rule and minimum stated
   source-auditable replacement; tasks/review cannot create/change/delete/
   broaden one or register a concrete hook through it. In `none` mode, search the whole
   task plan and named code surface for a hidden or anticipated seam. In
   `isolated` mode, prove every producer-to-test gap truly needs the control and
   every control has a concrete consumer/removal boundary. Apply the canonical
   source-root/language-marker/formal-api/control-model/touchpoint-shape/
   switch-identifier/validator-path-marker checks unless that exact Rule has an
   approved replacement. Always reject a validator that only echoes canonical
   text, runtime activation, and a hidden synonym/common Debug/`BUILD_TESTING`
   trigger. Without the corresponding TCE, also reject a fake `testonly`
   namespace token with normal-namespace declarations, alias/wrapper exposure,
   test-only dependency injection retained in production, and generic callback
   or options-bag state. Formal product APIs cannot acquire testing
   parameters/options/overloads/getters/state without a `formal-api` TCE: for example,
   `Open(path, CheckpointCoordinatorOptions)`, a generic observer/options
   surface, or an injected `AgentHost` constructor whose only consumer is a
   test is a blocker even if the default path preserves behavior and no
   `formal-api` TCE exactly authorizes its replacement. Require
   canonical typed declarative single-purpose per-instance RAII controls
   limited to named one-shot/count/barrier/time/random/fault/observation effects
   unless a `control-model` TCE gives the exact replacement. An orphan is never
   admissible.
   Without a `touchpoint-shape` TCE, each named production function may have at most one visually contiguous
   dedicated hook-macro guard block; the block contains only one `testonly`
   call and feeds its result into the normal production error/result path.
   Counting, waiting, fault selection, and observer dispatch must remain in
   the registered test-only root (canonical `/src/testonly`, or the exact
   `source-root` replacement), not be distributed through production code.
   Only `touchpoint-shape` may replace guard/call/result/mechanics shape; only
   `source-root` may replace that root. Crossing both requires both Rules;
   `control-model` never authorizes production-side mechanics.
   Independently estimate Test Control additions, churn, unique affected files,
   and unique registered production touchpoints from concrete tasks. Record
   those nonnegative ranges only in the verdict Audit, separate from Production;
   PASS Mode none is four zeros, while BLOCKED Mode none with an undeclared
   control reports its hidden-control range.
   Require validator implementation/test tasks that derive every reported
   manifest, coverage, and hit from current-lane configure/build/test and
   present install/export/symbol outputs. Literal/precomputed hashes, a stable
   canonical-row echo, and incomplete output discovery are blockers; the fresh
   implementation reviewer must be able to enumerate/hash outputs independently.
   Native-task registration; Closure/Audit/manifest/evidence/hash and clone
   lifecycle; dedicated explicit opt-in/default OFF; no runtime/umbrella
   activation; full OFF elision; Bash lanes with the same normal tests plus ON
   consumers; actual-output derivation without literal/echo; named gaps, real
   consumers, no orphans, and removal boundary are never exemptable. A row that
   tries to weaken this floor or a newly needed deviation blocks to
   `gatespec.specify --revise`, then a revised Plan and fresh tasks/REV-TASKS.

Independently enforce Scope Contract conservation across that pass. All
non-deferred CAPs must be covered through their FR/SC refs and executable tasks;
CAP IDs do not enter Closure tables. No task may implement a deferred CAP,
add unapproved external behavior, change Primary outcome, or silently remove a
Retained baseline behavior or burden. Gold-plating and “helpful” adjacent
optimization are blockers even when the implementation would be technically
clean. Route a scope change only to `gatespec.specify --revise`; never infer
admission from task detail.

For source-enabled v3, the same exhaustive pass includes every approved SD<n>,
every SD-F path, SD-U declaration/symbol, SD-FLOW, SD-ALG invariant/bound,
SD-FAIL behavior, SD-TEST trace, Source Change Manifest path, current Source
content hash, empty IA baseline, execution epoch, Task-Handoff commit, and
preserved revalidation. Revalidation items bind their own creation epoch,
preserved Subject, and current Source; after a task-only retask, validate the
raw preserved manifest without requiring immutable old items to claim the new
task-cycle epoch. A missing task, unexecutable test, late placement,
unbounded implementation choice, material uncertainty, gold-plating, or
approved-contract mismatch is a BLOCKER, not an inferred default.
Estimate size alone is not a blocker when it was disclosed by approved Design.
If the chosen response to drift is a scope-changing split, require
`gatespec.specify --revise`; never create sibling specs or impose LOC/file/
checkpoint limits.

Accumulate all independently actionable blockers across every closure row and
all ten categories before returning one verdict. Do not stop at the first
failure, cap findings, collapse unrelated defects into one vague item, or defer
an already observable blocker to a later review round. Each `- BLOCKER:` item
must name the affected artifact ref or prior Finding-SHA256, concrete task/path/
symbol evidence, and the missing or contradictory closure so the author can
remediate the whole set in one pass.

The adapter, or a manual fresh session whose returned text is supplied back to
this no-input coordinator, returns exactly this Protocol 3 schema. Test Control
Audit is mechanically parsed. For PASS, `Declared-Controls` is `none` in none
mode or the complete canonical `TC-001, TC-002` list in isolated mode;
Undeclared and Orphan are `none`; both proof fields are `not-applicable` in none
mode and `pending-REV-FINAL` in isolated task review. BLOCKED may use `found`
for Undeclared and/or a canonical TC list for Orphan, with corresponding
concrete BLOCKER items. Test-Control-Scale is a task-backed nonnegative range
estimate separate from Production. Its additions range never exceeds churn,
and its touchpoints range contains the exact number of unique registered
production `path::symbol` touchpoints. PASS none mode is exact all-zero;
BLOCKED none mode with `found` reports the detected hidden-control range.
REV-TASKS has no bound lane sidecars or rerun, so isolated proof fields remain
`pending-REV-FINAL` even for BLOCKED; mode none always uses both
`not-applicable`. Only a BLOCKED isolated REV-FINAL implementation review may
use `failed`.

```markdown
- **Protocol-Version**: `3`
- **Review-ID**: `REV-TASKS`
- **Round**: `<00|01|02>`
- **Request-SHA256**: `<request value>`
- **Reviewer-Platform**: `<codex|claude|manual-codex|manual-claude>`
- **Reviewer-Context-ID**: `<nonempty fresh context/run ID>`
- **Isolation**: `fresh`
- **Status**: `<PASS|BLOCKED>`

## Tests Run

- Not run — task-plan review

## Test Control Audit

- **Mode**: `<none|isolated>`
- **Declared-Controls**: `<none|TC-001, TC-002>`
- **Undeclared-Controls**: `<none|found>`
- **Orphan-Controls**: `<none|TC-001, TC-002>`
- **Default-OFF-Proof**: `<not-applicable|pending-REV-FINAL>`
- **Explicit-ON-Proof**: `<not-applicable|pending-REV-FINAL>`
- **Test-Control-Scale**: `additions=<N|N..N>; churn=<N|N..N>; files=<N|N..N>; touchpoints=<N|N..N>`

## Blockers

- `<None for PASS, or BLOCKER: ... for BLOCKED>`

## Observations

- `<observation or None>`

## Limitations

- `<limitation or None>`

- **Verdict-SHA256**: `<lowercase 64-hex>`
```

PASS Blockers is exactly `- None`; BLOCKED contains at least one
`- BLOCKER: ...`. Before persistence, validate field/section order, self-hash, matching
Review-ID/Round/Request-SHA256, allowed platform, nonempty context ID,
`Isolation: fresh`, exact Test Control Audit values, and PASS/BLOCKED blocker
semantics. Persist its exact bytes
as `round-<NN>-verdict.md`; never rewrite reviewer prose.

## Verdict handling

- BLOCKED: create no seal. Report blockers and stop the hook. The authoring
  context may remediate tasks, rerun native analyze, and open the next allowed
  round; this reviewer context may not do so. If this is round 02, normal
  remediation is exhausted: keep every receipt and task byte intact and direct
  the authoring context only to
  `__SPECKIT_COMMAND_GATESPEC_PLAN__ --retask`, which performs the bounded
  archive/reset before new native tasks and a fresh round-00 cycle.
- PASS: create `seal.md` atomically with the exact ordered fields below, copying
  all bound values from the accepted request/verdict. `Sealed-At` is current UTC
  `YYYY-MM-DDTHH:MM:SSZ`; hash all raw bytes before Seal-SHA256.

```markdown
- **Protocol-Version**: `3`
- **Review-ID**: `REV-TASKS`
- **Round**: `<00|01|02>`
- **Status**: `PASS`
- **Request-SHA256**: `<request value>`
- **Verdict-SHA256**: `<verdict value>`
- **Spec-Content-SHA256**: `<request value>`
- **Plan-Content-SHA256**: `<request value>`
- **Design-Attachments-SHA256**: `<request value>`
- **Tasks-Definition-SHA256**: `<request value>`
- **Test-Control-Mode**: `<request value>`
- **Test-Control-Closure-SHA256**: `<request value>`
- **Test-Control-Subject-Manifest-SHA256**: `not-applicable`
- **Default-OFF-Evidence-SHA256**: `not-applicable`
- **Explicit-ON-Evidence-SHA256**: `not-applicable`
- **Execution-Epoch**: `<request value>`
- **Source-Design-Content-SHA256**: `<request value>`
- **Implementation-Adjustments-SHA256**: `<request value>`
- **Task-Handoff-Commit**: `<request value>`
- **Preserved-Reviews-SHA256**: `<request value>`
- **Implementation-Baseline**: `not-applicable`
- **Base-Commit**: `not-applicable`
- **Subject-Commit**: `not-applicable`
- **Final-Delta-SHA256**: `not-applicable`
- **Sealed-At**: `<UTC RFC3339>`
- **Seal-SHA256**: `<lowercase 64-hex>`
```

After writing the seal, first validate its exact local schema/hash chain. Then
verify the feature branch contains no unrelated dirty paths and create one
local checkpoint commit containing only the approved Requirements/Design,
optional Source/REV-SOURCE/revalidation artifacts, tasks.md, execution state,
optional empty IA, and the REV-TASKS request, verdict, and seal. Never push.
Require a clean worktree after that commit, then run
`check-gate.sh task-review <feature-dir>`; the checker requires the seal to be
tracked at clean HEAD. Do not report PASS unless it succeeds. That exact HEAD
is the Implementation-Baseline used by the first implementation request. If a
safe unambiguous local commit cannot be made, stop before native implementation.

The integration-specific fresh dispatcher is appended when this command is
rendered as a Claude/Codex skill. In command mode, use the matching packaged
`reviewers/<platform>/dispatcher.md`; if no matching trusted adapter is
available, take only the manual-new-session path above and never self-review.
