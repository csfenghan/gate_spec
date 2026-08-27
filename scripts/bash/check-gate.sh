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
USAGE='Usage: check-gate.sh <spec|design|source-candidate|source-review|source|tasks-structure|task-review|retask-eligible|implementation-candidate|implementation-review|acceptance-candidate|acceptance> [feature-dir] [REV-ID]'

if [[ "$#" -gt 3 ]]; then
  echo "$USAGE" >&2
  exit 2
fi

case "$MODE" in
  spec|design|source-candidate|source-review|source|tasks-structure|retask-eligible|acceptance-candidate|acceptance)
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
LEGACY_SPEC_ESTIMATE=0
LEGACY_PLAN_ESTIMATE=0
DESIGN_ADDITIONS_LOWER=''
DESIGN_ADDITIONS_UPPER=''
DESIGN_CHURN_LOWER=''
DESIGN_CHURN_UPPER=''
DESIGN_FILES_LOWER=''
DESIGN_FILES_UPPER=''
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
    '[lower..upper]' '[capabilities, analogous changes' \
    '[repository-relative production path families' \
    '[path pattern — exclusion reason' '[low, medium, or high' \
    '[inspected modules, callers' '[within|expanded|reduced]' \
    '[why Design stayed within' \
    '[participant, current state' '[existing behavior or burden' \
    '[observable capability]' '[adjacent capability]' \
    '[which part of the Primary outcome' '[why it is outside this delivery' \
    '[non-deferred CAP/FR/D/constraint' \
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

delivery_field_values() {
  local file="$1" label="$2"
  awk -v prefix="- **${label}**:" '
    index($0, prefix) == 1 {
      value=substr($0, length(prefix) + 1)
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      print value
    }
  ' "$file"
}

delivery_field_line_numbers() {
  local file="$1" label="$2"
  awk -v prefix="- **${label}**:" 'index($0, prefix) == 1 {print NR}' "$file"
}

decimal_le() {
  local left="$1" right="$2"
  left=$(printf '%s' "$left" | sed 's/^0*//')
  right=$(printf '%s' "$right" | sed 's/^0*//')
  [[ -n "$left" ]] || left=0
  [[ -n "$right" ]] || right=0
  if [[ ${#left} -lt ${#right} ]]; then
    return 0
  fi
  if [[ ${#left} -gt ${#right} ]]; then
    return 1
  fi
  [[ "$left" == "$right" || "$left" < "$right" ]]
}

parse_delivery_range() {
  printf '%s\n' "$1" | sed -n 's/^`\([0-9][0-9]*\)\.\.\([0-9][0-9]*\)`$/\1 \2/p'
}

check_generated_exclusions() {
  local value="$1" context="$2"
  if printf '%s\n' "$value" | awk '
    BEGIN {bad=0}
    {
      count=split($0, entries, ";")
      for (i=1; i<=count; i++) {
        item=entries[i]
        sub(/^[[:space:]]*/, "", item)
        sub(/[[:space:]]*$/, "", item)
        lower=tolower(item)
        generated=index(lower, "generated:")
        looks_generated=(lower ~ /(^|\/)generated(\/|[.])|[.]pb[.](cc|h|go|java|py)|_generated[.]/)
        if (generated && generated != 1) bad=1
        if (generated == 1 && item !~ /^generated:[[:space:]]*[^[:space:]].*[[:space:]]+<-[[:space:]]+[^[:space:]].*[[:space:]]+via[[:space:]]+[^[:space:]].*$/) bad=1
        if (looks_generated && generated != 1) bad=1
      }
    }
    END {exit bad}
  '; then
    pass "$context: generated exclusions bind output, source, and generator"
    return 0
  else
    fail "$context: generated exclusions must use 'generated: output/path <- source/path via generator'"
    return 1
  fi
}

check_delivery_estimate() {
  local file="$1" kind="$2" context section
  local exact_schema all_schema section_count field value lines count previous=0 line bad=0
  local additions_lower additions_upper churn_lower churn_upper files_lower files_upper parsed
  local fields relation
  section="$TMP_DIR/delivery-estimate-${kind}"
  context="$(basename "$file") Delivery Estimate"
  exact_schema=$(grep -cFx '**Delivery Estimate Schema**: 1' "$file" || true)
  all_schema=$(grep -cF '**Delivery Estimate Schema**:' "$file" || true)
  section_count=$(h2_count "$file" 'Delivery Estimate')

  if [[ "$all_schema" -eq 0 && "$section_count" -eq 0 ]]; then
    if [[ "$kind" == requirements ]] &&
       grep -Eq '^\*\*Status\*\*: Approved-Requirements \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$' "$file"; then
      LEGACY_SPEC_ESTIMATE=1
      warn "spec.md: legacy Approved Requirements has no Delivery Estimate; the next Design must add one"
    elif [[ "$kind" == design ]] &&
         grep -Eq '^\*\*Status\*\*: Approved-Design \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$' "$file"; then
      LEGACY_PLAN_ESTIMATE=1
      warn "plan.md: legacy Approved Design has no Delivery Estimate"
    else
      fail "$context: Delivery Estimate Schema 1 and one Delivery Estimate section are required"
    fi
    return
  fi

  if [[ "$exact_schema" -ne 1 || "$all_schema" -ne 1 ]]; then
    fail "$context: expected exactly one '**Delivery Estimate Schema**: 1' field; missing, duplicate, and unknown schemas are invalid"
    bad=1
  else
    pass "$context: Delivery Estimate Schema 1 is declared exactly once"
  fi
  if [[ "$section_count" -ne 1 ]]; then
    fail "$context: expected exactly one '## Delivery Estimate' section"
    return
  fi
  section_body "$file" 'Delivery Estimate' > "$section"

  fields=$'Production additions\nProduction churn\nProduction files\nEstimate basis\nProduction path basis\nExcluded paths\nConfidence'
  if [[ "$kind" == design ]]; then
    fields="${fields}"$'\nRequirements estimate relation\nRequirements estimate rationale'
  fi
  while IFS= read -r field; do
    [[ -n "$field" ]] || continue
    lines=$(delivery_field_line_numbers "$section" "$field")
    count=$(printf '%s\n' "$lines" | awk 'NF {n++} END {print n+0}')
    value=$(delivery_field_values "$section" "$field")
    if [[ "$count" -ne 1 || $(printf '%s\n' "$value" | awk 'NF {n++} END {print n+0}') -ne 1 ]]; then
      fail "$context: expected exactly one nonempty '$field' field"
      bad=1
      continue
    fi
    line=$lines
    if [[ "$line" -le "$previous" ]]; then
      fail "$context: field '$field' is out of order"
      bad=1
    fi
    previous=$line
    if [[ "$value" == \[* ]]; then
      fail "$context: field '$field' still contains a placeholder"
      bad=1
    fi
  done <<< "$fields"

  while IFS= read -r field; do
    [[ -n "$field" ]] || continue
    if ! printf '%s\n' "$fields" | grep -Fqx -- "$field"; then
      fail "$context: unknown structured field '$field'"
      bad=1
    fi
  done < <(sed -n 's/^- \*\*\([^*][^*]*\)\*\*:.*/\1/p' "$section")

  parsed=$(parse_delivery_range "$(delivery_field_values "$section" 'Production additions')")
  if [[ -z "$parsed" ]]; then
    fail "$context: Production additions must be a non-negative 'lower..upper' range in backticks"
    bad=1
  else
    read -r additions_lower additions_upper <<< "$parsed"
    if ! decimal_le "$additions_lower" "$additions_upper"; then
      fail "$context: Production additions lower bound exceeds its upper bound"
      bad=1
    fi
  fi
  parsed=$(parse_delivery_range "$(delivery_field_values "$section" 'Production churn')")
  if [[ -z "$parsed" ]]; then
    fail "$context: Production churn must be a non-negative 'lower..upper' range in backticks"
    bad=1
  else
    read -r churn_lower churn_upper <<< "$parsed"
    if ! decimal_le "$churn_lower" "$churn_upper"; then
      fail "$context: Production churn lower bound exceeds its upper bound"
      bad=1
    fi
  fi
  parsed=$(parse_delivery_range "$(delivery_field_values "$section" 'Production files')")
  if [[ -z "$parsed" ]]; then
    fail "$context: Production files must be a non-negative 'lower..upper' range in backticks"
    bad=1
  else
    read -r files_lower files_upper <<< "$parsed"
    if ! decimal_le "$files_lower" "$files_upper"; then
      fail "$context: Production files lower bound exceeds its upper bound"
      bad=1
    fi
  fi
  if [[ -n "${additions_lower:-}" && -n "${churn_lower:-}" ]] &&
     { ! decimal_le "$additions_lower" "$churn_lower" || ! decimal_le "$additions_upper" "$churn_upper"; }; then
    fail "$context: Production additions cannot exceed Production churn at either interval bound"
    bad=1
  fi

  value=$(delivery_field_values "$section" 'Excluded paths')
  if [[ -n "$value" ]] && ! check_generated_exclusions "$value" "$context"; then
    bad=1
  fi

  if [[ "$kind" == design ]]; then
    relation=$(delivery_field_values "$section" 'Requirements estimate relation')
    case "$relation" in
      '`within`'|'`expanded`'|'`reduced`')
        if [[ "$LEGACY_SPEC_ESTIMATE" -eq 1 ]]; then
          fail "$context: legacy Requirements without an estimate require a not-applicable relation in backticks"
          bad=1
        fi
        ;;
      '`not-applicable`')
        if [[ "$LEGACY_SPEC_ESTIMATE" -ne 1 ]]; then
          fail "$context: Requirements estimate relation may be 'not-applicable' only for legacy Requirements without an estimate"
          bad=1
        fi
        ;;
      *)
        fail "$context: Requirements estimate relation must be within, expanded, or reduced in backticks"
        bad=1
        ;;
    esac
    DESIGN_ADDITIONS_LOWER=${additions_lower:-}
    DESIGN_ADDITIONS_UPPER=${additions_upper:-}
    DESIGN_CHURN_LOWER=${churn_lower:-}
    DESIGN_CHURN_UPPER=${churn_upper:-}
    DESIGN_FILES_LOWER=${files_lower:-}
    DESIGN_FILES_UPPER=${files_upper:-}
  fi
  [[ "$bad" -eq 0 ]] && pass "$context: ranges, bases, exclusions, confidence, and comparison fields are valid"
}

scope_definitions() {
  local kind="$1" outer section heading
  case "$kind" in
    FR)
      outer='Requirements'
      heading='Functional Requirements'
      ;;
    SC)
      outer='Success Criteria'
      heading='Measurable Outcomes'
      ;;
    *) return 1 ;;
  esac
  section="$TMP_DIR/scope-${kind}-outer"
  section_body "$SPEC" "$outer" > "$section"
  awk -v heading="### ${heading}" '
    index($0, heading) == 1 {inside=1; next}
    inside && (/^### / || /^## /) {exit}
    inside {print}
  ' "$section" | grep -oE "^-[[:space:]]+\\*\\*${kind}-[0-9]+\\*\\*:" | grep -oE "${kind}-[0-9]+" || true
}

check_scope_contract() {
  local exact_schema all_schema section_count section fields field lines count value
  local previous=0 line bad=0 header divider table_lines scope_sep cap admission refs rationale id
  local cap_count=0 core_count=0 fr_count sc_count ref inner duplicate definitions kind outside
  section="$TMP_DIR/scope-contract"
  exact_schema=$(grep -cFx '**Scope Contract Schema**: 1' "$SPEC" || true)
  all_schema=$(grep -cF '**Scope Contract Schema**:' "$SPEC" || true)
  section_count=$(h2_count "$SPEC" 'Scope Contract')

  if [[ "$all_schema" -eq 0 && "$section_count" -eq 0 ]]; then
    if grep -Eq '^\*\*Status\*\*: Approved-Requirements \([0-9]{4}-[0-9]{2}-[0-9]{2}\)$' "$SPEC"; then
      if legacy_design_has_implementation_progress; then
        warn "spec.md: legacy Approved Requirements has no Scope Contract; implementation progress already exists, so the artifact remains read-only"
      else
        fail "spec.md: legacy Approved Requirements has no Scope Contract and no implementation progress; run gatespec.specify --revise before Design"
      fi
    else
      fail "spec.md Scope Contract: Scope Contract Schema 1 and one Scope Contract section are required"
    fi
    return
  fi

  if [[ "$exact_schema" -ne 1 || "$all_schema" -ne 1 ]]; then
    fail "spec.md Scope Contract: expected exactly one '**Scope Contract Schema**: 1' field; missing, duplicate, and unknown schemas are invalid"
    bad=1
  else
    pass "spec.md Scope Contract: Scope Contract Schema 1 is declared exactly once"
  fi
  if [[ "$section_count" -ne 1 ]]; then
    fail "spec.md Scope Contract: expected exactly one '## Scope Contract' section"
    return
  fi
  section_body "$SPEC" 'Scope Contract' > "$section"

  fields=$'Primary outcome\nCore completion refs\nRetained baseline'
  while IFS= read -r field; do
    lines=$(delivery_field_line_numbers "$section" "$field")
    count=$(printf '%s\n' "$lines" | awk 'NF {n++} END {print n+0}')
    value=$(delivery_field_values "$section" "$field")
    if [[ "$count" -ne 1 || $(printf '%s\n' "$value" | awk 'NF {n++} END {print n+0}') -ne 1 ]]; then
      fail "spec.md Scope Contract: expected exactly one nonempty '$field' field"
      bad=1
      continue
    fi
    line=$lines
    if [[ "$line" -le "$previous" ]]; then
      fail "spec.md Scope Contract: field '$field' is out of order"
      bad=1
    fi
    previous=$line
    if [[ "$value" == \[* ]]; then
      fail "spec.md Scope Contract: field '$field' still contains a placeholder"
      bad=1
    fi
  done <<< "$fields"
  while IFS= read -r field; do
    [[ -n "$field" ]] || continue
    if ! printf '%s\n' "$fields" | grep -Fqx -- "$field"; then
      fail "spec.md Scope Contract: unknown structured field '$field'"
      bad=1
    fi
  done < <(sed -n 's/^- \*\*\([^*][^*]*\)\*\*:.*/\1/p' "$section")

  value=$(delivery_field_values "$section" 'Retained baseline')
  if printf '%s\n' "$value" | grep -Eq '^(None|无)([[:space:]]|$)' &&
     ! printf '%s\n' "$value" | grep -Eq '^(None|无)[[:space:]]+—[[:space:]]*[^[:space:]].*$'; then
    fail "spec.md Scope Contract: Retained baseline empty state requires 'None — <reason>'"
    bad=1
  fi

  value=$(delivery_field_values "$section" 'Core completion refs')
  : > "$TMP_DIR/scope-core-completion"
  if ! printf '%s\n' "$value" | grep -Eq '^`SC-[0-9]{3}(, SC-[0-9]{3})*`$'; then
    fail "spec.md Scope Contract: Core completion refs must be canonical SC-### IDs in backticks joined by comma-space"
    bad=1
  else
    inner=${value#\`}
    inner=${inner%\`}
    while IFS= read -r ref; do
      ref=${ref# }
      if grep -Fxq "$ref" "$TMP_DIR/scope-core-completion"; then
        fail "spec.md Scope Contract: Core completion ref $ref is duplicated"
        bad=1
      else
        printf '%s\n' "$ref" >> "$TMP_DIR/scope-core-completion"
      fi
    done < <(printf '%s\n' "$inner" | tr ',' '\n')
  fi

  header=$(grep -cE '^\|[[:space:]]*Capability[[:space:]]*\|[[:space:]]*Admission[[:space:]]*\|[[:space:]]*Spec refs[[:space:]]*\|[[:space:]]*Boundary rationale[[:space:]]*\|[[:space:]]*$' "$section" || true)
  divider=$(grep -cE '^\|[[:space:]]*-+[[:space:]]*\|[[:space:]]*-+[[:space:]]*\|[[:space:]]*-+[[:space:]]*\|[[:space:]]*-+[[:space:]]*\|[[:space:]]*$' "$section" || true)
  table_lines=$(grep -c '^|' "$section" || true)
  if [[ "$header" -ne 1 || "$divider" -ne 1 ]]; then
    fail "spec.md Scope Contract: capability rows require the exact four-column table header"
    bad=1
  fi

  scope_sep=$(printf '\034')
  awk -F '|' -v sep="$scope_sep" '
    function trim(value) {
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      return value
    }
    /^\|/ {
      if ($0 ~ /^\|[[:space:]]*Capability[[:space:]]*\|/ ||
          $0 ~ /^\|[[:space:]]*-+[[:space:]]*\|/) next
      if (NF != 6) {print "__MALFORMED__" sep NR sep "" sep ""; next}
      print trim($2) sep trim($3) sep trim($4) sep trim($5)
    }
  ' "$section" > "$TMP_DIR/scope-rows"
  : > "$TMP_DIR/scope-cap-ids"
  : > "$TMP_DIR/scope-nondeferred-refs"
  : > "$TMP_DIR/scope-core-cap-refs"
  while IFS="$scope_sep" read -r cap admission refs rationale; do
    cap_count=$((cap_count + 1))
    if [[ "$cap" == '__MALFORMED__' ]]; then
      fail "spec.md Scope Contract: malformed capability table row"
      bad=1
      continue
    fi
    if ! printf '%s\n' "$cap" | grep -Eq '^CAP-[0-9]{3} — [^[:space:]].*$'; then
      fail "spec.md Scope Contract: Capability must use 'CAP-### — <nonempty capability>'"
      bad=1
      id=''
    else
      id=${cap%% *}
      if grep -Fxq "$id" "$TMP_DIR/scope-cap-ids"; then
        fail "spec.md Scope Contract: capability ID $id is duplicated"
        bad=1
      else
        printf '%s\n' "$id" >> "$TMP_DIR/scope-cap-ids"
      fi
    fi
    case "$admission" in
      '`core`') admission='core'; core_count=$((core_count + 1)) ;;
      '`committed`') admission='committed' ;;
      '`constraint`') admission='constraint' ;;
      '`deferred`') admission='deferred' ;;
      *) fail "spec.md Scope Contract: Admission must be core, committed, constraint, or deferred in backticks"; bad=1; admission='invalid' ;;
    esac
    if [[ -z "$rationale" || "$rationale" == \[* ]]; then
      fail "spec.md Scope Contract: $id Boundary rationale is empty or still a placeholder"
      bad=1
    fi
    if [[ "$admission" == deferred ]]; then
      if [[ "$refs" != '`none`' ]]; then
        fail "spec.md Scope Contract: deferred $id must use exactly 'none' in backticks for Spec refs"
        bad=1
      fi
      continue
    fi
    [[ "$admission" != invalid ]] || continue
    if ! printf '%s\n' "$refs" | grep -Eq '^`(FR|SC)-[0-9]{3}(, (FR|SC)-[0-9]{3})*`$'; then
      fail "spec.md Scope Contract: non-deferred $id Spec refs must be canonical FR-###/SC-### IDs in backticks joined by comma-space"
      bad=1
      continue
    fi
    inner=${refs#\`}
    inner=${inner%\`}
    : > "$TMP_DIR/scope-row-refs"
    fr_count=0
    sc_count=0
    while IFS= read -r ref; do
      ref=${ref# }
      if grep -Fxq "$ref" "$TMP_DIR/scope-row-refs"; then
        fail "spec.md Scope Contract: $id repeats Spec ref $ref"
        bad=1
        continue
      fi
      printf '%s\n' "$ref" >> "$TMP_DIR/scope-row-refs"
      printf '%s\n' "$ref" >> "$TMP_DIR/scope-nondeferred-refs"
      case "$ref" in
        FR-*) fr_count=$((fr_count + 1)) ;;
        SC-*) sc_count=$((sc_count + 1)) ;;
      esac
      if [[ "$admission" == core && "$ref" == SC-* ]]; then
        printf '%s\n' "$ref" >> "$TMP_DIR/scope-core-cap-refs"
      fi
    done < <(printf '%s\n' "$inner" | tr ',' '\n')
    if [[ "$fr_count" -eq 0 || "$sc_count" -eq 0 ]]; then
      fail "spec.md Scope Contract: non-deferred $id requires at least one FR and one SC"
      bad=1
    fi
  done < "$TMP_DIR/scope-rows"

  if [[ "$cap_count" -eq 0 || "$table_lines" -lt 3 ]]; then
    fail "spec.md Scope Contract: at least one capability row is required"
    bad=1
  fi
  if [[ "$core_count" -eq 0 ]]; then
    fail "spec.md Scope Contract: at least one core capability is required"
    bad=1
  fi

  for kind in FR SC; do
    definitions="$TMP_DIR/scope-${kind}-definitions"
    scope_definitions "$kind" > "$definitions"
    if [[ ! -s "$definitions" ]]; then
      fail "spec.md Scope Contract: no $kind definitions found in the canonical section"
      bad=1
      continue
    fi
    while IFS= read -r ref; do
      [[ -n "$ref" ]] || continue
      duplicate=$(grep -Fxc "$ref" "$definitions")
      if [[ "$duplicate" -ne 1 ]]; then
        fail "spec.md Scope Contract: $ref is defined $duplicate times"
        bad=1
      fi
      if ! grep -Fxq "$ref" "$TMP_DIR/scope-nondeferred-refs"; then
        fail "spec.md Scope Contract: $ref is not mapped by any non-deferred capability"
        bad=1
      fi
    done < <(sort -u "$definitions")
  done

  outside=$(awk '
    /^## Success Criteria([[:space:]]|$)/ {success=1; next}
    success && /^## / {success=0}
    success && /^### Measurable Outcomes([[:space:]]|$)/ {measurable=1; next}
    measurable && (/^### / || /^## /) {measurable=0}
    /^-[[:space:]]+\*\*SC-[0-9]+\*\*:/ && !measurable {print NR ":" $0}
  ' "$SPEC")
  if [[ -n "$outside" ]]; then
    fail "spec.md Scope Contract: SC definitions found outside '### Measurable Outcomes'"
    bad=1
  fi

  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    if ! grep -Fxq "$ref" "$TMP_DIR/scope-SC-definitions"; then
      fail "spec.md Scope Contract: Core completion refs references undefined $ref"
      bad=1
    elif ! grep -Fxq "$ref" "$TMP_DIR/scope-core-cap-refs"; then
      fail "spec.md Scope Contract: Core completion ref $ref is not mapped by a core capability"
      bad=1
    fi
  done < "$TMP_DIR/scope-core-completion"

  while IFS= read -r ref; do
    [[ -n "$ref" ]] || continue
    kind=${ref%%-*}
    if ! grep -Fxq "$ref" "$TMP_DIR/scope-${kind}-definitions"; then
      fail "spec.md Scope Contract: capability table references undefined $ref"
      bad=1
    fi
  done < <(sort -u "$TMP_DIR/scope-nondeferred-refs")

  [[ "$bad" -eq 0 ]] && pass "spec.md Scope Contract: fields, admissions, canonical refs, complete coverage, and core closure are valid"
}

legacy_progress_path_is_production() {
  local path="$1" feature_rel="$2"
  case "$path" in
    "$feature_rel"|"$feature_rel"/*|specs/*|test/*|tests/*|doc/*|docs/*|\
    */test/*|*/tests/*|*/doc/*|*/docs/*|README|README.*|CHANGELOG|CHANGELOG.*|LICENSE|LICENSE.*|\
    *.md|*.rst|*.adoc|*.txt)
      return 1
      ;;
  esac
  return 0
}

legacy_design_has_implementation_progress() {
  local repo feature_rel baseline='' seal_rel plan_rel spec_rel path review review_name receipt
  if [[ -f "$TASKS" ]] && grep -Eq '^- \[[xX]\] T[0-9][0-9][0-9]([[:space:]]|$)' "$TASKS"; then
    return 0
  fi
  if [[ -d "$FEATURE_DIR/.gatespec/reviews" ]]; then
    while IFS= read -r review; do
      review_name=$(basename "$review")
      case "$review_name" in REV-FOUNDATION|REV-FINAL) ;;
        *) printf '%s\n' "$review_name" | grep -Eq '^REV-US[1-9][0-9]*$' || continue ;;
      esac
      while IFS= read -r receipt; do
        case "$(basename "$receipt")" in
          round-00-request.md|round-00-verdict.md|round-01-request.md|round-01-verdict.md|\
          round-02-request.md|round-02-verdict.md|seal.md) return 0 ;;
        esac
      done < <(find "$review" -mindepth 1 -maxdepth 1 -type f -print 2>/dev/null)
    done < <(find "$FEATURE_DIR/.gatespec/reviews" -mindepth 1 -maxdepth 1 -type d -print 2>/dev/null)
  fi

  repo=$(git -C "$FEATURE_DIR" rev-parse --show-toplevel 2>/dev/null || true)
  [[ -n "$repo" ]] || return 1
  feature_rel=$(git -C "$FEATURE_DIR" rev-parse --show-prefix 2>/dev/null || true)
  feature_rel=${feature_rel%/}
  [[ -n "$feature_rel" ]] || return 1
  seal_rel="$feature_rel/.gatespec/reviews/REV-TASKS/seal.md"
  plan_rel="$feature_rel/plan.md"
  spec_rel="$feature_rel/spec.md"

  if [[ -f "$EXECUTION_STATE" ]]; then
    baseline=$(markdown_field_value "$EXECUTION_STATE" 'Original-Implementation-Baseline')
    is_git_oid "$baseline" || baseline=''
  fi
  if [[ -z "$baseline" ]]; then
    baseline=$(git -C "$repo" log -1 --format=%H -- "$seal_rel" 2>/dev/null || true)
  fi
  if [[ -z "$baseline" ]]; then
    baseline=$(git -C "$repo" log -1 --format=%H -- "$plan_rel" 2>/dev/null || true)
  fi
  if [[ -z "$baseline" ]]; then
    baseline=$(git -C "$repo" log -1 --format=%H -- "$spec_rel" 2>/dev/null || true)
  fi
  if [[ -n "$baseline" ]] && git -C "$repo" cat-file -e "$baseline^{commit}" 2>/dev/null; then
    while IFS= read -r -d '' path; do
      legacy_progress_path_is_production "$path" "$feature_rel" && return 0
    done < <(git -C "$repo" -c core.quotepath=false diff --name-only -z --no-renames "$baseline" HEAD 2>/dev/null)
  fi
  while IFS= read -r -d '' path; do
    legacy_progress_path_is_production "$path" "$feature_rel" && return 0
  done < <(git -C "$repo" -c core.quotepath=false diff --name-only -z --no-renames HEAD 2>/dev/null)
  while IFS= read -r -d '' path; do
    legacy_progress_path_is_production "$path" "$feature_rel" && return 0
  done < <(git -C "$repo" -c core.quotepath=false diff --cached --name-only -z --no-renames HEAD 2>/dev/null)
  while IFS= read -r -d '' path; do
    legacy_progress_path_is_production "$path" "$feature_rel" && return 0
  done < <(git -C "$repo" -c core.quotepath=false ls-files --others --exclude-standard -z 2>/dev/null)
  return 1
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

extract_spec_test_control_exceptions() {
  awk '
    $0 == "### Test Control Policy Exceptions *(gatespec: mandatory)*" {inside=1; next}
    inside && (/^## / || /^### /) {exit}
    inside {print}
  ' "$SPEC"
}

validate_test_control_exception_body() {
  local body="$1" context="$2" mode header separator invalid rows="$TMP_DIR/test-control-exception-rows"
  local exception rule decision replacement reason expected=1 expected_id bad=0
  local clarifications="$TMP_DIR/test-control-exception-clarifications"
  header='| Exception | Rule | Approved requirements decision | Replacement source-auditable mechanism | Reason / consequence |'
  separator='|---|---|---|---|---|'
  mode=$(markdown_field_value "$body" 'Mode')
  invalid=$(awk -v header="$header" -v separator="$separator" '
    /^[[:space:]]*$/ {next}
    !mode {if ($0 != "- **Mode**: `none`" && $0 != "- **Mode**: `approved`") print NR ":" $0; mode=1; next}
    !head {if ($0 != header) print NR ":" $0; head=1; next}
    !sep {if ($0 != separator) print NR ":" $0; sep=1; next}
    {if ($0 !~ /^\| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \|$/) print NR ":" $0}
    END {if (!mode || !head || !sep) print "missing canonical preamble"}
  ' "$body")
  if [[ -n "$invalid" || ( "$mode" != none && "$mode" != approved ) ]]; then
    fail "$context: Test Control Policy Exceptions must use the exact Mode/table schema"
    return 1
  fi
  awk -F '|' -v header="$header" -v separator="$separator" '
    /^[[:space:]]*$/ || /^- \*\*Mode\*\*:/ || $0 == header || $0 == separator {next}
    {for (i=2;i<=6;i++) {v=$i; sub(/^ /,"",v); sub(/ $/,"",v); printf "%s%s",(i==2?"":"\t"),v} print ""}
  ' "$body" > "$rows"
  if [[ "$mode" == none ]]; then
    if [[ $(awk 'NF {n++} END {print n+0}' "$rows") -ne 1 ]] ||
       ! grep -Fqx $'none\tnone\tnone\tnone\tnone' "$rows"; then
      fail "$context: Mode none requires the exact sole all-none exception row"
      return 1
    fi
    return 0
  fi
  if [[ ! -s "$rows" ]]; then
    fail "$context: Mode approved requires at least one TCE-### exception"
    return 1
  fi
  section_body "$SPEC" 'Clarifications' > "$clarifications"
  while IFS=$'\t' read -r exception rule decision replacement reason; do
    [[ -n "$exception" ]] || continue
    expected_id=$(printf 'TCE-%03d' "$expected")
    [[ "$exception" == "$expected_id" ]] || { fail "$context: exception IDs must be continuous from TCE-001"; bad=1; }
    case "$rule" in
      source-root|language-marker|formal-api|switch-identifier|control-model|touchpoint-shape|validator-path-marker) ;;
      *) fail "$context: $exception names an unknown or non-exemptable Test Control Policy rule"; bad=1 ;;
    esac
    if ! printf '%s\n' "$decision" | grep -Eq '^R[1-9][0-9]*$' ||
       [[ $(grep -Ec "^- Q: \\[${decision}\\] .+ → A: .+" "$clarifications" || true) -ne 1 ]]; then
      fail "$context: $exception must reference one concluded Requirements Clarification R<n>"
      bad=1
    fi
    if [[ -z "$replacement" || "$replacement" == none || "$replacement" == \[* ||
          -z "$reason" || "$reason" == none || "$reason" == \[* ]]; then
      fail "$context: $exception requires a replacement source-auditable mechanism and material reason/consequence"
      bad=1
    fi
    expected=$((expected + 1))
  done < "$rows"
  [[ "$bad" -eq 0 ]]
}

test_control_rule_is_excepted() {
  local wanted="$1"
  extract_spec_test_control_exceptions | awk -F '|' -v wanted="$wanted" '
    {
      value=$3
      sub(/^[[:space:]]*/, "", value)
      sub(/[[:space:]]*$/, "", value)
      if (value == wanted) found=1
    }
    END {exit !found}
  '
}

check_spec_test_control_policy_exceptions() {
  local count candidates body="$TMP_DIR/spec-test-control-exceptions" status
  local constraint_line next_h2_line exception_line
  count=$(grep -Fxc '### Test Control Policy Exceptions *(gatespec: mandatory)*' "$SPEC" || true)
  candidates=$(grep -cE '^#{1,6} Test Control Policy Exceptions([[:space:]]|$)' "$SPEC" || true)
  if [[ "$count" -eq 0 && "$candidates" -eq 0 ]]; then
    status=$(grep -E '^\*\*Status\*\*:' "$SPEC" | head -1)
    if [[ "$status" == '**Status**: Draft' ]]; then
      fail "spec.md: new/revised Protocol v3 Requirements require Test Control Policy Exceptions (use Mode none when no exception was approved)"
    else
      warn "spec.md: legacy approved Requirements has no Test Control Policy Exceptions contract; Protocol v3 Design may copy only canonical Mode none"
    fi
    return
  fi
  if [[ "$count" -ne 1 || "$candidates" -ne 1 ]]; then
    fail "spec.md: Test Control Policy Exceptions must have one exact mandatory H3 heading"
    return
  fi
  constraint_line=$(awk '/^## Constraint Basis([[:space:]]|$)/ {print NR; exit}' "$SPEC")
  exception_line=$(grep -nFx '### Test Control Policy Exceptions *(gatespec: mandatory)*' "$SPEC" | cut -d: -f1)
  next_h2_line=$(awk -v start="$constraint_line" 'NR > start && /^## / {print NR; exit}' "$SPEC")
  if ! [[ "$constraint_line" =~ ^[0-9]+$ && "$exception_line" =~ ^[0-9]+$ &&
          "$next_h2_line" =~ ^[0-9]+$ ]] ||
     (( exception_line <= constraint_line || exception_line >= next_h2_line )); then
    fail "spec.md: Test Control Policy Exceptions must be the unique nested H3 inside Constraint Basis"
    return
  fi
  extract_spec_test_control_exceptions > "$body"
  if validate_test_control_exception_body "$body" 'spec.md'; then
    pass "spec.md: Test Control Policy Exceptions is canonical and Requirements-decision-bound"
  fi
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
  check_spec_test_control_policy_exceptions
  check_scope_contract
  check_delivery_estimate "$SPEC" requirements
  check_fr_traceability
  check_template_remnants "$SPEC"
  check_gate_approval "$SPEC" 'Approved-Requirements'
  check_vague_words "$SPEC"
}

check_design_scope_boundary() {
  local schema_count section_count
  schema_count=$(grep -cF '**Scope Contract Schema**:' "$PLAN" || true)
  section_count=$(h2_count "$PLAN" 'Scope Contract')
  if [[ "$schema_count" -eq 0 && "$section_count" -eq 0 ]]; then
    pass "plan.md: Scope Contract remains single-source in approved Requirements"
  else
    fail "plan.md: do not duplicate Scope Contract schema or table; Requirements Content-SHA256 already binds it"
  fi
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

canonical_test_control_repo_path() {
  local path="$1" remaining component
  [[ -n "$path" && "$path" != not-applicable && "$path" != /* &&
     "$path" != *$'\t'* ]] || return 1
  case "$path" in
    /*|*/|*//*|'') return 1 ;;
  esac
  remaining=$path
  while :; do
    component=${remaining%%/*}
    [[ -n "$component" && "$component" != . && "$component" != .. ]] || return 1
    printf '%s\n' "$component" | grep -Eq '^[[:alnum:]_.+@][[:alnum:]_.+@-]*$' || return 1
    [[ "$remaining" == "$component" ]] && break
    remaining=${remaining#*/}
  done
  return 0
}

test_control_symbol_has_default_language_marker() {
  local symbol="$1"
  printf '%s\n' "$symbol" | grep -Eq \
    '(^|::|[./#])testonly(::|[./#])[[:alnum:]_~]|(^|::|[./#])(TestOnly|test_only)[[:alnum:]_]*(::|[./#(<~]|$)'
}

protocol_has_execution_state() {
  [[ "$1" == 2 || "$1" == 3 ]]
}

normalized_test_control_closure_stream_for_file() {
  local file="$1" cr
  cr=$(printf '\r')
  printf '%s\n' '## GateSpec Test Control Closure *(gatespec: mandatory)*'
  section_body "$file" 'GateSpec Test Control Closure' |
    sed -e "s/${cr}\$//" |
    awk 'NF {lines[++count]=$0} END {for (i=1; i<=count; i++) print lines[i]}'
}

normalized_test_control_closure_stream() {
  normalized_test_control_closure_stream_for_file "$TASKS"
}

test_control_closure_hash_for_file() {
  normalized_test_control_closure_stream_for_file "$1" | portable_sha256 | awk '{print $1}'
}

test_control_closure_hash() {
  test_control_closure_hash_for_file "$TASKS"
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
    /^[[:space:]]*$/ {
      if (kind == "verdict" && section == "Blockers") blocker_active=0
      next
    }
    kind == "request" {
      if (state == 0 && $0 ~ /^- \*\*(Protocol-Version|Review-ID|Round|Scope|Spec-Content-SHA256|Plan-Content-SHA256|Design-Basis-SHA256|Source-Design-Reviewed-SHA256|Source-Baseline-Commit|Test-Control-Mode|Test-Control-Closure-SHA256|Test-Control-Subject-Manifest-SHA256|Default-OFF-Evidence-SHA256|Explicit-ON-Evidence-SHA256|Previous-Verdict-SHA256)\*\*: `[^`]+`$/) next
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
      if ($0 ~ /^- \*\*(Protocol-Version|Review-ID|Round|Status|Request-SHA256|Verdict-SHA256|Spec-Content-SHA256|Plan-Content-SHA256|Design-Basis-SHA256|Source-Design-Reviewed-SHA256|Source-Baseline-Commit|Test-Control-Mode|Test-Control-Closure-SHA256|Test-Control-Subject-Manifest-SHA256|Default-OFF-Evidence-SHA256|Explicit-ON-Evidence-SHA256|Sealed-At|Seal-SHA256)\*\*: `[^`]+`$/) next
      print NR ":" $0
    }
  ' "$file" > "$invalid"
  if [[ -s "$invalid" ]]; then
    fail "$context: SOURCE receipt contains non-canonical heading, field, or prose"
  else
    pass "$context: SOURCE receipt uses only its canonical schema"
  fi
}

check_no_test_control_receipt_fields() {
  local file="$1" context="$2" label bad=0
  for label in Test-Control-Mode Test-Control-Closure-SHA256 \
    Test-Control-Subject-Manifest-SHA256 Default-OFF-Evidence-SHA256 \
    Explicit-ON-Evidence-SHA256; do
    if [[ -n "$(markdown_field_line_numbers "$file" "$label")" ]]; then
      fail "$context: Protocol v1/v2 must not contain Protocol v3 field $label"
      bad=1
    fi
  done
  [[ "$bad" -eq 0 ]] && pass "$context: legacy receipt contains no Protocol v3 Test Control fields"
  [[ "$bad" -eq 0 ]]
}

check_source_request_file() {
  local file="$1" round="$2" previous="$3" bind_current="$4" context request_hash
  local protocol id scope spec_hash plan_hash basis_hash reviewed_hash baseline bad=0
  context=$(basename "$file")
  if [[ ! -f "$file" ]]; then fail "$context: SOURCE request file not found"; return; fi
  check_source_receipt_whitelist "$file" request "$context"
  protocol=$(markdown_field_value "$file" 'Protocol-Version')
  if [[ "$protocol" == 3 ]]; then
    check_ordered_fields "$file" "$context" \
      'Protocol-Version' 'Review-ID' 'Round' 'Scope' 'Spec-Content-SHA256' \
      'Plan-Content-SHA256' 'Design-Basis-SHA256' 'Source-Design-Reviewed-SHA256' \
      'Source-Baseline-Commit' 'Test-Control-Mode' 'Test-Control-Closure-SHA256' \
      'Test-Control-Subject-Manifest-SHA256' 'Default-OFF-Evidence-SHA256' \
      'Explicit-ON-Evidence-SHA256' 'Previous-Verdict-SHA256' 'Request-SHA256'
  else
    check_ordered_fields "$file" "$context" \
      'Protocol-Version' 'Review-ID' 'Round' 'Scope' 'Spec-Content-SHA256' \
      'Plan-Content-SHA256' 'Design-Basis-SHA256' 'Source-Design-Reviewed-SHA256' \
      'Source-Baseline-Commit' 'Previous-Verdict-SHA256' 'Request-SHA256'
  fi
  check_exact_h2_order "$file" "$context" 'Required Tests'
  id=$(markdown_field_value "$file" 'Review-ID')
  scope=$(markdown_field_value "$file" 'Scope')
  spec_hash=$(markdown_field_value "$file" 'Spec-Content-SHA256')
  plan_hash=$(markdown_field_value "$file" 'Plan-Content-SHA256')
  basis_hash=$(markdown_field_value "$file" 'Design-Basis-SHA256')
  reviewed_hash=$(markdown_field_value "$file" 'Source-Design-Reviewed-SHA256')
  baseline=$(markdown_field_value "$file" 'Source-Baseline-Commit')
  if [[ "$protocol" != 2 && "$protocol" != 3 ]]; then
    fail "$context: SOURCE Protocol-Version must be 2 or 3"; bad=1
  elif [[ "$protocol" != "${ACTIVE_REVIEW_PROTOCOL:-$protocol}" ]]; then
    fail "$context: SOURCE Protocol-Version must match the active Plan protocol"; bad=1
  fi
  if [[ "$protocol" == 3 ]]; then
    for label in Test-Control-Mode Test-Control-Closure-SHA256 Test-Control-Subject-Manifest-SHA256 \
      Default-OFF-Evidence-SHA256 Explicit-ON-Evidence-SHA256; do
      [[ $(markdown_field_value "$file" "$label") == not-applicable ]] || {
        fail "$context: pre-tasks SOURCE field $label must be not-applicable"; bad=1;
      }
    done
  else
    check_no_test_control_receipt_fields "$file" "$context" || bad=1
  fi
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
  [[ "$protocol" == "${ACTIVE_REVIEW_PROTOCOL:-2}" && ( "$protocol" == 2 || "$protocol" == 3 ) ]] || {
    fail "$context: SOURCE Protocol-Version must be 2 or 3 and match the active Plan"; bad=1;
  }
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
  local file="$1" request="$2" verdict="$3" round="$4" label expected actual bad=0 request_protocol
  if [[ ! -f "$file" ]]; then fail "REV-SOURCE: PASS seal not found"; return; fi
  check_source_receipt_whitelist "$file" seal 'REV-SOURCE seal'
  request_protocol=$(markdown_field_value "$request" 'Protocol-Version')
  if [[ "$request_protocol" == 3 ]]; then
    check_ordered_fields "$file" 'REV-SOURCE seal' \
      'Protocol-Version' 'Review-ID' 'Round' 'Status' 'Request-SHA256' 'Verdict-SHA256' \
      'Spec-Content-SHA256' 'Plan-Content-SHA256' 'Design-Basis-SHA256' \
      'Source-Design-Reviewed-SHA256' 'Source-Baseline-Commit' 'Test-Control-Mode' \
      'Test-Control-Closure-SHA256' 'Test-Control-Subject-Manifest-SHA256' \
      'Default-OFF-Evidence-SHA256' 'Explicit-ON-Evidence-SHA256' 'Sealed-At' 'Seal-SHA256'
  else
    check_ordered_fields "$file" 'REV-SOURCE seal' \
      'Protocol-Version' 'Review-ID' 'Round' 'Status' 'Request-SHA256' 'Verdict-SHA256' \
      'Spec-Content-SHA256' 'Plan-Content-SHA256' 'Design-Basis-SHA256' \
      'Source-Design-Reviewed-SHA256' 'Source-Baseline-Commit' 'Sealed-At' 'Seal-SHA256'
    check_no_test_control_receipt_fields "$file" 'REV-SOURCE seal' || bad=1
  fi
  [[ $(markdown_field_value "$file" 'Protocol-Version') == $(markdown_field_value "$request" 'Protocol-Version') ]] || {
    fail "REV-SOURCE seal: Protocol-Version must match request"; bad=1;
  }
  [[ $(markdown_field_value "$file" 'Review-ID') == REV-SOURCE ]] || { fail "REV-SOURCE seal: Review-ID mismatch"; bad=1; }
  [[ $(markdown_field_value "$file" 'Round') == "$round" && $(markdown_field_value "$file" 'Status') == PASS ]] || { fail "REV-SOURCE seal: round/status mismatch"; bad=1; }
  [[ $(markdown_field_value "$file" 'Request-SHA256') == $(markdown_field_value "$request" 'Request-SHA256') ]] || { fail "REV-SOURCE seal: request hash mismatch"; bad=1; }
  [[ $(markdown_field_value "$file" 'Verdict-SHA256') == $(markdown_field_value "$verdict" 'Verdict-SHA256') ]] || { fail "REV-SOURCE seal: verdict hash mismatch"; bad=1; }
  for label in Spec-Content-SHA256 Plan-Content-SHA256 Design-Basis-SHA256 Source-Design-Reviewed-SHA256 Source-Baseline-Commit; do
    expected=$(markdown_field_value "$request" "$label"); actual=$(markdown_field_value "$file" "$label")
    [[ "$actual" == "$expected" ]] || { fail "REV-SOURCE seal: $label mismatch"; bad=1; }
  done
  if [[ "$request_protocol" == 3 ]]; then
    for label in Test-Control-Mode Test-Control-Closure-SHA256 Test-Control-Subject-Manifest-SHA256 \
      Default-OFF-Evidence-SHA256 Explicit-ON-Evidence-SHA256; do
      expected=$(markdown_field_value "$request" "$label"); actual=$(markdown_field_value "$file" "$label")
      [[ "$expected" == not-applicable && "$actual" == "$expected" ]] || {
        fail "REV-SOURCE seal: $label must copy not-applicable from request"; bad=1;
      }
    done
  fi
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
  if [[ ! -f "$EXECUTION_STATE" ]]; then fail "$context: Review Protocol v2/v3 requires .gatespec/execution-state.md"; return; fi
  invalid=$(awk '
    /^[[:space:]]*$/ {next}
    NR == 1 && $0 == "# GateSpec Execution State" {next}
    /^- \*\*(Protocol-Version|Execution-Epoch|Original-Implementation-Baseline|Task-Handoff-Commit|Source-Design-Content-SHA256|Preserved-Reviews-SHA256|Execution-State-SHA256)\*\*: `[^`]+`$/ {next}
    {print NR ":" $0}
  ' "$EXECUTION_STATE")
  [[ -z "$invalid" ]] || { fail "$context: only the canonical v2/v3 execution fields are allowed"; bad=1; }
  [[ $(sed -n '1p' "$EXECUTION_STATE") == '# GateSpec Execution State' &&
     $(grep -cFx '# GateSpec Execution State' "$EXECUTION_STATE" || true) -eq 1 ]] || {
    fail "$context: canonical execution state requires its exact line-1 title"; bad=1;
  }
  check_ordered_fields "$EXECUTION_STATE" "$context" \
    'Protocol-Version' 'Execution-Epoch' 'Original-Implementation-Baseline' 'Task-Handoff-Commit' \
    'Source-Design-Content-SHA256' 'Preserved-Reviews-SHA256' 'Execution-State-SHA256'
  protocol=$(markdown_field_value "$EXECUTION_STATE" 'Protocol-Version')
  epoch=$(markdown_field_value "$EXECUTION_STATE" 'Execution-Epoch')
  original=$(markdown_field_value "$EXECUTION_STATE" 'Original-Implementation-Baseline')
  handoff=$(markdown_field_value "$EXECUTION_STATE" 'Task-Handoff-Commit')
  source_hash=$(markdown_field_value "$EXECUTION_STATE" 'Source-Design-Content-SHA256')
  preserved=$(markdown_field_value "$EXECUTION_STATE" 'Preserved-Reviews-SHA256')
  if ! protocol_has_execution_state "$protocol"; then
    fail "$context: Protocol-Version must be 2 or 3"; bad=1
  elif [[ "$protocol" != "${ACTIVE_REVIEW_PROTOCOL:-$protocol}" ]]; then
    fail "$context: Protocol-Version must match the active Plan protocol"; bad=1
  fi
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
    fail "$context: downstream Protocol v2/v3 requires a committed Task-Handoff-Commit"; bad=1
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
  [[ "$bad" -eq 0 ]] && pass "$context: v2/v3 epoch, original baseline, handoff, Source, and preserved reviews are current"
}

check_canonical_empty_ia() {
  local file="$1" context="$2" expected_epoch="$3" expected_source="$4"
  local before="$FAILURES" invalid epoch source
  if [[ ! -f "$file" || -L "$file" ]]; then
    fail "$context: canonical empty IA must be a regular non-symlink file"
    return 1
  fi
  invalid=$(awk '
    /^[[:space:]]*$/ {next}
    NR == 1 && $0 == "# GateSpec Implementation Adjustments" {next}
    /^- \*\*(Execution-Epoch|Source-Design-Content-SHA256)\*\*: `[^`]+`$/ {next}
    $0 == "## Adjustments" {next}
    $0 == "- None — no bounded implementation adjustment has been recorded." {next}
    {print NR ":" $0}
  ' "$file")
  [[ -z "$invalid" ]] || fail "$context: canonical empty IA contains extra fields, headings, comments, or prose"
  if ! awk '
    /^[[:space:]]*$/ {next}
    {
      n++
      if (n == 1 && $0 == "# GateSpec Implementation Adjustments") next
      if (n == 2 && $0 ~ /^- \*\*Execution-Epoch\*\*: `E[1-9][0-9]*`$/) next
      if (n == 3) {
        value=$0
        sub(/^- \*\*Source-Design-Content-SHA256\*\*: `/, "", value)
        sub(/`$/, "", value)
        if (length(value) == 64 && value !~ /[^0-9a-f]/) next
      }
      if (n == 4 && $0 == "## Adjustments") next
      if (n == 5 && $0 == "- None — no bounded implementation adjustment has been recorded.") next
      bad=1
    }
    END {exit bad || n != 5}
  ' "$file"; then
    fail "$context: canonical empty IA nonblank lines are not in the exact protocol order"
  fi
  [[ $(grep -cFx '# GateSpec Implementation Adjustments' "$file" || true) -eq 1 &&
     $(sed -n '1p' "$file") == '# GateSpec Implementation Adjustments' ]] ||
    fail "$context: canonical empty IA requires its exact line-1 title"
  check_ordered_fields "$file" "$context" \
    'Execution-Epoch' 'Source-Design-Content-SHA256'
  [[ $(grep -cFx '## Adjustments' "$file" || true) -eq 1 ]] ||
    fail "$context: canonical empty IA requires exactly one Adjustments section"
  [[ $(grep -cFx -- '- None — no bounded implementation adjustment has been recorded.' "$file" || true) -eq 1 ]] ||
    fail "$context: canonical empty IA requires the exact template None row"
  epoch=$(markdown_field_value "$file" 'Execution-Epoch')
  source=$(markdown_field_value "$file" 'Source-Design-Content-SHA256')
  [[ "$epoch" == "$expected_epoch" ]] || fail "$context: Execution-Epoch does not match the required snapshot"
  [[ "$source" == "$expected_source" ]] || fail "$context: Source Design hash does not match the required snapshot"
  if [[ "$FAILURES" -eq "$before" ]]; then
    pass "$context: IA snapshot is canonical, empty, and epoch/Source-bound"
    return 0
  fi
  return 1
}

check_implementation_adjustments() {
  local require_empty="$1" context='implementation-adjustments.md' epoch source_hash expected_source
  local headings="$TMP_DIR/ia-headings" id block value expected=1 bad=0 source_bundle="$TMP_DIR/ia-source-bundle"
  local changed_path control_path
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
  if [[ "$require_empty" == yes ]]; then
    check_canonical_empty_ia "$IA_FILE" "$context" "$CURRENT_EXECUTION_EPOCH" "$expected_source" || bad=1
    : > "$TMP_DIR/ia-changed-paths"
    [[ "$bad" -eq 0 ]] && pass "$context: IA log is epoch-bound, bounded, ordered, and path-complete"
    return
  fi
  grep -E '^### IA[1-9][0-9]*:' "$IA_FILE" > "$headings" || true
  if [[ -s "$headings" ]] && grep -E '^- None —' "$IA_FILE" >/dev/null 2>&1; then
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
  if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 3 && "${CURRENT_TEST_CONTROL_MODE:-none}" == isolated &&
        -s "$TMP_DIR/test-control-structural-paths" ]]; then
    while IFS= read -r changed_path; do
      [[ -n "$changed_path" ]] || continue
      while IFS= read -r control_path; do
        [[ -n "$control_path" ]] || continue
        if [[ "$changed_path" == "$control_path" || "$changed_path" == "$control_path/"* ||
              "$control_path" == "$changed_path/"* ]]; then
          fail "$context: IA path '$changed_path' must not touch declared Test Control surfaces, touchpoints, wiring, or validators"
          bad=1
        fi
      done < "$TMP_DIR/test-control-structural-paths"
    done < "$TMP_DIR/ia-changed-paths"
  fi
  [[ "$bad" -eq 0 ]] && pass "$context: IA log is epoch-bound, bounded, ordered, and path-complete"
}

git_final_delta_hash() {
  local repo="$1" original="$2" subject="$3"
  git -C "$repo" diff-tree --raw -z --no-abbrev --no-renames "$original" "$subject" 2>/dev/null \
    | portable_sha256 | awk '{print $1}'
}

collect_delivery_exclusion_patterns() {
  local body="$TMP_DIR/delivery-estimate-metric" value
  : > "$TMP_DIR/delivery-exclusion-patterns"
  [[ "$LEGACY_PLAN_ESTIMATE" -eq 0 ]] || return
  section_body "$PLAN" 'Delivery Estimate' > "$body"
  value=$(delivery_field_values "$body" 'Excluded paths')
  printf '%s\n' "$value" | awk '
    {
      count=split($0, entries, ";")
      for (i=1; i<=count; i++) {
        item=entries[i]
        sub(/^[[:space:]]*/, "", item)
        sub(/[[:space:]]*$/, "", item)
        lower=tolower(item)
        if (lower ~ /^none[[:space:]]/) continue
        if (lower ~ /^generated:/) {
          sub(/^[^:]*:[[:space:]]*/, "", item)
          sub(/[[:space:]]+<-.*/, "", item)
        } else if ((separator=index(item, " — ")) > 0) {
          item=substr(item, 1, separator - 1)
        }
        sub(/^[[:space:]`]+/, "", item)
        sub(/[[:space:]`]+$/, "", item)
        if (item != "") print item
      }
    }
  ' > "$TMP_DIR/delivery-exclusion-patterns"
}

delivery_path_is_production() {
  local path="$1" pattern
  if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 3 && "${CURRENT_TEST_CONTROL_MODE:-none}" == isolated &&
        "${CURRENT_TEST_CONTROL_EVIDENCE_VALID:-no}" == yes ]]; then
    if grep -Fqx -- "$path" "$TMP_DIR/test-control-subject-production-paths"; then
      return 0
    fi
    if grep -Fqx -- "$path" "$TMP_DIR/test-control-subject-surface-paths" ||
       grep -Fqx -- "$path" "$TMP_DIR/test-control-subject-validator-paths"; then
      return 1
    fi
  fi
  case "$path" in
    "$GIT_FEATURE_REL"|"$GIT_FEATURE_REL"/*|specs/*|test/*|tests/*|doc/*|docs/*|\
    */test/*|*/tests/*|*/doc/*|*/docs/*|README|README.*|CHANGELOG|CHANGELOG.*|LICENSE|LICENSE.*|\
    *.md|*.rst|*.adoc|*.txt)
      return 1
      ;;
  esac
  while IFS= read -r pattern; do
    [[ -n "$pattern" ]] || continue
    # The right side is intentionally unquoted: [[ ]] applies the recorded
    # repository-relative glob without pathname expansion or eval.
    # shellcheck disable=SC2053
    if [[ "$path" == $pattern ]]; then return 1; fi
  done < "$TMP_DIR/delivery-exclusion-patterns"
  return 0
}

actual_within_estimate() {
  local actual="$1" lower="$2" upper="$3"
  decimal_le "$lower" "$actual" && decimal_le "$actual" "$upper"
}

report_actual_delivery_metrics() {
  local final_dir="$FEATURE_DIR/.gatespec/reviews/REV-FINAL" request round
  local protocol original subject record additions deletions path
  local total_additions=0 total_churn=0 total_files=0 binary_files=0 confidence
  round=$(markdown_field_value "$final_dir/seal.md" 'Round')
  request="$final_dir/round-${round}-request.md"
  [[ -f "$request" ]] || { fail "Delivery Size: sealed REV-FINAL request is missing"; return; }
  protocol=$(markdown_field_value "$request" 'Protocol-Version')
  subject=$(markdown_field_value "$request" 'Subject-Commit')
  if protocol_has_execution_state "$protocol"; then
    original=$CURRENT_ORIGINAL_BASELINE
  else
    original=$(markdown_field_value "$request" 'Implementation-Baseline')
  fi
  if ! is_git_oid "$original" || ! is_git_oid "$subject" || ! resolve_git_feature_paths; then
    fail "Delivery Size: cannot resolve the bound Original Baseline and REV-FINAL Subject"
    return
  fi
  collect_delivery_exclusion_patterns
  if ! git -C "$GIT_ROOT" -c core.quotepath=false diff --numstat -z --no-renames \
       "$original" "$subject" > "$TMP_DIR/delivery-numstat" 2>/dev/null; then
    fail "Delivery Size: cannot read the bound Git numstat delta"
    return
  fi
  while IFS= read -r -d '' record; do
    additions=${record%%$'\t'*}
    record=${record#*$'\t'}
    deletions=${record%%$'\t'*}
    path=${record#*$'\t'}
    delivery_path_is_production "$path" || continue
    total_files=$((total_files + 1))
    if [[ "$additions" == '-' || "$deletions" == '-' ]]; then
      binary_files=$((binary_files + 1))
      continue
    fi
    total_additions=$((total_additions + additions))
    total_churn=$((total_churn + additions + deletions))
  done < "$TMP_DIR/delivery-numstat"

  echo ""
  echo "Delivery Size: $original..$subject"
  echo "  Actual production additions: $total_additions"
  echo "  Actual production churn: $total_churn"
  echo "  Actual production files: $total_files"
  echo "  Binary production files without line counts: $binary_files"
  if [[ "$LEGACY_PLAN_ESTIMATE" -eq 1 ]]; then
    echo "  Approved Design estimate: unavailable (legacy Design)"
    return
  fi
  confidence=$(delivery_field_values "$TMP_DIR/delivery-estimate-design" 'Confidence')
  echo "  Approved Design: additions ${DESIGN_ADDITIONS_LOWER}..${DESIGN_ADDITIONS_UPPER}; churn ${DESIGN_CHURN_LOWER}..${DESIGN_CHURN_UPPER}; files ${DESIGN_FILES_LOWER}..${DESIGN_FILES_UPPER}; confidence $confidence"
  if ! actual_within_estimate "$total_additions" "$DESIGN_ADDITIONS_LOWER" "$DESIGN_ADDITIONS_UPPER" ||
     ! actual_within_estimate "$total_churn" "$DESIGN_CHURN_LOWER" "$DESIGN_CHURN_UPPER" ||
     ! actual_within_estimate "$total_files" "$DESIGN_FILES_LOWER" "$DESIGN_FILES_UPPER"; then
    warn "Delivery Size: actual metrics fall outside the approved Design intervals; size alone does not fail acceptance"
  else
    pass "Delivery Size: actual metrics are within the approved Design intervals"
  fi
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
  if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 3 && "${CURRENT_TEST_CONTROL_MODE:-none}" == isolated &&
        -s "$TMP_DIR/test-control-subject-paths" ]]; then
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      if grep -Fqx -- "$path" "$actual"; then
        printf '%s\n' "$path" >> "$expected"
      fi
    done < "$TMP_DIR/test-control-subject-paths"
  fi
  LC_ALL=C sort -u -o "$actual" "$actual"
  LC_ALL=C sort -u -o "$expected" "$expected"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if ! grep -Fqx -- "$path" "$expected"; then
      fail "REV-FINAL: product path '$path' is absent from Source Change Manifest + IA + validated Test Control paths"
      bad=1
    fi
  done < "$actual"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if ! grep -Fqx -- "$path" "$actual"; then
      fail "REV-FINAL: declared Source/IA or changed Test Control path '$path' is absent from the actual implementation delta"
      bad=1
    fi
  done < "$expected"
  [[ "$bad" -eq 0 ]] && pass "REV-FINAL: actual product paths equal Source Change Manifest + bounded IA + changed validated Test Control objects"
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
    1|2|3) ;;
    *) fail "plan.md: review Protocol Version must be '1' (legacy), '2' (legacy), or '3'"; bad=1 ;;
  esac
  ACTIVE_REVIEW_PROTOCOL=$protocol
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

tracked_legacy_acceptance_exists() {
  local repo rel
  [[ ( "$MODE" == acceptance || "$MODE" == acceptance-candidate ) &&
     ( "${ACTIVE_REVIEW_PROTOCOL:-}" == 1 || "${ACTIVE_REVIEW_PROTOCOL:-}" == 2 ) &&
     -f "$ACCEPTANCE" && ! -L "$ACCEPTANCE" ]] || return 1
  [[ $(markdown_field_value "$ACCEPTANCE" 'Protocol-Version') == "${ACTIVE_REVIEW_PROTOCOL:-}" ]] || return 1
  [[ $(markdown_field_value "$ACCEPTANCE" 'Status') == Accepted ]] || return 1
  repo=$(git -C "$FEATURE_DIR" rev-parse --show-toplevel 2>/dev/null || true)
  [[ -n "$repo" ]] || return 1
  rel=$(git -C "$FEATURE_DIR" rev-parse --show-prefix 2>/dev/null || true)
  rel=${rel%/}
  [[ -n "$rel" ]] || return 1
  git -C "$repo" ls-files --error-unmatch -- "$rel/.gatespec/acceptance.md" >/dev/null 2>&1
}

enforce_active_protocol_v3() {
  case "$MODE" in
    design|source-candidate|source-review|source|tasks-structure|task-review|retask-eligible|implementation-candidate|implementation-review)
      if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" != 3 ]]; then
        fail "plan.md: active or unaccepted Protocol v1/v2 execution is closed; run gatespec.plan --revise to create Protocol v3 (--retask cannot upgrade protocols)"
      fi
      ;;
    acceptance-candidate|acceptance)
      if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" != 3 ]] && ! tracked_legacy_acceptance_exists; then
        fail "plan.md: unaccepted Protocol v1/v2 delivery is closed; run gatespec.plan --revise to create Protocol v3"
      fi
      ;;
  esac
}

check_test_control_policy() {
  local body="$TMP_DIR/test-control-policy" actual="$TMP_DIR/test-control-policy-actual"
  local expected="$TMP_DIR/test-control-policy-expected" invalid
  if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" != 3 ]]; then
    return
  fi
  if [[ $(h2_count "$PLAN" 'Test Control Policy') -ne 1 ||
        $(grep -Fxc '## Test Control Policy *(gatespec: mandatory)*' "$PLAN" || true) -ne 1 ]]; then
    fail "plan.md: Protocol v3 requires one exact mandatory ## Test Control Policy section"
    return
  fi
  section_body "$PLAN" 'Test Control Policy' > "$body"
  awk -v output="$actual" '
    function flush() {
      if (label != "") print label "\t" value > output
      label=""; value=""
    }
    /^[[:space:]]*$/ {next}
    /^<!--/ && !started && !comment_seen {comment=1; comment_seen=1; if ($0 ~ /-->[[:space:]]*$/) comment=0; next}
    comment {if ($0 ~ /-->[[:space:]]*$/) comment=0; next}
    /^- \*\*[^*]+\*\*: / {
      flush(); started=1
      line=$0; sub(/^- \*\*/, "", line)
      split_at=index(line, "**: ")
      label=substr(line, 1, split_at - 1)
      value=substr(line, split_at + 4)
      next
    }
    started && /^  [^[:space:]]/ {
      line=$0; sub(/^  /, "", line)
      value=value " " line
      next
    }
    {print NR ":" $0 > output ".invalid"}
    END {
      flush()
      if (comment) print "unterminated comment" > output ".invalid"
    }
  ' "$body"
  invalid=''
  [[ -f "$actual.invalid" ]] && invalid=$(awk 'NF {print; exit}' "$actual.invalid")
  {
    printf '%s\t%s\n' 'Policy Schema' '`1`'
    printf '%s\t%s\n' 'Registration Stage' '`native tasks only`'
    printf '%s\t%s\n' 'Allowed Modes' '`none|isolated`'
    printf '%s\t%s\n' 'Isolation Contract' 'Test Control source roots end in `/src/testonly`; the terminal namespace or module is `testonly`, or a language without namespaces uses a leading `TestOnly`/`test_only` name. Formal product APIs gain no testing parameter, option, overload, getter, or state.'
    printf '%s\t%s\n' 'Activation Contract' 'each hook project uses a dedicated positive `*_ENABLE_TEST_HOOKS` compile switch whose declared default is `OFF`; only an explicit opt-in enables it. Runtime activation and common Debug, `BUILD_TESTING`, or equivalent umbrella triggers are forbidden. The OFF build fully elides Test Control fields, branches, resources, and symbols.'
    printf '%s\t%s\n' 'Control Contract' 'controls are typed, declarative, single-purpose, per-instance RAII and limited to named one-shot, count, barrier, time, random, fault, or observation effects. Generic callbacks, options bags, global mutable state, validation bypasses, duplicated business algorithms, placeholders, and controls without a named verification gap are forbidden. A control is removed with its last consumer.'
    printf '%s\t%s\n' 'Production Readability Contract' 'each affected production function has at most one visually contiguous dedicated `*_ENABLE_TEST_HOOKS` macro-guard block. That block contains only one `testonly` call and feeds its result into the normal production error/result path. Counting, waiting, fault selection, and observer dispatch live entirely under the registered `/src/testonly` surface.'
    printf '%s\t%s\n' 'Validator Contract' 'every isolated hook project supplies one tracked regular non-symlink Bash validator with `testonly` in its path/name and the sole invocation `bash <validator> --gatespec-lane default-off|explicit-on` (file mode may be 100644 or 100755). The default lane omits the hook option; the explicit lane sets it ON. Both run the same normal tests, the ON lane additionally runs hook-consuming tests, and output is canonical and subject-bound.'
  } > "$expected"
  if [[ -n "$invalid" ]] || ! cmp -s "$actual" "$expected"; then
    fail "plan.md Test Control Policy: the eight-field universal policy must exactly match canonical Schema 1"
    return
  fi
  pass "plan.md: Protocol v3 Test Control Policy exactly matches canonical Schema 1"
}

check_plan_test_control_policy_exceptions() {
  local spec_body="$TMP_DIR/spec-test-control-exceptions-plan-check"
  local plan_body="$TMP_DIR/plan-test-control-exceptions"
  local policy_line exception_line next_h2
  [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 3 ]] || return
  if [[ $(h2_count "$PLAN" 'Test Control Policy Exceptions') -ne 1 ||
        $(grep -Fxc '## Test Control Policy Exceptions *(gatespec: mandatory)*' "$PLAN" || true) -ne 1 ]]; then
    fail "plan.md: Protocol v3 requires one exact mandatory Test Control Policy Exceptions copy"
    return
  fi
  policy_line=$(grep -nFx '## Test Control Policy *(gatespec: mandatory)*' "$PLAN" | cut -d: -f1)
  exception_line=$(grep -nFx '## Test Control Policy Exceptions *(gatespec: mandatory)*' "$PLAN" | cut -d: -f1)
  next_h2=$(awk -v start="$policy_line" 'NR > start && /^## / {print; exit}' "$PLAN")
  if ! [[ "$policy_line" =~ ^[0-9]+$ && "$exception_line" =~ ^[0-9]+$ ]] ||
     [[ "$next_h2" != '## Test Control Policy Exceptions *(gatespec: mandatory)*' ]]; then
    fail "plan.md: Test Control Policy Exceptions must be the H2 immediately after Test Control Policy"
    return
  fi
  next_h2=$(awk -v start="$exception_line" 'NR > start && /^## / {print; exit}' "$PLAN")
  if [[ "$next_h2" != '## Implementation Review Contract *(gatespec: mandatory)*' ]]; then
    fail "plan.md: Test Control Policy Exceptions must be immediately before Implementation Review Contract"
    return
  fi
  section_body "$PLAN" 'Test Control Policy Exceptions' > "$plan_body"
  validate_test_control_exception_body "$plan_body" 'plan.md' || return
  if [[ $(grep -Fxc '### Test Control Policy Exceptions *(gatespec: mandatory)*' "$SPEC" || true) -eq 0 ]]; then
    if [[ $(markdown_field_value "$plan_body" 'Mode') != none ]]; then
      fail "plan.md: legacy Requirements without a Test Control Policy Exceptions contract permits only canonical Mode none"
      return
    fi
    pass "plan.md: canonical Mode none preserves the legacy Requirements implicit no-exception state"
    return
  fi
  extract_spec_test_control_exceptions > "$spec_body"
  if ! cmp -s "$spec_body" "$plan_body"; then
    fail "plan.md: Test Control Policy Exceptions must be a scoped byte-identical copy of approved Requirements"
    return
  fi
  pass "plan.md: Test Control Policy Exceptions exactly copies the approved Requirements decisions"
}

check_tasks_structure() {
  local id count line line_number later_task phase_heading task_id bad=0 expected=1 expected_id story
  local previous_checkpoint_line=0 closure_policy="${1:-required}"
  local checkpoint_ids="$TMP_DIR/task-checkpoint-ids" valid_ids="$TMP_DIR/task-ids"
  echo ""
  echo "Tasks Structure Gate: $TASKS"
  TASKS_CLOSURE_POLICY=$closure_policy
  if [[ ! -f "$TASKS" || -L "$TASKS" ]]; then
    fail "tasks.md must be a regular non-symlink file in $FEATURE_DIR"
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
  if [[ "$closure_policy" == optional ]] &&
     ! grep -qE '^[[:space:]]*#{1,6}[[:space:]]+GateSpec (Checkpoint|Prior Review) Closure' "$TASKS"; then
    pass "tasks.md: legacy retask eligibility checks basic task/checkpoint structure before Closure regeneration"
  else
    check_tasks_closure
  fi
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

canonical_id_list() {
  local value="$1" pattern="$2" destination="$3" context="$4" allow_none="$5"
  local id rebuilt sorted="$TMP_DIR/canonical-list-sorted" bad=0 separator=''
  : > "$destination"
  if [[ "$value" == none ]]; then
    if [[ "$allow_none" == yes ]]; then return 0; fi
    fail "$context must contain at least one identifier"
    return 1
  fi
  [[ -n "$value" ]] || { fail "$context must not be empty"; return 1; }
  printf '%s\n' "$value" | awk -F ', ' '{for (i=1;i<=NF;i++) print $i}' > "$destination"
  while IFS= read -r id; do
    if ! printf '%s\n' "$id" | grep -Eq "$pattern"; then
      fail "$context contains invalid identifier '$id'"
      bad=1
    fi
    rebuilt="${rebuilt:-}${separator}${id}"
    separator=', '
  done < "$destination"
  if [[ "${rebuilt:-}" != "$value" ]]; then
    fail "$context must use exact comma+space separators"
    bad=1
  fi
  LC_ALL=C sort -u "$destination" > "$sorted"
  if ! cmp -s "$destination" "$sorted"; then
    fail "$context must be unique and C-sorted"
    bad=1
  fi
  [[ "$bad" -eq 0 ]]
}

collect_required_closure_contracts() {
  local bundle="$TMP_DIR/closure-source-bundle"
  : > "$TMP_DIR/closure-required-contracts"
  sed -n 's/^- \*\*\(FR-[0-9][0-9]*\|SC-[0-9][0-9]*\)\*\*:.*/\1/p' "$SPEC" \
    >> "$TMP_DIR/closure-required-contracts"
  sed -n 's/^### \(D[1-9][0-9]*\):.*/\1/p' "$PLAN" \
    >> "$TMP_DIR/closure-required-contracts"
  if [[ -f "$SOURCE_ENTRY" ]]; then
    source_bundle_concat > "$bundle"
    sed -n \
      -e 's/^### \(SD[1-9][0-9]*\):.*/\1/p' \
      -e 's/^### \(SD-\(F\|U\|FLOW\|ALG\|FAIL\|TEST\)[1-9][0-9]*\):.*/\1/p' \
      "$bundle" >> "$TMP_DIR/closure-required-contracts"
  fi
  LC_ALL=C sort -u -o "$TMP_DIR/closure-required-contracts" "$TMP_DIR/closure-required-contracts"
}

extract_four_column_table() {
  local body="$1" header="$2" output="$3" context="$4" invalid
  : > "$output"
  invalid=$(awk -v header="$header" '
    /^[[:space:]]*$/ {next}
    !seen_header {
      if ($0 != header) {print NR ":" $0; bad=1}
      seen_header=1
      next
    }
    !seen_separator {
      if ($0 != "|---|---|---|---|") {print NR ":" $0; bad=1}
      seen_separator=1
      next
    }
    {
      if ($0 !~ /^\| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \|$/) {
        print NR ":" $0
      }
    }
    END {
      if (!seen_header) print "missing header"
      if (!seen_separator) print "missing separator"
    }
  ' "$body")
  if [[ -n "$invalid" ]]; then
    fail "$context must contain only its exact header, separator, and canonical four-column rows"
    return 1
  fi
  awk -F '|' -v header="$header" '
    /^[[:space:]]*$/ || $0 == header || $0 == "|---|---|---|---|" {next}
    {
      for (i=2;i<=5;i++) {
        value=$i
        sub(/^ /, "", value)
        sub(/ $/, "", value)
        printf "%s%s", (i == 2 ? "" : "\t"), value
      }
      print ""
    }
  ' "$body" > "$output"
}

check_checkpoint_closure_table() {
  local body="$TMP_DIR/checkpoint-closure-body" rows="$TMP_DIR/checkpoint-closure-rows"
  local checkpoint refs production verification expected checkpoint_line previous_line=0
  local row_count required_count index=0 bad=0 id line
  local contract_pattern='^(FR-[0-9]+|SC-[0-9]+|D[1-9][0-9]*|SD[1-9][0-9]*|SD-(F|U|FLOW|ALG|FAIL|TEST)[1-9][0-9]*)$'
  local task_pattern='^T[0-9][0-9][0-9]$'
  section_body "$TASKS" 'GateSpec Checkpoint Closure' > "$body"
  if ! extract_four_column_table "$body" \
    '| Checkpoint | Contract refs | Production tasks | Verification tasks |' "$rows" \
    'tasks.md: GateSpec Checkpoint Closure'; then
    return
  fi
  : > "$TMP_DIR/closure-actual-contracts"
  : > "$TMP_DIR/closure-all-task-ids"
  row_count=$(awk 'NF {n++} END {print n+0}' "$rows")
  required_count=$(awk 'NF {n++} END {print n+0}' "$TMP_DIR/required-checkpoints")
  if [[ "$row_count" -ne "$required_count" ]]; then
    fail "tasks.md: Checkpoint Closure needs exactly one row per Required Checkpoint"
    bad=1
  fi

  while IFS=$'\t' read -r checkpoint refs production verification; do
    [[ -n "$checkpoint" ]] || continue
    index=$((index + 1))
    expected=$(sed -n "${index}p" "$TMP_DIR/required-checkpoints")
    if [[ "$checkpoint" != "$expected" ]]; then
      fail "tasks.md: Checkpoint Closure row $index must be $expected"
      bad=1
    fi
    if canonical_id_list "$refs" "$contract_pattern" "$TMP_DIR/closure-row-contracts" \
      "tasks.md: $checkpoint Contract refs" no; then
      cat "$TMP_DIR/closure-row-contracts" >> "$TMP_DIR/closure-actual-contracts"
    else
      bad=1
    fi
    if ! canonical_id_list "$production" "$task_pattern" "$TMP_DIR/closure-row-production" \
      "tasks.md: $checkpoint Production tasks" yes; then
      bad=1
    fi
    if ! canonical_id_list "$verification" "$task_pattern" "$TMP_DIR/closure-row-verification" \
      "tasks.md: $checkpoint Verification tasks" no; then
      bad=1
    fi
    cat "$TMP_DIR/closure-row-production" "$TMP_DIR/closure-row-verification" \
      > "$TMP_DIR/closure-row-tasks"
    LC_ALL=C sort "$TMP_DIR/closure-row-tasks" | uniq -d > "$TMP_DIR/closure-row-duplicates"
    if [[ -s "$TMP_DIR/closure-row-duplicates" ]]; then
      fail "tasks.md: $checkpoint Production and Verification tasks overlap"
      bad=1
    fi
    checkpoint_line=$(grep -nE "^- \\[[ xX]\\] T[0-9][0-9][0-9].*GateSpec review checkpoint ${checkpoint}:" "$TASKS" \
      | cut -d: -f1)
    if ! [[ "$checkpoint_line" =~ ^[0-9]+$ ]]; then
      fail "tasks.md: cannot establish the strict task interval for $checkpoint"
      bad=1
      checkpoint_line=$previous_line
    fi
    : > "$TMP_DIR/closure-interval-tasks"
    awk -v start="$previous_line" -v stop="$checkpoint_line" '
      NR > start && NR < stop &&
      /^- \[[ xX]\] T[0-9][0-9][0-9]([[:space:]]|$)/ &&
      $0 !~ /GateSpec review checkpoint REV-(FOUNDATION|US[1-9][0-9]*|FINAL):/ {
        print substr($0, index($0, "T"), 4)
      }
    ' "$TASKS" | LC_ALL=C sort > "$TMP_DIR/closure-interval-tasks"
    LC_ALL=C sort "$TMP_DIR/closure-row-tasks" > "$TMP_DIR/closure-row-tasks-sorted"
    if ! cmp -s "$TMP_DIR/closure-interval-tasks" "$TMP_DIR/closure-row-tasks-sorted"; then
      fail "tasks.md: $checkpoint Production/Verification tasks must exactly partition its strict checkpoint interval"
      bad=1
    fi
    while IFS= read -r id; do
      [[ -n "$id" ]] || continue
      line=$(grep -E "^- \\[[ xX]\\] ${id}([[:space:]]|$)" "$TASKS" || true)
      if [[ $(printf '%s\n' "$line" | awk 'NF {n++} END {print n+0}') -ne 1 ]]; then
        fail "tasks.md: Checkpoint Closure task $id must resolve exactly once"
        bad=1
      elif printf '%s\n' "$line" | grep -Eq 'GateSpec review checkpoint REV-(FOUNDATION|US[1-9][0-9]*|FINAL):'; then
        fail "tasks.md: Checkpoint Closure must not reference checkpoint task $id"
        bad=1
      fi
    done < "$TMP_DIR/closure-row-tasks"
    cat "$TMP_DIR/closure-row-tasks" >> "$TMP_DIR/closure-all-task-ids"
    previous_line=$checkpoint_line
  done < "$rows"

  LC_ALL=C sort -u "$TMP_DIR/closure-actual-contracts" > "$TMP_DIR/closure-contracts-sorted"
  if ! cmp -s "$TMP_DIR/closure-required-contracts" "$TMP_DIR/closure-contracts-sorted"; then
    fail "tasks.md: Checkpoint Closure Contract refs must exactly cover current FR/SC/approved Design and Source IDs"
    bad=1
  fi
  LC_ALL=C sort "$TMP_DIR/closure-all-task-ids" | uniq -d > "$TMP_DIR/closure-duplicate-tasks"
  if [[ -s "$TMP_DIR/closure-duplicate-tasks" ]]; then
    fail "tasks.md: every non-checkpoint task may appear in Closure exactly once"
    bad=1
  fi
  awk '
    /^- \[[ xX]\] T[0-9][0-9][0-9]([[:space:]]|$)/ &&
    $0 !~ /GateSpec review checkpoint REV-(FOUNDATION|US[1-9][0-9]*|FINAL):/ {
      print substr($0, index($0, "T"), 4)
    }
  ' "$TASKS" | LC_ALL=C sort > "$TMP_DIR/closure-all-noncheckpoint-tasks"
  LC_ALL=C sort "$TMP_DIR/closure-all-task-ids" > "$TMP_DIR/closure-all-task-ids-sorted"
  if ! cmp -s "$TMP_DIR/closure-all-noncheckpoint-tasks" "$TMP_DIR/closure-all-task-ids-sorted"; then
    fail "tasks.md: Checkpoint Closure must cover every non-checkpoint task exactly once"
    bad=1
  fi
  [[ "$bad" -eq 0 ]] && pass "tasks.md: checkpoint closure exactly partitions contracts and task intervals"
}

parse_test_control_path_symbols() {
  local value="$1" output="$2" context="$3" entry path symbol rebuilt='' separator='' bad=0
  : > "$output"
  printf '%s\n' "$value" | awk -F ', ' '{for (i=1; i<=NF; i++) print $i}' > "$TMP_DIR/test-control-path-symbol-items"
  while IFS= read -r entry; do
    path=${entry%%::*}
    symbol=${entry#*::}
    if [[ "$entry" != *::* || "$path" == "$entry" ]] ||
       ! canonical_test_control_repo_path "$path" ||
       ! printf '%s\n' "$symbol" | grep -Eq '^[][[:alnum:]_:.#()+<>=~/?!%^&*-]+$'; then
      fail "$context contains invalid concrete path::symbol '$entry'"
      bad=1
    else
      printf '%s\t%s\n' "$path" "$symbol" >> "$output"
    fi
    rebuilt="${rebuilt}${separator}${entry}"
    separator=', '
  done < "$TMP_DIR/test-control-path-symbol-items"
  if [[ -z "$value" || "$rebuilt" != "$value" ]]; then
    fail "$context must use canonical comma+space path::symbol entries"
    bad=1
  fi
  if [[ -s "$output" ]]; then
    LC_ALL=C sort -u "$output" > "$TMP_DIR/test-control-path-symbol-sorted"
    if ! cmp -s "$output" "$TMP_DIR/test-control-path-symbol-sorted"; then
      fail "$context entries must be unique and C-sorted"
      bad=1
    fi
  fi
  [[ "$bad" -eq 0 ]]
}

check_test_control_closure_table() {
  local body="$TMP_DIR/test-control-closure-body" rows="$TMP_DIR/test-control-closure-rows"
  local mode mode_lines invalid header separator control gap surfaces touchpoints effect wiring consumers proof
  local expected=1 expected_id switch wiring_path validator_path rebuilt count id task_line bad=0
  local source_root_excepted=no language_marker_excepted=no
  local switch_identifier_excepted=no validator_marker_excepted=no
  header='| Control | Verification gap / production invariant | Test-only surface | Production touchpoint | Allowed effect / lifetime | Build switch / validator | Consumer tasks/tests | Default-build proof task |'
  separator='|---|---|---|---|---|---|---|---|'
  section_body "$TASKS" 'GateSpec Test Control Closure' > "$body"
  mode=$(markdown_field_value "$body" 'Mode')
  mode_lines=$(markdown_field_line_numbers "$body" 'Mode')
  if [[ $(printf '%s\n' "$mode_lines" | awk 'NF {n++} END {print n+0}') -ne 1 ]] ||
     [[ "$mode" != none && "$mode" != isolated ]]; then
    fail "tasks.md: Test Control Closure requires one exact Mode of none or isolated"
    return
  fi
  invalid=$(awk -v header="$header" -v separator="$separator" '
    /^[[:space:]]*$/ {next}
    !mode {
      if ($0 != "- **Mode**: `none`" && $0 != "- **Mode**: `isolated`") print NR ":" $0
      mode=1; next
    }
    !head {if ($0 != header) print NR ":" $0; head=1; next}
    !sep {if ($0 != separator) print NR ":" $0; sep=1; next}
    {
      if ($0 !~ /^\| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \|$/) print NR ":" $0
    }
    END {if (!mode || !head || !sep) print "missing canonical preamble"}
  ' "$body")
  if [[ -n "$invalid" ]]; then
    fail "tasks.md: Test Control Closure must contain only its exact Mode, header, separator, and canonical eight-column rows"
    return
  fi
  awk -F '|' -v header="$header" -v separator="$separator" '
    /^[[:space:]]*$/ || /^- \*\*Mode\*\*:/ || $0 == header || $0 == separator {next}
    {
      for (i=2; i<=9; i++) {
        value=$i; sub(/^ /, "", value); sub(/ $/, "", value)
        printf "%s%s", (i == 2 ? "" : "\t"), value
      }
      print ""
    }
  ' "$body" > "$rows"
  : > "$TMP_DIR/test-control-ids"
  : > "$TMP_DIR/test-control-surface-declarations"
  : > "$TMP_DIR/test-control-touchpoint-declarations"
  : > "$TMP_DIR/test-control-structural-paths"
  : > "$TMP_DIR/test-control-consumer-task-ids"
  : > "$TMP_DIR/test-control-validator-tuples"
  test_control_rule_is_excepted source-root && source_root_excepted=yes
  test_control_rule_is_excepted language-marker && language_marker_excepted=yes
  test_control_rule_is_excepted switch-identifier && switch_identifier_excepted=yes
  test_control_rule_is_excepted validator-path-marker && validator_marker_excepted=yes
  if [[ "$mode" == none ]]; then
    if [[ $(awk 'NF {n++} END {print n+0}' "$rows") -ne 1 ]] ||
       ! grep -Fqx $'none\tnone\tnone\tnone\tnone\tnone\tnone\tnone' "$rows"; then
      fail "tasks.md: Test Control Closure Mode none requires the exact sole all-none row"
      bad=1
    fi
  else
    if [[ ! -s "$rows" ]]; then
      fail "tasks.md: Test Control Closure Mode isolated requires at least one TC-### row"
      bad=1
    fi
    while IFS=$'\t' read -r control gap surfaces touchpoints effect wiring consumers proof; do
      [[ -n "$control" ]] || continue
      expected_id=$(printf 'TC-%03d' "$expected")
      if [[ "$control" != "$expected_id" ]]; then
        fail "tasks.md: Test Control IDs must be continuous from TC-001 (expected $expected_id)"
        bad=1
      fi
      printf '%s\n' "$control" >> "$TMP_DIR/test-control-ids"
      if [[ -z "$gap" || "$gap" == none || "$gap" == \[* || -z "$effect" || "$effect" == none || "$effect" == \[* ]]; then
        fail "tasks.md: $control gap/invariant and allowed effect/lifetime must be substantive"
        bad=1
      fi
      if parse_test_control_path_symbols "$surfaces" "$TMP_DIR/test-control-row-surfaces" "tasks.md: $control Test-only surface"; then
        while IFS=$'\t' read -r path symbol; do
          case "$path" in
            src/testonly|src/testonly/*|*/src/testonly|*/src/testonly/*) ;;
            *)
              if [[ "$source_root_excepted" != yes ]]; then
                fail "tasks.md: $control Test-only surface '$path' must be under a src/testonly root unless Requirements approved the source-root exception"
                bad=1
              fi
              ;;
          esac
          if [[ "$language_marker_excepted" != yes ]] &&
             ! test_control_symbol_has_default_language_marker "$symbol"; then
            fail "tasks.md: $control Test-only surface symbol '$symbol' must use a testonly namespace/module or leading TestOnly/test_only name unless Requirements approved the language-marker exception"
            bad=1
          fi
          printf '%s\t%s\t%s\n' "$control" "$path" "$symbol" >> "$TMP_DIR/test-control-surface-declarations"
          printf '%s\n' "$path" >> "$TMP_DIR/test-control-structural-paths"
        done < "$TMP_DIR/test-control-row-surfaces"
      else
        bad=1
      fi
      if parse_test_control_path_symbols "$touchpoints" "$TMP_DIR/test-control-row-touchpoints" "tasks.md: $control Production touchpoint"; then
        while IFS=$'\t' read -r path symbol; do
          case "$path" in
            src/testonly|src/testonly/*|*/src/testonly|*/src/testonly/*)
              fail "tasks.md: $control Production touchpoint '$path' must not be under src/testonly"; bad=1 ;;
          esac
          printf '%s\t%s\t%s\n' "$control" "$path" "$symbol" >> "$TMP_DIR/test-control-touchpoint-declarations"
          printf '%s\n' "$path" >> "$TMP_DIR/test-control-structural-paths"
        done < "$TMP_DIR/test-control-row-touchpoints"
      else
        bad=1
      fi
      switch=${wiring%% @ *}
      rebuilt=${wiring#* @ }
      wiring_path=${rebuilt%% @ *}
      validator_path=${rebuilt#* @ }
      if [[ "$wiring" != "$switch @ $wiring_path @ $validator_path" ]] ||
         ! printf '%s\n' "$switch" | grep -Eq '^[A-Za-z_][A-Za-z0-9_]*$' ||
         ! canonical_test_control_repo_path "$wiring_path" ||
         ! canonical_test_control_repo_path "$validator_path"; then
        fail "tasks.md: $control Build switch / validator must be 'NAME_ENABLE_TEST_HOOKS @ wiring/path @ validator/testonly-path'"
        bad=1
      elif [[ "$switch_identifier_excepted" != yes ]] &&
           ! printf '%s\n' "$switch" | grep -Eq '^[A-Z][A-Z0-9_]*_ENABLE_TEST_HOOKS$'; then
        fail "tasks.md: $control Build switch must use uppercase NAME_ENABLE_TEST_HOOKS unless Requirements approved the switch-identifier exception"
        bad=1
      elif [[ "$validator_marker_excepted" != yes && "$validator_path" != *testonly* ]]; then
        fail "tasks.md: $control validator path must contain testonly unless Requirements approved the validator-path-marker exception"
        bad=1
      else
        printf '%s\n' "$wiring_path" "$validator_path" >> "$TMP_DIR/test-control-structural-paths"
        printf '%s\t%s\t%s\n' "$switch" "$wiring_path" "$validator_path" >> "$TMP_DIR/test-control-validator-tuples"
      fi
      if canonical_id_list "$consumers" '^T[0-9][0-9][0-9]$' "$TMP_DIR/test-control-row-consumers" \
        "tasks.md: $control Consumer tasks/tests" no; then
        while IFS= read -r id; do
          task_line=$(grep -E "^- \\[[ xX]\\] ${id}([[:space:]]|$)" "$TASKS" || true)
          if [[ $(printf '%s\n' "$task_line" | awk 'NF {n++} END {print n+0}') -ne 1 ]] ||
             printf '%s\n' "$task_line" | grep -Eq 'GateSpec review checkpoint REV-'; then
            fail "tasks.md: $control consumer $id must resolve to one non-checkpoint task"
            bad=1
          fi
          printf '%s\n' "$id" >> "$TMP_DIR/test-control-consumer-task-ids"
        done < "$TMP_DIR/test-control-row-consumers"
      else
        bad=1
      fi
      task_line=$(grep -E "^- \\[[ xX]\\] ${proof}([[:space:]]|$)" "$TASKS" || true)
      if ! printf '%s\n' "$proof" | grep -Eq '^T[0-9][0-9][0-9]$' ||
         [[ $(printf '%s\n' "$task_line" | awk 'NF {n++} END {print n+0}') -ne 1 ]] ||
         printf '%s\n' "$task_line" | grep -Eq 'GateSpec review checkpoint REV-'; then
        fail "tasks.md: $control Default-build proof task must resolve to one non-checkpoint T###"
        bad=1
      fi
      expected=$((expected + 1))
    done < "$rows"
    LC_ALL=C sort -u -o "$TMP_DIR/test-control-structural-paths" "$TMP_DIR/test-control-structural-paths"
    LC_ALL=C sort -u -o "$TMP_DIR/test-control-validator-tuples" "$TMP_DIR/test-control-validator-tuples"
    cut -f1,2 "$TMP_DIR/test-control-validator-tuples" | LC_ALL=C sort | uniq -d > "$TMP_DIR/test-control-duplicate-switch-wiring"
    if [[ -s "$TMP_DIR/test-control-duplicate-switch-wiring" ]]; then
      fail "tasks.md: each project/bundle switch and build-wiring pair must identify exactly one validator path"
      bad=1
    fi
    cut -f3 "$TMP_DIR/test-control-validator-tuples" | LC_ALL=C sort | uniq -d > "$TMP_DIR/test-control-duplicate-validators"
    if [[ -s "$TMP_DIR/test-control-duplicate-validators" ]]; then
      fail "tasks.md: each project/bundle validator path must identify exactly one switch/wiring tuple"
      bad=1
    fi
  fi
  CURRENT_TEST_CONTROL_MODE=$mode
  CURRENT_TEST_CONTROL_CLOSURE_HASH=$(test_control_closure_hash) || CURRENT_TEST_CONTROL_CLOSURE_HASH=''
  is_lower_hex64 "$CURRENT_TEST_CONTROL_CLOSURE_HASH" || { fail "tasks.md: cannot hash normalized Test Control Closure"; bad=1; }
  [[ "$bad" -eq 0 ]] && pass "tasks.md: Test Control Closure is canonical, bounded, and structurally parseable"
}

check_tasks_closure() {
  local checkpoint_exact prior_exact test_exact checkpoint_candidates prior_candidates test_candidates first_phase
  local before_phase_h2="$TMP_DIR/tasks-before-phase-h2" third_last second_last last bad=0 grandfather_before
  checkpoint_exact=$(grep -Fxc '## GateSpec Checkpoint Closure *(gatespec: mandatory)*' "$TASKS" || true)
  prior_exact=$(grep -Fxc '## GateSpec Prior Review Closure *(gatespec: mandatory)*' "$TASKS" || true)
  checkpoint_candidates=$(grep -cE '^[[:space:]]*#{1,6}[[:space:]]+GateSpec Checkpoint Closure' "$TASKS" || true)
  prior_candidates=$(grep -cE '^[[:space:]]*#{1,6}[[:space:]]+GateSpec Prior Review Closure' "$TASKS" || true)
  test_exact=$(grep -Fxc '## GateSpec Test Control Closure *(gatespec: mandatory)*' "$TASKS" || true)
  test_candidates=$(grep -cE '^[[:space:]]*#{1,6}[[:space:]]+GateSpec Test Control Closure' "$TASKS" || true)
  if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 3 ]]; then
    if [[ "$test_exact" -ne 1 || "$test_candidates" -ne 1 ]]; then
      fail "tasks.md: Protocol v3 requires one exact mandatory GateSpec Test Control Closure section"
      return
    fi
  elif [[ "$test_candidates" -ne 0 ]]; then
    fail "tasks.md: legacy Protocol v1/v2 must not contain the Protocol v3 Test Control Closure"
    return
  fi
  if [[ "$checkpoint_candidates" -eq 0 && "$prior_candidates" -eq 0 ]]; then
    if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 3 ]]; then
      fail "tasks.md: Protocol v3 never grandfathers missing Checkpoint, Prior Review, or Test Control Closure sections"
      return
    fi
    grandfather_before=$FAILURES
    if check_complete_tracked_task_review_grandfather; then
      collect_prior_review_findings
      [[ "$FAILURES" -eq "$grandfather_before" ]] && check_task_review_git_state
      if [[ "$FAILURES" -eq "$grandfather_before" ]]; then
        pass "tasks.md: complete clean tracked legacy REV-TASKS PASS handoff is grandfathered"
      fi
    else
      fail "tasks.md: both mandatory GateSpec Closure sections are required for a new or unsealed task plan"
    fi
    return
  fi
  if [[ "$checkpoint_exact" -ne 1 || "$prior_exact" -ne 1 ||
        "$checkpoint_candidates" -ne 1 || "$prior_candidates" -ne 1 ]]; then
    if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 3 ]]; then
      fail "tasks.md: all three Protocol v3 GateSpec Closure headings must be exact, unique, and present together"
    else
      fail "tasks.md: both legacy GateSpec Closure headings must be exact, unique, and present together"
    fi
    return
  fi
  first_phase=$(awk '/^## Phase([[:space:]]|$)/ {print NR; exit}' "$TASKS")
  if ! [[ "$first_phase" =~ ^[0-9]+$ ]]; then
    fail "tasks.md: Closure sections must precede the first ## Phase"
    return
  fi
  awk -v stop="$first_phase" 'NR < stop && /^## / {print}' "$TASKS" > "$before_phase_h2"
  third_last=$(awk 'NF {a=b; b=c; c=$0} END {print a}' "$before_phase_h2")
  second_last=$(awk 'NF {a=b; b=$0} END {print a}' "$before_phase_h2")
  last=$(awk 'NF {value=$0} END {print value}' "$before_phase_h2")
  if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 3 ]]; then
    if [[ "$third_last" != '## GateSpec Checkpoint Closure *(gatespec: mandatory)*' ||
          "$second_last" != '## GateSpec Prior Review Closure *(gatespec: mandatory)*' ||
          "$last" != '## GateSpec Test Control Closure *(gatespec: mandatory)*' ]]; then
      fail "tasks.md: Protocol v3 Closure sections must be the final three H2 sections before the first Phase, in fixed order"
      bad=1
    fi
  elif [[ "$second_last" != '## GateSpec Checkpoint Closure *(gatespec: mandatory)*' ||
          "$last" != '## GateSpec Prior Review Closure *(gatespec: mandatory)*' ]]; then
    fail "tasks.md: Closure sections must be the final two H2 sections before the first Phase, in fixed order"
    bad=1
  fi
  collect_required_closure_contracts
  check_checkpoint_closure_table
  if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 3 ]]; then
    check_test_control_closure_table
  fi
  check_prior_review_closure_table
  [[ "$bad" -eq 0 ]] && pass "tasks.md: mandatory Closure sections are exact and correctly positioned"
}

extract_retask_stable_test_control_contract() {
  local tasks_file="$1" output="$2" context="$3"
  local body="$TMP_DIR/retask-test-control-body" mode mode_lines invalid
  local header separator
  header='| Control | Verification gap / production invariant | Test-only surface | Production touchpoint | Allowed effect / lifetime | Build switch / validator | Consumer tasks/tests | Default-build proof task |'
  separator='|---|---|---|---|---|---|---|---|'
  : > "$output"
  if [[ $(grep -Fxc '## GateSpec Test Control Closure *(gatespec: mandatory)*' "$tasks_file" || true) -ne 1 ]] ||
     [[ $(grep -cE '^[[:space:]]*#{1,6}[[:space:]]+GateSpec Test Control Closure' "$tasks_file" || true) -ne 1 ]]; then
    fail "$context: archived Protocol v3 tasks require one exact Test Control Closure"
    return 1
  fi
  section_body "$tasks_file" 'GateSpec Test Control Closure' > "$body"
  mode=$(markdown_field_value "$body" 'Mode')
  mode_lines=$(markdown_field_line_numbers "$body" 'Mode')
  if [[ $(printf '%s\n' "$mode_lines" | awk 'NF {n++} END {print n+0}') -ne 1 ]] ||
     [[ "$mode" != none && "$mode" != isolated ]]; then
    fail "$context: archived Test Control Closure requires one exact Mode"
    return 1
  fi
  invalid=$(awk -v header="$header" -v separator="$separator" '
    /^[[:space:]]*$/ {next}
    !mode {
      if ($0 != "- **Mode**: `none`" && $0 != "- **Mode**: `isolated`") print NR ":" $0
      mode=1; next
    }
    !head {if ($0 != header) print NR ":" $0; head=1; next}
    !sep {if ($0 != separator) print NR ":" $0; sep=1; next}
    {
      if ($0 !~ /^\| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \| [^|[:space:]]([^|]*[^|[:space:]])? \|$/) print NR ":" $0
    }
    END {if (!mode || !head || !sep) print "missing canonical preamble"}
  ' "$body")
  if [[ -n "$invalid" ]]; then
    fail "$context: archived Test Control Closure is non-canonical"
    return 1
  fi
  printf 'Mode\t%s\n' "$mode" > "$output"
  awk -F '|' -v header="$header" -v separator="$separator" '
    /^[[:space:]]*$/ || /^- \*\*Mode\*\*:/ || $0 == header || $0 == separator {next}
    {
      for (i=2; i<=7; i++) {
        value=$i; sub(/^ /, "", value); sub(/ $/, "", value)
        printf "%s%s", (i == 2 ? "" : "\t"), value
      }
      print ""
    }
  ' "$body" >> "$output"
  if [[ $(awk 'END {print NR+0}' "$output") -lt 2 ]]; then
    fail "$context: archived Test Control Closure has no canonical row"
    return 1
  fi
}

check_retask_test_control_immutability() {
  local archive="$1" context="${1#"$FEATURE_DIR"/}"
  local current="$TMP_DIR/current-retask-test-control-stable"
  local historical="$TMP_DIR/historical-retask-test-control-stable"
  if ! extract_retask_stable_test_control_contract "$TASKS" "$current" 'tasks.md'; then
    return 1
  fi
  if ! extract_retask_stable_test_control_contract "$archive/tasks.md" "$historical" "$context/tasks.md"; then
    return 1
  fi
  if ! cmp -s "$current" "$historical"; then
    fail "tasks.md: retask archive '$context' changes immutable Test Control Mode/stable columns; retask may only rebind consumer/proof T### IDs"
    return 1
  fi
  pass "tasks.md: retask archive '$context' preserves Test Control Mode and stable columns"
}

check_historical_task_request_file() {
  local file="$1" expected_round="$2" previous_hash="$3" context protocol id round scope
  local spec_hash plan_hash attachments_hash tasks_hash source_hash epoch ia_hash handoff preserved
  local tc_mode tc_closure tc_manifest tc_default tc_explicit
  local baseline base subject task_ids changed final_delta previous previous_line tests_line hash_line
  local before="$FAILURES" expected_source
  HISTORICAL_REQUEST_BASIS_MATCH=no
  HISTORICAL_REQUEST_TASKS_HASH=''
  HISTORICAL_REQUEST_PROTOCOL=''
  HISTORICAL_REQUEST_SPEC_HASH=''
  HISTORICAL_REQUEST_PLAN_HASH=''
  HISTORICAL_REQUEST_ATTACHMENTS_HASH=''
  HISTORICAL_REQUEST_EPOCH=''
  HISTORICAL_REQUEST_SOURCE_HASH=''
  HISTORICAL_REQUEST_IA_HASH=''
  HISTORICAL_REQUEST_HANDOFF=''
  HISTORICAL_REQUEST_PRESERVED=''
  HISTORICAL_REQUEST_TC_MODE=''
  [[ -f "$file" ]] || { fail "historical REV-TASKS: request file is missing"; return 1; }
  context=${file#"$FEATURE_DIR"/}
  check_receipt_line_whitelist "$file" request "$context"
  protocol=$(markdown_field_value "$file" 'Protocol-Version')
  if [[ "$protocol" == 3 ]]; then
    check_ordered_fields "$file" "$context" \
      'Protocol-Version' 'Review-ID' 'Round' 'Scope' 'Spec-Content-SHA256' \
      'Plan-Content-SHA256' 'Design-Attachments-SHA256' 'Tasks-Definition-SHA256' \
      'Test-Control-Mode' 'Test-Control-Closure-SHA256' 'Test-Control-Subject-Manifest-SHA256' \
      'Default-OFF-Evidence-SHA256' 'Explicit-ON-Evidence-SHA256' \
      'Execution-Epoch' 'Source-Design-Content-SHA256' 'Implementation-Adjustments-SHA256' \
      'Task-Handoff-Commit' 'Preserved-Reviews-SHA256' 'Implementation-Baseline' \
      'Base-Commit' 'Subject-Commit' 'Task-IDs' 'Changed-Paths-SHA256' \
      'Final-Delta-SHA256' 'Previous-Verdict-SHA256' 'Request-SHA256'
  elif [[ "$protocol" == 2 ]]; then
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
  fi
  id=$(markdown_field_value "$file" 'Review-ID')
  round=$(markdown_field_value "$file" 'Round')
  scope=$(markdown_field_value "$file" 'Scope')
  spec_hash=$(markdown_field_value "$file" 'Spec-Content-SHA256')
  plan_hash=$(markdown_field_value "$file" 'Plan-Content-SHA256')
  attachments_hash=$(markdown_field_value "$file" 'Design-Attachments-SHA256')
  tasks_hash=$(markdown_field_value "$file" 'Tasks-Definition-SHA256')
  tc_mode=$(markdown_field_value "$file" 'Test-Control-Mode')
  tc_closure=$(markdown_field_value "$file" 'Test-Control-Closure-SHA256')
  tc_manifest=$(markdown_field_value "$file" 'Test-Control-Subject-Manifest-SHA256')
  tc_default=$(markdown_field_value "$file" 'Default-OFF-Evidence-SHA256')
  tc_explicit=$(markdown_field_value "$file" 'Explicit-ON-Evidence-SHA256')
  epoch=$(markdown_field_value "$file" 'Execution-Epoch')
  source_hash=$(markdown_field_value "$file" 'Source-Design-Content-SHA256')
  ia_hash=$(markdown_field_value "$file" 'Implementation-Adjustments-SHA256')
  handoff=$(markdown_field_value "$file" 'Task-Handoff-Commit')
  preserved=$(markdown_field_value "$file" 'Preserved-Reviews-SHA256')
  baseline=$(markdown_field_value "$file" 'Implementation-Baseline')
  base=$(markdown_field_value "$file" 'Base-Commit')
  subject=$(markdown_field_value "$file" 'Subject-Commit')
  task_ids=$(markdown_field_value "$file" 'Task-IDs')
  changed=$(markdown_field_value "$file" 'Changed-Paths-SHA256')
  final_delta=$(markdown_field_value "$file" 'Final-Delta-SHA256')
  previous=$(markdown_field_value "$file" 'Previous-Verdict-SHA256')
  case "$protocol" in 1|2|3) ;; *) fail "$context: Protocol-Version must be 1, 2, or 3" ;; esac
  [[ "$id" == REV-TASKS ]] || fail "$context: Review-ID must be REV-TASKS"
  [[ "$round" == "$expected_round" ]] || fail "$context: Round must be $expected_round"
  [[ "$scope" == TASKS ]] || fail "$context: Scope must be TASKS"
  [[ "$previous" == "$previous_hash" ]] || fail "$context: Previous-Verdict-SHA256 does not chain to the prior round"
  for digest in "$spec_hash" "$plan_hash" "$attachments_hash" "$tasks_hash"; do
    is_lower_hex64 "$digest" || { fail "$context: artifact hashes must be lowercase 64-hex"; break; }
  done
  if [[ "$baseline" != not-applicable || "$base" != not-applicable || "$subject" != not-applicable ||
        "$task_ids" != none || "$changed" != not-applicable ]]; then
    fail "$context: historical TASKS Git and Task-IDs fields must use their fixed not-applicable/none values"
  fi
  if protocol_has_execution_state "$protocol"; then
    printf '%s\n' "$epoch" | grep -Eq '^E[1-9][0-9]*$' || fail "$context: Execution-Epoch must be E<n>"
    if [[ "$source_hash" != not-applicable ]] && ! is_lower_hex64 "$source_hash"; then
      fail "$context: Source-Design-Content-SHA256 must be not-applicable or lowercase 64-hex"
    fi
    if [[ "$ia_hash" != not-applicable ]] && ! is_lower_hex64 "$ia_hash"; then
      fail "$context: Implementation-Adjustments-SHA256 must be not-applicable or lowercase 64-hex"
    fi
    is_git_oid "$handoff" || fail "$context: Task-Handoff-Commit must be a commit OID"
    if [[ "$preserved" != not-applicable ]] && ! is_lower_hex64 "$preserved"; then
      fail "$context: Preserved-Reviews-SHA256 must be not-applicable or lowercase 64-hex"
    fi
    [[ "$final_delta" == not-applicable ]] || fail "$context: TASKS Final-Delta-SHA256 must be not-applicable"
  elif [[ -n "$epoch$source_hash$ia_hash$handoff$preserved$final_delta" ]]; then
    fail "$context: Protocol v1 must not contain Protocol v2/v3 execution fields"
  fi
  if [[ "$protocol" == 3 ]]; then
    [[ "$tc_mode" == none || "$tc_mode" == isolated ]] || fail "$context: Test-Control-Mode must be none or isolated"
    is_lower_hex64 "$tc_closure" || fail "$context: Test-Control-Closure-SHA256 must be lowercase 64-hex"
    if [[ "$tc_manifest" != not-applicable || "$tc_default" != not-applicable || "$tc_explicit" != not-applicable ]]; then
      fail "$context: historical REV-TASKS Test Control subject/evidence fields must be not-applicable"
    fi
  elif [[ -n "$tc_mode$tc_closure$tc_manifest$tc_default$tc_explicit" ]]; then
    fail "$context: Protocol v1/v2 must not contain Protocol v3 Test Control fields"
  fi
  check_request_tests "$file" TASKS "$context" REV-TASKS
  check_self_hash "$file" 'Request-SHA256' "$context"
  HISTORICAL_REQUEST_TASKS_HASH=$tasks_hash
  HISTORICAL_REQUEST_PROTOCOL=$protocol
  HISTORICAL_REQUEST_SPEC_HASH=$spec_hash
  HISTORICAL_REQUEST_PLAN_HASH=$plan_hash
  HISTORICAL_REQUEST_ATTACHMENTS_HASH=$attachments_hash
  HISTORICAL_REQUEST_EPOCH=$epoch
  HISTORICAL_REQUEST_SOURCE_HASH=$source_hash
  HISTORICAL_REQUEST_IA_HASH=$ia_hash
  HISTORICAL_REQUEST_HANDOFF=$handoff
  HISTORICAL_REQUEST_PRESERVED=$preserved
  HISTORICAL_REQUEST_TC_MODE=$tc_mode
  if [[ -f "$SOURCE_ENTRY" ]]; then expected_source=$(source_design_content_hash) || expected_source=''
  else expected_source=not-applicable; fi
  if [[ "$spec_hash" == "$CURRENT_SPEC_HASH" && "$plan_hash" == "$CURRENT_PLAN_HASH" &&
        "$attachments_hash" == "$CURRENT_ATTACHMENTS_HASH" ]]; then
    if [[ -f "$SOURCE_ENTRY" ]]; then
      protocol_has_execution_state "$protocol" && [[ "$source_hash" == "$expected_source" ]] && HISTORICAL_REQUEST_BASIS_MATCH=yes
    elif [[ "$protocol" == 1 || "$source_hash" == not-applicable ]]; then
      HISTORICAL_REQUEST_BASIS_MATCH=yes
    fi
  fi
  [[ "$FAILURES" -eq "$before" ]]
}

append_blocker_findings() {
  local verdict="$1" relative="$2" archive_root="$3" body="$TMP_DIR/historical-blocker-body"
  local prefix count i=1 item digest ordinal
  HISTORICAL_FINDING_SERIAL=$(( ${HISTORICAL_FINDING_SERIAL:-0} + 1 ))
  prefix="$TMP_DIR/finding-${HISTORICAL_FINDING_SERIAL}"
  receipt_section_body "$verdict" 'Blockers' 'Verdict-SHA256' > "$body"
  count=$(awk -v prefix="$prefix" '
    function flush_blanks(    j) {
      for (j=0; j<pending_blanks; j++) printf "\n" >> file
      pending_blanks=0
    }
    /^- BLOCKER:[[:space:]]+/ {
      count++
      active=1
      pending_blanks=0
      file=sprintf("%s-%02d", prefix, count)
      printf "%s\n", $0 > file
      next
    }
    active && /^[[:space:]]*$/ {pending_blanks++; next}
    active && /^[[:space:]]+[^[:space:]]/ {
      flush_blanks()
      printf "%s\n", $0 >> file
      next
    }
    /^- / || /^## / || /^[^[:space:]]/ {active=0; pending_blanks=0; next}
    END {print count+0}
  ' "$body")
  while [[ "$i" -le "$count" ]]; do
    printf -v item '%s-%02d' "$prefix" "$i"
    digest=$(file_hash "$item") || digest=''
    printf -v ordinal 'B%02d' "$i"
    printf '%s\t%s#%s\t%s\n' "$digest" "$relative" "$ordinal" "$archive_root" \
      >> "$TMP_DIR/required-prior-findings"
    i=$((i + 1))
  done
}

git_tree_blob_manifest_hash() {
  local commit="$1" kind="$2"
  local tree="$TMP_DIR/git-tree-$kind"
  local manifest="$TMP_DIR/git-tree-$kind-manifest" meta path mode type oid rel digest tail
  local source_entry='' saw_source_shard=0
  : > "$manifest"
  git -C "$GIT_ROOT" ls-tree -r "$commit" -- "$GIT_FEATURE_REL" > "$tree" 2>/dev/null || return 1
  while IFS=$'\t' read -r meta path; do
    [[ -n "$path" ]] || continue
    mode=$(printf '%s\n' "$meta" | awk '{print $1}')
    type=$(printf '%s\n' "$meta" | awk '{print $2}')
    oid=$(printf '%s\n' "$meta" | awk '{print $3}')
    [[ "$type" == blob && "$mode" =~ ^100(644|755)$ ]] || continue
    rel=${path#"$GIT_FEATURE_REL"/}
    case "$kind" in
      attachments)
        case "$rel" in
          research.md|data-model.md|quickstart.md) ;;
          contracts/source-design.md|contracts/source-design/*) continue ;;
          contracts/*) ;;
          *) continue ;;
        esac
        digest=$(git -C "$GIT_ROOT" cat-file blob "$oid" 2>/dev/null | portable_sha256 | awk '{print $1}') || return 1
        printf '%s\t%s\n' "$rel" "$digest" >> "$manifest"
        ;;
      source)
        case "$rel" in
          contracts/source-design.md)
            git -C "$GIT_ROOT" cat-file blob "$oid" > "$TMP_DIR/git-tree-source-entry" 2>/dev/null || return 1
            digest=$(sed '/^## Gate Approval/,$d' "$TMP_DIR/git-tree-source-entry" | portable_sha256 | awk '{print $1}')
            printf '%s\t%s\n' "$rel" "$digest" >> "$manifest"
            source_entry=yes
            ;;
          contracts/source-design/*.md)
            tail=${rel#contracts/source-design/}
            [[ "$tail" != */* ]] || continue
            digest=$(git -C "$GIT_ROOT" cat-file blob "$oid" 2>/dev/null | portable_sha256 | awk '{print $1}') || return 1
            printf '%s\t%s\n' "$rel" "$digest" >> "$manifest"
            saw_source_shard=1
            ;;
        esac
        ;;
      preserved)
        case "$rel" in .gatespec/revalidations/*) ;; *) continue ;; esac
        digest=$(git -C "$GIT_ROOT" cat-file blob "$oid" 2>/dev/null | portable_sha256 | awk '{print $1}') || return 1
        printf '%s\t%s\n' "$rel" "$digest" >> "$manifest"
        ;;
      *) return 1 ;;
    esac
  done < "$tree"
  if [[ "$kind" == source ]]; then
    if [[ -z "$source_entry" ]]; then
      [[ "$saw_source_shard" -eq 0 ]] || return 1
      printf '%s' 'not-applicable'
      return
    fi
  elif [[ "$kind" == preserved && ! -s "$manifest" ]]; then
    printf '%s' 'not-applicable'
    return
  fi
  LC_ALL=C sort "$manifest" | portable_sha256 | awk '{print $1}'
}

check_archived_v2_handoff() {
  local root="$1" review="$root/reviews/REV-TASKS" round00="$root/reviews/REV-TASKS/round-00-request.md"
  local context="${root#"$FEATURE_DIR"/}" handoff original epoch source ia_hash preserved protocol
  local parents spec_blob="$TMP_DIR/archive-handoff-spec" plan_blob="$TMP_DIR/archive-handoff-plan"
  local tasks_blob="$TMP_DIR/archive-handoff-tasks" state_blob="$TMP_DIR/archive-handoff-state"
  local ia_blob="$TMP_DIR/archive-handoff-ia" invalid actual_attachments actual_source actual_preserved bad=0
  handoff=$(markdown_field_value "$round00" 'Task-Handoff-Commit')
  original=$(markdown_field_value "$root/execution-state.md" 'Original-Implementation-Baseline')
  epoch=$(markdown_field_value "$round00" 'Execution-Epoch')
  source=$(markdown_field_value "$round00" 'Source-Design-Content-SHA256')
  ia_hash=$(markdown_field_value "$round00" 'Implementation-Adjustments-SHA256')
  preserved=$(markdown_field_value "$round00" 'Preserved-Reviews-SHA256')
  protocol=$(markdown_field_value "$round00" 'Protocol-Version')
  if [[ -z "$GIT_ROOT" ]] || ! resolve_git_feature_paths || ! is_git_oid "$handoff" ||
     ! git -C "$GIT_ROOT" cat-file -e "${handoff}^{commit}" 2>/dev/null; then
    fail "tasks.md: $context archived Task-Handoff-Commit must resolve to a commit"
    return
  fi
  parents=$(git -C "$GIT_ROOT" rev-list --parents -n 1 "$handoff" 2>/dev/null || true)
  [[ $(printf '%s\n' "$parents" | awk '{print NF+0}') -eq 2 ]] || {
    fail "tasks.md: $context archived Task-Handoff-Commit must have one parent"; bad=1;
  }
  if ! is_git_oid "$original" ||
     ! git -C "$GIT_ROOT" merge-base --is-ancestor "$original" "$handoff" 2>/dev/null ||
     ! git -C "$GIT_ROOT" merge-base --is-ancestor "$handoff" HEAD 2>/dev/null; then
    fail "tasks.md: $context archived Original→Task-Handoff→HEAD ancestry is invalid"
    bad=1
  fi
  if ! git -C "$GIT_ROOT" show "$handoff:$GIT_FEATURE_REL/spec.md" > "$spec_blob" 2>/dev/null ||
     [[ $(content_hash "$spec_blob") != $(markdown_field_value "$round00" 'Spec-Content-SHA256') ]]; then
    fail "tasks.md: $context archived Task-Handoff spec snapshot is stale"
    bad=1
  fi
  if ! git -C "$GIT_ROOT" show "$handoff:$GIT_FEATURE_REL/plan.md" > "$plan_blob" 2>/dev/null ||
     [[ $(content_hash "$plan_blob") != $(markdown_field_value "$round00" 'Plan-Content-SHA256') ]]; then
    fail "tasks.md: $context archived Task-Handoff plan snapshot is stale"
    bad=1
  fi
  if ! git -C "$GIT_ROOT" show "$handoff:$GIT_FEATURE_REL/tasks.md" > "$tasks_blob" 2>/dev/null ||
     [[ $(normalized_tasks_hash "$tasks_blob") != $(markdown_field_value "$round00" 'Tasks-Definition-SHA256') ]]; then
    fail "tasks.md: $context archived Task-Handoff tasks snapshot does not bind round 00"
    bad=1
  fi
  if [[ -f "$tasks_blob" ]] && grep -Eq '^- \[[xX]\] T[0-9][0-9][0-9]([[:space:]]|$)' "$tasks_blob"; then
    fail "tasks.md: $context archived Task-Handoff tasks snapshot contains completed task evidence"
    bad=1
  fi
  actual_attachments=$(git_tree_blob_manifest_hash "$handoff" attachments) || actual_attachments=''
  [[ "$actual_attachments" == $(markdown_field_value "$round00" 'Design-Attachments-SHA256') ]] || {
    fail "tasks.md: $context archived Task-Handoff Design Attachments snapshot is stale"; bad=1;
  }
  actual_source=$(git_tree_blob_manifest_hash "$handoff" source) || actual_source=''
  [[ "$actual_source" == "$source" ]] || {
    fail "tasks.md: $context archived Task-Handoff Source snapshot is stale"; bad=1;
  }
  actual_preserved=$(git_tree_blob_manifest_hash "$handoff" preserved) || actual_preserved=''
  [[ "$actual_preserved" == "$preserved" ]] || {
    fail "tasks.md: $context archived Task-Handoff preserved-review manifest is stale"; bad=1;
  }
  if ! git -C "$GIT_ROOT" show "$handoff:$GIT_FEATURE_REL/.gatespec/execution-state.md" \
      > "$state_blob" 2>/dev/null; then
    fail "tasks.md: $context archived Task-Handoff is missing pending execution state"
    bad=1
  else
    invalid=$(awk '
      /^[[:space:]]*$/ {next}
      NR == 1 && $0 == "# GateSpec Execution State" {next}
      /^- \*\*(Protocol-Version|Execution-Epoch|Original-Implementation-Baseline|Task-Handoff-Commit|Source-Design-Content-SHA256|Preserved-Reviews-SHA256|Execution-State-SHA256)\*\*: `[^`]+`$/ {next}
      {print}
    ' "$state_blob")
    [[ -z "$invalid" && $(sed -n '1p' "$state_blob") == '# GateSpec Execution State' ]] || {
      fail "tasks.md: $context archived pending execution state is non-canonical"; bad=1;
    }
    check_ordered_fields "$state_blob" "$context archived pending execution state" \
      'Protocol-Version' 'Execution-Epoch' 'Original-Implementation-Baseline' 'Task-Handoff-Commit' \
      'Source-Design-Content-SHA256' 'Preserved-Reviews-SHA256' 'Execution-State-SHA256'
    [[ $(markdown_field_value "$state_blob" 'Protocol-Version') == "$protocol" &&
       $(markdown_field_value "$state_blob" 'Execution-Epoch') == "$epoch" &&
       $(markdown_field_value "$state_blob" 'Original-Implementation-Baseline') == "$original" &&
       $(markdown_field_value "$state_blob" 'Task-Handoff-Commit') == pending &&
       $(markdown_field_value "$state_blob" 'Source-Design-Content-SHA256') == "$source" &&
       $(markdown_field_value "$state_blob" 'Preserved-Reviews-SHA256') == "$preserved" ]] || {
      fail "tasks.md: $context archived pending execution state does not bind round 00"; bad=1;
    }
    check_self_hash "$state_blob" 'Execution-State-SHA256' "$context archived pending execution state"
  fi
  if [[ "$source" == not-applicable ]]; then
    [[ "$ia_hash" == not-applicable ]] || { fail "tasks.md: $context archived no-Source IA must be not-applicable"; bad=1; }
    if git -C "$GIT_ROOT" cat-file -e "$handoff:$GIT_FEATURE_REL/.gatespec/implementation-adjustments.md" 2>/dev/null; then
      fail "tasks.md: $context archived no-Source Task-Handoff contains IA"
      bad=1
    fi
  elif ! git -C "$GIT_ROOT" show "$handoff:$GIT_FEATURE_REL/.gatespec/implementation-adjustments.md" \
      > "$ia_blob" 2>/dev/null; then
    fail "tasks.md: $context archived Task-Handoff is missing empty IA"
    bad=1
  else
    check_canonical_empty_ia "$ia_blob" "$context archived Task-Handoff IA" "$epoch" "$source" || bad=1
    [[ $(file_hash "$ia_blob") == "$ia_hash" ]] || {
      fail "tasks.md: $context archived Task-Handoff IA does not bind round 00"; bad=1;
    }
  fi
  [[ "$bad" -eq 0 ]] && pass "tasks.md: $context archived v2/v3 Task-Handoff snapshot is reproducible"
}

append_contributing_archive_manifest() {
  local root="$1" review file rel protocol source_hash tasks_hash latest_request
  local archive_tc_hash archive_stable archive_mode archive_declared latest_verdict
  local request_mode verdict_mode verdict_declared
  local git_rel state_invalid state_epoch state_original state_source state_handoff state_preserved
  review="$root/reviews/REV-TASKS"
  [[ -n "$root" ]] || return 0
  if [[ ! -f "$root/tasks.md" ]]; then
    fail "tasks.md: contributing retask archive '${root#"$FEATURE_DIR"/}' is missing tasks.md"
    return 1
  fi
  printf '%s\n' "$root" >> "$TMP_DIR/prior-closure-contributing-archives"
  git_rel="${root#"$FEATURE_DIR"/}/tasks.md"
  [[ -n "${GIT_FEATURE_REL:-}" ]] && git_rel="$GIT_FEATURE_REL/$git_rel"
  printf '%s\t%s\n' "$git_rel" "$root/tasks.md" \
    >> "$TMP_DIR/prior-closure-archive-files"
  while IFS= read -r file; do
    [[ -f "$file" ]] || continue
    rel=${file#"$FEATURE_DIR"/}
    git_rel=$rel
    [[ -n "${GIT_FEATURE_REL:-}" ]] && git_rel="$GIT_FEATURE_REL/$git_rel"
    printf '%s\t%s\n' "$git_rel" "$file" >> "$TMP_DIR/prior-closure-archive-files"
  done < <(find "$review" -maxdepth 1 -type f -print)
  latest_request=$(find "$review" -maxdepth 1 -type f -name 'round-*-request.md' -print | LC_ALL=C sort | tail -1)
  protocol=$(markdown_field_value "$latest_request" 'Protocol-Version')
  tasks_hash=$(markdown_field_value "$latest_request" 'Tasks-Definition-SHA256')
  if [[ "$tasks_hash" != $(normalized_tasks_hash "$root/tasks.md") ]]; then
    fail "tasks.md: contributing retask archive tasks.md does not match its terminal REV-TASKS request"
  fi
  if [[ "$protocol" == 3 ]]; then
    archive_tc_hash=$(test_control_closure_hash_for_file "$root/tasks.md") || archive_tc_hash=''
    if [[ "$archive_tc_hash" != $(markdown_field_value "$latest_request" 'Test-Control-Closure-SHA256') ]]; then
      fail "tasks.md: contributing retask archive Test Control Closure does not match its terminal REV-TASKS request"
    fi
    archive_stable="$TMP_DIR/contributing-archive-test-control-stable"
    if extract_retask_stable_test_control_contract "$root/tasks.md" "$archive_stable" \
      "${root#"$FEATURE_DIR"/}/tasks.md"; then
      archive_mode=$(awk -F '\t' 'NR == 1 {print $2}' "$archive_stable")
      if [[ "$archive_mode" == none ]]; then
        archive_declared=none
      else
        archive_declared=$(awk -F '\t' 'NR > 1 {
          value=value separator $1; separator=", "
        } END {print value}' "$archive_stable")
      fi
      latest_verdict=${latest_request%-request.md}-verdict.md
      request_mode=$(markdown_field_value "$latest_request" 'Test-Control-Mode')
      verdict_mode=$(markdown_field_value "$latest_verdict" 'Mode')
      verdict_declared=$(markdown_field_value "$latest_verdict" 'Declared-Controls')
      if [[ "$request_mode" != "$archive_mode" || "$verdict_mode" != "$archive_mode" ||
            "$verdict_declared" != "$archive_declared" ]]; then
        fail "tasks.md: contributing retask archive terminal request/Audit must exactly bind archived Test Control Mode and declared IDs"
      fi
    fi
  fi
  if grep -Eq '^- \[[xX]\] T[0-9][0-9][0-9]([[:space:]]|$)' "$root/tasks.md"; then
    fail "tasks.md: retask archive contains completed task evidence"
  fi
  if protocol_has_execution_state "$protocol"; then
    if [[ ! -f "$root/execution-state.md" ]]; then
      fail "tasks.md: contributing Protocol v2/v3 retask archive is missing execution-state.md"
    else
      state_invalid=$(awk '
        /^[[:space:]]*$/ {next}
        NR == 1 && $0 == "# GateSpec Execution State" {next}
        /^- \*\*(Protocol-Version|Execution-Epoch|Original-Implementation-Baseline|Task-Handoff-Commit|Source-Design-Content-SHA256|Preserved-Reviews-SHA256|Execution-State-SHA256)\*\*: `[^`]+`$/ {next}
        {print NR ":" $0}
      ' "$root/execution-state.md")
      [[ -z "$state_invalid" ]] || fail "tasks.md: contributing retask archive execution state has non-canonical content"
      [[ $(sed -n '1p' "$root/execution-state.md") == '# GateSpec Execution State' &&
         $(grep -cFx '# GateSpec Execution State' "$root/execution-state.md" || true) -eq 1 ]] ||
        fail "tasks.md: contributing retask archive execution state requires its exact line-1 title"
      check_ordered_fields "$root/execution-state.md" "${root#"$FEATURE_DIR"/}/execution-state.md" \
        'Protocol-Version' 'Execution-Epoch' 'Original-Implementation-Baseline' 'Task-Handoff-Commit' \
        'Source-Design-Content-SHA256' 'Preserved-Reviews-SHA256' 'Execution-State-SHA256'
      [[ $(markdown_field_value "$root/execution-state.md" 'Protocol-Version') == "$protocol" ]] ||
        fail "tasks.md: contributing retask archive execution state must match its receipt protocol"
      state_epoch=$(markdown_field_value "$root/execution-state.md" 'Execution-Epoch')
      state_original=$(markdown_field_value "$root/execution-state.md" 'Original-Implementation-Baseline')
      state_source=$(markdown_field_value "$root/execution-state.md" 'Source-Design-Content-SHA256')
      state_handoff=$(markdown_field_value "$root/execution-state.md" 'Task-Handoff-Commit')
      state_preserved=$(markdown_field_value "$root/execution-state.md" 'Preserved-Reviews-SHA256')
      if [[ "$state_epoch" != $(markdown_field_value "$latest_request" 'Execution-Epoch') ||
            "$state_source" != $(markdown_field_value "$latest_request" 'Source-Design-Content-SHA256') ||
            "$state_handoff" != $(markdown_field_value "$latest_request" 'Task-Handoff-Commit') ||
            "$state_preserved" != $(markdown_field_value "$latest_request" 'Preserved-Reviews-SHA256') ]]; then
        fail "tasks.md: contributing retask archive execution state does not bind its terminal request"
      fi
      is_git_oid "$state_original" ||
        fail "tasks.md: contributing retask archive Original-Implementation-Baseline must be a commit OID"
      check_self_hash "$root/execution-state.md" 'Execution-State-SHA256' \
        "${root#"$FEATURE_DIR"/}/execution-state.md"
      git_rel="${root#"$FEATURE_DIR"/}/execution-state.md"
      [[ -n "${GIT_FEATURE_REL:-}" ]] && git_rel="$GIT_FEATURE_REL/$git_rel"
      printf '%s\t%s\n' "$git_rel" "$root/execution-state.md" \
        >> "$TMP_DIR/prior-closure-archive-files"
    fi
    [[ -f "$root/execution-state.md" ]] && check_archived_v2_handoff "$root"
    source_hash=$(markdown_field_value "$latest_request" 'Source-Design-Content-SHA256')
    if [[ "$source_hash" != not-applicable ]]; then
      if [[ ! -f "$root/implementation-adjustments.md" ]]; then
        fail "tasks.md: contributing Source Protocol v2/v3 retask archive is missing implementation-adjustments.md"
      else
        if [[ $(file_hash "$root/implementation-adjustments.md") != \
              $(markdown_field_value "$latest_request" 'Implementation-Adjustments-SHA256') ]]; then
          fail "tasks.md: contributing retask archive IA does not match its terminal REV-TASKS request"
        fi
        check_canonical_empty_ia "$root/implementation-adjustments.md" \
          "${root#"$FEATURE_DIR"/}/implementation-adjustments.md" \
          "$(markdown_field_value "$latest_request" 'Execution-Epoch')" "$source_hash" || true
        git_rel="${root#"$FEATURE_DIR"/}/implementation-adjustments.md"
        [[ -n "${GIT_FEATURE_REL:-}" ]] && git_rel="$GIT_FEATURE_REL/$git_rel"
        printf '%s\t%s\n' "$git_rel" \
          "$root/implementation-adjustments.md" >> "$TMP_DIR/prior-closure-archive-files"
      fi
    elif [[ -e "$root/implementation-adjustments.md" ]]; then
      fail "tasks.md: no-Source retask archive must not contain implementation-adjustments.md"
    fi
  elif [[ -e "$root/execution-state.md" || -e "$root/implementation-adjustments.md" ]]; then
    fail "tasks.md: Protocol v1 retask archive must not contain Protocol v2/v3 execution state or IA"
  fi
}

check_historical_task_chain() {
  local directory="$1" archive_root="$2" context=${1#"$FEATURE_DIR"/}
  local i=0 round request verdict request_hash status previous=none previous_tasks='' current_tasks
  local previous_status='' seal="$directory/seal.md" seal_round invalid gap=0 terminal_round='' terminal_status=''
  local chain_basis=yes before="$FAILURES" chain_protocol='' current_protocol
  local current_spec current_plan current_attachments current_epoch current_source current_ia current_handoff current_preserved
  local previous_spec='' previous_plan='' previous_attachments='' previous_epoch='' previous_source=''
  local previous_ia='' previous_handoff='' previous_preserved=''
  HISTORICAL_CHAIN_TERMINAL_ROUND=''
  HISTORICAL_CHAIN_TERMINAL_STATUS=''
  HISTORICAL_CHAIN_BASIS_MATCH=no
  HISTORICAL_CHAIN_PROTOCOL=''
  HISTORICAL_CHAIN_TERMINAL_TASKS_HASH=''
  HISTORICAL_CHAIN_TERMINAL_EPOCH=''
  HISTORICAL_CHAIN_TERMINAL_SOURCE_HASH=''
  HISTORICAL_CHAIN_TERMINAL_IA_HASH=''
  HISTORICAL_CHAIN_TERMINAL_HANDOFF=''
  HISTORICAL_CHAIN_TERMINAL_PRESERVED=''
  if [[ ! -d "$directory" || -L "$directory" ]]; then
    fail "$context: historical review root must be a regular directory"
    return 1
  fi
  invalid=$(find "$directory" -mindepth 1 -maxdepth 1 -print | while IFS= read -r file; do
    rel=${file##*/}
    if [[ ! -f "$file" || -L "$file" ]] ||
       ! printf '%s\n' "$rel" | grep -Eq '^(round-(00|01|02)-(request|verdict)\.md|seal\.md)$'; then
      printf '%s\n' "$rel"
    fi
  done)
  [[ -z "$invalid" ]] || fail "$context: historical chain contains non-canonical receipt files"
  while [[ "$i" -le 2 ]]; do
    printf -v round '%02d' "$i"
    request="$directory/round-${round}-request.md"
    verdict="$directory/round-${round}-verdict.md"
    if [[ -e "$request" || -e "$verdict" ]]; then
      if [[ "$gap" -eq 1 || ! -f "$request" || ! -f "$verdict" ]]; then
        fail "$context: historical rounds must be contiguous request/verdict pairs from round 00"
        gap=1
        i=$((i + 1))
        continue
      fi
      if ! check_historical_task_request_file "$request" "$round" "$previous"; then :; fi
      [[ "$HISTORICAL_REQUEST_BASIS_MATCH" == yes ]] || chain_basis=no
      current_tasks=$HISTORICAL_REQUEST_TASKS_HASH
      current_protocol=$HISTORICAL_REQUEST_PROTOCOL
      current_spec=$HISTORICAL_REQUEST_SPEC_HASH
      current_plan=$HISTORICAL_REQUEST_PLAN_HASH
      current_attachments=$HISTORICAL_REQUEST_ATTACHMENTS_HASH
      current_epoch=$HISTORICAL_REQUEST_EPOCH
      current_source=$HISTORICAL_REQUEST_SOURCE_HASH
      current_ia=$HISTORICAL_REQUEST_IA_HASH
      current_handoff=$HISTORICAL_REQUEST_HANDOFF
      current_preserved=$HISTORICAL_REQUEST_PRESERVED
      if [[ -z "$chain_protocol" ]]; then chain_protocol=$current_protocol
      elif [[ "$current_protocol" != "$chain_protocol" ]]; then fail "$context: Protocol-Version must remain fixed across rounds"; fi
      if [[ "$i" -gt 0 ]]; then
        [[ "$previous_status" == BLOCKED ]] || fail "$context: every nonterminal prior round must be BLOCKED"
        [[ "$current_tasks" != "$previous_tasks" ]] || fail "$context: task remediation must change Tasks-Definition-SHA256"
        if [[ "$current_spec" != "$previous_spec" || "$current_plan" != "$previous_plan" ||
              "$current_attachments" != "$previous_attachments" ]]; then
          fail "$context: task remediation must retain Spec, Plan, and Design-Attachments hashes"
        fi
        if protocol_has_execution_state "$current_protocol" &&
           [[ "$current_epoch" != "$previous_epoch" || "$current_source" != "$previous_source" ||
              "$current_ia" != "$previous_ia" || "$current_handoff" != "$previous_handoff" ||
              "$current_preserved" != "$previous_preserved" ]]; then
          fail "$context: Protocol v2/v3 task remediation must retain epoch, Source, IA, handoff, and preserved-review bindings"
        fi
      fi
      request_hash=$(markdown_field_value "$request" 'Request-SHA256')
      HISTORICAL_TASK_AUDIT=yes
      check_verdict_file "$verdict" REV-TASKS "$round" "$request_hash" TASKS "$current_protocol"
      HISTORICAL_TASK_AUDIT=no
      status=$CHECKED_VERDICT_STATUS
      if [[ "$status" == BLOCKED && "$HISTORICAL_REQUEST_BASIS_MATCH" == yes ]] &&
         ! [[ "$MODE" == retask-eligible && "${TASKS_CLOSURE_POLICY:-required}" == optional &&
               -z "$archive_root" && "$round" == 02 && ! -f "$seal" ]]; then
        append_blocker_findings "$verdict" "${verdict#"$FEATURE_DIR"/}" "$archive_root"
      fi
      previous=$CHECKED_VERDICT_HASH
      previous_status=$status
      previous_tasks=$current_tasks
      previous_spec=$current_spec
      previous_plan=$current_plan
      previous_attachments=$current_attachments
      previous_epoch=$current_epoch
      previous_source=$current_source
      previous_ia=$current_ia
      previous_handoff=$current_handoff
      previous_preserved=$current_preserved
      terminal_round=$round
      terminal_status=$status
    else
      gap=1
    fi
    i=$((i + 1))
  done
  if [[ -z "$terminal_round" ]]; then
    fail "$context: historical review directory has no complete round"
    return 1
  fi
  if [[ -f "$seal" ]]; then
    seal_round=$(markdown_field_value "$seal" 'Round')
    if [[ "$seal_round" != "$terminal_round" || "$terminal_status" != PASS ]]; then
      fail "$context: historical seal must bind its terminal PASS round"
    else
      check_seal_file "$seal" "$directory/round-${terminal_round}-request.md" \
        "$directory/round-${terminal_round}-verdict.md" REV-TASKS "$terminal_round"
    fi
  elif [[ "$terminal_status" != BLOCKED ]]; then
    fail "$context: unsealed historical chain must end in BLOCKED"
  fi
  HISTORICAL_CHAIN_TERMINAL_ROUND=$terminal_round
  HISTORICAL_CHAIN_TERMINAL_STATUS=$terminal_status
  HISTORICAL_CHAIN_BASIS_MATCH=$chain_basis
  HISTORICAL_CHAIN_PROTOCOL=$chain_protocol
  HISTORICAL_CHAIN_TERMINAL_TASKS_HASH=$current_tasks
  HISTORICAL_CHAIN_TERMINAL_EPOCH=$current_epoch
  HISTORICAL_CHAIN_TERMINAL_SOURCE_HASH=$current_source
  HISTORICAL_CHAIN_TERMINAL_IA_HASH=$current_ia
  HISTORICAL_CHAIN_TERMINAL_HANDOFF=$current_handoff
  HISTORICAL_CHAIN_TERMINAL_PRESERVED=$current_preserved
  [[ "$FAILURES" -eq "$before" ]]
}

collect_prior_review_findings() {
  local archive archive_name archive_entry archive_rel archive_invalid review
  : > "$TMP_DIR/required-prior-findings"
  : > "$TMP_DIR/prior-closure-contributing-archives"
  : > "$TMP_DIR/prior-closure-archive-files"
  HISTORICAL_FINDING_SERIAL=0
  initialize_review_hashes
  if [[ -n "$GIT_ROOT" ]]; then
    resolve_git_feature_paths || true
  fi
  review="$FEATURE_DIR/.gatespec/reviews/REV-TASKS"
  if [[ -e "$review" || -L "$review" ]]; then
    if [[ ! -d "$review" || -L "$review" ]]; then
      fail "tasks.md: current REV-TASKS review root must be a regular directory"
    elif find "$review" -mindepth 1 -maxdepth 1 -print -quit | grep -q .; then
      check_historical_task_chain "$review" ''
    fi
  fi
  if [[ -e "$FEATURE_DIR/.gatespec" || -L "$FEATURE_DIR/.gatespec" ]] &&
     [[ ! -d "$FEATURE_DIR/.gatespec" || -L "$FEATURE_DIR/.gatespec" ]]; then
    fail "tasks.md: an existing .gatespec root must be a regular non-symlink directory"
  elif [[ -e "$FEATURE_DIR/.gatespec/archive" || -L "$FEATURE_DIR/.gatespec/archive" ]] &&
       [[ ! -d "$FEATURE_DIR/.gatespec/archive" || -L "$FEATURE_DIR/.gatespec/archive" ]]; then
    fail "tasks.md: an existing archive root must be a regular non-symlink directory"
  elif [[ -d "$FEATURE_DIR/.gatespec/archive" ]]; then
    while IFS= read -r archive; do
      archive_name=${archive##*/}
      if ! printf '%s\n' "$archive_name" | grep -Eq '^[0-9]{8}T[0-9]{6}Z-retask$'; then
        fail "tasks.md: retask archive '$archive_name' must use the exact UTC timestamp name"
      fi
      if [[ ! -d "$archive" || -L "$archive" ]]; then
        fail "tasks.md: retask archive '${archive#"$FEATURE_DIR"/}' must be a regular directory"
        continue
      fi
      archive_invalid=''
      while IFS= read -r archive_entry; do
        archive_rel=${archive_entry#"$archive"/}
        case "$archive_rel" in
          tasks.md|execution-state.md|implementation-adjustments.md)
            [[ -f "$archive_entry" && ! -L "$archive_entry" ]] || archive_invalid=$archive_rel
            ;;
          reviews|reviews/REV-TASKS)
            [[ -d "$archive_entry" && ! -L "$archive_entry" ]] || archive_invalid=$archive_rel
            ;;
          reviews/REV-TASKS/round-00-request.md|reviews/REV-TASKS/round-00-verdict.md|\
          reviews/REV-TASKS/round-01-request.md|reviews/REV-TASKS/round-01-verdict.md|\
          reviews/REV-TASKS/round-02-request.md|reviews/REV-TASKS/round-02-verdict.md|\
          reviews/REV-TASKS/seal.md)
            [[ -f "$archive_entry" && ! -L "$archive_entry" ]] || archive_invalid=$archive_rel
            ;;
          *) archive_invalid=$archive_rel ;;
        esac
        [[ -z "$archive_invalid" ]] || break
      done < <(find "$archive" -mindepth 1 -print)
      if [[ -n "$archive_invalid" ]]; then
        fail "tasks.md: retask archive '${archive#"$FEATURE_DIR"/}' contains unknown or non-regular entry '$archive_invalid'"
        continue
      fi
      if [[ ! -f "$archive/tasks.md" || -L "$archive/tasks.md" ]]; then
        fail "tasks.md: retask archive '${archive#"$FEATURE_DIR"/}' is missing regular non-symlink tasks.md"
      fi
      if [[ ! -d "$archive/reviews/REV-TASKS" || -L "$archive/reviews" ||
            -L "$archive/reviews/REV-TASKS" ]]; then
        fail "tasks.md: retask archive '${archive#"$FEATURE_DIR"/}' is missing its regular REV-TASKS review directory"
        continue
      fi
      check_historical_task_chain "$archive/reviews/REV-TASKS" "$archive"
      if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 1 ]] && protocol_has_execution_state "$HISTORICAL_CHAIN_PROTOCOL"; then
        fail "tasks.md: legacy Protocol v1 cannot follow a Protocol v2/v3 retask archive"
      fi
      if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 3 && "$HISTORICAL_CHAIN_BASIS_MATCH" == yes ]]; then
        if [[ "$HISTORICAL_CHAIN_PROTOCOL" != 3 ]]; then
          fail "tasks.md: a basis-matching Protocol v3 retask archive must itself use Protocol v3"
        else
          check_retask_test_control_immutability "$archive" || true
        fi
      fi
      append_contributing_archive_manifest "$archive"
      if protocol_has_execution_state "$HISTORICAL_CHAIN_PROTOCOL"; then
        [[ -f "$archive/execution-state.md" && ! -L "$archive/execution-state.md" ]] ||
          fail "tasks.md: Protocol v2/v3 retask archive '${archive#"$FEATURE_DIR"/}' requires regular execution-state.md"
        if [[ "$HISTORICAL_CHAIN_TERMINAL_SOURCE_HASH" != not-applicable ]]; then
          [[ -f "$archive/implementation-adjustments.md" && ! -L "$archive/implementation-adjustments.md" ]] ||
            fail "tasks.md: Source Protocol v2/v3 retask archive '${archive#"$FEATURE_DIR"/}' requires regular implementation-adjustments.md"
        elif [[ -e "$archive/implementation-adjustments.md" || -L "$archive/implementation-adjustments.md" ]]; then
          fail "tasks.md: no-Source Protocol v2/v3 retask archive '${archive#"$FEATURE_DIR"/}' must not contain implementation-adjustments.md"
        fi
      elif [[ "$HISTORICAL_CHAIN_PROTOCOL" == 1 ]] &&
           [[ -e "$archive/execution-state.md" || -L "$archive/execution-state.md" ||
              -e "$archive/implementation-adjustments.md" || -L "$archive/implementation-adjustments.md" ]]; then
        fail "tasks.md: v1 retask archive '${archive#"$FEATURE_DIR"/}' must not contain Protocol v2/v3 state or IA"
      fi
    done < <(find "$FEATURE_DIR/.gatespec/archive" -mindepth 1 -maxdepth 1 -name '*-retask' -print | LC_ALL=C sort)
  fi
}

check_v2_execution_history_continuity() {
  local state_rel="$GIT_FEATURE_REL/.gatespec/execution-state.md"
  local commits="$TMP_DIR/retask-state-history-commits" blob="$TMP_DIR/retask-state-history-blob"
  local history_epochs="$TMP_DIR/retask-state-history-epochs"
  local commit epoch original number previous_number=0 anchor_original='' seen=0
  local current_number archive archive_state archive_epoch archive_original archive_number
  local previous_archive_number=0 bad=0
  if ! printf '%s\n' "${CURRENT_EXECUTION_EPOCH:-}" | grep -Eq '^E[1-9][0-9]*$' ||
     ! is_git_oid "${CURRENT_ORIGINAL_BASELINE:-}"; then
    fail "retask eligibility: cannot audit history from an invalid current epoch or Original Baseline"
    return
  fi
  git -C "$GIT_ROOT" log --reverse --format=%H -- "$state_rel" > "$commits" 2>/dev/null || {
    fail "retask eligibility: cannot inspect execution-state history"
    return
  }
  : > "$history_epochs"
  while IFS= read -r commit; do
    [[ -n "$commit" ]] || continue
    if ! git -C "$GIT_ROOT" show "$commit:$state_rel" > "$blob" 2>/dev/null; then
      fail "retask eligibility: committed execution-state history contains a deletion or unreadable snapshot"
      bad=1
      continue
    fi
    epoch=$(markdown_field_value "$blob" 'Execution-Epoch')
    original=$(markdown_field_value "$blob" 'Original-Implementation-Baseline')
    if ! printf '%s\n' "$epoch" | grep -Eq '^E[1-9][0-9]*$' || ! is_git_oid "$original"; then
      fail "retask eligibility: committed execution-state history has an invalid epoch or Original Baseline"
      bad=1
      continue
    fi
    number=${epoch#E}
    printf '%s\n' "$epoch" >> "$history_epochs"
    if [[ "$seen" -eq 0 ]]; then
      [[ "$number" -eq 1 ]] || { fail "retask eligibility: execution-state history must begin at E1"; bad=1; }
      anchor_original=$original
    else
      [[ "$original" == "$anchor_original" ]] || {
        fail "retask eligibility: Original-Implementation-Baseline changed in committed execution-state history"; bad=1;
      }
      if [[ "$number" -ne "$previous_number" && "$number" -ne $((previous_number + 1)) ]]; then
        fail "retask eligibility: execution epochs must advance one step without gaps"
        bad=1
      fi
    fi
    previous_number=$number
    seen=$((seen + 1))
  done < "$commits"
  if [[ "$seen" -eq 0 ]]; then
    fail "retask eligibility: Protocol v2/v3 requires committed execution-state history"
    return
  fi
  [[ "$CURRENT_ORIGINAL_BASELINE" == "$anchor_original" ]] || {
    fail "retask eligibility: current Original Baseline differs from the first committed execution state"; bad=1;
  }
  current_number=${CURRENT_EXECUTION_EPOCH#E}
  if [[ "$current_number" -ne "$previous_number" && "$current_number" -ne $((previous_number + 1)) ]]; then
    fail "retask eligibility: current execution epoch is not the committed epoch or its single successor"
    bad=1
  fi
  if [[ -d "$FEATURE_DIR/.gatespec/archive" ]]; then
    while IFS= read -r archive; do
      archive_state="$archive/execution-state.md"
      [[ -f "$archive_state" && ! -L "$archive_state" ]] || continue
      archive_epoch=$(markdown_field_value "$archive_state" 'Execution-Epoch')
      archive_original=$(markdown_field_value "$archive_state" 'Original-Implementation-Baseline')
      [[ "$archive_original" == "$anchor_original" ]] || {
        fail "retask eligibility: retask archive '${archive##*/}' changes Original-Implementation-Baseline"; bad=1;
      }
      if ! printf '%s\n' "$archive_epoch" | grep -Eq '^E[1-9][0-9]*$' ||
         [[ ${archive_epoch#E} -gt "$current_number" ]]; then
        fail "retask eligibility: retask archive '${archive##*/}' has an invalid or future execution epoch"
        bad=1
        continue
      fi
      archive_number=${archive_epoch#E}
      if [[ "$previous_archive_number" -gt 0 && "$archive_number" -le "$previous_archive_number" ]]; then
        fail "retask eligibility: Protocol v2/v3 retask archive epochs must strictly increase in timestamp order"
        bad=1
      fi
      if ! grep -Fqx -- "$archive_epoch" "$history_epochs"; then
        fail "retask eligibility: retask archive '${archive##*/}' epoch never appears in committed execution-state history"
        bad=1
      fi
      previous_archive_number=$archive_number
    done < <(find "$FEATURE_DIR/.gatespec/archive" -mindepth 1 -maxdepth 1 -name '*-retask' -print | LC_ALL=C sort)
  fi
  if [[ "$previous_archive_number" -gt 0 && "$current_number" -le "$previous_archive_number" ]]; then
    fail "retask eligibility: current execution epoch must be newer than every Protocol v2/v3 retask archive"
    bad=1
  fi
  [[ "$bad" -eq 0 ]] && pass "retask eligibility: Original Baseline and execution epochs are continuous across committed state and retask archives"
}

check_prior_review_closure_table() {
  local body="$TMP_DIR/prior-closure-body" rows="$TMP_DIR/prior-closure-rows"
  local digest source required remediation expected checkpoint_line id task_line bad=0 pair
  section_body "$TASKS" 'GateSpec Prior Review Closure' > "$body"
  if ! extract_four_column_table "$body" \
    '| Finding-SHA256 | Source verdict | Required-before | Remediation tasks |' "$rows" \
    'tasks.md: GateSpec Prior Review Closure'; then
    return
  fi
  collect_prior_review_findings
  if [[ ! -s "$TMP_DIR/required-prior-findings" ]]; then
    if [[ $(awk 'NF {n++} END {print n+0}' "$rows") -ne 1 ]] ||
       ! grep -Fqx $'none\tnone\tnone\tnone' "$rows"; then
      fail "tasks.md: Prior Review Closure without current-basis findings must contain only the exact none row"
    else
      pass "tasks.md: Prior Review Closure records the exact no-finding state"
    fi
    return
  fi
  : > "$TMP_DIR/prior-closure-actual-pairs"
  while IFS=$'\t' read -r digest source required remediation; do
    [[ -n "$digest" ]] || continue
    if [[ "$digest" == none || "$source" == none || "$required" == none || "$remediation" == none ]]; then
      fail "tasks.md: Prior Review Closure cannot mix the none row with findings"
      bad=1
      continue
    fi
    if ! is_lower_hex64 "$digest"; then fail "tasks.md: Finding-SHA256 must be lowercase 64-hex"; bad=1; fi
    pair=$(printf '%s\t%s' "$digest" "$source")
    if ! awk -F '\t' -v digest="$digest" -v source="$source" \
      '$1 == digest && $2 == source {found=1} END {exit !found}' "$TMP_DIR/required-prior-findings"; then
      fail "tasks.md: Prior Review Closure contains unknown or incorrectly hashed finding '$source'"
      bad=1
    fi
    printf '%s\n' "$pair" >> "$TMP_DIR/prior-closure-actual-pairs"
    if ! grep -Fqx -- "$required" "$TMP_DIR/required-checkpoints"; then
      fail "tasks.md: finding '$source' Required-before must be a declared checkpoint"
      bad=1
      continue
    fi
    checkpoint_line=$(grep -nE "^- \\[[ xX]\\] T[0-9][0-9][0-9].*GateSpec review checkpoint ${required}:" "$TASKS" | cut -d: -f1)
    if canonical_id_list "$remediation" '^T[0-9][0-9][0-9]$' "$TMP_DIR/prior-remediation-tasks" \
      "tasks.md: finding '$source' Remediation tasks" no; then
      while IFS= read -r id; do
        task_line=$(grep -nE "^- \\[[ xX]\\] ${id}([[:space:]]|$)" "$TASKS" | cut -d: -f1)
        if ! [[ "$task_line" =~ ^[0-9]+$ ]] ||
           grep -E "^- \\[[ xX]\\] ${id}.*GateSpec review checkpoint REV-" "$TASKS" >/dev/null 2>&1; then
          fail "tasks.md: finding '$source' remediation $id must be one non-checkpoint task"
          bad=1
        elif ! [[ "$checkpoint_line" =~ ^[0-9]+$ ]] || [[ "$task_line" -ge "$checkpoint_line" ]]; then
          fail "tasks.md: finding '$source' remediation $id occurs after Required-before $required"
          bad=1
        fi
      done < "$TMP_DIR/prior-remediation-tasks"
    else
      bad=1
    fi
  done < "$rows"
  LC_ALL=C sort "$TMP_DIR/prior-closure-actual-pairs" | uniq -d > "$TMP_DIR/prior-closure-duplicate-pairs"
  [[ ! -s "$TMP_DIR/prior-closure-duplicate-pairs" ]] || { fail "tasks.md: each prior finding must have exactly one closure row"; bad=1; }
  cut -f1,2 "$TMP_DIR/required-prior-findings" | LC_ALL=C sort > "$TMP_DIR/prior-closure-required-pairs"
  LC_ALL=C sort "$TMP_DIR/prior-closure-actual-pairs" > "$TMP_DIR/prior-closure-actual-pairs-sorted"
  if ! cmp -s "$TMP_DIR/prior-closure-required-pairs" "$TMP_DIR/prior-closure-actual-pairs-sorted"; then
    fail "tasks.md: Prior Review Closure must cover every current-basis BLOCKER item exactly once"
    bad=1
  fi
  [[ "$bad" -eq 0 ]] && pass "tasks.md: every current and retask-archive blocker has bounded remediation closure"
}

check_complete_tracked_task_review_grandfather() {
  local before="$FAILURES"
  [[ -f "$FEATURE_DIR/.gatespec/reviews/REV-TASKS/seal.md" ]] || return 1
  initialize_review_hashes
  if protocol_has_execution_state "${ACTIVE_REVIEW_PROTOCOL:-1}"; then
    check_execution_state downstream
    [[ "$FAILURES" -eq "$before" ]] && check_implementation_adjustments no
  fi
  [[ "$FAILURES" -eq "$before" ]] && check_review_chain REV-TASKS TASKS
  [[ "$FAILURES" -eq "$before" ]] && check_task_review_git_state
  [[ "$FAILURES" -eq "$before" ]]
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
      return line ~ /^- \*\*(Protocol-Version|Review-ID|Round|Scope|Spec-Content-SHA256|Plan-Content-SHA256|Design-Attachments-SHA256|Tasks-Definition-SHA256|Test-Control-Mode|Test-Control-Closure-SHA256|Test-Control-Subject-Manifest-SHA256|Default-OFF-Evidence-SHA256|Explicit-ON-Evidence-SHA256|Execution-Epoch|Source-Design-Content-SHA256|Implementation-Adjustments-SHA256|Task-Handoff-Commit|Preserved-Reviews-SHA256|Implementation-Baseline|Base-Commit|Subject-Commit|Task-IDs|Changed-Paths-SHA256|Final-Delta-SHA256|Previous-Verdict-SHA256)\*\*: `[^`]+`$/
    }
    function verdict_pre(line) {
      return line ~ /^- \*\*(Protocol-Version|Review-ID|Round|Request-SHA256|Reviewer-Platform|Reviewer-Context-ID|Isolation|Status)\*\*: `[^`]+`$/
    }
    function seal_field(line) {
      return line ~ /^- \*\*(Protocol-Version|Review-ID|Round|Status|Request-SHA256|Verdict-SHA256|Spec-Content-SHA256|Plan-Content-SHA256|Design-Attachments-SHA256|Tasks-Definition-SHA256|Test-Control-Mode|Test-Control-Closure-SHA256|Test-Control-Subject-Manifest-SHA256|Default-OFF-Evidence-SHA256|Explicit-ON-Evidence-SHA256|Execution-Epoch|Source-Design-Content-SHA256|Implementation-Adjustments-SHA256|Task-Handoff-Commit|Preserved-Reviews-SHA256|Implementation-Baseline|Base-Commit|Subject-Commit|Final-Delta-SHA256|Sealed-At|Seal-SHA256)\*\*: `[^`]+`$/
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
      if (state == 1 && $0 ~ /^- \*\*Verdict-SHA256\*\*: `[^`]+`$/) {state=2; next}
      if ($0 == "## Tests Run" || $0 == "## Test Control Audit" || $0 == "## Blockers" || $0 == "## Observations" || $0 == "## Limitations") {
        state=1
        section=substr($0, 4)
        blocker_active=0
        next
      }
      if (state == 1 && section == "Test Control Audit" && $0 ~ /^- \*\*(Mode|Declared-Controls|Undeclared-Controls|Orphan-Controls|Default-OFF-Proof|Explicit-ON-Proof|Test-Control-Scale)\*\*: `[^`]+`$/) next
      if (state == 1 && section == "Blockers") {
        if ($0 ~ /^- [^[:space:]](.*[^[:space:]])?$/) {
          blocker_active=($0 ~ /^- BLOCKER:[[:space:]]+/)
          next
        }
        if (blocker_active && $0 ~ /^[[:space:]]+[^[:space:]](.*[^[:space:]])?$/) next
      }
      if (state == 1 && section != "Blockers" && $0 ~ /^- [^[:space:]](.*[^[:space:]])?$/) next
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

append_test_control_manifest_object() {
  local subject="$1" role="$2" declared="$3" allow_tree="$4" context="$5"
  local listing="$TMP_DIR/test-control-ls-tree" meta object_path mode type oid count=0 bad=0
  : > "$listing"
  if [[ "$allow_tree" == yes ]]; then
    git -C "$GIT_ROOT" ls-tree "$subject" -- "$declared" > "$TMP_DIR/test-control-ls-root" 2>/dev/null || return 1
    if awk -F $'\t' 'NR == 1 {split($1,a," "); if (a[2] == "tree") ok=1} END {exit !ok}' \
      "$TMP_DIR/test-control-ls-root"; then
      git -C "$GIT_ROOT" ls-tree -r "$subject" -- "$declared" > "$listing" 2>/dev/null || return 1
    else
      cp "$TMP_DIR/test-control-ls-root" "$listing"
    fi
  else
    git -C "$GIT_ROOT" ls-tree "$subject" -- "$declared" > "$listing" 2>/dev/null || return 1
  fi
  while IFS=$'\t' read -r meta object_path; do
    [[ -n "$object_path" ]] || continue
    mode=$(printf '%s\n' "$meta" | awk '{print $1}')
    type=$(printf '%s\n' "$meta" | awk '{print $2}')
    oid=$(printf '%s\n' "$meta" | awk '{print $3}')
    if [[ "$type" != blob || ( "$mode" != 100644 && "$mode" != 100755 ) ]]; then
      fail "$context: Test Control $role '$object_path' must be a tracked regular non-symlink blob at Subject"
      bad=1
      continue
    fi
    printf '%s\t%s\t%s\t%s\t%s\n' "$role" "$declared" "$object_path" "$mode" "$oid" \
      >> "$TMP_DIR/test-control-subject-manifest"
    printf '%s\n' "$object_path" >> "$TMP_DIR/test-control-subject-paths"
    [[ "$role" == test-only-surface ]] && printf '%s\n' "$object_path" >> "$TMP_DIR/test-control-subject-surface-paths"
    [[ "$role" == validator ]] && printf '%s\n' "$object_path" >> "$TMP_DIR/test-control-subject-validator-paths"
    case "$role" in
      production-touchpoint|build-wiring)
        printf '%s\n' "$object_path" >> "$TMP_DIR/test-control-subject-production-paths"
        ;;
    esac
    count=$((count + 1))
  done < "$listing"
  if [[ "$count" -eq 0 ]]; then
    fail "$context: declared Test Control $role path '$declared' is missing from Subject"
    bad=1
  elif [[ "$allow_tree" != yes && "$count" -ne 1 ]]; then
    fail "$context: Test Control $role '$declared' must resolve to exactly one blob"
    bad=1
  fi
  [[ "$bad" -eq 0 ]]
}

test_control_subject_manifest_hash() {
  local subject="$1" context="$2" control path symbol switch wiring validator bad=0
  : > "$TMP_DIR/test-control-subject-manifest"
  : > "$TMP_DIR/test-control-subject-paths"
  : > "$TMP_DIR/test-control-subject-surface-paths"
  : > "$TMP_DIR/test-control-subject-validator-paths"
  : > "$TMP_DIR/test-control-subject-production-paths"
  while IFS=$'\t' read -r control path symbol; do
    [[ -n "$path" ]] || continue
    append_test_control_manifest_object "$subject" test-only-surface "$path" yes "$context" || bad=1
  done < "$TMP_DIR/test-control-surface-declarations"
  while IFS=$'\t' read -r control path symbol; do
    [[ -n "$path" ]] || continue
    append_test_control_manifest_object "$subject" production-touchpoint "$path" no "$context" || bad=1
  done < "$TMP_DIR/test-control-touchpoint-declarations"
  while IFS=$'\t' read -r switch wiring validator; do
    [[ -n "$switch" ]] || continue
    append_test_control_manifest_object "$subject" build-wiring "$wiring" no "$context" || bad=1
    append_test_control_manifest_object "$subject" validator "$validator" no "$context" || bad=1
  done < "$TMP_DIR/test-control-validator-tuples"
  LC_ALL=C sort -u -o "$TMP_DIR/test-control-subject-manifest" "$TMP_DIR/test-control-subject-manifest"
  LC_ALL=C sort -u -o "$TMP_DIR/test-control-subject-paths" "$TMP_DIR/test-control-subject-paths"
  LC_ALL=C sort -u -o "$TMP_DIR/test-control-subject-surface-paths" "$TMP_DIR/test-control-subject-surface-paths"
  LC_ALL=C sort -u -o "$TMP_DIR/test-control-subject-validator-paths" "$TMP_DIR/test-control-subject-validator-paths"
  LC_ALL=C sort -u -o "$TMP_DIR/test-control-subject-production-paths" "$TMP_DIR/test-control-subject-production-paths"
  [[ "$bad" -eq 0 ]] || return 1
  portable_sha256 < "$TMP_DIR/test-control-subject-manifest" | awk '{print $1}'
}

check_test_control_subject_manifest() {
  local subject="$1" recorded="$2" context="$3" actual
  actual=$(test_control_subject_manifest_hash "$subject" "$context") || actual=''
  if ! is_lower_hex64 "$recorded" || [[ "$recorded" != "$actual" ]]; then
    fail "$context: Test-Control-Subject-Manifest-SHA256 does not match declared Subject Git objects"
    return 1
  fi
  pass "$context: Test Control Subject manifest binds declared regular Git objects"
}

check_test_control_evidence_file() {
  local file="$1" lane="$2" round="$3" subject="$4" closure="$5" manifest="$6" context="$7"
  local header separator body="$TMP_DIR/test-control-evidence-table" rows="$TMP_DIR/test-control-evidence-rows"
  local invalid protocol id recorded_round recorded_lane recorded_subject mode recorded_closure recorded_manifest state
  local validator switch wiring command scope compile dependency artifact install tests source_coverage test_coverage
  local compile_hits dependency_hits artifact_hits install_hits result expected_state expected_scope expected_source expected_test
  local actual_hash tuple_count row_count bad=0 before="$FAILURES"
  header='| Validator | Build switch | Build wiring | Validator command | Production build scope | Compile manifest SHA256 | Dependency manifest SHA256 | Artifact manifest SHA256 | Install/export/symbol manifest SHA256 | Test manifest SHA256 | Declared source coverage | Declared test coverage | Undeclared compile hits | Undeclared dependency hits | Undeclared artifact hits | Undeclared install/export hits | Result |'
  separator='|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|'
  if [[ ! -f "$file" || -L "$file" ]]; then
    fail "$context: required $lane evidence must be a regular non-symlink file"
    return 1
  fi
  invalid=$(awk -v header="$header" -v separator="$separator" '
    /^[[:space:]]*$/ {next}
    NR == 1 && $0 == "# GateSpec Test Control Evidence" {next}
    state == 0 && $0 ~ /^- \*\*(Protocol-Version|Review-ID|Round|Lane|Subject-Commit|Test-Control-Mode|Test-Control-Closure-SHA256|Test-Control-Subject-Manifest-SHA256|Effective-Switch-State)\*\*: `[^`]+`$/ {next}
    state == 0 && $0 == "## Validator Results" {state=1; next}
    state == 1 && $0 == header {state=2; next}
    state == 2 && $0 == separator {state=3; next}
    state == 3 && substr($0,1,2) == "| " {
      count=split($0,cells,"|")
      rebuilt="|"
      row_ok=(count == 19 && cells[1] == "" && cells[19] == "")
      for (i=2; i<=18 && row_ok; i++) {
        value=cells[i]
        sub(/^ /,"",value)
        sub(/ $/,"",value)
        if (value == "" || value ~ /^[[:space:]]/ || value ~ /[[:space:]]$/) row_ok=0
        rebuilt=rebuilt " " value " |"
      }
      if (row_ok && rebuilt == $0) next
    }
    state == 3 && $0 ~ /^- \*\*Evidence-SHA256\*\*: `[0-9a-f]+`$/ {state=4; next}
    {print NR ":" $0}
    END {if (state != 4) print "incomplete canonical evidence"}
  ' "$file")
  [[ -z "$invalid" ]] || { fail "$context: $lane evidence contains non-canonical fields, table, or prose"; bad=1; }
  [[ $(sed -n '1p' "$file") == '# GateSpec Test Control Evidence' &&
     $(grep -cFx '# GateSpec Test Control Evidence' "$file" || true) -eq 1 ]] || {
    fail "$context: $lane evidence requires its exact line-1 title"; bad=1;
  }
  check_ordered_fields "$file" "$context $lane evidence" \
    'Protocol-Version' 'Review-ID' 'Round' 'Lane' 'Subject-Commit' 'Test-Control-Mode' \
    'Test-Control-Closure-SHA256' 'Test-Control-Subject-Manifest-SHA256' \
    'Effective-Switch-State' 'Evidence-SHA256'
  protocol=$(markdown_field_value "$file" 'Protocol-Version')
  id=$(markdown_field_value "$file" 'Review-ID')
  recorded_round=$(markdown_field_value "$file" 'Round')
  recorded_lane=$(markdown_field_value "$file" 'Lane')
  recorded_subject=$(markdown_field_value "$file" 'Subject-Commit')
  mode=$(markdown_field_value "$file" 'Test-Control-Mode')
  recorded_closure=$(markdown_field_value "$file" 'Test-Control-Closure-SHA256')
  recorded_manifest=$(markdown_field_value "$file" 'Test-Control-Subject-Manifest-SHA256')
  state=$(markdown_field_value "$file" 'Effective-Switch-State')
  [[ "$protocol" == 3 && "$id" == REV-FINAL && "$recorded_round" == "$round" &&
     "$recorded_lane" == "$lane" && "$recorded_subject" == "$subject" && "$mode" == isolated &&
     "$recorded_closure" == "$closure" && "$recorded_manifest" == "$manifest" ]] || {
    fail "$context: $lane evidence global fields do not bind the REV-FINAL request"; bad=1;
  }
  if [[ "$lane" == default-off ]]; then
    expected_state=omitted-default-off
    expected_scope='production-install-package-when-present'
    expected_source=absent
    expected_test=not-applicable
  else
    expected_state=explicit-on
    expected_scope=test-build-only
    expected_source=complete
    expected_test=complete
  fi
  [[ "$state" == "$expected_state" ]] || { fail "$context: $lane Effective-Switch-State is invalid"; bad=1; }
  awk -v start='## Validator Results' -v end='- **Evidence-SHA256**:' '
    $0 == start {inside=1; next}
    inside && index($0,end) == 1 {exit}
    inside {print}
  ' "$file" > "$body"
  awk -F '|' -v header="$header" -v separator="$separator" '
    /^[[:space:]]*$/ || $0 == header || $0 == separator {next}
    {
      if (NF != 19) {print "INVALID"; next}
      for (i=2; i<=18; i++) {
        value=$i; sub(/^ /,"",value); sub(/ $/,"",value)
        printf "%s%s", (i == 2 ? "" : "\t"), value
      }
      print ""
    }
  ' "$body" > "$rows"
  if grep -Fqx INVALID "$rows"; then
    fail "$context: $lane validator rows must have exactly seventeen columns"
    bad=1
  fi
  grep '^| ' "$body" | grep -Fvx "$header" > "$TMP_DIR/test-control-evidence-raw-rows" || true
  LC_ALL=C sort -u "$TMP_DIR/test-control-evidence-raw-rows" > "$TMP_DIR/test-control-evidence-raw-sorted"
  if ! cmp -s "$TMP_DIR/test-control-evidence-raw-rows" "$TMP_DIR/test-control-evidence-raw-sorted"; then
    fail "$context: $lane validator rows must be unique and C-sorted"
    bad=1
  fi
  : > "$TMP_DIR/test-control-evidence-actual-tuples"
  while IFS=$'\t' read -r validator switch wiring command scope compile dependency artifact install tests \
    source_coverage test_coverage compile_hits dependency_hits artifact_hits install_hits result; do
    [[ -n "$validator" && "$validator" != INVALID ]] || continue
    printf '%s\t%s\t%s\n' "$switch" "$wiring" "$validator" >> "$TMP_DIR/test-control-evidence-actual-tuples"
    [[ "$command" == "bash $validator --gatespec-lane $lane" ]] || { fail "$context: $lane validator command is not canonical for '$validator'"; bad=1; }
    [[ "$scope" == "$expected_scope" && "$source_coverage" == "$expected_source" &&
       "$test_coverage" == "$expected_test" && "$result" == PASS ]] || {
      fail "$context: $lane validator '$validator' has invalid scope, coverage, or result"; bad=1;
    }
    for actual_hash in "$compile" "$dependency" "$artifact" "$tests"; do
      is_lower_hex64 "$actual_hash" || { fail "$context: $lane validator manifest hashes must be lowercase 64-hex"; bad=1; break; }
    done
    if [[ "$install" != not-applicable ]] && ! is_lower_hex64 "$install"; then
      fail "$context: $lane install/export/symbol manifest must be not-applicable or lowercase 64-hex"; bad=1
    fi
    if [[ "$compile_hits" != 0 || "$dependency_hits" != 0 || "$artifact_hits" != 0 || "$install_hits" != 0 ]]; then
      fail "$context: $lane validator '$validator' must report zero undeclared hits in every manifest"; bad=1
    fi
  done < "$rows"
  LC_ALL=C sort -u -o "$TMP_DIR/test-control-evidence-actual-tuples" "$TMP_DIR/test-control-evidence-actual-tuples"
  if ! cmp -s "$TMP_DIR/test-control-validator-tuples" "$TMP_DIR/test-control-evidence-actual-tuples"; then
    fail "$context: $lane evidence must contain exactly one row per declared validator tuple"
    bad=1
  fi
  tuple_count=$(awk 'NF {n++} END {print n+0}' "$TMP_DIR/test-control-validator-tuples")
  row_count=$(awk 'NF && $0 != "INVALID" {n++} END {print n+0}' "$rows")
  [[ "$row_count" -eq "$tuple_count" ]] || { fail "$context: $lane evidence validator row count is incomplete"; bad=1; }
  check_self_hash "$file" 'Evidence-SHA256' "$context $lane evidence"
  [[ "$bad" -eq 0 && "$FAILURES" -eq "$before" ]]
}

check_test_control_final_evidence() {
  local request="$1" round="$2" context="$3" directory subject closure manifest default_file explicit_file
  local default_hash explicit_hash bad=0 before="$FAILURES"
  CURRENT_TEST_CONTROL_EVIDENCE_VALID=no
  directory=${request%/*}
  subject=$(markdown_field_value "$request" 'Subject-Commit')
  closure=$(markdown_field_value "$request" 'Test-Control-Closure-SHA256')
  manifest=$(markdown_field_value "$request" 'Test-Control-Subject-Manifest-SHA256')
  default_file="$directory/round-${round}-default-off-evidence.md"
  explicit_file="$directory/round-${round}-explicit-on-evidence.md"
  check_test_control_evidence_file "$default_file" default-off "$round" "$subject" "$closure" "$manifest" "$context" || bad=1
  check_test_control_evidence_file "$explicit_file" explicit-on "$round" "$subject" "$closure" "$manifest" "$context" || bad=1
  default_hash=$(markdown_field_value "$default_file" 'Evidence-SHA256')
  explicit_hash=$(markdown_field_value "$explicit_file" 'Evidence-SHA256')
  [[ "$default_hash" == $(markdown_field_value "$request" 'Default-OFF-Evidence-SHA256') ]] || {
    fail "$context: Default-OFF-Evidence-SHA256 does not bind its evidence self-hash"; bad=1;
  }
  [[ "$explicit_hash" == $(markdown_field_value "$request" 'Explicit-ON-Evidence-SHA256') ]] || {
    fail "$context: Explicit-ON-Evidence-SHA256 does not bind its evidence self-hash"; bad=1;
  }
  if [[ "$bad" -eq 0 && "$FAILURES" -eq "$before" ]]; then
    CURRENT_TEST_CONTROL_EVIDENCE_VALID=yes
    pass "$context: both Test Control lane records match canonical tuple, Subject, and hash bindings"
    return 0
  fi
  return 1
}

check_test_control_receipt_fields() {
  local file="$1" id="$2" scope="$3" context="$4"
  local mode closure manifest default_evidence explicit_evidence bad=0
  mode=$(markdown_field_value "$file" 'Test-Control-Mode')
  closure=$(markdown_field_value "$file" 'Test-Control-Closure-SHA256')
  manifest=$(markdown_field_value "$file" 'Test-Control-Subject-Manifest-SHA256')
  default_evidence=$(markdown_field_value "$file" 'Default-OFF-Evidence-SHA256')
  explicit_evidence=$(markdown_field_value "$file" 'Explicit-ON-Evidence-SHA256')
  [[ "$mode" == "${CURRENT_TEST_CONTROL_MODE:-}" ]] || {
    fail "$context: Test-Control-Mode does not match tasks.md"; bad=1;
  }
  [[ "$closure" == "${CURRENT_TEST_CONTROL_CLOSURE_HASH:-}" && -n "$closure" ]] || {
    fail "$context: Test-Control-Closure-SHA256 does not match normalized tasks closure"; bad=1;
  }
  if [[ "$mode" == isolated && "$id" == REV-FINAL && "$scope" == FINAL ]]; then
    for digest in "$manifest" "$default_evidence" "$explicit_evidence"; do
      is_lower_hex64 "$digest" || { fail "$context: isolated REV-FINAL Test Control subject/evidence bindings must be lowercase 64-hex"; bad=1; break; }
    done
  elif [[ "$manifest" != not-applicable || "$default_evidence" != not-applicable ||
          "$explicit_evidence" != not-applicable ]]; then
    fail "$context: non-final or Mode none Test Control subject/evidence fields must be not-applicable"
    bad=1
  fi
  [[ "$bad" -eq 0 ]]
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
  if [[ "$request_protocol" == 3 ]]; then
    check_ordered_fields "$file" "$context" \
      'Protocol-Version' 'Review-ID' 'Round' 'Scope' 'Spec-Content-SHA256' \
      'Plan-Content-SHA256' 'Design-Attachments-SHA256' 'Tasks-Definition-SHA256' \
      'Test-Control-Mode' 'Test-Control-Closure-SHA256' 'Test-Control-Subject-Manifest-SHA256' \
      'Default-OFF-Evidence-SHA256' 'Explicit-ON-Evidence-SHA256' \
      'Execution-Epoch' 'Source-Design-Content-SHA256' 'Implementation-Adjustments-SHA256' \
      'Task-Handoff-Commit' 'Preserved-Reviews-SHA256' 'Implementation-Baseline' \
      'Base-Commit' 'Subject-Commit' 'Task-IDs' 'Changed-Paths-SHA256' \
      'Final-Delta-SHA256' 'Previous-Verdict-SHA256' 'Request-SHA256'
  elif [[ "$request_protocol" == 2 ]]; then
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

  if protocol_has_execution_state "$protocol"; then
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
        else
          check_canonical_empty_ia "$TMP_DIR/task-handoff-ia" \
            "$context Task-Handoff IA snapshot" "$execution_epoch" "$source_hash" || bad=1
        fi
      elif [[ "$ia_hash" != not-applicable ]]; then
        fail "$context: IA must be not-applicable without Source Design"
        bad=1
      fi
    elif [[ "$ia_hash" != not-applicable ]] && ! is_lower_hex64 "$ia_hash"; then
      fail "$context: Implementation-Adjustments-SHA256 must be not-applicable or lowercase 64-hex"; bad=1
    fi
  elif [[ -n "$execution_epoch$source_hash$ia_hash$task_handoff$preserved$final_delta" ]]; then
    fail "$context: Protocol v1 must not contain Protocol v2/v3 execution fields"
    bad=1
  fi

  if [[ "$protocol" == 3 ]]; then
    check_test_control_receipt_fields "$file" "$expected_id" "$expected_scope" "$context" || bad=1
  else
    check_no_test_control_receipt_fields "$file" "$context" || bad=1
  fi

  check_task_ids_field "$task_ids" "$context"
  if [[ "$expected_scope" == 'TASKS' ]]; then
    if [[ "$baseline" != 'not-applicable' || "$base" != 'not-applicable' ||
          "$subject" != 'not-applicable' || "$changed" != 'not-applicable' ]]; then
      fail "$context: TASKS review Git fields must be 'not-applicable'"
      bad=1
    fi
    if protocol_has_execution_state "$protocol" && [[ "$final_delta" != not-applicable ]]; then
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
    elif protocol_has_execution_state "$protocol" && [[ "$expected_id" == REV-FINAL ]]; then
      if [[ "$base" != "$CURRENT_ORIGINAL_BASELINE" ]] ||
         ! git -C "$GIT_ROOT" merge-base --is-ancestor "$base" "$baseline" 2>/dev/null ||
         ! git -C "$GIT_ROOT" merge-base --is-ancestor "$baseline" "$subject" 2>/dev/null; then
        fail "$context: Protocol v2/v3 FINAL must use Original Baseline and preserve original -> handoff baseline -> subject ancestry"
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
    if protocol_has_execution_state "$protocol"; then
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
    if [[ "$protocol" == 3 && "$expected_id" == REV-FINAL &&
          "${CURRENT_TEST_CONTROL_MODE:-none}" == isolated ]]; then
      check_test_control_subject_manifest "$subject" \
        "$(markdown_field_value "$file" 'Test-Control-Subject-Manifest-SHA256')" "$context" || bad=1
      check_test_control_final_evidence "$file" "$expected_round" "$context" || bad=1
    fi
  fi

  check_request_tests "$file" "$expected_scope" "$context" "$expected_id"
  check_self_hash "$file" 'Request-SHA256' "$context"
  [[ "$bad" -eq 0 ]] && pass "$context: request fields match review scope and current artifact contract"
}

check_test_control_audit() {
  local file="$1" id="$2" scope="$3" status="$4" context="$5"
  local body="$TMP_DIR/test-control-audit" mode declared undeclared orphan default_proof explicit_proof scale
  local expected_declared expected_default expected_explicit value metric range lower upper bad=0
  local scale_shape_ok=no additions_lower additions_upper churn_lower churn_upper
  local touchpoints_lower touchpoints_upper actual_touchpoints
  section_body "$file" 'Test Control Audit' > "$body"
  check_ordered_fields "$body" "$context Test Control Audit" \
    'Mode' 'Declared-Controls' 'Undeclared-Controls' 'Orphan-Controls' \
    'Default-OFF-Proof' 'Explicit-ON-Proof' 'Test-Control-Scale'
  if grep -vE '^[[:space:]]*$|^- \*\*(Mode|Declared-Controls|Undeclared-Controls|Orphan-Controls|Default-OFF-Proof|Explicit-ON-Proof|Test-Control-Scale)\*\*: `[^`]+`$' "$body" >/dev/null 2>&1; then
    fail "$context: Test Control Audit permits only its seven canonical fields"
    bad=1
  fi
  mode=$(markdown_field_value "$body" 'Mode')
  declared=$(markdown_field_value "$body" 'Declared-Controls')
  undeclared=$(markdown_field_value "$body" 'Undeclared-Controls')
  orphan=$(markdown_field_value "$body" 'Orphan-Controls')
  default_proof=$(markdown_field_value "$body" 'Default-OFF-Proof')
  explicit_proof=$(markdown_field_value "$body" 'Explicit-ON-Proof')
  scale=$(markdown_field_value "$body" 'Test-Control-Scale')
  if [[ "${HISTORICAL_TASK_AUDIT:-no}" == yes ]]; then
    [[ "$mode" == "${HISTORICAL_REQUEST_TC_MODE:-}" ]] || { fail "$context: historical Audit Mode does not match its request"; bad=1; }
  else
    [[ "$mode" == "${CURRENT_TEST_CONTROL_MODE:-}" ]] || { fail "$context: Audit Mode does not match tasks.md"; bad=1; }
  fi
  if [[ "$mode" == none ]]; then
    expected_declared=none
    expected_default=not-applicable
    expected_explicit=not-applicable
  else
    expected_declared=$(awk 'BEGIN {sep=""} NF {printf "%s%s",sep,$0; sep=", "} END {print ""}' "$TMP_DIR/test-control-ids")
    if [[ "$id" == REV-FINAL && "$scope" == FINAL ]]; then
      expected_default=verified
      expected_explicit=verified
    else
      expected_default=pending-REV-FINAL
      expected_explicit=pending-REV-FINAL
    fi
  fi
  if [[ "${HISTORICAL_TASK_AUDIT:-no}" == yes ]]; then
    if [[ "$mode" == none ]]; then
      [[ "$declared" == none ]] || { fail "$context: historical Mode none audit must declare no controls"; bad=1; }
    elif ! canonical_id_list "$declared" '^TC-[0-9][0-9][0-9]$' "$TMP_DIR/historical-audit-controls" \
      "$context: historical Audit Declared-Controls" no; then
      bad=1
    fi
  else
    [[ "$declared" == "$expected_declared" ]] || { fail "$context: Audit Declared-Controls must exactly cover tasks.md"; bad=1; }
  fi
  case "$undeclared" in none|found) ;; *) fail "$context: Audit Undeclared-Controls must be none or found"; bad=1 ;; esac
  if [[ "$orphan" != none ]]; then
    if ! canonical_id_list "$orphan" '^TC-[0-9][0-9][0-9]$' "$TMP_DIR/test-control-audit-orphans" \
      "$context: Audit Orphan-Controls" no; then
      bad=1
    else
      while IFS= read -r value; do
        if [[ "${HISTORICAL_TASK_AUDIT:-no}" == yes ]]; then
          grep -Fqx -- "$value" "$TMP_DIR/historical-audit-controls" || { fail "$context: Audit orphan $value is not declared"; bad=1; }
        else
          grep -Fqx -- "$value" "$TMP_DIR/test-control-ids" || { fail "$context: Audit orphan $value is not declared"; bad=1; }
        fi
      done < "$TMP_DIR/test-control-audit-orphans"
    fi
  fi
  case "$default_proof" in not-applicable|pending-REV-FINAL|verified|failed) ;; *) fail "$context: invalid Default-OFF-Proof state"; bad=1 ;; esac
  case "$explicit_proof" in not-applicable|pending-REV-FINAL|verified|failed) ;; *) fail "$context: invalid Explicit-ON-Proof state"; bad=1 ;; esac
  if [[ "$mode" == isolated ]]; then
    if [[ "$id" == REV-FINAL && "$scope" == FINAL ]]; then
      case "$default_proof" in verified|failed) ;; *) fail "$context: isolated REV-FINAL Default-OFF-Proof must be verified or failed"; bad=1 ;; esac
      case "$explicit_proof" in verified|failed) ;; *) fail "$context: isolated REV-FINAL Explicit-ON-Proof must be verified or failed"; bad=1 ;; esac
    elif [[ "$default_proof" != pending-REV-FINAL || "$explicit_proof" != pending-REV-FINAL ]]; then
      fail "$context: isolated REV-TASKS and non-final implementation proofs must both be pending-REV-FINAL"
      bad=1
    fi
  fi
  if [[ "$status" == PASS && ( "$default_proof" == failed || "$explicit_proof" == failed ) ]]; then
    fail "$context: PASS Test Control Audit cannot report a failed lane proof"
    bad=1
  fi
  if [[ "$mode" == none && ( "$default_proof" != not-applicable || "$explicit_proof" != not-applicable ) ]]; then
    fail "$context: Mode none proof states must be not-applicable"
    bad=1
  fi
  if [[ "$status" == PASS ]] &&
     [[ "$undeclared" != none || "$orphan" != none || "$default_proof" != "$expected_default" ||
        "$explicit_proof" != "$expected_explicit" ]]; then
    fail "$context: PASS Test Control Audit must have no undeclared/orphan controls and the exact lane proof state"
    bad=1
  fi
  if [[ "$mode" == none && "$undeclared" == none ]]; then
    if [[ "$scale" == 'additions=0; churn=0; files=0; touchpoints=0' ]]; then
      scale_shape_ok=yes
    else
      fail "$context: Mode none without an undeclared control must use exact all-zero Test-Control-Scale counts"
      bad=1
    fi
  elif [[ "$scope" == TASKS ]]; then
    if ! printf '%s\n' "$scale" | grep -Eq '^additions=[0-9]+(\.\.[0-9]+)?; churn=[0-9]+(\.\.[0-9]+)?; files=[0-9]+(\.\.[0-9]+)?; touchpoints=[0-9]+(\.\.[0-9]+)?$'; then
      fail "$context: REV-TASKS Test-Control-Scale must use canonical nonnegative exact/range values"
      bad=1
    else
      scale_shape_ok=yes
    fi
  elif ! printf '%s\n' "$scale" | grep -Eq '^additions=[0-9]+; churn=[0-9]+; files=[0-9]+; touchpoints=[0-9]+$'; then
      fail "$context: implementation Test-Control-Scale must use exact nonnegative counts"
      bad=1
  else
    scale_shape_ok=yes
  fi
  if [[ "$scale_shape_ok" == yes ]]; then
    for metric in additions churn files touchpoints; do
      range=$(printf '%s\n' "$scale" | sed -n "s/.*${metric}=\\([0-9][0-9]*\\(\\.\\.[0-9][0-9]*\\)\\{0,1\\}\\).*/\\1/p")
      lower=${range%%..*}
      if [[ "$range" == *..* ]]; then upper=${range#*..}; else upper=$lower; fi
      decimal_le "$lower" "$upper" || {
        fail "$context: Test-Control-Scale $metric lower bound exceeds upper bound"
        bad=1
      }
      case "$metric" in
        additions) additions_lower=$lower; additions_upper=$upper ;;
        churn) churn_lower=$lower; churn_upper=$upper ;;
        touchpoints) touchpoints_lower=$lower; touchpoints_upper=$upper ;;
      esac
    done
    if ! decimal_le "$additions_lower" "$churn_lower" ||
       ! decimal_le "$additions_upper" "$churn_upper"; then
      fail "$context: Test-Control-Scale additions cannot exceed churn"
      bad=1
    fi
    if [[ "${HISTORICAL_TASK_AUDIT:-no}" != yes && "$mode" == isolated &&
          -f "$TMP_DIR/test-control-touchpoint-declarations" ]]; then
      cut -f2,3 "$TMP_DIR/test-control-touchpoint-declarations" |
        LC_ALL=C sort -u > "$TMP_DIR/test-control-unique-touchpoints"
      actual_touchpoints=$(awk 'NF {n++} END {print n+0}' "$TMP_DIR/test-control-unique-touchpoints")
      if ! decimal_le "$touchpoints_lower" "$actual_touchpoints" ||
         ! decimal_le "$actual_touchpoints" "$touchpoints_upper"; then
        if [[ "$scope" == TASKS ]]; then
          fail "$context: REV-TASKS Test-Control-Scale touchpoints range must include $actual_touchpoints unique declared production path::symbol touchpoint(s)"
        else
          fail "$context: implementation Test-Control-Scale touchpoints must equal $actual_touchpoints unique declared production path::symbol touchpoint(s)"
        fi
        bad=1
      fi
    fi
  fi
  [[ "$bad" -eq 0 ]] && pass "$context: Test Control Audit is canonical and status-consistent"
  [[ "$bad" -eq 0 ]]
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
  protocol=$(markdown_field_value "$file" 'Protocol-Version')
  if [[ "$protocol" == 3 ]]; then
    check_exact_h2_order "$file" "$context" 'Tests Run' 'Test Control Audit' 'Blockers' 'Observations' 'Limitations'
  else
    check_exact_h2_order "$file" "$context" 'Tests Run' 'Blockers' 'Observations' 'Limitations'
  fi

  status_line=$(markdown_field_line_numbers "$file" 'Status')
  tests_line=$(awk '$0 == "## Tests Run" {print NR}' "$file")
  hash_line=$(markdown_field_line_numbers "$file" 'Verdict-SHA256')
  if ! [[ "$status_line" =~ ^[0-9]+$ && "$tests_line" =~ ^[0-9]+$ && "$hash_line" =~ ^[0-9]+$ ]] ||
     (( status_line >= tests_line || tests_line >= hash_line )); then
    fail "$context: verdict sections must follow Status and precede Verdict-SHA256"
    bad=1
  fi

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

  if [[ "$protocol" == 3 ]]; then
    check_test_control_audit "$file" "$expected_id" "$expected_scope" "$status" "$context" || bad=1
  fi

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
  if [[ "$status" == 'PASS' ]]; then
    if [[ "$nonblank" -ne 1 ]] || ! grep -Fqx -- '- None' "$TMP_DIR/verdict-blockers"; then
      fail "$context: PASS verdict Blockers must be exactly '- None'"
      bad=1
    fi
  else
    malformed=$(awk '
      /^[[:space:]]*$/ {active=0; next}
      /^- BLOCKER:[[:space:]]+.+[^[:space:]]$/ {active=1; next}
      /^- / {print NR ":" $0; active=0; next}
      active && /^[[:space:]]+[^[:space:]](.*[^[:space:]])?$/ {next}
      {print NR ":" $0}
    ' "$TMP_DIR/verdict-blockers")
    if [[ "$blockers" -lt 1 || -n "$malformed" ]] || grep -Fqx -- '- None' "$TMP_DIR/verdict-blockers"; then
      fail "$context: BLOCKED verdict requires canonical '- BLOCKER:' items with only contiguous indented continuation lines"
      bad=1
    fi
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
  if [[ "$request_protocol" == 3 ]]; then
    check_ordered_fields "$file" "$expected_id seal" \
      'Protocol-Version' 'Review-ID' 'Round' 'Status' 'Request-SHA256' 'Verdict-SHA256' \
      'Spec-Content-SHA256' 'Plan-Content-SHA256' 'Design-Attachments-SHA256' \
      'Tasks-Definition-SHA256' 'Test-Control-Mode' 'Test-Control-Closure-SHA256' \
      'Test-Control-Subject-Manifest-SHA256' 'Default-OFF-Evidence-SHA256' \
      'Explicit-ON-Evidence-SHA256' 'Execution-Epoch' 'Source-Design-Content-SHA256' \
      'Implementation-Adjustments-SHA256' 'Task-Handoff-Commit' 'Preserved-Reviews-SHA256' \
      'Implementation-Baseline' 'Base-Commit' 'Subject-Commit' 'Final-Delta-SHA256' \
      'Sealed-At' 'Seal-SHA256'
  elif [[ "$request_protocol" == 2 ]]; then
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
  if protocol_has_execution_state "$request_protocol"; then
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
  if [[ "$request_protocol" == 3 ]]; then
    for label in Test-Control-Mode Test-Control-Closure-SHA256 Test-Control-Subject-Manifest-SHA256 \
      Default-OFF-Evidence-SHA256 Explicit-ON-Evidence-SHA256; do
      expected=$(markdown_field_value "$request" "$label")
      actual=$(markdown_field_value "$file" "$label")
      if [[ "$actual" != "$expected" ]]; then
        fail "$expected_id seal: $label does not match the sealed request"
        bad=1
      fi
    done
  else
    check_no_test_control_receipt_fields "$file" "$expected_id seal" || bad=1
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
  if [[ "$id" == REV-FINAL && "${ACTIVE_REVIEW_PROTOCOL:-1}" == 3 &&
        "${CURRENT_TEST_CONTROL_MODE:-none}" == isolated ]]; then
    printf '%s\n' "$request_rel" "$verdict_rel" \
      "${review_prefix}${id}/round-${prior_round}-default-off-evidence.md" \
      "${review_prefix}${id}/round-${prior_round}-explicit-on-evidence.md" | LC_ALL=C sort > "$expected_paths"
  else
    printf '%s\n' "$request_rel" "$verdict_rel" | LC_ALL=C sort > "$expected_paths"
  fi
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

  if [[ ! -d "$directory" || -L "$directory" ]]; then
    fail "$id: review root must be a regular directory at .gatespec/reviews/$id"
    return
  fi
  invalid=$(find "$directory" -mindepth 1 -maxdepth 1 -print | while IFS= read -r file; do
    rel=${file##*/}
    allowed=no
    if printf '%s\n' "$rel" | grep -Eq '^(round-(00|01|02)-(request|verdict)\.md|seal\.md)$'; then
      allowed=yes
    elif [[ "$id" == REV-FINAL && "${ACTIVE_REVIEW_PROTOCOL:-1}" == 3 &&
            "${CURRENT_TEST_CONTROL_MODE:-none}" == isolated ]] &&
         printf '%s\n' "$rel" | grep -Eq '^round-(00|01|02)-(default-off|explicit-on)-evidence\.md$'; then
      allowed=yes
    fi
    if [[ ! -f "$file" || -L "$file" || "$allowed" != yes ]]; then
      printf '%s\n' "$rel"
    fi
  done)
  if [[ -n "$invalid" ]]; then
    fail "$id: review directory contains non-canonical, nested, or symlink receipt content"
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
      if [[ "$i" -gt 0 ]] && protocol_has_execution_state "$request_protocol" &&
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
    elif [[ -e "$request" || -e "$verdict" ||
            -e "$directory/round-${round}-default-off-evidence.md" ||
            -e "$directory/round-${round}-explicit-on-evidence.md" ]]; then
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

append_retask_immutable_artifact_files() {
  local manifest="$1" path
  printf '%s\t%s\n' \
    "$GIT_FEATURE_REL/spec.md" "$SPEC" \
    "$GIT_FEATURE_REL/plan.md" "$PLAN" >> "$manifest"
  for path in research.md data-model.md quickstart.md; do
    [[ -f "$FEATURE_DIR/$path" ]] && printf '%s\t%s\n' "$GIT_FEATURE_REL/$path" "$FEATURE_DIR/$path" >> "$manifest"
  done
  if [[ -d "$FEATURE_DIR/contracts" ]]; then
    while IFS= read -r path; do
      [[ -f "$path" ]] || continue
      printf '%s\t%s\n' "$GIT_FEATURE_REL/${path#"$FEATURE_DIR"/}" "$path" >> "$manifest"
    done < <(find "$FEATURE_DIR/contracts" -type f -print)
  fi
  if [[ -d "$FEATURE_DIR/.gatespec/revalidations" ]]; then
    while IFS= read -r path; do
      [[ -f "$path" ]] || continue
      printf '%s\t%s\n' "$GIT_FEATURE_REL/${path#"$FEATURE_DIR"/}" "$path" >> "$manifest"
    done < <(find "$FEATURE_DIR/.gatespec/revalidations" -type f -print)
  fi
  if [[ -f "$SOURCE_ENTRY" ]]; then
    append_review_chain_files REV-SOURCE "$manifest" || return 1
  fi
}

retask_source_has_symlink_component() {
  local source="$1" relative component current="$FEATURE_DIR" old_ifs
  case "$source" in
    "$FEATURE_DIR"/*) relative=${source#"$FEATURE_DIR"/} ;;
    *) return 0 ;;
  esac
  old_ifs=$IFS
  IFS='/'
  for component in $relative; do
    current="$current/$component"
    if [[ -L "$current" ]]; then
      IFS=$old_ifs
      return 0
    fi
  done
  IFS=$old_ifs
  return 1
}

check_retask_archive_source_files() {
  local source rel bad=0 sources="$TMP_DIR/retask-archive-sources"
  local index_snapshot="$TMP_DIR/retask-archive-index-snapshot" index_tag
  : > "$sources"
  printf '%s\n' "$TASKS" >> "$sources"
  if [[ ! -d "$FEATURE_DIR/.gatespec/reviews/REV-TASKS" ||
        -L "$FEATURE_DIR/.gatespec/reviews/REV-TASKS" ]]; then
    fail "retask eligibility: REV-TASKS archive source must be a regular directory"
    bad=1
  else
    find "$FEATURE_DIR/.gatespec/reviews/REV-TASKS" -mindepth 1 -maxdepth 1 -print \
      >> "$sources"
  fi
  if protocol_has_execution_state "${ACTIVE_REVIEW_PROTOCOL:-1}"; then
    printf '%s\n' "$EXECUTION_STATE" >> "$sources"
    [[ -e "$IA_FILE" || -L "$IA_FILE" ]] && printf '%s\n' "$IA_FILE" >> "$sources"
  fi
  while IFS= read -r source; do
    [[ -n "$source" ]] || continue
    if [[ ! -f "$source" || -L "$source" ]] || retask_source_has_symlink_component "$source"; then
      fail "retask eligibility: archive source '${source#"$FEATURE_DIR"/}' and every ancestor must be regular and non-symlink"
      bad=1
      continue
    fi
    rel="$GIT_FEATURE_REL/${source#"$FEATURE_DIR"/}"
    if git -C "$GIT_ROOT" ls-files --stage -- "$rel" | grep -q .; then
      index_tag=$(git -C "$GIT_ROOT" -c core.quotepath=false ls-files -v -- "$rel" | sed -n '1s/^\(.\).*/\1/p')
      case "$index_tag" in
        S|[a-z])
          fail "retask eligibility: archive source '$rel' must not carry assume-unchanged or skip-worktree"
          bad=1
          ;;
      esac
      if ! git -C "$GIT_ROOT" show ":$rel" > "$index_snapshot" 2>/dev/null ||
         ! cmp -s "$index_snapshot" "$source"; then
        fail "retask eligibility: index and working-tree bytes differ for archive source '$rel'"
        bad=1
      fi
    elif git -C "$GIT_ROOT" check-ignore -q -- "$rel" 2>/dev/null; then
      fail "retask eligibility: untracked archive source '$rel' must not be ignored"
      bad=1
    fi
  done < "$sources"
  [[ "$bad" -eq 0 ]] && pass "retask eligibility: every archive source is regular, non-symlink, and recoverable"
}

check_retask_worktree_paths() {
  local entry state path bad=0 index_snapshot="$TMP_DIR/retask-index-snapshot"
  while IFS= read -r -d '' entry; do
    state=${entry:0:2}
    path=${entry:3}
    if [[ "$state" == *R* || "$state" == *C* ]]; then
      fail "retask eligibility: renamed/copied worktree paths are not allowed"
      bad=1
      continue
    fi
    if [[ "$state" == *D* ]]; then
      fail "retask eligibility: archive source '$path' must not be deleted"
      bad=1
      continue
    fi
    case "$path" in
      "$GIT_FEATURE_REL/tasks.md"|"$GIT_FEATURE_REL/.gatespec/reviews/REV-TASKS/"*) ;;
      "$GIT_FEATURE_REL/.gatespec/execution-state.md"|"$GIT_FEATURE_REL/.gatespec/implementation-adjustments.md")
        if ! protocol_has_execution_state "${ACTIVE_REVIEW_PROTOCOL:-1}"; then
          fail "retask eligibility: Protocol v1 must not have execution-state/IA worktree changes"
          bad=1
        fi
        ;;
      *)
        fail "retask eligibility: unrelated dirty or untracked path '$path'"
        bad=1
        continue
        ;;
    esac
    if git -C "$GIT_ROOT" ls-files --stage -- "$path" | grep -q .; then
      if [[ ! -f "$GIT_ROOT/$path" ]] ||
         ! git -C "$GIT_ROOT" show ":$path" > "$index_snapshot" 2>/dev/null ||
         ! cmp -s "$index_snapshot" "$GIT_ROOT/$path"; then
        fail "retask eligibility: index and working-tree bytes differ for archive source '$path'"
        bad=1
      fi
    fi
  done < <(git -C "$GIT_ROOT" -c core.quotepath=false status --porcelain=v1 -z --untracked-files=all 2>/dev/null)
  [[ "$bad" -eq 0 ]] && pass "retask eligibility: worktree changes are confined to replaceable task-review state"
}

check_retask_hidden_index_paths() {
  local entry tag path source bad=0 hidden=0
  local index_snapshot="$TMP_DIR/retask-hidden-index-snapshot"
  while IFS= read -r -d '' entry; do
    tag=${entry:0:1}
    case "$tag" in
      S|[a-z]) ;;
      *) continue ;;
    esac
    hidden=$((hidden + 1))
    path=${entry:2}
    source="$GIT_ROOT/$path"
    if [[ ! -f "$source" || -L "$source" ]] ||
       ! git -C "$GIT_ROOT" show ":$path" > "$index_snapshot" 2>/dev/null ||
       ! cmp -s "$index_snapshot" "$source"; then
      fail "retask eligibility: index flag '$tag' hides working-tree drift or a non-regular path at '$path'"
      bad=1
    fi
  done < <(git -C "$GIT_ROOT" -c core.quotepath=false ls-files -v -z)
  if [[ "$bad" -eq 0 ]]; then
    if [[ "$hidden" -eq 0 ]]; then
      pass "retask eligibility: no assume-unchanged or skip-worktree path can hide worktree drift"
    else
      pass "retask eligibility: every index-flag-hidden path still matches its staged blob"
    fi
  fi
}

canonical_empty_ia_shape() {
  local file="$1" invalid
  invalid=$(awk '
    /^[[:space:]]*$/ {next}
    NR == 1 && $0 == "# GateSpec Implementation Adjustments" {next}
    /^- \*\*(Execution-Epoch|Source-Design-Content-SHA256)\*\*: `[^`]+`$/ {next}
    $0 == "## Adjustments" {next}
    $0 == "- None — no bounded implementation adjustment has been recorded." {next}
    {print}
  ' "$file")
  [[ -z "$invalid" ]] && awk '
    /^[[:space:]]*$/ {next}
    {
      n++
      if (n == 1 && $0 == "# GateSpec Implementation Adjustments") next
      if (n == 2 && $0 ~ /^- \*\*Execution-Epoch\*\*: `E[1-9][0-9]*`$/) next
      if (n == 3) {
        value=$0
        sub(/^- \*\*Source-Design-Content-SHA256\*\*: `/, "", value)
        sub(/`$/, "", value)
        if (length(value) == 64 && value !~ /[^0-9a-f]/) next
      }
      if (n == 4 && $0 == "## Adjustments") next
      if (n == 5 && $0 == "- None — no bounded implementation adjustment has been recorded.") next
      bad=1
    }
    END {exit bad || n != 5}
  ' "$file"
}

check_retask_historical_content() {
  local start="$1" include_start="${2:-no}" commits="$TMP_DIR/retask-history-content-commits"
  local commit tasks_blob="$TMP_DIR/retask-history-tasks-blob"
  local ia_blob="$TMP_DIR/retask-history-ia-blob" bad=0
  : > "$commits"
  [[ "$include_start" == yes ]] && printf '%s\n' "$start" >> "$commits"
  git -C "$GIT_ROOT" rev-list --reverse "$start..HEAD" >> "$commits" 2>/dev/null || {
    fail "retask eligibility: cannot inspect committed task/IA content history"
    return
  }
  while IFS= read -r commit; do
    [[ -n "$commit" ]] || continue
    if git -C "$GIT_ROOT" show "$commit:$GIT_FEATURE_REL/tasks.md" > "$tasks_blob" 2>/dev/null &&
       grep -Eq '^- \[[xX]\] T[0-9][0-9][0-9]([[:space:]]|$)' "$tasks_blob"; then
      fail "retask eligibility: commit $commit records completed task evidence"
      bad=1
      break
    fi
    if protocol_has_execution_state "${ACTIVE_REVIEW_PROTOCOL:-1}" &&
       git -C "$GIT_ROOT" show "$commit:$GIT_FEATURE_REL/.gatespec/implementation-adjustments.md" \
         > "$ia_blob" 2>/dev/null && ! canonical_empty_ia_shape "$ia_blob"; then
      fail "retask eligibility: commit $commit records nonempty or non-canonical IA evidence"
      bad=1
      break
    fi
  done < "$commits"
  [[ "$bad" -eq 0 ]] && pass "retask eligibility: committed task and IA history contains no implementation-start evidence"
}

check_v2_task_handoff_snapshot() {
  local handoff="$CURRENT_TASK_HANDOFF" review="$FEATURE_DIR/.gatespec/reviews/REV-TASKS"
  local round00="$review/round-00-request.md" manifest="$TMP_DIR/retask-handoff-manifest"
  local blob="$TMP_DIR/retask-handoff-blob" tasks_blob="$TMP_DIR/retask-handoff-tasks"
  local state_blob="$TMP_DIR/retask-handoff-state" ia_blob="$TMP_DIR/retask-handoff-ia"
  local rel current invalid expected_protocol expected_tasks expected_epoch expected_source expected_ia expected_preserved bad=0
  : > "$manifest"
  if ! append_retask_immutable_artifact_files "$manifest"; then
    fail "retask eligibility: cannot enumerate immutable Task-Handoff snapshot files"
    return
  fi
  while IFS=$'\t' read -r rel current; do
    [[ -n "$rel" ]] || continue
    if ! git -C "$GIT_ROOT" show "$handoff:$rel" > "$blob" 2>/dev/null || ! cmp -s "$blob" "$current"; then
      fail "retask eligibility: Task-Handoff snapshot does not contain current immutable blob '$rel'"
      bad=1
    fi
  done < "$manifest"
  expected_tasks=$(markdown_field_value "$round00" 'Tasks-Definition-SHA256')
  expected_protocol=$(markdown_field_value "$round00" 'Protocol-Version')
  if ! git -C "$GIT_ROOT" show "$handoff:$GIT_FEATURE_REL/tasks.md" > "$tasks_blob" 2>/dev/null ||
     [[ $(normalized_tasks_hash "$tasks_blob") != "$expected_tasks" ]]; then
    fail "retask eligibility: Task-Handoff tasks snapshot does not bind round-00 Tasks-Definition-SHA256"
    bad=1
  fi
  expected_epoch=$(markdown_field_value "$round00" 'Execution-Epoch')
  expected_source=$(markdown_field_value "$round00" 'Source-Design-Content-SHA256')
  expected_ia=$(markdown_field_value "$round00" 'Implementation-Adjustments-SHA256')
  expected_preserved=$(markdown_field_value "$round00" 'Preserved-Reviews-SHA256')
  if ! git -C "$GIT_ROOT" show "$handoff:$GIT_FEATURE_REL/.gatespec/execution-state.md" \
      > "$state_blob" 2>/dev/null; then
    fail "retask eligibility: Task-Handoff snapshot is missing pending execution-state.md"
    bad=1
  else
    invalid=$(awk '
      /^[[:space:]]*$/ {next}
      NR == 1 && $0 == "# GateSpec Execution State" {next}
      /^- \*\*(Protocol-Version|Execution-Epoch|Original-Implementation-Baseline|Task-Handoff-Commit|Source-Design-Content-SHA256|Preserved-Reviews-SHA256|Execution-State-SHA256)\*\*: `[^`]+`$/ {next}
      {print NR ":" $0}
    ' "$state_blob")
    [[ -z "$invalid" ]] || { fail "retask eligibility: pending Task-Handoff execution state is non-canonical"; bad=1; }
    [[ $(sed -n '1p' "$state_blob") == '# GateSpec Execution State' &&
       $(grep -cFx '# GateSpec Execution State' "$state_blob" || true) -eq 1 ]] || {
      fail "retask eligibility: pending Task-Handoff execution state requires its exact line-1 title"; bad=1;
    }
    check_ordered_fields "$state_blob" 'Task-Handoff execution-state snapshot' \
      'Protocol-Version' 'Execution-Epoch' 'Original-Implementation-Baseline' 'Task-Handoff-Commit' \
      'Source-Design-Content-SHA256' 'Preserved-Reviews-SHA256' 'Execution-State-SHA256'
    [[ $(markdown_field_value "$state_blob" 'Protocol-Version') == "$expected_protocol" &&
       $(markdown_field_value "$state_blob" 'Execution-Epoch') == "$expected_epoch" &&
       $(markdown_field_value "$state_blob" 'Original-Implementation-Baseline') == "$CURRENT_ORIGINAL_BASELINE" &&
       $(markdown_field_value "$state_blob" 'Task-Handoff-Commit') == pending &&
       $(markdown_field_value "$state_blob" 'Source-Design-Content-SHA256') == "$expected_source" &&
       $(markdown_field_value "$state_blob" 'Preserved-Reviews-SHA256') == "$expected_preserved" ]] || {
      fail "retask eligibility: pending Task-Handoff execution state does not bind round-00/current immutable state"; bad=1;
    }
    check_self_hash "$state_blob" 'Execution-State-SHA256' 'Task-Handoff execution-state snapshot'
  fi
  if [[ "$expected_source" == not-applicable ]]; then
    [[ "$expected_ia" == not-applicable ]] || { fail "retask eligibility: no-Source round-00 IA must be not-applicable"; bad=1; }
    if git -C "$GIT_ROOT" cat-file -e "$handoff:$GIT_FEATURE_REL/.gatespec/implementation-adjustments.md" 2>/dev/null; then
      fail "retask eligibility: no-Source Task-Handoff must not contain implementation-adjustments.md"
      bad=1
    fi
  elif ! git -C "$GIT_ROOT" show "$handoff:$GIT_FEATURE_REL/.gatespec/implementation-adjustments.md" \
      > "$ia_blob" 2>/dev/null; then
    fail "retask eligibility: Source Task-Handoff snapshot is missing empty IA"
    bad=1
  else
    check_canonical_empty_ia "$ia_blob" 'Task-Handoff IA snapshot' "$expected_epoch" "$expected_source" || bad=1
    [[ $(file_hash "$ia_blob") == "$expected_ia" ]] || {
      fail "retask eligibility: Task-Handoff IA raw hash does not match round-00 request"; bad=1;
    }
  fi
  [[ "$bad" -eq 0 ]] && pass "retask eligibility: Task-Handoff tree binds immutable artifacts, round-00 tasks, pending state, and empty IA"
}

check_retask_product_delta() {
  local kind="$1" boundary='' scan_start='' seal_rel request_rel additions parent_fields path bad=0
  local paths="$TMP_DIR/retask-committed-delta" raw_paths="$TMP_DIR/retask-committed-delta-raw"
  local allowed="$TMP_DIR/retask-committed-allowlist"
  local manifest="$TMP_DIR/retask-product-immutable" addition_count plan_rel plan_commit plan_additions
  local boundary_fields boundary_paths="$TMP_DIR/retask-boundary-paths" include_scan_start=no
  if protocol_has_execution_state "${ACTIVE_REVIEW_PROTOCOL:-1}"; then
    boundary=$CURRENT_TASK_HANDOFF
    scan_start=$CURRENT_ORIGINAL_BASELINE
  elif [[ "$kind" == pass ]]; then
    seal_rel="$GIT_FEATURE_REL/.gatespec/reviews/REV-TASKS/seal.md"
    boundary=$(git -C "$GIT_ROOT" log -1 --format=%H -- "$seal_rel" 2>/dev/null || true)
    [[ -n "$boundary" ]] || { fail "retask eligibility: current PASS seal has no tracked handoff commit"; return; }
  else
    request_rel="$GIT_FEATURE_REL/.gatespec/reviews/REV-TASKS/round-00-request.md"
    additions=$(git -C "$GIT_ROOT" log --diff-filter=A --format=%H -- "$request_rel" 2>/dev/null || true)
    addition_count=$(printf '%s\n' "$additions" | awk 'NF {n++} END {print n+0}')
    if [[ "$addition_count" -eq 1 ]]; then
      parent_fields=$(git -C "$GIT_ROOT" rev-list --parents -n 1 "$additions" 2>/dev/null || true)
      if [[ $(printf '%s\n' "$parent_fields" | awk '{print NF+0}') -ne 2 ]]; then
        fail "retask eligibility: v1 round-00 first-add commit must have one provable parent"
        return
      fi
      boundary=$(printf '%s\n' "$parent_fields" | awk '{print $2}')
    elif [[ "$addition_count" -eq 0 ]]; then
      if git -C "$GIT_ROOT" cat-file -e "HEAD:$GIT_FEATURE_REL/tasks.md" 2>/dev/null; then
        fail "retask eligibility: v1 no-add fallback requires tasks and the complete review chain to be wholly untracked"
        return
      fi
      while IFS= read -r file; do
        path="$GIT_FEATURE_REL/${file#"$FEATURE_DIR"/}"
        if git -C "$GIT_ROOT" cat-file -e "HEAD:$path" 2>/dev/null; then
          fail "retask eligibility: v1 no-add fallback found tracked review path '$path'"
          return
        fi
      done < <(find "$FEATURE_DIR/.gatespec/reviews/REV-TASKS" -type f -print)
      boundary=$(git -C "$GIT_ROOT" rev-parse HEAD 2>/dev/null || true)
    else
      fail "retask eligibility: v1 round-00 request has ambiguous first-add history"
      return
    fi
  fi
  if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 1 ]]; then
    plan_rel="$GIT_FEATURE_REL/plan.md"
    plan_additions=$(git -C "$GIT_ROOT" log --diff-filter=A --format=%H -- "$plan_rel" 2>/dev/null || true)
    if [[ $(printf '%s\n' "$plan_additions" | awk 'NF {n++} END {print n+0}') -ne 1 ]]; then
      fail "retask eligibility: v1 requires one unambiguous first-add commit for plan.md"
      return
    fi
    plan_commit=$(printf '%s\n' "$plan_additions" | awk 'NF {print; exit}')
    parent_fields=$(git -C "$GIT_ROOT" rev-list --parents -n 1 "$plan_commit" 2>/dev/null || true)
    case $(printf '%s\n' "$parent_fields" | awk '{print NF+0}') in
      1) scan_start=$plan_commit; include_scan_start=yes ;;
      2) scan_start=$(printf '%s\n' "$parent_fields" | awk '{print $2}') ;;
      *) fail "retask eligibility: v1 first Plan commit must be a root or one-parent commit"; return ;;
    esac
  fi
  if ! is_git_oid "$boundary" || ! git -C "$GIT_ROOT" merge-base --is-ancestor "$boundary" HEAD 2>/dev/null ||
     ! is_git_oid "$scan_start" || ! git -C "$GIT_ROOT" merge-base --is-ancestor "$scan_start" HEAD 2>/dev/null; then
    fail "retask eligibility: pre-implementation boundary must be a HEAD ancestor"
    return
  fi
  if protocol_has_execution_state "${ACTIVE_REVIEW_PROTOCOL:-1}"; then
    boundary_fields=$(git -C "$GIT_ROOT" rev-list --parents -n 1 "$boundary" 2>/dev/null || true)
    if [[ $(printf '%s\n' "$boundary_fields" | awk '{print NF+0}') -ne 2 ]]; then
      fail "retask eligibility: Protocol v2/v3 Task-Handoff commit must have exactly one parent"
      return
    fi
    : > "$manifest"
    append_retask_immutable_artifact_files "$manifest" || true
    cut -f1 "$manifest" > "$allowed"
    printf '%s\n' \
      "$GIT_FEATURE_REL/tasks.md" \
      "$GIT_FEATURE_REL/.gatespec/execution-state.md" \
      "$GIT_FEATURE_REL/.gatespec/implementation-adjustments.md" >> "$allowed"
    LC_ALL=C sort -u -o "$allowed" "$allowed"
    if ! git -C "$GIT_ROOT" -c core.quotepath=false diff-tree --root --no-commit-id \
        --name-only -r "$boundary" > "$boundary_paths" 2>/dev/null; then
      fail "retask eligibility: cannot inspect the Protocol v2/v3 Task-Handoff commit"
      return
    fi
    while IFS= read -r path; do
      [[ -n "$path" ]] || continue
      if ! grep -Fqx -- "$path" "$allowed"; then
        fail "retask eligibility: Protocol v2/v3 Task-Handoff commit contains product or unknown path '$path'"
        bad=1
      fi
    done < "$boundary_paths"
    check_v2_task_handoff_snapshot
  fi
  if git -C "$GIT_ROOT" rev-list --merges "$scan_start..HEAD" 2>/dev/null | grep -q .; then
    fail "retask eligibility: pre-implementation evidence history must be linear and contain no merge commit"
    return
  fi
  if ! git -C "$GIT_ROOT" -c core.quotepath=false log --format= --name-only --no-renames \
      "$scan_start..HEAD" > "$raw_paths" 2>/dev/null; then
    fail "retask eligibility: cannot inspect every committed path after the pre-implementation baseline"
    return
  fi
  if [[ "$include_scan_start" == yes ]] &&
     ! git -C "$GIT_ROOT" -c core.quotepath=false diff-tree --root --no-commit-id \
       --name-only -r "$scan_start" >> "$raw_paths" 2>/dev/null; then
    fail "retask eligibility: cannot inspect the root Plan commit"
    return
  fi
  awk 'NF' "$raw_paths" | LC_ALL=C sort -u > "$paths"
  while IFS= read -r path; do
    [[ -n "$path" ]] || continue
    if protocol_has_execution_state "${ACTIVE_REVIEW_PROTOCOL:-1}"; then
      case "$path" in
        "$GIT_FEATURE_REL/spec.md"|"$GIT_FEATURE_REL/plan.md"|"$GIT_FEATURE_REL/tasks.md"|\
        "$GIT_FEATURE_REL/research.md"|"$GIT_FEATURE_REL/data-model.md"|"$GIT_FEATURE_REL/quickstart.md"|\
        "$GIT_FEATURE_REL/requirements-traceability.md"|\
        "$GIT_FEATURE_REL/contracts/"*|"$GIT_FEATURE_REL/checklists/"*|\
        "$GIT_FEATURE_REL/validation/"*|"$GIT_FEATURE_REL/archive/"*|\
        "$GIT_FEATURE_REL/.gatespec/archive/"*|\
        "$GIT_FEATURE_REL/.gatespec/reviews/REV-TASKS/"*|\
        "$GIT_FEATURE_REL/.gatespec/reviews/REV-SOURCE/"*|\
        "$GIT_FEATURE_REL/.gatespec/revalidations/"*|\
        "$GIT_FEATURE_REL/.gatespec/execution-state.md"|\
        "$GIT_FEATURE_REL/.gatespec/implementation-adjustments.md") ;;
        *) fail "retask eligibility: Protocol v2/v3 product or unknown evidence path '$path' changed after Original Baseline"; bad=1 ;;
      esac
    else
      case "$path" in
        "$GIT_FEATURE_REL/spec.md"|"$GIT_FEATURE_REL/plan.md"|"$GIT_FEATURE_REL/tasks.md"|\
        "$GIT_FEATURE_REL/research.md"|"$GIT_FEATURE_REL/data-model.md"|"$GIT_FEATURE_REL/quickstart.md"|\
        "$GIT_FEATURE_REL/requirements-traceability.md"|\
        "$GIT_FEATURE_REL/contracts/"*|"$GIT_FEATURE_REL/checklists/"*|\
        "$GIT_FEATURE_REL/validation/"*|"$GIT_FEATURE_REL/archive/"*|\
        "$GIT_FEATURE_REL/.gatespec/archive/"*|\
        "$GIT_FEATURE_REL/.gatespec/reviews/REV-TASKS/"*) ;;
        *) fail "retask eligibility: v1 product or unknown evidence path '$path' changed after the first Plan boundary"; bad=1 ;;
      esac
    fi
  done < "$paths"
  check_retask_historical_content "$scan_start" "$include_scan_start"
  [[ "$bad" -eq 0 ]] && pass "retask eligibility: no committed product delta exists after the reproducible pre-implementation baseline"
}

check_retask_eligibility() {
  local before="$FAILURES" review="$FEATURE_DIR/.gatespec/reviews/REV-TASKS" kind protocol
  local ref review_entry review_name latest_seal head seal_rel current_ia_hash current_source_hash
  local manifest="$TMP_DIR/retask-immutable-files"
  echo ""
  echo "Retask Eligibility Gate: $FEATURE_DIR"
  initialize_review_hashes
  if [[ -z "$GIT_ROOT" ]] || ! resolve_git_feature_paths; then
    fail "retask eligibility: feature must be inside a Git worktree"
    return
  fi
  if [[ -L "$FEATURE_DIR" ]]; then
    fail "retask eligibility: feature directory itself must not be a symlink"
  fi
  if [[ ! -f "$SOURCE_ENTRY" ]]; then
    if [[ -d "$SOURCE_SHARDS" ]] && find "$SOURCE_SHARDS" -type f -print -quit | grep -q .; then
      fail "retask eligibility: Source shards exist without contracts/source-design.md"
    fi
    if grep -E '^\*\*Source-Design-Content-SHA256\*\*: `[^`]+`$' "$TASKS" 2>/dev/null |
       grep -Fv '`not-applicable`' >/dev/null 2>&1; then
      fail "retask eligibility: tasks.md has an orphan Source Design binding"
    fi
  fi
  ref=$(git -C "$GIT_ROOT" symbolic-ref -q HEAD 2>/dev/null || true)
  case "$ref" in refs/heads/*) pass "retask eligibility: HEAD is attached to a local branch" ;;
    *) fail "retask eligibility: HEAD must be attached to a local branch" ;; esac

  if protocol_has_execution_state "${ACTIVE_REVIEW_PROTOCOL:-1}"; then
    check_execution_state downstream
    [[ "$FAILURES" -eq "$before" ]] && check_implementation_adjustments yes
  else
    [[ ! -e "$EXECUTION_STATE" ]] || fail "retask eligibility: Protocol v1 must not create execution-state.md"
    [[ ! -e "$IA_FILE" ]] || fail "retask eligibility: Protocol v1 must not create implementation-adjustments.md"
  fi

  if [[ -f "$review/seal.md" ]]; then
    kind=pass
    check_review_chain REV-TASKS TASKS
    [[ "$FAILURES" -eq "$before" ]] && check_task_review_git_state
    if [[ "${ACTIVE_REVIEW_PROTOCOL:-1}" == 1 ]]; then
      seal_rel="$GIT_FEATURE_REL/.gatespec/reviews/REV-TASKS/seal.md"
      latest_seal=$(git -C "$GIT_ROOT" log -1 --format=%H -- "$seal_rel" 2>/dev/null || true)
      head=$(git -C "$GIT_ROOT" rev-parse HEAD 2>/dev/null || true)
      if [[ -n "$latest_seal" && "$latest_seal" == "$head" ]]; then
        check_baseline_task_seal "$head"
      else
        fail "retask eligibility: v1 PASS seal latest-touch commit must be HEAD"
      fi
    fi
  else
    kind=blocked
    : > "$TMP_DIR/required-prior-findings"
    HISTORICAL_FINDING_SERIAL=0
    check_historical_task_chain "$review" ''
    protocol=$HISTORICAL_CHAIN_PROTOCOL
    if [[ "$HISTORICAL_CHAIN_TERMINAL_ROUND" != 02 || "$HISTORICAL_CHAIN_TERMINAL_STATUS" != BLOCKED ]]; then
      fail "retask eligibility: an unsealed task review must exhaust round 02 with BLOCKED"
    fi
    [[ "$HISTORICAL_CHAIN_BASIS_MATCH" == yes ]] || fail "retask eligibility: BLOCKED task review artifact basis is stale"
    [[ "$protocol" == "${ACTIVE_REVIEW_PROTOCOL:-1}" ]] || fail "retask eligibility: BLOCKED chain protocol is stale"
    [[ "$HISTORICAL_CHAIN_TERMINAL_TASKS_HASH" == "$CURRENT_TASKS_HASH" ]] ||
      fail "retask eligibility: terminal BLOCKED request does not bind the current tasks definition"
    if protocol_has_execution_state "$protocol"; then
      if [[ -f "$SOURCE_ENTRY" ]]; then
        current_source_hash=$(source_design_content_hash) || current_source_hash=''
        current_ia_hash=$(file_hash "$IA_FILE") || current_ia_hash=''
      else
        current_source_hash=not-applicable
        current_ia_hash=not-applicable
      fi
      if [[ "$HISTORICAL_CHAIN_TERMINAL_EPOCH" != "${CURRENT_EXECUTION_EPOCH:-}" ||
            "$HISTORICAL_CHAIN_TERMINAL_SOURCE_HASH" != "$current_source_hash" ||
            "$HISTORICAL_CHAIN_TERMINAL_IA_HASH" != "$current_ia_hash" ||
            "$HISTORICAL_CHAIN_TERMINAL_HANDOFF" != "${CURRENT_TASK_HANDOFF:-}" ||
            "$HISTORICAL_CHAIN_TERMINAL_PRESERVED" != "${CURRENT_PRESERVED_HASH:-}" ]]; then
        fail "retask eligibility: terminal BLOCKED request does not bind current Protocol v2/v3 epoch, Source, IA, handoff, and preserved reviews"
      fi
    fi
  fi

  # Retask archives are part of the eligibility proof even when legacy tasks
  # predate Closure tables. Revalidating them here prevents a preflight PASS
  # followed by a guaranteed post-regeneration Closure failure.
  collect_prior_review_findings
  if protocol_has_execution_state "${ACTIVE_REVIEW_PROTOCOL:-1}" && [[ -n "${CURRENT_EXECUTION_EPOCH:-}" &&
        -n "${CURRENT_ORIGINAL_BASELINE:-}" ]]; then
    check_v2_execution_history_continuity
  fi

  if grep -Eq '^- \[[xX]\] T[0-9][0-9][0-9]([[:space:]]|$)' "$TASKS"; then
    fail "retask eligibility: every task checkbox must still be unchecked"
  else
    pass "retask eligibility: no task execution progress is recorded"
  fi
  if [[ -d "$FEATURE_DIR/.gatespec/reviews" ]]; then
    while IFS= read -r review_entry; do
      review_name=${review_entry##*/}
      case "$review_name" in
        REV-TASKS) [[ -d "$review_entry" ]] || fail "retask eligibility: REV-TASKS must be a review directory" ;;
        REV-SOURCE)
          if [[ ! -f "$SOURCE_ENTRY" || ! -d "$review_entry" ]]; then
            fail "retask eligibility: REV-SOURCE is allowed only as the enabled Source review directory"
          fi
          ;;
        *) fail "retask eligibility: forbidden non-task review entry '$review_name' already exists" ;;
      esac
    done < <(find "$FEATURE_DIR/.gatespec/reviews" -mindepth 1 -maxdepth 1 -print)
  fi
  [[ ! -e "$ACCEPTANCE" ]] || fail "retask eligibility: acceptance metadata already exists"
  if [[ -d "$FEATURE_DIR/checklists" ]] && grep -R -nE '^- \[ \]' "$FEATURE_DIR/checklists" >/dev/null 2>&1; then
    fail "retask eligibility: every checklist item must be complete"
  fi

  : > "$manifest"
  if ! append_retask_immutable_artifact_files "$manifest"; then
    fail "retask eligibility: cannot enumerate approved immutable artifacts"
  elif check_head_tracked_manifest "$manifest" 'retask immutable basis'; then
    pass "retask eligibility: approved basis and Source/revalidation evidence match tracked HEAD"
  fi
  check_retask_worktree_paths
  check_retask_hidden_index_paths
  check_retask_archive_source_files
  check_retask_product_delta "$kind"
  [[ "$FAILURES" -eq "$before" ]] && pass "retask eligibility: replacement is proven pre-implementation and archive-safe"
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
  if [[ -s "$TMP_DIR/prior-closure-archive-files" ]]; then
    cat "$TMP_DIR/prior-closure-archive-files" >> "$manifest"
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
    if [[ "$id" == REV-FINAL && $(markdown_field_value "$request" 'Protocol-Version') == 3 &&
          $(markdown_field_value "$request" 'Test-Control-Mode') == isolated ]]; then
      printf '%s\t%s\n' \
        "$prefix/round-${current}-default-off-evidence.md" "$directory/round-${current}-default-off-evidence.md" \
        "$prefix/round-${current}-explicit-on-evidence.md" "$directory/round-${current}-explicit-on-evidence.md" \
        >> "$manifest"
    fi
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
  if [[ -s "$TMP_DIR/prior-closure-archive-files" ]]; then
    cut -f1 "$TMP_DIR/prior-closure-archive-files" >> "$allowed"
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
        if [[ "$MODE" != acceptance ]] && ! tracked_legacy_acceptance_exists; then
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
      if [[ "$id" == 'REV-FINAL' ]] && protocol_has_execution_state "${ACTIVE_REVIEW_PROTOCOL:-1}" && [[ "$CHAIN_BASE" != "$CURRENT_ORIGINAL_BASELINE" ]]; then
        fail "$id: Protocol v2/v3 Base-Commit must equal Original-Implementation-Baseline"
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
    if protocol_has_execution_state "${ACTIVE_REVIEW_PROTOCOL:-1}" && [[ -f "$SOURCE_ENTRY" && -n "$selected_subject" ]]; then
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
  local tc_mode tc_closure tc_manifest tc_default tc_explicit label
  local final_dir="$FEATURE_DIR/.gatespec/reviews/REV-FINAL" seal="$FEATURE_DIR/.gatespec/reviews/REV-FINAL/seal.md"
  local round request head parent latest seal_rel acceptance_rel changed parent_fields dirty invalid bad=0
  echo ""
  echo "Implementation Acceptance Gate: $ACCEPTANCE"
  if [[ ! -f "$ACCEPTANCE" ]]; then fail "$context: explicit final user acceptance is missing"; return; fi
  invalid=$(awk '
    /^[[:space:]]*$/ {next}
    NR == 1 && $0 == "# GateSpec Implementation Acceptance" {next}
    /^- \*\*(Protocol-Version|Status|Accepted-At|Spec-Content-SHA256|Plan-Content-SHA256|Design-Attachments-SHA256|Tasks-Definition-SHA256|Test-Control-Mode|Test-Control-Closure-SHA256|Test-Control-Subject-Manifest-SHA256|Default-OFF-Evidence-SHA256|Explicit-ON-Evidence-SHA256|Execution-Epoch|Source-Design-Content-SHA256|Implementation-Adjustments-SHA256|Original-Implementation-Baseline|Final-Subject-Commit|REV-FINAL-Seal-SHA256|Final-Review-Commit|Final-Delta-SHA256|Acceptance-SHA256)\*\*: `[^`]+`$/ {next}
    {print NR ":" $0}
  ' "$ACCEPTANCE")
  [[ -z "$invalid" ]] || { fail "$context: only the canonical acceptance fields are allowed"; bad=1; }
  protocol=$(markdown_field_value "$ACCEPTANCE" 'Protocol-Version')
  if [[ "$protocol" == 3 ]]; then
    check_ordered_fields "$ACCEPTANCE" "$context" \
      'Protocol-Version' 'Status' 'Accepted-At' 'Spec-Content-SHA256' 'Plan-Content-SHA256' \
      'Design-Attachments-SHA256' 'Tasks-Definition-SHA256' 'Test-Control-Mode' \
      'Test-Control-Closure-SHA256' 'Test-Control-Subject-Manifest-SHA256' \
      'Default-OFF-Evidence-SHA256' 'Explicit-ON-Evidence-SHA256' 'Execution-Epoch' \
      'Source-Design-Content-SHA256' 'Implementation-Adjustments-SHA256' \
      'Original-Implementation-Baseline' 'Final-Subject-Commit' 'REV-FINAL-Seal-SHA256' \
      'Final-Review-Commit' 'Final-Delta-SHA256' 'Acceptance-SHA256'
  else
    check_ordered_fields "$ACCEPTANCE" "$context" \
      'Protocol-Version' 'Status' 'Accepted-At' 'Spec-Content-SHA256' 'Plan-Content-SHA256' \
      'Design-Attachments-SHA256' 'Tasks-Definition-SHA256' 'Execution-Epoch' \
      'Source-Design-Content-SHA256' 'Implementation-Adjustments-SHA256' \
      'Original-Implementation-Baseline' 'Final-Subject-Commit' 'REV-FINAL-Seal-SHA256' \
      'Final-Review-Commit' 'Final-Delta-SHA256' 'Acceptance-SHA256'
  fi
  status=$(markdown_field_value "$ACCEPTANCE" 'Status')
  accepted_at=$(markdown_field_value "$ACCEPTANCE" 'Accepted-At')
  spec_hash=$(markdown_field_value "$ACCEPTANCE" 'Spec-Content-SHA256')
  plan_hash=$(markdown_field_value "$ACCEPTANCE" 'Plan-Content-SHA256')
  attachments_hash=$(markdown_field_value "$ACCEPTANCE" 'Design-Attachments-SHA256')
  tasks_hash=$(markdown_field_value "$ACCEPTANCE" 'Tasks-Definition-SHA256')
  tc_mode=$(markdown_field_value "$ACCEPTANCE" 'Test-Control-Mode')
  tc_closure=$(markdown_field_value "$ACCEPTANCE" 'Test-Control-Closure-SHA256')
  tc_manifest=$(markdown_field_value "$ACCEPTANCE" 'Test-Control-Subject-Manifest-SHA256')
  tc_default=$(markdown_field_value "$ACCEPTANCE" 'Default-OFF-Evidence-SHA256')
  tc_explicit=$(markdown_field_value "$ACCEPTANCE" 'Explicit-ON-Evidence-SHA256')
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
  if protocol_has_execution_state "$protocol"; then
    [[ "$epoch" == "$CURRENT_EXECUTION_EPOCH" ]] || { fail "$context: Execution Epoch is stale"; bad=1; }
    [[ "$original" == "$CURRENT_ORIGINAL_BASELINE" ]] || { fail "$context: Original Baseline is stale"; bad=1; }
    [[ "$source_hash" == $(markdown_field_value "$request" 'Source-Design-Content-SHA256') ]] || { fail "$context: Source hash does not match REV-FINAL"; bad=1; }
    [[ "$ia_hash" == $(markdown_field_value "$request" 'Implementation-Adjustments-SHA256') ]] || { fail "$context: IA hash does not match REV-FINAL"; bad=1; }
  else
    [[ "$epoch" == not-applicable && "$source_hash" == not-applicable && "$ia_hash" == not-applicable ]] || { fail "$context: Protocol v1 Source/IA/epoch fields must be not-applicable"; bad=1; }
    [[ "$original" == $(markdown_field_value "$request" 'Implementation-Baseline') ]] || { fail "$context: legacy Original Baseline must equal Implementation Baseline"; bad=1; }
  fi
  if [[ "$protocol" == 3 ]]; then
    for label in Test-Control-Mode Test-Control-Closure-SHA256 Test-Control-Subject-Manifest-SHA256 \
      Default-OFF-Evidence-SHA256 Explicit-ON-Evidence-SHA256; do
      [[ $(markdown_field_value "$ACCEPTANCE" "$label") == $(markdown_field_value "$request" "$label") ]] || {
        fail "$context: $label does not match REV-FINAL"; bad=1;
      }
    done
    [[ "$tc_mode" == "${CURRENT_TEST_CONTROL_MODE:-}" &&
       "$tc_closure" == "${CURRENT_TEST_CONTROL_CLOSURE_HASH:-}" ]] || {
      fail "$context: Test Control mode/closure is stale"; bad=1;
    }
  elif [[ -n "$tc_mode$tc_closure$tc_manifest$tc_default$tc_explicit" ]]; then
    fail "$context: legacy acceptance must not contain Protocol v3 Test Control fields"
    bad=1
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
  check_design_scope_boundary
  check_design_evidence_schema
  check_delivery_estimate "$PLAN" design
  if [[ "$LEGACY_PLAN_ESTIMATE" -eq 1 ]]; then
    if legacy_design_has_implementation_progress; then
      warn "plan.md: legacy Design remains valid because implementation progress already exists; final acceptance must still report actual delivery size"
    else
      fail "plan.md: legacy Approved Design has no Delivery Estimate and no implementation progress; run gatespec.plan --revise before tasks"
    fi
  fi
  check_decisions
  check_design_detailing
  check_implementation_review_contract
  check_test_control_policy
  check_plan_test_control_policy_exceptions
  check_template_remnants "$PLAN"
  check_gate_approval "$PLAN" 'Approved-Design'
  check_vague_words "$PLAN"
}

check_spec_gate
if [[ "$MODE" != 'spec' && "$FAILURES" -eq 0 ]]; then
  check_design_gate
fi
if [[ "${ACTIVE_REVIEW_PROTOCOL:-}" == 1 || "${ACTIVE_REVIEW_PROTOCOL:-}" == 2 ||
      "${ACTIVE_REVIEW_PROTOCOL:-}" == 3 ]]; then
  enforce_active_protocol_v3
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
    tasks-structure|task-review|retask-eligible|implementation-candidate|implementation-review|acceptance-candidate|acceptance)
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
if [[ "$MODE" == 'retask-eligible' && "$FAILURES" -eq 0 ]]; then
  check_tasks_structure optional
fi
if [[ "$MODE" == 'retask-eligible' && "$FAILURES" -eq 0 ]]; then
  check_retask_eligibility
fi
if [[ "$MODE" == 'task-review' && "$FAILURES" -eq 0 ]]; then
  if protocol_has_execution_state "${ACTIVE_REVIEW_PROTOCOL:-1}"; then
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
  if protocol_has_execution_state "${ACTIVE_REVIEW_PROTOCOL:-1}"; then
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
if [[ "$MODE" == 'acceptance-candidate' && "$FAILURES" -eq 0 ]]; then
  report_actual_delivery_metrics
fi
if [[ "$MODE" == 'acceptance-candidate' && "$FAILURES" -eq 0 ]] && tracked_legacy_acceptance_exists; then
  check_acceptance_gate
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
