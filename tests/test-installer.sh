#!/usr/bin/env bash
# Renderer, manifest, and scratch extension-install smoke tests.
# shellcheck disable=SC2016 # Assertions match literal Markdown backticks.

set -u
cd "$(dirname "$0")/.." || exit 1
REPO="$PWD"
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gatespec-installer-tests.XXXXXX") || exit 1
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM
PASS=0
FAIL=0

ok() { PASS=$((PASS + 1)); echo "✓ $1"; }
not_ok() { FAIL=$((FAIL + 1)); echo "✗ $1"; }

# Argument validation must happen before the first write.
mkdir -p "$TEST_TMP/invalid-home"
if HOME="$TEST_TMP/invalid-home" bash "$REPO/install.sh" --agent invalid > "$TEST_TMP/out" 2>&1; then
  not_ok "invalid renderer target is rejected"
elif [[ -e "$TEST_TMP/invalid-home/.gatespec" || -e "$TEST_TMP/invalid-home/.agents" || -e "$TEST_TMP/invalid-home/.claude" ]]; then
  not_ok "invalid arguments caused writes"
else
  ok "all arguments are validated before writes"
fi

# A conflicting custom reviewer is a fatal preflight error. Nothing else may
# be installed before the user chooses --force.
CONFLICT_HOME="$TEST_TMP/conflict-home"
mkdir -p "$CONFLICT_HOME/.codex/agents"
printf '%s\n' 'user-owned reviewer' > "$CONFLICT_HOME/expected-reviewer"
cp "$CONFLICT_HOME/expected-reviewer" "$CONFLICT_HOME/.codex/agents/gatespec-reviewer.toml"
if HOME="$CONFLICT_HOME" bash "$REPO/install.sh" --agent codex > "$TEST_TMP/out" 2>&1; then
  not_ok "conflicting reviewer adapter is rejected without --force"
elif ! cmp -s "$CONFLICT_HOME/expected-reviewer" "$CONFLICT_HOME/.codex/agents/gatespec-reviewer.toml" ||
     [[ -e "$CONFLICT_HOME/.gatespec" || -e "$CONFLICT_HOME/.agents" || -e "$CONFLICT_HOME/.claude" ]] ||
     ! grep -F 'reviewer adapter conflict' "$TEST_TMP/out" >/dev/null; then
  not_ok "reviewer conflict preflight preserved no-write behavior"
else
  ok "reviewer conflict is detected before any installer write"
fi

if HOME="$CONFLICT_HOME" bash "$REPO/install.sh" --agent codex --force > "$TEST_TMP/out" 2>&1; then
  adapter_backup=$(find "$CONFLICT_HOME/.codex/agents" -type f -name 'gatespec-reviewer.toml.bak.*' | head -1)
  if cmp -s "$REPO/reviewers/codex/gatespec-reviewer.toml" "$CONFLICT_HOME/.codex/agents/gatespec-reviewer.toml" &&
     [[ -n "$adapter_backup" ]] && cmp -s "$CONFLICT_HOME/expected-reviewer" "$adapter_backup" &&
     [[ ! -e "$CONFLICT_HOME/.claude" ]] &&
     grep -F 'Start a new Codex session to load this agent definition' "$TEST_TMP/out" >/dev/null; then
    ok "--force backs up and atomically replaces only the selected reviewer adapter"
  else
    not_ok "forced reviewer adapter replacement or backup"
  fi
else
  not_ok "--force reviewer adapter installation"
  sed 's/^/    /' "$TEST_TMP/out"
fi

backups_before=$(find "$CONFLICT_HOME/.codex/agents" -type f -name 'gatespec-reviewer.toml.bak.*' | wc -l | tr -d ' ')
if HOME="$CONFLICT_HOME" bash "$REPO/install.sh" --agent codex > "$TEST_TMP/out" 2>&1; then
  backups_after=$(find "$CONFLICT_HOME/.codex/agents" -type f -name 'gatespec-reviewer.toml.bak.*' | wc -l | tr -d ' ')
  if [[ "$backups_before" -eq 1 && "$backups_after" -eq "$backups_before" ]]; then
    ok "identical reviewer adapter reinstall is idempotent"
  else
    not_ok "idempotent reviewer reinstall created another backup"
  fi
else
  not_ok "identical reviewer adapter reinstall"
fi

# Render both integrations into an isolated home.
RENDER_HOME="$TEST_TMP/render-home"
mkdir -p "$RENDER_HOME"
if HOME="$RENDER_HOME" bash "$REPO/install.sh" --agent all > "$TEST_TMP/out" 2>&1; then
  ok "Claude and Codex skills render in an isolated target"
else
  not_ok "Claude/Codex rendering failed"
  sed 's/^/    /' "$TEST_TMP/out"
fi

if grep -F 'Start a new Claude Code session to load this agent definition' "$TEST_TMP/out" >/dev/null &&
   grep -F 'Start a new Codex session to load this agent definition' "$TEST_TMP/out" >/dev/null; then
  ok "installer explains that changed reviewer definitions need a new session"
else
  not_ok "reviewer adapter reload guidance"
fi

expected=0
for command_source in commands/speckit.gatespec.*.md; do
  [[ -f "$command_source" ]] && expected=$((expected + 1))
done
claude_count=$(find "$RENDER_HOME/.claude/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
codex_count=$(find "$RENDER_HOME/.agents/skills" -name SKILL.md 2>/dev/null | wc -l | tr -d ' ')
if [[ "$claude_count" -eq "$expected" && "$codex_count" -eq "$expected" ]]; then
  ok "every command renders for both agents ($expected each)"
else
  not_ok "rendered skill count differs (Claude=$claude_count, Codex=$codex_count, expected=$expected)"
fi

bad_frontmatter=0
while IFS= read -r skill; do
  if ! awk '
    NR == 1 && $0 != "---" {bad=1}
    NR == 2 && $0 !~ /^name: "[^"]+"$/ {bad=1}
    NR == 3 && $0 !~ /^description: "([^"\\]|\\.)+"$/ {bad=1}
    NR == 4 && $0 != "---" {bad=1}
    END {exit bad}
  ' "$skill"; then
    echo "bad frontmatter: $skill"
    bad_frontmatter=1
  fi
done < <(find "$RENDER_HOME/.claude/skills" "$RENDER_HOME/.agents/skills" -name SKILL.md | sort)
if [[ "$bad_frontmatter" -eq 0 ]]; then ok "rendered YAML frontmatter is quoted and well formed"; else not_ok "frontmatter validation"; fi

if grep -R -E '\{SCRIPT\}|__SPECKIT_COMMAND_[A-Z0-9_]+__' "$RENDER_HOME/.claude/skills" "$RENDER_HOME/.agents/skills" >/dev/null 2>&1; then
  not_ok "renderer left unresolved tokens"
else
  ok "renderer leaves zero script/command tokens"
fi

claude_plan="$RENDER_HOME/.claude/skills/speckit-gatespec-plan/SKILL.md"
codex_plan="$RENDER_HOME/.agents/skills/speckit-gatespec-plan/SKILL.md"
claude_spec="$RENDER_HOME/.claude/skills/speckit-gatespec-specify/SKILL.md"
codex_spec="$RENDER_HOME/.agents/skills/speckit-gatespec-specify/SKILL.md"
claude_review_tasks="$RENDER_HOME/.claude/skills/speckit-gatespec-review-tasks/SKILL.md"
claude_review_source="$RENDER_HOME/.claude/skills/speckit-gatespec-review-source-design/SKILL.md"
claude_review_implementation="$RENDER_HOME/.claude/skills/speckit-gatespec-review-implementation/SKILL.md"
codex_review_tasks="$RENDER_HOME/.agents/skills/speckit-gatespec-review-tasks/SKILL.md"
codex_review_source="$RENDER_HOME/.agents/skills/speckit-gatespec-review-source-design/SKILL.md"
codex_review_implementation="$RENDER_HOME/.agents/skills/speckit-gatespec-review-implementation/SKILL.md"
claude_source="$RENDER_HOME/.claude/skills/speckit-gatespec-source-design/SKILL.md"
codex_source="$RENDER_HOME/.agents/skills/speckit-gatespec-source-design/SKILL.md"
claude_accept="$RENDER_HOME/.claude/skills/speckit-gatespec-accept-implementation/SKILL.md"
codex_accept="$RENDER_HOME/.agents/skills/speckit-gatespec-accept-implementation/SKILL.md"
claude_refine="$RENDER_HOME/.claude/skills/speckit-gatespec-refine-tasks/SKILL.md"
codex_refine="$RENDER_HOME/.agents/skills/speckit-gatespec-refine-tasks/SKILL.md"
claude_check_tasks="$RENDER_HOME/.claude/skills/speckit-gatespec-check-tasks/SKILL.md"
codex_check_tasks="$RENDER_HOME/.agents/skills/speckit-gatespec-check-tasks/SKILL.md"
claude_reviewer="$RENDER_HOME/.claude/agents/gatespec-reviewer.md"
codex_reviewer="$RENDER_HOME/.codex/agents/gatespec-reviewer.toml"
dollar='$'
if cmp -s "$REPO/constraints.md" "$RENDER_HOME/.gatespec/constraints.md" &&
   grep -F '**Constraint Basis 正文使用中文。**' "$RENDER_HOME/.gatespec/constraints.md" >/dev/null; then
  ok "installed personal constraints exactly match the Chinese repository source"
else
  not_ok "installed personal constraints content"
fi

if grep -F 'write every human-readable field value in Simplified' "$claude_spec" >/dev/null &&
   grep -F 'write every human-readable field value in Simplified' "$codex_spec" >/dev/null; then
  ok "rendered specify skills require Chinese Constraint Basis values"
else
  not_ok "rendered Constraint Basis language rule"
fi

batching_contract_ok=1
for skill in "$claude_spec" "$codex_spec" "$claude_plan" "$codex_plan"; do
  for rule in \
    'load at most four.' \
    'ephemeral dependency graph' \
    'batch recommendation shortcuts do not cover this decision' \
    'first in the next batch' \
    'next round at most N'; do
    grep -F "$rule" "$skill" >/dev/null || batching_contract_ok=0
  done
done
for rule in \
  'R1=A; R2=recommended' \
  'decision shortcut never approves' \
  'do not rewrite concluded Clarifications that lack IDs'; do
  grep -F "$rule" "$claude_spec" >/dev/null || batching_contract_ok=0
  grep -F "$rule" "$codex_spec" >/dev/null || batching_contract_ok=0
done
for rule in \
  'D1=A; D2=recommended' \
  'Batch grouping and triage buckets are conversational only'; do
  grep -F "$rule" "$claude_plan" >/dev/null || batching_contract_ok=0
  grep -F "$rule" "$codex_plan" >/dev/null || batching_contract_ok=0
done
if [[ "$batching_contract_ok" -eq 1 ]]; then
  ok "rendered Claude/Codex skills preserve the adaptive batching contract"
else
  not_ok "rendered adaptive batching contract"
fi

triage_contract_ok=1
for skill in "$claude_spec" "$codex_spec"; do
  for rule in \
    '**Blocking human decision**' \
    '**Technical matter deferred to Design**' \
    'Technology choice alone never makes an item blocking.' \
    'not as a labeled questionnaire' \
    'Use domain-native roles and actions.' \
    'Keep relevant technical vocabulary intact' \
    'invent a click, button' \
    'Do not render standalone' \
    'explain R<n>' \
    'hash-only refresh is not progress'; do
    grep -F "$rule" "$skill" >/dev/null || triage_contract_ok=0
  done
  grep -F 'in this exact cognitive order' "$skill" >/dev/null && triage_contract_ok=0
  grep -F 'deleting Technical basis identifiers' "$skill" >/dev/null && triage_contract_ok=0
done
for skill in "$claude_plan" "$codex_plan"; do
  # shellcheck disable=SC2016 # Match literal Markdown backticks.
  for rule in \
    '**Human decision**' \
    '**Engineering determination**' \
    '**Implementation Freedom**' \
    'It gets no' \
    'dominated or forbidden foil' \
    'complex or high-risk card consumes the full' \
    'not as a labeled questionnaire' \
    'Use domain-native roles and actions.' \
    'Keep relevant technical vocabulary intact' \
    'invent a click, button' \
    'Do not render standalone' \
    'explain D<n>' \
    'does not change the artifact schema'; do
    grep -F "$rule" "$skill" >/dev/null || triage_contract_ok=0
  done
  grep -F 'in this exact cognitive order' "$skill" >/dev/null && triage_contract_ok=0
  grep -F 'deleting Technical basis identifiers' "$skill" >/dev/null && triage_contract_ok=0
done
if [[ "$triage_contract_ok" -eq 1 ]]; then
  ok "rendered Claude/Codex skills preserve engineering-scenario decision triage"
else
  not_ok "rendered engineering-scenario decision triage contract"
fi

scope_contract_ok=1
for skill in "$claude_spec" "$codex_spec"; do
  for rule in \
    '**Scope Contract Schema**: 1' \
    'Primary outcome' \
    'deferred by default' \
    'current workflow' \
    'smallest option that fully delivers' \
    'CAP IDs do not enter tasks Closure'; do
    grep -F "$rule" "$skill" >/dev/null || scope_contract_ok=0
  done
done
for skill in "$claude_plan" "$codex_plan"; do
  for rule in \
    'Do not copy its schema or table into plan.md' \
    'non-deferred CAP and an FR' \
    'Retained baseline' \
    'deferred CAPs remain absent'; do
    grep -F "$rule" "$skill" >/dev/null || scope_contract_ok=0
  done
done
for skill in "$claude_source" "$codex_source" "$claude_refine" "$codex_refine" \
             "$claude_review_source" "$codex_review_source" \
             "$claude_review_tasks" "$codex_review_tasks" \
             "$claude_review_implementation" "$codex_review_implementation"; do
  grep -F 'non-deferred CAP' "$skill" >/dev/null || scope_contract_ok=0
  grep -F 'Retained baseline' "$skill" >/dev/null || scope_contract_ok=0
done
for reviewer in "$claude_reviewer" "$codex_reviewer"; do
  grep -F 'An AI-discovered adjacent improvement remains deferred' "$reviewer" >/dev/null || scope_contract_ok=0
  grep -F 'concrete Primary outcome scenario' "$reviewer" >/dev/null || scope_contract_ok=0
  grep -F 'opportunistically removing a retained' "$reviewer" >/dev/null || scope_contract_ok=0
done
for rule in \
  '**Scope Contract Schema**: 1' \
  '## Scope Contract *(gatespec: mandatory)*' \
  '**Primary outcome**' \
  '**Core completion refs**' \
  '**Retained baseline**' \
  '| Capability | Admission | Spec refs | Boundary rationale |'; do
  grep -F "$rule" "$REPO/templates/gatespec-spec-template.md" >/dev/null || scope_contract_ok=0
done
if grep -F '**Scope Contract Schema**:' "$REPO/templates/gatespec-plan-template.md" >/dev/null; then
  scope_contract_ok=0
fi
if [[ "$scope_contract_ok" -eq 1 ]]; then
  ok "rendered skills, reviewers, and templates preserve scope admission and conservation"
else
  not_ok "rendered Scope Contract and conservation rules"
fi

design_evidence_ok=1
for skill in "$claude_plan" "$codex_plan"; do
  for rule in \
    '**Design Evidence Schema**: 1' \
    'review-source completeness walkthrough' \
    'language-native skeleton of key' \
    'Mermaid and other diagrams are' \
    'Approved-Design created before the Implementation Review Contract or Design'; do
    grep -F "$rule" "$skill" >/dev/null || design_evidence_ok=0
  done
  grep -F '## Architecture Blueprint' "$skill" >/dev/null && design_evidence_ok=0
done
for rule in \
  '**Design Evidence Schema**: 1' \
  '**Repository anchors**' \
  '**Core contract skeleton**' \
  '**Failure / recovery contract**'; do
  grep -F "$rule" "$REPO/templates/gatespec-plan-template.md" >/dev/null || design_evidence_ok=0
done
for reviewer in "$claude_reviewer" "$codex_reviewer"; do
  grep -F 'Design Evidence Schema 1' "$reviewer" >/dev/null || design_evidence_ok=0
done
if [[ "$design_evidence_ok" -eq 1 ]]; then
  ok "plan/template/reviewer preserve the structured design-evidence contract"
else
  not_ok "structured design-evidence contract"
fi

delivery_estimate_ok=1
for skill in "$claude_spec" "$codex_spec"; do
  for rule in \
    '**Delivery Estimate Schema**: 1' \
    'independently deliverable' \
    'generated: <output path> <- <source path> via <generator>' \
    'all three Delivery Estimate ranges and confidence'; do
    grep -F "$rule" "$skill" >/dev/null || delivery_estimate_ok=0
  done
done
for skill in "$claude_plan" "$codex_plan"; do
  for rule in \
    '**Delivery Estimate Schema**: 1' \
    '`within`, `expanded`, or `reduced`' \
    'There is no size, file-count, or checkpoint limit' \
    'all three Design estimate ranges with confidence'; do
    grep -F "$rule" "$skill" >/dev/null || delivery_estimate_ok=0
  done
done
for skill in "$claude_source" "$codex_source" "$claude_refine" "$codex_refine" \
             "$claude_review_tasks" "$codex_review_tasks"; do
  grep -F 'new_upper * 100 >= design_upper * 125' "$skill" >/dev/null || delivery_estimate_ok=0
  grep -F 'production path family' "$skill" >/dev/null || delivery_estimate_ok=0
done
for reviewer in "$claude_reviewer" "$codex_reviewer"; do
  grep -F 'new_upper * 100 >= design_upper * 125' "$reviewer" >/dev/null || delivery_estimate_ok=0
  grep -F 'Growth below 25%' "$reviewer" >/dev/null || delivery_estimate_ok=0
done
for skill in "$claude_accept" "$codex_accept"; do
  grep -F 'actual Production additions' "$skill" >/dev/null || delivery_estimate_ok=0
  grep -F 'size alone' "$skill" >/dev/null || delivery_estimate_ok=0
done
test_control_protocol_ok=1
for skill in "$claude_source" "$codex_source" "$claude_review_source" "$codex_review_source"; do
  for rule in \
    'Test-Control-Mode' \
    'Test-Control-Closure-SHA256' \
    'Test-Control-Subject-Manifest-SHA256' \
    'Default-OFF-Evidence-SHA256' \
    'Explicit-ON-Evidence-SHA256' \
    'not-applicable'; do
    grep -F -- "$rule" "$skill" >/dev/null || test_control_protocol_ok=0
  done
done
for rule in \
  '**Delivery Estimate Schema**: 1' \
  '**Production additions**' \
  '**Production churn**' \
  '**Production files**' \
  'generated: output/path <- source/path via generator'; do
  grep -F "$rule" "$REPO/templates/gatespec-spec-template.md" >/dev/null || delivery_estimate_ok=0
  grep -F "$rule" "$REPO/templates/gatespec-plan-template.md" >/dev/null || delivery_estimate_ok=0
done
if [[ "$delivery_estimate_ok" -eq 1 ]]; then
  ok "rendered skills, templates, and both reviewer adapters preserve delivery estimates and the 25% boundary"
else
  not_ok "rendered delivery-estimate and drift-review contract"
fi

source_protocol_ok=1
for skill in "$claude_source" "$codex_source"; do
  for rule in \
    'contracts/source-design.md' \
    'Any completed implementation task' \
    'refuses first enable' \
    'Source-Design-Reviewed-SHA256' \
    'Original-Implementation-Baseline' \
    'binary patch' \
    'compensating commit' \
    'revalidations/E<n>' \
    'every previously preserved PASS Subject' \
    'at most 20 lines'; do
    grep -F "$rule" "$skill" >/dev/null || source_protocol_ok=0
  done
done
for skill in "$claude_accept" "$codex_accept"; do
  for rule in \
    'acceptance-candidate' \
    'Final-Delta-SHA256' \
    'metadata-only commit' \
    'A rejection writes nothing' \
    'what I am least confident about'; do
    grep -F "$rule" "$skill" >/dev/null || source_protocol_ok=0
  done
done
for skill in "$claude_source" "$codex_source"; do
  grep -F 'must not register, name, or' "$skill" >/dev/null || test_control_protocol_ok=0
  grep -F 'production hook' "$skill" >/dev/null || test_control_protocol_ok=0
  grep -F 'task-stage registrations' "$skill" >/dev/null || test_control_protocol_ok=0
done
for skill in "$claude_review_source" "$codex_review_source"; do
  grep -F 'without registering any exact control' "$skill" >/dev/null || test_control_protocol_ok=0
  grep -F 'defer exact registration to native tasks' "$skill" >/dev/null || test_control_protocol_ok=0
done
for reviewer in "$claude_reviewer" "$codex_reviewer"; do
  for rule in 'REV-SOURCE' 'Source-Design-Reviewed-SHA256' 'Implementation-Adjustments-SHA256' 'Final-Delta-SHA256'; do
    grep -F "$rule" "$reviewer" >/dev/null || source_protocol_ok=0
  done
done
if [[ "$source_protocol_ok" -eq 1 ]]; then
  ok "rendered Source Design, Protocol v3, IA, and final acceptance contracts are complete"
else
  not_ok "Source Design / Protocol v3 / acceptance rendered contract"
fi

for skill in "$claude_spec" "$codex_spec"; do
  for rule in \
    '### Test Control Policy Exceptions *(gatespec: mandatory)*' \
    'Replacement source-auditable mechanism' \
    'source-root' \
    'validator-path-marker' \
    'structural/lifecycle floor'; do
    grep -F -- "$rule" "$skill" >/dev/null || test_control_protocol_ok=0
  done
done
for skill in "$claude_plan" "$codex_plan"; do
  for rule in \
    '## Test Control Policy *(gatespec: mandatory)*' \
    '## Test Control Policy Exceptions *(gatespec: mandatory)*' \
    '**Protocol Version**: `3`' \
    'active/unaccepted' \
    'cannot be upgraded by retask' \
    '*_ENABLE_TEST_HOOKS' \
    'bash <validator> --gatespec-lane default-off|explicit-on' \
    '**Production Readability Contract**'; do
    grep -F -- "$rule" "$skill" >/dev/null || test_control_protocol_ok=0
  done
done
for skill in "$claude_refine" "$codex_refine"; do
  for rule in \
    '## GateSpec Test Control Closure *(gatespec: mandatory)*' \
    '| Control | Verification gap / production invariant | Test-only surface | Production touchpoint | Allowed effect / lifetime | Build switch / validator | Consumer tasks/tests | Default-build proof task |' \
    '**Mode**: `none|isolated`' \
    'TC-001' \
    '/src/testonly' \
    'per-instance' \
    'default-off omits the option'; do
    grep -F -- "$rule" "$skill" >/dev/null || test_control_protocol_ok=0
  done
done
for skill in "$claude_review_tasks" "$codex_review_tasks" \
             "$claude_review_implementation" "$codex_review_implementation"; do
  for rule in \
    '## Test Control Audit' \
    '**Test-Control-Scale**' \
    'Test-Control-Mode' \
    'Test-Control-Closure-SHA256' \
    'Test-Control-Subject-Manifest-SHA256' \
    'Default-OFF-Evidence-SHA256' \
    'Explicit-ON-Evidence-SHA256' \
    'Crossing both requires both Rules' \
    '`control-model` never authorizes production-side mechanics'; do
    grep -F -- "$rule" "$skill" >/dev/null || test_control_protocol_ok=0
  done
done
for skill in "$claude_accept" "$codex_accept"; do
  for rule in \
    'Test-Control-Mode' \
    'Test-Control-Closure-SHA256' \
    'Test-Control-Subject-Manifest-SHA256' \
    'Default-OFF-Evidence-SHA256' \
    'Explicit-ON-Evidence-SHA256'; do
    grep -F -- "$rule" "$skill" >/dev/null || test_control_protocol_ok=0
  done
done
for reviewer in "$claude_reviewer" "$codex_reviewer"; do
  for rule in \
    '# GateSpec Test Control Evidence' \
    '## Validator Results' \
    'omitted-default-off' \
    'production-install-package-when-present' \
    'test-only-surface' \
    'Open(path, CheckpointCoordinatorOptions)' \
    'generic observer/options' \
    'AgentHost' \
    'echo-only validator' \
    'fake terminal `testonly`' \
    'runtime activation' \
    'without registering a concrete' \
    'actual configure' \
    'Literal/precomputed hashes' \
    'Crossing both requires both Rules' \
    '`control-model` never authorizes production-side mechanics'; do
    grep -F -- "$rule" "$reviewer" >/dev/null || test_control_protocol_ok=0
  done
done
grep -F 'Source cannot name' "$claude_reviewer" >/dev/null || test_control_protocol_ok=0
grep -F 'exact hook registration remains task-stage' "$codex_reviewer" >/dev/null || \
  test_control_protocol_ok=0
for skill in "$claude_check_tasks" "$codex_check_tasks"; do
  grep -F 'This hook checks the declared structure' "$skill" >/dev/null || test_control_protocol_ok=0
  grep -F 'fresh review still rejects fake namespace isolation' "$skill" >/dev/null || test_control_protocol_ok=0
done
for rule in \
  '## Test Control Policy *(gatespec: mandatory)*' \
  '**Policy Schema**: `1`' \
  '**Protocol Version**: `3`'; do
  grep -F -- "$rule" "$REPO/templates/gatespec-plan-template.md" >/dev/null || test_control_protocol_ok=0
done
for rule in \
  '### Test Control Policy Exceptions *(gatespec: mandatory)*' \
  '| Exception | Rule | Approved requirements decision | Replacement source-auditable mechanism | Reason / consequence |'; do
  grep -F -- "$rule" "$REPO/templates/gatespec-spec-template.md" >/dev/null || test_control_protocol_ok=0
done
grep -F -- '## Test Control Policy Exceptions *(gatespec: mandatory)*' \
  "$REPO/templates/gatespec-plan-template.md" >/dev/null || test_control_protocol_ok=0
if [[ "$test_control_protocol_ok" -eq 1 ]]; then
  ok "rendered skills, templates, and reviewers preserve Protocol v3 Test Controls"
else
  not_ok "Protocol v3 Test Control renderer contract"
fi

closure_protocol_ok=1
for skill in "$claude_refine" "$codex_refine"; do
  for rule in \
    'The only persistent path this command may create or modify is that exact' \
    'all ten audit categories' \
    '## GateSpec Checkpoint Closure *(gatespec: mandatory)*' \
    '## GateSpec Prior Review Closure *(gatespec: mandatory)*' \
    '.gatespec/archive/*-retask/reviews/REV-TASKS/' \
    'grandfathered no-op' \
    'raw UTF-8 bytes of the complete item'; do
    grep -F "$rule" "$skill" >/dev/null || closure_protocol_ok=0
  done
done
# Literal Markdown backticks are intentional protocol text.
# shellcheck disable=SC2016
for rule in \
  'retask-eligible' \
  'UTC-YYYYMMDDTHHMMSSZ' \
  'Task-Handoff-Commit' \
  'Preserved-Reviews-SHA256' \
  'A collision blocks: never overwrite' \
  'do not create a manifest or retask receipt' \
  'do not call ordinary `tasks-structure`' \
  'gatespec: archive REV-TASKS cycle for retask' \
  'Never push'; do
  grep -F "$rule" "$claude_plan" >/dev/null || closure_protocol_ok=0
  grep -F "$rule" "$codex_plan" >/dev/null || closure_protocol_ok=0
done
if [[ "$closure_protocol_ok" -eq 1 ]]; then
  ok "rendered refine/retask skills preserve Closure and safe regeneration contracts"
else
  not_ok "rendered Closure/refine/retask contract"
fi

if grep -F 'Only approval-eligible human decisions belong here' "$REPO/templates/gatespec-spec-template.md" >/dev/null &&
   grep -F -- '- **Scenario**:' "$REPO/templates/gatespec-plan-template.md" >/dev/null &&
   grep -F -- '- **Fixed boundary**:' "$REPO/templates/gatespec-plan-template.md" >/dev/null &&
   grep -F -- '- **Why this needs you**:' "$REPO/templates/gatespec-plan-template.md" >/dev/null &&
   grep -F -- '- **Technical basis**:' "$REPO/templates/gatespec-plan-template.md" >/dev/null &&
   grep -F 'approved human decisions, recorded engineering' "$claude_reviewer" >/dev/null &&
   grep -F 'approved human decisions, recorded engineering' "$codex_reviewer" >/dev/null; then
  ok "templates and reviewer adapters preserve the decision-triage taxonomy"
else
  not_ok "template/reviewer decision-triage taxonomy"
fi

if grep -F '/speckit-tasks' "$claude_plan" >/dev/null &&
   grep -F '/speckit-gatespec-source-design' "$claude_plan" >/dev/null &&
   grep -F '/speckit-gatespec-review-source-design' "$claude_source" >/dev/null &&
   grep -F '/speckit-gatespec-plan' "$claude_spec" >/dev/null &&
   grep -F "${dollar}speckit-tasks" "$codex_plan" >/dev/null &&
   grep -F "${dollar}speckit-gatespec-source-design" "$codex_plan" >/dev/null &&
   grep -F "${dollar}speckit-gatespec-review-source-design" "$codex_source" >/dev/null &&
   grep -F "${dollar}speckit-gatespec-accept-implementation" "$codex_plan" >/dev/null &&
   grep -F "${dollar}speckit-gatespec-plan" "$codex_spec" >/dev/null; then
  ok "Claude and Codex receive their own command-reference syntax"
else
  not_ok "agent-specific command references"
fi

if grep -F "$REPO/scripts/bash/check-gate.sh" "$claude_plan" >/dev/null &&
   grep -F "$REPO/templates/gatespec-spec-template.md" "$codex_spec" >/dev/null; then
  ok "rendered extension paths are absolute"
else
  not_ok "absolute repository path rendering"
fi

if cmp -s "$REPO/reviewers/claude/gatespec-reviewer.md" "$claude_reviewer" &&
   cmp -s "$REPO/reviewers/codex/gatespec-reviewer.toml" "$codex_reviewer"; then
  ok "Claude and Codex reviewer adapters install from repository sources"
else
  not_ok "reviewer adapter installation content"
fi

claude_agent_fields=$(awk 'NR == 1 && $0 == "---" {inside=1; next} inside && /^---$/ {exit} inside && NF {n++} END {print n+0}' "$claude_reviewer" 2>/dev/null)
if [[ "$claude_agent_fields" -eq 4 ]] &&
   grep -Fx 'name: gatespec-reviewer' "$claude_reviewer" >/dev/null &&
   grep -Fx 'tools: Read, Grep, Glob, Bash' "$claude_reviewer" >/dev/null &&
   grep -Fx 'isolation: worktree' "$claude_reviewer" >/dev/null &&
   ! grep -E '^tools:.*(Write|Edit)' "$claude_reviewer" >/dev/null; then
  ok "Claude reviewer uses official worktree isolation and no source-edit tool"
else
  not_ok "Claude reviewer frontmatter/tool boundary"
fi

if grep -Fx 'name = "gatespec_reviewer"' "$codex_reviewer" >/dev/null &&
   grep -Fx 'sandbox_mode = "workspace-write"' "$codex_reviewer" >/dev/null &&
   grep -Fx 'developer_instructions = """' "$codex_reviewer" >/dev/null; then
  ok "Codex reviewer uses the supported custom-agent schema"
else
  not_ok "Codex reviewer custom-agent schema"
fi

reviewer_safety_ok=1
for reviewer in "$claude_reviewer" "$codex_reviewer"; do
  # Literal Markdown backticks must not be interpreted by the shell.
  # shellcheck disable=SC2016
  for rule in \
    'Accept exactly one value: the absolute review-request path' \
    '<feature-root>/.gatespec/reviews/<REV-ID>/round-<NN>-request.md' \
    'extra field, H2, or prose' \
    '**Spec-Content-SHA256**' \
    '**Design-Attachments-SHA256**' \
    '**Tasks-Definition-SHA256**' \
    '**Previous-Verdict-SHA256**' \
    "sed '/^## Gate Approval/,\$d'" \
    '<feature-relative-path><TAB><file-SHA256><LF>' \
    'every raw byte before its final field line' \
    'C-sorted exact output of' \
    'Implementation Review Contract' \
    'Tests must contain exactly that mapping cell' \
    'from the first task through immediately' \
    'walk every earlier `- BLOCKER:` item' \
    'all approved requirements, stories, acceptance' \
    'input validation and security boundaries' \
    'execute every Required Tests bullet separately' \
    'unsafe, unavailable' \
    'style only in Observations' \
    'modify product source' \
    'git status --porcelain=v1 --untracked-files=all' \
    'prefixed `generated-`' \
    'Not run — task-plan review' \
    '**Verdict-SHA256**'; do
    grep -F "$rule" "$reviewer" >/dev/null || reviewer_safety_ok=0
  done
done
if [[ "$reviewer_safety_ok" -eq 1 ]]; then
  ok "reviewer adapters are self-contained across hashes, judgment, tests, and verdict output"
else
  not_ok "self-contained reviewer adapter contract"
fi

# Literal Markdown backticks must not be interpreted by the shell.
# shellcheck disable=SC2016
if grep -F 'platform-provided' "$claude_reviewer" >/dev/null &&
   grep -F 'Do not create or remove a Git worktree' "$claude_reviewer" >/dev/null &&
   grep -F 'Never run `git worktree add`' "$codex_reviewer" >/dev/null &&
   grep -F 'git clone --local --no-hardlinks --no-checkout' "$codex_reviewer" >/dev/null &&
   grep -F 'git checkout --detach <Subject-Commit>' "$codex_reviewer" >/dev/null; then
  ok "Claude and Codex use platform-safe isolated checkout strategies"
else
  not_ok "platform-specific reviewer checkout isolation"
fi

# Literal Markdown backticks must not be interpreted by the shell.
# shellcheck disable=SC2016
if grep -F 'dispatch `gatespec-reviewer` as' "$claude_review_tasks" >/dev/null &&
   grep -F 'dispatch `gatespec-reviewer` as' "$claude_review_source" >/dev/null &&
   grep -F 'new top-level Claude Code session' "$claude_review_implementation" >/dev/null &&
   grep -F 'do not carry `--scope` into manual mode' "$claude_review_implementation" >/dev/null &&
   grep -F 'In manual `--request` mode, this command is reviewer-only' "$claude_review_implementation" >/dev/null &&
   grep -F 'set `Reviewer-Platform` to `manual-claude`' "$claude_review_tasks" >/dev/null &&
   grep -F 'spawn the custom agent' "$codex_review_tasks" >/dev/null &&
   grep -F 'spawn the custom agent' "$codex_review_source" >/dev/null &&
   grep -F '`gatespec_reviewer` with `fork_turns="none"`' "$codex_review_tasks" >/dev/null &&
   grep -F 'new top-level Codex session' "$codex_review_implementation" >/dev/null &&
   grep -F 'do not carry `--scope` into manual mode' "$codex_review_implementation" >/dev/null &&
   grep -F 'In manual `--request` mode, this command is reviewer-only' "$codex_review_implementation" >/dev/null &&
   grep -F 'set `Reviewer-Platform` to `manual-codex`' "$codex_review_tasks" >/dev/null &&
   grep -F 'Do not dispatch' "$claude_review_tasks" >/dev/null &&
   grep -F 'Do not dispatch' "$codex_review_tasks" >/dev/null &&
   ! grep -F '## Fresh reviewer dispatch' "$claude_plan" >/dev/null &&
   ! grep -F '## Fresh reviewer dispatch' "$codex_plan" >/dev/null; then
  ok "review commands receive platform-specific fresh-context dispatch and blocking manual fallback"
else
  not_ok "platform reviewer dispatcher rendering"
fi

if find "$RENDER_HOME" "$CONFLICT_HOME" \( -name '.gatespec-skill.*' -o -name '.gatespec-copy.*' \) | grep -q .; then
  not_ok "atomic renderer left temporary files"
else
  ok "atomic renderer and reviewer installer leave zero temporary files"
fi

after_tasks_order_ok=0
if awk '
  /^  after_tasks:$/ {inside=1; next}
  inside && /^  after_analyze:$/ {exit (refine == 1 && check == 2 ? 0 : 1)}
  inside && /command: "speckit\.gatespec\.refine-tasks"/ {refine=++seen}
  inside && /command: "speckit\.gatespec\.check-tasks"/ {check=++seen}
  END {if (inside && !done) exit !(refine == 1 && check == 2)}
' extension.yml; then
  after_tasks_order_ok=1
fi
hook_entry_count=$(awk '
  /^hooks:$/ {inside=1; next}
  inside && /^tags:$/ {inside=0}
  inside && /command: "speckit\.gatespec\./ {count++}
  END {print count+0}
' extension.yml)

if ! grep -F 'version: "0.10.0"' extension.yml >/dev/null ||
   ! grep -F 'speckit_version: ">=0.16.0,<0.17.0"' extension.yml >/dev/null ||
   ! grep -F -- '- "speckit.tasks"' extension.yml >/dev/null ||
   ! grep -F -- '- "speckit.analyze"' extension.yml >/dev/null ||
   ! grep -F -- '- "speckit.implement"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.check-requirements"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.check-design"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.check-source-design"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.refine-tasks"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.check-tasks"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.review-tasks"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.check-task-review"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.check-implementation-review"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.accept-implementation"' extension.yml >/dev/null ||
   [[ "$after_tasks_order_ok" -ne 1 ]] ||
   [[ "$hook_entry_count" -ne 9 ]] ||
   [[ $(grep -c 'priority: 10' extension.yml || true) -ne 3 ]] ||
   [[ $(grep -c 'priority: 20' extension.yml || true) -ne 3 ]]; then
  not_ok "0.10.0 manifest requirements and nine ordered hook entries"
else
  ok "0.10.0 manifest preserves six events and registers nine ordered entries"
fi

# Use the real spec-kit CLI when available. This validates manifest schema,
# packaging, ignore rules, and the installer's project wiring in one scratch.
if command -v specify >/dev/null 2>&1; then
  PROJECT="$TEST_TMP/project"
  INSTALL_HOME="$TEST_TMP/install-home"
  mkdir -p "$PROJECT/.specify/scripts/bash" "$INSTALL_HOME"
  printf '%s\n' '#!/usr/bin/env bash' 'exit 0' > "$PROJECT/.specify/scripts/bash/setup-plan.sh"
  before_status=$(git status --porcelain)
  if HOME="$INSTALL_HOME" bash "$REPO/install.sh" --agent codex "$PROJECT" > "$TEST_TMP/out" 2>&1; then
    package="$PROJECT/.specify/extensions/gatespec"
    after_status=$(git status --porcelain)
    if [[ -d "$package" ]] &&
       [[ ! -e "$package/.git" ]] && [[ ! -e "$package/.agents" ]] && [[ ! -e "$package/.codex" ]] &&
       [[ ! -e "$package/specs" ]] &&
       [[ -f "$package/templates/gatespec-source-design-template.md" ]] &&
       [[ -f "$package/templates/gatespec-implementation-adjustments-template.md" ]] &&
       [[ -f "$package/templates/gatespec-task-closure-template.md" ]] &&
       cmp -s "$REPO/reviewers/claude/gatespec-reviewer.md" "$package/reviewers/claude/gatespec-reviewer.md" &&
       cmp -s "$REPO/reviewers/claude/dispatcher.md" "$package/reviewers/claude/dispatcher.md" &&
       cmp -s "$REPO/reviewers/codex/gatespec-reviewer.toml" "$package/reviewers/codex/gatespec-reviewer.toml" &&
       cmp -s "$REPO/reviewers/codex/dispatcher.md" "$package/reviewers/codex/dispatcher.md" &&
       [[ "$before_status" == "$after_status" ]]; then
      ok "scratch install includes Source templates/reviewers, excludes specs/agent state, and leaves source untouched"
    else
      not_ok "scratch package contents or source-tree cleanliness"
    fi
  else
    not_ok "scratch extension install"
    sed 's/^/    /' "$TEST_TMP/out"
  fi
else
  echo "- specify CLI unavailable: scratch extension-install portion skipped"
fi

echo ''
echo "==> installer/manifest: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
