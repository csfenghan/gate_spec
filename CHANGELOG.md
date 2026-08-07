# Changelog

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
