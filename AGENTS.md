# GateSpec — Agent Handoff Guide

Personal Spec-Driven Development tool: a **spec-kit extension** that adds
human approval gates to the requirements and design phases. Read this file
fully before iterating.

## Core philosophy (the "why" — do not dilute)

1. **Human-led constraints** — agents propose, humans approve. No key
   decision takes effect without explicit user approval.
2. **Low auto-inference** — unknowns become explicit markers or proposed
   defaults; "informed guesses" are forbidden. The one unavoidable
   inference (blocking vs non-blocking classification) gets a cheap veto.
3. **Discuss before execute** — gates block plan/tasks until Requirements
   and Design are approved.
4. **Bounded presentation** — humans approve only compressed artifacts:
   one question at a time (with recommendation), batch defaults tables,
   ≤20-line summaries (must include "what I am least confident about"),
   diffs on re-approval rounds. No info-bombing.
5. **Concrete over abstract** — every design option is presented with a
   concrete scenario (command session / file tree / failure picture);
   trade-offs as observable behavior. Abstract summary may follow, never
   replace.

## Architecture invariants (do not break)

- **Dual-track**: upstream `speckit.*` (auto path) is NEVER modified;
  gatespec adds a parallel gated path. Tracks share artifact formats and
  converge at upstream `speckit.tasks`.
- **Track marker**: line 1 of gated spec.md is `<!-- path: gatespec -->`.
  `check-gate.sh` silently passes artifacts WITHOUT it — this keeps the
  auto track untouched. Load-bearing; never remove.
- **Upstream compatibility**: gatespec templates must keep upstream
  mandatory sections intact (spec: User Scenarios & Testing / Requirements /
  Success Criteria; plan: Technical Context / Constitution Check /
  Project Structure). See docs/upstream-sync.md for the full contract list.
- **Approval-as-snapshot**: approvals record
  `**Content-SHA256**` = `sed '/^## Gate Approval/,$d' <file> | sha256sum`.
  Post-approval edits fail the gate until diff re-approval.
- **No state machines / orchestration** — enforcement is prompt rules +
  one thin bash script, by design.
- **Repo is single source of truth**: skills are rendered artifacts
  produced by `install.sh`; edit `commands/`, never the installed copies.

## Repo layout

| Path | Role |
|------|------|
| `extension.yml` | spec-kit extension manifest (commands, hooks, requires) |
| `commands/speckit.gatespec.{specify,plan,check}.md` | the three protocol prompts — the heart of the product |
| `templates/gatespec-{spec,plan}-template.md` | artifact templates (upstream sections + gatespec blocks) |
| `scripts/bash/check-gate.sh` | machine gate (spec/design modes) |
| `constraints.md` | the owner's personal standing constraints — synced to `~/.gatespec/constraints.md` |
| `install.sh` | personal installer (global skills + constraints; optional per-project hook wiring) |
| `tests/run-tests.sh` | fixture tests for check-gate.sh — must stay green |
| `docs/gate-protocol.md` | full protocol spec |
| `docs/upstream-sync.md` | upstream follow-up ritual + dependency contracts |
| `spec-kit/` | local upstream reference copy (gitignored, never modify) |

## Hard upstream constraints (verified against spec-kit 0.16.1.dev0)

- Extension command primary names must match `speckit.{ext-id}.{cmd}`
  (validated in src/specify_cli/extensions/__init__.py:453).
- Aliases are free-form but render ONLY in commands mode; Claude Code and
  Codex integrations are skills-mode (primary names only) → invocation is
  `/speckit-gatespec-specify` (Claude Code) / `$speckit-gatespec-specify`
  (Codex). Accepted limitation; do not add shims.
- Hooks (`before_plan`, `before_tasks`, optional:false) live in
  `.specify/extensions.yml`; they fire only on CORE commands — the gated
  commands therefore run gate checks inline (Step 0 of gatespec.plan).

## Iterating

1. Edit `commands/` / `templates/` / `scripts/` / `constraints.md`.
2. `bash tests/run-tests.sh` — all fixtures must pass; add fixtures for
   new gate rules.
3. Re-render global skills: `./install.sh` (use `--force` only to
   overwrite local `~/.gatespec/constraints.md` edits; a backup is kept).
4. After any spec-kit upgrade: follow docs/upstream-sync.md (2-minute
   smoke check: gated spec must be blocked by before_plan hook; auto-track
   spec must pass silently).

## Gate semantics quick reference

- Requirements Gate: marker → no residual `[NEEDS CLARIFICATION]` →
  Clarifications all concluded → defaults all ✅ → FR↔scenario cross-refs →
  Status `Approved-Requirements (date)` → hash match.
- Design Gate: spec gate + plan residual markers → Decision Log every
  `### D<n>` has `**Approved**: <choice> (date)` → six Design Detailing
  dimensions filled or `N/A — <reason>` → no template remnants →
  Status `Approved-Design (date)` → hash match.
- Semantic readiness (prompt-enforced): self-containment (every conclusion
  lands in the body), self-consistency (fresh-eyes adversarial read /
  implementer's walkthrough), verifiability (FR↔scenario; quickstart per
  P1 story), bidirectional traceability (no orphan FRs, no gold-plating).
- Human judgment points are exactly three: decision calls, defaults-table
  batch approval, summary approval.
