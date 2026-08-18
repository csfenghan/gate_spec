---
description: "GateSpec fresh-context task review: create and seal REV-TASKS after native analyze."
---

## User Input

```text
$ARGUMENTS
```

Accept either no input (the normal `after_analyze` coordinator path) or exactly
`--request <absolute-round-request-path>` (manual new-session fallback). Reject
all other input. The canonical path must resolve inside the current feature's
exact `.gatespec/reviews/REV-TASKS/` directory and its basename must be
`round-00-request.md`, `round-01-request.md`, or `round-02-request.md`.

## Non-negotiable isolation and ownership

- The spec/plan/tasks author or remediator context may create a request and
  persist the returned adapter output, but MUST NOT judge the request or write
  its own verdict.
- A verdict comes only from the fresh reviewer dispatcher appended to this
  command. Never fall back to review in the current context.
- If fresh dispatch is unavailable, emit `REVIEW BLOCKED`, give the exact
  `--request <absolute-request-path>` invocation for a new top-level session,
  and stop without a verdict or seal.
- The reviewer is read-only for spec, plan, tasks, source, Git, requests, and
  seals. It returns verdict text; the coordinator validates and persists it.
- A BLOCKED reviewer never performs remediation or re-reviews its own fix.
  Native tasks/analyze must remediate, followed by another fresh context.

## Manual `--request` path

This is reviewer-only mode for a user-opened fresh top-level session. Verify
the absolute path is the current feature's REV-TASKS request, then skip every
Coordinator step. Do not create, modify, persist, move, or commit any request,
verdict, seal, task, or source file. Do not alter the primary worktree, index,
branch, or commits, and never push. A test that may write may run only in a
unique detached temporary worktree; verify it has no tracked delta afterward
and remove it. Ephemeral files for hashing/test output may use `/tmp`; no
repository or other persistent file may be written.
Review under the installed adapter's remaining read-only rules and return only
the exact Verdict Markdown to the user, using `Reviewer-Platform`
`manual-codex` or `manual-claude` as selected by the active dispatcher and
`Isolation` `fresh`. The user carries that text back to the original
coordinator for validation and persistence. Never create a seal or local
commit in manual reviewer mode.

## Coordinator path

1. Resolve `.specify/feature.json` and quote the feature path. Run
   `check-gate.sh tasks-structure <feature-dir>`. A silent zero result for an
   unmarked upstream feature returns immediately with no writes or report.
   Stop on every failure.
2. Use review ID `REV-TASKS`, scope `TASKS`, and directory
   `<feature>/.gatespec/reviews/REV-TASKS/`. If `check-gate.sh task-review`
   already accepts a current seal, keep all receipt bytes read-only and return.
3. Select the next round without guessing:
   - no prior files → `00`, Previous-Verdict-SHA256 `none`;
   - a complete prior BLOCKED round → `01` or `02`, chained to that verdict;
   - PASS already sealed → read-only success;
   - round 02 BLOCKED, an orphan file, an invalid chain, or any round beyond 02
     → stop. There are at most two remediation rounds after round 00.
   A remediation request requires a changed normalized tasks definition. Never
   overwrite an earlier request or verdict.
4. Compute current hashes using the checker contract: scoped spec/plan content,
   the C-sorted relative-path/TAB/file-hash design-attachment manifest, and
   tasks.md with CRLF normalized and only valid T### `[xX]` progress normalized
   to `[ ]`.
5. Write `round-<NN>-request.md` atomically with exactly this field/section
   order. Replace values, omit angle brackets, and hash every raw byte before
   the final Request-SHA256 field:

```markdown
- **Protocol-Version**: `1`
- **Review-ID**: `REV-TASKS`
- **Round**: `<00|01|02>`
- **Scope**: `TASKS`
- **Spec-Content-SHA256**: `<lowercase 64-hex>`
- **Plan-Content-SHA256**: `<lowercase 64-hex>`
- **Design-Attachments-SHA256**: `<lowercase 64-hex>`
- **Tasks-Definition-SHA256**: `<lowercase 64-hex>`
- **Implementation-Baseline**: `not-applicable`
- **Base-Commit**: `not-applicable`
- **Subject-Commit**: `not-applicable`
- **Task-IDs**: `none`
- **Changed-Paths-SHA256**: `not-applicable`
- **Previous-Verdict-SHA256**: `<none|prior Verdict-SHA256>`

## Required Tests

- Not run — task-plan review

- **Request-SHA256**: `<lowercase 64-hex>`
```

6. Dispatch exactly that absolute request path using the appended or packaged platform
   adapter. Do not send conversation, analysis summaries, suggested findings,
   or a proposed verdict.

## Fresh reviewer judgment

Review the approved Requirements/Design and native tasks from the request
without editing them. Check at least: every FR/story and mapped validation has
executable task coverage; exact file scopes and dependencies are sufficient;
parallel labels cannot race; phases remain independently testable; every
Implementation Review Contract checkpoint is phase-final and its tests are
executable; and tasks introduce no unapproved requirement, design choice, or
gold-plating. A material uncertainty is a BLOCKER, not an inferred default.

The adapter, or a manual fresh session whose returned text is supplied back to
this no-input coordinator, returns exactly:

```markdown
- **Protocol-Version**: `1`
- **Review-ID**: `REV-TASKS`
- **Round**: `<00|01|02>`
- **Request-SHA256**: `<request value>`
- **Reviewer-Platform**: `<codex|claude|manual-codex|manual-claude>`
- **Reviewer-Context-ID**: `<nonempty fresh context/run ID>`
- **Isolation**: `fresh`
- **Status**: `<PASS|BLOCKED>`

## Tests Run

- Not run — task-plan review

## Blockers

- `<None for PASS, or BLOCKER: ... for BLOCKED>`

## Observations

- `<observation or None>`

## Limitations

- `<limitation or None>`

- **Verdict-SHA256**: `<lowercase 64-hex>`
```

PASS Blockers is exactly `- None`; BLOCKED contains at least one
`- BLOCKER: ...`. Before persistence, validate field/section order, self-hash, matching
Review-ID/Round/Request-SHA256, allowed platform, nonempty context ID,
`Isolation: fresh`, and PASS/BLOCKED blocker semantics. Persist its exact bytes
as `round-<NN>-verdict.md`; never rewrite reviewer prose.

## Verdict handling

- BLOCKED: create no seal. Report blockers and stop the hook. The authoring
  context may remediate tasks, rerun native analyze, and open the next allowed
  round; this reviewer context may not do so.
- PASS: create `seal.md` atomically with the exact ordered fields below, copying
  all bound values from the accepted request/verdict. `Sealed-At` is current UTC
  `YYYY-MM-DDTHH:MM:SSZ`; hash all raw bytes before Seal-SHA256.

```markdown
- **Protocol-Version**: `1`
- **Review-ID**: `REV-TASKS`
- **Round**: `<00|01|02>`
- **Status**: `PASS`
- **Request-SHA256**: `<request value>`
- **Verdict-SHA256**: `<verdict value>`
- **Spec-Content-SHA256**: `<request value>`
- **Plan-Content-SHA256**: `<request value>`
- **Design-Attachments-SHA256**: `<request value>`
- **Tasks-Definition-SHA256**: `<request value>`
- **Implementation-Baseline**: `not-applicable`
- **Base-Commit**: `not-applicable`
- **Subject-Commit**: `not-applicable`
- **Sealed-At**: `<UTC RFC3339>`
- **Seal-SHA256**: `<lowercase 64-hex>`
```

After writing the seal, first validate its exact local schema/hash chain. Then
verify the feature branch contains no unrelated dirty paths and create one
local checkpoint commit containing only the approved Requirements/Design
artifacts, tasks.md, and the REV-TASKS request, verdict, and seal. Never push.
Require a clean worktree after that commit, then run
`check-gate.sh task-review <feature-dir>`; the checker requires the seal to be
tracked at clean HEAD. Do not report PASS unless it succeeds. That exact HEAD
is the Implementation-Baseline used by the first implementation request. If a
safe unambiguous local commit cannot be made, stop before native implementation.

The integration-specific fresh dispatcher is appended when this command is
rendered as a Claude/Codex skill. In command mode, use the matching packaged
`reviewers/<platform>/dispatcher.md`; if no matching trusted adapter is
available, take only the manual-new-session path above and never self-review.
