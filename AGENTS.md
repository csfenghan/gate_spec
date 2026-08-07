# GateSpec — Agent Handoff Guide

GateSpec 0.2.0 is a personal spec-kit extension that adds human approval gates
to Requirements and Design. Read this file before changing the repository.

## Product invariants

1. **Human-led constraints**: agents propose and humans approve; no key feature
   decision takes effect implicitly.
2. **Low auto-inference**: unknowns become a blocking question or proposed
   default. The blocking/default classification has a cheap user veto.
3. **Discuss before execute**: Requirements blocks plan; Design blocks tasks.
4. **Bounded presentation**: one decision at a time, one defaults batch,
   ≤20-line final summaries including “what I am least confident about”, and
   diff-only re-approval.
5. **Concrete design**: every design option has a command/file-tree/flow/failure
   scenario and observable trade-offs; abstractions may only follow it.

Feature content has exactly three approval mechanisms: a decision answer, the
defaults batch, and final summary/diff approval. “Proceed” cannot seal unresolved
blocking work; a complete clarification set writes a Draft automatically.

## Architecture invariants

- Upstream `speckit.*` is never modified. Both paths converge at the unchanged
  `speckit.tasks → speckit.analyze → speckit.implement` sequence.
- Line 1 of gated spec.md is exactly `<!-- path: gatespec -->`. No marker means
  a true zero-output pass; a marker on any later line is corruption and fails.
- Keep upstream mandatory sections: spec User Scenarios & Testing,
  Requirements, Success Criteria; plan Technical Context, Constitution Check,
  Project Structure.
- `## Gate Approval` is unique/final and contains only approval date and scoped
  Content-SHA256. Status and approval dates agree.
- plan.md records the approved Requirements content hash. A re-approved spec
  invalidates an old plan and its tasks.
- Enforcement remains prompt rules plus one thin portable Bash checker. Do not
  introduce orchestration/state machines.
- The repository is the source of truth. Edit `commands/`, never rendered
  global skills.

## Constraint and rerun invariants

Constraint priority is constitution > `<repo>/.gatespec/constraints.md` >
`~/.gatespec/constraints.md`. spec.md Constraint Basis records source hashes,
effective rules, and conflicts. Constitution MUST conflicts are not approvable;
SHOULD deviations need reasons; GateSpec constraints need explicit exemptions.
Never merge personal constraints into the constitution automatically.

Approved Requirements freezes its basis. User constraint drift warns until
`--refresh-constraints`; constitution/project-policy drift forces re-approval.
Drafts resume in place, approved artifacts are read-only, `--revise` uses diff
re-approval, and `--restart` archives before rebuilding. Revision/restart must
archive tasks rather than leave stale execution work.

The six Design Detailing dimensions are exact mandatory core fields. Constraints
may add fields, never replace them. Plan performs its own attachment consistency
walkthrough before summary; upstream analyze runs only after tasks.

## Repository map

| Path | Responsibility |
|---|---|
| `extension.yml` | 0.2.0 manifest, fixed hooks, verified version range |
| `commands/speckit.gatespec.{specify,plan,check}.md` | public protocols |
| `commands/speckit.gatespec.check-{requirements,design}.md` | fixed hook entries |
| `templates/gatespec-{spec,plan}-template.md` | upstream-compatible artifacts |
| `scripts/bash/check-gate.sh` | deterministic machine gate |
| `install.sh` | atomic global renderer + optional project registration |
| `tests/run-tests.sh` | checker fixtures |
| `tests/test-installer.sh` | renderer/manifest/install smoke |
| `tests/run-all.sh` | syntax, ShellCheck, and all tests |
| `docs/` | full protocol and upstream sync ritual |

`.extensionignore` must exclude VCS state, local agent directories, tests/CI,
and development handoff files. Supported platforms are Linux/macOS Bash;
Windows uses WSL/Git Bash.

## Upstream constraints (verified with spec-kit 0.16.1.dev0)

- Primary extension command names are `speckit.{extension-id}.{command}`.
- Aliases render only in commands mode. Skill invocations are
  `/speckit-gatespec-*` (Claude) and `$speckit-gatespec-*` (Codex).
- `before_plan` is fixed to `check-requirements`; `before_tasks` is fixed to
  `check-design`. Manual check may accept `[spec|design]`.
- Core hooks fire on core commands. Gated commands run their inline gate plus
  peer same-phase before/after hooks and skip every `speckit.gatespec.*` hook.
- Manifest compatibility is `>=0.16.0,<0.17.0`; do not widen without the
  upstream sync ritual.

## Iterating

1. Edit repository sources and add a positive or counterexample fixture for
   each deterministic rule.
2. Run `bash tests/run-all.sh`; the tree must remain unchanged by tests.
3. Re-render with `./install.sh` only when an installed copy is needed for a
   manual smoke. Use `--force` only with intent; it backs up local constraints.
4. After spec-kit upgrades, follow `docs/upstream-sync.md` on Linux and macOS.
