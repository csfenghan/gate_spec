---
description: "GateSpec final delivery acceptance: present a bounded implementation summary and record explicit user acceptance."
---

## User Input

```text
$ARGUMENTS
```

Accept no arguments. This is the priority-20 `after_implement` hook, after the
priority-10 final-review check. Resolve the feature and run:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh acceptance-candidate <feature-dir>
```

A silent unmarked feature returns with no output or write. Every GateSpec
feature requires a current committed fresh REV-FINAL PASS. Failure blocks the
normal completion report; never manufacture or repair receipts here.
On success, use the checker's verified `Delivery Size` block; do not recalculate
against a different commit pair or path filter.

## One final user acceptance

From the validated final request/subject and repository diff, present at most
20 lines covering: delivered observable behavior; actual product/test/build
paths; material symbols/flows; Source manifest conformance when enabled;
bounded IA entries; exact tests and results; and actual Production additions,
churn, and unique files beside the approved Design ranges and confidence.
Production additions/deletions come from Git `--numstat --no-renames` over the
bound Original Baseline to REV-FINAL Subject. Count handwritten runtime code,
headers, protocol/schema, config, and build/packaging logic; exclude tests,
feature specs/review metadata, pure documentation, and only Design-declared
reproducibly generated outputs. A binary production file contributes to file
count and is disclosed separately because it has no line count. If an actual
number lies outside Design's interval, say so, but do not reject acceptance for
size alone; scope or contract violations remain governed by REV-FINAL. Include
remaining limitations/risks and mandatory “what I am least confident about”.
This is the only normal implementation-stage user acceptance; checkpoint PASS
results continue automatically and never ask for confirmation.

Wait for explicit acceptance of the whole implementation. A rejection writes nothing.
It does not infer whether to modify code, revise Source Design, or stop. Report
the rejection and ask the user for their chosen next action.

On explicit acceptance only, require a clean attached local branch. Compute all
values from the validated artifacts and Git objects; never copy an unverified
claim. Atomically write exactly:

```markdown
# GateSpec Implementation Acceptance
- **Protocol-Version**: `<active 1|2>`
- **Status**: `Accepted`
- **Accepted-At**: `<UTC YYYY-MM-DDTHH:MM:SSZ>`
- **Spec-Content-SHA256**: `<current scoped hash>`
- **Plan-Content-SHA256**: `<current scoped hash>`
- **Design-Attachments-SHA256**: `<current non-Source attachment manifest hash>`
- **Tasks-Definition-SHA256**: `<current normalized tasks hash>`
- **Execution-Epoch**: `<E<n>|not-applicable>`
- **Source-Design-Content-SHA256**: `<current hash|not-applicable>`
- **Implementation-Adjustments-SHA256**: `<REV-FINAL snapshot|not-applicable>`
- **Original-Implementation-Baseline**: `<commit OID>`
- **Final-Subject-Commit**: `<REV-FINAL Subject-Commit>`
- **REV-FINAL-Seal-SHA256**: `<current seal hash>`
- **Final-Review-Commit**: `<clean HEAD before acceptance>`
- **Final-Delta-SHA256**: `<raw tree delta hash>`
- **Acceptance-SHA256**: `<hash of all prior bytes>`
```

Protocol v1 uses its Implementation-Baseline as Original Baseline and records
epoch/Source/IA as `not-applicable`. Protocol v2 reads the unchanged Original
Baseline and epoch from execution state. Final-Delta-SHA256 hashes the exact raw
NUL-delimited stream from:

```bash
git diff-tree --raw -z --no-abbrev --no-renames <original-baseline> <final-subject>
```

This detects content/mode changes even when the old name-only Changed-Paths hash
is unchanged. Create one local metadata-only commit containing only
`.gatespec/acceptance.md`; never push. Then run `check-gate.sh acceptance
<feature-dir>`. Do not report GateSpec completion unless it validates the clean
worktree, direct commit parent, exact tracked bytes, all bound hashes/seals/
subjects, and raw final delta.
