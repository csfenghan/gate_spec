#!/usr/bin/env bash
# check-gate.sh — GateSpec machine gate checks.
#
# Usage:
#   check-gate.sh spec   [feature-dir]   # Requirements Gate (before plan)
#   check-gate.sh design [feature-dir]   # Design Gate (before tasks) — includes spec checks
#
# Exit 0: pass (or silently skipped — see below). Exit 1: gate failed.
#
# Skip rule (dual-track): if spec.md has no `<!-- path: gatespec -->` marker,
# the feature is on the upstream auto track and every check passes silently.
#
# Approval-as-snapshot: on approval the agent records
#   **Content-SHA256**: `<hash>`
# inside the `## Gate Approval` section, where the hash is computed as:
#   sed '/^## Gate Approval/,$d' <file> | sha256sum | cut -d' ' -f1
# Any post-approval edit therefore fails the gate until re-approved.

set -u

MODE="${1:-}"
FEATURE_DIR="${2:-}"

if [[ "$MODE" != "spec" && "$MODE" != "design" ]]; then
  echo "Usage: check-gate.sh <spec|design> [feature-dir]" >&2
  exit 2
fi

# --- Resolve feature dir -----------------------------------------------------
if [[ -z "$FEATURE_DIR" ]]; then
  if [[ -f .specify/feature.json ]]; then
    FEATURE_DIR=$(sed -n 's/.*"feature_directory"[^"]*"\([^"]*\)".*/\1/p' .specify/feature.json | head -1)
  fi
fi
if [[ -z "$FEATURE_DIR" || ! -d "$FEATURE_DIR" ]]; then
  echo "GATE FAIL: cannot resolve feature directory (got '$FEATURE_DIR')." >&2
  echo "  Pass it explicitly: check-gate.sh $MODE specs/NNN-name" >&2
  exit 1
fi

SPEC="$FEATURE_DIR/spec.md"
PLAN="$FEATURE_DIR/plan.md"
FAILURES=0
WARNINGS=0

fail() { FAILURES=$((FAILURES+1)); echo "  ✗ $1"; }
warn() { WARNINGS=$((WARNINGS+1)); echo "  ⚠ $1"; }
pass() { echo "  ✓ $1"; }

sha256_of() { # portable sha256
  if command -v sha256sum >/dev/null 2>&1; then sha256sum "$1" | cut -d' ' -f1
  else shasum -a 256 "$1" | cut -d' ' -f1; fi
}

# content_hash <file>: hash of everything before the '## Gate Approval' heading
content_hash() { sed '/^## Gate Approval/,$d' "$1" | { sha256sum 2>/dev/null || shasum -a 256; } | cut -d' ' -f1; }

check_marker() {
  grep -q '^<!-- path: gatespec -->' "$SPEC"
}

check_common_content() { # $1 = file, $2 = expected status prefix (Approved-Requirements|Approved-Design)
  local file="$1" status="$2"

  if grep -n '\[NEEDS CLARIFICATION' "$file" >/dev/null 2>&1; then
    fail "$(basename "$file"): residual [NEEDS CLARIFICATION] markers at lines: $(grep -n '\[NEEDS CLARIFICATION' "$file" | cut -d: -f1 | tr '\n' ' ')"
  else
    pass "$(basename "$file"): no residual [NEEDS CLARIFICATION]"
  fi

  if grep -qE "^\*\*Status\*\*: ${status} \([0-9]{4}-[0-9]{2}-[0-9]{2}\)" "$file"; then
    pass "$(basename "$file"): Status is ${status}"
  else
    fail "$(basename "$file"): missing '**Status**: ${status} (YYYY-MM-DD)' — user approval not recorded"
  fi

  # Approval-as-snapshot
  local recorded actual
  recorded=$(sed -n 's/.*\*\*Content-SHA256\*\*: `\([0-9a-f]\{64\}\)`.*/\1/p' "$file" | head -1)
  if [[ -z "$recorded" ]]; then
    fail "$(basename "$file"): no Content-SHA256 in '## Gate Approval' — approval snapshot missing"
  else
    actual=$(content_hash "$file")
    if [[ "$recorded" == "$actual" ]]; then
      pass "$(basename "$file"): content matches approval snapshot"
    else
      fail "$(basename "$file"): content changed AFTER approval (snapshot mismatch) — revert Status to Draft and re-approve via diff"
    fi
  fi

  # Vague-word lint (warning level, never fails the gate)
  local vague
  vague=$(grep -nE '快速|友好|合理|尽量|等等|robust|intuitive|user-friendly|appropriate|as needed' "$file" | grep -v '^\s*<!--' || true)
  if [[ -n "$vague" ]]; then
    warn "$(basename "$file"): vague wording to eyeball (line: text):"
    echo "$vague" | head -5 | while IFS= read -r l; do echo "      $l"; done
  fi
}

check_spec_gate() {
  echo "Requirements Gate: $SPEC"

  if [[ ! -f "$SPEC" ]]; then
    fail "spec.md not found in $FEATURE_DIR"
    return
  fi

  if ! check_marker; then
    echo "  ↷ no gatespec marker — auto-track spec, gate checks skipped"
    return 0
  fi
  pass "gatespec track marker present"

  # Clarifications: every Q must have a non-empty A
  if grep -q '^## Clarifications' "$SPEC"; then
    local badq
    badq=$(awk '/^## Clarifications/,/^## [^C]/' "$SPEC" | grep -n '^- Q:' | grep -v '→ A: *[^ ]' || true)
    if [[ -n "$badq" ]]; then
      fail "Clarifications entries without a conclusion:"
      echo "$badq" | while IFS= read -r l; do echo "      $l"; done
    else
      pass "Clarifications: every question has a conclusion"
    fi
  else
    fail "missing '## Clarifications' section"
  fi

  # Approved Defaults: every data row must carry ✅
  if grep -q '^## Approved Defaults' "$SPEC"; then
    local unapproved
    unapproved=$(awk '/^## Approved Defaults/,/^## [^A]/' "$SPEC" | grep -E '^\| *[0-9]+' | grep -v '✅' || true)
    if [[ -n "$unapproved" ]]; then
      fail "Approved Defaults rows not approved:"
      echo "$unapproved" | while IFS= read -r l; do echo "      $l"; done
    else
      pass "Approved Defaults: all rows approved"
    fi
  else
    fail "missing '## Approved Defaults' section"
  fi

  # Upstream interface compatibility: mandatory sections intact
  local sec
  for sec in '## User Scenarios & Testing' '## Requirements' '## Success Criteria'; do
    if grep -q "^${sec}" "$SPEC"; then pass "section present: ${sec}"
    else fail "upstream-mandatory section missing: ${sec} (speckit.tasks compatibility)"; fi
  done

  # Verifiability: every FR id must appear at least twice (definition + ≥1 reference)
  local fr dups_missing=0 id count
  for fr in $(grep -oE '\*\*FR-[0-9]+\*\*' "$SPEC" | tr -d '*' | sort -u); do
    count=$(grep -oE "${fr}([^0-9]|\$)" "$SPEC" | wc -l | tr -d ' ')
    if [[ "$count" -lt 2 ]]; then
      fail "verifiability: ${fr} is defined but never referenced by any Acceptance Scenario (add '(covers ${fr})')"
      dups_missing=1
    fi
  done
  [[ "$dups_missing" -eq 0 ]] && pass "verifiability: every FR is referenced by ≥1 Acceptance Scenario"

  check_common_content "$SPEC" "Approved-Requirements"
}

check_design_gate() {
  echo "Design Gate: $PLAN"

  # Auto-track specs skip everything (spec check already printed the skip note)
  if ! check_marker; then
    return 0
  fi

  if [[ ! -f "$PLAN" ]]; then
    fail "plan.md not found in $FEATURE_DIR"
    return
  fi

  # Decision Log: every ### D<n> block needs a filled Approved field
  if grep -q '^## Decision Log' "$PLAN"; then
    local decisions missing=0 d
    decisions=$(grep -c '^### D[0-9]' "$PLAN" || true)
    if [[ "$decisions" -eq 0 ]]; then
      fail "Decision Log has no '### D<n>' entries (or none were needed — then say so in the section)"
    fi
    while IFS= read -r d; do
      local block approved
      block=$(awk -v start="^${d}" '$0 ~ start {f=1; next} /^### D[0-9]/ {f=0} /^## / {f=0} f' "$PLAN")
      approved=$(echo "$block" | grep -E '^\s*-?\s*\*\*Approved\*\*:[^(\[]*\S.*\([0-9]{4}-[0-9]{2}-[0-9]{2}\)' || true)
      if [[ -z "$approved" ]]; then
        fail "decision '${d}' has no recorded approval ('**Approved**: <choice> (YYYY-MM-DD)')"
        missing=1
      fi
    done < <(grep -oE '^### D[0-9]+[^:]*' "$PLAN")
    [[ "$missing" -eq 0 && "$decisions" -gt 0 ]] && pass "Decision Log: all ${decisions} decisions approved"
  else
    fail "missing '## Decision Log' section"
  fi

  # Design Detailing: six dimensions present, none silently empty
  if grep -q '^## Design Detailing' "$PLAN"; then
    local dim_missing=0 dimlist
    dimlist=$(awk '/^## Design Detailing/{f=1;next} /^## /{f=0} f' "$PLAN")
    while IFS= read -r dimline; do
      if echo "$dimline" | grep -qE ':\s*(\[|$)'; then
        fail "Design Detailing dimension left empty: ${dimline%%:*} (fill it or mark 'N/A — <reason>')"
        dim_missing=1
      fi
    done < <(echo "$dimlist" | grep -E '^[0-9]+\. \*\*')
    local ndim
    ndim=$(echo "$dimlist" | grep -cE '^[0-9]+\. \*\*' || true)
    if [[ "$ndim" -lt 6 ]]; then
      fail "Design Detailing lists ${ndim}/6 dimensions — all six must be addressed or marked 'N/A — <reason>'"
      dim_missing=1
    fi
    [[ "$dim_missing" -eq 0 ]] && pass "Design Detailing: all six dimensions addressed"
  else
    fail "missing '## Design Detailing' section"
  fi

  # Upstream interface compatibility
  local sec
  for sec in '## Technical Context' '## Constitution Check' '## Project Structure'; do
    if grep -q "^${sec}" "$PLAN"; then pass "section present: ${sec}"
    else fail "upstream-mandatory section missing: ${sec} (speckit.tasks compatibility)"; fi
  done

  # Placeholder remnants
  if grep -n 'REMOVE IF UNUSED' "$PLAN" >/dev/null 2>&1; then
    fail "template placeholder remnants ('[REMOVE IF UNUSED]') at lines: $(grep -n 'REMOVE IF UNUSED' "$PLAN" | cut -d: -f1 | tr '\n' ' ')"
  fi

  check_common_content "$PLAN" "Approved-Design"
}

# --- Run ---------------------------------------------------------------------
check_spec_gate
SPEC_RESULT=$?
if [[ "$MODE" == "design" && "$FAILURES" -eq 0 ]]; then
  echo ""
  check_design_gate
fi

echo ""
if [[ "$FAILURES" -gt 0 ]]; then
  echo "GATE FAILED: ${FAILURES} check(s) failed, ${WARNINGS} warning(s)."
  echo "Resolve the items above, then re-run the gate. Do NOT proceed to the next phase."
  exit 1
else
  echo "GATE PASSED (${WARNINGS} warning(s))."
  exit 0
fi
