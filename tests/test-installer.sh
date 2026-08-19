#!/usr/bin/env bash
# Renderer, manifest, and scratch extension-install smoke tests.

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
claude_review_implementation="$RENDER_HOME/.claude/skills/speckit-gatespec-review-implementation/SKILL.md"
codex_review_tasks="$RENDER_HOME/.agents/skills/speckit-gatespec-review-tasks/SKILL.md"
codex_review_implementation="$RENDER_HOME/.agents/skills/speckit-gatespec-review-implementation/SKILL.md"
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
   grep -F '/speckit-gatespec-plan' "$claude_spec" >/dev/null &&
   grep -F "${dollar}speckit-tasks" "$codex_plan" >/dev/null &&
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
   grep -F 'new top-level Claude Code session' "$claude_review_implementation" >/dev/null &&
   grep -F 'do not carry `--scope` into manual mode' "$claude_review_implementation" >/dev/null &&
   grep -F 'In manual `--request` mode, this command is reviewer-only' "$claude_review_implementation" >/dev/null &&
   grep -F 'set `Reviewer-Platform` to `manual-claude`' "$claude_review_tasks" >/dev/null &&
   grep -F 'spawn the custom agent' "$codex_review_tasks" >/dev/null &&
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

if ! grep -F 'version: "0.5.1"' extension.yml >/dev/null ||
   ! grep -F 'speckit_version: ">=0.16.0,<0.17.0"' extension.yml >/dev/null ||
   ! grep -F -- '- "speckit.tasks"' extension.yml >/dev/null ||
   ! grep -F -- '- "speckit.analyze"' extension.yml >/dev/null ||
   ! grep -F -- '- "speckit.implement"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.check-requirements"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.check-design"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.check-tasks"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.review-tasks"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.check-task-review"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.check-implementation-review"' extension.yml >/dev/null; then
  not_ok "0.5.1 manifest requirements and fixed hook entries"
else
  ok "0.5.1 manifest requires the native sequence and registers all six fixed hooks"
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
       cmp -s "$REPO/reviewers/claude/gatespec-reviewer.md" "$package/reviewers/claude/gatespec-reviewer.md" &&
       cmp -s "$REPO/reviewers/claude/dispatcher.md" "$package/reviewers/claude/dispatcher.md" &&
       cmp -s "$REPO/reviewers/codex/gatespec-reviewer.toml" "$package/reviewers/codex/gatespec-reviewer.toml" &&
       cmp -s "$REPO/reviewers/codex/dispatcher.md" "$package/reviewers/codex/dispatcher.md" &&
       [[ "$before_status" == "$after_status" ]]; then
      ok "scratch extension install includes reviewer sources, excludes agent state, and leaves the source tree untouched"
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
