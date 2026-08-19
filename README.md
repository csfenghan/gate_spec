# GateSpec

GateSpec 0.5.0 is a lightweight [spec-kit](https://github.com/github/spec-kit)
extension that puts explicit human approval gates on requirements and design,
then requires task and implementation review receipts around the unchanged
native execution path. It does not fork or modify upstream commands.

Its operating principles are human-led constraints, low auto-inference,
discussion before execution, bounded review artifacts, and scenario-first
human decisions.

## Two paths, one downstream workflow

| Path | Workflow |
|---|---|
| Upstream auto path | `speckit.specify → speckit.plan → speckit.tasks → speckit.analyze → speckit.implement` |
| GateSpec path | `gatespec.specify → gatespec.plan → speckit.tasks → speckit.analyze → speckit.implement` plus fixed review hooks |

The paths converge at native `speckit.tasks`; GateSpec adds no task generator
or implement replacement. A gated spec is identified only by
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

Task and implementation review PASS verdicts are not additional human approval
mechanisms. A reviewer cannot introduce a requirement, design choice, waiver,
or scope change; such a finding returns to the existing Requirements or Design
diff-approval flow.

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

Human decisions retain a transient dependency graph and stable IDs. Each card
starts with one shared actor/trigger/outcome or failure scenario, states what is
already fixed and why human input matters, compares every option in that same
scenario, and puts FRs, constraints, paths, and flow evidence last. A reader
must be able to understand the choice without opening those references.

Each round contains at most four simple, pairwise-independent cards under a
four-unit cognitive budget. A complex or high-risk card consumes the full
budget and is presented alone. Progress counts only approval-eligible human
decisions; a separate compact digest reports other buckets without turning
them into a decision backlog. Dependent decisions remain serial and cycles
become one coherent bundled decision.

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

This is evidence capture, not architecture-document generation. Plan does not
create `architecture.md`, require Mermaid, or prescribe per-file edits and
production-ready method bodies. Directional text and ordered interactions are
sufficient; a diagram or Unicode view is optional. A populated dimension uses
its fixed child fields, while a genuinely irrelevant dimension uses one
reasoned N/A. The portable checker validates that structure; the plan
walkthrough and fresh reviewer remain responsible for semantic sufficiency.

## Task and implementation review

The approved plan contains one exact `Implementation Review Contract`. It lists
`REV-FOUNDATION`, one `REV-US<n>` for each implemented user-story phase, and
`REV-FINAL`, maps every checkpoint to exact tests, requires local checkpoint
commits without pushing, and permits at most two remediation rounds.

Native tasks end each corresponding phase with a non-parallel row containing
`GateSpec review checkpoint <REV-ID>:`,
`speckit.gatespec.review-implementation`, `--scope <REV-ID>`, the matching
`.gatespec/reviews/<REV-ID>/seal.md`, and `before continuing`. Native analyze
still runs immediately after tasks. A separate `REV-TASKS` PASS seal is
required before native implement begins; REV-FINAL is required before its
completion report.

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
preceding stage subject-to-current subject, and REV-FINAL returns to the
baseline so it independently covers the complete feature diff. No review
command pushes.

An implementation PASS first validates an uncommitted candidate seal plus the
temporary checkpoint checkmark. Only then are receipt/checkmark metadata
committed locally and rechecked as clean, tracked final state; normal execution
continues only after both checks pass.

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
- an old Approved-Design plan without Implementation Review Contract or Design
  Evidence Schema 1 is archived downstream, reopened as Draft, enriched, and
  diff re-approved before tasks;
- `--revise`: reopen as Draft, archive tasks and current review receipts, and
  use diff re-approval;
- `--restart`: archive current phase/downstream artifacts, then rebuild from
  the GateSpec template;
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

The public manual entry accepts `spec`, `design`, `tasks-structure`,
`task-review`, and `implementation-review [REV-ID]`.
Hooks never infer mode:

- `before_plan` → `speckit.gatespec.check-requirements`;
- `before_tasks` → `speckit.gatespec.check-design`;
- `after_tasks` → `speckit.gatespec.check-tasks`;
- `after_analyze` → `speckit.gatespec.review-tasks`;
- `before_implement` → `speckit.gatespec.check-task-review`;
- `after_implement` → `speckit.gatespec.check-implementation-review`
  (fixed to REV-FINAL).

The portable checker validates structure, hash chains, freshness, and PASS
seals. Semantic review quality and fresh-context behavior remain prompt and
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

This runs Bash syntax checks, ShellCheck, deterministic checker fixtures,
Claude/Codex renderer checks, manifest checks, and an extension-install smoke
test when the `specify` CLI is available. Ubuntu and macOS CI run the same
suite and assert that it leaves the worktree clean.

Static tests cannot prove model batching behavior. Before publishing a release
that changes Specify/Plan interaction, run the Claude and Codex behavioral
cases in steps 6–7 of the upstream compatibility ritual; both must pass.

See [the full gate protocol](docs/gate-protocol.md) and
[the upstream compatibility ritual](docs/upstream-sync.md).

## License

MIT
