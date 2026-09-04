# Upstream Sync Policy

GateSpec carries no upstream implementation. After any spec-kit upgrade,
review contracts and rerun smoke tests; never patch `spec-kit/` or upstream
`speckit.*` commands.

## Verified compatibility window

0.11.0 is verified against spec-kit `0.16.1.dev0` and declares
`>=0.16.0,<0.17.0`. Widen the upper bound only after completing this ritual.

## Contracts to compare

| Upstream contract | GateSpec consumer | Detection |
|---|---|---|
| Extension primary name `speckit.{ext}.{command}` | manifest commands | scratch install/schema validation |
| `spec.md` User Scenarios & Testing / Requirements / Success Criteria | native tasks/implement | Requirements checker |
| GateSpec Requirements Abstraction Schema 1 and normalized Input | gated specify/plan/review routing | abstraction checker + dual-platform behavioral smoke |
| GateSpec spec Scope Contract Schema 1 | Design/Source/tasks/review scope boundary | Scope checker + rendered/manual conservation smoke |
| `plan.md` Technical Context / Constitution Check / Project Structure | native tasks | Design checker |
| tasks checklist `T###`, `[P]`, story labels, phase order | checkpoint rows and all three Closure sections | tasks-structure/Test Control fixtures |
| `.specify/feature.json.feature_directory` | checker/commands | jq → python3 → restricted single-line parser tests |
| `setup-plan.sh --json` fields | gated plan setup | renderer/install smoke + manual plan smoke |
| six hook events, ordered multiple entries, and priority | 9 fixed gate/refine/review/acceptance entries | manifest assertions + manual hook smoke |
| native tasks/implement read `contracts/` | optional Source Design context | Source trace fixtures + manual prompt smoke |
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
   installed package contains Source/IA templates but no `.git/`, `.agents/`,
   `.codex/`, or development `specs/` state.
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
8. Generate Design Evidence Schema 1 without a diagram. Confirm all six
   dimensions contain the required structured fields, current repository
   evidence, target contracts, and Technical basis; the internal API dimension
   contains a language-tagged core contract skeleton plus ordered success and
   failure flow; and directional text is accepted without Mermaid. Confirm a
   shallow legacy one-line dimension fails.
9. For every conversational R/D card, confirm it uses a short domain-native
   engineering scenario, direct option bullets, and a natural recommendation;
   it must not render the structured Decision Log labels or invent UI actions
   for a non-UI feature. Remove citations mentally and confirm the situation,
   boundary, options, and consequences remain understandable, then use
   `explain R<n>` / `explain D<n>` to confirm the full basis remains available.
   For an approved D choice, confirm plan.md still contains the existing
   structured fields and passes the Design gate.
10. Confirm a co-presented defaults card needs its own explicit approval,
   partial answers retain IDs and refill the next batch, conflicting answers
   preserve unaffected approvals, and a legacy Draft resumes without rewriting
   unnumbered Clarifications or accepted D IDs; a retired unanswered ID is not
   reused.
11. Re-approve a spec and confirm the old plan fails Requirements basis match.
12. Generate native tasks with one non-parallel checkpoint row per approved
   REV-ID. Confirm priority-10 `after_tasks` changes only `tasks.md`, closes
   producer/consumer/test/lifecycle gaps, and writes the three exact Closure
   tables; priority-20 must reject a missing, duplicate, extra, parallel, or
   misplaced checkpoint, incomplete task interval/ref coverage, stale
   prior-finding row, and malformed Test Control row. A v3 task file missing any
   Closure section fails; pre-v3 work is historical only after acceptance.
13. Run native analyze. Confirm the same author/analyzer context may coordinate
   REV-TASKS receipts but is forbidden from judging or authoring the verdict;
   obtain judgment from a fresh Claude/Codex context or the manual new-session
   fallback, and confirm `before_implement` rejects missing, BLOCKED, and stale
   task-review seals.
   Exhaust REV-TASKS through a valid round-02 BLOCKED chain and confirm Plan
   `--retask` is the only bounded regeneration route: it uses one UTC
   `*-retask` archive target, makes separate archive/handoff local commits,
   never pushes, retains blocker identities in the new Prior Review Closure,
   and refuses round 00/01, checked/implemented/IA/acceptance/product-delta,
   out-of-scope dirt, divergent index/working snapshots, detached, stale,
   orphan, or collision states.
14. Run native implement through a stage checkpoint. Confirm parallel work joins,
   the context creates only a local commit/request and never pushes, a fresh
   reviewer alone returns verdict text, the coordinator validates/persists it
   and creates a PASS-only candidate seal, candidate validation precedes the
   receipt/checkmark commit, the clean tracked final check follows it, and
   rounds 03+ fail.
15. Approve Design, exercise both explicit handoffs (skip Source and enable
    Source), and confirm first enable after any product implementation is
    refused. With Source, change only Status/Gate Approval after REV-SOURCE and
    confirm the seal remains current; change body/shard and confirm it fails.
16. Confirm new/revised Plans and every active receipt use Protocol v3. Active
    or unaccepted v1/v2 work must stop at `gatespec.plan --revise`; accepted
    v1/v2 acceptance records remain historical. `--retask` must never upgrade
    them. In v3 verify Task-Handoff, empty IA baseline, exact SD task coverage,
    IA Subject snapshots, Original Baseline, preserved revalidations, raw Final
    Delta, Test Control Closure, and all five Test Control receipt bindings. A
    v3 retask increments only Execution Epoch, preserves Original Baseline,
    resets Task Handoff, binds current Source, derives preserved reviews, and
    resets Source IA to canonical empty. A material Source or control-wiring
    departure must block rather than become IA.
17. Confirm priority-10 `after_implement` rejects missing/stale REV-FINAL. Its
    PASS automatically reaches priority-20 acceptance; rejection writes
    nothing, acceptance makes one metadata-only local commit, and stale/
    dirty/subject/seal/delta mismatches fail.
18. Resume an old Approved-Design plan without Implementation Review Contract
    or Design Evidence Schema 1; confirm one migration archives tasks/reviews,
    reopens the plan as Draft, enriches structured evidence without rewriting
    unaffected decisions, and requires diff re-approval before task
    regeneration.
19. Generate Requirements/Design Delivery Estimate Schema 1, including one
    declared generated-output source. Confirm malformed intervals/fields fail,
    a disclosed very large estimate passes, legacy Requirements warn, and an
    unstarted legacy Design blocks. Re-estimate Source/tasks at 24% and exactly
    25% upper-bound growth: 24% continues, 25% returns to Plan revision; a new
    production path family does likewise. At final acceptance, confirm Git
    actual additions/churn/files exclude tests/spec/review/docs and appear
    beside Design without numeric variance becoming a failure.
20. Generate Scope Contract Schema 1 with core-only, core+committed+deferred,
    and MUST-backed constraint examples. Confirm missing/duplicate/unknown
    schema, malformed CAP/Admission/ref rows, incomplete FR/SC coverage,
    deferred refs, and non-core Core completion refs fail. An unstarted legacy
    Approved Requirements artifact must return to `specify --revise`; checked
    tasks, implementation review, or real production delta make it warning-only
    and read-only. Confirm Plan has no copied scope table and Source/tasks/
    implementation reviewers cover every admitted CAP through FR/SC, reject
    deferred CAPs, and preserve Retained baseline. In both Claude and Codex,
    ask whether an existing `SessionStream` should add Resume or also replace
    the complete typed API: the card must state that the current `request_id`
    burden remains under the minimum option, recommend Resume only, and defer
    the complete interface refactor without an item-by-item approval prompt.
21. Exercise the Requirements Test Control Policy Exceptions contract first:
    canonical Mode `none`, an approved continuous TCE set for every Rule token,
    exactly one concluded `R<n>` per row (with bundled rows allowed to share),
    exact Plan copy, and legacy Approved
    Requirements implicit-none behavior. Missing/malformed rows, unknown or
    structural-floor Rules, missing decisions, copy drift, concrete hook
    pre-registration, and non-source-auditable replacements must block. Then
    exercise both Test Control modes. `none` must use the exact all-`none` row.
    For `isolated`, verify consecutive TC IDs, `src/testonly` plus terminal
    namespace/module, typed per-instance RAII, one dedicated default-OFF
    `*_ENABLE_TEST_HOOKS` switch, a tracked non-symlink test-only-named
    validator, fixed `default-off|explicit-on` lanes, and concrete consumer and
    default-proof tasks. The default lane must omit the switch entirely; an
    explicit OFF argument, default-ON/nonzero definition, fake namespace alias,
    echo validator, runtime toggle, or product-API test parameter must fail or
    receive a semantic-review blocker as appropriate. Confirm every v3 verdict
    has Test Control Audit and REV-FINAL freshly reruns both lanes into the two
    canonical evidence files. Missing, swapped, stale, wrong-subject evidence,
    post-seal source drift, and IA control rewiring must fail. Finally present
    xclaw-style `Open(path, CheckpointCoordinatorOptions)`, generic observer/
    options, injected `AgentHost` constructor, fake namespace/alias, echo
    validator, and runtime-toggle proposals to both agents; they must reject
    hidden product seams without claiming regex proves arbitrary-language
    semantics. Explicit ON remains an opt-in test build; do not invent a
    packaging hard-fail or external signing/CI requirement. Make an echo-only
    validator report literal/precomputed manifest hashes: fresh review must
    reject it and require re-enumeration from the exact Subject clone's actual
    build/test and applicable install/export/symbol outputs.
    Confirm delivery metrics report Production and Test-Control scale
    separately without forcing disjoint attribution: touchpoint/build-wiring
    files remain Production, their dedicated hook lines may also count toward
    Test-Control scale, and only default-OFF-proven surface-only objects,
    validators, and ordinary tests are excluded from Production.
22. Give Claude and Codex the same request containing
    `Result<RequestHandle> Submit(...)`, `WorkerThread`, and `Cancel()`. Confirm
    each generated Schema 1 spec contains none of those prospective tokens but
    preserves non-waiting submission, synchronous accepted/rejected distinction,
    per-request cancellation with one terminal state, and exactly one internal
    execution thread per instance serializing the agreed task set. Confirm Plan
    independently chooses a complete concrete API/type/class/path shape. A pure
    rename or semantically equivalent signature/return-type change must route to
    `gatespec.plan --revise`; a Plan-bounded internal name may be chosen in
    Source/IA; removing cancellation, changing submission synchrony/error
    semantics, or changing the thread/resource constraint must route to
    `gatespec.specify --revise`. Exercise checker positive anchors and negative
    raw Input/source-fence/signature/generic/class/interface cases, then verify
    Draft and unimplemented legacy specs block while progressed and Accepted
    legacy deliveries remain warning-only/read-only. Finally render both agents'
    installed skills and confirm the abstraction and routing rules are identical.

Run `bash tests/run-all.sh` on Linux and macOS and verify `git status` remains
clean. If a hook or artifact contract changed, retain the old upper version
bound until compatibility is restored.

The optional local `spec-kit/` reference checkout is gitignored and
extension-ignored. It is read-only comparison material, never a vendored
dependency.
