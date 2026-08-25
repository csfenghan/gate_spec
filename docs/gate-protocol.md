# GateSpec 0.8.0 Gate Protocol

This document defines Requirements/Design gates, optional Source Design,
native-task and implementation reviews, final delivery acceptance, hooks,
templates, and `check-gate.sh`.

## Architecture

GateSpec remains a parallel gated path, not an upstream replacement:

```text
auto:   speckit.specify ─→ speckit.plan ────────────────────────────────┐
gated:  gatespec.specify ─→ gatespec.plan ─→ [optional source-design] ─┤
              └→ native speckit.tasks → bounded task-only refinement
                    → speckit.analyze → speckit.implement
                         task review     automatic reviews → final acceptance
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

## Scenario-first decision triage and batches

Specify and Plan make a complete first-pass inventory, then classify before
asking. A Requirements unknown is a blocking human decision, a proposed
routine default, or a technical matter deferred to Design. A Design fork is a
human decision, a reasoned engineering determination, or bounded
Implementation Freedom. Only a choice with at least two viable compliant
options and materially different consequences for an affected user, product
owner, operator, or maintainer receives an `R<n>`/`D<n>` approval card.
Requirement/MUST conflicts and dominated alternatives are excluded, not used
as artificial options. Uncertain classification is promoted to human decision.

Engineering determinations cover requirement-fixed outcomes whose
cross-component contract must be closed in Design, or a strictly simpler option
with no worse material consequence. They are recorded in Design
Detailing/research without `D<n>` or an individual approval field. Externally
equivalent choices on which no approved artifact depends are bounded in
Implementation Freedoms. `explain <topic>` and `discuss <topic>`
let the user inspect or promote either bucket before final approval; this is a
cheap conversational veto, not stored state or a fourth approval mechanism.

The dependency graph covers only human decisions and remains transient prompt
reasoning, not a persisted workflow artifact or orchestration state. A
decision depends on another when any option can change its existence,
scenario, options, recommendation, or constraint result. Only frontier
decisions may share a batch; uncertainty creates an edge, and a cycle
collapses into one coherent bundled decision.

Every conversational card is self-contained and ordered for human
comprehension: a plain question, one short domain-native engineering scenario,
direct option bullets in that scenario, and a natural recommendation.
Observable consequences precede mechanisms, while relevant API, thread,
lifecycle, protocol, state, and error vocabulary remains intact instead of
becoming a consumer analogy. Fixed boundaries and supporting evidence are
integrated where they affect the choice or expanded through `explain R<n>` /
`explain D<n>`; conversation does not expose them as a fixed questionnaire
schema. A non-UI feature never gains invented clicks, buttons, pages, or other
UI proxies. Removing artifact identifiers and citations must not make the
choice unintelligible.

Each round has cognitive load at most four. A normal card has load one; a
complex or high-risk card consumes all four units and is presented alone.
Simple cards share an actor/journey where possible; the agent presents fewer
rather than force unrelated mental contexts together. High-risk cards require
an explicit ID/choice; whole-batch recommendation shortcuts exclude them.

A compact progress line reports resolved/currently-known human decisions plus
current IDs and topics. Dependency-blocked topics are named only when they
explain sequencing; raw dependency counts, unchanged hashes, successful or
absent hooks, and resume recaps stay out unless they require action or affect a
choice. A separate digest reports other bucket counts only on first inventory
or material reclassification. Partial answers are validated together, then
every unaffected explicit answer is retained. Unanswered IDs lead the next
batch, conflicts become an explicit reconciliation decision, and retired
legacy IDs are not reused. Per-round split/single/cap and explain/discuss
controls are temporary. The Bash checker validates compatible artifact
structure, not semantic classification, self-containment, conversational
presentation, or batch provenance; rendered-protocol assertions and
dual-platform behavioral smoke cover those prompt contracts.

## Requirements protocol

Repository facts are discovered. Technology choice alone is not a blocking
Requirement: technical-only matters move to Design. Each blocking card has
2–4 viable options in one shared engineering scenario, with boundaries and
decision-relevant evidence integrated into its prose rather than rendered as
fixed fields. Stable `R<n>` IDs map explicit answers into the existing
`- Q: [R<n>] ... → A: ...` form; legacy unnumbered entries remain valid.
Proposed defaults are batch-approved once. They may be co-presented as one
independent normal card, never with a complex/high-risk card, and require their
own explicit approval; a decision shortcut never approves them. “Proceed” never
seals an unresolved blocking item.

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

## Delivery Estimate protocol

New or actively revised spec.md and plan.md declare exact
`**Delivery Estimate Schema**: 1` and one `## Delivery Estimate`. Requirements
records these seven ordered fields; Design adds the final comparison pair:

```markdown
- **Production additions**: `100..200`
- **Production churn**: `140..280`
- **Production files**: `4..8`
- **Estimate basis**: <substantive basis and uncertainty>
- **Production path basis**: <repository-relative path families>
- **Excluded paths**: <patterns and reasons>
- **Confidence**: <level and reason>
- **Requirements estimate relation**: `within|expanded|reduced`
- **Requirements estimate rationale**: <substantive reason>
```

Every range is non-negative, lower ≤ upper, and additions ≤ churn at both
bounds. Churn is additions + deletions. Production includes handwritten
runtime code, headers, protocol/schema, configuration, and build/packaging
logic. It excludes tests, specification/review metadata, pure documentation,
and reproducibly generated output. A generated exclusion is valid only as
`generated: <output> <- <source> via <generator>`; undeclared generated output
is counted as production.

Specify identifies independently deliverable capability boundaries before
detailed clarification. A meaningful merge/split choice is an ordinary
`R<n>` decision; no sibling spec is created automatically. Requirements may
use wide ranges and low confidence. Design inspects real modules, callers,
schemas/config/build wiring, and test surface, narrows or explains uncertainty,
and records its relation to Requirements. Legacy Requirements without an
estimate allow Design relation `not-applicable` with a reason.

The three metrics and confidence appear in both existing ≤20-line approval
summaries. Their acceptance is part of the normal Requirements/Design summary
approval, not a fourth mechanism. No LOC, file, task, or checkpoint ceiling
exists; a disclosed large estimate is valid.

Source Design, task refinement, and fresh REV-TASKS independently re-estimate
the complete feature. Any upper bound satisfying
`new_upper * 100 >= design_upper * 125`, any positive upper bound against an
approved zero, or any production path family outside Design's path basis
blocks to `gatespec.plan --revise`. Exactly 25% blocks; less does not. A
scope-changing split returns to `gatespec.specify --revise`. This is a drift
re-confirmation, not a size limit.

Legacy Approved Requirements missing the structure pass with a warning and
remain immutable. Legacy Approved Design missing it blocks before tasks unless
checked tasks, implementation-review receipts, or product-code delta proves
implementation progress; progressed legacy delivery passes with a warning.

## Design protocol

The Requirements Gate passes before planning. plan.md records the approved spec
content hash computed before its Gate Approval H2. Spec re-approval therefore
invalidates an old plan. Current plans also contain exactly one
`**Design Evidence Schema**: 1`; another declared version fails closed rather
than being downgraded.

Every design choice requiring individual human approval uses an exact
`### D<n>: <topic>` block with one shared scenario, fixed boundary, why human
input matters, at least two viable same-scenario options, observable trade-offs,
constraint results, a recommendation, Technical basis, and one dated user
choice. The agent normalizes the approved conversational choice into this
structured artifact form; the fields are not the interactive card. Adaptive
batch grouping is never stored in the Decision Log. A design with no such
decision uses:

```markdown
- None — <specific reason no design choice required individual human approval>
```

The six exact Design Detailing dimensions are concurrency, object
lifetime/ownership, modules/classes, internal API interactions, external
behavior contracts, and setup/runtime/teardown. Each is either one reasoned N/A
or its Schema 1 child fields:

| Dimension | Structured evidence |
|---|---|
| concurrency | execution contexts, directed cross-context flow, synchronization/safety contract, Technical basis |
| lifetime/ownership | owned resources, lifetime flow, memory/resource contract, Technical basis |
| modules/classes | inspected repository anchors, existing/modified/new change map, dependency contract, Technical basis |
| internal APIs/interactions | existing entry points, language-native contract skeleton, primary success/failure interaction, semantic contract, Technical basis |
| external behavior | affected surfaces, behavior and compatibility contracts, Technical basis |
| setup/runtime/teardown | states/owner, phase flow, failure/recovery contract, Technical basis |

Contract skeletons contain declarations rather than production bodies; bounded
pseudocode appears only when required to express a core state, concurrency, or
algorithm invariant. A skeleton may be a reasoned N/A when no executable
contract changes. Relationships remain directional and include material
execution context, ownership, data, and failure results, so a later tool can
derive component and sequence views. Mermaid and all other diagrams are
optional. Constraints may add dimensions but never replace the six core ones.

An implementer's walkthrough closes each fork as an approved human decision, a
reasoned engineering determination in Design Detailing/research, or bounded
Implementation Freedom. It also audits classification so a human-relevant
consequence cannot hide in a technical bucket. Bidirectional traceability
prevents orphan FRs and unapproved design. quickstart supplies a runnable path
per P1 story. Immediately before summary, the agent checks spec, plan, research,
data model, contracts, and quickstart, then verifies that a fresh reader can
reconstruct the design boundary, component integration, core interactions,
thread/resource/lifecycle contracts, and rationale without choosing an
architecture. The ≤20-line Design summary exposes the change boundary, primary
flow, material engineering determinations, and implementation freedoms so the
user can promote one before final approval. Native analyze still occurs only
after native tasks.

### Implementation Review Contract

Every newly approved plan contains one exact mandatory
`## Implementation Review Contract` with these fields:

```markdown
- **Protocol Version**: `2`
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

Each mapping cell is one line and has exactly two Markdown-table columns. A
raw `|` is rejected; put pipelines or multi-command validation in an
executable script and use the script invocation as the mapped value.

REV-FINAL reviews the complete feature subject; earlier seals cannot be
aggregated as a substitute.

An old Approved-Design plan without this contract is not grandfathered. Plan
resume archives tasks and current reviews, applies existing `--revise`
semantics, adds the contract, obtains diff-only Design re-approval, and then
regenerates native tasks.

Task and implementation review PASS verdicts are not human approvals. A
reviewer cannot introduce a feature choice, waiver, or scope change. Such a
finding returns to Requirements or Design diff-approval.

Legacy approved Protocol v1 Plans remain valid only while Source Design is not
enabled. Source activation independently switches downstream receipts to v2
without editing the approved Plan.

## Optional Source Design protocol

`contracts/source-design.md` alone enables Source Design and starts with
`<!-- gatespec: source-design -->`; orphan shards/REV-SOURCE fail. The user may
enable it after Design and before product implementation, or skip directly to
native tasks. Existing tasks/analyze/REV-TASKS may be archived and regenerated
only when no implementation progress, product diff, IA, or implementation
review exists.

The entry and optional direct `contracts/source-design/*.md` shards specify maintainer
scenario, before/after, success/failure, complete SD-F operations, critical
SD-U declarations, SD-FLOW lifecycle/data/state paths, SD-ALG algorithms and
invariants, SD-FAIL propagation/recovery/observability, SD-TEST traceability,
cross-cutting design, bounded freedoms, and prohibited material boundaries.
Human-relevant source choices use SD<n> and the existing decision mechanism.

REV-SOURCE uses a distinct Protocol v2 SOURCE request. It binds current Spec,
Plan, the original Design Basis with Source excluded, Source baseline commit,
and Source-Design-Reviewed-SHA256. The reviewed manifest entry digest removes
the unique Status line and final Gate Approval; shard digests are raw. Thus
approval-only edits preserve PASS, while body/shard drift invalidates it. After
fresh PASS, explicit user summary/diff approval sets
Approved-Source-Design and Source-Design-Content-SHA256. The content manifest
hashes entry bytes before Gate Approval plus raw shards. Both manifests hash
the C-sorted `<feature-relative-path><TAB><file-SHA256><LF>` byte stream.

Source revision after implementation blocks normal implement. Work after the
last PASS Subject is preserved as binary patch and path manifest, a normal
compensating commit restores the safe Subject without reset/rebase/stash, and
old Source/tasks/reviews/IA/acceptance are archived. Original Baseline remains
unchanged. Fresh revalidation under `.gatespec/revalidations/E<n>/` binds each
preserved PASS Subject; unreviewed work is never reapplied automatically. Each
revalidation retains its creation epoch and binds its preserved Subject plus
Source hash. A later task-only retask does not relabel or regenerate that
evidence when those bindings are unchanged; the new execution epoch instead
binds the C-sorted raw revalidation manifest through
Preserved-Reviews-SHA256.

## Native task and task-review protocol

Native `speckit.tasks` remains the only creator of `tasks.md`. Every required
checkpoint maps to exactly one phase-ending, non-`[P]` checklist row containing
the canonical reviewer command and stop condition:

```text
GateSpec review checkpoint <REV-ID>: run speckit.gatespec.review-implementation --scope <REV-ID>; require .gatespec/reviews/<REV-ID>/seal.md before continuing.
```

Priority-10 `after_tasks` runs `refine-tasks` before structural validation. It
reads the complete approved basis and native tasks, performs the fixed
type/build/API-consumer/producer-to-test/lifecycle/earliest-checkpoint/
path-symbol-parallel/artifact-trace/prior-blocker audit, and repairs every
task-local gap in one coherent pass. Its only write boundary is that exact
`tasks.md`; it cannot edit approved artifacts, receipts, execution metadata,
product files, Git state, or remotes. A Requirements, human-choice, Design, or
Source gap blocks and routes back to the corresponding revision protocol.

The refined task file contains exactly two mandatory Closure H2 sections, in
order, as the final two H2 sections before its first `## Phase`:

```markdown
## GateSpec Checkpoint Closure *(gatespec: mandatory)*

| Checkpoint | Contract refs | Production tasks | Verification tasks |
|---|---|---|---|
| REV-FOUNDATION | D1, FR-001 | T001 | T002 |

## GateSpec Prior Review Closure *(gatespec: mandatory)*

| Finding-SHA256 | Source verdict | Required-before | Remediation tasks |
|---|---|---|---|
| none | none | none | none |
```

Checkpoint rows exactly follow Plan order. Each row owns the non-checkpoint
task interval strictly after the preceding checkpoint and before its own
checkpoint. Across its Production/Verification cells every executable task
appears globally exactly once in file order; Production may be exact `none`,
Verification is nonempty. Contract refs use original IDs, no ranges, C-sorted
and joined only by comma-space. Collectively they cover all FR-###, SC-###,
approved D<n>, and, with Source, approved SD<n> plus every SD-* ID.

Prior findings come only from current REV-TASKS and
`.gatespec/archive/*-retask/reviews/REV-TASKS`. A verdict is relevant when its
Spec, Plan, Design Attachments and, for v2, Source content basis equal the
current approved basis; tasks/epoch/handoff/IA fields do not determine this
selection. Each complete raw `- BLOCKER:` Markdown item, including continuation
lines and their LF bytes, has identity SHA-256 and source
`<feature-relative-verdict>#B<NN>`. A row maps it to existing non-checkpoint
remediation tasks no later than one Required checkpoint. No finding uses the
single exact all-`none` row. Restart/revise/Source-revision archives are ignored.
The tables are navigation/trace evidence, not proof of semantic closure; the
fresh task reviewer still judges completeness and whether remediation works.

Priority-20 `after_tasks` rejects malformed Closure, missing/duplicate/extra/
parallel/misplaced checkpoint rows, interval or ref gaps, stale finding rows,
and mismatched test mapping. Both Closure sections may be absent only when a
complete current REV-TASKS PASS seal is tracked at HEAD, byte-current, and the
worktree is clean. One missing section or any malformed section is never
grandfathered. With Source enabled the checker also requires the approved
Source content hash, SD-* and precise-path refs on every non-checkpoint task,
and complete coverage of all Source IDs/manifest paths.
Same-phase parallel work must be disjoint and joined before the checkpoint. No
work crosses a checkpoint without its matching PASS seal.

Native `speckit.analyze` then runs unchanged. Its after hook obtains the
separate `REV-TASKS` semantic review. That review checks coverage, ordering,
dependency/parallel safety, exact test/checkpoint mapping, and absence of new
unclassified human choices. Approved decisions, recorded engineering
determinations, and bounded Implementation Freedoms are all valid task inputs;
an unbounded or human-relevant implementation-time choice is a blocker. The
tasks-definition hash normalizes only checkbox progress (`[ ]`, `[x]`, `[X]`)
so native implementation can safely resume. A current REV-TASKS PASS seal is
required by the fixed `before_implement` hook.
The coordinator commits the approved artifacts, tasks, REV-TASKS rounds, and
seal locally, verifies a clean worktree, and only then runs the task-review
checker. V2 first binds a clean Task-Handoff commit, execution epoch, unchanged
Original Baseline, optional empty IA, and preserved reviews; the later clean
commit containing the REV-TASKS seal is the Implementation Baseline. Checking
before it is invalid.

Task-only findings return to native tasks/analyze. Requirement or design
findings return to the applicable gated phase.

### Retask after task-review exhaustion

`gatespec.plan --retask` is the sole bounded regeneration path that does not
reopen approved Design. `retask-eligible` accepts only either a complete valid
REV-TASKS round-02 BLOCKED chain without a seal, or a valid PASS handoff before
implementation. It rejects round 00/01, malformed/orphan/stale reviews,
checked tasks, any implementation receipt, nonempty IA, acceptance, product
delta, detached HEAD, unrelated worktree changes, and any archive source whose
index blob differs from its working bytes (`MM`/`AM` snapshot ambiguity).
The comparison is unconditional for every indexed archive source, including
paths hidden by index flags, and every ancestor must be non-symlink. Existing
retask archives are exact-tree, tracked/raw-HEAD, chain, payload, handoff, and
epoch revalidated even when legacy tasks have no Closure tables. An archive
source carrying an index flag blocks even if its bytes currently match, because
its removal is not reproducibly stageable. Product-history inspection begins at the first v1 Plan boundary
or the v2 Original Baseline, audits every commit path and historical tasks/IA
blob, and therefore rejects checked tasks or nonempty IA that were later
restored. V2 additionally binds the complete Task-Handoff tree, anchors the
unchanged Original Baseline in the first committed execution state, and
requires gap-free epoch transitions.
At this entry boundary, existing Closure must be either wholly absent under the
legacy rule or structurally complete; the old tasks are not required to map the
new items in the legal unsealed terminal round-02 BLOCKED verdict that they
could not yet contain. Round-00/01 and prior retask-archive findings, plus every
existing row, remain strict. Regenerated tasks must map terminal findings after
the chain moves into the retask archive.

The command computes one UTC `YYYYMMDDTHHMMSSZ` timestamp and reserves
`.gatespec/archive/<timestamp>-retask/`. Any exact target or path-mapping
collision blocks before writes; it never overwrites, merges, changes suffix,
or waits for a new timestamp. One local archive commit moves `tasks.md` and
current `reviews/REV-TASKS`; v2 also archives execution state and IA. A second
local handoff commit contains regenerated tasks/state and no product change.
No step pushes.

Protocol v1 creates no execution state. Protocol v2 increments the execution
epoch, preserves Original Baseline, resets Task Handoff to `pending`, binds
current Source or `not-applicable`, derives Preserved Reviews, and creates
canonical empty IA with the exact template None row and no extra fields,
headings, comments, or prose when
Source is enabled. Native tasks remains the creator;
the normal refine → check → analyze → fresh REV-TASKS sequence then runs. New
Prior Review Closure rows retain all basis-matching blockers from current and
earlier `*-retask` archives.

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
only in a unique isolated temporary checkout (a platform worktree or local
clone), which must be clean and removed afterward. Ephemeral hashing/test files
may use `/tmp`; repository and other persistent files remain read-only.

The implementation baseline is exactly the current REV-TASKS seal path's
latest-touch commit (`git log -1 --format=%H -- <feature-relative-seal-path>`),
whose blob must equal the current seal. It is constant across all requests; a
later descendant that merely contains the seal is not the baseline.
REV-FOUNDATION uses it as Base-Commit; each REV-US<n> uses the preceding stage
Subject-Commit; v1 REV-FINAL uses the implementation baseline again. V2
REV-FINAL uses the unchanged Original-Implementation-Baseline and hashes the
raw NUL-delimited diff-tree stream as Final-Delta-SHA256, while Subject still
descends from Implementation Baseline. Remediation rounds retain
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
and withholds completion until its current final check passes. Non-final PASS
continues automatically with no user question. A second after hook presents
one ≤20-line whole-delivery summary. It computes actual additions, churn, and
unique handwritten production files from Git `--numstat --no-renames` over the
bound Original Baseline to REV-FINAL Subject, excluding tests, feature/review
metadata, docs, and Design-declared generated outputs. Binary production files
count as files and are disclosed without line counts. Actuals appear beside
Design ranges/confidence; variance alone does not fail delivery. Explicit
acceptance alone writes the self-hashed `.gatespec/acceptance.md` metadata-only
local commit.

## Safe reruns

| State/flag | Required behavior |
|---|---|
| Draft, no flag | Continue in place; enrich missing Schema 1 fields without recopying or renumbering decisions. |
| Valid Approved artifact, Schema 1, and current review contract | Read-only; hand off. |
| Approved plan missing review contract or Schema 1 | Archive downstream work once, reopen via revise, enrich, diff re-approve. |
| Legacy Approved Requirements missing Delivery Estimate | Warn, keep immutable, and require the next Design to supply the first estimate. |
| Legacy Approved Design missing Delivery Estimate | Revise before tasks; if implementation progress already exists, retain with warning and report final actuals. |
| Source/tasks estimate reaches 25% growth or a new path family | Return to Plan revision and diff-only estimate re-confirmation; scope-changing split returns to Requirements. |
| Plan declares an unknown design-evidence schema | Stop; never downgrade or guess a rewrite. |
| First Source enable | Before code only; archive stale tasks/REV-TASKS and regenerate. |
| Source revise after code | Preserve patch, compensate to safe Subject, archive, fresh review/approval/revalidation; keep Original Baseline. |
| `plan --retask` | Only after `retask-eligible`; archive tasks/REV-TASKS (plus v2 state/IA), then regenerate through native tasks and normal closure/review hooks in two local no-push commits. |
| `--revise` | Archive Source/tasks/reviews/revalidations/execution/IA/acceptance, reopen Draft, preserve baseline, diff re-approve. |
| `--restart` | Archive phase/downstream Source/execution/review/acceptance artifacts, rebuild template. |
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

The legacy v1 ordered request fields are `Protocol-Version`, `Review-ID`, `Round`,
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

Protocol v2 inserts `Execution-Epoch`, `Source-Design-Content-SHA256`,
`Implementation-Adjustments-SHA256`, `Task-Handoff-Commit`, and
`Preserved-Reviews-SHA256` after Tasks Definition, plus
`Final-Delta-SHA256` after Changed Paths. Non-final scopes use
`not-applicable` for Final Delta. SOURCE has a separate minimal schema with
`Design-Basis-SHA256`, `Source-Design-Reviewed-SHA256`, and
`Source-Baseline-Commit`; it is not a Plan checkpoint.

The ordered verdict fields are `Protocol-Version`, `Review-ID`, `Round`,
`Request-SHA256`, `Reviewer-Platform`, `Reviewer-Context-ID`, `Isolation`, and
`Status`; exact H2 sections `Tests Run`, `Blockers`, `Observations`, and
`Limitations` follow in that order, then final `Verdict-SHA256`. Status is only
`PASS` or `BLOCKED`; PASS has exactly `- None` under Blockers, while BLOCKED has
at least one `- BLOCKER: ...` item. Implementation Tests Run covers every
approved Required Tests string and adds non-empty result text.

Prior Review Closure hashes each complete raw BLOCKER list item separately,
from its leading `- BLOCKER:` through all continuation lines, with one LF per
line. Its `#B01`, `#B02`, ... ordinal is local to that verdict's source order;
identical text in distinct source items remains distinct rows.

The ordered v1 seal fields are `Protocol-Version`, `Review-ID`, `Round`, `Status`,
`Request-SHA256`, `Verdict-SHA256`, the four artifact hashes,
`Implementation-Baseline`, `Base-Commit`, `Subject-Commit`, `Sealed-At`, and
final `Seal-SHA256`. Each self-hash covers all raw bytes before its own final
hash-field line. The design-attachments digest hashes the C-sorted
`relative-path<TAB>file-SHA256<LF>` manifest of research.md, data-model.md,
quickstart.md, and files under contracts/; v2 excludes the Source bundle. V2
seals copy all added request bindings. The tasks digest first normalizes
CRLF to LF and only valid T### checkbox progress `[xX]` to `[ ]`. Changed paths
hash the C-sorted output of
`git diff --no-renames --name-only <base> <subject>`.
Final Delta hashes the exact output of
`git diff-tree --raw -z --no-abbrev --no-renames <original> <subject>`.

Acceptance binds current Spec/Plan/attachments/tasks, epoch, Source/IA,
Original Baseline, Final Subject, REV-FINAL seal, Final Review Commit, and raw
Final Delta. Its self-hash is final; its direct local commit changes only
acceptance.md and requires a clean worktree.

## Machine-check boundary

Requirements checks cover the marker, mandatory sections, Delivery Estimate
Schema 1 uniqueness/ranges/bases/exclusions/confidence and legacy warning,
clarification/default formats, residual markers, FR/scenario scoping, approval
structure/date/hash, constraint drift, and warning-only vague wording.

Design includes Requirements and then checks the Requirements hash chain,
Decision Log, the exact Design Evidence Schema 1 field and structured child
fields for all six Design Detailing dimensions, mandatory upstream sections,
Delivery Estimate comparison, legacy-progress compatibility, Implementation
Review Contract, template remnants, and approval snapshot. The
checker validates syntax, reasoned N/A, and code-fence presence; it never claims
to prove architectural sufficiency.

Tasks-structure checks cover exact contract fields, Closure placement/schema,
checkpoint intervals and ref coverage, prior-finding identity/remediation,
checkpoint/test-set equality, checkpoint row uniqueness/order/non-parallel
form, legacy grandfather eligibility, and every canonical reviewer-command/
stop token. Internal retask-eligible mode validates bounded regeneration
preconditions. Task-review checks validate REV-TASKS request, PASS verdict,
seal chain, plan basis, and normalized tasks definition.
Implementation-review checks validate the selected REV-ID (REV-FINAL by
default), bounded rounds, request/verdict/seal chain, subject/upstream hashes,
PASS-only sealing, and current-scope freshness. Its internal
`implementation-candidate` variant permits only the uncommitted candidate seal
and current checkpoint checkmark; final `implementation-review` additionally
requires the accepted seal/checkmark to be clean and tracked.
Source modes validate marker, Plan basis, schema/IDs, dual manifests,
REV-SOURCE and orphan behavior. V2 additionally validates execution/IA blobs,
Task Handoff, preserved reviews, Original Baseline ancestry, Source/IA path
reconciliation and raw final delta. Acceptance validates explicit record,
parent/metadata-only commit, clean tree, every final binding, and reports final
Git delivery metrics without turning estimate variance into failure.

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
| `before_tasks` priority 10 | `check-design` | Approved Design/contract required |
| `before_tasks` priority 20 | `check-source-design` | Conditional approved Source + REV-SOURCE |
| `after_tasks` priority 10 | `refine-tasks` | Bounded native-task closure audit/refinement |
| `after_tasks` priority 20 | `check-tasks` | Native task/checkpoint/Closure structure |
| `after_analyze` | `review-tasks` | Fresh-context REV-TASKS verdict |
| `before_implement` | `check-task-review` | Current REV-TASKS PASS seal |
| `after_implement` priority 10 | `check-implementation-review` | Current REV-FINAL PASS seal |
| `after_implement` priority 20 | `accept-implementation` | Explicit whole-delivery acceptance |

Manual check modes are `spec`, `design`, `source`, `tasks-structure`,
`task-review`, `implementation-review [REV-ID]`, and `acceptance`. Only
spec/design retain interactive default inference; `retask-eligible` is an
internal fail-closed Plan preflight rather than a public approval check. Gated
specify/plan execute peer extensions' same-phase hooks while
excluding `speckit.gatespec.*`, preventing recursion. Unmarked upstream
features remain silent in all GateSpec hooks.

Spec-kit dispatches these hooks through prompts. Missing/invalid extension
wiring and reviewer provenance are outside the portable checker's trust
boundary.
