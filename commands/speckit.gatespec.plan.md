---
description: "GateSpec gated plan: every key decision presented with concrete options + trade-offs + recommendation, approved one-by-one by the user before the plan is fixed."
handoffs:
  - label: Create Tasks
    agent: speckit.tasks
    prompt: Break the approved plan into tasks
    send: true
scripts:
  sh: ../../scripts/bash/setup-plan.sh --json
  ps: ../../scripts/powershell/setup-plan.ps1 -Json
---

## User Input

```text
$ARGUMENTS
```

You **MUST** consider the user input before proceeding (if not empty).

## Step 0: Requirements Gate (mandatory, blocking)

Run the gate script before doing anything else:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh spec
# fallback path if installed flat: bash .specify/scripts/bash/check-gate.sh spec
```

- **Exit 0** → continue. (A spec without the gatespec marker exits 0 with a
  "skipped" note — that means the user is on the auto track; ask whether they
  intended the gated plan before proceeding.)
- **Exit 1** → STOP. Print the failures verbatim, help the user resolve them
  (usually: return to `__SPECKIT_COMMAND_GATESPEC_SPECIFY__`), and do not
  proceed with planning.

## Step 1: Load context and constraints

1. Run `{SCRIPT}` from repo root and parse JSON for FEATURE_SPEC, IMPL_PLAN,
   SPECS_DIR, BRANCH.
2. Read FEATURE_SPEC fully.
3. Load constraints (project constitution wins on conflict):
   - `.specify/memory/constitution.md` (or `/memory/constitution.md`)
   - `~/.gatespec/constraints.md` (user-level standing constraints)
4. **Constraint sync offer** (once per project): if
   `~/.gatespec/constraints.md` exists and the project constitution does not
   yet contain its content, offer: "检测到个人约束文件，本项目
   constitution 尚未包含。合并后上游 tasks/implement 也会自动遵守。要合并吗？"
   On yes, merge it into the project constitution (append under a
   `## Personal Constraints (via ~/.gatespec)` section). If it was merged
   before but the files have since diverged, offer a re-sync.
5. Replace IMPL_PLAN's starting content with the gatespec plan template:
   copy `.specify/extensions/gatespec/templates/gatespec-plan-template.md`
   over the plan path given by the script (keep the resolved path).

## Step 2: Decision protocol (the heart of this command)

Extract every non-trivial decision the design requires (tech stack, module
structure, concurrency model, interface shapes, error handling strategy,
testing approach, ...). Then, **one decision at a time**:

1. **Context** — what forces this decision (cite spec FRs / codebase facts).
2. **≥2 options**, each presented CONCRETELY:
   - a concrete scenario: a command session, a file tree, a request/flow
     trace, or a failure-in-the-field picture;
   - trade-offs as observable behavior ("adding an X requires editing 3
     files" / "failure mode is silent" — never bare abstractions like
     "decoupled" or "scalable" without a concrete grounding).
3. **Constitution check per option**: an option violating any
   constitution/constraint rule MUST be flagged as such in the presentation
   (never silently dropped — the user may still choose it with eyes open).
4. **Recommendation** with 1-2 sentences of reasoning.
5. **Wait for the user's explicit choice.** Record it in the plan's
   `## Decision Log` as `### D<n>` with `**Approved**: <choice> (date)`.

An abstract one-line summary MAY follow the concrete presentation, never
replace it.

## Step 3: Fill the plan artifacts

Following the upstream Phase 0/1 workflow (research.md, data-model.md,
contracts/, quickstart.md as applicable), with these gatespec additions:

1. **Design Detailing — six dimensions** (each: substantive content or an
   explicit `N/A — <reason>`; silent omission is a gate failure):
   thread/concurrency model · object lifetimes & ownership · key modules &
   classes · key internal APIs & interactions · external interface behavior
   contracts · setup/runtime/teardown phase interactions.
   (The user may extend/override this list via `~/.gatespec/constraints.md`.)
2. **Bidirectional traceability**: every spec FR must have a technical home
   in the design; every design element must trace back to an FR or an
   approved decision — flag and remove gold-plating the user never asked for.
3. **Implementer's walkthrough** (mandatory): play an implementer who has
   only spec.md + these artifacts and never joined the discussion. Simulate
   starting the work — "where does the first file go, what library do I
   import, what happens on this error path?" Every non-trivial fork without
   a signpost is a HOLE. Close each hole: a new Decision Log entry (user
   approves) or an explicit entry in `## Implementation Freedoms` with
   constraints. Log the walkthrough findings at the end of the Decision Log.
4. **Cross-artifact consistency**: run `__SPECKIT_COMMAND_ANALYZE__` (if
   available) and resolve or explicitly get user acceptance for its findings.
5. quickstart.md must give a runnable end-to-end validation path per P1
   user story.

## Step 4: Approval (the Design Gate)

1. Present a summary of **at most 20 lines**: chosen technical approach, the
   approved decisions list, explicit implementation freedoms, validation
   approach — and, mandatory, **"what I am least confident about"**.
2. Wait for explicit approval. Change requests → apply, then present ONLY
   the diff since the last shown version.
3. On explicit approval:
   - Set `**Status**: Approved-Design (YYYY-MM-DD)` in plan.md
   - Fill plan.md's `## Gate Approval` (date + Content-SHA256), computing:
     `sed '/^## Gate Approval/,$d' plan.md | sha256sum | cut -d' ' -f1`
4. Post-approval edits to plan.md follow the same revert-to-Draft +
   diff re-approval rule as the spec.

## Done When

- [ ] Requirements Gate passed (script exit 0)
- [ ] Every key decision user-approved in the Decision Log (concrete
      presentation, constitution-checked options, recommendation given)
- [ ] Six Design Detailing dimensions addressed or explicitly N/A
- [ ] Implementer's walkthrough done; holes closed via decisions or
      explicit Implementation Freedoms
- [ ] FR traceability verified both directions; analyze findings resolved
- [ ] User explicitly approved the summary; Status + Content-SHA256 recorded
- [ ] Completion reported; suggest `__SPECKIT_COMMAND_TASKS__` (the gates
      wired into core tasks will re-verify before task generation)
