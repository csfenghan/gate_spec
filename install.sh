#!/usr/bin/env bash
# GateSpec personal installer (Linux/macOS Bash; Windows via WSL/Git Bash).

set -euo pipefail

REPO=$(cd "$(dirname "$0")" && pwd)
AGENT='all'
FORCE=0
TARGET=''
POSITIONAL=0

usage() {
  cat <<'EOF'
Usage: ./install.sh [--agent claude|codex|all] [--force] [project-dir]

Installs global GateSpec skills and the user constraints file. Supplying an
initialized spec-kit project also registers the extension and its hooks.
EOF
}

# Validate the entire argument vector before creating or changing anything.
while [[ $# -gt 0 ]]; do
  case "$1" in
    --agent)
      if [[ $# -lt 2 || -z "$2" ]]; then
        echo "--agent requires claude, codex, or all" >&2
        exit 2
      fi
      AGENT="$2"
      shift 2
      ;;
    --force)
      FORCE=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    --*)
      echo "unknown option: $1" >&2
      usage >&2
      exit 2
      ;;
    *)
      POSITIONAL=$((POSITIONAL + 1))
      if [[ "$POSITIONAL" -gt 1 ]]; then
        echo "only one project directory may be supplied" >&2
        exit 2
      fi
      TARGET="$1"
      shift
      ;;
  esac
done

case "$AGENT" in
  claude|codex|all) ;;
  *) echo "invalid --agent value: $AGENT (expected claude, codex, or all)" >&2; exit 2 ;;
esac

if [[ -z "${HOME:-}" ]]; then
  echo "HOME must be set to install global GateSpec files" >&2
  exit 2
fi

if [[ -n "$TARGET" && ! -d "$TARGET" ]]; then
  echo "project directory does not exist: $TARGET" >&2
  exit 2
fi
if [[ -n "$TARGET" && -d "$TARGET/.specify" ]]; then
  if [[ ! -f "$TARGET/.specify/scripts/bash/setup-plan.sh" ]]; then
    echo "initialized project is missing required script: $TARGET/.specify/scripts/bash/setup-plan.sh" >&2
    exit 1
  fi
  if ! command -v specify >/dev/null 2>&1; then
    echo "specify CLI is required to wire an initialized project" >&2
    exit 1
  fi
fi
for required in \
  "$REPO/constraints.md" \
  "$REPO/templates/gatespec-spec-template.md" \
  "$REPO/templates/gatespec-plan-template.md" \
  "$REPO/templates/gatespec-source-design-template.md" \
  "$REPO/templates/gatespec-implementation-adjustments-template.md" \
  "$REPO/scripts/bash/check-gate.sh" \
  "$REPO/reviewers/claude/gatespec-reviewer.md" \
  "$REPO/reviewers/claude/dispatcher.md" \
  "$REPO/reviewers/codex/gatespec-reviewer.toml" \
  "$REPO/reviewers/codex/dispatcher.md"; do
  if [[ ! -f "$required" ]]; then
    echo "GateSpec install is incomplete; required file missing: $required" >&2
    exit 1
  fi
done
command_sources=("$REPO"/commands/speckit.gatespec.*.md)
if [[ ! -f "${command_sources[0]}" ]]; then
  echo "GateSpec install is incomplete; no command sources found" >&2
  exit 1
fi

atomic_copy() {
  local src="$1" dest="$2" parent tmp
  parent=$(dirname "$dest")
  mkdir -p "$parent"
  tmp=$(mktemp "$parent/.gatespec-copy.XXXXXX")
  cp "$src" "$tmp"
  chmod 0644 "$tmp"
  mv -f "$tmp" "$dest"
}

reviewer_source() {
  case "$1" in
    claude) printf '%s' "$REPO/reviewers/claude/gatespec-reviewer.md" ;;
    codex) printf '%s' "$REPO/reviewers/codex/gatespec-reviewer.toml" ;;
    *) echo "unknown reviewer adapter: $1" >&2; return 1 ;;
  esac
}

reviewer_destination() {
  case "$1" in
    claude) printf '%s' "$HOME/.claude/agents/gatespec-reviewer.md" ;;
    codex) printf '%s' "$HOME/.codex/agents/gatespec-reviewer.toml" ;;
    *) echo "unknown reviewer adapter: $1" >&2; return 1 ;;
  esac
}

preflight_reviewer_adapter() {
  local agent="$1" src dest
  src=$(reviewer_source "$agent")
  dest=$(reviewer_destination "$agent")
  if [[ ! -e "$dest" && ! -L "$dest" ]]; then
    return 0
  fi
  if [[ -L "$dest" || ! -f "$dest" ]]; then
    echo "reviewer adapter target is not a regular file: $dest" >&2
    return 1
  fi
  if cmp -s "$src" "$dest"; then
    return 0
  fi
  if [[ "$FORCE" -ne 1 ]]; then
    echo "reviewer adapter conflict: $dest differs from GateSpec" >&2
    echo "  Re-run with --force to keep a timestamped backup and replace it." >&2
    return 1
  fi
}

preflight_reviewer_adapters() {
  local failed=0
  if [[ "$AGENT" == all || "$AGENT" == claude ]]; then
    preflight_reviewer_adapter claude || failed=1
  fi
  if [[ "$AGENT" == all || "$AGENT" == codex ]]; then
    preflight_reviewer_adapter codex || failed=1
  fi
  return "$failed"
}

install_reviewer_adapter() {
  local agent="$1" src dest backup platform
  src=$(reviewer_source "$agent")
  dest=$(reviewer_destination "$agent")
  if [[ -f "$dest" ]] && cmp -s "$src" "$dest"; then
    echo "✓ $dest (unchanged)"
    return 0
  fi
  if [[ -e "$dest" ]]; then
    backup="$dest.bak.$(date +%Y%m%d-%H%M%S)-$$"
    atomic_copy "$dest" "$backup"
    echo "✓ reviewer adapter backup: $backup"
  fi
  atomic_copy "$src" "$dest"
  echo "✓ $dest"
  case "$agent" in
    claude) platform='Claude Code' ;;
    codex) platform='Codex' ;;
  esac
  echo "  Start a new $platform session to load this agent definition; existing sessions do not reload it."
}

yaml_quote() {
  printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

sed_replacement() {
  printf '%s' "$1" | sed 's/[\\&|]/\\&/g'
}

command_ref() {
  local agent="$1" command="$2" dollar='$'
  case "$agent:$command" in
    claude:gatespec-specify) printf '%s' '/speckit-gatespec-specify' ;;
    claude:gatespec-plan)    printf '%s' '/speckit-gatespec-plan' ;;
    claude:gatespec-source-design) printf '%s' '/speckit-gatespec-source-design' ;;
    claude:gatespec-review-source-design) printf '%s' '/speckit-gatespec-review-source-design' ;;
    claude:gatespec-accept-implementation) printf '%s' '/speckit-gatespec-accept-implementation' ;;
    claude:gatespec-check)   printf '%s' '/speckit-gatespec-check' ;;
    claude:tasks)            printf '%s' '/speckit-tasks' ;;
    claude:analyze)          printf '%s' '/speckit-analyze' ;;
    claude:implement)        printf '%s' '/speckit-implement' ;;
    codex:gatespec-specify)  printf '%s' "${dollar}speckit-gatespec-specify" ;;
    codex:gatespec-plan)     printf '%s' "${dollar}speckit-gatespec-plan" ;;
    codex:gatespec-source-design) printf '%s' "${dollar}speckit-gatespec-source-design" ;;
    codex:gatespec-review-source-design) printf '%s' "${dollar}speckit-gatespec-review-source-design" ;;
    codex:gatespec-accept-implementation) printf '%s' "${dollar}speckit-gatespec-accept-implementation" ;;
    codex:gatespec-check)    printf '%s' "${dollar}speckit-gatespec-check" ;;
    codex:tasks)             printf '%s' "${dollar}speckit-tasks" ;;
    codex:analyze)           printf '%s' "${dollar}speckit-analyze" ;;
    codex:implement)         printf '%s' "${dollar}speckit-implement" ;;
    *) echo "unknown renderer command reference: $agent:$command" >&2; return 1 ;;
  esac
}

render_skill() {
  local agent="$1" src="$2" dest="$3" name description parent tmp repo_escaped
  local ref_specify ref_plan ref_source ref_review_source ref_accept ref_check ref_tasks ref_analyze ref_implement
  name=$(basename "$dest")
  description=$(awk '
    /^---$/ { fence++; next }
    fence == 1 && /^description:[[:space:]]*/ {
      sub(/^description:[[:space:]]*/, "")
      if (substr($0,1,1) == "\"" && substr($0,length($0),1) == "\"") {
        print substr($0,2,length($0)-2)
      } else print
      exit
    }
  ' "$src")
  if [[ -z "$description" ]]; then
    echo "missing command description: $src" >&2
    return 1
  fi

  ref_specify=$(command_ref "$agent" gatespec-specify)
  ref_plan=$(command_ref "$agent" gatespec-plan)
  ref_source=$(command_ref "$agent" gatespec-source-design)
  ref_review_source=$(command_ref "$agent" gatespec-review-source-design)
  ref_accept=$(command_ref "$agent" gatespec-accept-implementation)
  ref_check=$(command_ref "$agent" gatespec-check)
  ref_tasks=$(command_ref "$agent" tasks)
  ref_analyze=$(command_ref "$agent" analyze)
  ref_implement=$(command_ref "$agent" implement)
  repo_escaped=$(sed_replacement "$REPO")

  parent=$(dirname "$dest")
  mkdir -p "$parent"
  tmp=$(mktemp "$parent/.gatespec-skill.XXXXXX")
  {
    echo '---'
    printf 'name: "%s"\n' "$(yaml_quote "$name")"
    printf 'description: "%s"\n' "$(yaml_quote "$description")"
    echo '---'
    echo ''
    awk 'BEGIN {fence=0} /^---$/ {fence++; next} fence >= 2 {print}' "$src"
    case "$(basename "$src")" in
      speckit.gatespec.review-source-design.md|speckit.gatespec.review-tasks.md|speckit.gatespec.review-implementation.md)
        echo ''
        cat "$REPO/reviewers/$agent/dispatcher.md"
        ;;
    esac
  } | sed \
    -e "s|\.specify/extensions/gatespec/templates|$repo_escaped/templates|g" \
    -e "s|\.specify/extensions/gatespec/scripts|$repo_escaped/scripts|g" \
    -e 's|{SCRIPT}|.specify/scripts/bash/setup-plan.sh --json|g' \
    -e "s|__SPECKIT_COMMAND_GATESPEC_SPECIFY__|$(sed_replacement "$ref_specify")|g" \
    -e "s|__SPECKIT_COMMAND_GATESPEC_PLAN__|$(sed_replacement "$ref_plan")|g" \
    -e "s|__SPECKIT_COMMAND_GATESPEC_SOURCE_DESIGN__|$(sed_replacement "$ref_source")|g" \
    -e "s|__SPECKIT_COMMAND_GATESPEC_REVIEW_SOURCE_DESIGN__|$(sed_replacement "$ref_review_source")|g" \
    -e "s|__SPECKIT_COMMAND_GATESPEC_ACCEPT_IMPLEMENTATION__|$(sed_replacement "$ref_accept")|g" \
    -e "s|__SPECKIT_COMMAND_GATESPEC_CHECK__|$(sed_replacement "$ref_check")|g" \
    -e "s|__SPECKIT_COMMAND_TASKS__|$(sed_replacement "$ref_tasks")|g" \
    -e "s|__SPECKIT_COMMAND_ANALYZE__|$(sed_replacement "$ref_analyze")|g" \
    -e "s|__SPECKIT_COMMAND_IMPLEMENT__|$(sed_replacement "$ref_implement")|g" \
    > "$tmp"

  if grep -Eq '\{SCRIPT\}|__SPECKIT_COMMAND_[A-Z0-9_]+__' "$tmp"; then
    echo "renderer left an unresolved token in $src for $agent" >&2
    rm -f "$tmp"
    return 1
  fi
  chmod 0644 "$tmp"
  mkdir -p "$dest"
  mv -f "$tmp" "$dest/SKILL.md"
  echo "✓ $dest/SKILL.md"
}

install_for_agent() {
  local agent="$1" base cmd skillname
  case "$agent" in
    claude) base="$HOME/.claude/skills" ;;
    codex) base="$HOME/.agents/skills" ;;
  esac
  for cmd in "$REPO"/commands/speckit.gatespec.*.md; do
    skillname="speckit-gatespec-$(basename "$cmd" .md | sed 's/^speckit\.gatespec\.//')"
    render_skill "$agent" "$cmd" "$base/$skillname"
  done
}

# Adapter conflicts are fatal and are checked before any installer write, so a
# selected Claude/Codex bundle is never reported as usable after preserving a
# conflicting custom agent.
preflight_reviewer_adapters || exit 1

# Global constraints (also atomic; preserve user edits unless explicitly forced).
mkdir -p "$HOME/.gatespec"
if [[ -f "$HOME/.gatespec/constraints.md" ]] && ! diff -q "$REPO/constraints.md" "$HOME/.gatespec/constraints.md" >/dev/null 2>&1; then
  if [[ "$FORCE" -eq 1 ]]; then
    backup="$HOME/.gatespec/constraints.md.bak.$(date +%Y%m%d-%H%M%S)-$$"
    atomic_copy "$HOME/.gatespec/constraints.md" "$backup"
    atomic_copy "$REPO/constraints.md" "$HOME/.gatespec/constraints.md"
    echo "✓ ~/.gatespec/constraints.md updated (backup: $backup)"
  else
    echo "⚠ ~/.gatespec/constraints.md differs from the repo; keeping the installed copy."
    echo "  Review: diff ~/.gatespec/constraints.md $REPO/constraints.md"
    echo "  Overwrite: re-run with --force (a timestamped backup is kept)"
  fi
else
  atomic_copy "$REPO/constraints.md" "$HOME/.gatespec/constraints.md"
  echo "✓ ~/.gatespec/constraints.md installed"
fi

if [[ "$AGENT" == all || "$AGENT" == claude ]]; then
  install_for_agent claude
  install_reviewer_adapter claude
fi
if [[ "$AGENT" == all || "$AGENT" == codex ]]; then
  install_for_agent codex
  install_reviewer_adapter codex
fi

if [[ -n "$TARGET" ]]; then
  if [[ -d "$TARGET/.specify" ]]; then
    (cd "$TARGET" && specify extension add --dev "$REPO" --force)
    echo "✓ project wiring: $TARGET (6 events / 8 ordered gate-review-acceptance entries active)"
  else
    echo "⚠ $TARGET is not initialized for spec-kit (missing .specify/)."
    echo "  Global skills were installed, but the full plan/tasks workflow requires:"
    echo "    cd $TARGET && specify init --here --integration <agent>"
    echo "    $REPO/install.sh $TARGET"
  fi
else
  echo "ℹ Full plan/tasks workflow requires running inside an initialized spec-kit project."
fi

echo ''
dollar='$'
printf 'Done. Claude: /speckit-gatespec-specify · Codex: %sspeckit-gatespec-specify · optional Source Design available\n' "$dollar"
