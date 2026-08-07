# GateSpec

Human-gated Spec-Driven Development for coding agents — a lightweight
[spec-kit](https://github.com/github/spec-kit) **extension** (not a fork)
that puts explicit human approval gates on the requirements and design
phases, while leaving tasks/implementation untouched.

Philosophy: **human-led constraints · low auto-inference · discuss before
execute · bounded presentation**.

## Dual tracks

| Track | Flow | Use for |
|-------|------|---------|
| Auto (upstream, untouched) | `/speckit.specify → /speckit.plan → /speckit.tasks → /speckit.implement` | exploratory, mechanical changes |
| Gated (GateSpec) | `/gatespec.specify → /gatespec.plan → /speckit.tasks → /speckit.implement` | anything that matters |

Both tracks share artifact formats and converge at upstream `speckit.tasks`.
When in doubt, go gated.

## What the gates enforce

**Requirements Gate** (`gatespec.specify`):
grilling-style clarification (facts looked up, decisions asked one at a
time with recommendations; no informed guesses), batch-approved defaults,
fresh-eyes self-review, explicit approval of a ≤20-line summary that
includes "what I'm least confident about".

**Design Gate** (`gatespec.plan`):
every key decision presented with ≥2 concrete options + trade-offs +
recommendation and approved individually; six design detailing dimensions
(thread model, object lifetimes, key classes, key APIs, external contracts,
setup/runtime/teardown); implementer's walkthrough to eliminate silent
gaps; explicit approval.

**Approval-as-snapshot**: approvals record a content hash; any post-approval
edit fails the gate until re-approved via diff.

Machine checks (`check-gate.sh`) are wired through official extension hooks
(`before_plan`, `before_tasks`) and also block the mixed path
(gated spec + core plan, or gated plan + core tasks). Specs without the
`<!-- path: gatespec -->` marker are skipped silently — the auto track is
never disturbed.

## Install (personal use)

The repo provides its own installer; the repo is the single source of truth
(keep it in place — skills reference it by absolute path).

```bash
# Global install (default): skills → ~/.claude/skills/ + ~/.agents/skills/,
# personal constraints → ~/.gatespec/constraints.md
./install.sh

# Global install + project wiring (auto-gate hooks for core speckit commands):
./install.sh /path/to/a/spec-kit/project

# Options: --agent claude|codex|all   --force (overwrite local constraints edits)
```

After the global install, the skills are available in **every** project with
zero per-project setup. The project wiring (second form) only adds the
`before_plan` / `before_tasks` auto-gates for the mixed path (core
`speckit.plan` / `speckit.tasks` acting on gated artifacts) — the gated
commands enforce the gates inline regardless.

Uninstall: remove `~/.claude/skills/speckit-gatespec-*`,
`~/.agents/skills/speckit-gatespec-*`, and (optionally) `~/.gatespec/`;
in wired projects run `specify extension remove gatespec`.

## Commands

| Command | Purpose |
|---------|---------|
| `speckit.gatespec.specify` | gated requirements |
| `speckit.gatespec.plan` | gated design |
| `speckit.gatespec.check` | run gate checks manually |

Invocation names depend on the agent's registration mode: on skills-mode
agents (e.g. Claude Code) commands render as skills — invoke
`/speckit-gatespec-specify` etc. On commands-mode agents the declared
aliases also work: `/gatespec.specify`, `/gatespec.plan`, `/gatespec.check`.
(Skills-mode aliases are a known upstream limitation.)

## Personal constraints

Standing personal constraints (coding standards, design principles) live in
**`constraints.md` at this repo's root** — edit it here; `install.sh` syncs
it to `~/.gatespec/constraints.md` (local edits are preserved unless
`--force`, with a timestamped backup). Both gated commands load it next to
the project constitution, and `gatespec.plan` offers a one-time merge into
the project constitution so upstream phases obey it too.

## Docs

- [Gate protocol (full spec)](docs/gate-protocol.md)
- [Upstream sync policy](docs/upstream-sync.md)

## Development

```bash
bash tests/run-tests.sh   # fixture tests for the gate script
```

## License

MIT
