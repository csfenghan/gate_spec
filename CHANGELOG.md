# Changelog

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
