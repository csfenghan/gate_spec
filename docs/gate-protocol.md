# GateSpec 0.3.0 Gate Protocol

This document defines the Requirements/Design approval gates, native-task
review contract, fresh-context review receipts, fixed hooks, templates, and
`check-gate.sh`.

## Architecture

GateSpec remains a parallel gated path, not an upstream replacement:

```text
auto:   speckit.specify ─→ speckit.plan ─┐
                                         ├→ speckit.tasks → speckit.analyze → speckit.implement
gated:  gatespec.specify ─→ gatespec.plan┘        │ task review         │ checkpoint/final review
```

Line 1 of a gated spec is exactly `<!-- path: gatespec -->`. If the marker is
absent everywhere, every check returns zero without output. A marker anywhere
except line 1 is corruption and fails. This dispatch is the load-bearing
dual-track boundary.

Approval and review are content snapshots, not workflow states. Prompt rules
produce artifacts; one portable Bash checker validates deterministic structure
and hash chains. GateSpec adds no task generator, implement replacement,
orchestration engine, or automatic push.

## Constraint Basis

Requirements and Design read project constitution, project
`.gatespec/constraints.md`, and user `~/.gatespec/constraints.md`, in that
descending priority. `Constraint Basis` freezes source hashes, effective rules,
and conflict resolutions. A feature-impacting conclusion also appears in an
FR, scenario, Assumption, or scope boundary.

The heading and five labels remain fixed English protocol tokens. Unless a
higher-priority effective constraint requires otherwise, human-readable values
use Simplified Chinese while paths, hashes, API names, code identifiers, and
`absent` remain verbatim.

- A constitution `MUST` conflict cannot be approved inside a feature.
- A constitution `SHOULD` deviation needs a recorded reason.
- A GateSpec-constraint exemption needs an explicit feature decision and, for
  Design, a Decision Log entry.
- User-constraint drift warns until `--refresh-constraints`; constitution or
  project-policy drift forces Requirements re-approval.

## Requirements protocol

Repository facts are discovered. Unknown decisions are blocking questions or
proposed defaults, with a cheap user veto. A blocking question presents 2–4
mutually exclusive options, constraint results, and a recommendation, then
waits. Proposed defaults are batch-approved once. “Proceed” never seals an
unresolved blocking item.

Empty sections have exact semantics:

```markdown
## Clarifications
- None — <reason>
## Approved Defaults
- None — <reason>
```

Each conclusion lands in the body. Every FR is defined once and referenced by
an Acceptance Scenario; every scenario references a defined FR. The third and
final human feature-content approval mechanism is the explicit approval of a
≤20-line Requirements summary containing “what I am least confident about”.
Revision rounds show only the diff.

## Design protocol

The Requirements Gate passes before planning. plan.md records the approved spec
content hash computed before its Gate Approval H2. Spec re-approval therefore
invalidates an old plan.

Every non-trivial design decision uses an exact `### D<n>: <topic>` block with
at least two concrete scenarios, observable trade-offs, constraint results, a
recommendation, and one dated user choice. A design with no such decision uses:

```markdown
- None — <specific reason no non-trivial decision exists>
```

The six exact Design Detailing dimensions are concurrency, object
lifetime/ownership, modules/classes, internal API interactions, external
behavior contracts, and setup/runtime/teardown. Each has substantive content
or `N/A — <reason>`; constraints may add dimensions but never replace them.

An implementer's walkthrough closes each unsigned fork as an approved decision
or bounded Implementation Freedom. Bidirectional traceability prevents orphan
FRs and unapproved design. quickstart supplies a runnable path per P1 story.
Immediately before summary, the agent checks spec, plan, research, data model,
contracts, and quickstart. Native analyze still occurs only after native tasks.

### Implementation Review Contract

Every newly approved plan contains one exact mandatory
`## Implementation Review Contract` with these fields:

```markdown
- **Protocol Version**: `1`
- **Required Checkpoints**: `REV-FOUNDATION, REV-US1, REV-FINAL`
- **Review Root**: `.gatespec/reviews`
- **Task Review**: `REV-TASKS after speckit.analyze; PASS required before speckit.implement`
- **Reviewer Isolation**: `fresh-context-required; manual-new-session-on-unavailable; same-context-forbidden`
- **Parallel Policy**: `same-phase-disjoint-only; join-before-review; cross-checkpoint-forbidden`
- **Git Policy**: `clean-feature-branch; local-checkpoint-commits; no-push`
- **Remediation Limit**: `2`
```

Required Checkpoints lists `REV-FOUNDATION`, one actual `REV-US<n>` per
implemented user-story phase, and exactly one `REV-FINAL`. An exact
`### Checkpoint Test Mapping` table has one non-empty test-command row per ID:

```markdown
| Checkpoint | Required test command(s) |
|------------|--------------------------|
| REV-FOUNDATION | <exact command(s)> |
| REV-US1 | <exact command(s)> |
| REV-FINAL | <exact command(s)> |

- **Final Validation**: `<non-empty end-to-end validation>`
```

REV-FINAL reviews the complete feature subject; earlier seals cannot be
aggregated as a substitute.

An old Approved-Design plan without this contract is not grandfathered. Plan
resume archives tasks and current reviews, applies existing `--revise`
semantics, adds the contract, obtains diff-only Design re-approval, and then
regenerates native tasks.

Task and implementation review PASS verdicts are not human approvals. A
reviewer cannot introduce a feature choice, waiver, or scope change. Such a
finding returns to Requirements or Design diff-approval.

## Native task and task-review protocol

Native `speckit.tasks` remains the only task generator. Every required
checkpoint maps to exactly one phase-ending, non-`[P]` checklist row containing
all three literal elements:

```text
GateSpec review checkpoint <REV-ID>: run speckit.gatespec.review-implementation --scope <REV-ID>; require .gatespec/reviews/<REV-ID>/seal.md before continuing.
```

The `after_tasks` structural hook rejects missing, duplicate, extra, parallel,
or misplaced checkpoint rows and mismatched test mapping; it never edits tasks.
Same-phase parallel work must be disjoint and joined before the checkpoint. No
work crosses a checkpoint without its matching PASS seal.

Native `speckit.analyze` then runs unchanged. Its after hook obtains the
separate `REV-TASKS` semantic review. That review checks coverage, ordering,
dependency/parallel safety, exact test/checkpoint mapping, and absence of new
unapproved choices. The tasks-definition hash normalizes only checkbox progress
(`[ ]`, `[x]`, `[X]`) so native implementation can safely resume. A current
REV-TASKS PASS seal is required by the fixed `before_implement` hook.
The coordinator commits the approved artifacts, tasks, REV-TASKS rounds, and
seal locally, verifies a clean worktree, and only then runs the task-review
checker. That clean HEAD is the implementation baseline; checking before this
commit is invalid.

Task-only findings return to native tasks/analyze. Requirement or design
findings return to the applicable gated phase.

## Implementation review protocol

Review artifacts live under
`<feature>/.gatespec/reviews/<REV-ID>/`. Initial review uses
`round-00-request.md` and `round-00-verdict.md`; remediation may create only
round 01 and round 02. A third remediation round is forbidden. Each new round
binds the preceding BLOCKED verdict and a newly committed subject. Checkpoint
commits remain local on a clean feature branch; no review command pushes.

The implementation context may join workers, run mapped tests, create a local
checkpoint commit, revalidate REV-TASKS on that clean subject, and prepare a
request. It cannot write a verdict. A fresh reviewer checks the request,
committed subject, approved Requirements/Design, tasks, test evidence, and
prior finding closure. It edits no source, spec, plan, or tasks. BLOCKED writes
findings but no seal. PASS alone may produce `seal.md`, binding the request,
PASS verdict, subject, and upstream bases.

When an integration can create a genuinely fresh context it may delegate and
wait. Otherwise GateSpec stops and gives the user a manual new-session
invocation. That top-level manual context skips coordinator behavior, writes
nothing, and returns exact `manual-codex` or `manual-claude` verdict text to the
original coordinator for validation/persistence/sealing. Same-context review,
including remediation and re-review by one context, is forbidden. The receipt
records the isolation claim, but the Bash checker does not cryptographically
attest reviewer identity or session origin. A manual reviewer never changes the
primary worktree, index, branch, commits, or remotes; a test that may write runs
only in a unique detached temporary worktree, which must be clean and removed
afterward. Ephemeral hashing/test files may use `/tmp`; repository and other
persistent files remain read-only.

The implementation baseline is exactly the current REV-TASKS seal path's
latest-touch commit (`git log -1 --format=%H -- <feature-relative-seal-path>`),
whose blob must equal the current seal. It is constant across all requests; a
later descendant that merely contains the seal is not the baseline.
REV-FOUNDATION uses it as Base-Commit; each REV-US<n> uses the preceding stage
Subject-Commit; REV-FINAL deliberately uses the implementation baseline again
so its base-to-subject diff covers the whole feature. Remediation rounds retain
their checkpoint's Base-Commit.

The checkpoint task stays unchecked throughout request and review. On BLOCKED
the implementation context may remediate and open the next allowed round;
first the coordinator makes a local metadata-only finding commit containing
request and verdict but no seal, checkmark, or product change. That commit is
never a later Subject-Commit; the executor must create a strictly later
remediation subject containing a real product/test delta. The reviewer context
never fixes its own finding. On PASS, the coordinator creates a candidate seal
and temporarily checks the current checkpoint before running the
`implementation-candidate` checker. A failure immediately restores `[ ]`,
deletes that candidate seal, retains the immutable PASS request/verdict, and
creates no commit. The next invocation recognizes PASS-without-seal as a
candidate resume, revalidates unchanged bindings, and never dispatches/open a
new round; binding drift instead requires restoration or explicit upstream
revise/restart. Candidate success creates a local metadata/progress commit with
the request, verdict, seal, and checkbox, then the clean/tracked
`implementation-review` checker must pass. This same two-state ordering lets
REV-FINAL enforce both all-tasks-checked during candidate validation and a clean
committed final receipt. Every next round/phase starts clean, and none of these
commits is pushed. REV-FINAL independently reviews the full final subject and
runs Final Validation. The fixed `after_implement` hook defaults to REV-FINAL
and withholds the native completion report until its current final check passes.

## Safe reruns

| State/flag | Required behavior |
|---|---|
| Draft, no flag | Continue in place; never recopy the template. |
| Valid Approved artifact and current review contract | Read-only; hand off. |
| Approved plan missing review contract | Archive downstream work, reopen via revise, diff re-approve. |
| `--revise` | Archive tasks/current reviews, reopen Draft, preserve baseline, diff re-approve. |
| `--restart` | Archive phase/downstream artifacts and current reviews, rebuild template. |
| `--refresh-constraints` | Recompute spec basis and enter revision flow. |

Invalid approval or review metadata is never auto-repaired. Archives include
current non-archive review contents and are never archived recursively.

## Snapshot formats

`## Gate Approval` occurs exactly once, is the final H2, and contains only:

```markdown
- **Approved by user**: YYYY-MM-DD
- **Content-SHA256**: `<lowercase 64-hex>`
```

The Status approval date agrees. Its digest is:

```bash
sed '/^## Gate Approval/,$d' artifact.md | sha256sum
# macOS: ... | shasum -a 256
```

Review request, verdict, and seal files use their exact protocol field groups;
every digest is lowercase 64-hex. The deterministic chain is request → verdict
→ PASS-only seal. Each link names the same REV-ID/round and binds the required
approved bases and review subject. A syntactically valid digest never converts
a BLOCKED verdict into PASS.

The ordered request fields are `Protocol-Version`, `Review-ID`, `Round`,
`Scope`, `Spec-Content-SHA256`, `Plan-Content-SHA256`,
`Design-Attachments-SHA256`, `Tasks-Definition-SHA256`,
`Implementation-Baseline`, `Base-Commit`, `Subject-Commit`, `Task-IDs`,
`Changed-Paths-SHA256`, and `Previous-Verdict-SHA256`; exact H2
`## Required Tests` follows, then final `Request-SHA256`. REV-TASKS uses
`not-applicable` for all four Git fields and `none` for Task-IDs. Each
implementation request uses one bullet exactly equal to its mapping cell;
REV-FINAL adds the exact Final Validation as another bullet only when distinct.
Implementation Task-IDs is the exact tasks.md-order list of non-checkpoint rows
in that phase (all pre-story setup/foundational rows for FOUNDATION); REV-FINAL
lists every feature non-checkpoint T###.

The ordered verdict fields are `Protocol-Version`, `Review-ID`, `Round`,
`Request-SHA256`, `Reviewer-Platform`, `Reviewer-Context-ID`, `Isolation`, and
`Status`; exact H2 sections `Tests Run`, `Blockers`, `Observations`, and
`Limitations` follow in that order, then final `Verdict-SHA256`. Status is only
`PASS` or `BLOCKED`; PASS has exactly `- None` under Blockers, while BLOCKED has
at least one `- BLOCKER: ...` item. Implementation Tests Run covers every
approved Required Tests string and adds non-empty result text.

The ordered seal fields are `Protocol-Version`, `Review-ID`, `Round`, `Status`,
`Request-SHA256`, `Verdict-SHA256`, the four artifact hashes,
`Implementation-Baseline`, `Base-Commit`, `Subject-Commit`, `Sealed-At`, and
final `Seal-SHA256`. Each self-hash covers all raw bytes before its own final
hash-field line. The design-attachments digest hashes the C-sorted
`relative-path<TAB>file-SHA256<LF>` manifest of research.md, data-model.md,
quickstart.md, and files under contracts/. The tasks digest first normalizes
CRLF to LF and only valid T### checkbox progress `[xX]` to `[ ]`. Changed paths
hash the C-sorted output of
`git diff --no-renames --name-only <base> <subject>`.

## Machine-check boundary

Requirements checks cover the marker, mandatory sections,
clarification/default formats, residual markers, FR/scenario scoping, approval
structure/date/hash, constraint drift, and warning-only vague wording.

Design includes Requirements and then checks the Requirements hash chain,
Decision Log, six Design Detailing dimensions, mandatory upstream sections,
Implementation Review Contract, template remnants, and approval snapshot.

Tasks-structure checks cover exact contract fields, checkpoint/test-set
equality, checkpoint row uniqueness/order/non-parallel form, and the three
literal task tokens. Task-review checks validate REV-TASKS request, PASS
verdict, seal chain, plan basis, and normalized tasks definition.
Implementation-review checks validate the selected REV-ID (REV-FINAL by
default), bounded rounds, request/verdict/seal chain, subject/upstream hashes,
PASS-only sealing, and current-scope freshness. Its internal
`implementation-candidate` variant permits only the uncommitted candidate seal
and current checkpoint checkmark; final `implementation-review` additionally
requires the accepted seal/checkmark to be clean and tracked.

Semantic sufficiency, review judgment, reviewer isolation, and test truth remain
prompt/operator responsibilities. An external runner is needed for signed
identity or non-bypassable merge/deploy enforcement.

Native implement has no per-task hook. REV-FOUNDATION and REV-US<n> therefore
stop execution through the cooperative prompt/task contract; registered
before/after hooks and the final receipt checker block normal entry/completion
reports, but cannot roll back code already written or prevent deliberate hook
bypass.

## Hook contract

| Event | GateSpec command | Purpose |
|---|---|---|
| `before_plan` | `check-requirements` | Approved Requirements required |
| `before_tasks` | `check-design` | Approved Design/contract required |
| `after_tasks` | `check-tasks` | Native task/checkpoint structure |
| `after_analyze` | `review-tasks` | Fresh-context REV-TASKS verdict |
| `before_implement` | `check-task-review` | Current REV-TASKS PASS seal |
| `after_implement` | `check-implementation-review` | Current REV-FINAL PASS seal |

Manual check modes are `spec`, `design`, `tasks-structure`, `task-review`, and
`implementation-review [REV-ID]`. Only spec/design retain interactive default
inference. Gated specify/plan execute peer extensions' same-phase hooks while
excluding `speckit.gatespec.*`, preventing recursion. Unmarked upstream
features remain silent in all GateSpec hooks.

Spec-kit dispatches these hooks through prompts. Missing/invalid extension
wiring and reviewer provenance are outside the portable checker's trust
boundary.
