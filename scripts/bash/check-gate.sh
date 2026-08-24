#!/usr/bin/env bash
# shellcheck disable=SC2016 # Literal Markdown backticks are intentionally single-quoted.
# GateSpec deterministic artifact gate.
# Usage: check-gate.sh <mode> [feature-dir] [REV-ID]

set -u

MODE="${1:-}"
FEATURE_DIR="${2:-}"
REVIEW_ID="${3:-}"
MARKER='<!-- path: gatespec -->'
SOURCE_MARKER='<!-- gatespec: source-design -->'
USAGE='Usage: check-gate.sh <spec|design|source-candidate|source-review|source|tasks-structure|task-review|implementation-candidate|implementation-review|acceptance-candidate|acceptance> [feature-dir] [REV-ID]'

if [[ "$#" -gt 3 ]]; then
  echo "$USAGE" >&2
  exit 2
fi

case "$MODE" in
  spec|design|source-candidate|source-review|source|tasks-structure|acceptance-candidate|acceptance)
    if [[ -n "$REVIEW_ID" ]]; then
      echo "GATE ERROR: $MODE does not accept a REV-ID." >&2
      exit 2
    fi
    ;;
  task-review)
    REVIEW_ID="${REVIEW_ID:-REV-TASKS}"
    if [[ "$REVIEW_ID" != 'REV-TASKS' ]]; then
      echo "GATE ERROR: task-review uses the fixed review id REV-TASKS." >&2
      exit 2
    fi
    ;;
  implementation-candidate|implementation-review)
    REVIEW_ID="${REVIEW_ID:-REV-FINAL}"
    if ! printf '%s\n' "$REVIEW_ID" | grep -Eq '^REV-(FOUNDATION|US[1-9][0-9]*|FINAL)$'; then
      echo "GATE ERROR: $MODE REV-ID must be REV-FOUNDATION, REV-US<n>, or REV-FINAL." >&2
      exit 2
    fi
    ;;
  *)
    echo "$USAGE" >&2
    exit 2
    ;;
esac

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
TASKS="$FEATURE_DIR/tasks.md"
SOURCE_ENTRY="$FEATURE_DIR/contracts/source-design.md"
SOURCE_SHARDS="$FEATURE_DIR/contracts/source-design"
IA_FILE="$FEATURE_DIR/.gatespec/implementation-adjustments.md"
EXECUTION_STATE="$FEATURE_DIR/.gatespec/execution-state.md"
ACCEPTANCE="$FEATURE_DIR/.gatespec/acceptance.md"

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

# The optional Source Design sub-contract is enabled only by its authoritative
# entry file. Its fixed hook is a true silent pass when disabled. Stray shards
# or REV-SOURCE receipts cannot silently enable a partial contract.
case "$MODE" in
  source-candidate|source-review|source)
    if [[ ! -f "$SOURCE_ENTRY" ]]; then
      orphan=''
      if [[ -d "$SOURCE_SHARDS" ]] && find "$SOURCE_SHARDS" -type f -print -quit | grep -q .; then
        orphan='contracts/source-design/'
      elif [[ -e "$FEATURE_DIR/.gatespec/reviews/REV-SOURCE" ]]; then
        orphan='.gatespec/reviews/REV-SOURCE/'
      elif [[ -f "$TASKS" ]] && awk '
        /^\*\*Source-Design-Content-SHA256\*\*: `[^`]+`$/ && $0 !~ /`not-applicable`$/ {found=1}
        END {exit !found}
      ' "$TASKS" 2>/dev/null; then
        orphan='tasks.md Source-Design-Content-SHA256'
      elif [[ -f "$EXECUTION_STATE" ]] &&
           grep -E '^\- \*\*Source-Design-Content-SHA256\*\*: `[^`]+`$' "$EXECUTION_STATE" |
             grep -Fv '`not-applicable`' >/dev/null 2>&1; then
        orphan='.gatespec/execution-state.md source binding'
      fi
      if [[ -n "$orphan" ]]; then
        echo "GATE FAILED: orphan Source Design artifact '$orphan' exists without contracts/source-design.md." >&2
        exit 1
      fi
      exit 0
    fi
    ;;
esac

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

source_design_manifest_hash() {
  local kind="$1" entry_digest source rel digest manifest
  manifest="$TMP_DIR/source-design-${kind}-manifest"
  : > "$manifest"
  case "$kind" in
    reviewed)
      sed -e '/^\*\*Status\*\*:/d' -e '/^## Gate Approval/,$d' "$SOURCE_ENTRY" \
        | portable_sha256 | awk '{print $1}' > "$TMP_DIR/source-entry-digest"
      ;;
    content)
      sed '/^## Gate Approval/,$d' "$SOURCE_ENTRY" \
        | portable_sha256 | awk '{print $1}' > "$TMP_DIR/source-entry-digest"
      ;;
    *) return 1 ;;
  esac
  entry_digest=$(awk 'NR == 1 {print}' "$TMP_DIR/source-entry-digest")
  printf '%s\t%s\n' 'contracts/source-design.md' "$entry_digest" >> "$manifest"
  if [[ -d "$SOURCE_SHARDS" ]]; then
    while IFS= read -r source; do
      [[ -f "$source" ]] || continue
      rel=${source#"$FEATURE_DIR"/}
      digest=$(file_hash "$source") || return 1
      printf '%s\t%s\n' "$rel" "$digest" >> "$manifest"
    done < <(find "$SOURCE_SHARDS" -type f -print)
  fi
  LC_ALL=C sort "$manifest" | portable_sha256 | awk '{print $1}'
}

source_design_reviewed_hash() {
  source_design_manifest_hash reviewed
}

source_design_content_hash() {
  source_design_manifest_hash content
}

file_hash() {
  portable_sha256 < "$1" | awk '{print $1}'
}

normalized_tasks_stream() {
  local file="$1" cr
  cr=$(printf '\r')
  # Review seals bind task definitions, not execution progress. Normalize line
  # endings and only the checkbox of a syntactically valid T### task line.
  sed -E -e "s/${cr}\$//" \
    -e 's/^(- \[)[xX](\] T[0-9][0-9][0-9]([[:space:]]|$))/\1 \2/' "$file"
}

normalized_tasks_hash() {
  normalized_tasks_stream "$1" | portable_sha256 | awk '{print $1}'
}

design_attachments_hash() {
  local source rel digest list="$TMP_DIR/design-attachments"
  : > "$list"
  for rel in research.md data-model.md quickstart.md; do
    source="$FEATURE_DIR/$rel"
    if [[ -f "$source" ]]; then
      digest=$(file_hash "$source") || return 1
      printf '%s\t%s\n' "$rel" "$digest" >> "$list"
    fi
  done
  if [[ -d "$FEATURE_DIR/contracts" ]]; then
    while IFS= read -r source; do
      [[ -f "$source" ]] || continue
      rel=${source#"$FEATURE_DIR"/}
      case "$rel" in
        contracts/source-design.md|contracts/source-design/*) continue ;;
      esac
      digest=$(file_hash "$source") || return 1
      printf '%s\t%s\n' "$rel" "$digest" >> "$list"
    done < <(find "$FEATURE_DIR/contracts" -type f -print)
  fi
  LC_ALL=C sort "$list" | portable_sha256 | awk '{print $1}'
}

markdown_field_values() {
  local file="$1" label="$2"
  awk -v prefix="- **${label}**: \`" '
    index($0, prefix) == 1 && substr($0, length($0), 1) == "`" {
      print substr($0, length(prefix) + 1, length($0) - length(prefix) - 1)
    }
  ' "$file"
}

markdown_field_value() {
  markdown_field_values "$1" "$2" | awk 'NR == 1 { print }'
}

markdown_field_line_numbers() {
  local file="$1" label="$2"
  awk -v prefix="- **${label}**:" 'index($0, prefix) == 1 { print NR }' "$file"
}

check_ordered_fields() {
  local file="$1" context="$2" label lines values line last=0 bad=0
  shift 2
  for label in "$@"; do
    lines=$(markdown_field_line_numbers "$file" "$label")
    values=$(markdown_field_values "$file" "$label")
    if [[ $(printf '%s\n' "$lines" | awk 'NF {n++} END {print n+0}') -ne 1 ||
          $(printf '%s\n' "$values" | awk 'NF {n++} END {print n+0}') -ne 1 ]]; then
      fail "$context: expected exactly one backtick-wrapped '$label' field"
      bad=1
      continue
    fi
    line=$lines
    if [[ "$line" -le "$last" ]]; then
      fail "$context: field '$label' is out of order"
      bad=1
    fi
    last=$line
  done
  [[ "$bad" -eq 0 ]] && pass "$context: required fields are exact, unique, and ordered"
}

hash_before_field() {
  local file="$1" label="$2"
  sed "/^- \*\*${label}\*\*:/,\$d" "$file" | portable_sha256 | awk '{print $1}'
}

check_self_hash() {
  local file="$1" label="$2" context="$3" recorded actual last
  recorded=$(markdown_field_value "$file" "$label")
  last=$(awk 'NF { value=$0 } END { print value }' "$file")
  if [[ ${#recorded} -ne 64 ]] || printf '%s' "$recorded" | grep -qE '[^0-9a-f]|^$'; then
    fail "$context: $label must be lowercase 64-hex"
    return
  fi
  if [[ "$last" != "- **${label}**: \`${recorded}\`" ]]; then
    fail "$context: $label must be the final nonblank field"
    return
  fi
  actual=$(hash_before_field "$file" "$label") || actual=''
  if [[ "$recorded" == "$actual" ]]; then
    pass "$context: $label matches the preceding raw bytes"
  else
    fail "$context: $label self-hash mismatch"
  fi
}

is_lower_hex64() {
  [[ ${#1} -eq 64 ]] && ! printf '%s' "$1" | grep -qE '[^0-9a-f]|^$'
}

is_git_oid() {
  printf '%s\n' "$1" | grep -Eq '^([0-9a-f]{40}|[0-9a-f]{64})$'
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

receipt_section_body() {
  local file="$1" name="$2" terminal_label="$3"
  section_body "$file" "$name" | sed "/^- \*\*${terminal_label}\*\*:/,\$d"
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
    '[existing and planned' '[directed control/data' \
    '[primitives or serialization' '[FR/D/constraint' \
    '[key objects/buffers/handles' '[creation, share/borrow/copy/move' \
    '[material allocation' '[inspected existing modules' \
    '[each key existing/modified/new' '[directed callers/callees' \
    '[actual symbols or protocols' '[language]' \
    '[key type/interface/function' '[ordered main success' \
    '[inputs, outputs, errors' '[new/changed/unchanged API' \
    '[externally observable success' '[versioning, migration' \
    '[states, transition authority' '[ordered setup, runtime' \
    '[partial startup, rollback' \
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
  if grep -E '\[(source|hash|effective|conflict|constraint|源路径|哈希|按优先级|用中文)' "$body" >/dev/null 2>&1; then
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

check_design_evidence_schema() {
  local exact all
  exact=$(grep -cFx '**Design Evidence Schema**: 1' "$PLAN" || true)
  all=$(grep -cF '**Design Evidence Schema**:' "$PLAN" || true)
  if [[ "$exact" -eq 1 && "$all" -eq 1 ]]; then
    pass "plan.md: Design Evidence Schema 1 is declared exactly once"
  else
    fail "plan.md: expected exactly one '**Design Evidence Schema**: 1' field"
  fi
}

reasoned_na() {
  printf '%s\n' "$1" | grep -Eq '^(N/A|无额外约束)[[:space:]]*—[[:space:]]*[^[:space:]].*$'
}

bare_na() {
  printf '%s\n' "$1" | grep -Eq '^(N/A|无额外约束)([[:space:]]*—[[:space:]]*)?$'
}

extract_detail_field() {
  local source="$1" field="$2" destination="$3"
  awk -v target="- **${field}**:" '
    {
      line=$0
      sub(/^[[:space:]]*/, "", line)
    }
    index(line, target) == 1 {
      inside=1
      rest=substr(line, length(target) + 1)
      sub(/^[[:space:]]*/, "", rest)
      if (length(rest)) print rest
      next
    }
    inside && line ~ /^- \*\*[^*]+\*\*:/ { exit }
    inside { print }
  ' "$source" > "$destination"
}

check_detail_field() {
  local block="$1" field="$2" dimension="$3" index="$4"
  local count content_file first opening closing
  content_file="$TMP_DIR/design-field-${index}"
  count=$(awk -v target="- **${field}**:" '
    {
      line=$0
      sub(/^[[:space:]]*/, "", line)
      if (index(line, target) == 1) count++
    }
    END { print count+0 }
  ' "$block")
  if [[ "$count" -ne 1 ]]; then
    fail "Design Detailing '${dimension}' requires exactly one '${field}' field"
    return 1
  fi

  extract_detail_field "$block" "$field" "$content_file"
  first=$(awk 'NF { sub(/^[[:space:]]*/, ""); sub(/[[:space:]]*$/, ""); print; exit }' "$content_file")
  if [[ -z "$first" || "$first" == \[* ]]; then
    fail "Design Detailing '${dimension}' field '${field}' is empty or still a placeholder"
    return 1
  fi
  if bare_na "$first"; then
    fail "Design Detailing '${dimension}' field '${field}' uses N/A without a reason"
    return 1
  fi
  if reasoned_na "$first"; then
    if [[ "$field" == 'Technical basis' ]]; then
      fail "Design Detailing '${dimension}' field 'Technical basis' cannot be N/A"
      return 1
    fi
    return 0
  fi

  if [[ "$field" == 'Core contract skeleton' ]]; then
    # Literal Markdown fences in the regex must remain single quoted.
    # shellcheck disable=SC2016
    opening=$(grep -cE '^[[:space:]]*```[^[:space:]`]+[[:space:]]*$' "$content_file" || true)
    closing=$(grep -cE '^[[:space:]]*```[[:space:]]*$' "$content_file" || true)
    if [[ "$opening" -lt 1 || "$closing" -lt 1 ]]; then
      fail "Design Detailing '${dimension}' field 'Core contract skeleton' requires a language-tagged code fence or reasoned N/A"
      return 1
    fi
    if ! awk '
      {
        line=$0
        sub(/^[[:space:]]*/, "", line)
        sub(/[[:space:]]*$/, "", line)
      }
      !inside && line ~ /^```[^[:space:]`]+$/ { inside=1; next }
      inside && line == "```" { exit }
      inside && length(line) { content=1 }
      END { exit !content }
    ' "$content_file"; then
      fail "Design Detailing '${dimension}' field 'Core contract skeleton' has no declaration content"
      return 1
    fi
  fi
  return 0
}

check_design_detailing() {
  local body="$TMP_DIR/design-detailing" label line value expected count bad=0
  local block required field field_index=0
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
    block="$TMP_DIR/design-dimension-${expected}"
    awk -v target="${expected}. **${label}**:" '
      index($0, target) == 1 { inside=1; next }
      inside && /^[1-9][0-9]*\. \*\*/ { exit }
      inside { print }
    ' "$body" > "$block"
    value=${line#*:}
    value=$(printf '%s' "$value" | sed 's/^[[:space:]]*//; s/[[:space:]]*$//')
    if [[ -n "$value" ]]; then
      if reasoned_na "$value"; then
        if awk 'NF { found=1 } END { exit !found }' "$block"; then
          fail "Design Detailing '${label}' cannot mix inline N/A with structured fields"
          bad=1
        fi
        expected=$((expected + 1))
        continue
      fi
      if bare_na "$value"; then
        fail "Design Detailing '${label}' uses N/A without a reason"
      else
        fail "Design Detailing '${label}' must use its structured fields or a reasoned N/A"
      fi
      bad=1
      expected=$((expected + 1))
      continue
    fi

    case "$expected" in
      1) required=$'Execution contexts\nCross-context flow\nSynchronization contract\nTechnical basis' ;;
      2) required=$'Owned resources\nLifetime flow\nResource contract\nTechnical basis' ;;
      3) required=$'Repository anchors\nChange map\nDependency contract\nTechnical basis' ;;
      4) required=$'Existing entry points\nCore contract skeleton\nPrimary interaction\nSemantic contract\nTechnical basis' ;;
      5) required=$'Affected surfaces\nBehavior contract\nCompatibility contract\nTechnical basis' ;;
      6) required=$'States & owner\nPhase flow\nFailure / recovery contract\nTechnical basis' ;;
    esac
    while IFS= read -r field; do
      field_index=$((field_index + 1))
      if ! check_detail_field "$block" "$field" "$label" "$field_index"; then
        bad=1
      fi
    done <<< "$required"
    expected=$((expected + 1))
  done <<'EOF'
Thread / concurrency model
Object lifetimes & ownership
Key modules & classes
Key internal APIs & interactions
External interface behavior contracts
Setup / runtime / teardown phase interactions
EOF
  [[ "$bad" -eq 0 ]] && pass "Design Detailing: Schema 1 fields are exact, unique, and substantive"
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

source_bundle_concat() {
  local source
  printf '%s\n' "<!-- bundle-file: contracts/source-design.md -->"
  sed '/^## Gate Approval/,$d' "$SOURCE_ENTRY"
  if [[ -d "$SOURCE_SHARDS" ]]; then
    while IFS= read -r source; do
      [[ -f "$source" ]] || continue
      printf '\n<!-- bundle-file: %s -->\n' "${source#"$FEATURE_DIR"/}"
      sed -e '/^<!-- gatespec: source-design -->$/d' -e '/^## Gate Approval/,$d' "$source"
    done < <(find "$SOURCE_SHARDS" -type f -print | LC_ALL=C sort)
  fi
}

source_block() {
  local id="$1" bundle="$2"
  awk -v heading="### ${id}:" '
    index($0, heading) == 1 {inside=1; print; next}
    inside && /^### / {exit}
    inside {print}
  ' "$bundle"
}

source_plain_field() {
  local block="$1" label="$2"
  awk -v prefix="- **${label}**: " '
    index($0, prefix) == 1 {print substr($0, length(prefix) + 1); exit}
  ' "$block"
}

valid_repo_path() {
  local path="$1"
  [[ -n "$path" && "$path" != 'not-applicable' && "$path" != /* && "$path" != *'..'* && "$path" != *$'\t'* ]]
}

check_source_decisions() {
  local bundle="$1" body="$TMP_DIR/source-decisions" ids="$TMP_DIR/source-decision-ids"
  local id block approved bad=0
  section_body "$SOURCE_ENTRY" 'Source Decisions' > "$body"
  grep -hE '^### SD[1-9][0-9]*:' "$SOURCE_ENTRY" > "$ids" || true
  if [[ -d "$SOURCE_SHARDS" ]]; then
    while IFS= read -r source; do
      grep -hE '^### SD[1-9][0-9]*:' "$source" >> "$ids" || true
    done < <(find "$SOURCE_SHARDS" -type f -print)
  fi
  sed -n 's/^### \(SD[1-9][0-9]*\):.*/\1/p' "$ids" | LC_ALL=C sort | uniq -d > "$TMP_DIR/source-duplicate-decisions"
  if [[ -s "$TMP_DIR/source-duplicate-decisions" ]]; then
    fail "source-design: Source Decision IDs must be unique"
    bad=1
  fi
  if [[ ! -s "$ids" ]]; then
    if [[ $(grep -cE '^- (None|无) —[[:space:]]*[^[:space:]].*$' "$body" || true) -ne 1 ]]; then
      fail "source-design: Source Decisions needs approved SD<n> blocks or one reasoned empty state"
      return
    fi
    pass "source-design: no source-level human decision remains"
    return
  fi
  while IFS= read -r id; do
    id=${id#'### '}; id=${id%%:*}
    source_block "$id" "$bundle" > "$TMP_DIR/source-decision-block"
    approved=$(source_plain_field "$TMP_DIR/source-decision-block" 'Approved')
    if [[ -z "$approved" || "$approved" == \[* ]] ||
       ! printf '%s\n' "$approved" | grep -Eq '.+ \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$'; then
      fail "source-design: $id requires an explicit approved choice and date"
      bad=1
    fi
  done < "$ids"
  [[ "$bad" -eq 0 ]] && pass "source-design: every SD<n> decision records explicit user approval"
}

check_source_blocks() {
  local bundle="$1" type id block value operation path destination bad=0 count
  local headings="$TMP_DIR/source-headings" ids="$TMP_DIR/source-ids"
  : > "$headings"
  grep -E '^### SD-(F|U|FLOW|ALG|FAIL|TEST)[1-9][0-9]*:' "$bundle" > "$headings" || true
  sed -n 's/^### \(SD-\(F\|U\|FLOW\|ALG\|FAIL\|TEST\)[1-9][0-9]*\):.*/\1/p' "$headings" > "$ids"
  LC_ALL=C sort "$ids" | uniq -d > "$TMP_DIR/source-duplicate-ids"
  if [[ -s "$TMP_DIR/source-duplicate-ids" ]]; then
    fail "source-design: SD-* identifiers must be unique across entry and shards"
    bad=1
  fi
  for type in F U FLOW ALG FAIL TEST; do
    count=$(grep -Ec "^SD-${type}[1-9][0-9]*$" "$ids" || true)
    if [[ "$count" -lt 1 ]]; then
      fail "source-design: at least one SD-${type}<n> block is required"
      bad=1
    fi
  done

  : > "$TMP_DIR/source-manifest-paths"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    source_block "$id" "$bundle" > "$TMP_DIR/source-block"
    block="$TMP_DIR/source-block"
    case "$id" in
      SD-FLOW*) fields='Trigger and owner|Ordered flow|Success result|Failure / cancellation|Backpressure / ordering' ;;
      SD-FAIL*) fields='Classification|Detection|Propagation|Retry / recovery|Logging / alerting' ;;
      SD-F[1-9]*)
        operation=$(markdown_field_value "$block" 'Operation')
        path=$(markdown_field_value "$block" 'Path')
        destination=$(markdown_field_value "$block" 'Destination Path')
        case "$operation" in ADD|MODIFY|DELETE|RENAME) ;; *) fail "source-design: $id Operation must be ADD, MODIFY, DELETE, or RENAME"; bad=1 ;; esac
        if ! valid_repo_path "$path"; then fail "source-design: $id Path must be a precise repository-relative path"; bad=1
        else printf '%s\n' "$path" >> "$TMP_DIR/source-manifest-paths"; fi
        if [[ "$operation" == 'RENAME' ]]; then
          if ! valid_repo_path "$destination"; then fail "source-design: $id RENAME requires Destination Path"; bad=1
          else printf '%s\n' "$destination" >> "$TMP_DIR/source-manifest-paths"; fi
        elif [[ "$destination" != 'not-applicable' ]]; then
          fail "source-design: $id Destination Path must be not-applicable unless Operation is RENAME"
          bad=1
        fi
        for field in Responsibility 'Source refs'; do
          value=$(source_plain_field "$block" "$field")
          if [[ -z "$value" || "$value" == \[* ]]; then fail "source-design: $id field '$field' must be substantive"; bad=1; fi
        done
        ;;
      SD-U*)
        for field in File 'Visibility / role' 'Inputs / outputs / errors' 'Ownership / concurrency' Compatibility; do
          value=$(source_plain_field "$block" "$field")
          if [[ -z "$value" || "$value" == \[* ]]; then fail "source-design: $id field '$field' must be substantive"; bad=1; fi
        done
        if ! grep -Eq '^```[^[:space:]`]+' "$block" || ! awk '
          /^```[^[:space:]`]+/ {inside=1; next} inside && /^```/ {exit} inside && NF {content=1} END {exit !content}
        ' "$block"; then
          fail "source-design: $id requires a language-tagged complete declaration"
          bad=1
        fi
        ;;
      SD-ALG*) fields='Inputs / outputs|Steps|Data structures|Invariants|Complexity|Boundary cases' ;;
      SD-TEST*) fields='Requirement refs|Source refs|Test path|Test symbol / scenario|Evidence' ;;
    esac
    case "$id" in
      SD-FLOW*|SD-ALG*|SD-FAIL*|SD-TEST*)
        old_ifs=$IFS; IFS='|'
        for field in $fields; do
          value=$(source_plain_field "$block" "$field")
          if [[ -z "$value" || "$value" == \[* ]]; then fail "source-design: $id field '$field' must be substantive"; bad=1; fi
        done
        IFS=$old_ifs
        ;;
    esac
  done < "$ids"
  LC_ALL=C sort "$TMP_DIR/source-manifest-paths" | uniq -d > "$TMP_DIR/source-duplicate-manifest-paths"
  if [[ -s "$TMP_DIR/source-duplicate-manifest-paths" ]]; then
    fail "source-design: each Source Change Manifest path may appear in only one SD-F block"
    bad=1
  fi
  LC_ALL=C sort -u -o "$TMP_DIR/source-manifest-paths" "$TMP_DIR/source-manifest-paths"
  [[ "$bad" -eq 0 ]] && pass "source-design: manifests, declarations, flows, algorithms, failures, and tests are structurally complete"
}

check_source_cross_cutting() {
  local body="$TMP_DIR/source-cross-cutting" label line value bad=0
  section_body "$SOURCE_ENTRY" 'Operational and Cross-Cutting Design' > "$body"
  for label in 'Build registration' Dependencies Configuration 'Persistence / transactions / migration' Security Performance Compatibility Observability; do
    if [[ $(grep -Fc -- "- **${label}**:" "$body" || true) -ne 1 ]]; then
      fail "source-design: Operational design requires exactly one '$label' field"
      bad=1
      continue
    fi
    line=$(grep -F -- "- **${label}**:" "$body")
    value=${line#*: }
    if [[ -z "$value" || "$value" == \[* ]] || printf '%s\n' "$value" | grep -Eq '^(N/A|None|无)$'; then
      fail "source-design: '$label' must be substantive or use N/A — <reason>"
      bad=1
    fi
  done
  [[ "$bad" -eq 0 ]] && pass "source-design: cross-cutting build/runtime concerns are explicit"
}

check_source_approval() {
  local expectation="$1" status_count status date approved_date recorded actual body="$TMP_DIR/source-approval" bad=0
  status_count=$(grep -c '^\*\*Status\*\*:' "$SOURCE_ENTRY" || true)
  status=$(sed -n 's/^\*\*Status\*\*: //p' "$SOURCE_ENTRY")
  if [[ "$status_count" -ne 1 ]]; then
    fail "source-design.md: expected exactly one Status"
    return
  fi
  case "$expectation" in
    candidate) [[ "$status" == 'Draft' ]] || { fail "source-design.md: source candidate Status must be Draft"; bad=1; } ;;
    reviewed)
      if [[ "$status" != 'Draft' ]] && ! printf '%s\n' "$status" | grep -Eq '^Approved-Source-Design \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$'; then
        fail "source-design.md: reviewed candidate Status must be Draft or Approved-Source-Design (YYYY-MM-DD)"; bad=1
      fi
      ;;
    approved)
      if ! printf '%s\n' "$status" | grep -Eq '^Approved-Source-Design \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$'; then
        fail "source-design.md: expected Approved-Source-Design (YYYY-MM-DD)"; bad=1
      fi
      ;;
  esac
  if [[ $(h2_count "$SOURCE_ENTRY" 'Gate Approval') -ne 1 ]] ||
     [[ $(grep -c '^## Gate Approval$' "$SOURCE_ENTRY" || true) -ne 1 ]] ||
     [[ -n $(awk '/^## Gate Approval$/ {inside=1; next} inside && /^## / {print; exit}' "$SOURCE_ENTRY") ]]; then
    fail "source-design.md: Gate Approval must be the unique final H2"
    return
  fi
  section_body "$SOURCE_ENTRY" 'Gate Approval' > "$body"
  if [[ "$status" == 'Draft' ]]; then
    if [[ $(awk 'NF {n++} END {print n+0}' "$body") -ne 2 ]] ||
       ! grep -Fqx -- '- **Approved by user**: pending' "$body" ||
       ! grep -Fqx -- '- **Content-SHA256**: `pending`' "$body"; then
      fail "source-design.md: Draft Gate Approval must contain only pending approval fields"
      bad=1
    else
      pass "source-design.md: Draft approval fields remain unsealed"
    fi
  else
    date=$(printf '%s\n' "$status" | sed -n 's/^Approved-Source-Design (\([0-9-]*\))$/\1/p')
    approved_date=$(sed -n 's/^- \*\*Approved by user\*\*: \([0-9-]*\)$/\1/p' "$body")
    recorded=$(markdown_field_value "$body" 'Content-SHA256')
    actual=$(source_design_content_hash) || actual=''
    if [[ $(awk 'NF {n++} END {print n+0}' "$body") -ne 2 || "$approved_date" != "$date" ]]; then
      fail "source-design.md: approval date and Status date must agree"
      bad=1
    fi
    if ! is_lower_hex64 "$recorded" || [[ "$recorded" != "$actual" ]]; then
      fail "source-design.md: Content-SHA256 does not match the approved Source bundle"
      bad=1
    else
      pass "source-design.md: approved content manifest matches entry and shards"
    fi
  fi
  [[ "$bad" -eq 0 ]] && pass "source-design.md: source approval state is valid"
}

check_source_structure() {
  local expectation="$1" first plan_basis current_plan section bundle="$TMP_DIR/source-bundle" bad=0
  local shard relative nested
  echo ""
  echo "Source Design Gate: $SOURCE_ENTRY"
  first=$(sed -n '1p' "$SOURCE_ENTRY")
  if [[ "$first" != "$SOURCE_MARKER" ]]; then
    if grep -Fqx "$SOURCE_MARKER" "$SOURCE_ENTRY"; then
      fail "source-design.md: Source Design marker exists but is not line 1"
    else
      fail "source-design.md: fixed Source Design marker is missing from line 1"
    fi
    return
  fi
  plan_basis=$(sed -n 's/^\*\*Plan Content-SHA256\*\*: `\([0-9a-f]*\)`$/\1/p' "$SOURCE_ENTRY")
  current_plan=$(content_hash "$PLAN") || current_plan=''
  if ! is_lower_hex64 "$plan_basis" || [[ "$plan_basis" != "$current_plan" ]]; then
    fail "source-design.md: Plan Content-SHA256 is missing or stale"
    bad=1
  else
    pass "source-design.md: approved Plan basis matches"
  fi
  for section in 'Maintainer Scenario' 'Source Decisions' 'Source Change Manifest' 'Symbols and Contracts' \
    'Calls, Data, State, and Lifecycle' 'Algorithms and Invariants' 'Failure Model' 'Test Traceability' \
    'Operational and Cross-Cutting Design' 'Implementation Boundaries' 'Gate Approval'; do
    if [[ $(h2_count "$SOURCE_ENTRY" "$section") -ne 1 ]]; then
      fail "source-design.md: expected exactly one '## $section' section"
      bad=1
    fi
  done
  if [[ -d "$SOURCE_SHARDS" ]]; then
    nested=$(find "$SOURCE_SHARDS" -type d -print | awk 'NR > 1 {print; exit}')
    if [[ -n "$nested" ]] || find "$SOURCE_SHARDS" -type l -print -quit | grep -q .; then
      fail "source-design: shards must be direct regular Markdown files; nested directories and symlinks are forbidden"
      bad=1
    fi
    while IFS= read -r shard; do
      [[ -f "$shard" ]] || continue
      relative=${shard#"$SOURCE_SHARDS"/}
      if [[ "$relative" == */* || "$relative" != *.md ]]; then
        fail "source-design: shard '$relative' must be a direct .md file"
        bad=1
      fi
      if grep -Eq '^<!-- gatespec: source-design -->$|^\*\*Status\*\*:|^## Gate Approval$' "$shard"; then
        fail "source-design: shard '$relative' cannot define the entry marker, Status, or Gate Approval"
        bad=1
      fi
    done < <(find "$SOURCE_SHARDS" -type f -print)
  fi
  source_bundle_concat > "$bundle"
  if grep -nE '\[FEATURE\]|\[Describe |\[plain-language|\[change summary|\[symbol or contract|\[flow name|\[algorithm name|\[failure family|\[test obligation|\[repository/relative|\[complete type|\[exact target|\[externally equivalent' "$bundle" >/dev/null 2>&1; then
    fail "source-design: template placeholders remain in the entry or shards"
    bad=1
  fi
  check_source_decisions "$bundle"
  check_source_blocks "$bundle"
  check_source_cross_cutting
  check_source_approval "$expectation"
  CURRENT_SOURCE_REVIEWED_HASH=$(source_design_reviewed_hash) || CURRENT_SOURCE_REVIEWED_HASH=''
  [[ "$bad" -eq 0 ]] && pass "source-design: marker, Plan basis, required sections, and bundle hashes are structurally valid"
}

check_source_receipt_whitelist() {
  local file="$1" kind="$2" context="$3" invalid="$TMP_DIR/source-receipt-invalid"
  awk -v kind="$kind" '
    /^[[:space:]]*$/ {next}
    kind == "request" {
      if (state == 0 && $0 ~ /^- \*\*(Protocol-Version|Review-ID|Round|Scope|Spec-Content-SHA256|Plan-Content-SHA256|Design-Basis-SHA256|Source-Design-Reviewed-SHA256|Source-Baseline-Commit|Previous-Verdict-SHA256)\*\*: `[^`]+`$/) next
      if (state == 0 && $0 == "## Required Tests") {state=1; next}
      if (state == 1 && $0 == "- Not run — source-design review") next
      if (state == 1 && $0 ~ /^- \*\*Request-SHA256\*\*: `[0-9a-f]+`$/) {state=2; next}
      print NR ":" $0; next
    }
    kind == "verdict" {
      if (state == 0 && $0 ~ /^- \*\*(Protocol-Version|Review-ID|Round|Request-SHA256|Reviewer-Platform|Reviewer-Context-ID|Isolation|Status)\*\*: `[^`]+`$/) next
      if ($0 == "## Tests Run" || $0 == "## Blockers" || $0 == "## Observations" || $0 == "## Limitations") {state=1; next}
      if (state == 1 && $0 ~ /^- [^[:space:]](.*[^[:space:]])?$/ && $0 !~ /^- \*\*Verdict-SHA256\*\*:/) next
      if (state == 1 && $0 ~ /^- \*\*Verdict-SHA256\*\*: `[0-9a-f]+`$/) {state=2; next}
      print NR ":" $0; next
    }
    kind == "seal" {
      if ($0 ~ /^- \*\*(Protocol-Version|Review-ID|Round|Status|Request-SHA256|Verdict-SHA256|Spec-Content-SHA256|Plan-Content-SHA256|Design-Basis-SHA256|Source-Design-Reviewed-SHA256|Source-Baseline-Commit|Sealed-At|Seal-SHA256)\*\*: `[^`]+`$/) next
      print NR ":" $0
    }
  ' "$file" > "$invalid"
  if [[ -s "$invalid" ]]; then
    fail "$context: SOURCE receipt contains non-canonical heading, field, or prose"
  else
    pass "$context: SOURCE receipt uses only its canonical schema"
  fi
}

check_source_request_file() {
  local file="$1" round="$2" previous="$3" bind_current="$4" context request_hash
  local protocol id scope spec_hash plan_hash basis_hash reviewed_hash baseline bad=0
  context=$(basename "$file")
  if [[ ! -f "$file" ]]; then fail "$context: SOURCE request file not found"; return; fi
  check_source_receipt_whitelist "$file" request "$context"
  check_ordered_fields "$file" "$context" \
    'Protocol-Version' 'Review-ID' 'Round' 'Scope' 'Spec-Content-SHA256' \
    'Plan-Content-SHA256' 'Design-Basis-SHA256' 'Source-Design-Reviewed-SHA256' \
    'Source-Baseline-Commit' 'Previous-Verdict-SHA256' 'Request-SHA256'
  check_exact_h2_order "$file" "$context" 'Required Tests'
  protocol=$(markdown_field_value "$file" 'Protocol-Version')
  id=$(markdown_field_value "$file" 'Review-ID')
  scope=$(markdown_field_value "$file" 'Scope')
  spec_hash=$(markdown_field_value "$file" 'Spec-Content-SHA256')
  plan_hash=$(markdown_field_value "$file" 'Plan-Content-SHA256')
  basis_hash=$(markdown_field_value "$file" 'Design-Basis-SHA256')
  reviewed_hash=$(markdown_field_value "$file" 'Source-Design-Reviewed-SHA256')
  baseline=$(markdown_field_value "$file" 'Source-Baseline-Commit')
  [[ "$protocol" == '2' ]] || { fail "$context: SOURCE Protocol-Version must be '2'"; bad=1; }
  [[ "$id" == 'REV-SOURCE' && "$scope" == 'SOURCE' ]] || { fail "$context: SOURCE request must bind REV-SOURCE/SOURCE"; bad=1; }
  [[ $(markdown_field_value "$file" 'Round') == "$round" ]] || { fail "$context: Round must be $round"; bad=1; }
  [[ $(markdown_field_value "$file" 'Previous-Verdict-SHA256') == "$previous" ]] || { fail "$context: prior SOURCE verdict chain mismatch"; bad=1; }
  for digest in "$spec_hash" "$plan_hash" "$basis_hash" "$reviewed_hash"; do
    if ! is_lower_hex64 "$digest"; then fail "$context: SOURCE artifact hashes must be lowercase 64-hex"; bad=1; break; fi
  done
  if [[ "$bind_current" == yes ]]; then
    [[ "$spec_hash" == "$CURRENT_SPEC_HASH" ]] || { fail "$context: spec content hash is stale"; bad=1; }
    [[ "$plan_hash" == "$CURRENT_PLAN_HASH" ]] || { fail "$context: plan content hash is stale"; bad=1; }
    [[ "$basis_hash" == "$CURRENT_ATTACHMENTS_HASH" ]] || { fail "$context: original Design Basis hash is stale"; bad=1; }
    [[ "$reviewed_hash" == "$CURRENT_SOURCE_REVIEWED_HASH" ]] || { fail "$context: Source-Design-Reviewed-SHA256 is stale"; bad=1; }
  fi
  if ! is_git_oid "$baseline" || [[ -z "$GIT_ROOT" ]] ||
     ! git -C "$GIT_ROOT" cat-file -e "${baseline}^{commit}" 2>/dev/null ||
     ! git -C "$GIT_ROOT" merge-base --is-ancestor "$baseline" HEAD 2>/dev/null; then
    fail "$context: Source-Baseline-Commit must be an existing ancestor commit"
    bad=1
  fi
  if [[ -f "$EXECUTION_STATE" ]]; then
    state_original=$(markdown_field_value "$EXECUTION_STATE" 'Original-Implementation-Baseline')
    if [[ -n "$state_original" && "$state_original" != "$baseline" ]]; then
      fail "$context: Source-Baseline-Commit must equal execution state's original baseline"
      bad=1
    fi
  fi
  if [[ $(receipt_section_body "$file" 'Required Tests' 'Request-SHA256' | awk 'NF {n++} END {print n+0}') -ne 1 ]] ||
     ! receipt_section_body "$file" 'Required Tests' 'Request-SHA256' | grep -Fqx -- '- Not run — source-design review'; then
    fail "$context: SOURCE Required Tests must be the fixed review-only exception"
    bad=1
  fi
  check_self_hash "$file" 'Request-SHA256' "$context"
  request_hash=$(markdown_field_value "$file" 'Request-SHA256')
  is_lower_hex64 "$request_hash" || bad=1
  [[ "$bad" -eq 0 ]] && pass "$context: SOURCE request binds Spec, Plan, original Design Basis, reviewed bundle, and source baseline"
}

check_source_verdict_file() {
  local file="$1" round="$2" request_hash="$3" context protocol status platform context_id isolation
  local body blockers nonblank bad=0
  context=$(basename "$file")
  CHECKED_VERDICT_STATUS=''; CHECKED_VERDICT_HASH=''
  if [[ ! -f "$file" ]]; then fail "$context: SOURCE verdict file not found"; return; fi
  check_source_receipt_whitelist "$file" verdict "$context"
  check_ordered_fields "$file" "$context" \
    'Protocol-Version' 'Review-ID' 'Round' 'Request-SHA256' 'Reviewer-Platform' \
    'Reviewer-Context-ID' 'Isolation' 'Status' 'Verdict-SHA256'
  check_exact_h2_order "$file" "$context" 'Tests Run' 'Blockers' 'Observations' 'Limitations'
  protocol=$(markdown_field_value "$file" 'Protocol-Version')
  status=$(markdown_field_value "$file" 'Status')
  platform=$(markdown_field_value "$file" 'Reviewer-Platform')
  context_id=$(markdown_field_value "$file" 'Reviewer-Context-ID')
  isolation=$(markdown_field_value "$file" 'Isolation')
  [[ "$protocol" == '2' ]] || { fail "$context: SOURCE Protocol-Version must be '2'"; bad=1; }
  [[ $(markdown_field_value "$file" 'Review-ID') == 'REV-SOURCE' ]] || { fail "$context: Review-ID must be REV-SOURCE"; bad=1; }
  [[ $(markdown_field_value "$file" 'Round') == "$round" ]] || { fail "$context: Round mismatch"; bad=1; }
  [[ $(markdown_field_value "$file" 'Request-SHA256') == "$request_hash" ]] || { fail "$context: Request-SHA256 mismatch"; bad=1; }
  case "$platform" in codex|claude|manual-codex|manual-claude) ;; *) fail "$context: Reviewer-Platform is not allowed"; bad=1 ;; esac
  [[ -n "$context_id" && "$context_id" != \[* ]] || { fail "$context: Reviewer-Context-ID must be nonempty"; bad=1; }
  [[ "$isolation" == fresh ]] || { fail "$context: Isolation must declare fresh"; bad=1; }
  case "$status" in PASS|BLOCKED) ;; *) fail "$context: Status must be PASS or BLOCKED"; bad=1 ;; esac
  receipt_section_body "$file" 'Tests Run' 'Verdict-SHA256' > "$TMP_DIR/source-verdict-tests"
  if [[ $(awk 'NF {n++} END {print n+0}' "$TMP_DIR/source-verdict-tests") -ne 1 ]] ||
     ! grep -Fqx -- '- Not run — source-design review' "$TMP_DIR/source-verdict-tests"; then
    fail "$context: SOURCE Tests Run must be the fixed review-only exception"; bad=1
  fi
  receipt_section_body "$file" 'Blockers' 'Verdict-SHA256' > "$TMP_DIR/source-verdict-blockers"
  nonblank=$(awk 'NF {n++} END {print n+0}' "$TMP_DIR/source-verdict-blockers")
  blockers=$(grep -cE '^- BLOCKER:[[:space:]]+.+[^[:space:]]$' "$TMP_DIR/source-verdict-blockers" || true)
  if [[ "$status" == PASS ]]; then
    if [[ "$nonblank" -ne 1 ]] || ! grep -Fqx -- '- None' "$TMP_DIR/source-verdict-blockers"; then
      fail "$context: PASS Blockers must be exactly '- None'"
      bad=1
    fi
  elif [[ "$blockers" -lt 1 ]] || grep -Fqx -- '- None' "$TMP_DIR/source-verdict-blockers"; then
    fail "$context: BLOCKED requires at least one BLOCKER and no None"; bad=1
  fi
  for name in Observations Limitations; do
    body="$TMP_DIR/source-verdict-${name}"
    receipt_section_body "$file" "$name" 'Verdict-SHA256' > "$body"
    [[ $(grep -cE '^- [^[:space:]]' "$body" || true) -ge 1 ]] || { fail "$context: ## $name needs a bullet"; bad=1; }
  done
  check_self_hash "$file" 'Verdict-SHA256' "$context"
  CHECKED_VERDICT_STATUS=$status
  CHECKED_VERDICT_HASH=$(markdown_field_value "$file" 'Verdict-SHA256')
  [[ "$bad" -eq 0 ]] && pass "$context: fresh SOURCE verdict schema and blocker semantics are valid"
}

check_source_seal_file() {
  local file="$1" request="$2" verdict="$3" round="$4" label expected actual bad=0
  if [[ ! -f "$file" ]]; then fail "REV-SOURCE: PASS seal not found"; return; fi
  check_source_receipt_whitelist "$file" seal 'REV-SOURCE seal'
  check_ordered_fields "$file" 'REV-SOURCE seal' \
    'Protocol-Version' 'Review-ID' 'Round' 'Status' 'Request-SHA256' 'Verdict-SHA256' \
    'Spec-Content-SHA256' 'Plan-Content-SHA256' 'Design-Basis-SHA256' \
    'Source-Design-Reviewed-SHA256' 'Source-Baseline-Commit' 'Sealed-At' 'Seal-SHA256'
  [[ $(markdown_field_value "$file" 'Protocol-Version') == 2 ]] || { fail "REV-SOURCE seal: Protocol-Version must be 2"; bad=1; }
  [[ $(markdown_field_value "$file" 'Review-ID') == REV-SOURCE ]] || { fail "REV-SOURCE seal: Review-ID mismatch"; bad=1; }
  [[ $(markdown_field_value "$file" 'Round') == "$round" && $(markdown_field_value "$file" 'Status') == PASS ]] || { fail "REV-SOURCE seal: round/status mismatch"; bad=1; }
  [[ $(markdown_field_value "$file" 'Request-SHA256') == $(markdown_field_value "$request" 'Request-SHA256') ]] || { fail "REV-SOURCE seal: request hash mismatch"; bad=1; }
  [[ $(markdown_field_value "$file" 'Verdict-SHA256') == $(markdown_field_value "$verdict" 'Verdict-SHA256') ]] || { fail "REV-SOURCE seal: verdict hash mismatch"; bad=1; }
  for label in Spec-Content-SHA256 Plan-Content-SHA256 Design-Basis-SHA256 Source-Design-Reviewed-SHA256 Source-Baseline-Commit; do
    expected=$(markdown_field_value "$request" "$label"); actual=$(markdown_field_value "$file" "$label")
    [[ "$actual" == "$expected" ]] || { fail "REV-SOURCE seal: $label mismatch"; bad=1; }
  done
  printf '%s\n' "$(markdown_field_value "$file" 'Sealed-At')" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || { fail "REV-SOURCE seal: Sealed-At must be UTC RFC3339"; bad=1; }
  check_self_hash "$file" 'Seal-SHA256' 'REV-SOURCE seal'
  [[ "$bad" -eq 0 ]] && pass "REV-SOURCE: PASS seal binds the reviewed hash without binding mutable approval fields"
}

check_source_review_chain() {
  local directory="$FEATURE_DIR/.gatespec/reviews/REV-SOURCE" seal="$FEATURE_DIR/.gatespec/reviews/REV-SOURCE/seal.md"
  local seal_round seal_number i round request verdict previous=none request_hash status
  local previous_reviewed='' current_reviewed bad=0
  echo ""
  echo "Source Design Review Gate: REV-SOURCE"
  CURRENT_SPEC_HASH=$(content_hash "$SPEC") || CURRENT_SPEC_HASH=''
  CURRENT_PLAN_HASH=$(content_hash "$PLAN") || CURRENT_PLAN_HASH=''
  CURRENT_ATTACHMENTS_HASH=$(design_attachments_hash) || CURRENT_ATTACHMENTS_HASH=''
  CURRENT_SOURCE_REVIEWED_HASH=$(source_design_reviewed_hash) || CURRENT_SOURCE_REVIEWED_HASH=''
  GIT_ROOT=$(git -C "$FEATURE_DIR" rev-parse --show-toplevel 2>/dev/null || true)
  if [[ ! -d "$directory" || ! -f "$seal" ]]; then fail "REV-SOURCE: review directory and PASS seal are required"; return; fi
  invalid=$(find "$directory" -maxdepth 1 -type f \( -name 'round-*-request.md' -o -name 'round-*-verdict.md' \) -print | sed 's|.*/||' | grep -Ev '^round-(00|01|02)-(request|verdict)\.md$' || true)
  [[ -z "$invalid" ]] || { fail "REV-SOURCE: only rounds 00, 01, and 02 are allowed"; bad=1; }
  seal_round=$(markdown_field_value "$seal" 'Round')
  printf '%s\n' "$seal_round" | grep -Eq '^(00|01|02)$' || { fail "REV-SOURCE seal: invalid round"; return; }
  seal_number=$((10#$seal_round))
  i=0
  while [[ "$i" -le "$seal_number" ]]; do
    printf -v round '%02d' "$i"
    request="$directory/round-${round}-request.md"; verdict="$directory/round-${round}-verdict.md"
    bind_current=no; [[ "$i" -eq "$seal_number" ]] && bind_current=yes
    check_source_request_file "$request" "$round" "$previous" "$bind_current"
    current_reviewed=$(markdown_field_value "$request" 'Source-Design-Reviewed-SHA256')
    if [[ "$i" -gt 0 && "$current_reviewed" == "$previous_reviewed" ]]; then
      fail "REV-SOURCE round $round: remediation must change Source-Design-Reviewed-SHA256"; bad=1
    fi
    request_hash=$(markdown_field_value "$request" 'Request-SHA256')
    check_source_verdict_file "$verdict" "$round" "$request_hash"
    status=$CHECKED_VERDICT_STATUS
    if [[ "$i" -lt "$seal_number" && "$status" != BLOCKED ]]; then fail "REV-SOURCE: every pre-seal round must be BLOCKED"; bad=1; fi
    if [[ "$i" -eq "$seal_number" && "$status" != PASS ]]; then fail "REV-SOURCE: sealed round must be PASS"; bad=1; fi
    previous=$CHECKED_VERDICT_HASH; previous_reviewed=$current_reviewed
    i=$((i + 1))
  done
  i=$((seal_number + 1))
  while [[ "$i" -le 2 ]]; do
    printf -v round '%02d' "$i"
    if [[ -e "$directory/round-${round}-request.md" || -e "$directory/round-${round}-verdict.md" ]]; then fail "REV-SOURCE: receipt files exist after sealed PASS"; bad=1; fi
    i=$((i + 1))
  done
  request="$directory/round-${seal_round}-request.md"; verdict="$directory/round-${seal_round}-verdict.md"
  check_source_seal_file "$seal" "$request" "$verdict" "$seal_round"
  [[ "$bad" -eq 0 ]] && pass "REV-SOURCE: bounded fresh review chain is current"
}

preserved_reviews_hash() {
  local root="$FEATURE_DIR/.gatespec/revalidations" file rel digest manifest="$TMP_DIR/preserved-reviews-manifest"
  : > "$manifest"
  if [[ -d "$root" ]]; then
    while IFS= read -r file; do
      [[ -f "$file" ]] || continue
      rel=${file#"$FEATURE_DIR"/}
      digest=$(file_hash "$file") || return 1
      printf '%s\t%s\n' "$rel" "$digest" >> "$manifest"
    done < <(find "$root" -type f -print)
  fi
  if [[ ! -s "$manifest" ]]; then
    printf '%s' 'not-applicable'
  else
    LC_ALL=C sort "$manifest" | portable_sha256 | awk '{print $1}'
  fi
}

check_execution_state() {
  local phase="$1" context='execution-state.md' protocol epoch original handoff source_hash preserved
  local current_source current_preserved invalid bad=0
  if [[ ! -f "$EXECUTION_STATE" ]]; then fail "$context: Review Protocol v2 requires .gatespec/execution-state.md"; return; fi
  invalid=$(awk '
    /^[[:space:]]*$/ {next}
    NR == 1 && $0 == "# GateSpec Execution State" {next}
    /^- \*\*(Protocol-Version|Execution-Epoch|Original-Implementation-Baseline|Task-Handoff-Commit|Source-Design-Content-SHA256|Preserved-Reviews-SHA256|Execution-State-SHA256)\*\*: `[^`]+`$/ {next}
    {print NR ":" $0}
  ' "$EXECUTION_STATE")
  [[ -z "$invalid" ]] || { fail "$context: only the canonical v2 execution fields are allowed"; bad=1; }
  check_ordered_fields "$EXECUTION_STATE" "$context" \
    'Protocol-Version' 'Execution-Epoch' 'Original-Implementation-Baseline' 'Task-Handoff-Commit' \
    'Source-Design-Content-SHA256' 'Preserved-Reviews-SHA256' 'Execution-State-SHA256'
  protocol=$(markdown_field_value "$EXECUTION_STATE" 'Protocol-Version')
  epoch=$(markdown_field_value "$EXECUTION_STATE" 'Execution-Epoch')
  original=$(markdown_field_value "$EXECUTION_STATE" 'Original-Implementation-Baseline')
  handoff=$(markdown_field_value "$EXECUTION_STATE" 'Task-Handoff-Commit')
  source_hash=$(markdown_field_value "$EXECUTION_STATE" 'Source-Design-Content-SHA256')
  preserved=$(markdown_field_value "$EXECUTION_STATE" 'Preserved-Reviews-SHA256')
  [[ "$protocol" == 2 ]] || { fail "$context: Protocol-Version must be 2"; bad=1; }
  printf '%s\n' "$epoch" | grep -Eq '^E[1-9][0-9]*$' || { fail "$context: Execution-Epoch must be E<n>"; bad=1; }
  GIT_ROOT=${GIT_ROOT:-$(git -C "$FEATURE_DIR" rev-parse --show-toplevel 2>/dev/null || true)}
  if ! is_git_oid "$original" || [[ -z "$GIT_ROOT" ]] || ! git -C "$GIT_ROOT" cat-file -e "${original}^{commit}" 2>/dev/null; then
    fail "$context: Original-Implementation-Baseline must resolve to a commit"; bad=1
  fi
  if [[ "$phase" == source-candidate || "$phase" == source-review || "$phase" == source-approved || "$phase" == tasks ]]; then
    if [[ "$handoff" != pending ]] && { ! is_git_oid "$handoff" || ! git -C "$GIT_ROOT" cat-file -e "${handoff}^{commit}" 2>/dev/null; }; then
      fail "$context: Task-Handoff-Commit must be pending or a valid commit before tasks"; bad=1
    fi
  elif ! is_git_oid "$handoff" || ! git -C "$GIT_ROOT" cat-file -e "${handoff}^{commit}" 2>/dev/null; then
    fail "$context: downstream Protocol v2 requires a committed Task-Handoff-Commit"; bad=1
  fi
  if is_git_oid "$original" && is_git_oid "$handoff" &&
     ! git -C "$GIT_ROOT" merge-base --is-ancestor "$original" "$handoff" 2>/dev/null; then
    fail "$context: Original Baseline must be an ancestor of Task Handoff"; bad=1
  fi
  if [[ -f "$SOURCE_ENTRY" ]]; then
    if [[ "$phase" == source-candidate || "$phase" == source-review ]] && [[ "$source_hash" == pending ]]; then
      current_source=pending
    else
      current_source=$(source_design_content_hash) || current_source=''
    fi
  else
    current_source=not-applicable
  fi
  [[ "$source_hash" == "$current_source" ]] || { fail "$context: Source Design content binding is stale"; bad=1; }
  current_preserved=$(preserved_reviews_hash) || current_preserved=''
  [[ "$preserved" == "$current_preserved" ]] || { fail "$context: Preserved-Reviews-SHA256 is stale"; bad=1; }
  if [[ "$preserved" != not-applicable ]] && ! is_lower_hex64 "$preserved"; then fail "$context: Preserved-Reviews-SHA256 must be not-applicable or 64-hex"; bad=1; fi
  check_self_hash "$EXECUTION_STATE" 'Execution-State-SHA256' "$context"
  CURRENT_EXECUTION_EPOCH=$epoch
  CURRENT_ORIGINAL_BASELINE=$original
  CURRENT_TASK_HANDOFF=$handoff
  CURRENT_PRESERVED_HASH=$preserved
  [[ "$bad" -eq 0 ]] && pass "$context: v2 epoch, original baseline, handoff, Source, and preserved reviews are current"
}

check_implementation_adjustments() {
  local require_empty="$1" context='implementation-adjustments.md' epoch source_hash expected_source
  local headings="$TMP_DIR/ia-headings" id block value expected=1 bad=0 source_bundle="$TMP_DIR/ia-source-bundle"
  : > "$TMP_DIR/ia-changed-paths"
  if [[ ! -f "$SOURCE_ENTRY" ]]; then
    [[ ! -e "$IA_FILE" ]] || { fail "$context: IA is not applicable when Source Design is disabled"; return; }
    return
  fi
  if [[ ! -f "$IA_FILE" ]]; then fail "$context: source-enabled execution requires the IA log"; return; fi
  epoch=$(markdown_field_value "$IA_FILE" 'Execution-Epoch')
  source_hash=$(markdown_field_value "$IA_FILE" 'Source-Design-Content-SHA256')
  expected_source=$(source_design_content_hash) || expected_source=''
  [[ "$epoch" == "$CURRENT_EXECUTION_EPOCH" ]] || { fail "$context: Execution-Epoch does not match execution-state.md"; bad=1; }
  [[ "$source_hash" == "$expected_source" ]] || { fail "$context: Source Design hash is stale"; bad=1; }
  grep -E '^### IA[1-9][0-9]*:' "$IA_FILE" > "$headings" || true
  if [[ "$require_empty" == yes ]]; then
    if [[ -s "$headings" ]] || [[ $(grep -cE '^- None —[[:space:]]*[^[:space:]].*$' "$IA_FILE" || true) -ne 1 ]]; then
      fail "$context: REV-TASKS baseline requires an empty IA log"; bad=1
    fi
  elif [[ -s "$headings" ]] && grep -E '^- None —' "$IA_FILE" >/dev/null 2>&1; then
    fail "$context: adjustment blocks cannot coexist with the empty state"; bad=1
  fi
  while IFS= read -r heading; do
    id=${heading#'### IA'}; id=${id%%:*}
    if [[ "$id" -ne "$expected" ]]; then fail "$context: IA IDs must be continuous from IA1"; bad=1; fi
    source_block "IA${id}" "$IA_FILE" > "$TMP_DIR/ia-block"
    block="$TMP_DIR/ia-block"
    for field in 'Source refs' 'Task ID' 'Changed Paths' 'Changed Symbols' 'Boundary Impact'; do
      value=$(markdown_field_value "$block" "$field")
      [[ -n "$value" && "$value" != \[* ]] || { fail "$context: IA$id field '$field' must be backtick-wrapped and substantive"; bad=1; }
    done
    for field in Reason Verification; do
      value=$(source_plain_field "$block" "$field")
      [[ -n "$value" && "$value" != \[* ]] || { fail "$context: IA$id field '$field' must be substantive"; bad=1; }
    done
    [[ $(markdown_field_value "$block" 'Boundary Impact') == none ]] || { fail "$context: IA$id must declare Boundary Impact 'none'; material or uncertain change is forbidden"; bad=1; }
    value=$(markdown_field_value "$block" 'Task ID')
    printf '%s\n' "$value" | grep -Eq '^T[0-9]{3}$' || { fail "$context: IA$id Task ID must be one T###"; bad=1; }
    value=$(markdown_field_value "$block" 'Source refs')
    printf '%s\n' "$value" | grep -Eq 'SD-(F|U|FLOW|ALG|FAIL|TEST)[1-9][0-9]*' || { fail "$context: IA$id needs an existing Source ref"; bad=1; }
    source_bundle_concat > "$source_bundle"
    while IFS= read -r ref; do
      [[ -n "$ref" ]] || continue
      grep -Eq "^### ${ref}:" "$source_bundle" || { fail "$context: IA$id references unknown $ref"; bad=1; }
    done < <(printf '%s\n' "$value" | grep -oE 'SD-(F|U|FLOW|ALG|FAIL|TEST)[1-9][0-9]*' | LC_ALL=C sort -u)
    value=$(markdown_field_value "$block" 'Changed Paths')
    printf '%s\n' "$value" | awk -F ', ' '{for (i=1;i<=NF;i++) print $i}' > "$TMP_DIR/ia-path-list"
    if [[ $(awk 'BEGIN {s=""} {s=s (s=="" ? "" : ", ") $0} END {print s}' "$TMP_DIR/ia-path-list") != "$value" ]]; then
      fail "$context: IA$id Changed Paths must be a canonical comma+space list"; bad=1
    fi
    while IFS= read -r path; do
      if ! valid_repo_path "$path"; then fail "$context: IA$id contains invalid changed path '$path'"; bad=1
      else printf '%s\n' "$path" >> "$TMP_DIR/ia-changed-paths"; fi
    done < "$TMP_DIR/ia-path-list"
    expected=$((expected + 1))
  done < "$headings"
  LC_ALL=C sort -u -o "$TMP_DIR/ia-changed-paths" "$TMP_DIR/ia-changed-paths"
  [[ "$bad" -eq 0 ]] && pass "$context: IA log is epoch-bound, bounded, ordered, and path-complete"
}

git_final_delta_hash() {
  local repo="$1" original="$2" subject="$3"
  git -C "$repo" diff-tree --raw -z --no-abbrev --no-renames "$original" "$subject" 2>/dev/null \
    | portable_sha256 | awk '{print $1}'
}

check_source_final_paths() {
  local subject="$1" actual="$TMP_DIR/final-product-paths" expected="$TMP_DIR/final-allowed-paths"
  local path bad=0 bundle="$TMP_DIR/final-source-bundle"
  [[ -f "$SOURCE_ENTRY" ]] || return
  if ! resolve_git_feature_paths; then fail "REV-FINAL: cannot resolve feature path for Source reconciliation"; return; fi
  git -C "$GIT_ROOT" -c core.quotepath=false diff --no-renames --name-only \
    "$CURRENT_ORIGINAL_BASELINE" "$subject" > "$TMP_DIR/final-all-paths" 2>/dev/null || {
      fail "REV-FINAL: cannot enumerate Original-Baseline..Subject paths"; return;
    }
  : > "$actual"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$path" in "$GIT_FEATURE_REL"/*) ;; *) printf '%s\n' "$path" >> "$actual" ;; esac
  done < "$TMP_DIR/final-all-paths"
  source_bundle_concat > "$bundle"
  check_source_blocks "$bundle"
  : > "$expected"
  cat "$TMP_DIR/source-manifest-paths" >> "$expected"
  [[ -s "$TMP_DIR/ia-changed-paths" ]] && cat "$TMP_DIR/ia-changed-paths" >> "$expected"
  LC_ALL=C sort -u -o "$actual" "$actual"
  LC_ALL=C sort -u -o "$expected" "$expected"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if ! grep -Fqx -- "$path" "$expected"; then
      fail "REV-FINAL: product path '$path' is absent from Source Change Manifest + IA Changed Paths"
      bad=1
    fi
  done < "$actual"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if ! grep -Fqx -- "$path" "$actual"; then
      fail "REV-FINAL: declared Source/IA path '$path' is absent from the actual implementation delta"
      bad=1
    fi
  done < "$expected"
  [[ "$bad" -eq 0 ]] && pass "REV-FINAL: actual product paths equal Source Change Manifest + bounded IA paths"
}

check_implementation_review_contract() {
  local body="$TMP_DIR/implementation-review-contract" required protocol review_root
  local task_review isolation parallel git_policy limit final_validation
  local first last count id current_us previous_us=0 bad=0 mapping="$TMP_DIR/checkpoint-test-mapping"
  local mapping_body="$TMP_DIR/checkpoint-test-mapping-body" remediation_line mapping_line final_line

  if [[ $(h2_count "$PLAN" 'Implementation Review Contract') -ne 1 ]]; then
    fail "plan.md: expected exactly one '## Implementation Review Contract' section"
    return
  fi
  section_body "$PLAN" 'Implementation Review Contract' > "$body"
  check_ordered_fields "$body" 'plan.md Implementation Review Contract' \
    'Protocol Version' 'Required Checkpoints' 'Review Root' 'Task Review' \
    'Reviewer Isolation' 'Parallel Policy' 'Git Policy' 'Remediation Limit' \
    'Final Validation'

  protocol=$(markdown_field_value "$body" 'Protocol Version')
  required=$(markdown_field_value "$body" 'Required Checkpoints')
  review_root=$(markdown_field_value "$body" 'Review Root')
  task_review=$(markdown_field_value "$body" 'Task Review')
  isolation=$(markdown_field_value "$body" 'Reviewer Isolation')
  parallel=$(markdown_field_value "$body" 'Parallel Policy')
  git_policy=$(markdown_field_value "$body" 'Git Policy')
  limit=$(markdown_field_value "$body" 'Remediation Limit')
  final_validation=$(markdown_field_value "$body" 'Final Validation')
  printf '%s\n' "$final_validation" > "$TMP_DIR/final-validation"

  case "$protocol" in
    1|2) ;;
    *) fail "plan.md: review Protocol Version must be '1' (legacy) or '2'"; bad=1 ;;
  esac
  ACTIVE_REVIEW_PROTOCOL=$protocol
  # An approved legacy Plan stays byte-for-byte immutable. Enabling the
  # independent Source Design sub-contract activates receipt protocol v2.
  [[ -f "$SOURCE_ENTRY" ]] && ACTIVE_REVIEW_PROTOCOL=2
  [[ "$review_root" == '.gatespec/reviews' ]] || { fail "plan.md: Review Root must be '.gatespec/reviews'"; bad=1; }
  [[ "$task_review" == 'REV-TASKS after speckit.analyze; PASS required before speckit.implement' ]] || {
    fail "plan.md: Task Review contract is not the fixed REV-TASKS handoff"; bad=1;
  }
  [[ "$isolation" == 'fresh-context-required; manual-new-session-on-unavailable; same-context-forbidden' ]] || {
    fail "plan.md: Reviewer Isolation must use the fixed fresh-context policy"; bad=1;
  }
  [[ "$parallel" == 'same-phase-disjoint-only; join-before-review; cross-checkpoint-forbidden' ]] || {
    fail "plan.md: Parallel Policy must use the fixed checkpoint policy"; bad=1;
  }
  [[ "$git_policy" == 'clean-feature-branch; local-checkpoint-commits; no-push' ]] || {
    fail "plan.md: Git Policy must use the fixed local-checkpoint policy"; bad=1;
  }
  [[ "$limit" == '2' ]] || { fail "plan.md: Remediation Limit must be '2'"; bad=1; }
  if [[ -z "$final_validation" || "$final_validation" == \[* ]]; then
    fail "plan.md: Final Validation must be substantive"
    bad=1
  fi

  : > "$TMP_DIR/required-checkpoints"
  if [[ -z "$required" ]]; then
    fail "plan.md: Required Checkpoints cannot be empty"
    bad=1
  else
    printf '%s\n' "$required" | awk -F ', ' '{ for (i=1; i<=NF; i++) print $i }' > "$TMP_DIR/required-checkpoints"
    # Reject alternate spacing or empty elements by reconstructing the canonical list.
    if [[ $(awk 'BEGIN {sep=""} {printf "%s%s", sep, $0; sep=", "} END {print ""}' "$TMP_DIR/required-checkpoints") != "$required" ]]; then
      fail "plan.md: Required Checkpoints must be a canonical comma+space list"
      bad=1
    fi
  fi

  count=$(awk 'NF {n++} END {print n+0}' "$TMP_DIR/required-checkpoints")
  first=$(awk 'NF {print; exit}' "$TMP_DIR/required-checkpoints")
  last=$(awk 'NF {value=$0} END {print value}' "$TMP_DIR/required-checkpoints")
  if [[ "$count" -lt 3 || "$first" != 'REV-FOUNDATION' || "$last" != 'REV-FINAL' ]]; then
    fail "plan.md: Required Checkpoints must start REV-FOUNDATION, include REV-US<n>, and end REV-FINAL"
    bad=1
  fi
  LC_ALL=C sort "$TMP_DIR/required-checkpoints" | uniq -d > "$TMP_DIR/duplicate-checkpoints"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if grep -Fqx -- "$id" "$TMP_DIR/duplicate-checkpoints"; then
      fail "plan.md: Required Checkpoint $id is duplicated"
      bad=1
    fi
    case "$id" in
      REV-FOUNDATION|REV-FINAL) ;;
      REV-US*)
        if printf '%s\n' "$id" | grep -Eq '^REV-US[1-9][0-9]*$'; then
          current_us=${id#REV-US}
          if [[ "$current_us" -le "$previous_us" ]]; then
            fail "plan.md: REV-US checkpoints must be in increasing numeric order"
            bad=1
          fi
          previous_us=$current_us
        else
          fail "plan.md: invalid Required Checkpoint '$id'"
          bad=1
        fi
        ;;
      *)
        fail "plan.md: invalid Required Checkpoint '$id'"
        bad=1
        ;;
    esac
  done < "$TMP_DIR/required-checkpoints"

  remediation_line=$(markdown_field_line_numbers "$body" 'Remediation Limit')
  mapping_line=$(awk '$0 == "### Checkpoint Test Mapping" {print NR}' "$body")
  final_line=$(markdown_field_line_numbers "$body" 'Final Validation')
  if ! [[ "$remediation_line" =~ ^[0-9]+$ && "$mapping_line" =~ ^[0-9]+$ && "$final_line" =~ ^[0-9]+$ ]] ||
     (( remediation_line >= mapping_line || mapping_line >= final_line )); then
    fail "plan.md: one exact Checkpoint Test Mapping must follow Remediation Limit and precede Final Validation"
    bad=1
  fi
  awk '
    $0 == "### Checkpoint Test Mapping" {inside=1; next}
    inside && /^- \*\*Final Validation\*\*:/ {exit}
    inside && (/^## / || /^### /) {exit}
    inside {print}
  ' "$body" > "$mapping_body"
  if [[ $(grep -Fxc '| Checkpoint | Required test command(s) |' "$mapping_body" || true) -ne 1 ]]; then
    fail "plan.md: Checkpoint Test Mapping requires the exact two-column header"
    bad=1
  fi
  if ! awk -F '|' '
    /^\|[[:space:]]*REV-/ && NF != 4 {bad=1}
    END {exit bad}
  ' "$mapping_body"; then
    fail "plan.md: Checkpoint Test Mapping rows must have exactly two columns; use a script wrapper for pipelines"
    bad=1
  fi
  awk -F '|' '
    /^\|[[:space:]]*REV-(FOUNDATION|US[1-9][0-9]*|FINAL)[[:space:]]*\|/ {
      checkpoint=$2; tests=$3
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", checkpoint)
      gsub(/^[[:space:]]+|[[:space:]]+$/, "", tests)
      print checkpoint "\t" tests
    }
  ' "$mapping_body" > "$mapping"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    count=$(awk -F '\t' -v wanted="$id" '$1 == wanted {n++} END {print n+0}' "$mapping")
    if [[ "$count" -ne 1 ]]; then
      fail "plan.md: Checkpoint Test Mapping requires exactly one row for $id"
      bad=1
    elif ! awk -F '\t' -v wanted="$id" '$1 == wanted && $2 != "" && $2 !~ /^\[/ {ok=1} END {exit !ok}' "$mapping"; then
      fail "plan.md: Checkpoint Test Mapping for $id must be substantive"
      bad=1
    fi
  done < "$TMP_DIR/required-checkpoints"
  cut -f1 "$mapping" > "$TMP_DIR/mapping-checkpoints"
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if ! grep -Fqx -- "$id" "$TMP_DIR/required-checkpoints"; then
      fail "plan.md: Checkpoint Test Mapping contains undeclared $id"
      bad=1
    fi
  done < "$TMP_DIR/mapping-checkpoints"

  [[ "$bad" -eq 0 ]] && pass "plan.md: Implementation Review Contract is complete and fixed"
}

check_tasks_structure() {
  local id count line line_number later_task phase_heading task_id bad=0 expected=1 expected_id story
  local previous_checkpoint_line=0
  local checkpoint_ids="$TMP_DIR/task-checkpoint-ids" valid_ids="$TMP_DIR/task-ids"
  echo ""
  echo "Tasks Structure Gate: $TASKS"
  if [[ ! -f "$TASKS" ]]; then
    fail "tasks.md not found in $FEATURE_DIR"
    return
  fi

  [[ -s "$TMP_DIR/required-checkpoints" ]] || return

  grep -E '^- \[[ xX]\] T[0-9][0-9][0-9]([[:space:]]|$)' "$TASKS" \
    | sed -n 's/^- \[[ xX]\] \(T[0-9][0-9][0-9]\).*/\1/p' > "$valid_ids" || true
  LC_ALL=C sort "$valid_ids" | uniq -d > "$TMP_DIR/duplicate-task-ids"
  while IFS= read -r task_id; do
    [[ -n "$task_id" ]] || continue
    if grep -Fqx -- "$task_id" "$TMP_DIR/duplicate-task-ids"; then
      fail "tasks.md: task ID $task_id is duplicated"
      bad=1
    fi
    expected_id=$(printf 'T%03d' "$expected")
    if [[ "$task_id" != "$expected_id" ]]; then
      fail "tasks.md: task IDs must be strictly continuous from T001 (expected $expected_id, found $task_id)"
      bad=1
    fi
    expected=$((expected + 1))
  done < "$valid_ids"

  grep -E '^- \[[ xX]\] T[0-9][0-9][0-9].*GateSpec review checkpoint REV-(FOUNDATION|US[1-9][0-9]*|FINAL):' "$TASKS" \
    | sed -n 's/.*GateSpec review checkpoint \(REV-\(FOUNDATION\|US[1-9][0-9]*\|FINAL\)\):.*/\1/p' \
    > "$checkpoint_ids" || true

  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    count=$(grep -Ec "^- \\[[ xX]\\] T[0-9][0-9][0-9].*GateSpec review checkpoint ${id}:" "$TASKS" || true)
    if [[ "$count" -ne 1 ]]; then
      fail "tasks.md: expected exactly one task for checkpoint $id"
      bad=1
      continue
    fi
    line=$(grep -E "^- \\[[ xX]\\] T[0-9][0-9][0-9].*GateSpec review checkpoint ${id}:" "$TASKS")
    if printf '%s\n' "$line" | grep -F '[P]' >/dev/null 2>&1; then
      fail "tasks.md: checkpoint $id must not be marked [P]"
      bad=1
    fi
    if ! printf '%s\n' "$line" | grep -F -- "--scope $id" >/dev/null 2>&1; then
      fail "tasks.md: checkpoint $id must invoke --scope $id"
      bad=1
    fi
    if ! printf '%s\n' "$line" | grep -F -- ".gatespec/reviews/$id/seal.md" >/dev/null 2>&1; then
      fail "tasks.md: checkpoint $id must name .gatespec/reviews/$id/seal.md"
      bad=1
    fi
    if ! printf '%s\n' "$line" | grep -F -- 'speckit.gatespec.review-implementation' >/dev/null 2>&1; then
      fail "tasks.md: checkpoint $id must name speckit.gatespec.review-implementation"
      bad=1
    fi
    if ! printf '%s\n' "$line" | grep -F -- 'before continuing' >/dev/null 2>&1; then
      fail "tasks.md: checkpoint $id must require the PASS seal before continuing"
      bad=1
    fi

    line_number=$(grep -nE "^- \\[[ xX]\\] T[0-9][0-9][0-9].*GateSpec review checkpoint ${id}:" "$TASKS" | cut -d: -f1)
    if [[ "$line_number" -le "$previous_checkpoint_line" ]]; then
      fail "tasks.md: checkpoint tasks must follow Required Checkpoints order"
      bad=1
    fi
    previous_checkpoint_line=$line_number
    later_task=$(awk -v start="$line_number" '
      NR <= start {next}
      /^## / {exit}
      /^- \[[ xX]\] T[0-9][0-9][0-9]([[:space:]]|$)/ {print; exit}
    ' "$TASKS")
    if [[ -n "$later_task" ]]; then
      fail "tasks.md: checkpoint $id must be the final task in its phase"
      bad=1
    fi
    phase_heading=$(awk -v stop="$line_number" 'NR > stop {exit} /^## / {heading=$0} END {print heading}' "$TASKS")
    case "$id" in
      REV-FOUNDATION)
        printf '%s\n' "$phase_heading" | grep -Ei '^## Phase .*Foundational' >/dev/null 2>&1 || {
          fail "tasks.md: REV-FOUNDATION must close the Foundational phase"; bad=1;
        }
        if printf '%s\n' "$line" | grep -Eq '\[US[1-9][0-9]*\]'; then
          fail "tasks.md: REV-FOUNDATION must not carry a user-story label"
          bad=1
        fi
        ;;
      REV-US*)
        story=${id#REV-US}
        printf '%s\n' "$phase_heading" | grep -E "User Story[[:space:]]+${story}([^0-9]|$)" >/dev/null 2>&1 || {
          fail "tasks.md: $id must close User Story $story"; bad=1;
        }
        if ! printf '%s\n' "$line" | grep -F "[US$story]" >/dev/null 2>&1; then
          fail "tasks.md: $id checkpoint task must carry [US$story]"
          bad=1
        fi
        ;;
      REV-FINAL)
        if [[ $(awk -v start="$line_number" 'NR > start && /^- \[[ xX]\] T[0-9][0-9][0-9]([[:space:]]|$)/ {n++} END {print n+0}' "$TASKS") -ne 0 ]]; then
          fail "tasks.md: REV-FINAL must be the final task in tasks.md"
          bad=1
        fi
        if printf '%s\n' "$line" | grep -Eq '\[US[1-9][0-9]*\]'; then
          fail "tasks.md: REV-FINAL must not carry a user-story label"
          bad=1
        fi
        ;;
    esac
  done < "$TMP_DIR/required-checkpoints"

  while IFS= read -r story; do
    [[ -n "$story" ]] || continue
    if [[ $(grep -Fxc -- "REV-US$story" "$TMP_DIR/required-checkpoints" || true) -ne 1 ]]; then
      fail "tasks.md: User Story $story phase requires exactly one REV-US$story contract checkpoint"
      bad=1
    fi
  done < <(sed -n 's/^## Phase .*User Story \([1-9][0-9]*\)\([^0-9].*\)\{0,1\}$/\1/p' "$TASKS" | LC_ALL=C sort -u)

  sed -n 's/^## Phase .*User Story \([1-9][0-9]*\)\([^0-9].*\)\{0,1\}$/\1/p' "$TASKS" \
    | LC_ALL=C sort | uniq -d > "$TMP_DIR/duplicate-story-phases"
  if [[ -s "$TMP_DIR/duplicate-story-phases" ]]; then
    fail "tasks.md: each User Story n may have only one actual phase"
    bad=1
  fi

  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if ! grep -Fqx -- "$id" "$TMP_DIR/required-checkpoints"; then
      fail "tasks.md: checkpoint task $id is not declared by the plan"
      bad=1
    fi
  done < "$checkpoint_ids"
  if [[ $(awk 'NF {n++} END {print n+0}' "$checkpoint_ids") -ne $(awk 'NF {n++} END {print n+0}' "$TMP_DIR/required-checkpoints") ]]; then
    fail "tasks.md: checkpoint task set does not match Required Checkpoints"
    bad=1
  fi

  [[ "$bad" -eq 0 ]] && pass "tasks.md: review checkpoints are declared once, serial, and phase-final"
  if [[ -f "$SOURCE_ENTRY" ]]; then
    check_source_task_trace
  fi
}

check_source_task_trace() {
  local recorded actual bundle="$TMP_DIR/source-task-bundle" ids="$TMP_DIR/source-task-required-ids"
  local id path line bad=0 noncheckpoint="$TMP_DIR/source-noncheckpoint-tasks"
  recorded=$(sed -n 's/^\*\*Source-Design-Content-SHA256\*\*: `\([0-9a-f]*\)`$/\1/p' "$TASKS")
  actual=$(source_design_content_hash) || actual=''
  if [[ $(grep -c '^\*\*Source-Design-Content-SHA256\*\*:' "$TASKS" || true) -ne 1 ]] ||
     ! is_lower_hex64 "$recorded" || [[ "$recorded" != "$actual" ]]; then
    fail "tasks.md: source-enabled tasks require the current Source-Design-Content-SHA256"
    bad=1
  else
    pass "tasks.md: Source Design content hash is current"
  fi
  awk '
    /^- \[[ xX]\] T[0-9][0-9][0-9]([[:space:]]|$)/ &&
    $0 !~ /GateSpec review checkpoint REV-(FOUNDATION|US[1-9][0-9]*|FINAL):/ {print}
  ' "$TASKS" > "$noncheckpoint"
  while IFS= read -r line; do
    if ! printf '%s\n' "$line" | grep -Eq 'SD-(F|U|FLOW|ALG|FAIL|TEST)[1-9][0-9]*'; then
      fail "tasks.md: every non-checkpoint task needs at least one SD-* reference"
      bad=1
    fi
    if ! printf '%s\n' "$line" | grep -Eq '(^|[[:space:]`(])([[:alnum:]_.-]+/)+[[:alnum:]_.-]+([[:space:]`),;:]|$)'; then
      fail "tasks.md: every source-enabled non-checkpoint task needs a precise repository-relative path"
      bad=1
    fi
  done < "$noncheckpoint"
  source_bundle_concat > "$bundle"
  grep -E '^### SD-(F|U|FLOW|ALG|FAIL|TEST)[1-9][0-9]*:' "$bundle" \
    | sed -n 's/^### \(SD-[A-Z]*[1-9][0-9]*\):.*/\1/p' > "$ids" || true
  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    if ! grep -E "^- \[[ xX]\] T[0-9][0-9][0-9].*${id}([^0-9]|$)" "$noncheckpoint" >/dev/null 2>&1; then
      fail "tasks.md: no executable non-checkpoint task covers $id"
      bad=1
    fi
  done < "$ids"
  if [[ ! -s "$TMP_DIR/source-manifest-paths" ]]; then
    check_source_blocks "$bundle"
  fi
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if ! grep -F -- "$path" "$noncheckpoint" >/dev/null 2>&1; then
      fail "tasks.md: Source Change Manifest path '$path' has no task coverage"
      bad=1
    fi
  done < "$TMP_DIR/source-manifest-paths"
  [[ "$bad" -eq 0 ]] && pass "tasks.md: every Source item and changed path maps to executable work"
}

review_scope_for_id() {
  case "$1" in
    REV-TASKS) printf '%s' 'TASKS' ;;
    REV-FOUNDATION) printf '%s' 'FOUNDATION' ;;
    REV-US*) printf '%s' "${1#REV-}" ;;
    REV-FINAL) printf '%s' 'FINAL' ;;
    *) return 1 ;;
  esac
}

check_exact_h2_order() {
  local file="$1" context="$2" name lines line last=0 bad=0 expected_count=0 actual_count
  shift 2
  for name in "$@"; do
    expected_count=$((expected_count + 1))
    lines=$(awk -v exact="## $name" '$0 == exact {print NR}' "$file")
    if [[ $(printf '%s\n' "$lines" | awk 'NF {n++} END {print n+0}') -ne 1 ]]; then
      fail "$context: expected exactly one '## $name' section"
      bad=1
      continue
    fi
    line=$lines
    if [[ "$line" -le "$last" ]]; then
      fail "$context: section '## $name' is out of order"
      bad=1
    fi
    last=$line
  done
  actual_count=$(grep -c '^## ' "$file" || true)
  if [[ "$actual_count" -ne "$expected_count" ]]; then
    fail "$context: only the fixed H2 sections are allowed"
    bad=1
  fi
  [[ "$bad" -eq 0 ]] && pass "$context: required sections are exact, unique, and ordered"
}

check_receipt_line_whitelist() {
  local file="$1" kind="$2" context="$3" invalid="$TMP_DIR/receipt-invalid-lines"
  awk -v kind="$kind" '
    function request_pre(line) {
      return line ~ /^- \*\*(Protocol-Version|Review-ID|Round|Scope|Spec-Content-SHA256|Plan-Content-SHA256|Design-Attachments-SHA256|Tasks-Definition-SHA256|Execution-Epoch|Source-Design-Content-SHA256|Implementation-Adjustments-SHA256|Task-Handoff-Commit|Preserved-Reviews-SHA256|Implementation-Baseline|Base-Commit|Subject-Commit|Task-IDs|Changed-Paths-SHA256|Final-Delta-SHA256|Previous-Verdict-SHA256)\*\*: `[^`]+`$/
    }
    function verdict_pre(line) {
      return line ~ /^- \*\*(Protocol-Version|Review-ID|Round|Request-SHA256|Reviewer-Platform|Reviewer-Context-ID|Isolation|Status)\*\*: `[^`]+`$/
    }
    function seal_field(line) {
      return line ~ /^- \*\*(Protocol-Version|Review-ID|Round|Status|Request-SHA256|Verdict-SHA256|Spec-Content-SHA256|Plan-Content-SHA256|Design-Attachments-SHA256|Tasks-Definition-SHA256|Execution-Epoch|Source-Design-Content-SHA256|Implementation-Adjustments-SHA256|Task-Handoff-Commit|Preserved-Reviews-SHA256|Implementation-Baseline|Base-Commit|Subject-Commit|Final-Delta-SHA256|Sealed-At|Seal-SHA256)\*\*: `[^`]+`$/
    }
    /^[[:space:]]*$/ {next}
    kind == "request" {
      if (state == 0 && request_pre($0)) next
      if (state == 0 && $0 == "## Required Tests") {state=1; next}
      if (state == 1 && $0 ~ /^- [^[:space:]](.*[^[:space:]])?$/ && $0 !~ /^- \*\*Request-SHA256\*\*:/) next
      if (state == 1 && $0 ~ /^- \*\*Request-SHA256\*\*: `[^`]+`$/) {state=2; next}
      print NR ":" $0
      next
    }
    kind == "verdict" {
      if (state == 0 && verdict_pre($0)) next
      if ($0 == "## Tests Run" || $0 == "## Blockers" || $0 == "## Observations" || $0 == "## Limitations") {state=1; next}
      if (state == 1 && $0 ~ /^- [^[:space:]](.*[^[:space:]])?$/ && $0 !~ /^- \*\*Verdict-SHA256\*\*:/) next
      if (state == 1 && $0 ~ /^- \*\*Verdict-SHA256\*\*: `[^`]+`$/) {state=2; next}
      print NR ":" $0
      next
    }
    kind == "seal" {
      if (seal_field($0)) next
      print NR ":" $0
    }
  ' "$file" > "$invalid"
  if [[ -s "$invalid" ]]; then
    fail "$context: receipt contains non-canonical heading, field, or prose"
  else
    pass "$context: every nonblank line belongs to the canonical receipt schema"
  fi
}

required_test_strings() {
  local id="$1" scope="$2" mapped final
  if [[ "$scope" == 'TASKS' ]]; then
    printf '%s\n' 'Not run — task-plan review'
    return
  fi
  mapped=$(awk -F '\t' -v wanted="$id" '$1 == wanted { print $2; exit }' "$TMP_DIR/checkpoint-test-mapping")
  [[ -n "$mapped" ]] && printf '%s\n' "$mapped"
  if [[ "$id" == 'REV-FINAL' ]]; then
    final=$(awk 'NR == 1 { print }' "$TMP_DIR/final-validation")
    [[ -n "$final" && "$final" != "$mapped" ]] && printf '%s\n' "$final"
  fi
}

check_request_tests() {
  local file="$1" scope="$2" context="$3" id="$4" body="$TMP_DIR/request-tests"
  local bullets invalid malformed
  receipt_section_body "$file" 'Required Tests' 'Request-SHA256' > "$body"
  bullets=$(grep -cE '^- [^[:space:]](.*[^[:space:]])?$' "$body" || true)
  malformed=$(grep -vE '^[[:space:]]*$|^- [^[:space:]](.*[^[:space:]])?$' "$body" || true)
  if [[ "$bullets" -lt 1 || -n "$malformed" ]]; then
    fail "$context: Required Tests must contain at least one well-formed bullet and no other body text"
    return
  fi
  awk 'NF' "$body" > "$TMP_DIR/request-tests-actual"
  required_test_strings "$id" "$scope" | sed 's/^/- /' > "$TMP_DIR/request-tests-expected"
  if ! cmp -s "$TMP_DIR/request-tests-expected" "$TMP_DIR/request-tests-actual"; then
    fail "$context: Required Tests must exactly match the approved checkpoint mapping"
    return
  fi
  invalid=$(grep -E '^- (None|Not run)([[:space:]]|$)' "$body" || true)
  if [[ "$scope" != 'TASKS' && -n "$invalid" ]]; then
    fail "$context: implementation Required Tests must name a real command or scenario"
    return
  fi
  pass "$context: Required Tests exactly matches the approved checkpoint mapping"
}

check_verdict_test_results() {
  local file="$1" id="$2" scope="$3" context="$4" required bad=0
  if [[ "$scope" == 'TASKS' ]]; then
    if [[ $(awk 'NF {n++} END {print n+0}' "$file") -ne 1 ]] ||
       ! grep -Fqx -- '- Not run — task-plan review' "$file"; then
      fail "$context: TASKS Tests Run must be exactly '- Not run — task-plan review'"
    else
      pass "$context: TASKS Tests Run records the fixed task-plan exception"
    fi
    return
  fi
  required_test_strings "$id" "$scope" > "$TMP_DIR/verdict-required-tests"
  while IFS= read -r required; do
    [[ -n "$required" ]] || continue
    if ! awk -v required="$required" '
      /^- / {
        text=substr($0, 3)
        position=index(text, required)
        if (position > 0) {
          before=substr(text, 1, position - 1)
          after=substr(text, position + length(required))
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", before)
          gsub(/^[[:space:]]+|[[:space:]]+$/, "", after)
          if (before != "" || after != "") found=1
        }
      }
      END { exit !found }
    ' "$file"; then
      fail "$context: Tests Run must contain approved test '$required' plus its result"
      bad=1
    fi
  done < "$TMP_DIR/verdict-required-tests"
  [[ "$bad" -eq 0 ]] && pass "$context: Tests Run covers every approved test with result text"
}

check_task_ids_field() {
  local value="$1" context="$2" id reconstructed='' separator='' bad=0
  if [[ "$value" == 'none' ]]; then
    return
  fi
  printf '%s\n' "$value" | tr ',' '\n' > "$TMP_DIR/request-task-ids"
  while IFS= read -r id; do
    if ! printf '%s\n' "$id" | grep -Eq '^T[0-9][0-9][0-9]$'; then
      fail "$context: Task-IDs must be 'none' or a comma-only T### list"
      bad=1
      continue
    fi
    if [[ $(grep -Ec "^- \\[[ xX]\\] ${id}([[:space:]]|$)" "$TASKS" || true) -ne 1 ]]; then
      fail "$context: Task-ID $id is not unique in tasks.md"
      bad=1
    fi
    reconstructed="${reconstructed}${separator}${id}"
    separator=','
  done < "$TMP_DIR/request-task-ids"
  if [[ "$reconstructed" != "$value" ]]; then
    fail "$context: Task-IDs must use canonical comma-only formatting"
    bad=1
  fi
  [[ "$bad" -eq 0 ]] && pass "$context: Task-IDs resolve uniquely in tasks.md"
}

expected_implementation_task_ids() {
  local id="$1" checkpoint_line phase_line
  if [[ "$id" == 'REV-FINAL' ]]; then
    awk '
      /^- \[[ xX]\] T[0-9][0-9][0-9]([[:space:]]|$)/ &&
      $0 !~ /GateSpec review checkpoint REV-(FOUNDATION|US[1-9][0-9]*|FINAL):/ {
        value=substr($0, index($0, "T"), 4)
        output=output separator value
        separator=","
      }
      END { print output }
    ' "$TASKS"
    return
  fi
  checkpoint_line=$(grep -nE "^- \[[ xX]\] T[0-9][0-9][0-9].*GateSpec review checkpoint ${id}:" "$TASKS" | cut -d: -f1)
  [[ "$checkpoint_line" =~ ^[0-9]+$ ]] || return 1
  if [[ "$id" == 'REV-FOUNDATION' ]]; then
    phase_line=0
  else
    phase_line=$(awk -v stop="$checkpoint_line" 'NR >= stop {exit} /^## / {line=NR} END {print line}' "$TASKS")
  fi
  [[ "$phase_line" =~ ^[0-9]+$ ]] || return 1
  awk -v start="$phase_line" -v stop="$checkpoint_line" '
    NR <= start || NR >= stop {next}
    /^- \[[ xX]\] T[0-9][0-9][0-9]([[:space:]]|$)/ &&
    $0 !~ /GateSpec review checkpoint REV-(FOUNDATION|US[1-9][0-9]*|FINAL):/ {
      value=substr($0, index($0, "T"), 4)
      output=output separator value
      separator=","
    }
    END { print output }
  ' "$TASKS"
}

git_changed_paths_hash() {
  local repo="$1" base="$2" subject="$3" list="$TMP_DIR/git-changed-paths"
  if ! git -C "$repo" diff --no-renames --name-only "$base" "$subject" > "$list" 2>/dev/null; then
    return 1
  fi
  LC_ALL=C sort "$list" | portable_sha256 | awk '{print $1}'
}

check_request_file() {
  local file="$1" expected_id="$2" expected_round="$3" expected_scope="$4"
  local bind_current="$5" previous_hash="$6" context
  local protocol id round scope spec_hash plan_hash attachments_hash tasks_hash
  local baseline base subject task_ids changed final_delta previous actual_changed actual_final expected_task_ids bad=0
  local execution_epoch source_hash ia_hash task_handoff preserved request_protocol expected_protocol
  local previous_line tests_line hash_line
  context=$(basename "$file")

  if [[ ! -f "$file" ]]; then
    fail "$context: request file not found"
    return
  fi
  check_receipt_line_whitelist "$file" request "$context"
  request_protocol=$(markdown_field_value "$file" 'Protocol-Version')
  if [[ "$request_protocol" == 2 ]]; then
    check_ordered_fields "$file" "$context" \
      'Protocol-Version' 'Review-ID' 'Round' 'Scope' 'Spec-Content-SHA256' \
      'Plan-Content-SHA256' 'Design-Attachments-SHA256' 'Tasks-Definition-SHA256' \
      'Execution-Epoch' 'Source-Design-Content-SHA256' 'Implementation-Adjustments-SHA256' \
      'Task-Handoff-Commit' 'Preserved-Reviews-SHA256' 'Implementation-Baseline' \
      'Base-Commit' 'Subject-Commit' 'Task-IDs' 'Changed-Paths-SHA256' \
      'Final-Delta-SHA256' 'Previous-Verdict-SHA256' 'Request-SHA256'
  else
    check_ordered_fields "$file" "$context" \
      'Protocol-Version' 'Review-ID' 'Round' 'Scope' 'Spec-Content-SHA256' \
      'Plan-Content-SHA256' 'Design-Attachments-SHA256' 'Tasks-Definition-SHA256' \
      'Implementation-Baseline' 'Base-Commit' 'Subject-Commit' 'Task-IDs' \
      'Changed-Paths-SHA256' 'Previous-Verdict-SHA256' 'Request-SHA256'
  fi
  check_exact_h2_order "$file" "$context" 'Required Tests'

  previous_line=$(markdown_field_line_numbers "$file" 'Previous-Verdict-SHA256')
  tests_line=$(awk '$0 == "## Required Tests" {print NR}' "$file")
  hash_line=$(markdown_field_line_numbers "$file" 'Request-SHA256')
  if ! [[ "$previous_line" =~ ^[0-9]+$ && "$tests_line" =~ ^[0-9]+$ && "$hash_line" =~ ^[0-9]+$ ]] ||
     (( previous_line >= tests_line || tests_line >= hash_line )); then
    fail "$context: Required Tests must follow Previous-Verdict-SHA256 and precede Request-SHA256"
    bad=1
  fi

  protocol=$(markdown_field_value "$file" 'Protocol-Version')
  id=$(markdown_field_value "$file" 'Review-ID')
  round=$(markdown_field_value "$file" 'Round')
  scope=$(markdown_field_value "$file" 'Scope')
  spec_hash=$(markdown_field_value "$file" 'Spec-Content-SHA256')
  plan_hash=$(markdown_field_value "$file" 'Plan-Content-SHA256')
  attachments_hash=$(markdown_field_value "$file" 'Design-Attachments-SHA256')
  tasks_hash=$(markdown_field_value "$file" 'Tasks-Definition-SHA256')
  execution_epoch=$(markdown_field_value "$file" 'Execution-Epoch')
  source_hash=$(markdown_field_value "$file" 'Source-Design-Content-SHA256')
  ia_hash=$(markdown_field_value "$file" 'Implementation-Adjustments-SHA256')
  task_handoff=$(markdown_field_value "$file" 'Task-Handoff-Commit')
  preserved=$(markdown_field_value "$file" 'Preserved-Reviews-SHA256')
  baseline=$(markdown_field_value "$file" 'Implementation-Baseline')
  base=$(markdown_field_value "$file" 'Base-Commit')
  subject=$(markdown_field_value "$file" 'Subject-Commit')
  task_ids=$(markdown_field_value "$file" 'Task-IDs')
  changed=$(markdown_field_value "$file" 'Changed-Paths-SHA256')
  final_delta=$(markdown_field_value "$file" 'Final-Delta-SHA256')
  previous=$(markdown_field_value "$file" 'Previous-Verdict-SHA256')

  expected_protocol=${ACTIVE_REVIEW_PROTOCOL:-1}
  [[ "$protocol" == "$expected_protocol" ]] || { fail "$context: Protocol-Version must match active protocol '$expected_protocol'"; bad=1; }
  [[ "$id" == "$expected_id" ]] || { fail "$context: Review-ID must be $expected_id"; bad=1; }
  [[ "$round" == "$expected_round" ]] || { fail "$context: Round must be $expected_round"; bad=1; }
  [[ "$scope" == "$expected_scope" ]] || { fail "$context: Scope must be $expected_scope"; bad=1; }
  [[ "$previous" == "$previous_hash" ]] || { fail "$context: Previous-Verdict-SHA256 does not chain to the prior round"; bad=1; }
  for digest in "$spec_hash" "$plan_hash" "$attachments_hash" "$tasks_hash"; do
    if ! is_lower_hex64 "$digest"; then
      fail "$context: artifact hashes must be lowercase 64-hex"
      bad=1
      break
    fi
  done

  if [[ "$bind_current" == 'yes' ]]; then
    [[ "$spec_hash" == "$CURRENT_SPEC_HASH" ]] || { fail "$context: spec content hash is stale"; bad=1; }
    [[ "$plan_hash" == "$CURRENT_PLAN_HASH" ]] || { fail "$context: plan content hash is stale"; bad=1; }
    [[ "$attachments_hash" == "$CURRENT_ATTACHMENTS_HASH" ]] || { fail "$context: design attachments hash is stale"; bad=1; }
    [[ "$tasks_hash" == "$CURRENT_TASKS_HASH" ]] || { fail "$context: normalized tasks definition hash is stale"; bad=1; }
  fi

  if [[ "$protocol" == 2 ]]; then
    [[ "$execution_epoch" == "$CURRENT_EXECUTION_EPOCH" ]] || { fail "$context: Execution-Epoch is stale"; bad=1; }
    [[ "$task_handoff" == "$CURRENT_TASK_HANDOFF" ]] || { fail "$context: Task-Handoff-Commit is stale"; bad=1; }
    [[ "$preserved" == "$CURRENT_PRESERVED_HASH" ]] || { fail "$context: Preserved-Reviews-SHA256 is stale"; bad=1; }
    if [[ -f "$SOURCE_ENTRY" ]]; then expected_source=$(source_design_content_hash) || expected_source=''
    else expected_source=not-applicable; fi
    [[ "$source_hash" == "$expected_source" ]] || { fail "$context: Source-Design-Content-SHA256 is stale"; bad=1; }
    if [[ "$expected_scope" == TASKS ]]; then
      if [[ -f "$SOURCE_ENTRY" ]]; then
        if [[ -z "$GIT_ROOT" ]] || ! resolve_git_feature_paths ||
           ! git -C "$GIT_ROOT" show "$task_handoff:$GIT_FEATURE_REL/.gatespec/implementation-adjustments.md" \
             > "$TMP_DIR/task-handoff-ia" 2>/dev/null; then
          fail "$context: Task-Handoff-Commit must contain the empty IA baseline"
          bad=1
        elif [[ "$ia_hash" != $(file_hash "$TMP_DIR/task-handoff-ia") ]]; then
          fail "$context: task handoff IA snapshot hash is stale"
          bad=1
        elif [[ $(markdown_field_value "$TMP_DIR/task-handoff-ia" 'Execution-Epoch') != "$execution_epoch" ]] ||
             [[ $(markdown_field_value "$TMP_DIR/task-handoff-ia" 'Source-Design-Content-SHA256') != "$source_hash" ]] ||
             grep -Eq '^### IA[1-9][0-9]*:' "$TMP_DIR/task-handoff-ia" ||
             [[ $(grep -cE '^- None —[[:space:]]*[^[:space:]].*$' "$TMP_DIR/task-handoff-ia" || true) -ne 1 ]]; then
          fail "$context: Task-Handoff-Commit IA baseline must be empty and bind the receipt epoch and Source hash"
          bad=1
        else
          pass "$context: task review binds the empty IA snapshot in Task-Handoff-Commit"
        fi
      elif [[ "$ia_hash" != not-applicable ]]; then
        fail "$context: IA must be not-applicable without Source Design"
        bad=1
      fi
    elif [[ "$ia_hash" != not-applicable ]] && ! is_lower_hex64 "$ia_hash"; then
      fail "$context: Implementation-Adjustments-SHA256 must be not-applicable or lowercase 64-hex"; bad=1
    fi
  elif [[ -n "$execution_epoch$source_hash$ia_hash$task_handoff$preserved$final_delta" ]]; then
    fail "$context: Protocol v1 must not contain Protocol v2 fields"
    bad=1
  fi

  check_task_ids_field "$task_ids" "$context"
  if [[ "$expected_scope" == 'TASKS' ]]; then
    if [[ "$baseline" != 'not-applicable' || "$base" != 'not-applicable' ||
          "$subject" != 'not-applicable' || "$changed" != 'not-applicable' ]]; then
      fail "$context: TASKS review Git fields must be 'not-applicable'"
      bad=1
    fi
    if [[ "$protocol" == 2 && "$final_delta" != not-applicable ]]; then
      fail "$context: TASKS Final-Delta-SHA256 must be not-applicable"
      bad=1
    fi
  else
    if [[ "$task_ids" == 'none' ]]; then
      fail "$context: implementation Task-IDs must not be 'none'"
      bad=1
    fi
    expected_task_ids=$(expected_implementation_task_ids "$expected_id") || expected_task_ids=''
    if [[ "$task_ids" != "$expected_task_ids" ]]; then
      fail "$context: Task-IDs must exactly match the non-checkpoint tasks for $expected_id in tasks.md order"
      bad=1
    else
      pass "$context: Task-IDs exactly binds the $expected_id task scope"
    fi
    if ! is_git_oid "$baseline" || ! is_git_oid "$base" || ! is_git_oid "$subject"; then
      fail "$context: implementation Git fields must be lowercase commit OIDs"
      bad=1
    elif [[ -z "$GIT_ROOT" ]]; then
      fail "$context: implementation review requires a Git worktree"
      bad=1
    elif ! git -C "$GIT_ROOT" cat-file -e "${baseline}^{commit}" 2>/dev/null ||
         ! git -C "$GIT_ROOT" cat-file -e "${base}^{commit}" 2>/dev/null ||
         ! git -C "$GIT_ROOT" cat-file -e "${subject}^{commit}" 2>/dev/null; then
      fail "$context: baseline/base/subject must resolve to commits"
      bad=1
    elif [[ "$protocol" == 2 && "$expected_id" == REV-FINAL ]]; then
      if [[ "$base" != "$CURRENT_ORIGINAL_BASELINE" ]] ||
         ! git -C "$GIT_ROOT" merge-base --is-ancestor "$base" "$baseline" 2>/dev/null ||
         ! git -C "$GIT_ROOT" merge-base --is-ancestor "$baseline" "$subject" 2>/dev/null; then
        fail "$context: v2 FINAL must use Original Baseline and preserve original -> handoff baseline -> subject ancestry"
        bad=1
      else
        actual_changed=$(git_changed_paths_hash "$GIT_ROOT" "$base" "$subject") || actual_changed=''
        if [[ "$changed" != "$actual_changed" ]]; then
          fail "$context: Changed-Paths-SHA256 does not match base..subject"
          bad=1
        else
          pass "$context: Git commits, ancestry, and changed-path hash agree"
        fi
      fi
    elif ! git -C "$GIT_ROOT" merge-base --is-ancestor "$baseline" "$base" 2>/dev/null ||
         ! git -C "$GIT_ROOT" merge-base --is-ancestor "$base" "$subject" 2>/dev/null; then
      fail "$context: Git ancestry must be baseline -> base -> subject"
      bad=1
    else
      actual_changed=$(git_changed_paths_hash "$GIT_ROOT" "$base" "$subject") || actual_changed=''
      if [[ "$changed" != "$actual_changed" ]]; then
        fail "$context: Changed-Paths-SHA256 does not match base..subject"
        bad=1
      else
        pass "$context: Git commits, ancestry, and changed-path hash agree"
      fi
    fi
    if [[ "$protocol" == 2 ]]; then
      if [[ -f "$SOURCE_ENTRY" ]]; then
        if ! resolve_git_feature_paths || ! git -C "$GIT_ROOT" show "$subject:$GIT_FEATURE_REL/.gatespec/implementation-adjustments.md" > "$TMP_DIR/request-subject-ia" 2>/dev/null; then
          fail "$context: Subject-Commit must contain the complete IA snapshot"
          bad=1
        elif [[ "$ia_hash" != $(file_hash "$TMP_DIR/request-subject-ia") ]]; then
          fail "$context: Implementation-Adjustments-SHA256 does not match Subject-Commit"
          bad=1
        fi
      elif [[ "$ia_hash" != not-applicable ]]; then
        fail "$context: IA must be not-applicable without Source Design"
        bad=1
      fi
      if [[ "$expected_id" == REV-FINAL ]]; then
        actual_final=$(git_final_delta_hash "$GIT_ROOT" "$CURRENT_ORIGINAL_BASELINE" "$subject") || actual_final=''
        if ! is_lower_hex64 "$final_delta" || [[ "$final_delta" != "$actual_final" ]]; then
          fail "$context: Final-Delta-SHA256 does not match the raw Original-Baseline..Subject tree delta"
          bad=1
        else
          pass "$context: raw Final-Delta-SHA256 binds content/mode changes, not only path names"
        fi
      elif [[ "$final_delta" != not-applicable ]]; then
        fail "$context: Final-Delta-SHA256 is only applicable to REV-FINAL"
        bad=1
      fi
    fi
  fi

  check_request_tests "$file" "$expected_scope" "$context" "$expected_id"
  check_self_hash "$file" 'Request-SHA256' "$context"
  [[ "$bad" -eq 0 ]] && pass "$context: request fields match review scope and current artifact contract"
}

check_verdict_file() {
  local file="$1" expected_id="$2" expected_round="$3" expected_request_hash="$4" expected_scope="$5"
  local expected_protocol="${6:-1}"
  local context protocol id round request_hash platform context_id isolation status
  local body nonblank blockers malformed bad=0 status_line tests_line hash_line
  context=$(basename "$file")
  CHECKED_VERDICT_STATUS=''
  CHECKED_VERDICT_HASH=''
  if [[ ! -f "$file" ]]; then
    fail "$context: verdict file not found"
    return
  fi
  check_receipt_line_whitelist "$file" verdict "$context"
  check_ordered_fields "$file" "$context" \
    'Protocol-Version' 'Review-ID' 'Round' 'Request-SHA256' 'Reviewer-Platform' \
    'Reviewer-Context-ID' 'Isolation' 'Status' 'Verdict-SHA256'
  check_exact_h2_order "$file" "$context" 'Tests Run' 'Blockers' 'Observations' 'Limitations'

  status_line=$(markdown_field_line_numbers "$file" 'Status')
  tests_line=$(awk '$0 == "## Tests Run" {print NR}' "$file")
  hash_line=$(markdown_field_line_numbers "$file" 'Verdict-SHA256')
  if ! [[ "$status_line" =~ ^[0-9]+$ && "$tests_line" =~ ^[0-9]+$ && "$hash_line" =~ ^[0-9]+$ ]] ||
     (( status_line >= tests_line || tests_line >= hash_line )); then
    fail "$context: verdict sections must follow Status and precede Verdict-SHA256"
    bad=1
  fi

  protocol=$(markdown_field_value "$file" 'Protocol-Version')
  id=$(markdown_field_value "$file" 'Review-ID')
  round=$(markdown_field_value "$file" 'Round')
  request_hash=$(markdown_field_value "$file" 'Request-SHA256')
  platform=$(markdown_field_value "$file" 'Reviewer-Platform')
  context_id=$(markdown_field_value "$file" 'Reviewer-Context-ID')
  isolation=$(markdown_field_value "$file" 'Isolation')
  status=$(markdown_field_value "$file" 'Status')
  CHECKED_VERDICT_HASH=$(markdown_field_value "$file" 'Verdict-SHA256')
  CHECKED_VERDICT_STATUS=$status

  [[ "$protocol" == "$expected_protocol" ]] || { fail "$context: Protocol-Version must match request protocol '$expected_protocol'"; bad=1; }
  [[ "$id" == "$expected_id" ]] || { fail "$context: Review-ID must be $expected_id"; bad=1; }
  [[ "$round" == "$expected_round" ]] || { fail "$context: Round must be $expected_round"; bad=1; }
  [[ "$request_hash" == "$expected_request_hash" ]] || { fail "$context: Request-SHA256 does not match its request"; bad=1; }
  case "$platform" in
    codex|claude|manual-codex|manual-claude) ;;
    *) fail "$context: Reviewer-Platform is not an allowed adapter"; bad=1 ;;
  esac
  if [[ -z "$context_id" || "$context_id" == \[* ]]; then
    fail "$context: Reviewer-Context-ID must be nonempty"
    bad=1
  fi
  [[ "$isolation" == 'fresh' ]] || { fail "$context: Isolation must declare 'fresh'"; bad=1; }
  if [[ "$isolation" == 'fresh' && -n "$context_id" ]]; then
    pass "$context: receipt declares fresh isolation (context identity is not machine-verifiable)"
  fi
  case "$status" in
    PASS|BLOCKED) ;;
    *) fail "$context: Status must be PASS or BLOCKED"; bad=1 ;;
  esac

  receipt_section_body "$file" 'Tests Run' 'Verdict-SHA256' > "$TMP_DIR/verdict-tests"
  nonblank=$(grep -cE '^- [^[:space:]](.*[^[:space:]])?$' "$TMP_DIR/verdict-tests" || true)
  malformed=$(grep -vE '^[[:space:]]*$|^- [^[:space:]](.*[^[:space:]])?$' "$TMP_DIR/verdict-tests" || true)
  if [[ "$expected_scope" == 'TASKS' ]]; then
    if [[ "$nonblank" -lt 1 || -n "$malformed" ]]; then
      fail "$context: Tests Run must contain at least one well-formed bullet"
      bad=1
    elif grep -E '^- (None|Not run)([[:space:]]|$)' "$TMP_DIR/verdict-tests" >/dev/null 2>&1 &&
         ! grep -Fqx -- '- Not run — task-plan review' "$TMP_DIR/verdict-tests"; then
      fail "$context: TASKS verdict may only use the fixed task-plan review exception"
      bad=1
    fi
  elif [[ "$nonblank" -lt 1 || -n "$malformed" ]] || grep -E '^- (None|Not run)([[:space:]]|$)' "$TMP_DIR/verdict-tests" >/dev/null 2>&1; then
    fail "$context: implementation Tests Run must name a real command or scenario"
    bad=1
  fi
  check_verdict_test_results "$TMP_DIR/verdict-tests" "$expected_id" "$expected_scope" "$context"

  receipt_section_body "$file" 'Blockers' 'Verdict-SHA256' > "$TMP_DIR/verdict-blockers"
  nonblank=$(awk 'NF {n++} END {print n+0}' "$TMP_DIR/verdict-blockers")
  blockers=$(grep -cE '^- BLOCKER:[[:space:]]+.+[^[:space:]]$' "$TMP_DIR/verdict-blockers" || true)
  malformed=$(grep -vE '^[[:space:]]*$|^- [^[:space:]](.*[^[:space:]])?$' "$TMP_DIR/verdict-blockers" || true)
  if [[ "$status" == 'PASS' ]]; then
    if [[ "$nonblank" -ne 1 ]] || ! grep -Fqx -- '- None' "$TMP_DIR/verdict-blockers"; then
      fail "$context: PASS verdict Blockers must be exactly '- None'"
      bad=1
    fi
  elif [[ "$blockers" -lt 1 || -n "$malformed" ]] || grep -Fqx -- '- None' "$TMP_DIR/verdict-blockers"; then
    fail "$context: BLOCKED verdict requires at least one '- BLOCKER:' item and must not contain '- None'"
    bad=1
  fi
  for name in Observations Limitations; do
    receipt_section_body "$file" "$name" 'Verdict-SHA256' > "$TMP_DIR/verdict-section"
    nonblank=$(grep -cE '^- [^[:space:]](.*[^[:space:]])?$' "$TMP_DIR/verdict-section" || true)
    malformed=$(grep -vE '^[[:space:]]*$|^- [^[:space:]](.*[^[:space:]])?$' "$TMP_DIR/verdict-section" || true)
    if [[ "$nonblank" -lt 1 || -n "$malformed" ]]; then
      fail "$context: ## $name must contain at least one well-formed bullet"
      bad=1
    fi
  done

  check_self_hash "$file" 'Verdict-SHA256' "$context"
  [[ "$bad" -eq 0 ]] && pass "$context: verdict schema and blocker semantics are valid"
}

check_seal_file() {
  local file="$1" request="$2" verdict="$3" expected_id="$4" expected_round="$5"
  local context protocol id round status request_hash verdict_hash sealed_at bad=0 label expected actual request_protocol
  context=$(basename "$file")
  if [[ ! -f "$file" ]]; then
    fail "$expected_id: PASS seal not found"
    return
  fi
  check_receipt_line_whitelist "$file" seal "$expected_id seal"
  request_protocol=$(markdown_field_value "$request" 'Protocol-Version')
  if [[ "$request_protocol" == 2 ]]; then
    check_ordered_fields "$file" "$expected_id seal" \
      'Protocol-Version' 'Review-ID' 'Round' 'Status' 'Request-SHA256' 'Verdict-SHA256' \
      'Spec-Content-SHA256' 'Plan-Content-SHA256' 'Design-Attachments-SHA256' \
      'Tasks-Definition-SHA256' 'Execution-Epoch' 'Source-Design-Content-SHA256' \
      'Implementation-Adjustments-SHA256' 'Task-Handoff-Commit' 'Preserved-Reviews-SHA256' \
      'Implementation-Baseline' 'Base-Commit' 'Subject-Commit' 'Final-Delta-SHA256' \
      'Sealed-At' 'Seal-SHA256'
  else
    check_ordered_fields "$file" "$expected_id seal" \
      'Protocol-Version' 'Review-ID' 'Round' 'Status' 'Request-SHA256' 'Verdict-SHA256' \
      'Spec-Content-SHA256' 'Plan-Content-SHA256' 'Design-Attachments-SHA256' \
      'Tasks-Definition-SHA256' 'Implementation-Baseline' 'Base-Commit' \
      'Subject-Commit' 'Sealed-At' 'Seal-SHA256'
  fi
  protocol=$(markdown_field_value "$file" 'Protocol-Version')
  id=$(markdown_field_value "$file" 'Review-ID')
  round=$(markdown_field_value "$file" 'Round')
  status=$(markdown_field_value "$file" 'Status')
  request_hash=$(markdown_field_value "$file" 'Request-SHA256')
  verdict_hash=$(markdown_field_value "$file" 'Verdict-SHA256')
  sealed_at=$(markdown_field_value "$file" 'Sealed-At')
  [[ "$protocol" == "$request_protocol" ]] || { fail "$expected_id seal: Protocol-Version must match its request"; bad=1; }
  [[ "$id" == "$expected_id" ]] || { fail "$expected_id seal: Review-ID mismatch"; bad=1; }
  [[ "$round" == "$expected_round" ]] || { fail "$expected_id seal: Round mismatch"; bad=1; }
  [[ "$status" == 'PASS' ]] || { fail "$expected_id seal: Status must be PASS"; bad=1; }
  [[ "$request_hash" == "$(markdown_field_value "$request" 'Request-SHA256')" ]] || {
    fail "$expected_id seal: Request-SHA256 mismatch"; bad=1;
  }
  [[ "$verdict_hash" == "$(markdown_field_value "$verdict" 'Verdict-SHA256')" ]] || {
    fail "$expected_id seal: Verdict-SHA256 mismatch"; bad=1;
  }
  for label in Spec-Content-SHA256 Plan-Content-SHA256 Design-Attachments-SHA256 \
    Tasks-Definition-SHA256 Implementation-Baseline Base-Commit Subject-Commit; do
    expected=$(markdown_field_value "$request" "$label")
    actual=$(markdown_field_value "$file" "$label")
    if [[ "$actual" != "$expected" ]]; then
      fail "$expected_id seal: $label does not match the sealed request"
      bad=1
    fi
  done
  if [[ "$request_protocol" == 2 ]]; then
    for label in Execution-Epoch Source-Design-Content-SHA256 Implementation-Adjustments-SHA256 \
      Task-Handoff-Commit Preserved-Reviews-SHA256 Final-Delta-SHA256; do
      expected=$(markdown_field_value "$request" "$label")
      actual=$(markdown_field_value "$file" "$label")
      if [[ "$actual" != "$expected" ]]; then
        fail "$expected_id seal: $label does not match the sealed request"
        bad=1
      fi
    done
  fi
  if ! printf '%s\n' "$sealed_at" | grep -Eq '^[0-9][0-9][0-9][0-9]-[0-9][0-9]-[0-9][0-9]T[0-9][0-9]:[0-9][0-9]:[0-9][0-9]Z$'; then
    fail "$expected_id seal: Sealed-At must be UTC RFC3339"
    bad=1
  fi
  check_self_hash "$file" 'Seal-SHA256' "$expected_id seal"
  [[ "$bad" -eq 0 ]] && pass "$expected_id: PASS seal binds request, verdict, and artifacts"
}

check_implementation_remediation_commit() {
  local id="$1" prior_round="$2" prior_verdict="$3" prior_subject="$4" subject="$5"
  local review_prefix tasks_rel verdict_rel request_rel finding path meaningful=0 bad=0
  local metadata_paths="$TMP_DIR/remediation-metadata-paths" expected_paths="$TMP_DIR/remediation-expected-paths"
  local product_paths="$TMP_DIR/remediation-product-paths"
  if [[ -z "$GIT_ROOT" ]] || ! resolve_git_feature_paths; then
    fail "$id: cannot verify remediation commits outside the feature Git worktree"
    return
  fi
  review_prefix="$GIT_FEATURE_REL/.gatespec/reviews/"
  tasks_rel="$GIT_FEATURE_REL/tasks.md"
  verdict_rel="${review_prefix}${id}/round-${prior_round}-verdict.md"
  request_rel="${review_prefix}${id}/round-${prior_round}-request.md"
  finding=$(git -C "$GIT_ROOT" log -1 --format=%H -- "$verdict_rel" 2>/dev/null || true)
  if [[ -z "$finding" ]]; then
    fail "$id: prior BLOCKED verdict must have a tracked metadata-only finding commit"
    return
  fi
  if ! git -C "$GIT_ROOT" show "$finding:$verdict_rel" > "$TMP_DIR/finding-verdict" 2>/dev/null ||
     ! cmp -s "$TMP_DIR/finding-verdict" "$prior_verdict"; then
    fail "$id: finding commit must contain the exact prior BLOCKED verdict"
    bad=1
  fi
  if [[ "$finding" == "$prior_subject" ]] ||
     ! git -C "$GIT_ROOT" merge-base --is-ancestor "$prior_subject" "$finding" 2>/dev/null; then
    fail "$id: finding commit must strictly descend from the prior review subject"
    bad=1
  fi
  if [[ "$subject" == "$finding" ]] ||
     ! git -C "$GIT_ROOT" merge-base --is-ancestor "$finding" "$subject" 2>/dev/null; then
    fail "$id: remediation Subject-Commit must strictly descend from the finding commit"
    bad=1
  fi

  git -C "$GIT_ROOT" -c core.quotepath=false diff --no-renames --name-only "$prior_subject" "$finding" \
    | LC_ALL=C sort > "$metadata_paths"
  printf '%s\n' "$request_rel" "$verdict_rel" | LC_ALL=C sort > "$expected_paths"
  if ! cmp -s "$metadata_paths" "$expected_paths"; then
    fail "$id: finding commit must change only its prior request and verdict"
    bad=1
  fi

  git -C "$GIT_ROOT" -c core.quotepath=false diff --no-renames --name-only "$finding" "$subject" \
    | LC_ALL=C sort -u > "$product_paths"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$path" in
      "$review_prefix"*|"$tasks_rel") ;;
      *) meaningful=1 ;;
    esac
  done < "$product_paths"
  if [[ "$meaningful" -ne 1 ]]; then
    fail "$id: remediation subject must contain a real product/test delta after the finding commit"
    bad=1
  fi
  [[ "$bad" -eq 0 ]] && pass "$id: remediation has separate finding and product/test commits"
}

check_review_chain() {
  local id="$1" scope="$2" directory="$FEATURE_DIR/.gatespec/reviews/$1"
  local seal="$directory/seal.md" seal_round seal_number i round request verdict
  local previous='none' request_hash status invalid bad=0 bind_current
  local request_tasks request_baseline request_base request_subject
  local request_spec request_plan request_attachments
  local request_protocol request_epoch request_source request_handoff request_preserved
  local previous_tasks='' previous_baseline='' previous_base='' previous_subject=''
  local previous_spec='' previous_plan='' previous_attachments='' previous_round='' previous_verdict_file=''
  local previous_epoch='' previous_source='' previous_handoff='' previous_preserved=''
  CHAIN_BASELINE=''
  CHAIN_BASE=''
  CHAIN_SUBJECT=''

  if [[ ! -d "$directory" ]]; then
    fail "$id: review directory not found at .gatespec/reviews/$id"
    return
  fi
  invalid=$(find "$directory" -maxdepth 1 -type f \( -name 'round-*-request.md' -o -name 'round-*-verdict.md' \) -print \
    | sed 's|.*/||' | grep -Ev '^round-(00|01|02)-(request|verdict)\.md$' || true)
  if [[ -n "$invalid" ]]; then
    fail "$id: only review rounds 00, 01, and 02 are allowed"
    bad=1
  fi
  if [[ ! -f "$seal" ]]; then
    fail "$id: PASS seal not found"
    return
  fi
  seal_round=$(markdown_field_value "$seal" 'Round')
  if ! printf '%s\n' "$seal_round" | grep -Eq '^(00|01|02)$'; then
    fail "$id seal: Round must be 00, 01, or 02"
    return
  fi
  seal_number=$((10#$seal_round))
  i=0
  while [[ "$i" -le 2 ]]; do
    printf -v round '%02d' "$i"
    request="$directory/round-${round}-request.md"
    verdict="$directory/round-${round}-verdict.md"
    if [[ "$i" -le "$seal_number" ]]; then
      bind_current='no'
      [[ "$i" -eq "$seal_number" ]] && bind_current='yes'
      check_request_file "$request" "$id" "$round" "$scope" "$bind_current" "$previous"
      request_hash=$(markdown_field_value "$request" 'Request-SHA256')
      request_tasks=$(markdown_field_value "$request" 'Tasks-Definition-SHA256')
      request_spec=$(markdown_field_value "$request" 'Spec-Content-SHA256')
      request_plan=$(markdown_field_value "$request" 'Plan-Content-SHA256')
      request_attachments=$(markdown_field_value "$request" 'Design-Attachments-SHA256')
      request_baseline=$(markdown_field_value "$request" 'Implementation-Baseline')
      request_base=$(markdown_field_value "$request" 'Base-Commit')
      request_subject=$(markdown_field_value "$request" 'Subject-Commit')
      request_protocol=$(markdown_field_value "$request" 'Protocol-Version')
      request_epoch=$(markdown_field_value "$request" 'Execution-Epoch')
      request_source=$(markdown_field_value "$request" 'Source-Design-Content-SHA256')
      request_handoff=$(markdown_field_value "$request" 'Task-Handoff-Commit')
      request_preserved=$(markdown_field_value "$request" 'Preserved-Reviews-SHA256')
      if [[ "$i" -gt 0 && "$request_protocol" == 2 ]] &&
         [[ "$request_epoch" != "$previous_epoch" || "$request_source" != "$previous_source" ||
            "$request_handoff" != "$previous_handoff" || "$request_preserved" != "$previous_preserved" ]]; then
        fail "$id round $round: remediation must retain execution epoch, Source, task handoff, and preserved-review bindings"
        bad=1
      fi
      if [[ "$i" -gt 0 && "$scope" == 'TASKS' ]]; then
        if [[ "$request_tasks" == "$previous_tasks" ]]; then
          fail "$id round $round: remediation must change Tasks-Definition-SHA256"
          bad=1
        fi
        if [[ "$request_spec" != "$previous_spec" || "$request_plan" != "$previous_plan" ||
              "$request_attachments" != "$previous_attachments" ]]; then
          fail "$id round $round: task remediation must retain Spec, Plan, and Design-Attachments hashes"
          bad=1
        fi
      elif [[ "$i" -gt 0 && "$scope" != 'TASKS' ]]; then
        if [[ "$request_baseline" != "$previous_baseline" || "$request_base" != "$previous_base" ]]; then
          fail "$id round $round: remediation must retain Implementation-Baseline and Base-Commit"
          bad=1
        fi
        if [[ "$request_spec" != "$previous_spec" || "$request_plan" != "$previous_plan" ||
              "$request_attachments" != "$previous_attachments" || "$request_tasks" != "$previous_tasks" ]]; then
          fail "$id round $round: implementation remediation must retain all approved artifact hashes"
          bad=1
        fi
        if [[ "$request_subject" == "$previous_subject" ]]; then
          fail "$id round $round: remediation must advance Subject-Commit"
          bad=1
        elif [[ -n "$GIT_ROOT" ]] && ! git -C "$GIT_ROOT" merge-base --is-ancestor "$previous_subject" "$request_subject" 2>/dev/null; then
          fail "$id round $round: remediation Subject-Commit must descend from the prior round subject"
          bad=1
        fi
        check_implementation_remediation_commit "$id" "$previous_round" "$previous_verdict_file" \
          "$previous_subject" "$request_subject"
      fi
      check_verdict_file "$verdict" "$id" "$round" "$request_hash" "$scope" "$request_protocol"
      status=$CHECKED_VERDICT_STATUS
      if [[ "$i" -lt "$seal_number" && "$status" != 'BLOCKED' ]]; then
        fail "$id: every pre-seal review round must be BLOCKED"
        bad=1
      elif [[ "$i" -eq "$seal_number" && "$status" != 'PASS' ]]; then
        fail "$id: sealed review round must be PASS"
        bad=1
      fi
      previous=$CHECKED_VERDICT_HASH
      previous_tasks=$request_tasks
      previous_spec=$request_spec
      previous_plan=$request_plan
      previous_attachments=$request_attachments
      previous_baseline=$request_baseline
      previous_base=$request_base
      previous_subject=$request_subject
      previous_epoch=$request_epoch
      previous_source=$request_source
      previous_handoff=$request_handoff
      previous_preserved=$request_preserved
      previous_round=$round
      previous_verdict_file=$verdict
    elif [[ -e "$request" || -e "$verdict" ]]; then
      fail "$id: review files exist after the sealed PASS round"
      bad=1
    fi
    i=$((i + 1))
  done
  request="$directory/round-${seal_round}-request.md"
  verdict="$directory/round-${seal_round}-verdict.md"
  check_seal_file "$seal" "$request" "$verdict" "$id" "$seal_round"
  CHAIN_BASELINE=$(markdown_field_value "$request" 'Implementation-Baseline')
  CHAIN_BASE=$(markdown_field_value "$request" 'Base-Commit')
  CHAIN_SUBJECT=$(markdown_field_value "$request" 'Subject-Commit')
  [[ "$bad" -eq 0 ]] && pass "$id: review rounds form a bounded BLOCKED* -> PASS chain"
}

initialize_review_hashes() {
  CURRENT_SPEC_HASH=$(content_hash "$SPEC") || CURRENT_SPEC_HASH=''
  CURRENT_PLAN_HASH=$(content_hash "$PLAN") || CURRENT_PLAN_HASH=''
  CURRENT_ATTACHMENTS_HASH=$(design_attachments_hash) || CURRENT_ATTACHMENTS_HASH=''
  CURRENT_TASKS_HASH=$(normalized_tasks_hash "$TASKS") || CURRENT_TASKS_HASH=''
  GIT_ROOT=$(git -C "$FEATURE_DIR" rev-parse --show-toplevel 2>/dev/null || true)
}

resolve_git_feature_paths() {
  local repo_abs feature_abs
  GIT_FEATURE_REL=''
  [[ -n "$GIT_ROOT" ]] || return 1
  repo_abs=$(cd "$GIT_ROOT" 2>/dev/null && pwd -P) || return 1
  feature_abs=$(cd "$FEATURE_DIR" 2>/dev/null && pwd -P) || return 1
  case "$feature_abs" in
    "$repo_abs"/*) GIT_FEATURE_REL=${feature_abs#"$repo_abs"/} ;;
    *) return 1 ;;
  esac
}

append_current_artifact_files() {
  local manifest="$1" path
  printf '%s\t%s\n' \
    "$GIT_FEATURE_REL/spec.md" "$SPEC" \
    "$GIT_FEATURE_REL/plan.md" "$PLAN" \
    "$GIT_FEATURE_REL/tasks.md" "$TASKS" >> "$manifest"
  for path in research.md data-model.md quickstart.md; do
    [[ -f "$FEATURE_DIR/$path" ]] && printf '%s\t%s\n' "$GIT_FEATURE_REL/$path" "$FEATURE_DIR/$path" >> "$manifest"
  done
  if [[ -d "$FEATURE_DIR/contracts" ]]; then
    while IFS= read -r path; do
      [[ -f "$path" ]] || continue
      printf '%s\t%s\n' "$GIT_FEATURE_REL/${path#"$FEATURE_DIR"/}" "$path" >> "$manifest"
    done < <(find "$FEATURE_DIR/contracts" -type f -print)
  fi
  [[ -f "$EXECUTION_STATE" ]] && printf '%s\t%s\n' "$GIT_FEATURE_REL/.gatespec/execution-state.md" "$EXECUTION_STATE" >> "$manifest"
  [[ -f "$IA_FILE" ]] && printf '%s\t%s\n' "$GIT_FEATURE_REL/.gatespec/implementation-adjustments.md" "$IA_FILE" >> "$manifest"
  if [[ -d "$FEATURE_DIR/.gatespec/revalidations" ]]; then
    while IFS= read -r path; do
      [[ -f "$path" ]] || continue
      printf '%s\t%s\n' "$GIT_FEATURE_REL/${path#"$FEATURE_DIR"/}" "$path" >> "$manifest"
    done < <(find "$FEATURE_DIR/.gatespec/revalidations" -type f -print)
  fi
  if [[ -f "$SOURCE_ENTRY" ]]; then
    append_review_chain_files 'REV-SOURCE' "$manifest" || return 1
  fi
}

append_review_chain_files() {
  local id="$1" manifest="$2" directory="$FEATURE_DIR/.gatespec/reviews/$1"
  local seal_file="$directory/seal.md" round number i current request verdict prefix
  [[ -f "$seal_file" ]] || return 1
  round=$(markdown_field_value "$seal_file" 'Round')
  [[ "$round" =~ ^(00|01|02)$ ]] || return 1
  number=$((10#$round))
  prefix="$GIT_FEATURE_REL/.gatespec/reviews/$id"
  i=0
  while [[ "$i" -le "$number" ]]; do
    printf -v current '%02d' "$i"
    request="$directory/round-${current}-request.md"
    verdict="$directory/round-${current}-verdict.md"
    printf '%s\t%s\n' \
      "$prefix/round-${current}-request.md" "$request" \
      "$prefix/round-${current}-verdict.md" "$verdict" >> "$manifest"
    i=$((i + 1))
  done
  printf '%s\t%s\n' "$prefix/seal.md" "$seal_file" >> "$manifest"
}

check_head_tracked_manifest() {
  local manifest="$1" context="$2" rel current bad=0
  while IFS=$'\t' read -r rel current; do
    [[ -n "$rel" ]] || continue
    if ! git -C "$GIT_ROOT" ls-files --error-unmatch -- "$rel" >/dev/null 2>&1; then
      fail "$context: '$rel' must be tracked at HEAD"
      bad=1
    elif ! git -C "$GIT_ROOT" show "HEAD:$rel" > "$TMP_DIR/head-required-blob" 2>/dev/null ||
         ! cmp -s "$TMP_DIR/head-required-blob" "$current"; then
      fail "$context: current '$rel' must match its HEAD blob exactly"
      bad=1
    fi
  done < "$manifest"
  [[ "$bad" -eq 0 ]]
}

check_task_review_git_state() {
  local ref status manifest="$TMP_DIR/task-handoff-files"
  if [[ -z "$GIT_ROOT" ]] || ! resolve_git_feature_paths; then
    fail "REV-TASKS: task-review requires the feature to be inside a Git worktree"
    return
  fi
  ref=$(git -C "$GIT_ROOT" symbolic-ref -q HEAD 2>/dev/null || true)
  case "$ref" in
    refs/heads/*) pass "REV-TASKS: HEAD is attached to a local feature branch" ;;
    *) fail "REV-TASKS: HEAD must be attached to a local feature branch" ;;
  esac
  status=$(git -C "$GIT_ROOT" -c core.quotepath=false status --porcelain=v1 --untracked-files=all 2>/dev/null || true)
  if [[ -n "$status" ]]; then
    fail "REV-TASKS: worktree must be clean before speckit.implement"
  else
    pass "REV-TASKS: worktree is clean before speckit.implement"
  fi
  : > "$manifest"
  append_current_artifact_files "$manifest"
  if ! append_review_chain_files 'REV-TASKS' "$manifest"; then
    fail "REV-TASKS: cannot enumerate the sealed review handoff"
  elif check_head_tracked_manifest "$manifest" 'REV-TASKS handoff'; then
    pass "REV-TASKS: approved artifacts and complete receipt chain match tracked HEAD blobs"
  else
    fail "REV-TASKS: tracked handoff is incomplete or stale"
  fi
}

check_baseline_task_seal() {
  local baseline="$1" seal_rel latest path parent_fields bad=0
  local changed="$TMP_DIR/baseline-changed-paths" allowed="$TMP_DIR/baseline-allowed-paths"
  local manifest="$TMP_DIR/baseline-required-files" rel current baseline_tasks_hash task_ia_hash
  if [[ -z "$GIT_ROOT" ]] || ! resolve_git_feature_paths; then
    fail "implementation baseline: feature directory is outside its Git worktree"
    return
  fi
  seal_rel="$GIT_FEATURE_REL/.gatespec/reviews/REV-TASKS/seal.md"
  latest=$(git -C "$GIT_ROOT" log -1 --format=%H -- "$seal_rel" 2>/dev/null || true)
  if [[ -z "$latest" ]]; then
    fail "implementation baseline: REV-TASKS seal has no tracked checkpoint commit"
  elif [[ "$baseline" != "$latest" ]]; then
    fail "implementation baseline: must equal the latest commit that touched the current REV-TASKS seal"
  elif ! git -C "$GIT_ROOT" show "$baseline:$seal_rel" > "$TMP_DIR/baseline-task-seal" 2>/dev/null; then
    fail "implementation baseline: commit does not contain the REV-TASKS seal"
  elif ! cmp -s "$TMP_DIR/baseline-task-seal" "$FEATURE_DIR/.gatespec/reviews/REV-TASKS/seal.md"; then
    fail "implementation baseline: REV-TASKS seal differs from the current validated seal"
  else
    pass "implementation baseline contains the current REV-TASKS PASS seal"
  fi

  parent_fields=$(git -C "$GIT_ROOT" rev-list --parents -n 1 "$baseline" 2>/dev/null | awk '{print NF+0}')
  if [[ "$parent_fields" -gt 2 ]]; then
    fail "implementation baseline: REV-TASKS checkpoint commit must not be a merge"
    return
  fi
  : > "$allowed"
  printf '%s\n' \
    "$GIT_FEATURE_REL/spec.md" "$GIT_FEATURE_REL/plan.md" "$GIT_FEATURE_REL/tasks.md" \
    >> "$allowed"
  [[ -f "$EXECUTION_STATE" ]] && printf '%s\n' "$GIT_FEATURE_REL/.gatespec/execution-state.md" >> "$allowed"
  [[ -f "$IA_FILE" ]] && printf '%s\n' "$GIT_FEATURE_REL/.gatespec/implementation-adjustments.md" >> "$allowed"
  for path in research.md data-model.md quickstart.md; do
    [[ -f "$FEATURE_DIR/$path" ]] && printf '%s\n' "$GIT_FEATURE_REL/$path" >> "$allowed"
  done
  if [[ -d "$FEATURE_DIR/contracts" ]]; then
    while IFS= read -r path; do
      [[ -f "$path" ]] || continue
      printf '%s\n' "$GIT_FEATURE_REL/${path#"$FEATURE_DIR"/}" >> "$allowed"
    done < <(find "$FEATURE_DIR/contracts" -type f -print)
  fi
  if ! git -C "$GIT_ROOT" -c core.quotepath=false diff-tree --root --no-commit-id --name-only -r "$baseline" > "$changed" 2>/dev/null; then
    fail "implementation baseline: cannot inspect checkpoint commit paths"
    return
  fi
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$path" in
      "$GIT_FEATURE_REL/.gatespec/reviews/REV-TASKS/"*) ;;
      "$GIT_FEATURE_REL/.gatespec/reviews/REV-SOURCE/"*) ;;
      "$GIT_FEATURE_REL/.gatespec/revalidations/"*) ;;
      *)
        if ! grep -Fqx -- "$path" "$allowed"; then
          fail "implementation baseline: checkpoint commit contains disallowed path '$path'"
          bad=1
        fi
        ;;
    esac
  done < "$changed"
  [[ "$bad" -eq 0 ]] && pass "implementation baseline commit contains only approved artifacts, tasks, and REV-TASKS metadata"

  : > "$manifest"
  append_current_artifact_files "$manifest"
  if ! append_review_chain_files 'REV-TASKS' "$manifest"; then
    fail "implementation baseline: cannot enumerate the complete REV-TASKS handoff"
    return
  fi
  while IFS=$'\t' read -r rel current; do
    [[ -n "$rel" ]] || continue
    if ! git -C "$GIT_ROOT" show "$baseline:$rel" > "$TMP_DIR/baseline-required-blob" 2>/dev/null; then
      fail "implementation baseline: '$rel' is absent from the baseline commit"
      bad=1
    elif [[ "$rel" == "$GIT_FEATURE_REL/tasks.md" ]]; then
      baseline_tasks_hash=$(normalized_tasks_hash "$TMP_DIR/baseline-required-blob") || baseline_tasks_hash=''
      if [[ "$baseline_tasks_hash" != "$CURRENT_TASKS_HASH" ]]; then
        fail "implementation baseline: tasks.md normalized definition differs from the current sealed definition"
        bad=1
      fi
    elif [[ "$rel" == "$GIT_FEATURE_REL/.gatespec/implementation-adjustments.md" ]]; then
      task_ia_hash=$(markdown_field_value \
        "$FEATURE_DIR/.gatespec/reviews/REV-TASKS/round-$(markdown_field_value "$FEATURE_DIR/.gatespec/reviews/REV-TASKS/seal.md" 'Round')-request.md" \
        'Implementation-Adjustments-SHA256')
      if [[ "$task_ia_hash" != $(file_hash "$TMP_DIR/baseline-required-blob") ]]; then
        fail "implementation baseline: IA snapshot differs from the empty REV-TASKS baseline"
        bad=1
      fi
    elif ! cmp -s "$TMP_DIR/baseline-required-blob" "$current"; then
      fail "implementation baseline: current '$rel' differs from its baseline blob"
      bad=1
    fi
  done < "$manifest"
  [[ "$bad" -eq 0 ]] && pass "implementation baseline binds the full REV-TASKS handoff and approved artifact snapshots"
}

check_task_review_gate() {
  local enforce_git_state="${1:-no}"
  echo ""
  echo "Task Review Gate: $FEATURE_DIR/.gatespec/reviews/REV-TASKS"
  initialize_review_hashes
  check_review_chain 'REV-TASKS' 'TASKS'
  if [[ "$enforce_git_state" == 'yes' ]]; then
    check_task_review_git_state
  fi
}

checkpoint_checkbox_normalized() {
  local file="$1" id="$2"
  sed -E "s/^(- \\[)[xX](\\] T[0-9][0-9][0-9].*GateSpec review checkpoint ${id}:)/\\1 \\2/" "$file"
}

check_post_subject_delta() {
  local subject="$1" id="$2" repo_abs feature_abs feature_rel review_prefix tasks_rel acceptance_rel
  local path bad=0 list="$TMP_DIR/post-subject-paths"
  if [[ -z "$GIT_ROOT" ]]; then
    fail "$id: cannot validate post-subject delta outside a Git worktree"
    return
  fi
  repo_abs=$(cd "$GIT_ROOT" 2>/dev/null && pwd -P) || repo_abs=''
  feature_abs=$(cd "$FEATURE_DIR" 2>/dev/null && pwd -P) || feature_abs=''
  case "$feature_abs" in
    "$repo_abs"/*) feature_rel=${feature_abs#"$repo_abs"/} ;;
    *) fail "$id: feature directory is outside the Git worktree"; return ;;
  esac
  review_prefix="$feature_rel/.gatespec/reviews/"
  tasks_rel="$feature_rel/tasks.md"
  acceptance_rel="$feature_rel/.gatespec/acceptance.md"
  : > "$list"
  git -C "$GIT_ROOT" -c core.quotepath=false diff --no-renames --name-only "$subject" >> "$list" 2>/dev/null || {
    fail "$id: cannot inspect worktree delta after subject commit"
    return
  }
  git -C "$GIT_ROOT" -c core.quotepath=false ls-files --others --exclude-standard >> "$list" 2>/dev/null || true
  LC_ALL=C sort -u -o "$list" "$list"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    case "$path" in
      "$review_prefix"*) ;;
      "$tasks_rel") ;;
      "$acceptance_rel")
        if [[ "$MODE" != acceptance ]]; then
          fail "$id: acceptance metadata exists before the acceptance phase"
          bad=1
        fi
        ;;
      *)
        fail "$id: post-subject path '$path' is neither review metadata nor tasks.md"
        bad=1
        ;;
    esac
  done < "$list"

  if ! git -C "$GIT_ROOT" show "$subject:$tasks_rel" > "$TMP_DIR/subject-tasks" 2>/dev/null; then
    fail "$id: subject commit does not contain tasks.md"
    bad=1
  else
    if [[ $(grep -Ec "^- \\[ \\] T[0-9][0-9][0-9].*GateSpec review checkpoint ${id}:" "$TMP_DIR/subject-tasks" || true) -ne 1 ]]; then
      fail "$id: checkpoint checkbox must be open in the subject commit"
      bad=1
    fi
    if [[ $(grep -Ec "^- \\[[xX]\\] T[0-9][0-9][0-9].*GateSpec review checkpoint ${id}:" "$TASKS" || true) -ne 1 ]]; then
      fail "$id: current checkpoint checkbox must be complete after its PASS seal"
      bad=1
    fi
    checkpoint_checkbox_normalized "$TMP_DIR/subject-tasks" "$id" > "$TMP_DIR/subject-tasks-normalized"
    checkpoint_checkbox_normalized "$TASKS" "$id" > "$TMP_DIR/current-tasks-normalized"
    if ! cmp -s "$TMP_DIR/subject-tasks-normalized" "$TMP_DIR/current-tasks-normalized"; then
      fail "$id: tasks.md changed after subject beyond the $id checkpoint checkbox"
      bad=1
    fi
  fi
  [[ "$bad" -eq 0 ]] && pass "$id: post-subject delta contains only review metadata and its checkpoint checkbox"
}

check_committed_implementation_state() {
  local subject="$1" id="$2" ref status checkpoint found=0 bad=0
  local manifest="$TMP_DIR/committed-review-files"
  if [[ -z "$GIT_ROOT" ]] || ! resolve_git_feature_paths; then
    fail "$id: committed review verification requires the feature Git worktree"
    return
  fi
  ref=$(git -C "$GIT_ROOT" symbolic-ref -q HEAD 2>/dev/null || true)
  case "$ref" in
    refs/heads/*) ;;
    *) fail "$id: committed implementation review requires an attached local feature branch"; bad=1 ;;
  esac
  status=$(git -C "$GIT_ROOT" -c core.quotepath=false status --porcelain=v1 --untracked-files=all 2>/dev/null || true)
  if [[ -n "$status" ]]; then
    fail "$id: implementation-review requires a clean worktree after the metadata/progress commit"
    bad=1
  fi
  if ! git -C "$GIT_ROOT" merge-base --is-ancestor "$subject" HEAD 2>/dev/null ||
     [[ "$(git -C "$GIT_ROOT" rev-parse HEAD 2>/dev/null || true)" == "$subject" ]]; then
    fail "$id: HEAD must strictly descend from the reviewed subject commit"
    bad=1
  fi

  : > "$manifest"
  append_current_artifact_files "$manifest"
  append_review_chain_files 'REV-TASKS' "$manifest" || bad=1
  while IFS= read -r checkpoint; do
    [[ -n "$checkpoint" ]] || continue
    append_review_chain_files "$checkpoint" "$manifest" || bad=1
    if [[ "$checkpoint" == "$id" ]]; then
      found=1
      break
    fi
  done < "$TMP_DIR/required-checkpoints"
  if [[ "$found" -ne 1 || "$bad" -ne 0 ]]; then
    fail "$id: cannot enumerate every sealed review through the current scope"
    bad=1
  elif ! check_head_tracked_manifest "$manifest" "$id committed review"; then
    bad=1
  fi
  [[ "$bad" -eq 0 ]] && pass "$id: clean HEAD tracks the accepted receipt, seal, and checkpoint progress"
}

check_implementation_review_gate() {
  local id scope found=0 previous_subject='' baseline='' selected_subject='' bad=0 unchecked
  echo ""
  echo "Implementation Review Gate: $REVIEW_ID"
  initialize_review_hashes

  while IFS= read -r id; do
    [[ -n "$id" ]] || continue
    scope=$(review_scope_for_id "$id") || scope=''
    check_review_chain "$id" "$scope"
    if [[ -z "$baseline" ]]; then
      baseline=$CHAIN_BASELINE
      [[ -n "$baseline" ]] && check_baseline_task_seal "$baseline"
      if [[ -n "$CHAIN_BASE" && "$CHAIN_BASE" != "$CHAIN_BASELINE" ]]; then
        fail "$id: first implementation review Base-Commit must equal Implementation-Baseline"
        bad=1
      fi
    else
      if [[ "$CHAIN_BASELINE" != "$baseline" ]]; then
        fail "$id: all implementation seals must share one Implementation-Baseline"
        bad=1
      fi
      if [[ "$id" == 'REV-FINAL' && "${ACTIVE_REVIEW_PROTOCOL:-1}" == 2 && "$CHAIN_BASE" != "$CURRENT_ORIGINAL_BASELINE" ]]; then
        fail "$id: Protocol v2 Base-Commit must equal Original-Implementation-Baseline"
        bad=1
      elif [[ "$id" == 'REV-FINAL' && "${ACTIVE_REVIEW_PROTOCOL:-1}" == 1 && "$CHAIN_BASE" != "$baseline" ]]; then
        fail "$id: Protocol v1 Base-Commit must equal Implementation-Baseline for cumulative final review"
        bad=1
      elif [[ "$id" == 'REV-FINAL' && -n "$previous_subject" ]] &&
           ! git -C "$GIT_ROOT" merge-base --is-ancestor "$previous_subject" "$CHAIN_SUBJECT" 2>/dev/null; then
        fail "$id: Subject-Commit must descend from the preceding checkpoint Subject-Commit"
        bad=1
      elif [[ "$id" != 'REV-FINAL' && -n "$previous_subject" && "$CHAIN_BASE" != "$previous_subject" ]]; then
        fail "$id: Base-Commit must equal the preceding checkpoint Subject-Commit"
        bad=1
      fi
    fi
    previous_subject=$CHAIN_SUBJECT
    if [[ "$id" == "$REVIEW_ID" ]]; then
      selected_subject=$CHAIN_SUBJECT
      found=1
      break
    fi
  done < "$TMP_DIR/required-checkpoints"

  if [[ "$found" -ne 1 ]]; then
    fail "plan.md: requested implementation checkpoint $REVIEW_ID is not declared"
    return
  fi
  if [[ -n "$selected_subject" ]]; then
    check_post_subject_delta "$selected_subject" "$REVIEW_ID"
    if [[ "$MODE" == 'implementation-review' || "$MODE" == 'acceptance-candidate' || "$MODE" == 'acceptance' ]]; then
      check_committed_implementation_state "$selected_subject" "$REVIEW_ID"
    fi
  fi
  if [[ "$REVIEW_ID" == 'REV-FINAL' ]]; then
    if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 2 && -f "$SOURCE_ENTRY" && -n "$selected_subject" ]]; then
      check_source_final_paths "$selected_subject"
    fi
    unchecked=$(grep -cE '^- \[ \] T[0-9][0-9][0-9]([[:space:]]|$)' "$TASKS" || true)
    if [[ "$unchecked" -ne 0 ]]; then
      fail "tasks.md: REV-FINAL requires every valid task checkbox to be complete"
      bad=1
    else
      pass "tasks.md: every valid task is complete at REV-FINAL"
    fi
  fi
  [[ "$bad" -eq 0 ]] && pass "$REVIEW_ID: implementation seal chain is continuous through the requested checkpoint"
}

check_acceptance_gate() {
  local context='acceptance.md' protocol status accepted_at spec_hash plan_hash attachments_hash tasks_hash
  local epoch source_hash ia_hash original subject seal_hash review_commit final_delta actual_final
  local final_dir="$FEATURE_DIR/.gatespec/reviews/REV-FINAL" seal="$FEATURE_DIR/.gatespec/reviews/REV-FINAL/seal.md"
  local round request head parent latest seal_rel acceptance_rel changed parent_fields dirty invalid bad=0
  echo ""
  echo "Implementation Acceptance Gate: $ACCEPTANCE"
  if [[ ! -f "$ACCEPTANCE" ]]; then fail "$context: explicit final user acceptance is missing"; return; fi
  invalid=$(awk '
    /^[[:space:]]*$/ {next}
    NR == 1 && $0 == "# GateSpec Implementation Acceptance" {next}
    /^- \*\*(Protocol-Version|Status|Accepted-At|Spec-Content-SHA256|Plan-Content-SHA256|Design-Attachments-SHA256|Tasks-Definition-SHA256|Execution-Epoch|Source-Design-Content-SHA256|Implementation-Adjustments-SHA256|Original-Implementation-Baseline|Final-Subject-Commit|REV-FINAL-Seal-SHA256|Final-Review-Commit|Final-Delta-SHA256|Acceptance-SHA256)\*\*: `[^`]+`$/ {next}
    {print NR ":" $0}
  ' "$ACCEPTANCE")
  [[ -z "$invalid" ]] || { fail "$context: only the canonical acceptance fields are allowed"; bad=1; }
  check_ordered_fields "$ACCEPTANCE" "$context" \
    'Protocol-Version' 'Status' 'Accepted-At' 'Spec-Content-SHA256' 'Plan-Content-SHA256' \
    'Design-Attachments-SHA256' 'Tasks-Definition-SHA256' 'Execution-Epoch' \
    'Source-Design-Content-SHA256' 'Implementation-Adjustments-SHA256' \
    'Original-Implementation-Baseline' 'Final-Subject-Commit' 'REV-FINAL-Seal-SHA256' \
    'Final-Review-Commit' 'Final-Delta-SHA256' 'Acceptance-SHA256'
  protocol=$(markdown_field_value "$ACCEPTANCE" 'Protocol-Version')
  status=$(markdown_field_value "$ACCEPTANCE" 'Status')
  accepted_at=$(markdown_field_value "$ACCEPTANCE" 'Accepted-At')
  spec_hash=$(markdown_field_value "$ACCEPTANCE" 'Spec-Content-SHA256')
  plan_hash=$(markdown_field_value "$ACCEPTANCE" 'Plan-Content-SHA256')
  attachments_hash=$(markdown_field_value "$ACCEPTANCE" 'Design-Attachments-SHA256')
  tasks_hash=$(markdown_field_value "$ACCEPTANCE" 'Tasks-Definition-SHA256')
  epoch=$(markdown_field_value "$ACCEPTANCE" 'Execution-Epoch')
  source_hash=$(markdown_field_value "$ACCEPTANCE" 'Source-Design-Content-SHA256')
  ia_hash=$(markdown_field_value "$ACCEPTANCE" 'Implementation-Adjustments-SHA256')
  original=$(markdown_field_value "$ACCEPTANCE" 'Original-Implementation-Baseline')
  subject=$(markdown_field_value "$ACCEPTANCE" 'Final-Subject-Commit')
  seal_hash=$(markdown_field_value "$ACCEPTANCE" 'REV-FINAL-Seal-SHA256')
  review_commit=$(markdown_field_value "$ACCEPTANCE" 'Final-Review-Commit')
  final_delta=$(markdown_field_value "$ACCEPTANCE" 'Final-Delta-SHA256')
  [[ "$protocol" == "${ACTIVE_REVIEW_PROTOCOL:-1}" ]] || { fail "$context: Protocol-Version must match the final review"; bad=1; }
  [[ "$status" == Accepted ]] || { fail "$context: Status must be Accepted"; bad=1; }
  printf '%s\n' "$accepted_at" | grep -Eq '^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$' || { fail "$context: Accepted-At must be UTC RFC3339"; bad=1; }
  [[ "$spec_hash" == "$CURRENT_SPEC_HASH" ]] || { fail "$context: Spec hash is stale"; bad=1; }
  [[ "$plan_hash" == "$CURRENT_PLAN_HASH" ]] || { fail "$context: Plan hash is stale"; bad=1; }
  [[ "$attachments_hash" == "$CURRENT_ATTACHMENTS_HASH" ]] || { fail "$context: Design Attachments hash is stale"; bad=1; }
  [[ "$tasks_hash" == "$CURRENT_TASKS_HASH" ]] || { fail "$context: Tasks definition hash is stale"; bad=1; }
  round=$(markdown_field_value "$seal" 'Round')
  request="$final_dir/round-${round}-request.md"
  [[ -f "$request" ]] || { fail "$context: sealed REV-FINAL request is missing"; return; }
  [[ "$subject" == $(markdown_field_value "$request" 'Subject-Commit') ]] || { fail "$context: Final Subject does not match REV-FINAL"; bad=1; }
  [[ "$seal_hash" == $(markdown_field_value "$seal" 'Seal-SHA256') ]] || { fail "$context: REV-FINAL seal hash mismatch"; bad=1; }
  if [[ "$protocol" == 2 ]]; then
    [[ "$epoch" == "$CURRENT_EXECUTION_EPOCH" ]] || { fail "$context: Execution Epoch is stale"; bad=1; }
    [[ "$original" == "$CURRENT_ORIGINAL_BASELINE" ]] || { fail "$context: Original Baseline is stale"; bad=1; }
    [[ "$source_hash" == $(markdown_field_value "$request" 'Source-Design-Content-SHA256') ]] || { fail "$context: Source hash does not match REV-FINAL"; bad=1; }
    [[ "$ia_hash" == $(markdown_field_value "$request" 'Implementation-Adjustments-SHA256') ]] || { fail "$context: IA hash does not match REV-FINAL"; bad=1; }
  else
    [[ "$epoch" == not-applicable && "$source_hash" == not-applicable && "$ia_hash" == not-applicable ]] || { fail "$context: Protocol v1 Source/IA/epoch fields must be not-applicable"; bad=1; }
    [[ "$original" == $(markdown_field_value "$request" 'Implementation-Baseline') ]] || { fail "$context: legacy Original Baseline must equal Implementation Baseline"; bad=1; }
  fi
  if ! is_git_oid "$subject" || ! is_git_oid "$original" || ! is_git_oid "$review_commit"; then
    fail "$context: baseline, subject, and final review commit must be Git OIDs"; bad=1
  else
    actual_final=$(git_final_delta_hash "$GIT_ROOT" "$original" "$subject") || actual_final=''
    [[ "$final_delta" == "$actual_final" ]] || { fail "$context: Final-Delta-SHA256 is stale"; bad=1; }
  fi
  if ! resolve_git_feature_paths; then fail "$context: feature is outside its Git worktree"; return; fi
  seal_rel="$GIT_FEATURE_REL/.gatespec/reviews/REV-FINAL/seal.md"
  acceptance_rel="$GIT_FEATURE_REL/.gatespec/acceptance.md"
  latest=$(git -C "$GIT_ROOT" log -1 --format=%H -- "$seal_rel" 2>/dev/null || true)
  [[ "$review_commit" == "$latest" ]] || { fail "$context: Final-Review-Commit is not the latest commit that touched the final seal"; bad=1; }
  head=$(git -C "$GIT_ROOT" rev-parse HEAD 2>/dev/null || true)
  parent=$(git -C "$GIT_ROOT" rev-parse HEAD^ 2>/dev/null || true)
  [[ "$parent" == "$review_commit" ]] || { fail "$context: acceptance commit must directly follow Final-Review-Commit"; bad=1; }
  parent_fields=$(git -C "$GIT_ROOT" rev-list --parents -n 1 "$head" 2>/dev/null | awk '{print NF+0}')
  [[ "$parent_fields" -eq 2 ]] || { fail "$context: acceptance metadata commit must not be a root or merge commit"; bad=1; }
  changed=$(git -C "$GIT_ROOT" -c core.quotepath=false diff-tree --no-commit-id --name-only -r "$head" 2>/dev/null || true)
  if [[ $(printf '%s\n' "$changed" | awk 'NF {n++} END {print n+0}') -ne 1 || "$changed" != "$acceptance_rel" ]]; then
    fail "$context: acceptance commit must be metadata-only and change only acceptance.md"; bad=1
  fi
  if ! git -C "$GIT_ROOT" show "HEAD:$acceptance_rel" > "$TMP_DIR/head-acceptance" 2>/dev/null || ! cmp -s "$TMP_DIR/head-acceptance" "$ACCEPTANCE"; then
    fail "$context: current acceptance.md must exactly match tracked HEAD"; bad=1
  fi
  dirty=$(git -C "$GIT_ROOT" -c core.quotepath=false status --porcelain=v1 --untracked-files=all 2>/dev/null || true)
  [[ -z "$dirty" ]] || { fail "$context: acceptance requires a clean worktree with no untracked paths"; bad=1; }
  check_self_hash "$ACCEPTANCE" 'Acceptance-SHA256' "$context"
  [[ "$bad" -eq 0 ]] && pass "$context: explicit user acceptance binds all artifacts, REV-FINAL, commit chain, and raw tree delta"
}

check_design_gate() {
  local section
  echo ""
  echo "Design Gate: $PLAN"
  if [[ ! -f "$PLAN" ]]; then
    fail "plan.md not found in $FEATURE_DIR"
    return
  fi
  for section in 'Technical Context' 'Constitution Check' 'Decision Log' 'Design Detailing' 'Project Structure' 'Implementation Review Contract'; do
    check_h2_once "$PLAN" "$section"
  done
  check_requirements_basis
  check_design_evidence_schema
  check_decisions
  check_design_detailing
  check_implementation_review_contract
  check_template_remnants "$PLAN"
  check_gate_approval "$PLAN" 'Approved-Design'
  check_vague_words "$PLAN"
}

check_spec_gate
if [[ "$MODE" != 'spec' && "$FAILURES" -eq 0 ]]; then
  check_design_gate
fi
if [[ "$FAILURES" -eq 0 ]]; then
  case "$MODE" in
    source-candidate)
      check_source_structure candidate
      [[ "$FAILURES" -eq 0 ]] && check_execution_state source-candidate
      ;;
    source-review)
      check_source_structure reviewed
      [[ "$FAILURES" -eq 0 ]] && check_execution_state source-review
      [[ "$FAILURES" -eq 0 ]] && check_source_review_chain
      ;;
    source)
      check_source_structure approved
      [[ "$FAILURES" -eq 0 ]] && check_execution_state source-approved
      [[ "$FAILURES" -eq 0 ]] && check_source_review_chain
      ;;
    tasks-structure|task-review|implementation-candidate|implementation-review|acceptance-candidate|acceptance)
      if [[ -f "$SOURCE_ENTRY" ]]; then
        check_source_structure approved
        [[ "$FAILURES" -eq 0 ]] && check_source_review_chain
      fi
      ;;
  esac
fi
if [[ ( "$MODE" == 'tasks-structure' || "$MODE" == 'task-review' ||
        "$MODE" == 'implementation-candidate' || "$MODE" == 'implementation-review' ||
        "$MODE" == 'acceptance-candidate' || "$MODE" == 'acceptance' ) && "$FAILURES" -eq 0 ]]; then
  check_tasks_structure
fi
if [[ "$MODE" == 'task-review' && "$FAILURES" -eq 0 ]]; then
  if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 2 ]]; then
    check_execution_state downstream
    [[ "$FAILURES" -eq 0 ]] && check_implementation_adjustments yes
    if [[ -d "$FEATURE_DIR/checklists" ]] && grep -R -nE '^- \[ \]' "$FEATURE_DIR/checklists" >/dev/null 2>&1; then
      fail "checklists: every checklist item must be complete before speckit.implement"
    else
      pass "checklists: no incomplete checklist item remains"
    fi
  fi
fi
if [[ "$MODE" == 'task-review' && "$FAILURES" -eq 0 ]]; then
  check_task_review_gate yes
fi
if [[ ( "$MODE" == 'implementation-candidate' || "$MODE" == 'implementation-review' ||
        "$MODE" == 'acceptance-candidate' || "$MODE" == 'acceptance' ) && "$FAILURES" -eq 0 ]]; then
  if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 2 ]]; then
    check_execution_state downstream
    [[ "$FAILURES" -eq 0 ]] && check_implementation_adjustments no
  fi
fi
if [[ ( "$MODE" == 'implementation-candidate' || "$MODE" == 'implementation-review' ||
        "$MODE" == 'acceptance-candidate' || "$MODE" == 'acceptance' ) && "$FAILURES" -eq 0 ]]; then
  check_task_review_gate no
  if [[ "$FAILURES" -eq 0 ]]; then
    case "$MODE" in acceptance-candidate|acceptance) REVIEW_ID='REV-FINAL' ;; esac
    check_implementation_review_gate
  fi
fi
if [[ "$MODE" == 'acceptance' && "$FAILURES" -eq 0 ]]; then
  check_acceptance_gate
fi

echo ""
if [[ "$FAILURES" -gt 0 ]]; then
  echo "GATE FAILED: $FAILURES check(s) failed, $WARNINGS warning(s)."
  echo "Resolve the listed artifact issues and obtain explicit re-approval before proceeding."
  exit 1
fi
echo "GATE PASSED ($WARNINGS warning(s))."
exit 0
