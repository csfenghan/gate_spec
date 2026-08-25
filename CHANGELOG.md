# Changelog

## 0.8.0 (2026-08-25)

- Added Delivery Estimate Schema 1 to new/revised Requirements and Design with
  aggregate Production additions, churn, and file ranges, explicit path/
  exclusion basis, generated-output provenance, and confidence.
- Added pre-clarification capability split decisions, Design re-estimation and
  Requirements comparison, and existing-summary approval of disclosed scale
  without LOC/file/checkpoint limits or another approval mechanism.
- Added Source/task/REV-TASKS estimate drift review: ≥25% upper-bound growth or
  a new production path family returns through Plan diff revision; a
  scope-changing split returns to Requirements.
- Added legacy Requirements warnings, pre-task migration for unstarted legacy
  Design, warning-only compatibility after implementation progress, and final
  Git additions/churn/file metrics beside Design estimates.
- Expanded checker, renderer, reviewer, compatibility, generated-file, large-
  estimate, threshold, legacy, and final-metric fixtures while preserving six
  hook events, nine hook entries, Review Protocol v1/v2, and native execution.

## 0.7.0 (2026-08-24)

- Added a bounded `after_tasks` refinement pass that may edit only native
  `tasks.md`, followed by deterministic validation of exact Checkpoint Closure
  and Prior Review Closure matrices.
- Made task review exhaustive across fixed closure categories and preserved
  every basis-matching current or `*-retask` archived BLOCKER as a raw-item
  hash, source location, checkpoint deadline, and concrete remediation tasks.
- Added `gatespec.plan --retask` for pre-implementation recovery after an
  exhausted round-02 BLOCKED chain or an unused PASS handoff, with lossless
  local archival, v1 compatibility, and v2 epoch/state reset.
- Added legacy PASS grandfathering, strict retask eligibility checks, Closure
  and historical-chain counterexamples, Source/v2 coverage, and rendered-hook
  installer tests while retaining the native tasks → analyze → implement
  sequence.
- Made retask preflight fail closed over full committed task/IA history,
  index-hidden drift, exact archived evidence trees, historical v2 handoff
  snapshots, and Original/epoch continuity so a reported PASS remains
  executable by the immediately following archive/reset step.

## 0.6.0 (2026-08-24)

- Added optional `gatespec.source-design`, enabled solely by the authoritative
  Source entry, with SD-F/U/FLOW/ALG/FAIL/TEST traceability, dual reviewed/
  approved bundle hashes, fresh REV-SOURCE, and explicit whole-Source approval.
- Added conditional Source `before_tasks` and final acceptance
  `after_implement` entries while preserving six upstream hook events and the
  unchanged native tasks → analyze → implement sequence.
- Added Review Protocol v2 execution epochs, immutable Original Baseline,
  Task-Handoff commits, preserved-review bindings, bounded IA snapshots, and
  raw NUL-delimited Final-Delta-SHA256; legacy v1 remains valid without Source.
- Made implementation checkpoint PASS continue automatically; material or
  uncertain Source deviation blocks into the archive/compensating-commit/
  revalidation revision flow.
- Added explicit whole-delivery acceptance bound to artifacts, REV-FINAL,
  final review commit, Subject, Source/IA, and raw tree delta in a metadata-only
  local commit.
- Added source/v2/acceptance checker fixtures, multi-hook installer coverage,
  Source templates, dispatcher rendering, and `specs/` package exclusion.

## 0.5.1 (2026-08-19)

- Replaced schema-like conversational R/D cards with concise, domain-native
  engineering scenarios, direct option bullets, and natural recommendations.
- Kept fixed boundaries and technical evidence available inline when material
  or through `explain`, while suppressing unchanged hashes, absent hooks,
  resume recaps, and other non-actionable progress telemetry.
- Preserved the structured Design Decision Log, artifact schema, checker,
  stable IDs, approval mechanisms, and spec-kit compatibility window.

## 0.5.0 (2026-08-19)

- Added decision triage so only choices with at least two viable options and
  materially different human consequences receive individual R/D approval.
- Split Requirements unknowns into human decisions, proposed defaults, and
  technical matters deferred to Design; split Design forks into human
  decisions, reasoned engineering determinations, and bounded Implementation
  Freedoms without adding an approval mechanism or workflow state.
- Reframed every human decision around one shared actor/trigger/outcome or
  failure scenario, with fixed boundaries and human consequences before
  options, recommendations, FRs, constraints, paths, and flow evidence.
- Excluded requirement/MUST-conflicting and dominated alternatives from option
  sets instead of using them as approval foils.
- Changed progress to count only human decisions and made every complex or
  high-risk card a single-card round; simple coherent cards retain the bounded
  adaptive batch flow.
- Kept existing artifact/checker compatibility, stable accepted IDs, three
  approval mechanisms, fixed hooks, and the native tasks/analyze/implement
  sequence; added cheap explain/promote controls and dual-platform behavior
  cases for the new prompt contract.

## 0.4.0 (2026-08-19)

- Replaced serial Specify/Plan questioning with adaptive batches of up to four
  pairwise-independent frontier decisions under a cognitive-load budget.
- Added complete first-pass decision inventories, transient dependency graphs,
  stable Requirements `R<n>` IDs, compact progress, and temporary per-round
  split/single/cap controls without adding workflow state or flags.
- Preserved full per-decision facts, options, constraint results, concrete
  Design scenarios, recommendations, and individual approvals inside batches.
- Added explicit high-risk authorization, partial-answer retention/refill, and
  conflict reconciliation that keeps unaffected approvals and forbids inferred
  option changes.
- Allowed an independent defaults batch to share a round while retaining its
  separate explicit approval; decision shortcuts never approve defaults.
- Kept legacy unnumbered Clarifications valid, left checker/hook/artifact hash
  contracts unchanged, and added dual-platform batching smoke requirements.

## 0.3.0 (2026-08-18)

- Added an approved `Implementation Review Contract` with exact checkpoint,
  isolation, parallelism, local-Git, test-mapping, final-validation, and
  two-remediation-round limits.
- Kept the native `speckit.tasks → speckit.analyze → speckit.implement`
  sequence while adding required `after_tasks`, `after_analyze`,
  `before_implement`, and `after_implement` structure/receipt hooks.
- Added explicit non-parallel `REV-FOUNDATION`, per-story, and REV-FINAL task
  checkpoints plus the independent REV-TASKS pre-implementation review.
- Added request → verdict → PASS-only seal artifacts under feature-local review
  roots, with deterministic upstream/subject hashes and stale-review blocking.
- Split implementation PASS enforcement into a dirty precommit candidate check
  and a clean, tracked postcommit final check.
- Required fresh reviewer context, prohibited same-context fallback, retained a
  manual new-session fallback for integrations without isolation support, and
  documented that session identity is procedural rather than cryptographic.
- Required clean feature branches and local checkpoint commits while forbidding
  review commands from pushing.
- Made old Approved-Design plans without the review contract enter archived
  diff-revision instead of silently continuing downstream.

## 0.2.0 (2026-08-07)

- Rebuilt the checker around section-scoped, portable parsing: strict line-1
  marker dispatch, unique/final approval blocks, matching dates and hashes,
  exact FR/scenario references, exact D-block boundaries, fixed empty states,
  six exact design dimensions, and Requirements-to-plan hash chaining.
- Added jq → python3 → restricted single-line feature.json resolution, including
  pretty JSON and paths with spaces.
- Fixed negative fixtures to reseal artifacts before structural assertions and
  expanded coverage for marker, approval, placeholders, FRs, D1/D10, dimensions,
  zero-decision plans, and stale Requirements bases.
- Added explicit constraint precedence and frozen Constraint Basis semantics,
  `--refresh-constraints`, constitution MUST/SHOULD rules, and approved
  GateSpec-constraint exemptions without constitution mutation.
- Added Draft-safe resume, read-only approved artifacts, `--revise`, `--restart`,
  and stale-task archival requirements.
- Replaced hook mode guessing with fixed `check-requirements`/`check-design`
  commands; gated phases run peer hooks while skipping their own entries.
- Restored the native `tasks → analyze → implement` timing and moved the plan's
  cross-artifact review to an internal pre-summary check.
- Rewrote skill rendering with pre-write argument validation, YAML quoting,
  agent-specific command references, absolute paths, atomic output, and a hard
  unresolved-token check.
- Pinned spec-kit to `>=0.16.0,<0.17.0`, tightened extension packaging, documented
  Linux/macOS Bash plus WSL/Git Bash, and added Ubuntu/macOS CI with ShellCheck,
  fixtures, renderer, manifest, and install smoke coverage.

## 0.1.0 (2026-08-07)

Initial release.

- `gatespec.specify` — grilling-style gated requirements: one-at-a-time
  decisions with recommendations, batch-approved defaults, zero
  auto-inference, fresh-eyes self-review, explicit summary approval.
- `gatespec.plan` — gated design: per-decision concrete options with
  constitution checks, six design detailing dimensions, implementer's
  walkthrough, explicit approval.
- `gatespec.check` + `check-gate.sh` — machine gates wired via official
  `before_plan` / `before_tasks` hooks; approval-as-snapshot (SHA-256)
  anti-drift; silent pass-through for non-gatespec (auto-track) specs.
- Dual-track design: upstream `speckit.*` commands untouched; both tracks
  converge at `speckit.tasks`.
- User-level constraints via `~/.gatespec/constraints.md` with one-time
  merge into project constitution.
