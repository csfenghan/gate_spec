# Changelog

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
