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
   Select the active protocol deterministically: an approved Plan declaring 1
   with no Source entry is legacy v1; a Plan declaring 2, or any feature with
   `contracts/source-design.md`, is v2. Never downgrade a v2 feature.
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
   For v2, exclude the Source bundle from Design-Attachments-SHA256. Initialize
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
5. Write `round-<NN>-request.md` atomically with exactly this field/section
   order. Replace values, omit angle brackets, and hash every raw byte before
   the final Request-SHA256 field. Use the following only for legacy v1:

```markdown
- **Protocol-Version**: `1`
- **Review-ID**: `REV-TASKS`
- **Round**: `<00|01|02>`
- **Scope**: `TASKS`
- **Spec-Content-SHA256**: `<lowercase 64-hex>`
- **Plan-Content-SHA256**: `<lowercase 64-hex>`
- **Design-Attachments-SHA256**: `<lowercase 64-hex>`
- **Tasks-Definition-SHA256**: `<lowercase 64-hex>`
- **Implementation-Baseline**: `not-applicable`
- **Base-Commit**: `not-applicable`
- **Subject-Commit**: `not-applicable`
- **Task-IDs**: `none`
- **Changed-Paths-SHA256**: `not-applicable`
- **Previous-Verdict-SHA256**: `<none|prior Verdict-SHA256>`

## Required Tests

- Not run — task-plan review

- **Request-SHA256**: `<lowercase 64-hex>`
```

For active Protocol v2, use this exact request instead:

```markdown
- **Protocol-Version**: `2`
- **Review-ID**: `REV-TASKS`
- **Round**: `<00|01|02>`
- **Scope**: `TASKS`
- **Spec-Content-SHA256**: `<lowercase 64-hex>`
- **Plan-Content-SHA256**: `<lowercase 64-hex>`
- **Design-Attachments-SHA256**: `<lowercase 64-hex; Source excluded>`
- **Tasks-Definition-SHA256**: `<lowercase 64-hex>`
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
without editing them. A successful structural hook and the two closure matrices
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
complete-item SHA-256, validate its current Spec/Plan/Attachments plus v2 Source
basis, and prove that the named remediation tasks close the whole finding no
later than Required-before. The all-`none` row is valid only when exhaustive
search of the current chain and every basis-matching `*-retask` archive finds no
BLOCKER item.

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

For source-enabled v2, the same exhaustive pass includes every approved SD<n>,
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

Accumulate all independently actionable blockers across every matrix row and
all nine categories before returning one verdict. Do not stop at the first
failure, cap findings, collapse unrelated defects into one vague item, or defer
an already observable blocker to a later review round. Each `- BLOCKER:` item
must name the affected artifact ref or prior Finding-SHA256, concrete task/path/
symbol evidence, and the missing or contradictory closure so the author can
remediate the whole set in one pass.

The adapter, or a manual fresh session whose returned text is supplied back to
this no-input coordinator, returns exactly the active request Protocol-Version
(`1` below for legacy; substitute `2` only for a v2 request):

```markdown
- **Protocol-Version**: `1`
- **Review-ID**: `REV-TASKS`
- **Round**: `<00|01|02>`
- **Request-SHA256**: `<request value>`
- **Reviewer-Platform**: `<codex|claude|manual-codex|manual-claude>`
- **Reviewer-Context-ID**: `<nonempty fresh context/run ID>`
- **Isolation**: `fresh`
- **Status**: `<PASS|BLOCKED>`

## Tests Run

- Not run — task-plan review

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
`Isolation: fresh`, and PASS/BLOCKED blocker semantics. Persist its exact bytes
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
- **Protocol-Version**: `1`
- **Review-ID**: `REV-TASKS`
- **Round**: `<00|01|02>`
- **Status**: `PASS`
- **Request-SHA256**: `<request value>`
- **Verdict-SHA256**: `<verdict value>`
- **Spec-Content-SHA256**: `<request value>`
- **Plan-Content-SHA256**: `<request value>`
- **Design-Attachments-SHA256**: `<request value>`
- **Tasks-Definition-SHA256**: `<request value>`
- **Implementation-Baseline**: `not-applicable`
- **Base-Commit**: `not-applicable`
- **Subject-Commit**: `not-applicable`
- **Sealed-At**: `<UTC RFC3339>`
- **Seal-SHA256**: `<lowercase 64-hex>`
```

For Protocol v2, insert the following request-bound fields after
Tasks-Definition-SHA256 and before Implementation-Baseline, and insert
Final-Delta-SHA256 after Subject-Commit. The seal Protocol-Version is `2`:

```markdown
- **Execution-Epoch**: `<request value>`
- **Source-Design-Content-SHA256**: `<request value>`
- **Implementation-Adjustments-SHA256**: `<request value>`
- **Task-Handoff-Commit**: `<request value>`
- **Preserved-Reviews-SHA256**: `<request value>`
...
- **Final-Delta-SHA256**: `not-applicable`
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
