#!/usr/bin/env bash
# shellcheck disable=SC2016 # Fixture Markdown uses literal backticks.
set -u

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SCRIPT="$ROOT/scripts/bash/check-gate.sh"
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gatespec-source-tests.XXXXXX") || exit 1
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM
PASS=0
FAIL=0

sha_stream() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi
}

file_hash() { sha_stream < "$1" | awk '{print $1}'; }
content_hash() { sed '/^## Gate Approval/,$d' "$1" | sha_stream | awk '{print $1}'; }

normalized_tasks_hash() {
  local file="$1" cr
  cr=$(printf '\r')
  sed -E -e "s/${cr}\$//" -e 's/^(- \[)[xX](\] T[0-9][0-9][0-9]([[:space:]]|$))/\1 \2/' "$file" \
    | sha_stream | awk '{print $1}'
}

changed_paths_hash() {
  local repo="$1" base="$2" subject="$3"
  git -C "$repo" diff --no-renames --name-only "$base" "$subject" | LC_ALL=C sort | sha_stream | awk '{print $1}'
}

final_delta_hash() {
  local repo="$1" original="$2" subject="$3"
  git -C "$repo" diff-tree --raw -z --no-abbrev --no-renames "$original" "$subject" | sha_stream | awk '{print $1}'
}

receipt_field() {
  local file="$1" label="$2"
  awk -v prefix="- **${label}**: \`" '
    index($0, prefix) == 1 && substr($0, length($0), 1) == "`" {
      print substr($0, length(prefix) + 1, length($0) - length(prefix) - 1); exit
    }
  ' "$file"
}

mark_task() {
  local file="$1" id="$2" tmp
  tmp="$file.tmp"
  sed -E "s/^- \[ \] (${id}([[:space:]]|$))/- [X] \1/" "$file" > "$tmp" && mv "$tmp" "$file"
}

write_v2_review() {
  local feature="$1" id="$2" scope="$3" baseline="$4" base="$5" subject="$6"
  local task_ids="$7" tests="$8" final_delta="$9" directory request verdict seal repo
  local spec_hash plan_hash attachments_hash tasks_hash source_content ia_hash changed request_hash verdict_hash
  directory="$feature/.gatespec/reviews/$id"
  repo=$(git -C "$feature" rev-parse --show-toplevel)
  request="$directory/round-00-request.md"
  verdict="$directory/round-00-verdict.md"
  seal="$directory/seal.md"
  mkdir -p "$directory"
  spec_hash=$(content_hash "$feature/spec.md")
  plan_hash=$(content_hash "$feature/plan.md")
  attachments_hash=$(printf '' | sha_stream | awk '{print $1}')
  tasks_hash=$(normalized_tasks_hash "$feature/tasks.md")
  if [[ -f "$feature/contracts/source-design.md" ]]; then
    source_content=$(source_hash "$feature" content)
    ia_hash=$(file_hash "$feature/.gatespec/implementation-adjustments.md")
  else
    source_content=not-applicable
    ia_hash=not-applicable
  fi
  if [[ "$scope" == TASKS ]]; then changed=not-applicable; else changed=$(changed_paths_hash "$repo" "$base" "$subject"); fi
  {
    printf '%s\n' '- **Protocol-Version**: `2`'
    printf -- '- **Review-ID**: `%s`\n' "$id"
    printf '%s\n' '- **Round**: `00`'
    printf -- '- **Scope**: `%s`\n' "$scope"
    printf -- '- **Spec-Content-SHA256**: `%s`\n' "$spec_hash"
    printf -- '- **Plan-Content-SHA256**: `%s`\n' "$plan_hash"
    printf -- '- **Design-Attachments-SHA256**: `%s`\n' "$attachments_hash"
    printf -- '- **Tasks-Definition-SHA256**: `%s`\n' "$tasks_hash"
    printf '%s\n' '- **Execution-Epoch**: `E1`'
    printf -- '- **Source-Design-Content-SHA256**: `%s`\n' "$source_content"
    printf -- '- **Implementation-Adjustments-SHA256**: `%s`\n' "$ia_hash"
    printf -- '- **Task-Handoff-Commit**: `%s`\n' "$HANDOFF"
    printf '%s\n' '- **Preserved-Reviews-SHA256**: `not-applicable`'
    printf -- '- **Implementation-Baseline**: `%s`\n' "$baseline"
    printf -- '- **Base-Commit**: `%s`\n' "$base"
    printf -- '- **Subject-Commit**: `%s`\n' "$subject"
    printf -- '- **Task-IDs**: `%s`\n' "$task_ids"
    printf -- '- **Changed-Paths-SHA256**: `%s`\n' "$changed"
    printf -- '- **Final-Delta-SHA256**: `%s`\n' "$final_delta"
    printf '%s\n\n' '- **Previous-Verdict-SHA256**: `none`'
    printf '%s\n\n' '## Required Tests'
    printf -- '- %s\n\n' "$tests"
    printf '%s\n' '- **Request-SHA256**: `pending`'
  } > "$request"
  self_hash "$request" 'Request-SHA256'
  request_hash=$(receipt_field "$request" 'Request-SHA256')
  {
    printf '%s\n' '- **Protocol-Version**: `2`'
    printf -- '- **Review-ID**: `%s`\n' "$id"
    printf '%s\n' '- **Round**: `00`'
    printf -- '- **Request-SHA256**: `%s`\n' "$request_hash"
    printf '%s\n' '- **Reviewer-Platform**: `codex`'
    printf -- '- **Reviewer-Context-ID**: `v2-%s-00`\n' "$id"
    printf '%s\n' '- **Isolation**: `fresh`' '- **Status**: `PASS`' '' '## Tests Run' ''
    if [[ "$scope" == TASKS ]]; then printf '%s\n' '- Not run — task-plan review'; else printf -- '- %s — exit 0 fixture\n' "$tests"; fi
    printf '%s\n' '' '## Blockers' '' '- None' '' '## Observations' '' '- Protocol v2 fixture is complete.' '' '## Limitations' '' '- Semantic freshness is adapter evidence.' '' '- **Verdict-SHA256**: `pending`'
  } > "$verdict"
  self_hash "$verdict" 'Verdict-SHA256'
  verdict_hash=$(receipt_field "$verdict" 'Verdict-SHA256')
  {
    printf '%s\n' '- **Protocol-Version**: `2`'
    printf -- '- **Review-ID**: `%s`\n' "$id"
    printf '%s\n' '- **Round**: `00`' '- **Status**: `PASS`'
    printf -- '- **Request-SHA256**: `%s`\n' "$request_hash"
    printf -- '- **Verdict-SHA256**: `%s`\n' "$verdict_hash"
    printf -- '- **Spec-Content-SHA256**: `%s`\n' "$spec_hash"
    printf -- '- **Plan-Content-SHA256**: `%s`\n' "$plan_hash"
    printf -- '- **Design-Attachments-SHA256**: `%s`\n' "$attachments_hash"
    printf -- '- **Tasks-Definition-SHA256**: `%s`\n' "$tasks_hash"
    printf '%s\n' '- **Execution-Epoch**: `E1`'
    printf -- '- **Source-Design-Content-SHA256**: `%s`\n' "$source_content"
    printf -- '- **Implementation-Adjustments-SHA256**: `%s`\n' "$ia_hash"
    printf -- '- **Task-Handoff-Commit**: `%s`\n' "$HANDOFF"
    printf '%s\n' '- **Preserved-Reviews-SHA256**: `not-applicable`'
    printf -- '- **Implementation-Baseline**: `%s`\n' "$baseline"
    printf -- '- **Base-Commit**: `%s`\n' "$base"
    printf -- '- **Subject-Commit**: `%s`\n' "$subject"
    printf -- '- **Final-Delta-SHA256**: `%s`\n' "$final_delta"
    printf '%s\n' '- **Sealed-At**: `2026-08-24T13:00:00Z`' '- **Seal-SHA256**: `pending`'
  } > "$seal"
  self_hash "$seal" 'Seal-SHA256'
}

self_hash() {
  local file="$1" label="$2" digest tmp
  tmp="$file.tmp"
  digest=$(sed "/^- \*\*${label}\*\*:/,\$d" "$file" | sha_stream | awk '{print $1}')
  awk -v label="$label" -v digest="$digest" '
    $0 ~ "^- \\*\\*" label "\\*\\*:" {print "- **" label "**: `" digest "`"; next}
    {print}
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

seal_gate() {
  local file="$1" digest tmp
  tmp="$file.tmp"
  digest=$(content_hash "$file")
  awk -v digest="$digest" '
    /^- \*\*Content-SHA256\*\*:/ {print "- **Content-SHA256**: `" digest "`"; next}
    {print}
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

source_hash() {
  local feature="$1" kind="$2" entry
  local manifest="$TEST_TMP/source-manifest" file rel digest
  entry="$feature/contracts/source-design.md"
  : > "$manifest"
  if [[ "$kind" == reviewed ]]; then
    digest=$(sed -e '/^\*\*Status\*\*:/d' -e '/^## Gate Approval/,$d' "$entry" | sha_stream | awk '{print $1}')
  else
    digest=$(sed '/^## Gate Approval/,$d' "$entry" | sha_stream | awk '{print $1}')
  fi
  printf '%s\t%s\n' 'contracts/source-design.md' "$digest" >> "$manifest"
  if [[ -d "$feature/contracts/source-design" ]]; then
    while IFS= read -r file; do
      rel=${file#"$feature"/}
      printf '%s\t%s\n' "$rel" "$(file_hash "$file")" >> "$manifest"
    done < <(find "$feature/contracts/source-design" -type f -print)
  fi
  LC_ALL=C sort "$manifest" | sha_stream | awk '{print $1}'
}

replace_token() {
  local file="$1" token="$2" value="$3" tmp
  tmp="$file.tmp"
  awk -v token="$token" -v value="$value" '
    {
      line=$0
      while ((position=index(line, token)) > 0) {
        line=substr(line, 1, position - 1) value substr(line, position + length(token))
      }
      print line
    }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

bind_current_source_content() {
  local feature="$1" digest tmp
  digest=$(source_hash "$feature" content)
  tmp="$feature/contracts/source-design.md.tmp"
  awk -v digest="$digest" '
    /^- \*\*Content-SHA256\*\*:/ {print "- **Content-SHA256**: `" digest "`"; next}
    {print}
  ' "$feature/contracts/source-design.md" > "$tmp" && mv "$tmp" "$feature/contracts/source-design.md"
  tmp="$feature/.gatespec/execution-state.md.tmp"
  awk -v digest="$digest" '
    /^- \*\*Source-Design-Content-SHA256\*\*:/ {print "- **Source-Design-Content-SHA256**: `" digest "`"; next}
    {print}
  ' "$feature/.gatespec/execution-state.md" > "$tmp" && mv "$tmp" "$feature/.gatespec/execution-state.md"
  self_hash "$feature/.gatespec/execution-state.md" 'Execution-State-SHA256'
}

expect() {
  local wanted="$1" mode="$2" feature="$3" label="$4" diagnostic="${5:-}" rc=0 got
  bash "$SCRIPT" "$mode" "$feature" > "$TEST_TMP/out" 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then got=pass; else got=fail; fi
  if [[ "$got" == "$wanted" ]] && { [[ -z "$diagnostic" ]] || grep -F "$diagnostic" "$TEST_TMP/out" >/dev/null 2>&1; }; then
    PASS=$((PASS + 1)); echo "✓ $label"
  else
    FAIL=$((FAIL + 1)); echo "✗ $label (wanted $wanted, got $got/$rc)"
    [[ -n "$diagnostic" ]] && echo "    required diagnostic: $diagnostic"
    sed 's/^/    /' "$TEST_TMP/out"
  fi
}

expect_review() {
  local wanted="$1" mode="$2" feature="$3" review_id="$4" label="$5" diagnostic="${6:-}" rc=0 got
  bash "$SCRIPT" "$mode" "$feature" "$review_id" > "$TEST_TMP/out" 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then got=pass; else got=fail; fi
  if [[ "$got" == "$wanted" ]] && { [[ -z "$diagnostic" ]] || grep -F "$diagnostic" "$TEST_TMP/out" >/dev/null 2>&1; }; then
    PASS=$((PASS + 1)); echo "✓ $label"
  else
    FAIL=$((FAIL + 1)); echo "✗ $label (wanted $wanted, got $got/$rc)"
    [[ -n "$diagnostic" ]] && echo "    required diagnostic: $diagnostic"
    sed 's/^/    /' "$TEST_TMP/out"
  fi
}

expect_silent() {
  local mode="$1" feature="$2" label="$3" rc=0
  bash "$SCRIPT" "$mode" "$feature" > "$TEST_TMP/out" 2>&1 || rc=$?
  if [[ "$rc" -eq 0 && ! -s "$TEST_TMP/out" ]]; then PASS=$((PASS + 1)); echo "✓ $label"
  else FAIL=$((FAIL + 1)); echo "✗ $label (rc=$rc, expected silence)"; sed 's/^/    /' "$TEST_TMP/out"; fi
}

REPO="$TEST_TMP/repo"
FEATURE="$REPO/specs/001-hot-reload"
mkdir -p "$FEATURE/contracts" "$FEATURE/.gatespec"

awk '/^cat > "\$TEST_TMP\/good\/spec\.md" <<'"'"'EOF'"'"'$/{on=1;next} on && /^EOF$/{exit} on{print}' \
  "$ROOT/tests/run-tests.sh" > "$FEATURE/spec.md"
seal_gate "$FEATURE/spec.md"
SPEC_HASH=$(content_hash "$FEATURE/spec.md")
awk -v hash="$SPEC_HASH" '/^cat > "\$TEST_TMP\/good\/plan\.md" <<EOF$/{on=1;next} on && /^EOF$/{exit} on{gsub(/\$SPEC_HASH/,hash); gsub(/\\`/,"`"); print}' \
  "$ROOT/tests/run-tests.sh" > "$FEATURE/plan.md"
seal_gate "$FEATURE/plan.md"
PLAN_HASH=$(content_hash "$FEATURE/plan.md")

git -C "$REPO" init -q
git -C "$REPO" symbolic-ref HEAD refs/heads/feature
git -C "$REPO" config user.name 'GateSpec Source Fixture'
git -C "$REPO" config user.email 'source-fixture@example.invalid'
git -C "$REPO" add specs
git -C "$REPO" commit -qm 'approved plan baseline'
BASE=$(git -C "$REPO" rev-parse HEAD)

cat > "$FEATURE/contracts/source-design.md" <<'EOF'
<!-- gatespec: source-design -->
# Source Design: Config hot reload
**Status**: Draft
**Plan Content-SHA256**: `__PLAN_HASH__`
## Maintainer Scenario
### Shared engineering scenario
A maintainer changes configuration while active readers keep serving.
### Before
ConfigService loads once at startup.
### After
ConfigWatcher validates and atomically publishes a snapshot.
### Success flow
1. ConfigWatcher calls ConfigStore::Reload and readers observe the next snapshot.
### Failure flow
1. Validation retains the prior snapshot and emits one diagnostic.
## Source Decisions
- None — the approved Design fixes every source-level material consequence.
## Source Change Manifest
### SD-F1: configuration implementation
- **Operation**: `MODIFY`
- **Path**: `src/config/store.cc`
- **Destination Path**: `not-applicable`
- **Responsibility**: Own validation and atomic snapshot publication.
- **Source refs**: SD-U1, SD-FLOW1, SD-ALG1, SD-FAIL1, SD-TEST1
### SD-F2: configuration tests
- **Operation**: `ADD`
- **Path**: `tests/config/store_test.cc`
- **Destination Path**: `not-applicable`
- **Responsibility**: Verify reload success, failure, timing, and shutdown.
- **Source refs**: SD-TEST1
## Symbols and Contracts
### SD-U1: reload contract
- **File**: `src/config/store.h`
- **Visibility / role**: Cross-module ConfigStore API and snapshot owner.
- **Complete declaration**:

```cpp
Result Reload();
```

- **Inputs / outputs / errors**: Returns validation or publication result without partial state.
- **Ownership / concurrency**: ConfigStore owns publication; readers share immutable snapshots.
- **Compatibility**: Existing Current callers and configuration syntax are preserved.
## Calls, Data, State, and Lifecycle
### SD-FLOW1: reload flow
- **Trigger and owner**: ConfigWatcher worker owns the poll trigger.
- **Ordered flow**: ConfigWatcher -> Reload -> validate -> atomic publish -> Current.
- **Success result**: A complete snapshot becomes visible within one second.
- **Failure / cancellation**: Failed validation retains prior state; Stop joins the worker.
- **Backpressure / ordering**: One serialized reload is in flight; newer polls coalesce.
## Algorithms and Invariants
### SD-ALG1: snapshot publication
- **Inputs / outputs**: Parsed candidate to immutable snapshot or validation error.
- **Steps**: Parse, validate, construct, publish, and release the prior owner.
- **Data structures**: Immutable ConfigSnapshot behind a shared handle.
- **Invariants**: Readers see either the prior or next complete snapshot.
- **Complexity**: Linear in configuration size with constant publication work.
- **Boundary cases**: Empty, malformed, maximum-size, repeated, and shutdown saves.
## Failure Model
### SD-FAIL1: runtime reload failure
- **Classification**: Parse, validation, I/O, cancellation, and publication errors.
- **Detection**: Reload classifies errors before publication.
- **Propagation**: Reload returns Result and watcher records one diagnostic.
- **Retry / recovery**: Next poll retries; prior snapshot stays live; Stop is idempotent.
- **Logging / alerting**: Structured warning is rate-limited by error signature.
## Test Traceability
### SD-TEST1: reload behavior
- **Requirement refs**: FR-001, FR-002, and SC-001.
- **Source refs**: SD-F1, SD-U1, SD-FLOW1, SD-ALG1, SD-FAIL1.
- **Test path**: `tests/config/store_test.cc`
- **Test symbol / scenario**: ReloadPublishesAtomically and InvalidReloadRetainsSnapshot.
- **Evidence**: Assertions cover timing, prior-reader continuity, failure, and shutdown.
## Operational and Cross-Cutting Design
- **Build registration**: Register store_test.cc in the existing config test target.
- **Dependencies**: Use the existing Result and shared-handle dependencies only.
- **Configuration**: Preserve syntax; poll interval remains within the one-second bound.
- **Persistence / transactions / migration**: N/A — snapshots are process-local and schema is unchanged.
- **Security**: Existing file permissions and parsing trust boundary are preserved.
- **Performance**: Reload is linear and Current stays non-blocking.
- **Compatibility**: Network, CLI, syntax, startup validation, and callers remain unchanged.
- **Observability**: One structured diagnostic reports class, path, and retained generation.
## Implementation Boundaries
### Bounded Implementation Freedoms
- Private helper names may vary while declarations and flow stay unchanged.
### Prohibited material boundaries
- External behavior, dependency direction, ownership, concurrency, errors, and invariants cannot change.
## Gate Approval
- **Approved by user**: pending
- **Content-SHA256**: `pending`
EOF
replace_token "$FEATURE/contracts/source-design.md" '__PLAN_HASH__' "$PLAN_HASH"

mkdir -p "$FEATURE/.gatespec/reviews/REV-SOURCE"
cat > "$FEATURE/.gatespec/execution-state.md" <<'EOF'
# GateSpec Execution State
- **Protocol-Version**: `2`
- **Execution-Epoch**: `E1`
- **Original-Implementation-Baseline**: `__BASE__`
- **Task-Handoff-Commit**: `pending`
- **Source-Design-Content-SHA256**: `pending`
- **Preserved-Reviews-SHA256**: `not-applicable`
- **Execution-State-SHA256**: `pending`
EOF
replace_token "$FEATURE/.gatespec/execution-state.md" '__BASE__' "$BASE"
self_hash "$FEATURE/.gatespec/execution-state.md" 'Execution-State-SHA256'

expect pass source-candidate "$FEATURE" "complete Draft Source candidate passes"
expect fail source "$FEATURE" "Draft Source blocks the conditional before_tasks gate" "expected Approved-Source-Design"
mkdir -p "$FEATURE/contracts/source-design"
printf '%s\n' '<!-- gatespec: source-design -->' > "$FEATURE/contracts/source-design/invalid.md"
expect fail source-candidate "$FEATURE" "Source shard cannot impersonate the authoritative entry" "cannot define the entry marker"
rm -f "$FEATURE/contracts/source-design/invalid.md"

SPEC_HASH=$(content_hash "$FEATURE/spec.md")
PLAN_HASH=$(content_hash "$FEATURE/plan.md")
DESIGN_HASH=$(printf '' | sha_stream | awk '{print $1}')
REVIEWED_HASH=$(source_hash "$FEATURE" reviewed)
REQUEST="$FEATURE/.gatespec/reviews/REV-SOURCE/round-00-request.md"
VERDICT="$FEATURE/.gatespec/reviews/REV-SOURCE/round-00-verdict.md"
SEAL="$FEATURE/.gatespec/reviews/REV-SOURCE/seal.md"
cat > "$REQUEST" <<'EOF'
- **Protocol-Version**: `2`
- **Review-ID**: `REV-SOURCE`
- **Round**: `00`
- **Scope**: `SOURCE`
- **Spec-Content-SHA256**: `__SPEC_HASH__`
- **Plan-Content-SHA256**: `__PLAN_HASH__`
- **Design-Basis-SHA256**: `__DESIGN_HASH__`
- **Source-Design-Reviewed-SHA256**: `__REVIEWED_HASH__`
- **Source-Baseline-Commit**: `__BASE__`
- **Previous-Verdict-SHA256**: `none`

## Required Tests

- Not run — source-design review

- **Request-SHA256**: `pending`
EOF
replace_token "$REQUEST" '__SPEC_HASH__' "$SPEC_HASH"
replace_token "$REQUEST" '__PLAN_HASH__' "$PLAN_HASH"
replace_token "$REQUEST" '__DESIGN_HASH__' "$DESIGN_HASH"
replace_token "$REQUEST" '__REVIEWED_HASH__' "$REVIEWED_HASH"
replace_token "$REQUEST" '__BASE__' "$BASE"
self_hash "$REQUEST" 'Request-SHA256'
REQUEST_HASH=$(sed -n 's/^- \*\*Request-SHA256\*\*: `\([0-9a-f]*\)`$/\1/p' "$REQUEST")
cat > "$VERDICT" <<'EOF'
- **Protocol-Version**: `2`
- **Review-ID**: `REV-SOURCE`
- **Round**: `00`
- **Request-SHA256**: `__REQUEST_HASH__`
- **Reviewer-Platform**: `codex`
- **Reviewer-Context-ID**: `source-fixture-00`
- **Isolation**: `fresh`
- **Status**: `PASS`

## Tests Run

- Not run — source-design review

## Blockers

- None

## Observations

- Source trace is complete.

## Limitations

- Semantic freshness is adapter evidence, not a Bash proof.

- **Verdict-SHA256**: `pending`
EOF
replace_token "$VERDICT" '__REQUEST_HASH__' "$REQUEST_HASH"
self_hash "$VERDICT" 'Verdict-SHA256'
VERDICT_HASH=$(sed -n 's/^- \*\*Verdict-SHA256\*\*: `\([0-9a-f]*\)`$/\1/p' "$VERDICT")
cat > "$SEAL" <<'EOF'
- **Protocol-Version**: `2`
- **Review-ID**: `REV-SOURCE`
- **Round**: `00`
- **Status**: `PASS`
- **Request-SHA256**: `__REQUEST_HASH__`
- **Verdict-SHA256**: `__VERDICT_HASH__`
- **Spec-Content-SHA256**: `__SPEC_HASH__`
- **Plan-Content-SHA256**: `__PLAN_HASH__`
- **Design-Basis-SHA256**: `__DESIGN_HASH__`
- **Source-Design-Reviewed-SHA256**: `__REVIEWED_HASH__`
- **Source-Baseline-Commit**: `__BASE__`
- **Sealed-At**: `2026-08-24T12:00:00Z`
- **Seal-SHA256**: `pending`
EOF
replace_token "$SEAL" '__REQUEST_HASH__' "$REQUEST_HASH"
replace_token "$SEAL" '__VERDICT_HASH__' "$VERDICT_HASH"
replace_token "$SEAL" '__SPEC_HASH__' "$SPEC_HASH"
replace_token "$SEAL" '__PLAN_HASH__' "$PLAN_HASH"
replace_token "$SEAL" '__DESIGN_HASH__' "$DESIGN_HASH"
replace_token "$SEAL" '__REVIEWED_HASH__' "$REVIEWED_HASH"
replace_token "$SEAL" '__BASE__' "$BASE"
self_hash "$SEAL" 'Seal-SHA256'

expect pass source-review "$FEATURE" "fresh REV-SOURCE PASS accepts the Draft reviewed hash"

SOURCE_BACKUP="$TEST_TMP/source-approved-backup"
sed -e 's/^\*\*Status\*\*: Draft$/**Status**: Approved-Source-Design (2026-08-24)/' \
  -e 's/^- \*\*Approved by user\*\*: pending$/- **Approved by user**: 2026-08-24/' \
  "$FEATURE/contracts/source-design.md" > "$TEST_TMP/source-approving"
mv "$TEST_TMP/source-approving" "$FEATURE/contracts/source-design.md"
CONTENT_HASH=$(source_hash "$FEATURE" content)
sed "s/^- \*\*Content-SHA256\*\*: \`pending\`$/- **Content-SHA256**: \`$CONTENT_HASH\`/" \
  "$FEATURE/contracts/source-design.md" > "$TEST_TMP/source-approved"
mv "$TEST_TMP/source-approved" "$FEATURE/contracts/source-design.md"
sed "s/^- \*\*Source-Design-Content-SHA256\*\*: \`pending\`$/- **Source-Design-Content-SHA256**: \`$CONTENT_HASH\`/" \
  "$FEATURE/.gatespec/execution-state.md" > "$TEST_TMP/state-approved"
mv "$TEST_TMP/state-approved" "$FEATURE/.gatespec/execution-state.md"
self_hash "$FEATURE/.gatespec/execution-state.md" 'Execution-State-SHA256'
cp "$FEATURE/contracts/source-design.md" "$SOURCE_BACKUP"
cp "$FEATURE/.gatespec/execution-state.md" "$TEST_TMP/state-approved-backup"

expect pass source "$FEATURE" "approval-only Status/Gate change preserves REV-SOURCE"

mv "$SEAL" "$TEST_TMP/rev-source-seal"
expect fail source "$FEATURE" "approved Source still requires REV-SOURCE PASS" "review directory and PASS seal are required"
mv "$TEST_TMP/rev-source-seal" "$SEAL"

cp "$FEATURE/plan.md" "$TEST_TMP/plan-approved-backup"
sed 's/Add portable polling and atomic snapshot replacement/Add portable serialized polling and atomic snapshot replacement/' \
  "$TEST_TMP/plan-approved-backup" > "$FEATURE/plan.md"
seal_gate "$FEATURE/plan.md"
expect fail source "$FEATURE" "Plan drift invalidates approved Source" "Plan Content-SHA256 is missing or stale"
cp "$TEST_TMP/plan-approved-backup" "$FEATURE/plan.md"

git -C "$REPO" commit --allow-empty -qm 'advance after source baseline'
DRIFTED_BASE=$(git -C "$REPO" rev-parse HEAD)
replace_token "$FEATURE/.gatespec/execution-state.md" "$BASE" "$DRIFTED_BASE"
self_hash "$FEATURE/.gatespec/execution-state.md" 'Execution-State-SHA256'
expect fail source "$FEATURE" "Source baseline drift invalidates REV-SOURCE" "must equal execution state's original baseline"
cp "$TEST_TMP/state-approved-backup" "$FEATURE/.gatespec/execution-state.md"

sed 's/One serialized reload is in flight/Two concurrent reloads are allowed/' "$SOURCE_BACKUP" > "$FEATURE/contracts/source-design.md"
bind_current_source_content "$FEATURE"
expect fail source "$FEATURE" "Source body drift invalidates reviewed seal" "Source-Design-Reviewed-SHA256 is stale"
cp "$SOURCE_BACKUP" "$FEATURE/contracts/source-design.md"
cp "$TEST_TMP/state-approved-backup" "$FEATURE/.gatespec/execution-state.md"

mkdir -p "$FEATURE/contracts/source-design"
printf '%s\n' '# Extra source detail' > "$FEATURE/contracts/source-design/details.md"
bind_current_source_content "$FEATURE"
expect fail source "$FEATURE" "Source shard drift invalidates reviewed seal" "Source-Design-Reviewed-SHA256 is stale"
rm -f "$FEATURE/contracts/source-design/details.md"
cp "$SOURCE_BACKUP" "$FEATURE/contracts/source-design.md"
cp "$TEST_TMP/state-approved-backup" "$FEATURE/.gatespec/execution-state.md"

sed 's/^- \*\*Content-SHA256\*\*:.*/- **Content-SHA256**: `0000000000000000000000000000000000000000000000000000000000000000`/' \
  "$SOURCE_BACKUP" > "$FEATURE/contracts/source-design.md"
expect fail source "$FEATURE" "stale approved Source content hash fails" "Content-SHA256 does not match"
cp "$SOURCE_BACKUP" "$FEATURE/contracts/source-design.md"

cat > "$FEATURE/tasks.md" <<'EOF'
# Tasks: Source-traced reload
**Source-Design-Content-SHA256**: `__CONTENT_HASH__`
## Phase 1: Setup
- [ ] T001 Prepare src/config/store.cc for SD-F1 and SD-U1.
## Phase 2: Foundational
- [ ] T002 Implement SD-FLOW1 and SD-ALG1 in src/config/store.cc.
- [ ] T003 GateSpec review checkpoint REV-FOUNDATION: run speckit.gatespec.review-implementation --scope REV-FOUNDATION and require .gatespec/reviews/REV-FOUNDATION/seal.md before continuing
## Phase 3: User Story 1 - Hot reload
- [ ] T004 [US1] Implement SD-F2, SD-FAIL1 and SD-TEST1 in tests/config/store_test.cc.
- [ ] T005 [US1] GateSpec review checkpoint REV-US1: run speckit.gatespec.review-implementation --scope REV-US1 and require .gatespec/reviews/REV-US1/seal.md before continuing
## Phase 4: Polish & Cross-Cutting Concerns
- [ ] T006 Validate SD-TEST1 in tests/config/store_test.cc.
- [ ] T007 GateSpec review checkpoint REV-FINAL: run speckit.gatespec.review-implementation --scope REV-FINAL and require .gatespec/reviews/REV-FINAL/seal.md before continuing
EOF
replace_token "$FEATURE/tasks.md" '__CONTENT_HASH__' "$CONTENT_HASH"
cp "$FEATURE/tasks.md" "$TEST_TMP/tasks-good"
expect pass tasks-structure "$FEATURE" "source-enabled tasks bind hash, SD refs, files, and tests"

sed '/^\*\*Source-Design-Content-SHA256\*\*:/d' "$FEATURE/tasks.md" > "$TEST_TMP/tasks-no-source-hash"
mv "$TEST_TMP/tasks-no-source-hash" "$FEATURE/tasks.md"
expect fail tasks-structure "$FEATURE" "source-enabled tasks cannot omit Source hash" "require the current Source-Design-Content-SHA256"
sed "2i\\**Source-Design-Content-SHA256**: \`$CONTENT_HASH\`" "$FEATURE/tasks.md" > "$TEST_TMP/tasks-restored"
mv "$TEST_TMP/tasks-restored" "$FEATURE/tasks.md"

sed 's/SD-ALG1/algorithm/' "$FEATURE/tasks.md" > "$TEST_TMP/tasks-missing-ref"
mv "$TEST_TMP/tasks-missing-ref" "$FEATURE/tasks.md"
expect fail tasks-structure "$FEATURE" "tasks cannot omit an SD item" "no executable non-checkpoint task covers SD-ALG1"
cp "$TEST_TMP/tasks-good" "$FEATURE/tasks.md"

sed 's#tests/config/store_test.cc#test-target#g' "$FEATURE/tasks.md" > "$TEST_TMP/tasks-missing-path"
mv "$TEST_TMP/tasks-missing-path" "$FEATURE/tasks.md"
expect fail tasks-structure "$FEATURE" "tasks cannot omit a Source manifest path" "has no task coverage"
cp "$TEST_TMP/tasks-good" "$FEATURE/tasks.md"

sed 's/SD-TEST1/test-obligation/g' "$FEATURE/tasks.md" > "$TEST_TMP/tasks-missing-test-trace"
mv "$TEST_TMP/tasks-missing-test-trace" "$FEATURE/tasks.md"
expect fail tasks-structure "$FEATURE" "tasks cannot omit Source test traceability" "no executable non-checkpoint task covers SD-TEST1"
cp "$TEST_TMP/tasks-good" "$FEATURE/tasks.md"

# Protocol v2 task handoff and complete automated implementation path --------
cat > "$FEATURE/.gatespec/implementation-adjustments.md" <<EOF
# GateSpec Implementation Adjustments
- **Execution-Epoch**: \`E1\`
- **Source-Design-Content-SHA256**: \`$CONTENT_HASH\`
## Adjustments
- None — no bounded implementation adjustment has been recorded.
EOF
git -C "$REPO" add specs
git -C "$REPO" commit -qm 'source task handoff'
HANDOFF=$(git -C "$REPO" rev-parse HEAD)
replace_token "$FEATURE/.gatespec/execution-state.md" '`pending`' "\`$HANDOFF\`"
# The first replacement also touched no other pending field: approved Source
# state has only Task-Handoff pending at this point.
self_hash "$FEATURE/.gatespec/execution-state.md" 'Execution-State-SHA256'

write_v2_review "$FEATURE" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  'Not run — task-plan review' not-applicable
git -C "$REPO" add specs
git -C "$REPO" commit -qm 'REV-TASKS PASS baseline'
BASELINE=$(git -C "$REPO" rev-parse HEAD)
expect pass task-review "$FEATURE" "Protocol v2 REV-TASKS binds epoch, Source, empty IA, and Task Handoff"

cat > "$FEATURE/.gatespec/implementation-adjustments.md" <<EOF
# GateSpec Implementation Adjustments
- **Execution-Epoch**: \`E1\`
- **Source-Design-Content-SHA256**: \`$CONTENT_HASH\`
## Adjustments
### IA1: local reload helper name
- **Source refs**: \`SD-F1, SD-U1\`
- **Task ID**: \`T002\`
- **Changed Paths**: \`src/config/store.cc\`
- **Changed Symbols**: \`ReloadConfig\`
- **Reason**: The private helper keeps the approved public declaration unchanged.
- **Boundary Impact**: \`none\`
- **Verification**: Foundation review inspects the symbol and unit result.
EOF
mark_task "$FEATURE/tasks.md" T001
mark_task "$FEATURE/tasks.md" T002
mkdir -p "$REPO/src/config"
printf '%s\n' 'int ReloadConfig() { return 1; }' > "$REPO/src/config/store.cc"
git -C "$REPO" add specs src
git -C "$REPO" commit -qm 'foundation implementation'
FOUNDATION_SUBJECT=$(git -C "$REPO" rev-parse HEAD)
write_v2_review "$FEATURE" REV-FOUNDATION FOUNDATION "$BASELINE" "$BASELINE" "$FOUNDATION_SUBJECT" T001,T002 \
  'bash tests/unit.sh' not-applicable
mark_task "$FEATURE/tasks.md" T003
expect_review pass implementation-candidate "$FEATURE" REV-FOUNDATION "v2 foundation candidate validates bounded IA in Subject-Commit"
git -C "$REPO" add specs
git -C "$REPO" commit -qm 'REV-FOUNDATION PASS metadata'
expect_review pass implementation-review "$FEATURE" REV-FOUNDATION "v2 foundation committed review passes"

mark_task "$FEATURE/tasks.md" T004
mkdir -p "$REPO/tests/config"
printf '%s\n' 'int ReloadConfigTest() { return 0; }' > "$REPO/tests/config/store_test.cc"
git -C "$REPO" add specs tests/config
git -C "$REPO" commit -qm 'user story implementation'
US_SUBJECT=$(git -C "$REPO" rev-parse HEAD)
write_v2_review "$FEATURE" REV-US1 US1 "$BASELINE" "$FOUNDATION_SUBJECT" "$US_SUBJECT" T004 \
  'bash tests/integration.sh' not-applicable
mark_task "$FEATURE/tasks.md" T005
expect_review pass implementation-candidate "$FEATURE" REV-US1 "v2 user-story candidate validates automatically"
git -C "$REPO" add specs
git -C "$REPO" commit -qm 'REV-US1 PASS metadata'
expect_review pass implementation-review "$FEATURE" REV-US1 "v2 user-story committed review passes"

mark_task "$FEATURE/tasks.md" T006
git -C "$REPO" add specs
git -C "$REPO" commit -qm 'final validation subject'
FINAL_SUBJECT=$(git -C "$REPO" rev-parse HEAD)
FINAL_DELTA=$(final_delta_hash "$REPO" "$BASE" "$FINAL_SUBJECT")
write_v2_review "$FEATURE" REV-FINAL FINAL "$BASELINE" "$BASE" "$FINAL_SUBJECT" T001,T002,T004,T006 \
  'bash tests/run-all.sh' "$FINAL_DELTA"
mark_task "$FEATURE/tasks.md" T007
expect_review pass implementation-candidate "$FEATURE" REV-FINAL "v2 cumulative REV-FINAL reconciles Source paths and raw delta"
git -C "$REPO" add specs
git -C "$REPO" commit -qm 'REV-FINAL PASS metadata'
FINAL_REVIEW_COMMIT=$(git -C "$REPO" rev-parse HEAD)
expect_review pass implementation-review "$FEATURE" REV-FINAL "v2 committed REV-FINAL passes without user checkpoint approval"
expect fail acceptance "$FEATURE" "REV-FINAL alone cannot complete without acceptance" "explicit final user acceptance is missing"
expect pass acceptance-candidate "$FEATURE" "final delivery is ready for one user acceptance"

FINAL_SEAL="$FEATURE/.gatespec/reviews/REV-FINAL/seal.md"
IA_HASH=$(file_hash "$FEATURE/.gatespec/implementation-adjustments.md")
TASKS_HASH=$(normalized_tasks_hash "$FEATURE/tasks.md")
FINAL_SEAL_HASH=$(receipt_field "$FINAL_SEAL" 'Seal-SHA256')
{
  printf '%s\n' '# GateSpec Implementation Acceptance' '- **Protocol-Version**: `2`' '- **Status**: `Accepted`' '- **Accepted-At**: `2026-08-24T14:00:00Z`'
  printf -- '- **Spec-Content-SHA256**: `%s`\n' "$(content_hash "$FEATURE/spec.md")"
  printf -- '- **Plan-Content-SHA256**: `%s`\n' "$(content_hash "$FEATURE/plan.md")"
  printf -- '- **Design-Attachments-SHA256**: `%s`\n' "$(printf '' | sha_stream | awk '{print $1}')"
  printf -- '- **Tasks-Definition-SHA256**: `%s`\n' "$TASKS_HASH"
  printf '%s\n' '- **Execution-Epoch**: `E1`'
  printf -- '- **Source-Design-Content-SHA256**: `%s`\n' "$CONTENT_HASH"
  printf -- '- **Implementation-Adjustments-SHA256**: `%s`\n' "$IA_HASH"
  printf -- '- **Original-Implementation-Baseline**: `%s`\n' "$BASE"
  printf -- '- **Final-Subject-Commit**: `%s`\n' "$FINAL_SUBJECT"
  printf -- '- **REV-FINAL-Seal-SHA256**: `%s`\n' "$FINAL_SEAL_HASH"
  printf -- '- **Final-Review-Commit**: `%s`\n' "$FINAL_REVIEW_COMMIT"
  printf -- '- **Final-Delta-SHA256**: `%s`\n' "$FINAL_DELTA"
  printf '%s\n' '- **Acceptance-SHA256**: `pending`'
} > "$FEATURE/.gatespec/acceptance.md"
self_hash "$FEATURE/.gatespec/acceptance.md" 'Acceptance-SHA256'
git -C "$REPO" add "${FEATURE#"$REPO"/}/.gatespec/acceptance.md"
git -C "$REPO" commit -qm 'accept implementation delivery'
expect pass acceptance "$FEATURE" "explicit acceptance binds final review commit and raw tree delta"
cp "$FEATURE/.gatespec/acceptance.md" "$TEST_TMP/acceptance-valid"

IA_MISMATCH_REPO="$TEST_TMP/ia-subject-mismatch"
git clone -q --local --no-hardlinks "$REPO" "$IA_MISMATCH_REPO"
git -C "$IA_MISMATCH_REPO" checkout -q -b ia-mismatch "$FOUNDATION_SUBJECT"
IA_MISMATCH_FEATURE="$IA_MISMATCH_REPO/specs/001-hot-reload"
write_v2_review "$IA_MISMATCH_FEATURE" REV-FOUNDATION FOUNDATION "$BASELINE" "$BASELINE" "$FOUNDATION_SUBJECT" T001,T002 \
  'bash tests/unit.sh' not-applicable
mark_task "$IA_MISMATCH_FEATURE/tasks.md" T003
IA_REQUEST="$IA_MISMATCH_FEATURE/.gatespec/reviews/REV-FOUNDATION/round-00-request.md"
IA_VERDICT="$IA_MISMATCH_FEATURE/.gatespec/reviews/REV-FOUNDATION/round-00-verdict.md"
IA_SEAL="$IA_MISMATCH_FEATURE/.gatespec/reviews/REV-FOUNDATION/seal.md"
IA_RECORDED=$(receipt_field "$IA_REQUEST" 'Implementation-Adjustments-SHA256')
IA_REQUEST_HASH=$(receipt_field "$IA_REQUEST" 'Request-SHA256')
IA_VERDICT_HASH=$(receipt_field "$IA_VERDICT" 'Verdict-SHA256')
ZERO_HASH=0000000000000000000000000000000000000000000000000000000000000000
replace_token "$IA_REQUEST" "$IA_RECORDED" "$ZERO_HASH"
self_hash "$IA_REQUEST" 'Request-SHA256'
IA_BAD_REQUEST_HASH=$(receipt_field "$IA_REQUEST" 'Request-SHA256')
replace_token "$IA_VERDICT" "$IA_REQUEST_HASH" "$IA_BAD_REQUEST_HASH"
self_hash "$IA_VERDICT" 'Verdict-SHA256'
IA_BAD_VERDICT_HASH=$(receipt_field "$IA_VERDICT" 'Verdict-SHA256')
replace_token "$IA_SEAL" "$IA_REQUEST_HASH" "$IA_BAD_REQUEST_HASH"
replace_token "$IA_SEAL" "$IA_VERDICT_HASH" "$IA_BAD_VERDICT_HASH"
replace_token "$IA_SEAL" "$IA_RECORDED" "$ZERO_HASH"
self_hash "$IA_SEAL" 'Seal-SHA256'
expect_review fail implementation-candidate "$IA_MISMATCH_FEATURE" REV-FOUNDATION \
  "implementation request IA hash must match Subject-Commit" "does not match Subject-Commit"

UNRECORDED_REPO="$TEST_TMP/unrecorded-final-path"
git clone -q --local --no-hardlinks "$REPO" "$UNRECORDED_REPO"
git -C "$UNRECORDED_REPO" checkout -q -b unrecorded-path "$FINAL_SUBJECT"
git -C "$UNRECORDED_REPO" config user.name 'GateSpec Source Fixture'
git -C "$UNRECORDED_REPO" config user.email 'source-fixture@example.invalid'
UNRECORDED_FEATURE="$UNRECORDED_REPO/specs/001-hot-reload"
printf '%s\n' 'int UnplannedPath() { return 0; }' > "$UNRECORDED_REPO/src/unplanned.cc"
git -C "$UNRECORDED_REPO" add src/unplanned.cc
git -C "$UNRECORDED_REPO" commit -qm 'add unrecorded final path'
UNRECORDED_SUBJECT=$(git -C "$UNRECORDED_REPO" rev-parse HEAD)
UNRECORDED_DELTA=$(final_delta_hash "$UNRECORDED_REPO" "$BASE" "$UNRECORDED_SUBJECT")
write_v2_review "$UNRECORDED_FEATURE" REV-FINAL FINAL "$BASELINE" "$BASE" "$UNRECORDED_SUBJECT" T001,T002,T004,T006 \
  'bash tests/run-all.sh' "$UNRECORDED_DELTA"
mark_task "$UNRECORDED_FEATURE/tasks.md" T007
expect_review fail implementation-candidate "$UNRECORDED_FEATURE" REV-FINAL \
  "REV-FINAL rejects a product path absent from Source and IA" "product path 'src/unplanned.cc'"

for acceptance_variant in seal subject delta; do
  VARIANT_REPO="$TEST_TMP/acceptance-$acceptance_variant"
  git clone -q --local --no-hardlinks "$REPO" "$VARIANT_REPO"
  git -C "$VARIANT_REPO" checkout -q -b "acceptance-$acceptance_variant" "$FINAL_REVIEW_COMMIT"
  git -C "$VARIANT_REPO" config user.name 'GateSpec Source Fixture'
  git -C "$VARIANT_REPO" config user.email 'source-fixture@example.invalid'
  VARIANT_FEATURE="$VARIANT_REPO/specs/001-hot-reload"
  cp "$TEST_TMP/acceptance-valid" "$VARIANT_FEATURE/.gatespec/acceptance.md"
  case "$acceptance_variant" in
    seal)
      replace_token "$VARIANT_FEATURE/.gatespec/acceptance.md" "$FINAL_SEAL_HASH" "$ZERO_HASH"
      acceptance_diagnostic='REV-FINAL seal hash mismatch'
      ;;
    subject)
      replace_token "$VARIANT_FEATURE/.gatespec/acceptance.md" "$FINAL_SUBJECT" "$US_SUBJECT"
      acceptance_diagnostic='Final Subject does not match REV-FINAL'
      ;;
    delta)
      replace_token "$VARIANT_FEATURE/.gatespec/acceptance.md" "$FINAL_DELTA" "$ZERO_HASH"
      acceptance_diagnostic='Final-Delta-SHA256 is stale'
      ;;
  esac
  self_hash "$VARIANT_FEATURE/.gatespec/acceptance.md" 'Acceptance-SHA256'
  git -C "$VARIANT_REPO" add specs/001-hot-reload/.gatespec/acceptance.md
  git -C "$VARIANT_REPO" commit -qm "invalid $acceptance_variant acceptance binding"
  expect fail acceptance "$VARIANT_FEATURE" "acceptance rejects a mismatched $acceptance_variant binding" "$acceptance_diagnostic"
done

printf '%s\n' 'dirty' > "$REPO/untracked-after-acceptance"
expect fail acceptance "$FEATURE" "acceptance rejects dirty or untracked worktree" "clean worktree"
rm -f "$REPO/untracked-after-acceptance"

cp "$FEATURE/.gatespec/implementation-adjustments.md" "$TEST_TMP/ia-valid"
sed 's/- \*\*Boundary Impact\*\*: `none`/- **Boundary Impact**: `material`/' "$TEST_TMP/ia-valid" \
  > "$FEATURE/.gatespec/implementation-adjustments.md"
expect_review fail implementation-candidate "$FEATURE" REV-FINAL \
  "material Source boundary cannot masquerade as IA" "must declare Boundary Impact 'none'"
cp "$TEST_TMP/ia-valid" "$FEATURE/.gatespec/implementation-adjustments.md"

ALT_REPO="$TEST_TMP/alternate-delta"
git clone -q --local --no-hardlinks "$REPO" "$ALT_REPO"
git -C "$ALT_REPO" checkout -q --detach "$FINAL_SUBJECT"
printf '%s\n' 'int ReloadConfig() { return 2; }' > "$ALT_REPO/src/config/store.cc"
git -C "$ALT_REPO" config user.name 'GateSpec Delta Fixture'
git -C "$ALT_REPO" config user.email 'delta-fixture@example.invalid'
git -C "$ALT_REPO" add src/config/store.cc
git -C "$ALT_REPO" commit -qm 'same path different content'
ALT_SUBJECT=$(git -C "$ALT_REPO" rev-parse HEAD)
ORIGINAL_PATH_HASH=$(changed_paths_hash "$REPO" "$BASE" "$FINAL_SUBJECT")
ALT_PATH_HASH=$(changed_paths_hash "$ALT_REPO" "$BASE" "$ALT_SUBJECT")
ALT_DELTA=$(final_delta_hash "$ALT_REPO" "$BASE" "$ALT_SUBJECT")
if [[ "$ORIGINAL_PATH_HASH" == "$ALT_PATH_HASH" && "$FINAL_DELTA" != "$ALT_DELTA" ]]; then
  PASS=$((PASS + 1)); echo "✓ raw Final Delta changes when the same path's content changes"
else
  FAIL=$((FAIL + 1)); echo "✗ raw Final Delta must distinguish same-path content changes"
fi

NO_SOURCE="$REPO/specs/002-no-source"
mkdir -p "$NO_SOURCE/.gatespec"
cp "$FEATURE/spec.md" "$NO_SOURCE/spec.md"
sed 's/^- \*\*Protocol Version\*\*: `1`$/- **Protocol Version**: `2`/' "$FEATURE/plan.md" > "$NO_SOURCE/plan.md"
seal_gate "$NO_SOURCE/plan.md"
sed '/^\*\*Source-Design-Content-SHA256\*\*:/d' "$TEST_TMP/tasks-good" > "$NO_SOURCE/tasks.md"
NO_SOURCE_ORIGINAL=$(git -C "$REPO" rev-parse HEAD)
cat > "$NO_SOURCE/.gatespec/execution-state.md" <<EOF
# GateSpec Execution State
- **Protocol-Version**: \`2\`
- **Execution-Epoch**: \`E1\`
- **Original-Implementation-Baseline**: \`$NO_SOURCE_ORIGINAL\`
- **Task-Handoff-Commit**: \`pending\`
- **Source-Design-Content-SHA256**: \`not-applicable\`
- **Preserved-Reviews-SHA256**: \`not-applicable\`
- **Execution-State-SHA256**: \`pending\`
EOF
self_hash "$NO_SOURCE/.gatespec/execution-state.md" 'Execution-State-SHA256'
git -C "$REPO" add specs/002-no-source
git -C "$REPO" commit -qm 'protocol v2 no-source handoff'
HANDOFF=$(git -C "$REPO" rev-parse HEAD)
replace_token "$NO_SOURCE/.gatespec/execution-state.md" '`pending`' "\`$HANDOFF\`"
self_hash "$NO_SOURCE/.gatespec/execution-state.md" 'Execution-State-SHA256'
write_v2_review "$NO_SOURCE" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  'Not run — task-plan review' not-applicable
git -C "$REPO" add specs/002-no-source
git -C "$REPO" commit -qm 'protocol v2 no-source REV-TASKS'
expect pass task-review "$NO_SOURCE" "Protocol v2 without Source uses not-applicable Source and IA bindings"

ORPHAN_REPO="$TEST_TMP/orphan-repo"
cp -R "$REPO" "$ORPHAN_REPO"
ORPHAN="$ORPHAN_REPO/specs/001-hot-reload"
rm -f "$ORPHAN/contracts/source-design.md"
expect fail source "$ORPHAN" "orphan Source receipts fail without authoritative entry" "orphan Source Design artifact"

UNMARKED="$TEST_TMP/unmarked"
mkdir -p "$UNMARKED/contracts/source-design" "$UNMARKED/.gatespec/reviews/REV-SOURCE"
printf '%s\n' '# upstream feature' > "$UNMARKED/spec.md"
printf '%s\n' '# orphan' > "$UNMARKED/contracts/source-design/part.md"
for unmarked_mode in source-candidate source-review source acceptance-candidate acceptance; do
  expect_silent "$unmarked_mode" "$UNMARKED" "unmarked upstream feature is silent in $unmarked_mode mode"
done

echo ""
echo "==> source-design fixtures: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
