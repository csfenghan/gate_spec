# GateSpec

GateSpec 0.11.0 is a lightweight [spec-kit](https://github.com/github/spec-kit)
extension with explicit Requirements/Design gates, optional reviewed Source
Design, bounded native-task closure, fresh task/implementation receipts, and
one final whole-delivery user acceptance around the unchanged native execution
path. Requirements bind delivery to one observable Primary outcome through a
versioned Scope Contract and remove prospective code shape before approval;
Design is the first instantiation stage. Requirements and Design disclose
whole-feature delivery-size estimates. Protocol v3 additionally makes any production test
control explicit, isolated, default-OFF, and review-bound. Later reviews prevent
silent scope, estimate, or test-control expansion. It does not fork or modify
upstream commands.

Its operating principles are human-led constraints, low auto-inference,
discussion before execution, bounded review artifacts, and scenario-first
human decisions.

## Two paths, one downstream workflow

| Path | Workflow |
|---|---|
| Upstream auto path | `speckit.specify → speckit.plan → speckit.tasks → speckit.analyze → speckit.implement` |
| GateSpec path | `gatespec.specify → gatespec.plan → [optional gatespec.source-design] → speckit.tasks → bounded task-only refinement → speckit.analyze → speckit.implement → final acceptance` |

The paths converge at native `speckit.tasks`, which remains the only creator of
`tasks.md`. GateSpec adds no task generator or implement replacement; its first
`after_tasks` hook may only audit and refine that native file before the second
hook validates it. A gated spec is identified only by
`<!-- path: gatespec -->` on line 1. Completely unmarked specs make the gate
checker exit successfully with no output, so upstream behavior stays untouched.
A displaced marker is treated as a damaged gated artifact and fails.

## What is approved

Feature content has exactly three human approval mechanisms:

1. an answer to each approval-eligible Requirements/Design decision;
2. one batch approval for proposed non-blocking defaults;
3. final approval of a ≤20-line Requirements or Design summary (or a diff on
   revision), including “what I am least confident about”.

“Done” cannot seal a Draft while blocking items remain. When blocking items and
defaults are complete, the agent writes the Draft automatically. Empty
Clarifications, Defaults, and Decision Log sections use explicit
`None — <reason>` records; blank sections never pass.

Requirements approval records a content SHA-256. Design records both its own
approval hash and the exact approved Requirements content hash. A changed spec
therefore invalidates an old plan, and revision/restart archives stale tasks.
The same normal Requirements summary approval accepts its Scope Contract and
disclosed delivery estimate; neither adds an approval mechanism.

Task and implementation review PASS verdicts are not additional human approval
mechanisms. A reviewer cannot introduce a requirement, design choice, waiver,
or scope change; such a finding returns to the existing Requirements or Design
diff-approval flow.
Source Design reuses decision answers and one final summary/diff approval; its
fresh REV-SOURCE PASS is engineering evidence. Implementation checkpoints do
not ask the user. After REV-FINAL, the user explicitly accepts the complete
delivered implementation once; rejection records nothing and does not infer a
remediation choice.

## Requirements abstraction

New or actively revised Requirements declare exact
`**Requirements Abstraction Schema**: 1`. Their Input is one normalized
`**Input**: Requirements intent: ...` line, never the raw user description.
Specify treats a user-supplied API or architecture sketch as transient: it
extracts capability, observable success/error and terminal-state behavior,
lifecycle, compatibility, and verifiable resource/timing/thread-affinity/
ownership constraints, then discards the prospective code shape. It creates no
sidecar for the discarded sketch.

Across Input, Clarifications, Defaults, Scope Contract, stories, FRs, SCs, and
Assumptions, Requirements does not create names for new or changed APIs,
functions, classes/types/enums, fields, namespaces/packages, internal thread or
queue/task/algorithm/data-structure components, or source paths; nor does it fix
signatures, parameter/return types, or overloads. Existing-system compatibility
anchors and indispensable external standard/wire identifiers remain allowed
when they do not instantiate the new interface. Verifiable semantics such as
asynchronous acceptance, synchronous accepted/rejected distinction, per-request
cancellation, deterministic terminal state, or exactly one internal execution
thread per instance remain valid Requirements.

Every Requirements statement must survive arbitrary prospective-symbol
renaming, permit at least two implementation shapes, and be testable without
inspecting a prospective declaration. Requirements cards compare semantic
consequences only; an explicit user sketch admits only its extracted capability,
not its names or types. Design is the first instantiation stage and fixes
contract-bearing API/type/class/source names, signatures, return types, and
structure. Later semantically equivalent shape changes route to
`gatespec.plan --revise`; a name/local shape explicitly left as bounded
Implementation Freedom may be fixed in Source or IA; capability, behavior,
compatibility, or measurable constraint changes route to
`gatespec.specify --revise`.

The checker rejects raw `User description` Input and high-confidence source
fences/declarations/signatures/concrete type shapes only within those semantic
areas. It emits located warnings for ambiguous identifiers, calls, constants,
component names, and paths so Specify can distinguish an allowed existing or
external anchor from a prospective identifier. Regex cannot prove semantic
abstraction; the prompt audit remains authoritative.

## Outcome-based scope admission

New or actively revised Requirements declare exact
`**Scope Contract Schema**: 1` and one `## Scope Contract`. The contract fixes:

- one Primary outcome with participant, current state, trigger, and observable
  result delivered now;
- Core completion SC refs and the existing behavior or burden deliberately
  retained;
- one table of capabilities admitted as `core`, `committed`, `constraint`, or
  `deferred`, with canonical FR/SC refs and a boundary rationale.

Removing a `core` capability defeats the Primary outcome. A `committed`
capability is an explicit same-delivery user request; `constraint` is reserved
for an effective MUST. Everything else is deferred by default: it is outside
this delivery and is not a future commitment. Pure implementation mechanisms
do not create CAP rows. GateSpec does not proactively enumerate adjacent
features or ask the user to approve AI-discovered improvements one by one.

Every FR and SC maps to a non-deferred CAP, every non-deferred CAP has at least
one FR and SC, and every Core completion SC belongs to a core CAP. CAP IDs stay
out of task Closure; closure remains CAP → FR/SC → task. Plan binds the approved
contract through Requirements Content-SHA256 instead of copying a second scope
table. Design, Source, task, and implementation reviews require all admitted
scope, reject deferred scope and new external behavior, and preserve Retained
baseline. A scope change returns to `gatespec.specify --revise`.

A Scope decision describes the current workflow, one concrete gap, the burden
the minimum sufficient option retains, and any external interface/caller-flow/
compatibility change caused by a broader option. The recommendation is the
smallest delivery that completely achieves the Primary outcome; elegance or
extensibility alone does not justify expansion.

## Delivery estimates

New or actively revised Requirements and Plans declare
`**Delivery Estimate Schema**: 1` and one `## Delivery Estimate`. They record
non-negative `lower..upper` ranges for Production additions, churn (additions +
deletions), and unique production files, plus estimate basis, production path
basis, excluded paths, and confidence. Design re-estimates from inspected
modules, callers, build/config/schema changes, and the complete test surface,
then records whether it is `within`, `expanded`, or `reduced` from
Requirements and why.

Production code means handwritten runtime code, headers, protocol/schema,
configuration, and build/packaging logic. Tests, feature/review metadata, pure
documentation, and reproducibly generated outputs are excluded. A generated
output is excludable only when its output path, source path, and generator are
declared as `generated: output <- source via generator`.

Specify considers independently deliverable capability boundaries only when
the user raised them, the request is reasonably ambiguous, or Design could
otherwise cross the boundary accidentally. A genuine merge-versus-split choice
uses the normal `R<n>` decision mechanism; GateSpec never creates sibling specs automatically.
There is no LOC, file, task, or checkpoint ceiling. Large disclosed estimates
remain approvable.

Source Design, task refinement, and fresh REV-TASKS independently re-estimate.
If any upper bound grows by at least 25% (`new * 100 >= approved * 125`), grows
positive from zero, or introduces a production path family absent from Design,
work returns to `gatespec.plan --revise` for estimate update and diff-only
re-confirmation. A scope-changing split returns to Requirements revision.
Smaller drift proceeds without another approval.

Legacy Approved Requirements without estimates remain valid with a warning;
their next Design supplies the first estimate. A legacy Approved Design must
add an estimate before tasks unless checked work, implementation reviews, or a
product delta proves implementation is already underway; progressed legacy
delivery remains valid and warning-only.

Legacy Approved Requirements without Scope Contract block before Design and
require `gatespec.specify --revise` when no implementation progress exists. A
checked task, implementation-review receipt, or real production delta preserves
the legacy artifact as warning-only and byte-for-byte read-only.

Legacy Approved Requirements without Requirements Abstraction Schema 1 follow
the same progress boundary: before implementation they must return through
`gatespec.specify --revise`; checked work, an implementation review, real
production delta, or an already Accepted delivery keeps them immutable with a
warning. Draft, duplicate, and unknown abstraction schemas fail closed.

## Scenario-first decision triage

Specify first classifies Requirements unknowns as a blocking human decision, a
batch-approved routine default, or a technical matter deferred to Design. Plan
classifies design forks as a human decision, a reasoned engineering
determination, or bounded Implementation Freedom. Individual approval is used
only when at least two compliant options remain and a reasonable affected
human could prefer either because their observable consequences differ.
Forbidden or dominated alternatives cannot be used as foils.

Engineering determinations are not hidden: they are recorded with rationale in
Design Detailing/research and covered by final Design approval. They do not get
`D<n>` IDs or individual approval fields. Technical choices that are safe to
defer stay in Implementation Freedoms with explicit bounds. A user can request
an explanation or promote either classification into full discussion before
final approval.

Human decisions retain a transient dependency graph and stable IDs. In
conversation, each card uses a plain question, one short domain-native
engineering scenario, direct A/B/C option bullets, and a natural recommendation.
It preserves relevant API, thread, lifecycle, protocol, state, and error terms
instead of replacing them with consumer analogies. It does not expose
`Scenario`, `Fixed boundary`, `Why this needs you`, `Options`, `Recommendation`,
or `Technical basis` as questionnaire fields, and it does not invent UI actions
for a non-UI feature. Boundaries and evidence are integrated where they affect
the choice or expanded through `explain R<n>` / `explain D<n>`. A reader must
still understand the choice without opening references.

The conversational form is distinct from artifact evidence. Accepted
Requirements choices remain compact Clarification Q/A entries; accepted Design
choices are normalized into the existing structured Decision Log fields. This
keeps approved artifacts and old Drafts compatible while making the approval
conversation easier to follow.

Each round contains at most four simple, pairwise-independent cards under a
four-unit cognitive budget. A complex or high-risk card consumes the full
budget and is presented alone. Progress is one compact line with current IDs
and topics; unchanged hashes, successful or absent hooks, resume recaps, and
raw dependency telemetry stay out unless they require action or affect the
choice. Other buckets are summarized only on first inventory or material
reclassification. Dependent decisions remain serial and cycles become one
coherent bundled decision.

Requirements IDs are stored inside the existing Clarification form as
`- Q: [R<n>] ... → A: ...`; Design keeps `D<n>` blocks only for individually
approved choices. Legacy approved entries remain valid and are never rewritten.

“Accept all recommendations in this batch” covers only non-high-risk decision
cards in the current batch. High-risk cards require an explicit ID/choice, and
the separately presented defaults table still requires “approve defaults”.
Partial answers are retained; unanswered IDs lead the next batch, which may be
refilled with newly eligible independent decisions. Users can temporarily ask
to split a card, ask one next round, or cap the next round at 1–4 cards without
creating a stored mode. They may also ask to explain or discuss an engineering
determination or Implementation Freedom; this likewise creates no stored mode
or fourth approval mechanism.

## Review-ready design evidence

Every current plan declares `**Design Evidence Schema**: 1`. The existing six
Design Detailing dimensions use structured fields that preserve enough source
information for a later documentation tool to render an architecture review:
current repository anchors and current-to-target component changes, dependency
directions, core type/API skeletons and success/failure interactions, thread
and resource-ownership contracts, external behavior, lifecycle, and exact
technical basis.

This is also the prospective-code instantiation boundary. The modules/classes
and internal-API dimensions fix complete contract-bearing names, source paths,
signatures, parameter/return types, overloads, and class/type structure. Only
explicitly bounded non-contract internal shapes remain Implementation Freedom.

This is evidence capture, not architecture-document generation. Plan does not
create `architecture.md`, require Mermaid, or prescribe per-file edits and
production-ready method bodies. Directional text and ordered interactions are
sufficient; a diagram or Unicode view is optional. A populated dimension uses
its fixed child fields, while a genuinely irrelevant dimension uses one
reasoned N/A. The portable checker validates that structure; the plan
walkthrough and fresh reviewer remain responsible for semantic sufficiency.

## Protocol v3 test controls

Every new or revised Plan uses Review Protocol v3. Requirements owns the sole
policy-deviation channel: the mandatory nested `Test Control Policy Exceptions`
section. Its default is Mode `none` with one five-cell all-`none` row. Mode
`approved` uses continuous `TCE-001...` rows, names exactly one of
`source-root`, `language-marker`, `formal-api`, `switch-identifier`,
`control-model`, `touchpoint-shape`, or `validator-path-marker`, and binds
exactly one concluded Requirements `R<n>` per row to a replacement
source-auditable mechanism and its consequence; bundled rows may share one
`R<n>`. A TCE cannot pre-register a
control or weaken the structural/lifecycle floor. Plan copies the approved body
exactly; a legacy Approved Requirements artifact without it means Mode `none`.

A v3 delivery declares one
Test Control mode in the mandatory `GateSpec Test Control Closure` section of
`tasks.md`:

- `none` means production needs no test-only seam. The table is the exact
  all-`none` row and no build switch, validator, or test-control source may be
  introduced.
- `isolated` registers every exceptional control as `TC-###` and traces its
  verification gap, test-only surface, production touchpoint, allowed effect
  and lifetime, build switch/validator, consumer tasks/tests, and the task that
  proves the ordinary build remains clean.

Absent a matching `source-root` or `language-marker` TCE, an isolated control
is under a production tree ending in `src/testonly`; its namespace/module ends
in `testonly`, or a language without namespaces uses a leading `TestOnly` or
`test_only` name. Absent a `control-model` or `formal-api` TCE, the surface is a
typed per-instance RAII capability and adds no test-shaped product API. Any
replacement must remain source-auditable. Process-wide runtime toggles and
environment/config/API activation remain forbidden regardless of TCE.

Absent a `touchpoint-shape` TCE, an affected production function has at most
one visually contiguous dedicated hook guard. That guard makes one `testonly`
call and rejoins the ordinary result/error path; counting, waiting, fault
choice, and observation stay on the registered test-only surface.

Hook-enabled projects use one dedicated positive switch, canonically named
`*_ENABLE_TEST_HOOKS` unless a `switch-identifier` TCE supplies the replacement;
its default is always OFF. A tracked validator uses a test-only path/basename
unless a `validator-path-marker` TCE supplies its auditable replacement. The
validator accepts exactly
`bash <validator> --gatespec-lane default-off|explicit-on`. The default lane configures the
ordinary build without passing an explicit OFF override, rejects a default-ON
or nonzero hook definition anywhere in the built subject, and proves test-only
symbols are absent. The explicit lane enables the dedicated switch and runs the
registered consumer tests. A validator that merely echoes success is not
evidence. Protocol v3 guarantees the switch-omitted build only; an operator who
explicitly opts in accepts that test-enabled build. GateSpec does not require
packaging to reject that opt-in or require an external release/signing system.
Each lane re-enumerates and hashes its actual configure/build/test and, when
present, install/export/symbol outputs from the exact Subject clone. Literal or
precomputed hashes are not evidence; the fresh reviewer checks their derivation.

REV-TASKS and every implementation verdict include `## Test Control Audit`.
The audit also reports Test Control additions, churn, files, and production
touchpoints (ranges at task review, exact integers for implementation).
Production and Test-Control scale are separate reports, not disjoint buckets:
a changed production touchpoint or build-wiring file remains Production, while
its dedicated hook-attributable lines may also count toward Test-Control
scale. Only default-OFF-proven surface-only objects, validators, and ordinary
tests are excluded from Production. REV-FINAL performs a local preflight and
then a fresh rerun of both validator lanes against the exact Subject commit.
The two canonical evidence files are
`round-NN-default-off-evidence.md` and
`round-NN-explicit-on-evidence.md`. Requests, seals, and acceptance bind the
mode, Closure hash, Subject manifest, and both evidence hashes. Source or
control-wiring drift after the sealed subject therefore invalidates final
acceptance even when receipt Markdown is unchanged.

Protocol v1/v2 artifacts are retained only as already accepted historical
deliveries. Any active or unaccepted v1/v2 Plan blocks with
`gatespec.plan --revise`; `--retask` cannot perform the protocol upgrade.

## Optional Source Design

After Design approval, the user may go directly to native tasks or enable
`contracts/source-design.md`. Its existence alone enables the sub-contract;
line 1 is `<!-- gatespec: source-design -->`, and optional shards are direct
regular `.md` files under `contracts/source-design/`. First enable is allowed
only before product implementation. Existing tasks/REV-TASKS may be archived and regenerated when
no code work began; implementation progress, product diff, IA, or implementation
receipt blocks retrospective enablement.

Source Design records a maintainer scenario, before/after and success/failure
flows, complete SD-F file operations, SD-U declarations, SD-FLOW lifecycle/data
paths, SD-ALG algorithms/invariants/complexity, SD-FAIL recovery/observability,
SD-TEST Requirement-to-file/symbol/test traceability, cross-cutting design,
bounded freedoms, and prohibited material boundaries. Fresh REV-SOURCE binds a
reviewed manifest hash that excludes only entry Status/Gate Approval. User
approval then binds a content manifest hash that includes approved entry
content; both include raw shard hashes, so approval-only edits preserve review
while body/shard drift invalidates it.

Source-enabled tasks record the content hash and map every non-checkpoint task
to SD-* refs and precise paths. Bounded private/internal changes are logged as
IA<n> in the reviewed Subject commit. External behavior, compatibility,
security/performance promises, responsibilities/dependencies, cross-module API,
state/concurrency/error semantics, schema, and key invariants are material;
they block normal implement and require the archived compensating-commit/source
revision/revalidation flow.

## Task and implementation review

The approved plan contains one exact `Implementation Review Contract`. New and
revised Plans use Protocol v3. It lists
`REV-FOUNDATION`, one `REV-US<n>` for each implemented user-story phase, and
`REV-FINAL`, maps every checkpoint to exact tests, requires local checkpoint
commits without pushing, and permits at most two remediation rounds.

Native tasks end each corresponding phase with a non-parallel row containing
`GateSpec review checkpoint <REV-ID>:`,
`speckit.gatespec.review-implementation`, `--scope <REV-ID>`, the matching
`.gatespec/reviews/<REV-ID>/seal.md`, and `before continuing`. The priority-10
`after_tasks` hook performs one exhaustive task-local closure pass, then the
priority-20 hook checks the result. Only `tasks.md` may change: approved
Requirements, Design, Source, receipts, Git state, and product files remain
read-only. A human-choice or upstream artifact gap blocks and routes to that
artifact's revision flow.

The refined file's final three H2 sections before its first phase are exact
Checkpoint Closure, Prior Review Closure, and Test Control Closure sections.
The first partitions every
non-checkpoint task into its strict checkpoint interval, requires verification
at every checkpoint, and covers every FR/SC/approved D plus Source IDs when
enabled. The second navigates every basis-matching current or `*-retask` archived
REV-TASKS `BLOCKER` item by raw-item SHA-256 to concrete remediation tasks.
The two legacy Closure matrices are grandfathered only when both are absent and
a complete, current, tracked, clean legacy PASS seal exists; partial or
malformed Closure never is. Protocol v3 always requires Test Control Closure.
These matrices are trace/navigation evidence; the fresh reviewer still judges
whether tasks semantically close the approved contract and prior findings.

Native analyze still runs after the refined tasks. A separate `REV-TASKS` PASS
seal is required before native implement begins; REV-FINAL is required before
its completion report.

Review data is stored under
`<feature>/.gatespec/reviews/<REV-ID>/`. Round zero uses
`round-00-request.md` and `round-00-verdict.md`; remediation may create only
rounds 01 and 02. Earlier rounds are BLOCKED and only the final PASS round may
produce `seal.md`. Requests bind the review subject; verdicts bind the matching
request; seals bind the PASS verdict.

The author/remediator context may prepare a request but may never write its
verdict. Review must use a fresh context. When the active Claude or Codex
integration cannot start one, GateSpec stops and instructs the user to invoke
the reviewer from a new session. That manual session returns verdict text only;
the original coordinator validates/persists it and creates a PASS seal. Falling
back to same-context review is forbidden. This is a procedural isolation
contract, not cryptographic reviewer identity attestation.

The local commit that writes the current REV-TASKS seal is the fixed
implementation baseline (the seal path's latest-touch commit, with an identical
blob). REV-FOUNDATION reviews baseline-to-foundation, each REV-US<n> reviews the
preceding stage subject-to-current subject, and legacy v1 REV-FINAL returns to
that baseline. No review command pushes.

Protocol v3 retains the v2 execution epoch, unchanged Original Baseline,
Task-Handoff commit, Source/IA snapshots, preserved Source-revision reviews,
and raw NUL-delimited Final Delta. It also binds Test Control mode, Closure,
Subject manifest, and both REV-FINAL validator-lane evidence snapshots.
REV-FINAL uses Original Baseline rather than only the task handoff. The raw
delta changes for content/mode changes even when the old name-only path hash is
unchanged.

An implementation PASS first validates an uncommitted candidate seal plus the
temporary checkpoint checkmark. Only then are receipt/checkmark metadata
committed locally and rechecked as clean, tracked final state; normal execution
continues automatically only after both checks pass. REV-FINAL is followed by
a ≤20-line delivery summary and explicit acceptance recorded in
`.gatespec/acceptance.md`; its local commit may change only that metadata file.
The summary computes actual Production additions, churn, and unique files from
the bound Original-Baseline-to-REV-FINAL-Subject Git diff and shows them beside
Design's ranges and confidence. Numeric variance is disclosed but does not
itself reject delivery; scope and contract violations remain REV-FINAL blocks.

If REV-TASKS reaches valid BLOCKED round 02, or a valid PASS handoff has not
begun implementation, `gatespec.plan --retask` may regenerate tasks without
reopening approved Design. It first requires the deterministic
`retask-eligible` check: attached branch, tracked/current approved artifacts,
no checked task, implementation receipt, nonempty IA, acceptance, product
delta in the complete first-Plan/v3-Original history, or worktree change
outside the exact retask archive set. It audits historical task/IA blobs,
binds the v3 handoff tree and epoch/Original continuity, and validates every
older retask archive's exact tracked tree and historical handoff before
reporting success. One UTC
timestamp names `.gatespec/archive/<YYYYMMDDTHHMMSSZ>-retask/`. Every staged
archive source must have an index blob identical to its working bytes;
ambiguous `MM`/`AM`, hidden index drift, an index flag on an archive source,
or an ancestor symlink blocks. Any
exact-target conflict blocks with no overwrite or retry. The archive and the
regenerated v3 handoff are separate local commits and are never pushed. Retask
never upgrades a v1/v2 Plan. V3 increments the epoch, keeps Original Baseline,
resets Task Handoff to pending, binds current Source, derives preserved reviews,
and starts with canonical empty IA.

## Constraints

Both gated phases load and explicitly merge:

1. project constitution (`.specify/memory/constitution.md`),
2. project GateSpec constraints (`.gatespec/constraints.md`),
3. user GateSpec constraints (`~/.gatespec/constraints.md`).

Higher entries win. The spec's `Constraint Basis` records source hashes,
effective rules, conflicts, and resolutions. Constitution `MUST` conflicts
cannot be approved inside a feature; `SHOULD` deviations require a reason.
Project/user GateSpec rules can be exempted only by an explicit decision.

The `Constraint Basis` heading and its five field labels remain fixed English
protocol tokens. Human-readable values use Simplified Chinese unless a
higher-priority effective constraint requires another language; paths, hashes,
and technical identifiers remain verbatim, and any override is recorded as a
conflict resolution.

The approved Requirements snapshot freezes its basis. A changed user file is a
warning until `--refresh-constraints`; a changed constitution or project
policy forces Requirements re-approval. GateSpec never silently copies user
constraints into the constitution.

## Safe resume controls

- default: continue a Draft in place; keep a valid approved artifact read-only;
- an old Approved Requirements artifact without Scope Contract must be revised
  before Design unless implementation progress makes it warning-only/read-only;
- an old Approved Requirements artifact without Requirements Abstraction Schema
  1 follows the same revision/progress split; Accepted history remains read-only;
- an old Approved-Design plan without Implementation Review Contract or Design
  Evidence Schema 1 is archived downstream, reopened as Draft, enriched, and
  diff re-approved before tasks;
- an old Approved-Design without Delivery Estimate follows the same revision
  path before tasks unless implementation progress already exists, in which
  case it remains valid with warnings and final actual metrics;
- `--revise`: reopen as Draft, archive Source/tasks, reviews/revalidations,
  execution state, IA, and acceptance, and
  use diff re-approval;
- `--restart`: archive current phase/downstream artifacts, then rebuild from
  the GateSpec template;
- `--retask` (plan): only after deterministic eligibility, archive current
  tasks/REV-TASKS (plus v3 state/IA), then run native tasks and the normal
  refine → check → analyze → fresh REV-TASKS sequence;
- `--refresh-constraints` (specify): recompute the frozen basis and enter the
  revision flow.

Design always covers six core dimensions (concurrency, lifetime/ownership,
modules/classes, internal APIs, external behavior, lifecycle) using structured
current facts, target contracts, and traceable technical basis. Constraints may
add dimensions but cannot remove or replace them. Before Design summary the
agent performs an internal review-source completeness and
spec/design-attachment consistency check. Native `speckit.analyze` runs after
tasks.md exists.

## Install

Supported shells are Linux and macOS Bash. On Windows, use WSL or Git Bash.

```bash
# Global Claude + Codex skills and user constraints
./install.sh

# Also register the extension and fixed hooks in an initialized project
./install.sh /path/to/spec-kit-project

# Options
./install.sh --agent claude|codex|all [--force] [project-dir]
```

Arguments are validated before writes. Skills are rendered atomically with
agent-specific command references and absolute paths back to this repository.
The installer also installs the GateSpec reviewer adapter as
`~/.claude/agents/gatespec-reviewer.md` and
`~/.codex/agents/gatespec-reviewer.toml`; conflicting local adapters require
explicit `--force` and receive a timestamped backup.
Start a new Claude Code or Codex session after installing or updating an agent
definition; an already-running session does not reload it.
Keep the repository in place. Global skills are available everywhere, but the
complete plan/tasks workflow requires a project initialized by spec-kit.

`--force` replaces a locally changed `~/.gatespec/constraints.md` only after
keeping a timestamped backup. Without it, the installed personal copy is left
untouched.

Skill-mode invocation is `/speckit-gatespec-specify` for Claude and
`$speckit-gatespec-specify` for Codex. Command-mode aliases such as
`/gatespec.specify` remain available where upstream renders aliases.

## Machine gates and hooks

The public manual entry accepts `spec`, `design`, `source`, `tasks-structure`,
`task-review`, `implementation-review [REV-ID]`, and `acceptance`.
Hooks never infer mode:

- `before_plan` → `speckit.gatespec.check-requirements`;
- `before_tasks` priority 10 → `speckit.gatespec.check-design`;
- `before_tasks` priority 20 → conditional `speckit.gatespec.check-source-design`;
- `after_tasks` priority 10 → `speckit.gatespec.refine-tasks` (bounded
  `tasks.md`-only audit/refinement);
- `after_tasks` priority 20 → `speckit.gatespec.check-tasks`;
- `after_analyze` → `speckit.gatespec.review-tasks`;
- `before_implement` → `speckit.gatespec.check-task-review`;
- `after_implement` priority 10 → `speckit.gatespec.check-implementation-review`
  (fixed to REV-FINAL);
- `after_implement` priority 20 → `speckit.gatespec.accept-implementation`.

The portable checker validates Requirements Abstraction Schema/Input plus
high-confidence semantic-area shapes and located ambiguity warnings, Scope
Contract schema/fields/CAP IDs/admissions,
canonical FR/SC coverage and core closure, estimate schemas/ranges, structure,
Closure/finding identity, hash chains, freshness, retask eligibility, PASS
seals, legacy compatibility, and final Git metrics. Semantic estimate rechecks,
scope necessity, review quality, and fresh-context behavior remain prompt and
operator contracts. Missing or invalid receipts fail; they are never
manufactured by a checker.

Native implement exposes no per-task hook, so REV-FOUNDATION/REV-US stage stops
are a cooperative prompt/task contract. With hooks registered, the fixed
before/after boundaries and final receipt checker block entry/completion
reports, but cannot roll back written code or prevent deliberate hook bypass.

Gated specify/plan also run other extensions' same-phase before/after hooks,
skipping GateSpec's own entries to avoid recursion.

## Development

```bash
bash tests/run-all.sh
```

This runs Bash syntax checks, ShellCheck, Scope/estimate/legacy/Closure/retask and
Source/v3/test-control/acceptance checker fixtures, final Git-metric fixtures, Claude/Codex
renderer checks, manifest checks, and an extension-install smoke test when the
`specify` CLI is available. Ubuntu and macOS CI run the same suite and assert
that it leaves the worktree clean.

Static tests cannot prove model batching behavior. Before publishing a release
that changes Specify/Plan interaction, run the Claude and Codex behavioral
cases in steps 6–7 and the Scope calibration in step 20 of the upstream
compatibility ritual; both platforms must pass.

See [the full gate protocol](docs/gate-protocol.md) and
[the upstream compatibility ritual](docs/upstream-sync.md).

## License

MIT
