---
description: "GateSpec fresh-context implementation review: request, verdict, and PASS seal for one approved checkpoint."
---

## User Input

```text
$ARGUMENTS
```

Accept exactly one form:

```text
--scope <REV-FOUNDATION|REV-US<n>|REV-FINAL>
--request <absolute-round-request-path>
```

`--scope` is the native implementation/checkpoint coordinator path. `--request`
is the manual new-session reviewer fallback. Its canonical path must resolve
under the current feature's declared `.gatespec/reviews/<REV-ID>/`, and its
basename must be `round-00-request.md`, `round-01-request.md`, or
`round-02-request.md`. Reject mixed, missing, or extra input.

## Non-negotiable isolation and ownership

- The implementation/remediation context may join work, test, commit locally,
  and create a request. It MUST NOT judge that request or write a verdict.
- A verdict comes only from the fresh reviewer dispatcher appended to this
  command. Never fall back to the implementation context.
- If dispatch is unavailable, emit `REVIEW BLOCKED`, show the exact
  `--request <absolute-request-path>` invocation for a new top-level session,
  leave the checkpoint task unchecked, and stop.
- Reviewer work is read-only. It returns verdict text; the coordinator
  validates/persists it and alone creates a PASS seal.
- A BLOCKED reviewer never fixes or re-reviews its own finding. The executor
  may remediate, but the next round needs another fresh context.
- No command in this protocol pushes, rebases, resets, cleans, stashes, or
  rewrites history.

## Manual `--request` path

This is reviewer-only mode for a user-opened fresh top-level session. Derive
and validate REV-ID from the absolute request path, then skip every Scope
coordinator step. Do not create, modify, persist, move, or commit any request,
verdict, seal, task, or source file. Do not alter the primary worktree, index,
branch, or commits, and never push. Tests that may write run only in a unique
isolated temporary checkout at Subject-Commit (a platform worktree or local
clone); verify it has no tracked delta afterward and remove it. Review under
the installed adapter's remaining
read-only rules. Ephemeral files for hashing/test output may use `/tmp`; no
repository or other persistent file may be written. Return only the exact
Verdict Markdown to the user, with `Reviewer-Platform`
`manual-codex` or `manual-claude` as selected by the active dispatcher and
`Isolation` `fresh`. The user carries that text back to the original `--scope`
coordinator for validation and persistence. Never create a seal or mark a task
complete in manual mode.

## Scope coordinator

1. Resolve the feature, run `check-gate.sh tasks-structure <feature-dir>`, and
   verify the requested REV-ID occurs exactly once in the approved Required
   Checkpoints and Checkpoint Test Mapping. A silent zero result for an unmarked
   upstream feature returns immediately with no writes or report. Stop on every
   failure. Select the active protocol deterministically: an approved Plan
   declaring 1 with no Source entry is legacy v1; Plan 2 or any
   `contracts/source-design.md` is v2. Never downgrade v2. Validate v2 execution
   state, epoch, original baseline, task handoff, preserved reviews, and IA.
2. Verify the matching native task is the current phase-final, non-`[P]`
   `GateSpec review checkpoint <REV-ID>:` row. All earlier work must be complete,
   all same-phase workers joined, and no later work started. Keep this checkpoint
   row unchecked while requesting/reviewing.
3. Select only round 00, 01, or 02. Round 00 has previous verdict `none`.
   Rounds 01/02 require the complete preceding BLOCKED verdict, actual
   remediation, and its Verdict-SHA256. Never overwrite prior files; a round 02
   BLOCKED result is terminal pending Requirements/Design/task revision. A
   valid immutable PASS request/verdict with no seal means `resume candidate`:
   do not dispatch or open another round. Revalidate every binding and recreate
   only the candidate seal; if any binding drifted, fail closed and require the
   bound state to be restored or an explicit upstream revise/restart.
4. Run the exact mapped checkpoint tests automatically. REV-FINAL also runs the non-empty
   Final Validation and reviews the complete baseline-to-final feature subject,
   never an aggregation of earlier PASS seals.
5. On the feature branch, create a local subject commit containing only
   intended implementation, completed pre-checkpoint task progress, and—for
   source-enabled v2—the complete IA snapshot. Every IA<n> records Source refs,
   Task ID, actual paths/symbols, reason, `Boundary Impact: none`, and
   verification. Require a clean worktree. Never push.
6. Run `check-gate.sh task-review <feature-dir>` only after that clean subject
   commit; stop if the approved artifacts/tasks or REV-TASKS receipt are stale.
   Resolve Git fields as follows:
   - Implementation-Baseline is exactly the current REV-TASKS seal's
     latest-touch commit, resolved as
     `git log -1 --format=%H -- <feature-relative-seal-path>`. Its seal blob must
     equal the current seal, and this exact OID is identical for every
     implementation checkpoint; never substitute a later commit merely because
     it also contains the seal.
   - REV-FOUNDATION Base-Commit equals Implementation-Baseline.
   - Each REV-US<n> Base-Commit equals the preceding stage checkpoint's sealed
     Subject-Commit.
   - REV-FINAL Base-Commit returns to Implementation-Baseline for v1. For v2 it
     is the unchanged Original-Implementation-Baseline, while Subject still
     descends from Implementation-Baseline; final review covers every epoch.
   - All remediation rounds for one REV-ID retain that same Base-Commit while
     Subject-Commit advances to the newly committed fix.
   - Changed-Paths-SHA256 hashes the C-sorted output of
     `git diff --no-renames --name-only <base> <subject>`.
   - V2 Final-Delta-SHA256 is `not-applicable` before REV-FINAL. REV-FINAL
     hashes the exact raw NUL-delimited stream from
     `git diff-tree --raw -z --no-abbrev --no-renames <original> <subject>`.
7. Derive Scope as `FOUNDATION`, `US<n>`, or `FINAL`. Task-IDs is the exact,
   non-empty, canonical comma-only list of all and only non-checkpoint T### rows
   assigned to the reviewed scope: FOUNDATION includes its pre-story
   setup/foundational work, each US<n> includes that story phase, and REV-FINAL
   lists every non-checkpoint T### in the feature. Preserve tasks.md order; do
   not include a GateSpec review-checkpoint task. Compute the current scoped
   spec/plan, non-Source design-attachments, and normalized tasks-definition
   hashes. V2 additionally binds Execution-Epoch, Source content or
   `not-applicable`, the Subject's IA snapshot or `not-applicable`,
   Task-Handoff-Commit, and Preserved-Reviews-SHA256.
8. Atomically write
   `.gatespec/reviews/<REV-ID>/round-<NN>-request.md` with this exact order and
   exactly one Required Tests bullet whose text equals that REV-ID's mapping
   cell. For REV-FINAL, append one bullet equal to Final Validation when its
   text differs from the mapping cell; do not duplicate an identical value.
   Hash every raw byte before Request-SHA256. Use this exact schema only for
   legacy Protocol v1:

```markdown
- **Protocol-Version**: `1`
- **Review-ID**: `<REV-ID>`
- **Round**: `<00|01|02>`
- **Scope**: `<FOUNDATION|US<n>|FINAL>`
- **Spec-Content-SHA256**: `<lowercase 64-hex>`
- **Plan-Content-SHA256**: `<lowercase 64-hex>`
- **Design-Attachments-SHA256**: `<lowercase 64-hex>`
- **Tasks-Definition-SHA256**: `<lowercase 64-hex>`
- **Implementation-Baseline**: `<lowercase Git commit OID>`
- **Base-Commit**: `<lowercase Git commit OID>`
- **Subject-Commit**: `<lowercase Git commit OID>`
- **Task-IDs**: `<T###|T###,T###>`
- **Changed-Paths-SHA256**: `<lowercase 64-hex>`
- **Previous-Verdict-SHA256**: `<none|prior Verdict-SHA256>`

## Required Tests

- `<exact Checkpoint Test Mapping cell>`

- **Request-SHA256**: `<lowercase 64-hex>`
```

For Protocol v2 use this exact schema:

```markdown
- **Protocol-Version**: `2`
- **Review-ID**: `<REV-ID>`
- **Round**: `<00|01|02>`
- **Scope**: `<FOUNDATION|US<n>|FINAL>`
- **Spec-Content-SHA256**: `<lowercase 64-hex>`
- **Plan-Content-SHA256**: `<lowercase 64-hex>`
- **Design-Attachments-SHA256**: `<lowercase 64-hex; Source excluded>`
- **Tasks-Definition-SHA256**: `<lowercase 64-hex>`
- **Execution-Epoch**: `<E1|E2|...>`
- **Source-Design-Content-SHA256**: `<lowercase 64-hex|not-applicable>`
- **Implementation-Adjustments-SHA256**: `<Subject IA hash|not-applicable>`
- **Task-Handoff-Commit**: `<execution-state commit OID>`
- **Preserved-Reviews-SHA256**: `<lowercase 64-hex|not-applicable>`
- **Implementation-Baseline**: `<REV-TASKS seal commit OID>`
- **Base-Commit**: `<stage base; Original Baseline for REV-FINAL>`
- **Subject-Commit**: `<lowercase commit OID>`
- **Task-IDs**: `<T###|T###,T###>`
- **Changed-Paths-SHA256**: `<lowercase 64-hex>`
- **Final-Delta-SHA256**: `<lowercase 64-hex for REV-FINAL|not-applicable>`
- **Previous-Verdict-SHA256**: `<none|prior Verdict-SHA256>`

## Required Tests

- `<exact Checkpoint Test Mapping cell>`

- **Request-SHA256**: `<lowercase 64-hex>`
```

9. Dispatch only the absolute request path with the appended platform adapter.
   Send no executor transcript, rationale, summary, findings, or proposed
   verdict.

## Fresh reviewer judgment

Validate the request and its bound commits before reviewing. Inspect only the
approved artifacts and base-to-subject diff it binds. Check correctness,
Requirements/Design compliance—including the approved component boundaries,
core API/interaction skeleton, thread and ownership/resource contracts,
external behavior, and lifecycle—task completion, error/failure behavior,
regressions, scope, and material test gaps. Run the Required Tests in the
adapter's isolated temporary checkout when safe. A changed primary worktree,
unsafe/unavailable mandatory test, stale hash, unclosed prior blocker, or
material uncertainty is BLOCKED. For source-enabled v2, compare code—not only
names/tests—to SD-U declarations, SD-FLOW/SD-ALG/SD-FAIL semantics,
ownership/concurrency/invariants, and SD-TEST obligations. Actual product paths
must equal Source Change Manifest + IA Changed Paths. Only private helpers,
internal naming, equivalent local algorithms, test organization, and necessary
adjacent internal paths are bounded IA. External behavior, compatibility,
security/performance promises, module/dependency boundaries, cross-module API,
state ownership, concurrency/error semantics, schema, or key invariants are
material; a material or uncertain departure is BLOCKED and exits normal
implement for Source revision. Tests Run contains evidence for every Required
Tests bullet: include that exact approved string plus non-empty result text.

The adapter, or a manual fresh session whose returned text is supplied back to
the original `--scope` coordinator, returns exactly the request's protocol
(`1` shown for legacy; use `2` for a v2 request):

```markdown
- **Protocol-Version**: `1`
- **Review-ID**: `<request value>`
- **Round**: `<request value>`
- **Request-SHA256**: `<request value>`
- **Reviewer-Platform**: `<codex|claude|manual-codex|manual-claude>`
- **Reviewer-Context-ID**: `<nonempty fresh context/run ID>`
- **Isolation**: `fresh`
- **Status**: `<PASS|BLOCKED>`

## Tests Run

- `<exact command or scenario and outcome; never None/Not run>`

## Blockers

- `<None for PASS, or BLOCKER: ... for BLOCKED>`

## Observations

- `<observation or None>`

## Limitations

- `<limitation or None>`

- **Verdict-SHA256**: `<lowercase 64-hex>`
```

PASS Blockers is exactly `- None`; BLOCKED contains at least one
`- BLOCKER: ...`. Before persistence,
validate its self-hash, matching Review-ID/Round/Request-SHA256, allowed
platform, nonempty context ID, `Isolation: fresh`, section order, test evidence,
and PASS/BLOCKED blocker semantics. Persist exact returned bytes as
`round-<NN>-verdict.md`; do not rewrite reviewer content.

## Verdict handling

- BLOCKED: do not create `seal.md`. Report blockers and leave the checkpoint
  task unchecked. After validating/persisting the verdict, the coordinator
  immediately creates one local metadata-only finding commit containing that
  round's request and verdict: no seal, checkpoint checkmark, product change,
  or push. This finding commit can never be a later request's Subject-Commit.
  The executor then makes a strictly later, separate remediation subject commit
  with a real product/test delta that closes the blocker; the worktree must be
  clean before the next round. This reviewer context may not do either commit.
- PASS: atomically create `seal.md` with the exact ordered fields below, copied
  from the accepted request/verdict. Use current UTC `YYYY-MM-DDTHH:MM:SSZ` and
  hash every raw byte before Seal-SHA256. Then temporarily change only the
  current checkpoint checkbox from `[ ]` to `[X]`; this is not committed until
  the checker succeeds.

```markdown
- **Protocol-Version**: `1`
- **Review-ID**: `<REV-ID>`
- **Round**: `<00|01|02>`
- **Status**: `PASS`
- **Request-SHA256**: `<request value>`
- **Verdict-SHA256**: `<verdict value>`
- **Spec-Content-SHA256**: `<request value>`
- **Plan-Content-SHA256**: `<request value>`
- **Design-Attachments-SHA256**: `<request value>`
- **Tasks-Definition-SHA256**: `<request value>`
- **Implementation-Baseline**: `<request value>`
- **Base-Commit**: `<request value>`
- **Subject-Commit**: `<request value>`
- **Sealed-At**: `<UTC RFC3339>`
- **Seal-SHA256**: `<lowercase 64-hex>`
```

For a v2 seal, set Protocol-Version to `2`, insert these copied request fields
after Tasks-Definition-SHA256, and insert Final-Delta-SHA256 after
Subject-Commit:

```markdown
- **Execution-Epoch**: `<request value>`
- **Source-Design-Content-SHA256**: `<request value>`
- **Implementation-Adjustments-SHA256**: `<request value>`
- **Task-Handoff-Commit**: `<request value>`
- **Preserved-Reviews-SHA256**: `<request value>`
...
- **Final-Delta-SHA256**: `<request value>`
```

Run `check-gate.sh implementation-candidate <feature-dir> <REV-ID>` with that
one temporary checkpoint checkmark and the candidate seal in place. On failure,
immediately restore the checkbox to `[ ]`, delete only the uncommitted candidate
seal, retain the immutable PASS request/verdict, make no commit, and do not
report PASS. A later `--scope` invocation resumes candidate validation as Step
3 specifies instead of dispatching again.

On candidate success, create one local metadata/progress commit containing the
request, verdict, seal, and checkpoint checkbox, with no product change; require
a clean worktree, then run
`check-gate.sh implementation-review <feature-dir> <REV-ID>`. Only this clean,
tracked final check permits continuation. Never push. REV-FINAL is checked
again by the fixed `after_implement` hook; do not report native implementation
completion early. A non-final PASS continues automatically without asking the
user. After REV-FINAL, the acceptance hook is the one normal implementation
question.

The integration-specific fresh dispatcher is appended when this command is
rendered as a Claude/Codex skill. In command mode, use the matching packaged
`reviewers/<platform>/dispatcher.md`; if no matching trusted adapter is
available, take only the manual-new-session path above and never self-review.
