#!/usr/bin/env bash
# GateSpec personal installer.
#
#   ./install.sh                  global install (default):
#                                   skills  → ~/.claude/skills/ and ~/.agents/skills/
#                                   constraints → ~/.gatespec/constraints.md
#   ./install.sh <project-dir>    global install + project wiring:
#                                   runs `specify extension add --dev` when the
#                                   target is a spec-kit project (enables the
#                                   before_plan / before_tasks auto-gates)
#
# Options:
#   --agent claude|codex|all   which agent skill dirs to install (default: all)
#   --force                    overwrite ~/.gatespec/constraints.md even if
#                              locally modified (a timestamped backup is kept)
#
# The repo IS the source of truth: skill bodies reference this repo's
# templates/ and scripts/ via absolute paths, so editing the repo updates
# every project at once. Keep the repo in place.

set -euo pipefail
REPO="$(cd "$(dirname "$0")" && pwd)"
AGENT="all"
FORCE=0
TARGET=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent) AGENT="$2"; shift 2 ;;
    --force) FORCE=1; shift ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) TARGET="$1"; shift ;;
  esac
done

# --- 1. Global constraints ---------------------------------------------------
mkdir -p "$HOME/.gatespec"
if [[ -f "$HOME/.gatespec/constraints.md" ]] && ! diff -q "$REPO/constraints.md" "$HOME/.gatespec/constraints.md" >/dev/null 2>&1; then
  if [[ "$FORCE" -eq 1 ]]; then
    cp "$HOME/.gatespec/constraints.md" "$HOME/.gatespec/constraints.md.bak.$(date +%Y%m%d-%H%M%S)"
    cp "$REPO/constraints.md" "$HOME/.gatespec/constraints.md"
    echo "✓ ~/.gatespec/constraints.md updated (backup kept)"
  else
    echo "⚠ ~/.gatespec/constraints.md differs from repo — keeping yours."
    echo "  Review: diff ~/.gatespec/constraints.md $REPO/constraints.md"
    echo "  Overwrite: re-run with --force (a backup will be kept)"
  fi
else
  cp "$REPO/constraints.md" "$HOME/.gatespec/constraints.md"
  echo "✓ ~/.gatespec/constraints.md installed"
fi

# --- 2. Global skills --------------------------------------------------------
# Render each commands/speckit.gatespec.<cmd>.md into a skill, rewriting
# project-relative extension paths to this repo's absolute paths.
render_skill() { # $1=src command file  $2=dest skill dir
  local src="$1" dest="$2" name desc
  name="$(basename "$dest")"
  desc=$(sed -n 's/^description: *"\?\(.*\)"\?$/\1/p' "$src" | head -1)
  mkdir -p "$dest"
  {
    echo "---"
    echo "name: $name"
    echo "description: $desc"
    echo "---"
    echo ""
    # body = everything after the frontmatter's closing '---'
    awk 'BEGIN{fm=0} /^---$/{fm++; next} fm>=2' "$src"
  } | sed \
      -e "s|\.specify/extensions/gatespec/templates|$REPO/templates|g" \
      -e "s|\.specify/extensions/gatespec/scripts|$REPO/scripts|g" \
      -e "s|{SCRIPT}|.specify/scripts/bash/setup-plan.sh --json|g" \
      > "$dest/SKILL.md"
  # drop the "fallback path" comment lines made meaningless by absolute paths
  sed -i '/fallback path if installed flat/d' "$dest/SKILL.md"
  echo "✓ $dest/SKILL.md"
}

install_for_agent() { # $1=agent key
  case "$1" in
    claude) local base="$HOME/.claude/skills" ;;
    codex)  local base="$HOME/.agents/skills" ;;
    *) echo "unknown agent: $1" >&2; return 1 ;;
  esac
  local cmd skillname
  for cmd in "$REPO"/commands/speckit.gatespec.*.md; do
    skillname="speckit-gatespec-$(basename "$cmd" .md | sed 's/^speckit\.gatespec\.//')"
    render_skill "$cmd" "$base/$skillname"
  done
}

[[ "$AGENT" == "all" || "$AGENT" == "claude" ]] && install_for_agent claude
[[ "$AGENT" == "all" || "$AGENT" == "codex"  ]] && install_for_agent codex

# --- 3. Optional project wiring (hooks + extension registration) -------------
if [[ -n "$TARGET" ]]; then
  if [[ -d "$TARGET/.specify" ]]; then
    (cd "$TARGET" && specify extension add --dev "$REPO" --force)
    echo "✓ project wiring: $TARGET (hooks before_plan/before_tasks active)"
  else
    echo "⚠ $TARGET is not a spec-kit project (no .specify/)."
    echo "  Global skills already work there; for auto-gate hooks run:"
    echo "    cd $TARGET && specify init --here --integration claude"
    echo "    $REPO/install.sh $TARGET"
  fi
fi

echo ""
echo "Done. Invoke as /speckit-gatespec-specify (Claude Code) or \$speckit-gatespec-specify (Codex)."
