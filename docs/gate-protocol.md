# GateSpec Gate Protocol

The full protocol behind the `gatespec.specify` / `gatespec.plan` /
`gatespec.check` commands. Design rationale and rules live here; the command
files are the executable summaries.

## Tracks

GateSpec is **dual-track** by design:

- **Auto track** (upstream, untouched): `speckit.specify → speckit.plan →
  speckit.tasks → speckit.implement`. For exploratory or mechanical work.
- **Gated track** (this extension): `gatespec.specify → gatespec.plan →
  speckit.tasks → speckit.implement`. For anything that matters.

Tracks share artifact formats and converge at upstream `speckit.tasks`.
Rule of thumb: when in doubt, use the gated track; only confirmed
throwaway/exploratory changes go auto.

The track marker is line 1 of spec.md: `<!-- path: gatespec -->`.
Gate checks **silently pass** specs without it, so the auto track is never
disturbed — including when gatespec's `before_plan` / `before_tasks` hooks
fire on core commands.

## The four protocol pillars

1. **Human-led constraints** — agents propose, humans approve. No key
   decision takes effect without explicit user approval.
2. **Low auto-inference** — unknowns become explicit markers or proposed
   defaults; "informed guesses" are forbidden. The single unavoidable
   inference (blocking vs non-blocking classification) gets a cheap veto:
   any defaults-table row can be pulled out for full discussion.
3. **Discuss before execute** — gates block plan/tasks until Requirements
   and Design are approved.
4. **Bounded presentation** — humans approve only compressed artifacts:
   one question at a time (with recommendation), batch defaults tables,
   ≤20-line summaries, diffs on re-approval rounds.

## Requirements phase (gatespec.specify)

- **Facts are looked up, not asked**; only decisions go to the user.
- **Blocking decisions**: one at a time, decision-tree order; each with
  context + options + recommendation + reason. User answers before the next.
- **Non-blocking unknowns**: batch "proposed defaults" table, approved in
  one reply; any row can be escalated.
- **Semantic readiness** (before approval):
  - *Self-containment* — every clarification conclusion must land in the
    spec body; chat is not spec.
  - *Self-consistency* — fresh-eyes adversarial read (as an implementer who
    wasn't there); findings resolved or explicitly accepted, and logged.
  - *Verifiability* — every FR referenced by ≥1 acceptance scenario
    (machine-checked); vague-word lint (warning).
- **Approval**: user approves a ≤20-line summary that must include
  "what I am least confident about". Status → `Approved-Requirements`,
  content hash recorded.

## Design phase (gatespec.plan)

- **Step 0**: machine Requirements Gate must pass.
- **Decision protocol**: one decision at a time; ≥2 options each with a
  CONCRETE scenario (command session / file tree / failure picture),
  trade-offs as observable behavior, per-option constitution check,
  recommendation + reason. Abstract-only presentations are forbidden.
- **Six design detailing dimensions** (fill or explicitly N/A): thread
  model · object lifetimes/ownership · key modules & classes · key internal
  APIs · external interface contracts · setup/runtime/teardown.
- **Implementer's walkthrough**: simulate implementation start; every
  unsigned fork closes via an approved decision or an explicit entry in
  `## Implementation Freedoms`.
- **Bidirectional traceability**: every FR has a design home; every design
  element traces to an FR (no gold-plating).
- Cross-artifact consistency via upstream `speckit.analyze`.
- **Approval**: same summary + least-confident-point + hash protocol.

## Approval-as-snapshot (anti-drift)

On approval the agent records in `## Gate Approval`:

```
- **Approved by user**: YYYY-MM-DD
- **Content-SHA256**: `<hash>`
```

where the hash is `sed '/^## Gate Approval/,$d' <file> | sha256sum`.
Any post-approval edit fails the gate until re-approved via a diff round.
Approval is a contract over exact content, not a one-time gesture.

## Machine gates (check-gate.sh)

Wired through official extension hooks with `optional: false`:
`before_plan` → spec gate, `before_tasks` → design gate (includes spec).
Hook mode is auto-detected: plan.md absent ⇒ spec check; present ⇒ design.

Requirements Gate checks: marker (else skip) · no residual
`[NEEDS CLARIFICATION]` · Clarifications all concluded · defaults all
approved · Status + date · mandatory upstream sections · FR↔scenario
cross-refs · snapshot hash · vague-word lint (warning).

Design Gate adds: plan residual markers · Decision Log all Approved ·
six dimensions addressed/N/A · upstream plan sections · no template
placeholder remnants · Status + snapshot hash.

Enforcement is prompt-level by design (thin script + hard instructions),
not a state machine.

## Human judgment points (the only three)

1. Each blocking decision (with the right to reject recommendations).
2. The batch defaults table (with the right to escalate any row).
3. The final summary approval.

Everything else — fact lookup, classification proposals, self-checks,
walkthroughs, documentation — is the agent's job.

## User-level constraints (~/.gatespec/constraints.md)

Standing personal constraints loaded by both gated commands next to the
project constitution (constitution wins conflicts). The source of truth is
`constraints.md` at the repo root; `install.sh` syncs it to
`~/.gatespec/constraints.md`. `gatespec.plan` offers a one-time merge into
the project constitution so upstream phases (tasks/implement) obey them too,
and offers re-sync when they drift.
