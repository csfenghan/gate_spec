---
description: "GateSpec gate check: run the machine gate (requirements/design) for the current feature and report results."
---

## User Input

```text
$ARGUMENTS
```

Optional argument: `spec` or `design` to force a gate; omit to auto-detect.

## What to do

1. **Resolve the feature directory**: read `.specify/feature.json`
   (`feature_directory`). If missing, run the core
   `check-prerequisites --json --paths-only` script, or ask the user for the
   path.

2. **Pick the gate mode**:
   - Explicit argument `spec` / `design` → use it.
   - Otherwise auto-detect: `plan.md` absent → `spec`; present → `design`.
     (This matches the hook wiring: before_plan fires when plan.md does not
     exist yet; before_tasks fires when it does.)

3. **Run the check**:

   ```bash
   bash .specify/extensions/gatespec/scripts/bash/check-gate.sh <mode> <feature-dir>
   # fallback path if installed flat: bash .specify/scripts/bash/check-gate.sh <mode> <feature-dir>
   ```

4. **Report and act**:
   - Exit 0 → report "GATE PASSED" (or the skip note for auto-track specs)
     and continue with whatever invoked this check.
   - Exit 1 → print the failure list verbatim. If this check was invoked by
     a `before_plan` / `before_tasks` hook: **STOP the surrounding command
     immediately** — do not generate the plan/tasks. Tell the user exactly
     which items to resolve (e.g. unanswered clarifications, unapproved
     decisions, approval-snapshot drift) and which command to re-run
     (`__SPECKIT_COMMAND_GATESPEC_SPECIFY__` /
     `__SPECKIT_COMMAND_GATESPEC_PLAN__`).

## Rules

- Never "fix" a failing gate by editing Status fields, approval records, or
  hashes yourself — approvals come from the user only. You may help resolve
  content-level failures (e.g. landing a clarification into the body), but
  re-approval always goes through the user.
- A spec without the `<!-- path: gatespec -->` marker is auto-track: the
  gate passes silently by design. Do not demand gatespec artifacts for it.
