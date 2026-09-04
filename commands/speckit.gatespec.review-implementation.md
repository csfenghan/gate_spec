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
branch, or commits, and never push. Tests that may write run only in unique
no-hardlink temporary clones at Subject-Commit; an isolated REV-FINAL uses two
independent clones for the default-off and explicit-on reruns. Verify every
clone has no tracked delta afterward and remove it. Review under
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
   failure. Require the Plan, execution state, tasks seal, and all current
   receipts to use Protocol 3. An active or unaccepted Protocol 1/2 delivery
   fails closed and returns through `gatespec.plan --revise`; only a complete
   Accepted legacy delivery is historical and cannot open a checkpoint.
   Validate the v3 epoch, original baseline, task handoff, preserved reviews,
   Test Control Closure, Plan's canonical policy plus exact approved/legacy-none
   Requirements TCE copy, and IA. A late/inferred/changed TCE blocks to
   `gatespec.specify --revise`; it is never an implementation adjustment.
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
4. Complete the checkpoint implementation and its mapped tests. REV-FINAL also
   completes the non-empty Final Validation and the complete baseline-to-final
   feature subject, never an aggregation of earlier PASS seals.
5. On the feature branch, create a local subject commit containing only
   intended implementation, completed pre-checkpoint task progress, and—for
   source-enabled v3—the complete IA snapshot. Every IA<n> records Source refs,
   Task ID, actual paths/symbols, reason, `Boundary Impact: none`, and
   verification. IA cannot add/change/remove a Test Control, touchpoint, hook
   switch/wiring, validator, or policy exception. A late or undeclared control
   must be removed or
   routed to `gatespec.plan --revise` plus fresh native tasks; a needed policy
   deviation first routes to `gatespec.specify --revise`. Require a clean
   worktree. Never push.
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
   - REV-FINAL Base-Commit is the unchanged
     Original-Implementation-Baseline, while Subject still
     descends from Implementation-Baseline; final review covers every epoch.
   - All remediation rounds for one REV-ID retain that same Base-Commit while
     Subject-Commit advances to the newly committed fix.
   - Changed-Paths-SHA256 hashes the C-sorted output of
     `git diff --no-renames --name-only <base> <subject>`.
   - Final-Delta-SHA256 is `not-applicable` before REV-FINAL. REV-FINAL
     hashes the exact raw NUL-delimited stream from
     `git diff-tree --raw -z --no-abbrev --no-renames <original> <subject>`.
7. Derive Scope as `FOUNDATION`, `US<n>`, or `FINAL`. Task-IDs is the exact,
   non-empty, canonical comma-only list of all and only non-checkpoint T### rows
   assigned to the reviewed scope: FOUNDATION includes its pre-story
   setup/foundational work, each US<n> includes that story phase, and REV-FINAL
   lists every non-checkpoint T### in the feature. Preserve tasks.md order; do
   not include a GateSpec review-checkpoint task. Compute the current scoped
   spec/plan, non-Source design-attachments, and normalized tasks-definition
   hashes. V3 additionally binds Execution-Epoch, Source content or
   `not-applicable`, the Subject's IA snapshot or `not-applicable`,
   Task-Handoff-Commit, and Preserved-Reviews-SHA256.
8. Reproduce Test-Control-Mode and Test-Control-Closure-SHA256 from tasks.md.
   The Closure hash is the exact heading plus LF followed by every nonblank
   body line before the next H2 in original order, stripping only a terminal CR
   and emitting one LF per line.
   For every non-final checkpoint, set Subject Manifest and both lane evidence
   bindings to exact `not-applicable`; the fresh reviewer still audits all code
   implemented so far and records `pending-REV-FINAL` in isolated mode. At
   REV-FINAL, mode `none` also uses those three exact `not-applicable` values
   after exhaustive search confirms no undeclared hook. Mode `isolated` must
   compute the subject manifest and complete the dual-lane preflight described
   below, yielding three lowercase 64-hex values.

   Build the isolated REV-FINAL Subject Manifest only from the final Subject
   Git tree. From every Closure row emit roles `test-only-surface`,
   `production-touchpoint`, `build-wiring`, and `validator`. A declared
   test-only path may be a blob or tree; recursively expand a tree to its
   regular blobs. Every other role is one regular blob. Missing paths,
   symlinks, submodules, and special objects block. Strip `::symbol` only for
   object lookup, retain the declared path separately, and emit exact lines:

   ```text
   <role><TAB><declared-path><TAB><object-path><TAB><git-mode><TAB><blob-oid><LF>
   ```

   C-sort unique lines bytewise and hash the exact LF-terminated stream. Every
   test-only object is under a source root whose path ends `/src/testonly`, or
   the exact `source-root` TCE replacement; production touchpoints are not under
   that registered test-only root. Shared object paths across roles are allowed. Closure
   separately binds symbols, switches, consumers, and proof tasks.

   For isolated REV-FINAL create two fresh independent
   `git clone --local --no-hardlinks --no-checkout` clones, detach each at
   Subject-Commit, and use separate build roots. In one run every unique
   registered validator from repository root as
   `bash <validator> --gatespec-lane default-off`; in the other use
   `bash <validator> --gatespec-lane explicit-on`. The default lane must not pass any
   hook option; the explicit lane sets each row's positive switch ON. Both run
   the same normal tests and ON adds the hook-consuming tests. A validator is a
   tracked regular non-symlink project Bash file with canonical `testonly` in
   its path/name, or the exact `validator-path-marker` TCE replacement (mode
   100644 or 100755); it emits exactly one canonical table body
   row and no other
   stdout. Any nonzero exit, malformed/duplicate/missing row, dirty clone, or
   inconsistent subject/hash blocks before a request or either sidecar is
   written. Coordinator evidence is PASS-only; never manufacture a FAIL
   evidence row or bind failed preflight output.

   C-sort rows by their exact bytes and coordinator-wrap them into the two
   field-only files
   `round-<NN>-default-off-evidence.md` and
   `round-<NN>-explicit-on-evidence.md` in the current REV-FINAL directory:

   ```markdown
   # GateSpec Test Control Evidence
   - **Protocol-Version**: `3`
   - **Review-ID**: `REV-FINAL`
   - **Round**: `<NN>`
   - **Lane**: `<default-off|explicit-on>`
   - **Subject-Commit**: `<request Subject-Commit>`
   - **Test-Control-Mode**: `isolated`
   - **Test-Control-Closure-SHA256**: `<request value>`
   - **Test-Control-Subject-Manifest-SHA256**: `<request value>`
   - **Effective-Switch-State**: `<omitted-default-off|explicit-on>`

   ## Validator Results

   | Validator | Build switch | Build wiring | Validator command | Production build scope | Compile manifest SHA256 | Dependency manifest SHA256 | Artifact manifest SHA256 | Install/export/symbol manifest SHA256 | Test manifest SHA256 | Declared source coverage | Declared test coverage | Undeclared compile hits | Undeclared dependency hits | Undeclared artifact hits | Undeclared install/export hits | Result |
   |---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
   | <validator> | <switch> | <wiring> | <canonical command> | <scope> | <compile hash> | <dependency hash> | <artifact hash> | <install/export/symbol hash or not-applicable> | <test hash> | <source coverage> | <test coverage> | <0> | <0> | <0> | <0> | PASS |

   - **Evidence-SHA256**: `<hash of all preceding raw bytes>`
   ```

   There is one row per unique switch/wiring/validator tuple and no extra H2 or
   prose. `Validator command` is exactly
   `bash <validator> --gatespec-lane <lane>`. Default-off rows use Effective state
   `omitted-default-off`, Production build scope
   `production-install-package-when-present`, Declared source coverage
   `absent`, Declared test coverage `not-applicable`, four undeclared-hit cells
   `0`, and Result `PASS`.
   Explicit-on rows use `explicit-on`, `test-build-only`, both coverage cells
   `complete`, all four undeclared-hit cells `0`, and Result `PASS`. Compile,
   dependency, artifact, install/export/symbol, and test manifest cells are
   lowercase 64-hex; install/export/symbol may instead be `not-applicable` only
   when that project has no such surface. The request evidence fields copy the
   two Evidence-SHA256 values, not an unrelated log or whole-file digest. No
   timestamp, clone/build path, external CI, or artifact signature enters this
   deterministic evidence. Explicit ON is only a test build; GateSpec does not
   forbid a user from deliberately packaging an ON build outside this proof.
9. Atomically write
   `.gatespec/reviews/<REV-ID>/round-<NN>-request.md` with this exact order and
   exactly one Required Tests bullet whose text equals that REV-ID's mapping
   cell. For REV-FINAL, append one bullet equal to Final Validation when its
   text differs from the mapping cell; do not duplicate an identical value.
   Hash every raw byte before Request-SHA256. Use only this Protocol 3 schema:

```markdown
- **Protocol-Version**: `3`
- **Review-ID**: `<REV-ID>`
- **Round**: `<00|01|02>`
- **Scope**: `<FOUNDATION|US<n>|FINAL>`
- **Spec-Content-SHA256**: `<lowercase 64-hex>`
- **Plan-Content-SHA256**: `<lowercase 64-hex>`
- **Design-Attachments-SHA256**: `<lowercase 64-hex; Source excluded>`
- **Tasks-Definition-SHA256**: `<lowercase 64-hex>`
- **Test-Control-Mode**: `<none|isolated>`
- **Test-Control-Closure-SHA256**: `<lowercase 64-hex>`
- **Test-Control-Subject-Manifest-SHA256**: `<REV-FINAL isolated lowercase 64-hex|not-applicable>`
- **Default-OFF-Evidence-SHA256**: `<REV-FINAL isolated lowercase 64-hex|not-applicable>`
- **Explicit-ON-Evidence-SHA256**: `<REV-FINAL isolated lowercase 64-hex|not-applicable>`
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

10. Dispatch only the absolute request path with the appended platform adapter.
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
material uncertainty is BLOCKED. For source-enabled v3, compare code—not only
names/tests—to SD-U declarations, SD-FLOW/SD-ALG/SD-FAIL semantics,
ownership/concurrency/invariants, and SD-TEST obligations. Actual product paths
must equal Source Change Manifest + IA Changed Paths + the validated registered
Test Control Subject Manifest object paths that actually changed from Original
Baseline to Subject. The manifest still recursively binds unchanged members of
a declared test-only tree; those members are not invented implementation delta.
A task-registered touchpoint or wiring
path authorizes only the declared hook integration; any other product behavior,
API, state, or algorithm change hidden in that file remains an unapproved
Source departure. Only private helpers,
internal naming, equivalent local algorithms, test organization, and necessary
adjacent internal paths are bounded IA. External behavior, compatibility,
security/performance promises, module/dependency boundaries, cross-module API,
state ownership, concurrency/error semantics, schema, or key invariants are
material; a material or uncertain departure is BLOCKED and exits normal
implement for Source revision. Tests Run contains evidence for every Required
Tests bullet: include that exact approved string plus non-empty result text.

Classify the destination before routing a departure. A capability, observable
error/terminal-state, async/cancellation, compatibility, resource, timing,
affinity, or ownership change requires `gatespec.specify --revise`. A
semantically equivalent contract-bearing name, signature, parameter/return
type, overload, declaration, class structure, or source-layout change requires
`gatespec.plan --revise` (and then Source revision when enabled). An internal
name or equivalent local shape that Plan explicitly left as bounded
Implementation Freedom may be recorded in Source or IA; IA still cannot alter a
Source/Plan contract or any Test Control boundary.

Also reconstruct Scope Contract coverage from CAP → FR/SC → bound Task-IDs and
the diff. Require every implemented behavior to belong to a non-deferred CAP;
block implementation of deferred CAPs, new unapproved external behavior,
Primary outcome drift, and any opportunistic elimination of a Retained baseline
burden or behavior. A technically sound adjacent improvement is still scope
deviation. Reviewers report the violation and route it to
`gatespec.specify --revise`; they never admit scope themselves.

Independently audit the entire Subject for Test Controls; do not trust the
registered paths, namespace token, task row, or passing test. Validate the
canonical Policy and exact Requirements TCE provenance/copy first; apply a TCE
only to its named Rule and minimum replacement. Without the corresponding TCE,
a fake `testonly` namespace with real declarations in a normal namespace,
public/normal-module alias/wrapper/forwarder, test-only dependency injection in
normal production, and generic callback/options-bag state are BLOCKERs. An
echo-only validator, hidden/runtime toggle, or common Debug/`BUILD_TESTING`
trigger is always a BLOCKER. Formal product APIs cannot acquire testing params,
options, overloads, getters, or state without a `formal-api` TCE. Concretely, a test-motivated
`Open(path, CheckpointCoordinatorOptions)`, generic observer/options surface,
or injected `AgentHost` constructor is forbidden even if its default preserves
behavior unless the exact approved replacement authorizes it. Without a
`control-model` TCE, each declared control must be typed, declarative,
single-purpose, per-instance RAII, and have exactly a named one-shot/count/
barrier/time/random/fault/observation effect. Every control must close its named
verification gap, disappear from the default build with every associated
field/branch/resource/symbol, and have a real consumer/removal boundary.
Undeclared controls and orphans always block.

Absent a `touchpoint-shape` TCE, enforce source readability at every production touchpoint: each affected
production function has at most one visually contiguous dedicated hook-macro
guard block. Inside that block allow only one `testonly` call and delivery of
its result into the normal production error/result path. Counting, waiting,
fault selection, and observer dispatch live in the registered test-only root
(canonical `/src/testonly`, or the exact `source-root` replacement). Only
`touchpoint-shape` may replace guard/call/result/mechanics shape; only
`source-root` may replace that root. Crossing both requires both Rules;
`control-model` never authorizes production-side mechanics.
A scattered set of guards or production-side hook algorithm is BLOCKED even
when OFF compilation elides it and no exact TCE replaces that shape.

Do not accept deterministic stdout alone. Inspect each validator and, inside
each fresh lane clone, independently enumerate and hash the actual configure,
compile/dependency, linked artifact, test, and present install/export/symbol
outputs. Recompute declared coverage and undeclared-hit sets, then compare them
with every row value. Literal/precomputed hashes, a validator that merely echoes
a canonical row, missing output-family discovery, or a row that is stable but
not derived from the current clone is BLOCKED. The Bash checker validates the
contract/evidence chain only; it never substitutes for these project builds.

Compute Test-Control-Scale cumulatively from Original Baseline to the bound
Subject. Count additions/churn/files attributable to registered test-only
surfaces, validators, hook build wiring, and the dedicated guard blocks in
production touchpoints; `touchpoints` is the number of unique registered
`path::symbol` production touchpoints. Keep unrelated production lines out of
this scale. Report it separately from Production, but do not treat the two
sets as disjoint: a changed production touchpoint or build-wiring file remains
Production even when its dedicated guard/wiring lines also contribute to
Test-Control-Scale. Only a proven surface-only test-only object, validator, or
ordinary test is excluded from Production by the default-OFF classification.
A PASS Mode-none audit is four zeros. A BLOCKED Mode-none audit that reports an
undeclared control instead reports the attributable hidden-control scale.

For isolated REV-FINAL, reproduce the Test Control Subject Manifest, then use
two new independent `git clone --local --no-hardlinks --no-checkout` clones at
the bound Subject. Rerun the fixed default-off validator lane in one and the
explicit-on lane in the other. Default-off omits every hook option; explicit-on
sets only the registered dedicated positive options (canonical
`*_ENABLE_TEST_HOOKS`, or the exact `switch-identifier` replacement). Both run the
same normal tests, ON also runs the hook-consuming tests. Each validator stdout
must be exactly its canonical row plus LF; C-sort rerun rows and require byte
equality with the bound same-round sidecar table, then independently validate
the sidecar fields and self-hash. Either command failure, tracked delta, schema
mismatch, stale subject, or byte difference is BLOCKED. Do not reuse the
coordinator's clones or logs. This
contract promises only that omitting an explicit option yields a hook-free
default build. It does not police what a user deliberately builds/packages
after opting ON and introduces no external CI or artifact-signing requirement;
the explicit-on review lane itself needs only a test build.

The request-bound coordinator sidecars always remain canonical PASS evidence.
If this fresh reviewer rerun or independent manifest/coverage/hit derivation
fails, return a BLOCKED verdict and set the corresponding proof field (or both,
when both are affected) to `failed`; do not rewrite the bound sidecar and do not
invent a FAIL Result row. A coordinator lane failure would already have stopped
before any request/sidecar existed.

The adapter, or a manual fresh session whose returned text is supplied back to
the original `--scope` coordinator, returns exactly this Protocol 3 schema.
Test Control Audit is mechanically parsed. For PASS, Mode equals the request;
Declared is `none` or the full canonical TC list; Undeclared/Orphan are `none`;
proofs are both `not-applicable` for none mode, both `pending-REV-FINAL` for an
isolated non-final checkpoint, and both `verified` for isolated REV-FINAL.
BLOCKED may use `found` and/or a canonical orphan TC list only with concrete
BLOCKER items. Test-Control-Scale uses actual nonnegative exact integers for
the bound Subject and remains separate from Production. Additions never exceed
churn, and touchpoints exactly equals the unique registered production
`path::symbol` count. PASS none mode is exact all-zero; BLOCKED none mode with
`found` reports the detected hidden-control scale. `failed` is permitted only
for a BLOCKED isolated verdict and means
the fresh reviewer rerun/derivation failed despite PASS-only bound coordinator
sidecars; mode none always uses both `not-applicable`.

```markdown
- **Protocol-Version**: `3`
- **Review-ID**: `<request value>`
- **Round**: `<request value>`
- **Request-SHA256**: `<request value>`
- **Reviewer-Platform**: `<codex|claude|manual-codex|manual-claude>`
- **Reviewer-Context-ID**: `<nonempty fresh context/run ID>`
- **Isolation**: `fresh`
- **Status**: `<PASS|BLOCKED>`

## Tests Run

- `<exact command or scenario and outcome; never None/Not run>`

## Test Control Audit

- **Mode**: `<none|isolated>`
- **Declared-Controls**: `<none|TC-001, TC-002>`
- **Undeclared-Controls**: `<none|found>`
- **Orphan-Controls**: `<none|TC-001, TC-002>`
- **Default-OFF-Proof**: `<not-applicable|pending-REV-FINAL|verified|failed>`
- **Explicit-ON-Proof**: `<not-applicable|pending-REV-FINAL|verified|failed>`
- **Test-Control-Scale**: `additions=<N>; churn=<N>; files=<N>; touchpoints=<N>`

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
exact Test Control Audit states, and PASS/BLOCKED blocker semantics. Persist
exact returned bytes as
`round-<NN>-verdict.md`; do not rewrite reviewer content.

## Verdict handling

- BLOCKED: do not create `seal.md`. Report blockers and leave the checkpoint
  task unchecked. After validating/persisting the verdict, the coordinator
  immediately creates one local metadata-only finding commit containing that
  round's request, verdict, and for isolated REV-FINAL its two bound evidence
  files: no seal, checkpoint checkmark, product change, or push. This finding
  commit can never be a later request's Subject-Commit.
  The executor then makes a strictly later, separate remediation subject commit
  with a real product/test delta that closes the blocker; the worktree must be
  clean before the next round. This reviewer context may not do either commit.
- PASS: atomically create `seal.md` with the exact ordered fields below, copied
  from the accepted request/verdict. Use current UTC `YYYY-MM-DDTHH:MM:SSZ` and
  hash every raw byte before Seal-SHA256. Then temporarily change only the
  current checkpoint checkbox from `[ ]` to `[X]`; this is not committed until
  the checker succeeds.

```markdown
- **Protocol-Version**: `3`
- **Review-ID**: `<REV-ID>`
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
- **Test-Control-Subject-Manifest-SHA256**: `<request value>`
- **Default-OFF-Evidence-SHA256**: `<request value>`
- **Explicit-ON-Evidence-SHA256**: `<request value>`
- **Execution-Epoch**: `<request value>`
- **Source-Design-Content-SHA256**: `<request value>`
- **Implementation-Adjustments-SHA256**: `<request value>`
- **Task-Handoff-Commit**: `<request value>`
- **Preserved-Reviews-SHA256**: `<request value>`
- **Implementation-Baseline**: `<request value>`
- **Base-Commit**: `<request value>`
- **Subject-Commit**: `<request value>`
- **Final-Delta-SHA256**: `<request value>`
- **Sealed-At**: `<UTC RFC3339>`
- **Seal-SHA256**: `<lowercase 64-hex>`
```

Run `check-gate.sh implementation-candidate <feature-dir> <REV-ID>` with that
one temporary checkpoint checkmark and the candidate seal in place. On failure,
immediately restore the checkbox to `[ ]`, delete only the uncommitted candidate
seal, retain the immutable PASS request/verdict, make no commit, and do not
report PASS. A later `--scope` invocation resumes candidate validation as Step
3 specifies instead of dispatching again.

On candidate success, create one local metadata/progress commit containing the
request, verdict, seal, checkpoint checkbox, and for isolated REV-FINAL the two
bound evidence files, with no product change; require
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
