<!--
  Replace every bracketed value before tasks.md leaves refinement.

  These must be the final two H2 sections before the first `## Phase` heading.
  The Checkpoint rows exactly follow the Plan's Required Checkpoints. Each row
  partitions the non-checkpoint task interval ending at that checkpoint: every
  non-checkpoint T### appears exactly once across Production tasks and
  Verification tasks, production may be `none`, and verification is nonempty.
  Contract refs use original FR-###, SC-###, approved D<n>, and, when Source is
  enabled, approved SD<n> and all SD-* IDs. C-sort refs and separate them only
  with `, `; never use a range or invented umbrella ID.

  When no basis-matching prior BLOCKER exists, retain the one exact all-`none`
  row. Otherwise remove it and add one row per complete prior `- BLOCKER: ...`
  item. Hash the exact raw UTF-8 bytes of that complete item. Source verdict is
  its feature-relative verdict path plus `#B<two-digit ordinal>`. Required-before
  is one Plan checkpoint, and every listed remediation task occurs no later
  than that checkpoint.
-->

## GateSpec Checkpoint Closure *(gatespec: mandatory)*

| Checkpoint | Contract refs | Production tasks | Verification tasks |
|---|---|---|---|
| [REV-ID] | [C-sorted artifact IDs separated by comma+space] | [T### list in tasks order, or none] | [one or more T### IDs in tasks order] |

## GateSpec Prior Review Closure *(gatespec: mandatory)*

| Finding-SHA256 | Source verdict | Required-before | Remediation tasks |
|---|---|---|---|
| none | none | none | none |
