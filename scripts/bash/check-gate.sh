#!/usr/bin/env bash
# GateSpec deterministic artifact gate.
# Usage: check-gate.sh <spec|design> [feature-dir]

set -u

MODE="${1:-}"
FEATURE_DIR="${2:-}"
MARKER='<!-- path: gatespec -->'

if [[ "$MODE" != "spec" && "$MODE" != "design" ]]; then
  echo "Usage: check-gate.sh <spec|design> [feature-dir]" >&2
  exit 2
fi

resolve_feature_dir() {
  local json='.specify/feature.json' value=''
  [[ -f "$json" ]] || return 0

  if command -v jq >/dev/null 2>&1; then
    value=$(jq -r 'if (.feature_directory | type) == "string" then .feature_directory else empty end' "$json" 2>/dev/null || true)
  fi
  if [[ -z "$value" ]] && command -v python3 >/dev/null 2>&1; then
    value=$(python3 -c 'import json,sys; v=json.load(open(sys.argv[1])).get("feature_directory", ""); print(v if isinstance(v, str) else "")' "$json" 2>/dev/null || true)
  fi
  # Last-resort parser: deliberately accepts only a single-line JSON string.
  if [[ -z "$value" ]] && [[ $(wc -l < "$json" | tr -d ' ') -le 1 ]]; then
    value=$(sed -n 's/^[[:space:]]*{[[:space:]]*"feature_directory"[[:space:]]*:[[:space:]]*"\([^"\\]*\)"[[:space:]]*}[[:space:]]*$/\1/p' "$json")
  fi
  printf '%s' "$value"
}

if [[ -z "$FEATURE_DIR" ]]; then
  FEATURE_DIR=$(resolve_feature_dir)
fi
if [[ -z "$FEATURE_DIR" || ! -d "$FEATURE_DIR" ]]; then
  echo "GATE FAIL: cannot resolve feature directory (got '$FEATURE_DIR')." >&2
  echo "  Pass it explicitly: check-gate.sh $MODE specs/NNN-name" >&2
  exit 1
fi

SPEC="$FEATURE_DIR/spec.md"
PLAN="$FEATURE_DIR/plan.md"

if [[ ! -f "$SPEC" ]]; then
  echo "GATE FAILED: spec.md not found in $FEATURE_DIR." >&2
  exit 1
fi

# Dual-track dispatch happens before any normal output. A genuinely unmarked
# upstream artifact is therefore silent. A displaced marker is corruption.
FIRST_LINE=$(sed -n '1p' "$SPEC")
if [[ "$FIRST_LINE" != "$MARKER" ]]; then
  if grep -Fqx "$MARKER" "$SPEC"; then
    echo "GATE FAILED: gatespec track marker exists but is not line 1 of spec.md." >&2
    exit 1
  fi
  exit 0
fi

FAILURES=0
WARNINGS=0
TMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/gatespec-check.XXXXXX") || exit 1
trap 'rm -rf "$TMP_DIR"' EXIT HUP INT TERM

fail() { FAILURES=$((FAILURES + 1)); echo "  ✗ $1"; }
warn() { WARNINGS=$((WARNINGS + 1)); echo "  ⚠ $1"; }
pass() { echo "  ✓ $1"; }

portable_sha256() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum
  elif command -v shasum >/dev/null 2>&1; then
    shasum -a 256
  else
    echo "GATE ERROR: neither sha256sum nor shasum is available" >&2
    return 1
  fi
}

content_hash() {
  sed '/^## Gate Approval/,$d' "$1" | portable_sha256 | awk '{print $1}'
}

file_hash() {
  portable_sha256 < "$1" | awk '{print $1}'
}

h2_count() {
  awk -v name="$2" '
    /^## / {
      text=substr($0,4)
      if (text == name || text == name " *(mandatory)*" ||
          text == name " *(gatespec: mandatory)*") count++
    }
    END { print count+0 }
  ' "$1"
}

section_body() {
  awk -v name="$2" '
    /^## / {
      text=substr($0,4)
      if (inside) exit
      if (text == name || text == name " *(mandatory)*" ||
          text == name " *(gatespec: mandatory)*") { inside=1; next }
    }
    inside { print }
  ' "$1"
}

check_h2_once() {
  local file="$1" name="$2" count
  count=$(h2_count "$file" "$name")
  if [[ "$count" -eq 1 ]]; then
    pass "$(basename "$file"): unique section present: ## $name"
  else
    fail "$(basename "$file"): expected exactly one '## $name' section, found $count"
  fi
}

check_template_remnants() {
  local file="$1" token found=0
  for token in \
    '[NEEDS CLARIFICATION' '[FEATURE' '[###-feature' '[DATE]' '$'"ARGUMENTS" \
    '[YYYY-MM-DD]' '[question asked]' '[user'"'"'s final answer]' '[item]' \
    '[default value]' '[initial state]' '[action]' '[expected outcome]' \
    '[specific capability' '[Measurable metric' '[Assumption about' \
    '[Extract from feature spec' '[choice left open]' '[64 hex chars]' \
    '[approved spec content hash]' '[e.g.,' '[if applicable' \
    '[domain-specific' '[Gates determined' '[what forces this decision]' \
    '[thread ownership' '[creation/destruction' '[responsibilities' \
    '[signature-level' '[externally visible' '[state transitions' \
    '[Document the selected' '[current need]' '[why 3 projects' \
    '[REMOVE IF UNUSED]'; do
    if grep -Fn "$token" "$file" >/dev/null 2>&1; then
      fail "$(basename "$file"): template/residual marker '$token' remains"
      found=1
    fi
  done
  if grep -nE '\{SCRIPT\}|__SPECKIT_COMMAND_[A-Z0-9_]+__' "$file" >/dev/null 2>&1; then
    fail "$(basename "$file"): unresolved renderer token remains"
    found=1
  fi
  [[ "$found" -eq 0 ]] && pass "$(basename "$file"): no known template remnants"
}

check_gate_approval() {
  local file="$1" status_prefix="$2" count raw_count gate_line later_h2
  local status_date approved_date recorded actual nonblank invalid_fields status_fields

  count=$(h2_count "$file" 'Gate Approval')
  raw_count=$(grep -cE '^## Gate Approval([[:space:]]|$)' "$file" || true)
  if [[ "$count" -ne 1 || "$raw_count" -ne 1 ]]; then
    fail "$(basename "$file"): one exact '## Gate Approval' section is required (found $raw_count candidate(s), $count valid)"
    return
  fi

  gate_line=$(awk '/^## Gate Approval([[:space:]]|$)/ { print NR; exit }' "$file")
  later_h2=$(awk -v start="$gate_line" 'NR > start && /^## / { print NR; exit }' "$file")
  if [[ -n "$later_h2" ]]; then
    fail "$(basename "$file"): '## Gate Approval' must be the final H2 section (later H2 at line $later_h2)"
  else
    pass "$(basename "$file"): Gate Approval is the final H2 section"
  fi

  section_body "$file" 'Gate Approval' > "$TMP_DIR/approval"
  nonblank=$(awk 'NF { count++ } END { print count+0 }' "$TMP_DIR/approval")
  invalid_fields=$(awk '
    NF && $0 !~ /^- \*\*Approved by user\*\*: [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/ &&
          $0 !~ /^- \*\*Content-SHA256\*\*: `[0-9a-f]+`$/ { print NR ":" $0 }
  ' "$TMP_DIR/approval")
  if [[ "$nonblank" -ne 2 || -n "$invalid_fields" ]]; then
    fail "$(basename "$file"): Gate Approval may contain only the approval date and Content-SHA256 fields"
  fi

  approved_date=$(sed -n 's/^- \*\*Approved by user\*\*: \([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)$/\1/p' "$TMP_DIR/approval")
  if [[ $(printf '%s\n' "$approved_date" | awk 'NF {n++} END {print n+0}') -ne 1 ]]; then
    fail "$(basename "$file"): missing or duplicate 'Approved by user' date"
    approved_date=''
  fi

  # Literal Markdown backticks and an end anchor require single quoting.
  # shellcheck disable=SC2016
  recorded=$(sed -n 's/^- \*\*Content-SHA256\*\*: `\([0-9a-f]*\)`$/\1/p' "$TMP_DIR/approval")
  if [[ $(printf '%s\n' "$recorded" | awk 'NF {n++} END {print n+0}') -ne 1 || ${#recorded} -ne 64 ]] || printf '%s' "$recorded" | grep -q '[^0-9a-f]'; then
    fail "$(basename "$file"): Content-SHA256 must be one lowercase 64-hex digest"
    recorded=''
  fi

  status_fields=$(grep -c '^\*\*Status\*\*:' "$file" || true)
  status_date=$(sed -n "s/^\*\*Status\*\*: ${status_prefix} (\([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\))$/\1/p" "$file")
  if [[ "$status_fields" -ne 1 || $(printf '%s\n' "$status_date" | awk 'NF {n++} END {print n+0}') -ne 1 ]]; then
    fail "$(basename "$file"): expected exactly one '**Status**: ${status_prefix} (YYYY-MM-DD)'"
    status_date=''
  elif [[ -n "$approved_date" && "$status_date" != "$approved_date" ]]; then
    fail "$(basename "$file"): Status date ($status_date) does not match Approved by user ($approved_date)"
  else
    pass "$(basename "$file"): approval status and date agree"
  fi

  if [[ -n "$recorded" ]]; then
    actual=$(content_hash "$file") || actual=''
    if [[ "$recorded" == "$actual" ]]; then
      pass "$(basename "$file"): content matches approval snapshot"
    else
      fail "$(basename "$file"): content changed after approval (snapshot mismatch)"
    fi
  fi
}

check_vague_words() {
  local file="$1" vague
  vague=$(grep -nE '快速|友好|合理|尽量|等等|robust|intuitive|user-friendly|appropriate|as needed' "$file" | grep -v '^[^:]*:[[:space:]]*<!--' || true)
  if [[ -n "$vague" ]]; then
    warn "$(basename "$file"): vague wording requires human review"
    printf '%s\n' "$vague" | head -5 | sed 's/^/      /'
  fi
}

check_constraint_basis() {
  local file="$1" body="$TMP_DIR/constraint-basis" missing=0 label line recorded
  local current actual severity source_value value
  if [[ $(h2_count "$file" 'Constraint Basis') -ne 1 ]]; then
    fail "spec.md: expected exactly one '## Constraint Basis' section"
    return
  fi
  section_body "$file" 'Constraint Basis' > "$body"
  for label in 'Project constitution' 'Project GateSpec constraints' 'User GateSpec constraints' 'Effective constraints' 'Conflicts and resolutions'; do
    if [[ $(grep -Fc "**$label**:" "$body" || true) -ne 1 ]]; then
      fail "spec.md: Constraint Basis requires exactly one '$label' field"
      missing=1
    fi
  done
  if grep -E '\[(source|hash|effective|conflict|constraint)' "$body" >/dev/null 2>&1; then
    fail "spec.md: Constraint Basis still contains placeholders"
    missing=1
  fi
  for label in 'Project constitution' 'Project GateSpec constraints' 'User GateSpec constraints'; do
    line=$(grep -F "**$label**:" "$body" | head -1)
    if [[ "$line" != "- **$label**: "*' — SHA-256: `'*'`' ]]; then
      fail "spec.md: Constraint Basis '$label' must record a source and SHA-256"
      missing=1
    fi
    source_value=${line#"- **$label**: "}
    source_value=${source_value%% — SHA-256:*}
    if ! printf '%s' "$source_value" | grep -q '[^[:space:]]'; then
      fail "spec.md: Constraint Basis '$label' source cannot be empty"
      missing=1
    fi
    recorded=${line##*SHA-256: \`}
    recorded=${recorded%\`}
    if [[ "$recorded" != 'absent' ]]; then
      if [[ ${#recorded} -ne 64 ]] || printf '%s' "$recorded" | grep -qE '[^0-9a-f]|^$'; then
        fail "spec.md: Constraint Basis '$label' hash must be 'absent' or lowercase 64-hex"
        missing=1
      fi
    fi
  done
  for label in 'Effective constraints' 'Conflicts and resolutions'; do
    line=$(grep -F "**$label**:" "$body" | head -1)
    value=${line#*: }
    if ! printf '%s' "$value" | grep -q '[^[:space:]]'; then
      fail "spec.md: Constraint Basis '$label' cannot be empty"
      missing=1
    fi
  done

  # Source drift is meaningful only when invoked from an initialized project
  # root. Explicit fixture/path checks remain portable and self-contained.
  if [[ -d .specify ]]; then
    for label in 'Project constitution' 'Project GateSpec constraints' 'User GateSpec constraints'; do
      case "$label" in
        'Project constitution') current='.specify/memory/constitution.md'; severity='fail' ;;
        'Project GateSpec constraints') current='.gatespec/constraints.md'; severity='fail' ;;
        'User GateSpec constraints') current="${HOME:-}/.gatespec/constraints.md"; severity='warn' ;;
      esac
      line=$(grep -F "**$label**:" "$body" | head -1)
      recorded=${line##*SHA-256: \`}
      recorded=${recorded%\`}
      if [[ -n "${HOME:-}" || "$label" != 'User GateSpec constraints' ]] && [[ -f "$current" ]]; then
        actual=$(file_hash "$current")
      else
        actual='absent'
      fi
      if [[ "$recorded" != "$actual" ]]; then
        if [[ "$severity" == 'warn' ]]; then
          warn "spec.md: user constraints changed after snapshot; use --refresh-constraints to adopt them"
        else
          fail "spec.md: $label changed after snapshot; Requirements re-approval is required"
          missing=1
        fi
      fi
    done
  fi
  [[ "$missing" -eq 0 ]] && pass "spec.md: Constraint Basis records all sources, effective rules, and conflicts"
}

check_clarifications() {
  local body="$TMP_DIR/clarifications" bad=0 entries none_count sessions invalid nonblank
  section_body "$SPEC" 'Clarifications' > "$body"
  entries=$(grep -c '^- Q:' "$body" || true)
  none_count=$(grep -cE '^- (None|无) —[[:space:]]*[^[:space:]].*$' "$body" || true)
  sessions=$(grep -cE '^### Session [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$' "$body" || true)
  nonblank=$(awk 'NF {n++} END {print n+0}' "$body")
  if [[ "$entries" -eq 0 && "$none_count" -ne 1 ]]; then
    fail "Clarifications must contain concluded '- Q: ... → A: ...' entries or exactly one '- None — <reason>'"
    return
  fi
  if [[ "$entries" -gt 0 && "$none_count" -gt 0 ]]; then
    fail "Clarifications cannot mix entries with the empty-state declaration"
    bad=1
  fi
  if [[ "$entries" -eq 0 && "$nonblank" -ne 1 ]]; then
    fail "Clarifications empty state must be the section's only content"
    bad=1
  elif [[ "$entries" -gt 0 && "$sessions" -lt 1 ]]; then
    fail "Clarifications entries require a dated '### Session YYYY-MM-DD' heading"
    bad=1
  fi
  invalid=$(grep -vE '^[[:space:]]*$|^### Session [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$|^- Q:|^- (None|无) —[[:space:]]*[^[:space:]].*$' "$body" || true)
  if [[ -n "$invalid" ]]; then
    fail "Clarifications contain content outside the fixed session/entry format"
    bad=1
  fi
  while IFS= read -r line; do
    case "$line" in
      '- Q: '*" → A: "*)
        question=${line#- Q: }
        question=${question%% → A: *}
        answer=${line#* → A: }
        if ! printf '%s' "$question" | grep -q '[^[:space:]]' ||
           ! printf '%s' "$answer" | grep -q '[^[:space:]]'; then bad=1; fi
        ;;
      '- Q:'*) bad=1 ;;
    esac
  done < "$body"
  if [[ "$bad" -ne 0 ]]; then
    fail "Clarifications contain an unconcluded or malformed entry"
  else
    pass "Clarifications use a valid concluded/empty-state format"
  fi
}

check_defaults() {
  local body="$TMP_DIR/defaults" rows none_count bad nonblank header divider invalid
  section_body "$SPEC" 'Approved Defaults' > "$body"
  rows=$(grep -cE '^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$body" || true)
  none_count=$(grep -cE '^- (None|无) —[[:space:]]*[^[:space:]].*$' "$body" || true)
  nonblank=$(awk 'NF {n++} END {print n+0}' "$body")
  if [[ "$rows" -eq 0 && "$none_count" -ne 1 ]]; then
    fail "Approved Defaults must contain approved rows or exactly one '- None — <reason>'"
    return
  fi
  if [[ "$rows" -gt 0 && "$none_count" -gt 0 ]]; then
    fail "Approved Defaults cannot mix rows with the empty-state declaration"
    return
  fi
  if [[ "$rows" -eq 0 && "$nonblank" -ne 1 ]]; then
    fail "Approved Defaults empty state must be the section's only content"
    return
  fi
  if [[ "$rows" -gt 0 ]]; then
    header=$(grep -cE '^\|[[:space:]]*#[[:space:]]*\|[[:space:]]*Item[[:space:]]*\|[[:space:]]*Approved Default[[:space:]]*\|[[:space:]]*Approved[[:space:]]*\|[[:space:]]*$' "$body" || true)
    divider=$(grep -cE '^\|[[:space:]]*-+[[:space:]]*\|[[:space:]]*-+[[:space:]]*\|[[:space:]]*-+[[:space:]]*\|[[:space:]]*-+[[:space:]]*\|[[:space:]]*$' "$body" || true)
    invalid=$(grep -vE '^[[:space:]]*$|^\|[[:space:]]*#[[:space:]]*\||^\|[[:space:]]*-+[[:space:]]*\||^\|[[:space:]]*[0-9]+[[:space:]]*\|' "$body" || true)
    if [[ "$header" -ne 1 || "$divider" -ne 1 || -n "$invalid" ]]; then
      fail "Approved Defaults must use the fixed four-column table format"
      return
    fi
  fi
  bad=$(awk -F '|' '
    /^\|[[:space:]]*[0-9]+[[:space:]]*\|/ {
      for (i=2;i<=5;i++) { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $i) }
      if (NF != 6 || $2 !~ /^[0-9]+$/ || $3 == "" || $4 == "" ||
          $5 !~ /^✅ [0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]$/) print NR ":" $0
    }
  ' "$body")
  if [[ -n "$bad" ]]; then
    fail "Approved Defaults contain malformed or unapproved rows"
  else
    pass "Approved Defaults use a valid approved/empty-state format"
  fi
}

check_fr_traceability() {
  local requirements="$TMP_DIR/requirements" functional="$TMP_DIR/functional"
  local scenarios="$TMP_DIR/scenarios" definitions="$TMP_DIR/definitions"
  local duplicate=0 id count undefined=0 orphan=0 bad_scenario=0 outside=0

  section_body "$SPEC" 'Requirements' > "$requirements"
  awk '
    /^### Functional Requirements([[:space:]]|$)/ { inside=1; next }
    inside && (/^### / || /^## /) { exit }
    inside { print }
  ' "$requirements" > "$functional"
  grep -oE '^-[[:space:]]+\*\*FR-[0-9]+\*\*:' "$functional" | grep -oE 'FR-[0-9]+' > "$definitions" || true

  if [[ ! -s "$definitions" ]]; then
    fail "Requirements: Functional Requirements has no FR definitions"
  fi
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    count=$(grep -cx "$id" "$definitions")
    if [[ "$count" -ne 1 ]]; then
      fail "Requirements: $id is defined $count times (must be unique)"
      duplicate=1
    fi
  done < <(sort -u "$definitions")
  [[ "$duplicate" -eq 0 && -s "$definitions" ]] && pass "Requirements: FR definitions are unique and section-scoped"

  outside=$(awk '
    /^## Requirements([[:space:]]|$)/ { req=1; next }
    req && /^## / { req=0 }
    req && /^### Functional Requirements([[:space:]]|$)/ { func=1; next }
    func && (/^### / || /^## /) { func=0 }
    /^-[[:space:]]+\*\*FR-[0-9]+\*\*:/ && !func { print NR ":" $0 }
  ' "$SPEC" | wc -l | tr -d ' ')
  if [[ "$outside" -ne 0 ]]; then
    fail "Requirements: FR definitions found outside '### Functional Requirements'"
  fi

  section_body "$SPEC" 'User Scenarios & Testing' > "$scenarios"
  awk '
    /^\*\*Acceptance Scenarios\*\*:/ { accept=1; next }
    accept && (/^### / || /^---$/) { accept=0 }
    accept && /^[0-9]+\.[[:space:]]/ { print }
  ' "$scenarios" > "$TMP_DIR/acceptance-lines"
  if [[ ! -s "$TMP_DIR/acceptance-lines" ]]; then
    fail "User Scenarios & Testing has no Acceptance Scenario entries"
  else
    while IFS= read -r line; do
      if ! printf '%s\n' "$line" | grep -E '\(covers[[:space:]]+FR-[0-9]+' >/dev/null 2>&1; then
        bad_scenario=1
      fi
    done < "$TMP_DIR/acceptance-lines"
    if [[ "$bad_scenario" -ne 0 ]]; then
      fail "every Acceptance Scenario must contain a '(covers FR-...)' reference"
    fi
  fi

  grep -oE 'FR-[0-9]+' "$TMP_DIR/acceptance-lines" | sort -u > "$TMP_DIR/scenario-refs" || true
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if ! grep -qx "$id" "$definitions"; then
      fail "traceability: Acceptance Scenario references undefined $id"
      undefined=1
    fi
  done < "$TMP_DIR/scenario-refs"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if ! grep -qx "$id" "$TMP_DIR/scenario-refs"; then
      fail "traceability: $id has no Acceptance Scenario reference"
      orphan=1
    fi
  done < <(sort -u "$definitions")
  [[ "$undefined" -eq 0 && "$orphan" -eq 0 && "$bad_scenario" -eq 0 && -s "$definitions" ]] && pass "traceability: scenario references and FR definitions agree"
}

check_spec_gate() {
  local section
  echo "Requirements Gate: $SPEC"
  pass "gatespec track marker is exactly line 1"

  for section in 'Clarifications' 'Approved Defaults' 'Constraint Basis' 'User Scenarios & Testing' 'Requirements' 'Success Criteria'; do
    check_h2_once "$SPEC" "$section"
  done
  check_clarifications
  check_defaults
  check_constraint_basis "$SPEC"
  check_fr_traceability
  check_template_remnants "$SPEC"
  check_gate_approval "$SPEC" 'Approved-Requirements'
  check_vague_words "$SPEC"
}

check_decisions() {
  local body="$TMP_DIR/decisions" headings="$TMP_DIR/decision-headings"
  local malformed count none_count nonblank duplicate=0 missing=0 heading id approved_count
  section_body "$PLAN" 'Decision Log' > "$body"
  grep -E '^### D[0-9]+: .*[^[:space:]][[:space:]]*$' "$body" > "$headings" || true
  sed -n 's/^### \(D[0-9][0-9]*\):.*/\1/p' "$headings" > "$TMP_DIR/decision-ids"
  count=$(awk 'END {print NR+0}' "$headings")
  none_count=$(grep -cE '^- (None|无) —[[:space:]]*[^[:space:]].*$' "$body" || true)
  nonblank=$(awk 'NF {n++} END {print n+0}' "$body")
  malformed=$(grep -nE '^### D' "$body" | grep -vE '^([0-9]+:)?### D[0-9]+: .*[^[:space:]][[:space:]]*$' || true)
  if [[ -n "$malformed" ]]; then
    fail "Decision Log contains a malformed decision heading; required: '### D<n>: <topic>'"
  fi
  if [[ "$count" -eq 0 ]]; then
    if [[ "$none_count" -eq 1 && "$nonblank" -eq 1 ]]; then
      pass "Decision Log records the fixed zero-decision state"
    else
      fail "Decision Log must contain D<n> blocks or only one '- None — <reason>'"
    fi
    return
  fi
  if [[ "$none_count" -gt 0 ]]; then
    fail "Decision Log cannot mix decisions with the zero-decision state"
  fi
  while IFS= read -r heading; do
    id=$(printf '%s\n' "$heading" | sed -n 's/^### \(D[0-9][0-9]*\):.*/\1/p')
    if [[ $(grep -cx "$id" "$TMP_DIR/decision-ids") -ne 1 ]]; then
      fail "Decision Log decision ID $id is duplicated"
      duplicate=1
      continue
    fi
    awk -v target="$heading" '
      $0 == target {inside=1; next}
      inside && (/^### / || /^## /) {exit}
      inside {print}
    ' "$body" > "$TMP_DIR/decision-block"
    approved_count=$(grep -cE '^- \*\*Approved\*\*: .*[^[:space:]] \([0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]\)$' "$TMP_DIR/decision-block" || true)
    if [[ "$approved_count" -ne 1 ]]; then
      fail "decision $id must contain exactly one '**Approved**: <choice> (YYYY-MM-DD)'"
      missing=1
    fi
  done < "$headings"
  [[ "$duplicate" -eq 0 && "$missing" -eq 0 ]] && pass "Decision Log: all $count exact D<n> blocks have approvals"
}

check_design_detailing() {
  local body="$TMP_DIR/design-detailing" label line value expected count bad=0
  section_body "$PLAN" 'Design Detailing' > "$body"
  expected=1
  while IFS= read -r label; do
    count=$(grep -Fc "**${label}**:" "$body" || true)
    if [[ "$count" -ne 1 ]] || ! grep -E "^${expected}\\. \\*\\*${label}\\*\\*:" "$body" >/dev/null 2>&1; then
      fail "Design Detailing requires exactly one '${expected}. **${label}**:' entry"
      bad=1
      expected=$((expected + 1))
      continue
    fi
    line=$(grep -E "^${expected}\\. \\*\\*${label}\\*\\*:" "$body")
    value=${line#*: }
    if [[ -z "$value" || "$value" == \[* ]]; then
      fail "Design Detailing '${label}' is empty or still a placeholder"
      bad=1
    elif printf '%s\n' "$value" | grep -Eq '^(N/A|无额外约束)([[:space:]]*)$'; then
      fail "Design Detailing '${label}' uses N/A without an '— <reason>'"
      bad=1
    elif printf '%s\n' "$value" | grep -Eq '^(N/A|无额外约束)[[:space:]]*—[[:space:]]*$'; then
      fail "Design Detailing '${label}' uses N/A without a reason"
      bad=1
    fi
    expected=$((expected + 1))
  done <<'EOF'
Thread / concurrency model
Object lifetimes & ownership
Key modules & classes
Key internal APIs & interactions
External interface behavior contracts
Setup / runtime / teardown phase interactions
EOF
  [[ "$bad" -eq 0 ]] && pass "Design Detailing: all six core dimensions are exact, unique, and substantive"
}

check_requirements_basis() {
  local recorded actual count all_count
  # Literal Markdown backticks and end anchors require single quoting.
  # shellcheck disable=SC2016
  count=$(grep -cE '^\*\*Requirements Content-SHA256\*\*: `[0-9a-f]+`$' "$PLAN" || true)
  all_count=$(grep -c '^\*\*Requirements Content-SHA256\*\*:' "$PLAN" || true)
  # shellcheck disable=SC2016
  recorded=$(sed -n 's/^\*\*Requirements Content-SHA256\*\*: `\([0-9a-f]*\)`$/\1/p' "$PLAN")
  if [[ "$count" -ne 1 || "$all_count" -ne 1 || ${#recorded} -ne 64 ]] || printf '%s' "$recorded" | grep -q '[^0-9a-f]'; then
    fail "plan.md: expected one 64-hex Requirements Content-SHA256 basis"
    return
  fi
  actual=$(content_hash "$SPEC") || actual=''
  if [[ "$recorded" == "$actual" ]]; then
    pass "plan.md: Requirements basis matches the approved spec content"
  else
    fail "plan.md: Requirements basis mismatch — spec was revised; archive stale tasks and re-plan"
  fi
}

check_design_gate() {
  local section
  echo ""
  echo "Design Gate: $PLAN"
  if [[ ! -f "$PLAN" ]]; then
    fail "plan.md not found in $FEATURE_DIR"
    return
  fi
  for section in 'Technical Context' 'Constitution Check' 'Decision Log' 'Design Detailing' 'Project Structure'; do
    check_h2_once "$PLAN" "$section"
  done
  check_requirements_basis
  check_decisions
  check_design_detailing
  check_template_remnants "$PLAN"
  check_gate_approval "$PLAN" 'Approved-Design'
  check_vague_words "$PLAN"
}

check_spec_gate
if [[ "$MODE" == "design" && "$FAILURES" -eq 0 ]]; then
  check_design_gate
fi

echo ""
if [[ "$FAILURES" -gt 0 ]]; then
  echo "GATE FAILED: $FAILURES check(s) failed, $WARNINGS warning(s)."
  echo "Resolve the listed artifact issues and obtain explicit re-approval before proceeding."
  exit 1
fi
echo "GATE PASSED ($WARNINGS warning(s))."
exit 0
