# GateSpec

GateSpec 0.2.0 is a lightweight [spec-kit](https://github.com/github/spec-kit)
extension that puts explicit human approval gates on requirements and design.
It does not fork or modify upstream commands.

Its operating principles are human-led constraints, low auto-inference,
discussion before execution, bounded review artifacts, and concrete design
options.

## Two paths, one downstream workflow

| Path | Workflow |
|---|---|
| Upstream auto path | `speckit.specify → speckit.plan → speckit.tasks → speckit.analyze → speckit.implement` |
| GateSpec path | `gatespec.specify → gatespec.plan → speckit.tasks → speckit.analyze → speckit.implement` |

The paths converge at native `speckit.tasks`; GateSpec adds no gated tasks or
implement command. A gated spec is identified only by
`<!-- path: gatespec -->` on line 1. Completely unmarked specs make the gate
checker exit successfully with no output, so upstream behavior stays untouched.
A displaced marker is treated as a damaged gated artifact and fails.

## What is approved

Feature content has exactly three human approval mechanisms:

1. an answer to each blocking requirements/design decision;
2. one batch approval for proposed non-blocking defaults;
3. final approval of a ≤20-line Requirements or Design summary (or a diff on
   revision), including “what I am least confident about”.

“Done” cannot seal a Draft while blocking items remain. When blocking items and
defaults are complete, the agent writes the Draft automatically. Empty
Clarifications, Defaults, and Decision Log sections use explicit
`None — <reason>` records; blank sections never pass.

Requirements approval records a content SHA-256. Design records both its own
approval hash and the exact approved Requirements content hash. A changed spec
therefore invalidates an old plan, and revision/restart archives stale tasks.

## Constraints

Both gated phases load and explicitly merge:

1. project constitution (`.specify/memory/constitution.md`),
2. project GateSpec constraints (`.gatespec/constraints.md`),
3. user GateSpec constraints (`~/.gatespec/constraints.md`).

Higher entries win. The spec's `Constraint Basis` records source hashes,
effective rules, conflicts, and resolutions. Constitution `MUST` conflicts
cannot be approved inside a feature; `SHOULD` deviations require a reason.
Project/user GateSpec rules can be exempted only by an explicit decision.

The `Constraint Basis` heading and its five field labels remain fixed English
protocol tokens. Human-readable values use Simplified Chinese unless a
higher-priority effective constraint requires another language; paths, hashes,
and technical identifiers remain verbatim, and any override is recorded as a
conflict resolution.

The approved Requirements snapshot freezes its basis. A changed user file is a
warning until `--refresh-constraints`; a changed constitution or project
policy forces Requirements re-approval. GateSpec never silently copies user
constraints into the constitution.

## Safe resume controls

- default: continue a Draft in place; keep a valid approved artifact read-only;
- `--revise`: reopen as Draft, archive tasks, and use diff re-approval;
- `--restart`: archive current phase/downstream artifacts, then rebuild from
  the GateSpec template;
- `--refresh-constraints` (specify): recompute the frozen basis and enter the
  revision flow.

Design always covers six core dimensions (concurrency, lifetime/ownership,
modules/classes, internal APIs, external behavior, lifecycle). Constraints may
add dimensions but cannot remove or replace them. Before Design summary the
agent performs an internal spec/design-attachment consistency check. Native
`speckit.analyze` runs after tasks.md exists.

## Install

Supported shells are Linux and macOS Bash. On Windows, use WSL or Git Bash.

```bash
# Global Claude + Codex skills and user constraints
./install.sh

# Also register the extension and fixed hooks in an initialized project
./install.sh /path/to/spec-kit-project

# Options
./install.sh --agent claude|codex|all [--force] [project-dir]
```

Arguments are validated before writes. Skills are rendered atomically with
agent-specific command references and absolute paths back to this repository.
Keep the repository in place. Global skills are available everywhere, but the
complete plan/tasks workflow requires a project initialized by spec-kit.

`--force` replaces a locally changed `~/.gatespec/constraints.md` only after
keeping a timestamped backup. Without it, the installed personal copy is left
untouched.

Skill-mode invocation is `/speckit-gatespec-specify` for Claude and
`$speckit-gatespec-specify` for Codex. Command-mode aliases such as
`/gatespec.specify` remain available where upstream renders aliases.

## Machine gates and hooks

The public manual entry remains `speckit.gatespec.check [spec|design]`.
Hooks never infer mode:

- `before_plan` → `speckit.gatespec.check-requirements`;
- `before_tasks` → `speckit.gatespec.check-design`.

Gated specify/plan also run other extensions' same-phase before/after hooks,
skipping GateSpec's own entries to avoid recursion.

## Development

```bash
bash tests/run-all.sh
```

This runs Bash syntax checks, ShellCheck, deterministic checker fixtures,
Claude/Codex renderer checks, manifest checks, and an extension-install smoke
test when the `specify` CLI is available. Ubuntu and macOS CI run the same
suite and assert that it leaves the worktree clean.

See [the full gate protocol](docs/gate-protocol.md) and
[the upstream compatibility ritual](docs/upstream-sync.md).

## License

MIT
