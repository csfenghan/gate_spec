# GateSpec — Agent Handoff Guide

GateSpec 0.8.0 is a personal spec-kit extension with human approval gates for
Requirements and Design, optional reviewed Source Design, independent-context
task/implementation reviews, bounded checked task closure, and one final
whole-delivery acceptance. Requirements/Design disclose aggregate delivery
size and later reviews catch material estimate drift. Read this file before
changing the repository.

## Product invariants

1. **Human-led constraints**: agents propose and humans approve; no key feature
   decision takes effect implicitly. Only choices with at least two viable
   options and materially different human consequences require individual
   approval; reasoned engineering determinations remain visible in Design.
2. **Low auto-inference**: Requirements unknowns become a blocking human
   question, proposed default, or technical matter deferred to Design. Design
   forks become a human decision, engineering determination, or bounded
   Implementation Freedom. Every classification has a cheap user veto.
3. **Discuss before execute**: Requirements blocks plan; Design blocks tasks;
   enabled Source Design blocks tasks until fresh REV-SOURCE and user approval.
4. **Bounded presentation**: a round contains at most four total cards—simple
   pairwise-independent decisions plus at most one independent defaults card;
   complex or high-risk decisions are presented alone. Progress counts only
   human decisions. Final summaries stay ≤20 lines, include “what I am least
   confident about”, and revisions use diff-only re-approval.
5. **Scenario-first design**: every human decision starts with one shared,
   self-contained engineering scenario and compares observable consequences in
   that scenario. Conversation uses domain-native prose, preserves relevant
   technical vocabulary, and presents direct option bullets plus a natural
   recommendation rather than schema-like labels; it never invents UI actions
   for a non-UI feature. Supporting constraints and evidence are integrated
   only where material or expanded on request. The Design artifact retains its
   structured evidence fields.
6. **Scale disclosure, not budgeting**: Requirements and Design show aggregate
   Production additions, churn, and file ranges plus basis/exclusions/
   confidence. There is no LOC/file/checkpoint cap. Existing summary approval
   accepts the disclosed size; Source/tasks/REV-TASKS return to Design revision
   at ≥25% upper-bound growth or a new production path family.

Feature content has exactly three approval mechanisms: a decision answer, the
defaults batch, and final summary/diff approval. “Proceed” cannot seal unresolved
blocking work; a complete clarification set writes a Draft automatically.
Reviewer PASS/BLOCKED verdicts are engineering evidence, never a fourth human
approval mechanism.
Normal implementation checkpoints are automatic. After REV-FINAL, the user
accepts the complete delivery once; Source boundary violations are exceptional
blocks, not routine implementation approvals.
Native tasks is the only task-file creator. The first after_tasks hook may
perform one bounded tasks.md-only closure refinement; the second validates it.

## Architecture invariants

- Upstream `speckit.*` is never modified. Both paths converge at the unchanged
  `speckit.tasks → speckit.analyze → speckit.implement` sequence.
- Native tasks remains the only creator. `after_tasks` priority 10 may modify
  only that `tasks.md` to close the fixed audit; priority 20 validates exact
  Closure matrices. It never edits approved artifacts, receipts, Git, or code.
- `contracts/source-design.md` alone enables the optional Source sub-contract;
  its line 1 is exactly `<!-- gatespec: source-design -->`. Shards are direct
  regular `.md` files under `contracts/source-design/` and never enable Source
  by themselves.
- Line 1 of gated spec.md is exactly `<!-- path: gatespec -->`. No marker means
  a true zero-output pass; a marker on any later line is corruption and fails.
- Keep upstream mandatory sections: spec User Scenarios & Testing,
  Requirements, Success Criteria; plan Technical Context, Constitution Check,
  Project Structure.
- `## Gate Approval` is unique/final and contains only approval date and scoped
  Content-SHA256. Status and approval dates agree.
- plan.md records the approved Requirements content hash. A re-approved spec
  invalidates an old plan and its tasks.
- New or revised spec/plan use Delivery Estimate Schema 1. Production includes
  handwritten runtime/header/schema/config/build/packaging code and excludes
  tests, spec/review metadata, pure docs, and only source-declared reproducible
  generated outputs. Legacy Requirements warn; legacy Design blocks before
  tasks unless implementation progress already exists.
- REV-SOURCE binds the reviewed manifest hash that excludes entry Status/Gate
  Approval; downstream binds the approved content manifest hash. Both include
  raw shard hashes. Design Attachments always exclude the Source bundle.
- Enforcement remains prompt rules plus one thin portable Bash checker. Do not
  introduce orchestration/state machines.
- GateSpec review tasks are cooperative checkpoints inside native implement;
  only registered boundary hooks and receipt checks are deterministic gates.
  Never claim that Markdown, a hook, or a self-hashed receipt proves reviewer
  identity or fresh-context provenance.
- A reviewer receives a self-contained request in a fresh Codex/Claude context.
  Same-context fallback is forbidden; unavailable isolation blocks and requires
  a new top-level session. Reviewers do not author product changes.
- Implementation checkpoints use local commits and isolated review checkouts
  (a Claude worktree or Codex temporary clone). GateSpec never pushes or
  performs any other remote VCS write.
- Protocol v1 remains valid only for a legacy Plan without Source. New Plans
  use v2, binding execution epoch, Source/IA, Task Handoff, preserved reviews,
  and raw Final Delta. Original Baseline never changes across Source revision.
- IA is limited to bounded internal adjustments and belongs in each Subject;
  material or uncertain Source departure blocks. Final acceptance is a
  metadata-only local commit after REV-FINAL and never substitutes for CI.
- Final acceptance reports actual additions, churn, and unique production files
  from the bound Original-Baseline-to-Final-Subject Git diff beside Design's
  estimate. Numeric variance alone never rejects a conforming delivery.
- Closure partitions every non-checkpoint task by strict checkpoint interval,
  covers all approved artifact IDs, and hashes every basis-matching current or
  `*-retask` archived REV-TASKS blocker. Missing both sections is grandfathered
  only by a current tracked clean legacy PASS; partial/malformed never is.
  The matrices are navigation evidence; fresh review still judges semantics.
- The repository is the source of truth. Edit `commands/`, never rendered
  global skills.

## Constraint and rerun invariants

Constraint priority is constitution > `<repo>/.gatespec/constraints.md` >
`~/.gatespec/constraints.md`. spec.md Constraint Basis records source hashes,
effective rules, and conflicts. Constitution MUST conflicts are not approvable;
SHOULD deviations need reasons; GateSpec constraints need explicit exemptions.
Never merge personal constraints into the constitution automatically.

Approved Requirements freezes its basis. User constraint drift warns until
`--refresh-constraints`; constitution/project-policy drift forces re-approval.
Drafts resume in place, approved artifacts are read-only, `--revise` uses diff
re-approval, and `--restart` archives before rebuilding. Revision/restart must
archive tasks and review receipts rather than leave stale execution work.
`plan --retask` is narrower: only valid round-02 BLOCKED or not-yet-implemented
PASS is eligible. It creates separate local archive/handoff commits, never
pushes, preserves blocker lineage, and for v2 increments epoch while keeping
Original Baseline and resetting Task Handoff/current Source/empty IA.
Allowed archive dirt must have identical index and working bytes; `MM`/`AM`
snapshot ambiguity blocks rather than choosing one copy implicitly.

The six Design Detailing dimensions are exact mandatory core fields and record
reasoned engineering determinations where applicable. Constraints may add
fields, never replace them. Plan performs its own attachment consistency and
decision-classification walkthrough before summary; upstream analyze runs only
after tasks.

## Repository map

| Path | Responsibility |
|---|---|
| `extension.yml` | 0.8.0 manifest, 6 hook events / 9 ordered entries |
| `commands/speckit.gatespec.*.md` | public protocols and fixed hook entries |
| `templates/` | spec/plan, Source Design, IA, and task Closure templates |
| `reviewers/` | Codex/Claude custom reviewer source definitions |
| `scripts/bash/check-gate.sh` | deterministic machine gate |
| `install.sh` | atomic global renderer + optional project registration |
| `tests/run-tests.sh` | checker fixtures |
| `tests/run-source-design-tests.sh` | Source/v2/IA/final acceptance fixtures |
| `tests/test-installer.sh` | renderer/manifest/install smoke |
| `tests/run-all.sh` | syntax, ShellCheck, and all tests |
| `docs/` | full protocol and upstream sync ritual |

`.extensionignore` must exclude VCS state, local agent directories, tests/CI,
and development handoff files. Supported platforms are Linux/macOS Bash;
Windows uses WSL/Git Bash.

## Upstream constraints (verified with spec-kit 0.16.1.dev0)

- Primary extension command names are `speckit.{extension-id}.{command}`.
- Aliases render only in commands mode. Skill invocations are
  `/speckit-gatespec-*` (Claude) and `$speckit-gatespec-*` (Codex).
- `before_plan` and `before_tasks` retain the Requirements/Design gates.
  Source adds the second `before_tasks` entry; bounded refine then check are the
  two ordered `after_tasks` entries; final acceptance adds the second
  `after_implement` entry. Manual check accepts `spec`, `design`, `source`,
  `tasks-structure`, `task-review`, `implementation-review [REV-ID]`, or
  `acceptance`.
- Core hooks fire on core commands. Gated commands run their inline gate plus
  peer same-phase before/after hooks and skip every `speckit.gatespec.*` hook.
- Core hooks ask the current agent/session to invoke a command; independent
  review therefore comes from the installed platform adapter, not the hook.
- Manifest compatibility is `>=0.16.0,<0.17.0`; do not widen without the
  upstream sync ritual.

## Iterating

1. Edit repository sources and add a positive or counterexample fixture for
   each deterministic rule.
2. Run `bash tests/run-all.sh`; the tree must remain unchanged by tests.
3. Re-render with `./install.sh` only when an installed copy is needed for a
   manual smoke. Use `--force` only with intent; it backs up local constraints.
4. After spec-kit upgrades, follow `docs/upstream-sync.md` on Linux and macOS.
