# Upstream Sync Policy

GateSpec carries no upstream implementation. After any spec-kit upgrade,
review contracts and rerun smoke tests; never patch `spec-kit/` or upstream
`speckit.*` commands.

## Verified compatibility window

0.5.0 is verified against spec-kit `0.16.1.dev0` and declares
`>=0.16.0,<0.17.0`. Widen the upper bound only after completing this ritual.

## Contracts to compare

| Upstream contract | GateSpec consumer | Detection |
|---|---|---|
| Extension primary name `speckit.{ext}.{command}` | manifest commands | scratch install/schema validation |
| `spec.md` User Scenarios & Testing / Requirements / Success Criteria | native tasks/implement | Requirements checker |
| `plan.md` Technical Context / Constitution Check / Project Structure | native tasks | Design checker |
| tasks checklist `T###`, `[P]`, story labels, phase order | checkpoint rows | tasks-structure fixtures |
| `.specify/feature.json.feature_directory` | checker/commands | jq → python3 → restricted single-line parser tests |
| `setup-plan.sh --json` fields | gated plan setup | renderer/install smoke + manual plan smoke |
| `before_plan`, `before_tasks`, `after_tasks`, `after_analyze`, `before_implement`, `after_implement` | fixed gates/reviews | manifest assertions + manual hook smoke |
| mandatory hook same-session invocation and invalid-YAML skip behavior | fresh-context/manual fallback boundary | Claude/Codex manual isolation smoke |
| Claude/Codex custom-agent locations and fresh-spawn syntax | reviewer adapters/dispatcher | renderer + isolated-home install smoke |
| native `tasks → analyze → implement` handoff | downstream convergence | command/template review |

Review upstream specify, clarify, plan, tasks, analyze, and implement
prompt/template changes. In particular, confirm all six hook events still fire
at the same boundaries and native tasks preserve strict checklist rows. Port
useful behavior manually without deleting GateSpec mandatory sections, the six
design dimensions, or the Implementation Review Contract.

## Post-upgrade smoke

In a scratch initialized project:

1. `specify extension add --dev /path/to/gatespec --force` succeeds and the
   installed package contains no `.git/`, `.agents/`, or `.codex/` state.
2. A Draft gated spec blocks core plan through fixed
   `speckit.gatespec.check-requirements`, even if plan.md already exists.
3. An approved spec plus Draft plan blocks core tasks through fixed
   `speckit.gatespec.check-design`.
4. An unmarked upstream spec produces no GateSpec output in every fixed hook.
5. Gated specify/plan execute a harmless peer hook exactly once and skip their
   own hook entries.
6. In both Claude and Codex, present six genuine simple independent human
   decisions sharing one journey and confirm they take at most two question
   rounds. Present two genuine complex decisions and confirm each is alone in
   its round. A three-decision dependency chain remains three serial rounds,
   and a high-risk card is alone and cannot use the batch recommendation
   shortcut.
7. Present a technology-only Requirements unknown and confirm it creates no R
   card. Present a D56/D57-style design where Requirements fix the outcome,
   alternatives are externally equivalent, and one candidate violates a MUST;
   confirm the invalid candidate is excluded, the selected mechanism is a
   reasoned Design Detailing/research engineering determination, and no D card
   is created. Then request `discuss <topic>` and confirm promotion creates a
   self-contained shared-scenario card only when two viable options exist.
8. For every R/D card, remove Technical basis identifiers mentally and confirm
   the actor, trigger, options, and consequences remain understandable. Confirm
   fixed boundary and why-human-input fields precede options, while FRs,
   constraints, paths, and flows appear last.
9. Confirm a co-presented defaults card needs its own explicit approval,
   partial answers retain IDs and refill the next batch, conflicting answers
   preserve unaffected approvals, and a legacy Draft resumes without rewriting
   unnumbered Clarifications or accepted D IDs; a retired unanswered ID is not
   reused.
10. Re-approve a spec and confirm the old plan fails Requirements basis match.
11. Generate native tasks with one non-parallel checkpoint row per approved
   REV-ID and confirm `after_tasks` rejects a missing, duplicate, extra, or
   parallel checkpoint.
12. Run native analyze. Confirm the same author/analyzer context may coordinate
   REV-TASKS receipts but is forbidden from judging or authoring the verdict;
   obtain judgment from a fresh Claude/Codex context or the manual new-session
   fallback, and confirm `before_implement` rejects missing, BLOCKED, and stale
   task-review seals.
13. Run native implement through a stage checkpoint. Confirm parallel work joins,
   the context creates only a local commit/request and never pushes, a fresh
   reviewer alone returns verdict text, the coordinator validates/persists it
   and creates a PASS-only candidate seal, candidate validation precedes the
   receipt/checkmark commit, the clean tracked final check follows it, and
   rounds 03+ fail.
14. Confirm `after_implement` rejects missing/stale REV-FINAL and accepts a
    current full-feature PASS seal without replacing native implement.
15. Resume an old Approved-Design plan without Implementation Review Contract;
    confirm tasks/reviews archive, the plan reopens Draft, and diff re-approval
    is required before task regeneration.

Run `bash tests/run-all.sh` on Linux and macOS and verify `git status` remains
clean. If a hook or artifact contract changed, retain the old upper version
bound until compatibility is restored.

The optional local `spec-kit/` reference checkout is gitignored and
extension-ignored. It is read-only comparison material, never a vendored
dependency.
