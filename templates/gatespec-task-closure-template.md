<!--
  Replace every bracketed value before tasks.md leaves refinement.

  Before finalizing these matrices, re-estimate aggregate Production
  additions/churn/files from all concrete task paths and build work. At 25%
  upper-bound growth (or positive from zero) or a new Design-undeclared
  production path family, stop for Plan revision; do not encode or conceal the
  drift in a matrix row.

  These must be the final three H2 sections before the first `## Phase` heading.
  The Checkpoint rows exactly follow the Plan's Required Checkpoints. Each row
  partitions the non-checkpoint task interval ending at that checkpoint: every
  non-checkpoint T### appears exactly once across Production tasks and
  Verification tasks, production may be `none`, and verification is nonempty.
  Contract refs use original FR-###, SC-###, approved D<n>, and, when Source is
  enabled, approved SD<n> and all SD-* IDs. C-sort refs and separate them only
  with `, `; never use a range or invented umbrella ID. CAP-### remains in the
  Requirements Scope Contract and never appears here; its closure is proven by
  the existing CAP → FR/SC → task chain.

  When no basis-matching prior BLOCKER exists, retain the one exact all-`none`
  row. Otherwise remove it and add one row per complete prior `- BLOCKER: ...`
  item. Hash the exact raw UTF-8 bytes of that complete item. Source verdict is
  its feature-relative verdict path plus `#B<two-digit ordinal>`. Required-before
  is one Plan checkpoint, and every listed remediation task occurs no later
  than that checkpoint.

  Test Control Closure is registered only by native tasks/refinement. Mode
  `none` has exactly the all-none row. Mode `isolated` removes it and uses
  continuous TC-001... IDs. Test-only surface and Production touchpoint cells
  contain canonical comma+space `repo/path::symbol` entries. Repository paths
  are slash-normalized relative paths with no leading dash, empty, `.` or `..`
  component, repeated/trailing slash, whitespace, or shell metacharacter.
  Symbols are nonempty whitespace-free declaration locators; common operator
  spellings such as `operator[]` and `operator=` are valid, while Markdown/list
  delimiters remain forbidden.
  Unless Requirements approved a `language-marker` TCE, each Test-only surface
  symbol contains a `testonly` namespace/module component or a declaration name
  beginning `TestOnly`/`test_only`. Apply the Plan's
  exact Requirements-copied TCE only to its named Rule; no task may create or
  broaden one. Build switch / validator is canonically
  `NAME_ENABLE_TEST_HOOKS @ wiring/path @ validator/testonly-path`; an approved
  `switch-identifier` or `validator-path-marker` TCE replaces only that token
  while retaining the three-part tuple. A switch replacement remains a safe
  `[A-Za-z_][A-Za-z0-9_]*` source/build identifier. Consumer IDs use comma+space T### order and the
  default-build proof cell is exactly one non-checkpoint task.
  Absent an exact `touchpoint-shape` TCE, each affected production function has at most one visually contiguous
  dedicated hook-macro guard block containing one `testonly` call whose result
  rejoins the normal production error/result path. Count/wait/fault selection/
  observer dispatch stays in the registered test-only root (canonical
  `/src/testonly`, or the exact `source-root` replacement). Only a
  `touchpoint-shape` TCE may replace the guard/call/result/mechanics shape; only
  a `source-root` TCE may replace that root. A replacement spanning both needs
  both Rules; `control-model` never authorizes production-side mechanics.
  Concrete task paths/symbols must also support a separate Test Control scale
  estimate (additions, churn, files, touchpoints) for REV-TASKS Audit. Do not
  add that estimate to this table or Production estimate; implementation
  verdicts replace ranges with actual exact numbers.
  On a retask, preserve Mode plus every registered TC ID, surface, touchpoint,
  effect/lifetime, switch, wiring path, and validator path from the
  basis-matching archive. Only consumer/default-proof T### IDs may be rebound
  without changing meaning. Any other change requires Plan revision and fresh
  native tasks/REV-TASKS.
-->

## GateSpec Checkpoint Closure *(gatespec: mandatory)*

| Checkpoint | Contract refs | Production tasks | Verification tasks |
|---|---|---|---|
| [REV-ID] | [C-sorted artifact IDs separated by comma+space] | [T### list in tasks order, or none] | [one or more T### IDs in tasks order] |

## GateSpec Prior Review Closure *(gatespec: mandatory)*

| Finding-SHA256 | Source verdict | Required-before | Remediation tasks |
|---|---|---|---|
| none | none | none | none |

## GateSpec Test Control Closure *(gatespec: mandatory)*

- **Mode**: `none`

| Control | Verification gap / production invariant | Test-only surface | Production touchpoint | Allowed effect / lifetime | Build switch / validator | Consumer tasks/tests | Default-build proof task |
|---|---|---|---|---|---|---|---|
| none | none | none | none | none | none | none | none |
