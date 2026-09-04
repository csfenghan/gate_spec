---
description: "GateSpec fresh-context Source Design review: create and seal the independent REV-SOURCE contract."
---

## User Input

```text
$ARGUMENTS
```

Accept no input for the coordinator path or exactly
`--request <absolute-round-request-path>` for a manual fresh top-level reviewer
session. The canonical request must be inside the current feature's exact
`.gatespec/reviews/REV-SOURCE/` and named `round-00-request.md`,
`round-01-request.md`, or `round-02-request.md`. Reject every other form.

## Isolation and ownership

- The Source author/coordinator creates requests and persists returned text;
  it never judges its own request or authors a verdict.
- A fresh dispatcher supplies the verdict. Same-context fallback is forbidden.
  If unavailable, emit `REVIEW BLOCKED`, show the exact manual `--request`
  invocation, and stop without a verdict or seal.
- The reviewer is read-only for source, artifacts, Git, requests, and seals.
  It returns exact verdict bytes; the coordinator validates and persists them.
- BLOCKED never edits Source Design. The author may revise it, after which a
  different fresh context reviews the next bounded round.

Manual `--request` mode validates the canonical path and request, performs only
read-only review, and returns the exact Verdict Markdown. It never modifies the
repository, worktree, index, branch, commits, request, verdict, or seal. A test
that can write runs only in a unique temporary isolated checkout; no push is
ever allowed.

## Coordinator path

1. Resolve the feature and run `check-gate.sh source-candidate <feature-dir>`.
   A silent unmarked feature returns immediately. Require Draft Source Design,
   Protocol v3 execution state, and an attached local branch. Reject unrelated
   or product-code dirt; the bound Draft Source/execution files and current
   REV-SOURCE request metadata may remain uncommitted until their normal
   downstream handoff commit.
2. Select immutable round 00, 01, or 02. Round 00 chains to `none`; later rounds
   require the immediately preceding complete fresh BLOCKED verdict and a
   changed Source-Design-Reviewed-SHA256. Never overwrite receipt bytes or
   continue after round 02 BLOCKED.
3. Compute:
   - Spec/Plan content hashes over exact bytes before their Gate Approval;
   - Design-Basis-SHA256 from top-level research/data-model/quickstart and all
     regular contracts files except `contracts/source-design.md` and its direct
     `contracts/source-design/*.md` shards, as the C-sorted
     `<relative-path><TAB><raw-file-SHA256><LF>` manifest hash;
   - Source-Design-Reviewed-SHA256 from a manifest whose entry line hashes
     source-design.md after deleting its unique Status line and final Gate
     Approval, while every shard line uses its raw file hash;
   - Source-Baseline-Commit from execution state's unchanged
     Original-Implementation-Baseline.
4. Atomically write the request below, hashing every raw byte before the final
   Request-SHA256 field. Dispatch only its absolute path—no conversation,
   suggested finding, or proposed verdict.

```markdown
- **Protocol-Version**: `3`
- **Review-ID**: `REV-SOURCE`
- **Round**: `<00|01|02>`
- **Scope**: `SOURCE`
- **Spec-Content-SHA256**: `<64 lowercase hex>`
- **Plan-Content-SHA256**: `<64 lowercase hex>`
- **Design-Basis-SHA256**: `<64 lowercase hex>`
- **Source-Design-Reviewed-SHA256**: `<64 lowercase hex>`
- **Source-Baseline-Commit**: `<lowercase commit OID>`
- **Test-Control-Mode**: `not-applicable`
- **Test-Control-Closure-SHA256**: `not-applicable`
- **Test-Control-Subject-Manifest-SHA256**: `not-applicable`
- **Default-OFF-Evidence-SHA256**: `not-applicable`
- **Explicit-ON-Evidence-SHA256**: `not-applicable`
- **Previous-Verdict-SHA256**: `<none|prior verdict hash>`

## Required Tests

- Not run — source-design review

- **Request-SHA256**: `<64 lowercase hex>`
```

## Fresh reviewer judgment

Validate the request and reproduce every hash before judgment. Read the full
Source bundle and inspect the baseline repository. Require maintainer-facing
before/after plus success/failure flows; a complete ADD/MODIFY/DELETE/RENAME
SD-F manifest; complete declarations for public/cross-module/state/concurrency/
ownership/error SD-U symbols; executable call/data/state/lifecycle SD-FLOWs;
SD-ALG steps, data structures, invariants, complexity and boundaries;
SD-FAIL classification, propagation, retry/recovery, logging and alerting;
Requirement-to-file/symbol/test SD-TEST traceability; and explicit build,
dependency, configuration, persistence/transaction/migration, security,
performance, compatibility, and observability treatment. A reasoned N/A is
allowed; omission is not.

Check every choice is either an approved SD<n>, a reasoned engineering
determination, or bounded Implementation Freedom. Any unclassified human fork,
missing path/symbol/flow/test, incompatibility with Spec/Plan, material
uncertainty, or unbounded implementation choice is a BLOCKER. Reviewer PASS is
engineering evidence, not user approval.

Route abstraction-boundary findings precisely. A capability, observable error
or terminal-state, async/cancellation, compatibility, resource, timing,
affinity, or ownership change blocks to `gatespec.specify --revise`. A
semantically equivalent API/function/type/field/class/path rename, signature,
overload, or return-type change not covered by explicit Plan Implementation
Freedom blocks to `gatespec.plan --revise`. A bounded internal name or local
shape left free by Plan may be determined in Source and is not a revision by
itself.

Require Source to preserve the Plan's canonical Test Control Policy and exact
Requirements-copied TCE overlay without registering any exact control or
creating/changing/deleting/broadening an exception. A concrete `/src/testonly` path, production
touchpoint, hook switch/wiring, or validator in the Source manifest/design is a
stage violation: remove it and defer exact registration to native tasks. This
is not a Source decision and receives no per-hook human approval.
Also reject laundering a prospective hook into a normal product API or DI seam:
`Open(path, CheckpointCoordinatorOptions)`, generic observer/options state, or
an injected `AgentHost` constructor without an independent production contract
or exact approved `formal-api` TCE is not ordinary Source design merely because
it lacks a TC ID. Even with that TCE, concrete registration remains task-stage.

Reconstruct Scope Contract Schema 1 before judging the Source bundle. Every
Source element must trace to a non-deferred CAP and FR, all admitted CAPs must
be covered through their FR/SC obligations, deferred CAPs must stay absent, and
Retained baseline must remain unchanged. Activating deferred scope, adding
external behavior, changing Primary outcome, or opportunistically removing a
retained burden is a BLOCKER routed to `gatespec.specify --revise`; the reviewer
cannot admit the change.

Independently re-estimate aggregate Production additions, churn, and files
from the Source manifest and inspected baseline. A Design-estimate upper bound
of zero is exceeded by any positive value; otherwise block when any new upper
bound satisfies `new_upper * 100 >= design_upper * 125` (exactly 25% counts),
or when any Source production path family is absent from Design's Production
path basis. Direct remediation to `gatespec.plan --revise`; if splitting would
change approved scope, direct it to `gatespec.specify --revise`. Values below
the threshold are observations, not blockers, and large estimates already
disclosed in approved Design are valid.

Return exactly this Protocol v3 verdict, self-hashed over all preceding bytes:

```markdown
- **Protocol-Version**: `3`
- **Review-ID**: `REV-SOURCE`
- **Round**: `<request round>`
- **Request-SHA256**: `<request hash>`
- **Reviewer-Platform**: `<codex|claude|manual-codex|manual-claude>`
- **Reviewer-Context-ID**: `<nonempty fresh run ID>`
- **Isolation**: `fresh`
- **Status**: `<PASS|BLOCKED>`

## Tests Run

- Not run — source-design review

## Blockers

- `<None for PASS, or BLOCKER: ...>`

## Observations

- `<observation or None>`

## Limitations

- `<limitation or None>`

- **Verdict-SHA256**: `<64 lowercase hex>`
```

PASS Blockers is exactly `- None`; BLOCKED has at least one `- BLOCKER:` and no
`- None`. Validate schema, field/section order, isolation declaration, request
binding, blocker semantics, and self-hash before atomically persisting the exact
returned bytes.

For PASS, atomically create `seal.md` with the following exact field order and
self-hash. Copy every binding; do not add Scope, prose, or approval fields.

```markdown
- **Protocol-Version**: `3`
- **Review-ID**: `REV-SOURCE`
- **Round**: `<round>`
- **Status**: `PASS`
- **Request-SHA256**: `<request hash>`
- **Verdict-SHA256**: `<verdict hash>`
- **Spec-Content-SHA256**: `<request value>`
- **Plan-Content-SHA256**: `<request value>`
- **Design-Basis-SHA256**: `<request value>`
- **Source-Design-Reviewed-SHA256**: `<request value>`
- **Source-Baseline-Commit**: `<request value>`
- **Test-Control-Mode**: `not-applicable`
- **Test-Control-Closure-SHA256**: `not-applicable`
- **Test-Control-Subject-Manifest-SHA256**: `not-applicable`
- **Default-OFF-Evidence-SHA256**: `not-applicable`
- **Explicit-ON-Evidence-SHA256**: `not-applicable`
- **Sealed-At**: `<UTC YYYY-MM-DDTHH:MM:SSZ>`
- **Seal-SHA256**: `<64 lowercase hex>`
```

Run `check-gate.sh source-review <feature-dir>`. Do not mark Source approved or
commit on behalf of the user. The integration-specific fresh dispatcher is
appended when rendered; command mode uses the matching packaged dispatcher.
