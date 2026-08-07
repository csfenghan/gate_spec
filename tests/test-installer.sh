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

# Render both integrations into an isolated home.
RENDER_HOME="$TEST_TMP/render-home"
mkdir -p "$RENDER_HOME"
if HOME="$RENDER_HOME" bash "$REPO/install.sh" --agent all > "$TEST_TMP/out" 2>&1; then
  ok "Claude and Codex skills render in an isolated target"
else
  not_ok "Claude/Codex rendering failed"
  sed 's/^/    /' "$TEST_TMP/out"
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
dollar='$'
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

if find "$RENDER_HOME" -name '.gatespec-skill.*' -o -name '.gatespec-copy.*' | grep -q .; then
  not_ok "atomic renderer left temporary files"
else
  ok "atomic renderer leaves no temporary files"
fi

if ! grep -F 'speckit_version: ">=0.16.0,<0.17.0"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.check-requirements"' extension.yml >/dev/null ||
   ! grep -F 'command: "speckit.gatespec.check-design"' extension.yml >/dev/null; then
  not_ok "manifest version range/fixed hook entries"
else
  ok "manifest pins the verified range and fixed hook commands"
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
       [[ "$before_status" == "$after_status" ]]; then
      ok "scratch extension install excludes VCS/agent state and leaves the source tree untouched"
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
