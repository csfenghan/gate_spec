# Upstream Sync Policy

GateSpec carries no upstream implementation. After any spec-kit upgrade,
review contracts and rerun smoke tests; never patch `spec-kit/` or upstream
`speckit.*` commands.

## Verified compatibility window

0.2.0 is verified against spec-kit `0.16.1.dev0` and declares
`>=0.16.0,<0.17.0`. Widen the upper bound only after completing this ritual.

## Contracts to compare

| Upstream contract | GateSpec consumer | Detection |
|---|---|---|
| Extension primary name `speckit.{ext}.{command}` | manifest commands | scratch install/schema validation |
| `spec.md` User Scenarios & Testing / Requirements / Success Criteria | native tasks/implement | Requirements checker |
| `plan.md` Technical Context / Constitution Check / Project Structure | native tasks | Design checker |
| `.specify/feature.json.feature_directory` | checker/commands | jq → python3 → restricted single-line parser tests |
| `setup-plan.sh --json` fields | gated plan setup | renderer/install smoke + manual plan smoke |
| `before_plan`, `before_tasks`, peer before/after hook behavior | mixed path/interoperability | manual hook smoke |
| native `tasks → analyze → implement` handoff | downstream convergence | command/template review |

Review upstream specify, clarify, plan, tasks, and analyze prompt/template
changes. Port useful behavior manually without deleting GateSpec mandatory
sections or the six design dimensions.

## Post-upgrade smoke

In a scratch initialized project:

1. `specify extension add --dev /path/to/gatespec --force` succeeds and the
   installed package contains no `.git/`, `.agents/`, or `.codex/` state.
2. A Draft gated spec blocks core plan through fixed
   `speckit.gatespec.check-requirements`, even if plan.md already exists.
3. An approved spec plus Draft plan blocks core tasks through fixed
   `speckit.gatespec.check-design`.
4. An unmarked upstream spec produces no GateSpec output in both hooks.
5. Gated specify/plan execute a harmless peer hook exactly once and skip their
   own hook entries.
6. Re-approve a spec and confirm the old plan fails Requirements basis match.
7. Generate native tasks, then run native analyze, then implement.

Run `bash tests/run-all.sh` on Linux and macOS and verify `git status` remains
clean. If a hook or artifact contract changed, retain the old upper version
bound until compatibility is restored.

The optional local `spec-kit/` reference checkout is gitignored and
extension-ignored. It is read-only comparison material, never a vendored
dependency.
