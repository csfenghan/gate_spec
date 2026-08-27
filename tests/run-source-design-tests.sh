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

test_control_closure_hash() {
  local file="$1" cr
  cr=$(printf '\r')
  {
    printf '%s\n' '## GateSpec Test Control Closure *(gatespec: mandatory)*'
    awk '
      /^## GateSpec Test Control Closure \*\(gatespec: mandatory\)\*$/ {inside=1; next}
      inside && /^## / {exit}
      inside && NF {print}
    ' "$file" | sed -e "s/${cr}\$//"
  } | sha_stream | awk '{print $1}'
}

test_control_subject_manifest_hash() {
  local repo="$1" subject="$2" role path meta mode oid object_path
  local manifest="$TEST_TMP/test-control-subject-manifest"
  : > "$manifest"

  while IFS=$'\t' read -r meta object_path; do
    mode=${meta%% *}
    oid=${meta##* }
    printf '%s\t%s\t%s\t%s\t%s\n' \
      test-only-surface src/testonly "$object_path" "$mode" "$oid" >> "$manifest"
  done < <(git -C "$repo" ls-tree -r "$subject" -- src/testonly)

  while IFS='|' read -r role path; do
    meta=$(git -C "$repo" ls-tree "$subject" -- "$path")
    mode=${meta%% *}
    oid=${meta#* }; oid=${oid%%$'\t'*}; oid=${oid##* }
    printf '%s\t%s\t%s\t%s\t%s\n' "$role" "$path" "$path" "$mode" "$oid" >> "$manifest"
  done <<'EOF'
production-touchpoint|src/config/store.cc
production-touchpoint|src/config/store.h
build-wiring|CMakeLists.txt
validator|tools/testonly_control_validator.sh
EOF
  LC_ALL=C sort -u "$manifest" | sha_stream | awk '{print $1}'
}

write_test_control_evidence() {
  local feature="$1" subject="$2" closure="$3" manifest="$4" round="$5"
  local repo lane state file row coordinator
  repo=$(git -C "$feature" rev-parse --show-toplevel)
  for lane in default-off explicit-on; do
    if [[ "$lane" == default-off ]]; then state=omitted-default-off; else state=explicit-on; fi
    file="$feature/.gatespec/reviews/REV-FINAL/round-${round}-${lane}-evidence.md"
    coordinator=$(mktemp -d "$TEST_TMP/coordinator-test-control-${lane}.XXXXXX")
    git clone -q --local --no-hardlinks --no-checkout "$repo" "$coordinator" || exit 1
    git -C "$coordinator" checkout -q --detach "$subject" || exit 1
    row=$(cd "$coordinator" && bash tools/testonly_control_validator.sh \
      --gatespec-lane "$lane") || exit 1
    if [[ -n "$(git -C "$coordinator" status --porcelain --untracked-files=all)" ]]; then
      echo "coordinator Test Control validator dirtied its isolated Subject clone" >&2
      exit 1
    fi
    {
      printf '%s\n' '# GateSpec Test Control Evidence'
      printf '%s\n' '- **Protocol-Version**: `3`' '- **Review-ID**: `REV-FINAL`'
      printf -- '- **Round**: `%s`\n' "$round"
      printf -- '- **Lane**: `%s`\n' "$lane"
      printf -- '- **Subject-Commit**: `%s`\n' "$subject"
      printf '%s\n' '- **Test-Control-Mode**: `isolated`'
      printf -- '- **Test-Control-Closure-SHA256**: `%s`\n' "$closure"
      printf -- '- **Test-Control-Subject-Manifest-SHA256**: `%s`\n' "$manifest"
      printf -- '- **Effective-Switch-State**: `%s`\n\n' "$state"
      printf '%s\n' '## Validator Results' ''
      printf '%s\n' '| Validator | Build switch | Build wiring | Validator command | Production build scope | Compile manifest SHA256 | Dependency manifest SHA256 | Artifact manifest SHA256 | Install/export/symbol manifest SHA256 | Test manifest SHA256 | Declared source coverage | Declared test coverage | Undeclared compile hits | Undeclared dependency hits | Undeclared artifact hits | Undeclared install/export hits | Result |'
      printf '%s\n' '|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|---|'
      printf '%s\n\n' "$row"
      printf '%s\n' '- **Evidence-SHA256**: `pending`'
    } > "$file"
    self_hash "$file" 'Evidence-SHA256'
  done
}

fresh_test_control_rows_match() {
  local feature="$1" subject="$2" round="$3" repo lane fresh expected actual
  repo=$(git -C "$feature" rev-parse --show-toplevel)
  for lane in default-off explicit-on; do
    fresh=$(mktemp -d "$TEST_TMP/fresh-test-control-${lane}.XXXXXX")
    git clone -q --local --no-hardlinks --no-checkout "$repo" "$fresh" || return 1
    git -C "$fresh" checkout -q --detach "$subject" || return 1
    expected="$fresh.expected"
    actual="$fresh.actual"
    awk '/^\| tools\/testonly_control_validator[.]sh \|/ {print; exit}' \
      "$feature/.gatespec/reviews/REV-FINAL/round-${round}-${lane}-evidence.md" > "$expected"
    (cd "$fresh" && bash tools/testonly_control_validator.sh \
      --gatespec-lane "$lane") > "$actual" || return 1
    cmp -s "$expected" "$actual" || return 1
    [[ -z "$(git -C "$fresh" status --porcelain --untracked-files=all)" ]] || return 1
  done
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

write_v3_review() {
  local feature="$1" id="$2" scope="$3" baseline="$4" base="$5" subject="$6"
  local task_ids="$7" tests="$8" final_delta="$9" directory request verdict seal repo
  local spec_hash plan_hash attachments_hash tasks_hash closure_hash source_content ia_hash changed request_hash verdict_hash
  local subject_manifest default_evidence explicit_evidence default_proof explicit_proof control_scale
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
  closure_hash=$(test_control_closure_hash "$feature/tasks.md")
  subject_manifest=not-applicable
  default_evidence=not-applicable
  explicit_evidence=not-applicable
  default_proof=pending-REV-FINAL
  explicit_proof=pending-REV-FINAL
  control_scale='additions=220..240; churn=220..240; files=6; touchpoints=2'
  if [[ -f "$feature/contracts/source-design.md" ]]; then
    source_content=$(source_hash "$feature" content)
    ia_hash=$(file_hash "$feature/.gatespec/implementation-adjustments.md")
  else
    source_content=not-applicable
    ia_hash=not-applicable
  fi
  if [[ "$scope" == TASKS ]]; then changed=not-applicable; else changed=$(changed_paths_hash "$repo" "$base" "$subject"); fi
  if [[ "$scope" == FINAL ]]; then
    subject_manifest=$(test_control_subject_manifest_hash "$repo" "$subject")
    write_test_control_evidence "$feature" "$subject" "$closure_hash" "$subject_manifest" 00
    default_evidence=$(receipt_field "$directory/round-00-default-off-evidence.md" 'Evidence-SHA256')
    explicit_evidence=$(receipt_field "$directory/round-00-explicit-on-evidence.md" 'Evidence-SHA256')
    default_proof=verified
    explicit_proof=verified
  fi
  if [[ "$scope" != TASKS ]]; then
    # Original Baseline -> Subject: 211 surface/validator lines, 7 CMake
    # wiring lines, 13 guarded store.h lines, and 7 guarded store.cc lines.
    # All are additive; the six changed control files include both production
    # overlap files and surface-only/validator files.
    control_scale='additions=238; churn=238; files=6; touchpoints=2'
  fi
  {
    printf '%s\n' '- **Protocol-Version**: `3`'
    printf -- '- **Review-ID**: `%s`\n' "$id"
    printf '%s\n' '- **Round**: `00`'
    printf -- '- **Scope**: `%s`\n' "$scope"
    printf -- '- **Spec-Content-SHA256**: `%s`\n' "$spec_hash"
    printf -- '- **Plan-Content-SHA256**: `%s`\n' "$plan_hash"
    printf -- '- **Design-Attachments-SHA256**: `%s`\n' "$attachments_hash"
    printf -- '- **Tasks-Definition-SHA256**: `%s`\n' "$tasks_hash"
    printf '%s\n' '- **Test-Control-Mode**: `isolated`'
    printf -- '- **Test-Control-Closure-SHA256**: `%s`\n' "$closure_hash"
    printf -- '- **Test-Control-Subject-Manifest-SHA256**: `%s`\n' "$subject_manifest"
    printf -- '- **Default-OFF-Evidence-SHA256**: `%s`\n' "$default_evidence"
    printf -- '- **Explicit-ON-Evidence-SHA256**: `%s`\n' "$explicit_evidence"
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
    printf '%s\n' '- **Protocol-Version**: `3`'
    printf -- '- **Review-ID**: `%s`\n' "$id"
    printf '%s\n' '- **Round**: `00`'
    printf -- '- **Request-SHA256**: `%s`\n' "$request_hash"
    printf '%s\n' '- **Reviewer-Platform**: `codex`'
    printf -- '- **Reviewer-Context-ID**: `v3-%s-00`\n' "$id"
    printf '%s\n' '- **Isolation**: `fresh`' '- **Status**: `PASS`' '' '## Tests Run' ''
    if [[ "$scope" == TASKS ]]; then printf '%s\n' '- Not run — task-plan review'; else printf -- '- %s — exit 0 fixture\n' "$tests"; fi
    printf '%s\n' '' '## Test Control Audit' '' '- **Mode**: `isolated`' '- **Declared-Controls**: `TC-001`' '- **Undeclared-Controls**: `none`' '- **Orphan-Controls**: `none`'
    printf -- '- **Default-OFF-Proof**: `%s`\n' "$default_proof"
    printf -- '- **Explicit-ON-Proof**: `%s`\n' "$explicit_proof"
    printf -- '- **Test-Control-Scale**: `%s`\n' "$control_scale"
    printf '%s\n' '' '## Blockers' '' '- None' '' '## Observations' '' '- Protocol v3 fixture is complete.' '' '## Limitations' '' '- Semantic freshness is adapter evidence.' '' '- **Verdict-SHA256**: `pending`'
  } > "$verdict"
  self_hash "$verdict" 'Verdict-SHA256'
  verdict_hash=$(receipt_field "$verdict" 'Verdict-SHA256')
  {
    printf '%s\n' '- **Protocol-Version**: `3`'
    printf -- '- **Review-ID**: `%s`\n' "$id"
    printf '%s\n' '- **Round**: `00`' '- **Status**: `PASS`'
    printf -- '- **Request-SHA256**: `%s`\n' "$request_hash"
    printf -- '- **Verdict-SHA256**: `%s`\n' "$verdict_hash"
    printf -- '- **Spec-Content-SHA256**: `%s`\n' "$spec_hash"
    printf -- '- **Plan-Content-SHA256**: `%s`\n' "$plan_hash"
    printf -- '- **Design-Attachments-SHA256**: `%s`\n' "$attachments_hash"
    printf -- '- **Tasks-Definition-SHA256**: `%s`\n' "$tasks_hash"
    printf '%s\n' '- **Test-Control-Mode**: `isolated`'
    printf -- '- **Test-Control-Closure-SHA256**: `%s`\n' "$closure_hash"
    printf -- '- **Test-Control-Subject-Manifest-SHA256**: `%s`\n' "$subject_manifest"
    printf -- '- **Default-OFF-Evidence-SHA256**: `%s`\n' "$default_evidence"
    printf -- '- **Explicit-ON-Evidence-SHA256**: `%s`\n' "$explicit_evidence"
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

rewrite() {
  local file="$1" expression="$2" tmp
  tmp="$file.tmp"
  sed "$expression" "$file" > "$tmp" && mv "$tmp" "$file"
}

rebind_final_evidence_chain() {
  local feature="$1" label="$2" evidence="$3"
  local request verdict seal old_evidence new_evidence old_request new_request old_verdict new_verdict
  request="$feature/.gatespec/reviews/REV-FINAL/round-00-request.md"
  verdict="$feature/.gatespec/reviews/REV-FINAL/round-00-verdict.md"
  seal="$feature/.gatespec/reviews/REV-FINAL/seal.md"
  old_evidence=$(receipt_field "$request" "$label")
  new_evidence=$(receipt_field "$evidence" 'Evidence-SHA256')
  old_request=$(receipt_field "$request" 'Request-SHA256')
  old_verdict=$(receipt_field "$verdict" 'Verdict-SHA256')
  replace_token "$request" "$old_evidence" "$new_evidence"
  self_hash "$request" 'Request-SHA256'
  new_request=$(receipt_field "$request" 'Request-SHA256')
  replace_token "$verdict" "$old_request" "$new_request"
  self_hash "$verdict" 'Verdict-SHA256'
  new_verdict=$(receipt_field "$verdict" 'Verdict-SHA256')
  replace_token "$seal" "$old_evidence" "$new_evidence"
  replace_token "$seal" "$old_request" "$new_request"
  replace_token "$seal" "$old_verdict" "$new_verdict"
  self_hash "$seal" 'Seal-SHA256'
}

blocker_digest() {
  printf '%s\n' "$@" | sha_stream | awk '{print $1}'
}

set_prior_finding() {
  local file="$1" digest="$2" source="$3" required="$4" tasks="$5" tmp="$1.tmp"
  awk -v row="| $digest | $source | $required | $tasks |" '
    $0 == "| none | none | none | none |" {print row; next}
    {print}
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

clear_prior_finding() {
  local file="$1" digest="$2" tmp="$1.tmp"
  awk -v prefix="| $digest |" '
    index($0, prefix) == 1 {print "| none | none | none | none |"; next}
    {print}
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

add_prior_finding() {
  local file="$1" digest="$2" source="$3" required="$4" tasks="$5" tmp="$1.tmp"
  awk -v row="| $digest | $source | $required | $tasks |" '
    $0 == "## GateSpec Prior Review Closure *(gatespec: mandatory)*" {inside=1}
    inside && $0 == "| none | none | none | none |" {print row; added=1; next}
    inside && !added && /^[[:space:]]*$/ {print row; added=1; inside=0}
    {print}
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

write_v3_blocked_task_round() {
  local feature="$1" round="$2" previous="$3" blocker="$4" remediation="$5"
  local directory request verdict spec_hash plan_hash attachments_hash tasks_hash closure_hash
  local source_content ia_hash epoch handoff preserved request_hash
  directory="$feature/.gatespec/reviews/REV-TASKS"
  request="$directory/round-${round}-request.md"
  verdict="$directory/round-${round}-verdict.md"
  mkdir -p "$directory"
  spec_hash=$(content_hash "$feature/spec.md")
  plan_hash=$(content_hash "$feature/plan.md")
  attachments_hash=$(printf '' | sha_stream | awk '{print $1}')
  tasks_hash=$(normalized_tasks_hash "$feature/tasks.md")
  closure_hash=$(test_control_closure_hash "$feature/tasks.md")
  source_content=$(source_hash "$feature" content)
  ia_hash=$(file_hash "$feature/.gatespec/implementation-adjustments.md")
  epoch=$(receipt_field "$feature/.gatespec/execution-state.md" 'Execution-Epoch')
  handoff=$(receipt_field "$feature/.gatespec/execution-state.md" 'Task-Handoff-Commit')
  preserved=$(receipt_field "$feature/.gatespec/execution-state.md" 'Preserved-Reviews-SHA256')
  {
    printf '%s\n' '- **Protocol-Version**: `3`' '- **Review-ID**: `REV-TASKS`'
    printf -- '- **Round**: `%s`\n' "$round"
    printf '%s\n' '- **Scope**: `TASKS`'
    printf -- '- **Spec-Content-SHA256**: `%s`\n' "$spec_hash"
    printf -- '- **Plan-Content-SHA256**: `%s`\n' "$plan_hash"
    printf -- '- **Design-Attachments-SHA256**: `%s`\n' "$attachments_hash"
    printf -- '- **Tasks-Definition-SHA256**: `%s`\n' "$tasks_hash"
    printf '%s\n' '- **Test-Control-Mode**: `isolated`'
    printf -- '- **Test-Control-Closure-SHA256**: `%s`\n' "$closure_hash"
    printf '%s\n' '- **Test-Control-Subject-Manifest-SHA256**: `not-applicable`'
    printf '%s\n' '- **Default-OFF-Evidence-SHA256**: `not-applicable`'
    printf '%s\n' '- **Explicit-ON-Evidence-SHA256**: `not-applicable`'
    printf -- '- **Execution-Epoch**: `%s`\n' "$epoch"
    printf -- '- **Source-Design-Content-SHA256**: `%s`\n' "$source_content"
    printf -- '- **Implementation-Adjustments-SHA256**: `%s`\n' "$ia_hash"
    printf -- '- **Task-Handoff-Commit**: `%s`\n' "$handoff"
    printf -- '- **Preserved-Reviews-SHA256**: `%s`\n' "$preserved"
    printf '%s\n' '- **Implementation-Baseline**: `not-applicable`'
    printf '%s\n' '- **Base-Commit**: `not-applicable`'
    printf '%s\n' '- **Subject-Commit**: `not-applicable`'
    printf '%s\n' '- **Task-IDs**: `none`'
    printf '%s\n' '- **Changed-Paths-SHA256**: `not-applicable`'
    printf '%s\n' '- **Final-Delta-SHA256**: `not-applicable`'
    printf -- '- **Previous-Verdict-SHA256**: `%s`\n\n' "$previous"
    printf '%s\n' '## Required Tests' '' '- Not run — task-plan review' '' '- **Request-SHA256**: `pending`'
  } > "$request"
  self_hash "$request" 'Request-SHA256'
  request_hash=$(receipt_field "$request" 'Request-SHA256')
  {
    printf '%s\n' '- **Protocol-Version**: `3`' '- **Review-ID**: `REV-TASKS`'
    printf -- '- **Round**: `%s`\n' "$round"
    printf -- '- **Request-SHA256**: `%s`\n' "$request_hash"
    printf '%s\n' '- **Reviewer-Platform**: `codex`'
    printf -- '- **Reviewer-Context-ID**: `retask-v3-%s`\n' "$round"
    printf '%s\n' '- **Isolation**: `fresh`' '- **Status**: `BLOCKED`' '' '## Tests Run' ''
    printf '%s\n' '- Not run — task-plan review' '' '## Test Control Audit' ''
    printf '%s\n' '- **Mode**: `isolated`' '- **Declared-Controls**: `TC-001`' '- **Undeclared-Controls**: `none`' '- **Orphan-Controls**: `none`' '- **Default-OFF-Proof**: `pending-REV-FINAL`' '- **Explicit-ON-Proof**: `pending-REV-FINAL`' '- **Test-Control-Scale**: `additions=220..240; churn=220..240; files=6; touchpoints=2`' '' '## Blockers' ''
    printf -- '- BLOCKER: %s\n' "$blocker"
    printf -- '  %s\n\n' "$remediation"
    printf '%s\n' '## Observations' '' '- The task plan remains structurally reviewable.' ''
    printf '%s\n' '## Limitations' '' '- Semantic freshness is adapter evidence.' ''
    printf '%s\n' '- **Verdict-SHA256**: `pending`'
  } > "$verdict"
  self_hash "$verdict" 'Verdict-SHA256'
  BLOCKED_TASK_VERDICT_HASH=$(receipt_field "$verdict" 'Verdict-SHA256')
  BLOCKED_TASK_FINDING_HASH=$(blocker_digest "- BLOCKER: $blocker" "  $remediation")
}

write_stale_v1_task_pass_archive() {
  local feature="$1" archive="$2" request verdict seal tasks_hash request_hash verdict_hash
  local stale_hash=0000000000000000000000000000000000000000000000000000000000000000
  mkdir -p "$archive/reviews/REV-TASKS"
  cp "$feature/tasks.md" "$archive/tasks.md"
  tasks_hash=$(normalized_tasks_hash "$archive/tasks.md")
  request="$archive/reviews/REV-TASKS/round-00-request.md"
  verdict="$archive/reviews/REV-TASKS/round-00-verdict.md"
  seal="$archive/reviews/REV-TASKS/seal.md"
  {
    printf '%s\n' '- **Protocol-Version**: `1`' '- **Review-ID**: `REV-TASKS`' '- **Round**: `00`'
    printf '%s\n' '- **Scope**: `TASKS`'
    printf -- '- **Spec-Content-SHA256**: `%s`\n' "$stale_hash"
    printf -- '- **Plan-Content-SHA256**: `%s`\n' "$stale_hash"
    printf -- '- **Design-Attachments-SHA256**: `%s`\n' "$stale_hash"
    printf -- '- **Tasks-Definition-SHA256**: `%s`\n' "$tasks_hash"
    printf '%s\n' '- **Implementation-Baseline**: `not-applicable`'
    printf '%s\n' '- **Base-Commit**: `not-applicable`'
    printf '%s\n' '- **Subject-Commit**: `not-applicable`'
    printf '%s\n' '- **Task-IDs**: `none`'
    printf '%s\n' '- **Changed-Paths-SHA256**: `not-applicable`'
    printf '%s\n\n' '- **Previous-Verdict-SHA256**: `none`'
    printf '%s\n' '## Required Tests' '' '- Not run — task-plan review' '' '- **Request-SHA256**: `pending`'
  } > "$request"
  self_hash "$request" 'Request-SHA256'
  request_hash=$(receipt_field "$request" 'Request-SHA256')
  {
    printf '%s\n' '- **Protocol-Version**: `1`' '- **Review-ID**: `REV-TASKS`' '- **Round**: `00`'
    printf -- '- **Request-SHA256**: `%s`\n' "$request_hash"
    printf '%s\n' '- **Reviewer-Platform**: `codex`'
    printf '%s\n' '- **Reviewer-Context-ID**: `stale-v1-archive-00`'
    printf '%s\n' '- **Isolation**: `fresh`' '- **Status**: `PASS`' '' '## Tests Run' ''
    printf '%s\n' '- Not run — task-plan review' '' '## Blockers' '' '- None' ''
    printf '%s\n' '## Observations' '' '- The legacy task basis was internally self-consistent.' ''
    printf '%s\n' '## Limitations' '' '- This receipt predates the current v3 artifact basis.' ''
    printf '%s\n' '- **Verdict-SHA256**: `pending`'
  } > "$verdict"
  self_hash "$verdict" 'Verdict-SHA256'
  verdict_hash=$(receipt_field "$verdict" 'Verdict-SHA256')
  {
    printf '%s\n' '- **Protocol-Version**: `1`' '- **Review-ID**: `REV-TASKS`' '- **Round**: `00`'
    printf '%s\n' '- **Status**: `PASS`'
    printf -- '- **Request-SHA256**: `%s`\n' "$request_hash"
    printf -- '- **Verdict-SHA256**: `%s`\n' "$verdict_hash"
    printf -- '- **Spec-Content-SHA256**: `%s`\n' "$stale_hash"
    printf -- '- **Plan-Content-SHA256**: `%s`\n' "$stale_hash"
    printf -- '- **Design-Attachments-SHA256**: `%s`\n' "$stale_hash"
    printf -- '- **Tasks-Definition-SHA256**: `%s`\n' "$tasks_hash"
    printf '%s\n' '- **Implementation-Baseline**: `not-applicable`'
    printf '%s\n' '- **Base-Commit**: `not-applicable`'
    printf '%s\n' '- **Subject-Commit**: `not-applicable`'
    printf '%s\n' '- **Sealed-At**: `2026-08-24T12:00:00Z`' '- **Seal-SHA256**: `pending`'
  } > "$seal"
  self_hash "$seal" 'Seal-SHA256'
}

copy_current_v3_pass_archive() {
  local feature="$1" archive="$2"
  mkdir -p "$archive/reviews"
  cp "$feature/tasks.md" "$archive/tasks.md"
  cp "$feature/.gatespec/execution-state.md" "$archive/execution-state.md"
  cp "$feature/.gatespec/implementation-adjustments.md" "$archive/implementation-adjustments.md"
  cp -R "$feature/.gatespec/reviews/REV-TASKS" "$archive/reviews/REV-TASKS"
}

rebind_v3_archive_handoff() {
  local archive="$1" handoff="$2" request verdict seal state old_handoff
  local old_request_hash new_request_hash old_verdict_hash new_verdict_hash
  request="$archive/reviews/REV-TASKS/round-00-request.md"
  verdict="$archive/reviews/REV-TASKS/round-00-verdict.md"
  seal="$archive/reviews/REV-TASKS/seal.md"
  state="$archive/execution-state.md"
  old_handoff=$(receipt_field "$request" 'Task-Handoff-Commit')
  old_request_hash=$(receipt_field "$request" 'Request-SHA256')
  old_verdict_hash=$(receipt_field "$verdict" 'Verdict-SHA256')
  replace_token "$request" "$old_handoff" "$handoff"
  self_hash "$request" 'Request-SHA256'
  new_request_hash=$(receipt_field "$request" 'Request-SHA256')
  replace_token "$verdict" "$old_request_hash" "$new_request_hash"
  self_hash "$verdict" 'Verdict-SHA256'
  new_verdict_hash=$(receipt_field "$verdict" 'Verdict-SHA256')
  replace_token "$seal" "$old_handoff" "$handoff"
  replace_token "$seal" "$old_request_hash" "$new_request_hash"
  replace_token "$seal" "$old_verdict_hash" "$new_verdict_hash"
  self_hash "$seal" 'Seal-SHA256'
  replace_token "$state" "$old_handoff" "$handoff"
  self_hash "$state" 'Execution-State-SHA256'
}

set_markdown_field() {
  local file="$1" label="$2" value="$3" tmp="$1.tmp"
  awk -v label="$label" -v value="$value" '
    index($0, "- **" label "**: `") == 1 {
      print "- **" label "**: `" value "`"
      next
    }
    {print}
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

rebind_v3_archive_test_control_contract() {
  local archive="$1" handoff="$2" request verdict seal state
  local tasks_hash closure_hash mode declared request_hash verdict_hash
  request="$archive/reviews/REV-TASKS/round-00-request.md"
  verdict="$archive/reviews/REV-TASKS/round-00-verdict.md"
  seal="$archive/reviews/REV-TASKS/seal.md"
  state="$archive/execution-state.md"
  tasks_hash=$(normalized_tasks_hash "$archive/tasks.md")
  closure_hash=$(test_control_closure_hash "$archive/tasks.md")
  mode=$(awk '
    /^## GateSpec Test Control Closure \*\(gatespec: mandatory\)\*$/ {inside=1; next}
    inside && /^- \*\*Mode\*\*:/ {
      value=$0
      sub(/^- \*\*Mode\*\*: `/, "", value); sub(/`$/, "", value)
      print value; exit
    }
  ' "$archive/tasks.md")
  if [[ "$mode" == none ]]; then
    declared=none
  else
    declared=$(awk -F '|' '
      /^## GateSpec Test Control Closure \*\(gatespec: mandatory\)\*$/ {inside=1; next}
      inside && /^## / {exit}
      inside && $2 ~ /^ TC-[0-9][0-9][0-9] $/ {
        value=$2; sub(/^ /, "", value); sub(/ $/, "", value)
        printf "%s%s", (count++ ? ", " : ""), value
      }
      END {print ""}
    ' "$archive/tasks.md")
  fi

  set_markdown_field "$request" 'Tasks-Definition-SHA256' "$tasks_hash"
  set_markdown_field "$request" 'Test-Control-Mode' "$mode"
  set_markdown_field "$request" 'Test-Control-Closure-SHA256' "$closure_hash"
  set_markdown_field "$request" 'Task-Handoff-Commit' "$handoff"
  self_hash "$request" 'Request-SHA256'
  request_hash=$(receipt_field "$request" 'Request-SHA256')

  set_markdown_field "$verdict" 'Request-SHA256' "$request_hash"
  set_markdown_field "$verdict" 'Mode' "$mode"
  set_markdown_field "$verdict" 'Declared-Controls' "$declared"
  set_markdown_field "$verdict" 'Undeclared-Controls' 'none'
  set_markdown_field "$verdict" 'Orphan-Controls' 'none'
  if [[ "$mode" == none ]]; then
    set_markdown_field "$verdict" 'Default-OFF-Proof' 'not-applicable'
    set_markdown_field "$verdict" 'Explicit-ON-Proof' 'not-applicable'
    set_markdown_field "$verdict" 'Test-Control-Scale' \
      'additions=0; churn=0; files=0; touchpoints=0'
  else
    set_markdown_field "$verdict" 'Default-OFF-Proof' 'pending-REV-FINAL'
    set_markdown_field "$verdict" 'Explicit-ON-Proof' 'pending-REV-FINAL'
  fi
  self_hash "$verdict" 'Verdict-SHA256'
  verdict_hash=$(receipt_field "$verdict" 'Verdict-SHA256')

  set_markdown_field "$seal" 'Request-SHA256' "$request_hash"
  set_markdown_field "$seal" 'Verdict-SHA256' "$verdict_hash"
  set_markdown_field "$seal" 'Tasks-Definition-SHA256' "$tasks_hash"
  set_markdown_field "$seal" 'Test-Control-Mode' "$mode"
  set_markdown_field "$seal" 'Test-Control-Closure-SHA256' "$closure_hash"
  set_markdown_field "$seal" 'Task-Handoff-Commit' "$handoff"
  self_hash "$seal" 'Seal-SHA256'

  set_markdown_field "$state" 'Task-Handoff-Commit' "$handoff"
  self_hash "$state" 'Execution-State-SHA256'
}

commit_rebound_archive_handoff() {
  local repo="$1" feature="$2" archive="$3" rel tasks_backup state_backup pending_state
  rel=${feature#"$repo"/}
  tasks_backup=$(mktemp "$TEST_TMP/current-tasks.XXXXXX")
  state_backup=$(mktemp "$TEST_TMP/current-state.XXXXXX")
  pending_state=$(mktemp "$TEST_TMP/pending-state.XXXXXX")
  cp "$feature/tasks.md" "$tasks_backup"
  cp "$feature/.gatespec/execution-state.md" "$state_backup"
  cp "$archive/execution-state.md" "$pending_state"
  set_markdown_field "$pending_state" 'Task-Handoff-Commit' 'pending'
  self_hash "$pending_state" 'Execution-State-SHA256'
  cp "$archive/tasks.md" "$feature/tasks.md"
  cp "$pending_state" "$feature/.gatespec/execution-state.md"
  git -C "$repo" add -- "$rel/tasks.md" "$rel/.gatespec/execution-state.md"
  git -C "$repo" commit -qm 'Record rebound historical task handoff'
  REBOUND_ARCHIVE_HANDOFF=$(git -C "$repo" rev-parse HEAD)
  cp "$tasks_backup" "$feature/tasks.md"
  cp "$state_backup" "$feature/.gatespec/execution-state.md"
  git -C "$repo" add -- "$rel/tasks.md" "$rel/.gatespec/execution-state.md"
  git -C "$repo" commit -qm 'Restore current task epoch after historical handoff'
  rebind_v3_archive_test_control_contract "$archive" "$REBOUND_ARCHIVE_HANDOFF"
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
mkdir -p "$REPO/src/config" "$REPO/src/testonly" "$REPO/tests/config"
cat > "$REPO/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(gatespec_test_control_fixture LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

enable_testing()
add_library(config_store STATIC src/config/store.cc)
target_include_directories(config_store PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src")
add_executable(config_store_normal_test tests/config/store_test.cc)
target_link_libraries(config_store_normal_test PRIVATE config_store)
add_test(NAME config_store_normal COMMAND config_store_normal_test)
install(TARGETS config_store ARCHIVE DESTINATION lib)
EOF
cat > "$REPO/src/config/store.h" <<'EOF'
#pragma once

namespace xclaw {
class ConfigStore final {
 public:
  int Set(int value);
  int value() const;

 private:
  int value_ = 0;
};
}  // namespace xclaw
EOF
cat > "$REPO/src/config/store.cc" <<'EOF'
#include "config/store.h"

namespace xclaw {
int ConfigStore::Set(int value) {
  value_ = value;
  return value_;
}

int ConfigStore::value() const { return value_; }
}  // namespace xclaw
EOF
cat > "$REPO/tests/config/store_test.cc" <<'EOF'
#include "config/store.h"

int main() {
  xclaw::ConfigStore store;
  return store.Set(7) == 7 && store.value() == 7 ? 0 : 1;
}
EOF
cat > "$REPO/src/testonly/unchanged_helper.h" <<'EOF'
#pragma once

namespace xclaw::testonly {
struct ExistingFixtureTag final {};
}  // namespace xclaw::testonly
EOF
git -C "$REPO" add CMakeLists.txt specs src tests
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
### SD1: runtime reload failure reporting
- **Scenario**: An invalid save occurs while active readers retain the prior snapshot.
- **Fixed boundary**: Reload must preserve active connections and the prior valid values.
- **Options**:
  - A. Emit one structured diagnostic and retry on the next poll.
  - B. Return a sticky error through every Current call until a valid save.
- **Recommendation**: A — readers keep the approved non-blocking behavior.
- **Technical basis**: FR-002, D1, SD-FAIL1, and the existing diagnostic surface.
- **Approved**: A (2026-08-24)
## Source Change Manifest
### SD-F1: configuration implementation
- **Operation**: `MODIFY`
- **Path**: `src/config/store.cc`
- **Destination Path**: `not-applicable`
- **Responsibility**: Own validation and atomic snapshot publication.
- **Source refs**: SD-U1, SD-FLOW1, SD-ALG1, SD-FAIL1, SD-TEST1
### SD-F2: configuration tests
- **Operation**: `MODIFY`
- **Path**: `tests/config/store_test.cc`
- **Destination Path**: `not-applicable`
- **Responsibility**: Verify reload success, failure, timing, and shutdown.
- **Source refs**: SD-TEST1
### SD-F3: configuration declaration
- **Operation**: `MODIFY`
- **Path**: `src/config/store.h`
- **Destination Path**: `not-applicable`
- **Responsibility**: Declare the ordinary reload operation while preserving the existing value API.
- **Source refs**: SD-U1, SD-FLOW1
## Symbols and Contracts
### SD-U1: reload contract
- **File**: `src/config/store.h`
- **Visibility / role**: Cross-module ConfigStore API and snapshot owner.
- **Complete declaration**:

```cpp
int Reload(int value);
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
- **Protocol-Version**: `3`
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
- **Protocol-Version**: `3`
- **Review-ID**: `REV-SOURCE`
- **Round**: `00`
- **Scope**: `SOURCE`
- **Spec-Content-SHA256**: `__SPEC_HASH__`
- **Plan-Content-SHA256**: `__PLAN_HASH__`
- **Design-Basis-SHA256**: `__DESIGN_HASH__`
- **Source-Design-Reviewed-SHA256**: `__REVIEWED_HASH__`
- **Source-Baseline-Commit**: `__BASE__`
- **Test-Control-Mode**: `not-applicable`
- **Test-Control-Closure-SHA256**: `not-applicable`
- **Test-Control-Subject-Manifest-SHA256**: `not-applicable`
- **Default-OFF-Evidence-SHA256**: `not-applicable`
- **Explicit-ON-Evidence-SHA256**: `not-applicable`
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
- **Protocol-Version**: `3`
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
- **Protocol-Version**: `3`
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
- **Test-Control-Mode**: `not-applicable`
- **Test-Control-Closure-SHA256**: `not-applicable`
- **Test-Control-Subject-Manifest-SHA256**: `not-applicable`
- **Default-OFF-Evidence-SHA256**: `not-applicable`
- **Explicit-ON-Evidence-SHA256**: `not-applicable`
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

## GateSpec Checkpoint Closure *(gatespec: mandatory)*
| Checkpoint | Contract refs | Production tasks | Verification tasks |
|---|---|---|---|
| REV-FOUNDATION | D1, FR-002, SD-ALG1, SD-F1, SD-F3, SD-FLOW1, SD-U1, SD1 | T001 | T002 |
| REV-US1 | FR-001, SD-F2, SD-FAIL1, SD-TEST1 | none | T004 |
| REV-FINAL | SC-001 | none | T006 |

## GateSpec Prior Review Closure *(gatespec: mandatory)*
| Finding-SHA256 | Source verdict | Required-before | Remediation tasks |
|---|---|---|---|
| none | none | none | none |

## GateSpec Test Control Closure *(gatespec: mandatory)*
- **Mode**: `isolated`
| Control | Verification gap / production invariant | Test-only surface | Production touchpoint | Allowed effect / lifetime | Build switch / validator | Consumer tasks/tests | Default-build proof task |
|---|---|---|---|---|---|---|---|
| TC-001 | Deterministically observe one reload publication without changing the approved ConfigStore API. | src/testonly::xclaw::testonly::ReloadControl | src/config/store.cc::xclaw::ConfigStore::Reload, src/config/store.h::xclaw::ConfigStore::test_reload_observer_ | One named observation on one ConfigStore; a typed per-instance RAII guard restores ordinary execution on destruction. | XCLAW_ENABLE_TEST_HOOKS @ CMakeLists.txt @ tools/testonly_control_validator.sh | T004 | T006 |

## Phase 1: Setup
- [ ] T001 Prepare src/config/store.cc and src/config/store.h for SD-F1, SD-F3, and SD-U1.
## Phase 2: Foundational
- [ ] T002 Implement SD1, SD-FLOW1 and SD-ALG1 in src/config/store.cc and src/config/store.h; register TC-001 for the first time as typed per-instance RAII xclaw::testonly::ReloadControl under src/testonly, add the sole src/config/store.cc::xclaw::ConfigStore::Reload guard, wire XCLAW_ENABLE_TEST_HOOKS default OFF in CMakeLists.txt, and add tools/testonly_control_validator.sh.
- [ ] T003 GateSpec review checkpoint REV-FOUNDATION: run speckit.gatespec.review-implementation --scope REV-FOUNDATION and require .gatespec/reviews/REV-FOUNDATION/seal.md before continuing
## Phase 3: User Story 1 - Hot reload
- [ ] T004 [US1] Implement SD-F2, SD-FAIL1 and SD-TEST1 in tests/config/store_test.cc, add its explicit-ON TC-001 consumer assertions, and validate with bash tools/testonly_control_validator.sh --gatespec-lane explicit-on.
- [ ] T005 [US1] GateSpec review checkpoint REV-US1: run speckit.gatespec.review-implementation --scope REV-US1 and require .gatespec/reviews/REV-US1/seal.md before continuing
## Phase 4: Polish & Cross-Cutting Concerns
- [ ] T006 Validate SD-TEST1 in tests/config/store_test.cc and prove the switch-omitted build through bash tools/testonly_control_validator.sh --gatespec-lane default-off.
- [ ] T007 GateSpec review checkpoint REV-FINAL: run speckit.gatespec.review-implementation --scope REV-FINAL and require .gatespec/reviews/REV-FINAL/seal.md before continuing
EOF
replace_token "$FEATURE/tasks.md" '__CONTENT_HASH__' "$CONTENT_HASH"
cp "$FEATURE/tasks.md" "$TEST_TMP/tasks-good"
expect pass tasks-structure "$FEATURE" "source-enabled tasks bind hash, SD refs, files, and tests"

sed 's/, SD-U1//' "$FEATURE/tasks.md" > "$TEST_TMP/tasks-missing-source-closure-ref"
mv "$TEST_TMP/tasks-missing-source-closure-ref" "$FEATURE/tasks.md"
expect fail tasks-structure "$FEATURE" \
  "Source-enabled Closure covers every approved SD and SD-* ID"
cp "$TEST_TMP/tasks-good" "$FEATURE/tasks.md"

sed 's/, SD1 |/ |/' "$FEATURE/tasks.md" > "$TEST_TMP/tasks-missing-approved-sd"
mv "$TEST_TMP/tasks-missing-approved-sd" "$FEATURE/tasks.md"
expect fail tasks-structure "$FEATURE" \
  "Source-enabled Closure cannot omit an approved SD<n> decision"
cp "$TEST_TMP/tasks-good" "$FEATURE/tasks.md"

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

# Protocol v3 task handoff and complete automated implementation path --------
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

SOURCE_FINDING_REPO="$TEST_TMP/source-finding-repo"
cp -R "$REPO" "$SOURCE_FINDING_REPO"
SOURCE_FINDING_FEATURE="$SOURCE_FINDING_REPO/specs/001-hot-reload"
write_v3_review "$SOURCE_FINDING_FEATURE" REV-TASKS TASKS not-applicable not-applicable \
  not-applicable none 'Not run — task-plan review' not-applicable
SOURCE_FINDING_VERDICT="$SOURCE_FINDING_FEATURE/.gatespec/reviews/REV-TASKS/round-00-verdict.md"
rewrite_source_finding_tmp="$SOURCE_FINDING_VERDICT.tmp"
awk '
  /^- \*\*Status\*\*: `PASS`$/ {print "- **Status**: `BLOCKED`"; next}
  $0 == "- None" {
    print "- BLOCKER: Preserve the approved Source publication invariant."
    print "  Add a failure-path verification before foundation review."
    next
  }
  {print}
' "$SOURCE_FINDING_VERDICT" > "$rewrite_source_finding_tmp"
mv "$rewrite_source_finding_tmp" "$SOURCE_FINDING_VERDICT"
self_hash "$SOURCE_FINDING_VERDICT" 'Verdict-SHA256'
mv "$SOURCE_FINDING_FEATURE/.gatespec/reviews/REV-TASKS/seal.md" \
  "$TEST_TMP/source-finding-unused-seal.md"
source_finding_hash=$(blocker_digest \
  '- BLOCKER: Preserve the approved Source publication invariant.' \
  '  Add a failure-path verification before foundation review.')
set_prior_finding "$SOURCE_FINDING_FEATURE/tasks.md" "$source_finding_hash" \
  '.gatespec/reviews/REV-TASKS/round-00-verdict.md#B01' REV-FOUNDATION T002
expect pass tasks-structure "$SOURCE_FINDING_FEATURE" \
  "v3 Prior Review Closure includes blockers whose Spec, Plan, attachments, and Source basis match"

SOURCE_STALE_REPO="$TEST_TMP/source-stale-finding-repo"
cp -R "$SOURCE_FINDING_REPO" "$SOURCE_STALE_REPO"
SOURCE_STALE_FEATURE="$SOURCE_STALE_REPO/specs/001-hot-reload"
SOURCE_STALE_REQUEST="$SOURCE_STALE_FEATURE/.gatespec/reviews/REV-TASKS/round-00-request.md"
SOURCE_STALE_VERDICT="$SOURCE_STALE_FEATURE/.gatespec/reviews/REV-TASKS/round-00-verdict.md"
SOURCE_OLD_REQUEST_HASH=$(receipt_field "$SOURCE_STALE_REQUEST" 'Request-SHA256')
SOURCE_RECORDED_HASH=$(receipt_field "$SOURCE_STALE_REQUEST" 'Source-Design-Content-SHA256')
SOURCE_ZERO_HASH=0000000000000000000000000000000000000000000000000000000000000000
replace_token "$SOURCE_STALE_REQUEST" "$SOURCE_RECORDED_HASH" "$SOURCE_ZERO_HASH"
self_hash "$SOURCE_STALE_REQUEST" 'Request-SHA256'
SOURCE_NEW_REQUEST_HASH=$(receipt_field "$SOURCE_STALE_REQUEST" 'Request-SHA256')
replace_token "$SOURCE_STALE_VERDICT" "$SOURCE_OLD_REQUEST_HASH" "$SOURCE_NEW_REQUEST_HASH"
self_hash "$SOURCE_STALE_VERDICT" 'Verdict-SHA256'
clear_prior_finding "$SOURCE_STALE_FEATURE/tasks.md" "$source_finding_hash"
expect pass tasks-structure "$SOURCE_STALE_FEATURE" \
  "v3 Prior Review discovery ignores a structurally valid blocker from a stale Source basis"

write_v3_review "$FEATURE" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  'Not run — task-plan review' not-applicable
git -C "$REPO" add specs
git -C "$REPO" commit -qm 'REV-TASKS PASS baseline'
BASELINE=$(git -C "$REPO" rev-parse HEAD)
expect pass task-review "$FEATURE" "Protocol v3 REV-TASKS binds epoch, Source, empty IA, and Task Handoff"
expect pass retask-eligible "$FEATURE" \
  "Protocol v3 with current Source and canonical empty IA is retask-eligible before implementation"

SOURCE_STALE_V1_ARCHIVE_REPO="$TEST_TMP/source-stale-v1-retask-archive"
git clone -q --local --no-hardlinks "$REPO" "$SOURCE_STALE_V1_ARCHIVE_REPO"
SOURCE_STALE_V1_ARCHIVE_FEATURE="$SOURCE_STALE_V1_ARCHIVE_REPO/specs/001-hot-reload"
SOURCE_STALE_V1_ARCHIVE="$SOURCE_STALE_V1_ARCHIVE_FEATURE/.gatespec/archive/20260824T120000Z-retask"
write_stale_v1_task_pass_archive "$SOURCE_STALE_V1_ARCHIVE_FEATURE" "$SOURCE_STALE_V1_ARCHIVE"
expect pass tasks-structure "$SOURCE_STALE_V1_ARCHIVE_FEATURE" \
  "current Protocol v3 accepts a self-consistent stale-basis Protocol v1 retask archive"

SOURCE_STALE_V1_ARCHIVE_DRIFT_REPO="$TEST_TMP/source-stale-v1-retask-archive-drift"
cp -R "$SOURCE_STALE_V1_ARCHIVE_REPO" "$SOURCE_STALE_V1_ARCHIVE_DRIFT_REPO"
SOURCE_STALE_V1_ARCHIVE_DRIFT_FEATURE="$SOURCE_STALE_V1_ARCHIVE_DRIFT_REPO/specs/001-hot-reload"
printf '%s\n' '<!-- stale archived tasks drift -->' \
  >> "$SOURCE_STALE_V1_ARCHIVE_DRIFT_FEATURE/.gatespec/archive/20260824T120000Z-retask/tasks.md"
expect fail tasks-structure "$SOURCE_STALE_V1_ARCHIVE_DRIFT_FEATURE" \
  "stale Protocol v1 retask archives remain subject to internal task-hash validation" \
  "contributing retask archive tasks.md does not match its terminal REV-TASKS request"

SOURCE_ARCHIVE_BAD_HANDOFF_REPO="$TEST_TMP/source-v3-archive-missing-handoff"
git clone -q --local --no-hardlinks "$REPO" "$SOURCE_ARCHIVE_BAD_HANDOFF_REPO"
SOURCE_ARCHIVE_BAD_HANDOFF_FEATURE="$SOURCE_ARCHIVE_BAD_HANDOFF_REPO/specs/001-hot-reload"
SOURCE_ARCHIVE_BAD_HANDOFF="$SOURCE_ARCHIVE_BAD_HANDOFF_FEATURE/.gatespec/archive/20260824T121000Z-retask"
copy_current_v3_pass_archive "$SOURCE_ARCHIVE_BAD_HANDOFF_FEATURE" "$SOURCE_ARCHIVE_BAD_HANDOFF"
rebind_v3_archive_handoff "$SOURCE_ARCHIVE_BAD_HANDOFF" \
  1111111111111111111111111111111111111111
expect fail tasks-structure "$SOURCE_ARCHIVE_BAD_HANDOFF_FEATURE" \
  "archived v3 handoff must resolve even when request, state, verdict, and seal hashes are self-consistent"

SOURCE_ARCHIVE_STABLE_REPO="$TEST_TMP/source-v3-stable-archive"
git clone -q --local --no-hardlinks "$REPO" "$SOURCE_ARCHIVE_STABLE_REPO"
git -C "$SOURCE_ARCHIVE_STABLE_REPO" config user.name 'GateSpec Fixture'
git -C "$SOURCE_ARCHIVE_STABLE_REPO" config user.email 'fixture@example.invalid'
SOURCE_ARCHIVE_STABLE_FEATURE="$SOURCE_ARCHIVE_STABLE_REPO/specs/001-hot-reload"
SOURCE_ARCHIVE_STABLE="$SOURCE_ARCHIVE_STABLE_FEATURE/.gatespec/archive/20260824T121500Z-retask"
copy_current_v3_pass_archive "$SOURCE_ARCHIVE_STABLE_FEATURE" "$SOURCE_ARCHIVE_STABLE"
git -C "$SOURCE_ARCHIVE_STABLE_REPO" add -- \
  specs/001-hot-reload/.gatespec/archive/20260824T121500Z-retask
git -C "$SOURCE_ARCHIVE_STABLE_REPO" commit -qm 'Record canonical Protocol v3 retask archive'
expect pass tasks-structure "$SOURCE_ARCHIVE_STABLE_FEATURE" \
  "a basis-matching Protocol v3 archive preserves the exact Test Control contract"

for stable_part in mode id gap surface touchpoint effect switch wiring validator; do
  stable_repo="$TEST_TMP/source-v3-archive-stable-$stable_part"
  git clone -q --local --no-hardlinks "$SOURCE_ARCHIVE_STABLE_REPO" "$stable_repo"
  git -C "$stable_repo" config user.name 'GateSpec Fixture'
  git -C "$stable_repo" config user.email 'fixture@example.invalid'
  stable_feature="$stable_repo/specs/001-hot-reload"
  stable_archive="$stable_feature/.gatespec/archive/20260824T121500Z-retask"
  case "$stable_part" in
    mode)
      awk '
        /^## GateSpec Test Control Closure \*\(gatespec: mandatory\)\*$/ {
          print
          print "- **Mode**: `none`"
          print "| Control | Verification gap / production invariant | Test-only surface | Production touchpoint | Allowed effect / lifetime | Build switch / validator | Consumer tasks/tests | Default-build proof task |"
          print "|---|---|---|---|---|---|---|---|"
          print "| none | none | none | none | none | none | none | none |"
          skip=1
          next
        }
        skip && /^## / {skip=0}
        !skip {print}
      ' "$stable_archive/tasks.md" > "$TEST_TMP/stable-mode-tasks.md"
      mv "$TEST_TMP/stable-mode-tasks.md" "$stable_archive/tasks.md"
      ;;
    id)
      replace_token "$stable_archive/tasks.md" 'TC-001' 'TC-002'
      ;;
    gap)
      replace_token "$stable_archive/tasks.md" \
        'Deterministically observe one reload publication' \
        'Deterministically count one reload publication'
      ;;
    surface)
      replace_token "$stable_archive/tasks.md" 'ReloadControl' 'RefreshProbe'
      ;;
    touchpoint)
      replace_token "$stable_archive/tasks.md" \
        'src/config/store.cc::xclaw::ConfigStore::Reload' \
        'src/config/store.cc::xclaw::ConfigStore::RefreshObserved'
      ;;
    effect)
      replace_token "$stable_archive/tasks.md" \
        'One named observation on one ConfigStore' \
        'One named counted observation on one ConfigStore'
      ;;
    switch)
      replace_token "$stable_archive/tasks.md" \
        'XCLAW_ENABLE_TEST_HOOKS' 'XCLAW_ENABLE_TEST_CONTROL'
      ;;
    wiring)
      replace_token "$stable_archive/tasks.md" \
        'CMakeLists.txt' 'cmake/TestControl.cmake'
      ;;
    validator)
      replace_token "$stable_archive/tasks.md" \
        'tools/testonly_control_validator.sh' \
        'tools/alternate_testonly_control_validator.sh'
      ;;
  esac
  commit_rebound_archive_handoff "$stable_repo" "$stable_feature" "$stable_archive"
  git -C "$stable_repo" add -- \
    specs/001-hot-reload/.gatespec/archive/20260824T121500Z-retask
  git -C "$stable_repo" commit -qm \
    "Rebind internally consistent $stable_part-mutated historical contract"
  expect fail tasks-structure "$stable_feature" \
    "retask archive cannot mutate the stable Test Control $stable_part registration" \
    "changes immutable Test Control Mode/stable columns"
done

SOURCE_ARCHIVE_TASK_REBIND_REPO="$TEST_TMP/source-v3-archive-task-rebind"
git clone -q --local --no-hardlinks "$SOURCE_ARCHIVE_STABLE_REPO" \
  "$SOURCE_ARCHIVE_TASK_REBIND_REPO"
git -C "$SOURCE_ARCHIVE_TASK_REBIND_REPO" config user.name 'GateSpec Fixture'
git -C "$SOURCE_ARCHIVE_TASK_REBIND_REPO" config user.email 'fixture@example.invalid'
SOURCE_ARCHIVE_TASK_REBIND_FEATURE="$SOURCE_ARCHIVE_TASK_REBIND_REPO/specs/001-hot-reload"
SOURCE_ARCHIVE_TASK_REBIND="$SOURCE_ARCHIVE_TASK_REBIND_FEATURE/.gatespec/archive/20260824T121500Z-retask"
rewrite "$SOURCE_ARCHIVE_TASK_REBIND/tasks.md" \
  's/| T004 | T006 |$/| T002, T006 | T001 |/'
commit_rebound_archive_handoff "$SOURCE_ARCHIVE_TASK_REBIND_REPO" \
  "$SOURCE_ARCHIVE_TASK_REBIND_FEATURE" "$SOURCE_ARCHIVE_TASK_REBIND"
git -C "$SOURCE_ARCHIVE_TASK_REBIND_REPO" add -- \
  specs/001-hot-reload/.gatespec/archive/20260824T121500Z-retask
git -C "$SOURCE_ARCHIVE_TASK_REBIND_REPO" commit -qm \
  'Rebind archived consumer and default proof task IDs only'
expect pass tasks-structure "$SOURCE_ARCHIVE_TASK_REBIND_FEATURE" \
  "retask archive may rebind only consumer and default-proof T### IDs"

SOURCE_ARCHIVE_BLOCKED_REBIND_REPO="$TEST_TMP/source-v3-archive-blocked-task-rebind"
git clone -q --local --no-hardlinks "$SOURCE_ARCHIVE_STABLE_REPO" \
  "$SOURCE_ARCHIVE_BLOCKED_REBIND_REPO"
git -C "$SOURCE_ARCHIVE_BLOCKED_REBIND_REPO" config user.name 'GateSpec Fixture'
git -C "$SOURCE_ARCHIVE_BLOCKED_REBIND_REPO" config user.email 'fixture@example.invalid'
SOURCE_ARCHIVE_BLOCKED_REBIND_FEATURE="$SOURCE_ARCHIVE_BLOCKED_REBIND_REPO/specs/001-hot-reload"
SOURCE_ARCHIVE_BLOCKED_REBIND="$SOURCE_ARCHIVE_BLOCKED_REBIND_FEATURE/.gatespec/archive/20260824T121500Z-retask"
rewrite "$SOURCE_ARCHIVE_BLOCKED_REBIND/tasks.md" \
  's/| T004 | T006 |$/| T002, T006 | T001 |/'
commit_rebound_archive_handoff "$SOURCE_ARCHIVE_BLOCKED_REBIND_REPO" \
  "$SOURCE_ARCHIVE_BLOCKED_REBIND_FEATURE" "$SOURCE_ARCHIVE_BLOCKED_REBIND"
SOURCE_ARCHIVE_BLOCKED_REBIND_VERDICT="$SOURCE_ARCHIVE_BLOCKED_REBIND/reviews/REV-TASKS/round-00-verdict.md"
rewrite "$SOURCE_ARCHIVE_BLOCKED_REBIND_VERDICT" \
  's/- \*\*Status\*\*: `PASS`/- **Status**: `BLOCKED`/'
awk '
  /^## Blockers$/ {inside=1; print; next}
  inside && /^- None$/ {
    print "- BLOCKER: Rebind the archived consumer and default proof tasks after task regeneration."
    print "  Preserve the stable control contract while moving only T### responsibility."
    inside=0
    next
  }
  {print}
' "$SOURCE_ARCHIVE_BLOCKED_REBIND_VERDICT" > "$TEST_TMP/blocked-rebind-verdict.md"
mv "$TEST_TMP/blocked-rebind-verdict.md" "$SOURCE_ARCHIVE_BLOCKED_REBIND_VERDICT"
self_hash "$SOURCE_ARCHIVE_BLOCKED_REBIND_VERDICT" 'Verdict-SHA256'
mv "$SOURCE_ARCHIVE_BLOCKED_REBIND/reviews/REV-TASKS/seal.md" \
  "$TEST_TMP/blocked-rebind-unused-seal.md"
git -C "$SOURCE_ARCHIVE_BLOCKED_REBIND_REPO" add -A -- \
  specs/001-hot-reload/.gatespec/archive/20260824T121500Z-retask
git -C "$SOURCE_ARCHIVE_BLOCKED_REBIND_REPO" commit -qm \
  'Record an unsealed blocked archive after task-only rebinding'
expect fail tasks-structure "$SOURCE_ARCHIVE_BLOCKED_REBIND_FEATURE" \
  "a BLOCKED task-only archive rebind still requires current Prior Review closure" \
  "Prior Review Closure must cover every current-basis BLOCKER item exactly once"
SOURCE_ARCHIVE_BLOCKED_FINDING=$(blocker_digest \
  '- BLOCKER: Rebind the archived consumer and default proof tasks after task regeneration.' \
  '  Preserve the stable control contract while moving only T### responsibility.')
set_prior_finding "$SOURCE_ARCHIVE_BLOCKED_REBIND_FEATURE/tasks.md" \
  "$SOURCE_ARCHIVE_BLOCKED_FINDING" \
  '.gatespec/archive/20260824T121500Z-retask/reviews/REV-TASKS/round-00-verdict.md#B01' \
  REV-FOUNDATION T002
expect pass tasks-structure "$SOURCE_ARCHIVE_BLOCKED_REBIND_FEATURE" \
  "Prior Review Closure can close a BLOCKED archive after consumer/proof-only rebinding"

SOURCE_ARCHIVE_LOOKALIKE_REPO="$TEST_TMP/source-v3-archive-lookalike-closure"
git clone -q --local --no-hardlinks "$SOURCE_ARCHIVE_STABLE_REPO" \
  "$SOURCE_ARCHIVE_LOOKALIKE_REPO"
git -C "$SOURCE_ARCHIVE_LOOKALIKE_REPO" config user.name 'GateSpec Fixture'
git -C "$SOURCE_ARCHIVE_LOOKALIKE_REPO" config user.email 'fixture@example.invalid'
SOURCE_ARCHIVE_LOOKALIKE_FEATURE="$SOURCE_ARCHIVE_LOOKALIKE_REPO/specs/001-hot-reload"
SOURCE_ARCHIVE_LOOKALIKE="$SOURCE_ARCHIVE_LOOKALIKE_FEATURE/.gatespec/archive/20260824T121500Z-retask"
awk '
  /^## GateSpec Test Control Closure \*\(gatespec: mandatory\)\*$/ {
    print "### GateSpec Test Control Closure lookalike"
  }
  {print}
' "$SOURCE_ARCHIVE_LOOKALIKE/tasks.md" > "$TEST_TMP/lookalike-archive-tasks.md"
mv "$TEST_TMP/lookalike-archive-tasks.md" "$SOURCE_ARCHIVE_LOOKALIKE/tasks.md"
commit_rebound_archive_handoff "$SOURCE_ARCHIVE_LOOKALIKE_REPO" \
  "$SOURCE_ARCHIVE_LOOKALIKE_FEATURE" "$SOURCE_ARCHIVE_LOOKALIKE"
git -C "$SOURCE_ARCHIVE_LOOKALIKE_REPO" add -- \
  specs/001-hot-reload/.gatespec/archive/20260824T121500Z-retask
git -C "$SOURCE_ARCHIVE_LOOKALIKE_REPO" commit -qm \
  'Add a lookalike archived Test Control Closure heading'
expect fail tasks-structure "$SOURCE_ARCHIVE_LOOKALIKE_FEATURE" \
  "archived Test Control Closure rejects lookalike headings beside the canonical section" \
  "archived Protocol v3 tasks require one exact Test Control Closure"

SOURCE_ARCHIVE_FALSE_NONE_REPO="$TEST_TMP/source-v3-archive-false-none"
git clone -q --local --no-hardlinks "$SOURCE_ARCHIVE_STABLE_REPO" \
  "$SOURCE_ARCHIVE_FALSE_NONE_REPO"
git -C "$SOURCE_ARCHIVE_FALSE_NONE_REPO" config user.name 'GateSpec Fixture'
git -C "$SOURCE_ARCHIVE_FALSE_NONE_REPO" config user.email 'fixture@example.invalid'
SOURCE_ARCHIVE_FALSE_NONE_FEATURE="$SOURCE_ARCHIVE_FALSE_NONE_REPO/specs/001-hot-reload"
SOURCE_ARCHIVE_FALSE_NONE="$SOURCE_ARCHIVE_FALSE_NONE_FEATURE/.gatespec/archive/20260824T121500Z-retask"
SOURCE_ARCHIVE_FALSE_NONE_REQUEST="$SOURCE_ARCHIVE_FALSE_NONE/reviews/REV-TASKS/round-00-request.md"
SOURCE_ARCHIVE_FALSE_NONE_VERDICT="$SOURCE_ARCHIVE_FALSE_NONE/reviews/REV-TASKS/round-00-verdict.md"
SOURCE_ARCHIVE_FALSE_NONE_SEAL="$SOURCE_ARCHIVE_FALSE_NONE/reviews/REV-TASKS/seal.md"
set_markdown_field "$SOURCE_ARCHIVE_FALSE_NONE_REQUEST" 'Test-Control-Mode' 'none'
self_hash "$SOURCE_ARCHIVE_FALSE_NONE_REQUEST" 'Request-SHA256'
SOURCE_ARCHIVE_FALSE_NONE_REQUEST_HASH=$(receipt_field \
  "$SOURCE_ARCHIVE_FALSE_NONE_REQUEST" 'Request-SHA256')
set_markdown_field "$SOURCE_ARCHIVE_FALSE_NONE_VERDICT" 'Request-SHA256' \
  "$SOURCE_ARCHIVE_FALSE_NONE_REQUEST_HASH"
set_markdown_field "$SOURCE_ARCHIVE_FALSE_NONE_VERDICT" 'Mode' 'none'
set_markdown_field "$SOURCE_ARCHIVE_FALSE_NONE_VERDICT" 'Declared-Controls' 'none'
set_markdown_field "$SOURCE_ARCHIVE_FALSE_NONE_VERDICT" \
  'Default-OFF-Proof' 'not-applicable'
set_markdown_field "$SOURCE_ARCHIVE_FALSE_NONE_VERDICT" \
  'Explicit-ON-Proof' 'not-applicable'
set_markdown_field "$SOURCE_ARCHIVE_FALSE_NONE_VERDICT" 'Test-Control-Scale' \
  'additions=0; churn=0; files=0; touchpoints=0'
self_hash "$SOURCE_ARCHIVE_FALSE_NONE_VERDICT" 'Verdict-SHA256'
SOURCE_ARCHIVE_FALSE_NONE_VERDICT_HASH=$(receipt_field \
  "$SOURCE_ARCHIVE_FALSE_NONE_VERDICT" 'Verdict-SHA256')
set_markdown_field "$SOURCE_ARCHIVE_FALSE_NONE_SEAL" 'Test-Control-Mode' 'none'
set_markdown_field "$SOURCE_ARCHIVE_FALSE_NONE_SEAL" 'Request-SHA256' \
  "$SOURCE_ARCHIVE_FALSE_NONE_REQUEST_HASH"
set_markdown_field "$SOURCE_ARCHIVE_FALSE_NONE_SEAL" 'Verdict-SHA256' \
  "$SOURCE_ARCHIVE_FALSE_NONE_VERDICT_HASH"
self_hash "$SOURCE_ARCHIVE_FALSE_NONE_SEAL" 'Seal-SHA256'
git -C "$SOURCE_ARCHIVE_FALSE_NONE_REPO" add -- \
  specs/001-hot-reload/.gatespec/archive/20260824T121500Z-retask
git -C "$SOURCE_ARCHIVE_FALSE_NONE_REPO" commit -qm \
  'Make terminal receipts falsely claim no archived controls'
expect fail tasks-structure "$SOURCE_ARCHIVE_FALSE_NONE_FEATURE" \
  "archived terminal request and Audit cannot self-consistently hide an isolated Closure" \
  "terminal request/Audit must exactly bind archived Test Control Mode and declared IDs"

SOURCE_ARCHIVE_CLOSURE_MISMATCH_REPO="$TEST_TMP/source-v3-archive-closure-mismatch"
git clone -q --local --no-hardlinks "$SOURCE_ARCHIVE_STABLE_REPO" \
  "$SOURCE_ARCHIVE_CLOSURE_MISMATCH_REPO"
git -C "$SOURCE_ARCHIVE_CLOSURE_MISMATCH_REPO" config user.name 'GateSpec Fixture'
git -C "$SOURCE_ARCHIVE_CLOSURE_MISMATCH_REPO" config user.email 'fixture@example.invalid'
SOURCE_ARCHIVE_CLOSURE_MISMATCH_FEATURE="$SOURCE_ARCHIVE_CLOSURE_MISMATCH_REPO/specs/001-hot-reload"
SOURCE_ARCHIVE_CLOSURE_MISMATCH="$SOURCE_ARCHIVE_CLOSURE_MISMATCH_FEATURE/.gatespec/archive/20260824T121500Z-retask"
SOURCE_ARCHIVE_CLOSURE_REQUEST="$SOURCE_ARCHIVE_CLOSURE_MISMATCH/reviews/REV-TASKS/round-00-request.md"
SOURCE_ARCHIVE_CLOSURE_VERDICT="$SOURCE_ARCHIVE_CLOSURE_MISMATCH/reviews/REV-TASKS/round-00-verdict.md"
SOURCE_ARCHIVE_CLOSURE_SEAL="$SOURCE_ARCHIVE_CLOSURE_MISMATCH/reviews/REV-TASKS/seal.md"
set_markdown_field "$SOURCE_ARCHIVE_CLOSURE_REQUEST" 'Test-Control-Closure-SHA256' \
  '0000000000000000000000000000000000000000000000000000000000000000'
self_hash "$SOURCE_ARCHIVE_CLOSURE_REQUEST" 'Request-SHA256'
SOURCE_ARCHIVE_CLOSURE_REQUEST_HASH=$(receipt_field \
  "$SOURCE_ARCHIVE_CLOSURE_REQUEST" 'Request-SHA256')
set_markdown_field "$SOURCE_ARCHIVE_CLOSURE_VERDICT" 'Request-SHA256' \
  "$SOURCE_ARCHIVE_CLOSURE_REQUEST_HASH"
self_hash "$SOURCE_ARCHIVE_CLOSURE_VERDICT" 'Verdict-SHA256'
SOURCE_ARCHIVE_CLOSURE_VERDICT_HASH=$(receipt_field \
  "$SOURCE_ARCHIVE_CLOSURE_VERDICT" 'Verdict-SHA256')
set_markdown_field "$SOURCE_ARCHIVE_CLOSURE_SEAL" 'Request-SHA256' \
  "$SOURCE_ARCHIVE_CLOSURE_REQUEST_HASH"
set_markdown_field "$SOURCE_ARCHIVE_CLOSURE_SEAL" 'Verdict-SHA256' \
  "$SOURCE_ARCHIVE_CLOSURE_VERDICT_HASH"
set_markdown_field "$SOURCE_ARCHIVE_CLOSURE_SEAL" 'Test-Control-Closure-SHA256' \
  '0000000000000000000000000000000000000000000000000000000000000000'
self_hash "$SOURCE_ARCHIVE_CLOSURE_SEAL" 'Seal-SHA256'
git -C "$SOURCE_ARCHIVE_CLOSURE_MISMATCH_REPO" add -- \
  specs/001-hot-reload/.gatespec/archive/20260824T121500Z-retask
git -C "$SOURCE_ARCHIVE_CLOSURE_MISMATCH_REPO" commit -qm \
  'Bind a terminal archived closure hash to the wrong canonical value'
expect fail tasks-structure "$SOURCE_ARCHIVE_CLOSURE_MISMATCH_FEATURE" \
  "terminal archived Test Control closure hash must bind its archived tasks" \
  "contributing retask archive Test Control Closure does not match its terminal REV-TASKS request"

SOURCE_ARCHIVE_EPOCH_REPO="$TEST_TMP/source-v3-archive-duplicate-epochs"
git clone -q --local --no-hardlinks "$REPO" "$SOURCE_ARCHIVE_EPOCH_REPO"
git -C "$SOURCE_ARCHIVE_EPOCH_REPO" config user.name 'GateSpec Fixture'
git -C "$SOURCE_ARCHIVE_EPOCH_REPO" config user.email 'fixture@example.invalid'
SOURCE_ARCHIVE_EPOCH_FEATURE="$SOURCE_ARCHIVE_EPOCH_REPO/specs/001-hot-reload"
copy_current_v3_pass_archive "$SOURCE_ARCHIVE_EPOCH_FEATURE" \
  "$SOURCE_ARCHIVE_EPOCH_FEATURE/.gatespec/archive/20260824T122000Z-retask"
copy_current_v3_pass_archive "$SOURCE_ARCHIVE_EPOCH_FEATURE" \
  "$SOURCE_ARCHIVE_EPOCH_FEATURE/.gatespec/archive/20260824T123000Z-retask"
git -C "$SOURCE_ARCHIVE_EPOCH_REPO" add -- \
  specs/001-hot-reload/.gatespec/archive
git -C "$SOURCE_ARCHIVE_EPOCH_REPO" commit -qm 'two individually valid v3 archives repeat E1'
expect fail retask-eligible "$SOURCE_ARCHIVE_EPOCH_FEATURE" \
  "v3 retask archive epochs must strictly increase in timestamp order"

SOURCE_RETASK_BLOCKED_REPO="$TEST_TMP/source-retask-blocked"
git clone -q --local --no-hardlinks "$REPO" "$SOURCE_RETASK_BLOCKED_REPO"
git -C "$SOURCE_RETASK_BLOCKED_REPO" checkout -q -B retask-blocked "$HANDOFF"
git -C "$SOURCE_RETASK_BLOCKED_REPO" config user.name 'GateSpec Fixture'
git -C "$SOURCE_RETASK_BLOCKED_REPO" config user.email 'fixture@example.invalid'
SOURCE_RETASK_BLOCKED_FEATURE="$SOURCE_RETASK_BLOCKED_REPO/specs/001-hot-reload"
replace_token "$SOURCE_RETASK_BLOCKED_FEATURE/.gatespec/execution-state.md" \
  '`pending`' "\`$HANDOFF\`"
self_hash "$SOURCE_RETASK_BLOCKED_FEATURE/.gatespec/execution-state.md" 'Execution-State-SHA256'

write_v3_blocked_task_round "$SOURCE_RETASK_BLOCKED_FEATURE" 00 none \
  'Bind the failure-path task to a precise verification command.' \
  'Add explicit failure-path evidence before foundation review.'
BLOCKED_ROUND_00_VERDICT=$BLOCKED_TASK_VERDICT_HASH
add_prior_finding "$SOURCE_RETASK_BLOCKED_FEATURE/tasks.md" "$BLOCKED_TASK_FINDING_HASH" \
  '.gatespec/reviews/REV-TASKS/round-00-verdict.md#B01' REV-FOUNDATION T002

write_v3_blocked_task_round "$SOURCE_RETASK_BLOCKED_FEATURE" 01 "$BLOCKED_ROUND_00_VERDICT" \
  'Separate the atomic publication setup from its behavioral assertion.' \
  'Make the setup responsibility explicit before foundation review.'
BLOCKED_ROUND_01_VERDICT=$BLOCKED_TASK_VERDICT_HASH
add_prior_finding "$SOURCE_RETASK_BLOCKED_FEATURE/tasks.md" "$BLOCKED_TASK_FINDING_HASH" \
  '.gatespec/reviews/REV-TASKS/round-01-verdict.md#B01' REV-FOUNDATION T001

write_v3_blocked_task_round "$SOURCE_RETASK_BLOCKED_FEATURE" 02 "$BLOCKED_ROUND_01_VERDICT" \
  'The remaining task decomposition still couples two independently testable failure cases.' \
  'Regenerate the task plan through the bounded retask recovery path.'
git -C "$SOURCE_RETASK_BLOCKED_REPO" add -- \
  specs/001-hot-reload/tasks.md \
  specs/001-hot-reload/.gatespec/execution-state.md \
  specs/001-hot-reload/.gatespec/reviews/REV-TASKS
expect pass retask-eligible "$SOURCE_RETASK_BLOCKED_FEATURE" \
  "Protocol v3 round-02 BLOCKED chain is eligible when its terminal request binds current tasks and state"

SOURCE_RETASK_TASK_DRIFT_REPO="$TEST_TMP/source-retask-task-drift"
cp -R "$SOURCE_RETASK_BLOCKED_REPO" "$SOURCE_RETASK_TASK_DRIFT_REPO"
SOURCE_RETASK_TASK_DRIFT_FEATURE="$SOURCE_RETASK_TASK_DRIFT_REPO/specs/001-hot-reload"
sed 's/T002 Implement SD1,/T002 Implement drifted SD1,/' \
  "$SOURCE_RETASK_TASK_DRIFT_FEATURE/tasks.md" > "$TEST_TMP/source-retask-task-drift.md"
mv "$TEST_TMP/source-retask-task-drift.md" "$SOURCE_RETASK_TASK_DRIFT_FEATURE/tasks.md"
git -C "$SOURCE_RETASK_TASK_DRIFT_REPO" add -- specs/001-hot-reload/tasks.md
expect fail retask-eligible "$SOURCE_RETASK_TASK_DRIFT_FEATURE" \
  "Protocol v3 retask rejects tasks changed after the terminal round-02 request" \
  "terminal BLOCKED request does not bind the current tasks definition"

SOURCE_RETASK_STATE_DRIFT_REPO="$TEST_TMP/source-retask-state-drift"
cp -R "$SOURCE_RETASK_BLOCKED_REPO" "$SOURCE_RETASK_STATE_DRIFT_REPO"
SOURCE_RETASK_STATE_DRIFT_FEATURE="$SOURCE_RETASK_STATE_DRIFT_REPO/specs/001-hot-reload"
replace_token "$SOURCE_RETASK_STATE_DRIFT_FEATURE/.gatespec/execution-state.md" '`E1`' '`E2`'
self_hash "$SOURCE_RETASK_STATE_DRIFT_FEATURE/.gatespec/execution-state.md" 'Execution-State-SHA256'
replace_token "$SOURCE_RETASK_STATE_DRIFT_FEATURE/.gatespec/implementation-adjustments.md" '`E1`' '`E2`'
git -C "$SOURCE_RETASK_STATE_DRIFT_REPO" add -- \
  specs/001-hot-reload/.gatespec/execution-state.md \
  specs/001-hot-reload/.gatespec/implementation-adjustments.md
expect fail retask-eligible "$SOURCE_RETASK_STATE_DRIFT_FEATURE" \
  "Protocol v3 retask rejects epoch and IA drift after the terminal round-02 request" \
  "terminal BLOCKED request does not bind current Protocol v2/v3 epoch, Source, IA, handoff, and preserved reviews"

SOURCE_RETASK_BOUNDARY_REPO="$TEST_TMP/source-retask-product-handoff"
git clone -q --local --no-hardlinks "$REPO" "$SOURCE_RETASK_BOUNDARY_REPO"
git -C "$SOURCE_RETASK_BOUNDARY_REPO" checkout -q -B product-handoff "$HANDOFF"
git -C "$SOURCE_RETASK_BOUNDARY_REPO" config user.name 'GateSpec Fixture'
git -C "$SOURCE_RETASK_BOUNDARY_REPO" config user.email 'fixture@example.invalid'
SOURCE_RETASK_BOUNDARY_FEATURE="$SOURCE_RETASK_BOUNDARY_REPO/specs/001-hot-reload"
mkdir -p "$SOURCE_RETASK_BOUNDARY_REPO/src/retask-fixture"
printf '%s\n' 'product work hidden in the declared task handoff' \
  > "$SOURCE_RETASK_BOUNDARY_REPO/src/retask-fixture/handoff.txt"
git -C "$SOURCE_RETASK_BOUNDARY_REPO" add -- src/retask-fixture/handoff.txt
git -C "$SOURCE_RETASK_BOUNDARY_REPO" commit -qm 'invalid product-bearing task handoff'
SOURCE_RETASK_BAD_HANDOFF=$(git -C "$SOURCE_RETASK_BOUNDARY_REPO" rev-parse HEAD)
replace_token "$SOURCE_RETASK_BOUNDARY_FEATURE/.gatespec/execution-state.md" \
  '`pending`' "\`$SOURCE_RETASK_BAD_HANDOFF\`"
self_hash "$SOURCE_RETASK_BOUNDARY_FEATURE/.gatespec/execution-state.md" 'Execution-State-SHA256'
SOURCE_RETASK_ORIGINAL_HANDOFF=$HANDOFF
HANDOFF=$SOURCE_RETASK_BAD_HANDOFF
write_v3_review "$SOURCE_RETASK_BOUNDARY_FEATURE" REV-TASKS TASKS not-applicable \
  not-applicable not-applicable none 'Not run — task-plan review' not-applicable
HANDOFF=$SOURCE_RETASK_ORIGINAL_HANDOFF
git -C "$SOURCE_RETASK_BOUNDARY_REPO" add -- specs/001-hot-reload
git -C "$SOURCE_RETASK_BOUNDARY_REPO" commit -qm 'seal invalid product-bearing handoff'
expect fail retask-eligible "$SOURCE_RETASK_BOUNDARY_FEATURE" \
  "Protocol v3 retask inspects the Task-Handoff boundary commit itself" \
  "v3 Task-Handoff commit contains product or unknown path 'src/retask-fixture/handoff.txt'"

SOURCE_RETASK_MERGE_REPO="$TEST_TMP/source-retask-merge-handoff"
git clone -q --local --no-hardlinks "$REPO" "$SOURCE_RETASK_MERGE_REPO"
git -C "$SOURCE_RETASK_MERGE_REPO" checkout -q -B merge-handoff-main "$HANDOFF"
git -C "$SOURCE_RETASK_MERGE_REPO" config user.name 'GateSpec Fixture'
git -C "$SOURCE_RETASK_MERGE_REPO" config user.email 'fixture@example.invalid'
SOURCE_RETASK_MERGE_FEATURE="$SOURCE_RETASK_MERGE_REPO/specs/001-hot-reload"
git -C "$SOURCE_RETASK_MERGE_REPO" checkout -q -b merge-handoff-side
sed 's/T002 Implement SD1,/T002 Implement merged-handoff SD1,/' \
  "$SOURCE_RETASK_MERGE_FEATURE/tasks.md" > "$TEST_TMP/source-retask-merge-tasks.md"
mv "$TEST_TMP/source-retask-merge-tasks.md" "$SOURCE_RETASK_MERGE_FEATURE/tasks.md"
git -C "$SOURCE_RETASK_MERGE_REPO" add -- specs/001-hot-reload/tasks.md
git -C "$SOURCE_RETASK_MERGE_REPO" commit -qm 'side task handoff candidate'
git -C "$SOURCE_RETASK_MERGE_REPO" checkout -q merge-handoff-main
git -C "$SOURCE_RETASK_MERGE_REPO" merge -q --no-ff merge-handoff-side \
  -m 'invalid merged task handoff'
SOURCE_RETASK_MERGE_HANDOFF=$(git -C "$SOURCE_RETASK_MERGE_REPO" rev-parse HEAD)
replace_token "$SOURCE_RETASK_MERGE_FEATURE/.gatespec/execution-state.md" \
  '`pending`' "\`$SOURCE_RETASK_MERGE_HANDOFF\`"
self_hash "$SOURCE_RETASK_MERGE_FEATURE/.gatespec/execution-state.md" 'Execution-State-SHA256'
SOURCE_RETASK_ORIGINAL_HANDOFF=$HANDOFF
HANDOFF=$SOURCE_RETASK_MERGE_HANDOFF
write_v3_review "$SOURCE_RETASK_MERGE_FEATURE" REV-TASKS TASKS not-applicable \
  not-applicable not-applicable none 'Not run — task-plan review' not-applicable
HANDOFF=$SOURCE_RETASK_ORIGINAL_HANDOFF
git -C "$SOURCE_RETASK_MERGE_REPO" add -- specs/001-hot-reload
git -C "$SOURCE_RETASK_MERGE_REPO" commit -qm 'seal invalid merged handoff'
expect fail retask-eligible "$SOURCE_RETASK_MERGE_FEATURE" \
  "Protocol v3 retask rejects a merge commit used as Task-Handoff" \
  "v3 Task-Handoff commit must have exactly one parent"

SOURCE_RETASK_TRANSIENT_REPO="$TEST_TMP/source-retask-transient-product"
git clone -q --local --no-hardlinks "$REPO" "$SOURCE_RETASK_TRANSIENT_REPO"
git -C "$SOURCE_RETASK_TRANSIENT_REPO" config user.name 'GateSpec Fixture'
git -C "$SOURCE_RETASK_TRANSIENT_REPO" config user.email 'fixture@example.invalid'
SOURCE_RETASK_TRANSIENT_FEATURE="$SOURCE_RETASK_TRANSIENT_REPO/specs/001-hot-reload"
mkdir -p "$SOURCE_RETASK_TRANSIENT_REPO/src/retask-fixture"
printf '%s\n' 'transient v3 product implementation' \
  > "$SOURCE_RETASK_TRANSIENT_REPO/src/retask-fixture/transient.txt"
git -C "$SOURCE_RETASK_TRANSIENT_REPO" add -- src/retask-fixture/transient.txt
git -C "$SOURCE_RETASK_TRANSIENT_REPO" commit -qm 'Temporarily add v3 product implementation'
git -C "$SOURCE_RETASK_TRANSIENT_REPO" rm -q -- src/retask-fixture/transient.txt
git -C "$SOURCE_RETASK_TRANSIENT_REPO" commit -qm 'Delete transient v3 product implementation'
expect fail retask-eligible "$SOURCE_RETASK_TRANSIENT_FEATURE" \
  "Protocol v3 retask inspects transient committed product paths, not only the final tree diff"

SOURCE_RETASK_TRANSIENT_TASK_REPO="$TEST_TMP/source-retask-transient-task-progress"
git clone -q --local --no-hardlinks "$REPO" "$SOURCE_RETASK_TRANSIENT_TASK_REPO"
git -C "$SOURCE_RETASK_TRANSIENT_TASK_REPO" config user.name 'GateSpec Fixture'
git -C "$SOURCE_RETASK_TRANSIENT_TASK_REPO" config user.email 'fixture@example.invalid'
SOURCE_RETASK_TRANSIENT_TASK_FEATURE="$SOURCE_RETASK_TRANSIENT_TASK_REPO/specs/001-hot-reload"
cp "$SOURCE_RETASK_TRANSIENT_TASK_FEATURE/tasks.md" "$TEST_TMP/source-retask-before-progress.md"
mark_task "$SOURCE_RETASK_TRANSIENT_TASK_FEATURE/tasks.md" T001
git -C "$SOURCE_RETASK_TRANSIENT_TASK_REPO" add -- specs/001-hot-reload/tasks.md
git -C "$SOURCE_RETASK_TRANSIENT_TASK_REPO" commit -qm 'temporarily record task execution progress'
cp "$TEST_TMP/source-retask-before-progress.md" "$SOURCE_RETASK_TRANSIENT_TASK_FEATURE/tasks.md"
git -C "$SOURCE_RETASK_TRANSIENT_TASK_REPO" add -- specs/001-hot-reload/tasks.md
git -C "$SOURCE_RETASK_TRANSIENT_TASK_REPO" commit -qm 'hide prior task execution progress'
expect fail retask-eligible "$SOURCE_RETASK_TRANSIENT_TASK_FEATURE" \
  "Protocol v3 retask inspects historical task progress even after checkboxes are restored"

SOURCE_RETASK_TRANSIENT_IA_REPO="$TEST_TMP/source-retask-transient-ia"
git clone -q --local --no-hardlinks "$REPO" "$SOURCE_RETASK_TRANSIENT_IA_REPO"
git -C "$SOURCE_RETASK_TRANSIENT_IA_REPO" config user.name 'GateSpec Fixture'
git -C "$SOURCE_RETASK_TRANSIENT_IA_REPO" config user.email 'fixture@example.invalid'
SOURCE_RETASK_TRANSIENT_IA_FEATURE="$SOURCE_RETASK_TRANSIENT_IA_REPO/specs/001-hot-reload"
cp "$SOURCE_RETASK_TRANSIENT_IA_FEATURE/.gatespec/implementation-adjustments.md" \
  "$TEST_TMP/source-retask-empty-ia.md"
cat > "$SOURCE_RETASK_TRANSIENT_IA_FEATURE/.gatespec/implementation-adjustments.md" <<EOF
# GateSpec Implementation Adjustments
- **Execution-Epoch**: \`E1\`
- **Source-Design-Content-SHA256**: \`$CONTENT_HASH\`
## Adjustments
### IA1: transient implementation evidence
- **Source refs**: \`SD-F1\`
- **Task ID**: \`T002\`
- **Changed Paths**: \`src/config/store.cc\`
- **Changed Symbols**: \`ReloadConfig\`
- **Reason**: This fixture proves implementation work once existed.
- **Boundary Impact**: \`none\`
- **Verification**: Historical inspection must retain this evidence.
EOF
git -C "$SOURCE_RETASK_TRANSIENT_IA_REPO" add -- \
  specs/001-hot-reload/.gatespec/implementation-adjustments.md
git -C "$SOURCE_RETASK_TRANSIENT_IA_REPO" commit -qm 'temporarily record implementation adjustment'
cp "$TEST_TMP/source-retask-empty-ia.md" \
  "$SOURCE_RETASK_TRANSIENT_IA_FEATURE/.gatespec/implementation-adjustments.md"
git -C "$SOURCE_RETASK_TRANSIENT_IA_REPO" add -- \
  specs/001-hot-reload/.gatespec/implementation-adjustments.md
git -C "$SOURCE_RETASK_TRANSIENT_IA_REPO" commit -qm 'hide prior implementation adjustment'
expect fail retask-eligible "$SOURCE_RETASK_TRANSIENT_IA_FEATURE" \
  "Protocol v3 retask inspects historical nonempty IA even after the empty baseline is restored"

SOURCE_RETASK_HIDDEN_PRODUCT_REPO="$TEST_TMP/source-retask-hidden-pre-handoff-product"
git clone -q --local --no-hardlinks "$REPO" "$SOURCE_RETASK_HIDDEN_PRODUCT_REPO"
git -C "$SOURCE_RETASK_HIDDEN_PRODUCT_REPO" checkout -q -B hidden-product-handoff "$HANDOFF"
git -C "$SOURCE_RETASK_HIDDEN_PRODUCT_REPO" config user.name 'GateSpec Fixture'
git -C "$SOURCE_RETASK_HIDDEN_PRODUCT_REPO" config user.email 'fixture@example.invalid'
SOURCE_RETASK_HIDDEN_PRODUCT_FEATURE="$SOURCE_RETASK_HIDDEN_PRODUCT_REPO/specs/001-hot-reload"
mkdir -p "$SOURCE_RETASK_HIDDEN_PRODUCT_REPO/src/retask-fixture"
printf '%s\n' 'product work hidden before an empty declared handoff' \
  > "$SOURCE_RETASK_HIDDEN_PRODUCT_REPO/src/retask-fixture/pre-handoff.txt"
git -C "$SOURCE_RETASK_HIDDEN_PRODUCT_REPO" add -- src/retask-fixture/pre-handoff.txt
git -C "$SOURCE_RETASK_HIDDEN_PRODUCT_REPO" commit -qm 'product work before declared task handoff'
git -C "$SOURCE_RETASK_HIDDEN_PRODUCT_REPO" commit --allow-empty -qm 'empty metadata handoff after product work'
SOURCE_RETASK_HIDDEN_HANDOFF=$(git -C "$SOURCE_RETASK_HIDDEN_PRODUCT_REPO" rev-parse HEAD)
replace_token "$SOURCE_RETASK_HIDDEN_PRODUCT_FEATURE/.gatespec/execution-state.md" \
  '`pending`' "\`$SOURCE_RETASK_HIDDEN_HANDOFF\`"
self_hash "$SOURCE_RETASK_HIDDEN_PRODUCT_FEATURE/.gatespec/execution-state.md" 'Execution-State-SHA256'
SOURCE_RETASK_ORIGINAL_HANDOFF=$HANDOFF
HANDOFF=$SOURCE_RETASK_HIDDEN_HANDOFF
write_v3_review "$SOURCE_RETASK_HIDDEN_PRODUCT_FEATURE" REV-TASKS TASKS not-applicable \
  not-applicable not-applicable none 'Not run — task-plan review' not-applicable
HANDOFF=$SOURCE_RETASK_ORIGINAL_HANDOFF
git -C "$SOURCE_RETASK_HIDDEN_PRODUCT_REPO" add -- specs/001-hot-reload
git -C "$SOURCE_RETASK_HIDDEN_PRODUCT_REPO" commit -qm 'seal handoff that hides pre-boundary product work'
expect fail retask-eligible "$SOURCE_RETASK_HIDDEN_PRODUCT_FEATURE" \
  "Protocol v3 Task-Handoff tree cannot hide product work behind a later metadata commit"

SOURCE_RETASK_STATE_HISTORY_REPO="$TEST_TMP/source-retask-state-history-drift"
git clone -q --local --no-hardlinks "$REPO" "$SOURCE_RETASK_STATE_HISTORY_REPO"
git -C "$SOURCE_RETASK_STATE_HISTORY_REPO" config user.name 'GateSpec Fixture'
git -C "$SOURCE_RETASK_STATE_HISTORY_REPO" config user.email 'fixture@example.invalid'
SOURCE_RETASK_STATE_HISTORY_FEATURE="$SOURCE_RETASK_STATE_HISTORY_REPO/specs/001-hot-reload"
SOURCE_RETASK_STATE_HISTORY_FILE="$SOURCE_RETASK_STATE_HISTORY_FEATURE/.gatespec/execution-state.md"
cp "$SOURCE_RETASK_STATE_HISTORY_FILE" "$TEST_TMP/source-retask-valid-state.md"
replace_token "$SOURCE_RETASK_STATE_HISTORY_FILE" '`E1`' '`E3`'
SOURCE_RETASK_STATE_HISTORY_TMP="$SOURCE_RETASK_STATE_HISTORY_FILE.tmp"
awk -v original="$HANDOFF" '
  /^- \*\*Original-Implementation-Baseline\*\*:/ {
    print "- **Original-Implementation-Baseline**: `" original "`"
    next
  }
  {print}
' "$SOURCE_RETASK_STATE_HISTORY_FILE" > "$SOURCE_RETASK_STATE_HISTORY_TMP"
mv "$SOURCE_RETASK_STATE_HISTORY_TMP" "$SOURCE_RETASK_STATE_HISTORY_FILE"
self_hash "$SOURCE_RETASK_STATE_HISTORY_FILE" 'Execution-State-SHA256'
git -C "$SOURCE_RETASK_STATE_HISTORY_REPO" add -- \
  specs/001-hot-reload/.gatespec/execution-state.md
git -C "$SOURCE_RETASK_STATE_HISTORY_REPO" commit -qm 'invalid E1 to E3 execution-state jump and Original drift'
cp "$TEST_TMP/source-retask-valid-state.md" "$SOURCE_RETASK_STATE_HISTORY_FILE"
git -C "$SOURCE_RETASK_STATE_HISTORY_REPO" add -- \
  specs/001-hot-reload/.gatespec/execution-state.md
git -C "$SOURCE_RETASK_STATE_HISTORY_REPO" commit -qm 'restore apparently valid current execution state'
expect fail retask-eligible "$SOURCE_RETASK_STATE_HISTORY_FEATURE" \
  "Protocol v3 retask rejects committed epoch gaps and Original Baseline drift even after restoration"

SOURCE_RETASK_IA_ORDER_REPO="$TEST_TMP/source-retask-empty-ia-reordered"
git clone -q --local --no-hardlinks "$REPO" "$SOURCE_RETASK_IA_ORDER_REPO"
SOURCE_RETASK_IA_ORDER_FEATURE="$SOURCE_RETASK_IA_ORDER_REPO/specs/001-hot-reload"
cat > "$SOURCE_RETASK_IA_ORDER_FEATURE/.gatespec/implementation-adjustments.md" <<EOF
# GateSpec Implementation Adjustments
## Adjustments
- None — no bounded implementation adjustment has been recorded.
- **Source-Design-Content-SHA256**: \`$CONTENT_HASH\`
- **Execution-Epoch**: \`E1\`
EOF
git -C "$SOURCE_RETASK_IA_ORDER_REPO" add -- \
  specs/001-hot-reload/.gatespec/implementation-adjustments.md
expect fail retask-eligible "$SOURCE_RETASK_IA_ORDER_FEATURE" \
  "Protocol v3 canonical empty IA rejects reordered fields and Adjustments section"

SOURCE_RETASK_IA_NONE_REPO="$TEST_TMP/source-retask-empty-ia-none-text"
git clone -q --local --no-hardlinks "$REPO" "$SOURCE_RETASK_IA_NONE_REPO"
SOURCE_RETASK_IA_NONE_FEATURE="$SOURCE_RETASK_IA_NONE_REPO/specs/001-hot-reload"
sed 's/^- None — no bounded implementation adjustment has been recorded\.$/- None — no implementation changes have been recorded./' \
  "$SOURCE_RETASK_IA_NONE_FEATURE/.gatespec/implementation-adjustments.md" \
  > "$TEST_TMP/source-retask-empty-ia-none-text.md"
mv "$TEST_TMP/source-retask-empty-ia-none-text.md" \
  "$SOURCE_RETASK_IA_NONE_FEATURE/.gatespec/implementation-adjustments.md"
git -C "$SOURCE_RETASK_IA_NONE_REPO" add -- \
  specs/001-hot-reload/.gatespec/implementation-adjustments.md
expect fail retask-eligible "$SOURCE_RETASK_IA_NONE_FEATURE" \
  "Protocol v3 canonical empty IA requires the exact fixed None row"

SOURCE_RETASK_IA_PROSE_REPO="$TEST_TMP/source-retask-empty-ia-extra-prose"
git clone -q --local --no-hardlinks "$REPO" "$SOURCE_RETASK_IA_PROSE_REPO"
SOURCE_RETASK_IA_PROSE_FEATURE="$SOURCE_RETASK_IA_PROSE_REPO/specs/001-hot-reload"
printf '%s\n' '- Extra prose outside the canonical empty IA schema.' \
  >> "$SOURCE_RETASK_IA_PROSE_FEATURE/.gatespec/implementation-adjustments.md"
git -C "$SOURCE_RETASK_IA_PROSE_REPO" add -- \
  specs/001-hot-reload/.gatespec/implementation-adjustments.md
expect fail retask-eligible "$SOURCE_RETASK_IA_PROSE_FEATURE" \
  "Protocol v3 canonical empty IA rejects extra fields or prose"

SOURCE_RETASK_IA_REPO="$TEST_TMP/source-retask-nonempty-ia"
cp -R "$REPO" "$SOURCE_RETASK_IA_REPO"
SOURCE_RETASK_IA_FEATURE="$SOURCE_RETASK_IA_REPO/specs/001-hot-reload"
cat > "$SOURCE_RETASK_IA_FEATURE/.gatespec/implementation-adjustments.md" <<'EOF'
# GateSpec Implementation Adjustments
- **Execution-Epoch**: `E1`
- **Source-Design-Content-SHA256**: `__CONTENT_HASH__`
## Adjustments
### IA1: work already began
- **Source refs**: `SD-F1`
- **Task ID**: `T002`
- **Changed Paths**: `src/config/store.cc`
- **Changed Symbols**: `ReloadConfig`
- **Reason**: A product adjustment already exists.
- **Boundary Impact**: `none`
- **Verification**: Unit review would inspect the helper.
EOF
replace_token "$SOURCE_RETASK_IA_FEATURE/.gatespec/implementation-adjustments.md" \
  '__CONTENT_HASH__' "$CONTENT_HASH"
expect fail retask-eligible "$SOURCE_RETASK_IA_FEATURE" \
  "Protocol v3 retask rejects nonempty Source IA even when the dirt path is otherwise allowed"

cat > "$FEATURE/.gatespec/implementation-adjustments.md" <<EOF
# GateSpec Implementation Adjustments
- **Execution-Epoch**: \`E1\`
- **Source-Design-Content-SHA256**: \`$CONTENT_HASH\`
## Adjustments
- None — no bounded implementation adjustment has been recorded.
EOF
mark_task "$FEATURE/tasks.md" T001
mark_task "$FEATURE/tasks.md" T002
mkdir -p "$REPO/src/testonly" "$REPO/tools"
cat > "$REPO/src/config/store.h" <<'EOF'
#pragma once

namespace xclaw {
class ConfigStore;
#ifdef XCLAW_ENABLE_TEST_HOOKS
namespace testonly {
class ReloadControl;
int ObserveReload(ConfigStore& store, int value) noexcept;
}  // namespace testonly
#endif

class ConfigStore final {
 public:
  int Set(int value);
  int Reload(int value);
  int value() const;

 private:
  int value_ = 0;
#ifdef XCLAW_ENABLE_TEST_HOOKS
  friend class testonly::ReloadControl;
  friend int testonly::ObserveReload(ConfigStore& store, int value) noexcept;
  int* test_reload_observer_ = nullptr;
#endif
};
}  // namespace xclaw
EOF
cat > "$REPO/src/config/store.cc" <<'EOF'
#include "config/store.h"

#ifdef XCLAW_ENABLE_TEST_HOOKS
#include "testonly/reload_control.h"
#endif

namespace xclaw {
int ConfigStore::Set(int value) {
  value_ = value;
  return value_;
}

int ConfigStore::Reload(int value) {
#ifdef XCLAW_ENABLE_TEST_HOOKS
  value = testonly::ObserveReload(*this, value);
#endif
  return Set(value);
}

int ConfigStore::value() const { return value_; }
}  // namespace xclaw
EOF
cat > "$REPO/src/testonly/reload_control.h" <<'EOF'
#pragma once

#include "config/store.h"

namespace xclaw::testonly {
class ReloadControl final {
 public:
  ReloadControl(ConfigStore& store, int& observations);
  ~ReloadControl() noexcept;
  ReloadControl(const ReloadControl&) = delete;
  ReloadControl& operator=(const ReloadControl&) = delete;
  ReloadControl(ReloadControl&&) = delete;
  ReloadControl& operator=(ReloadControl&&) = delete;

 private:
  ConfigStore* store_;
  int* previous_observer_;
};

int ObserveReload(ConfigStore& store, int value) noexcept;
}  // namespace xclaw::testonly
EOF
cat > "$REPO/src/testonly/reload_control.cc" <<'EOF'
#include "testonly/reload_control.h"

#include <stdexcept>

namespace xclaw::testonly {
ReloadControl::ReloadControl(ConfigStore& store, int& observations)
    : store_(&store), previous_observer_(store.test_reload_observer_) {
  if (previous_observer_ != nullptr) {
    throw std::logic_error("ReloadControl already installed for this ConfigStore");
  }
  store.test_reload_observer_ = &observations;
}

ReloadControl::~ReloadControl() noexcept {
  store_->test_reload_observer_ = previous_observer_;
}

int ObserveReload(ConfigStore& store, int value) noexcept {
  if (store.test_reload_observer_ != nullptr) {
    ++*store.test_reload_observer_;
  }
  return value;
}
}  // namespace xclaw::testonly
EOF
cat > "$REPO/CMakeLists.txt" <<'EOF'
cmake_minimum_required(VERSION 3.16)
project(gatespec_test_control_fixture LANGUAGES CXX)

set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_EXPORT_COMPILE_COMMANDS ON)

enable_testing()
add_library(config_store STATIC src/config/store.cc)
target_include_directories(config_store PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}/src")
add_executable(config_store_normal_test tests/config/store_test.cc)
target_link_libraries(config_store_normal_test PRIVATE config_store)
add_test(NAME config_store_normal COMMAND config_store_normal_test)

option(XCLAW_ENABLE_TEST_HOOKS "Build isolated test controls" OFF)
if(XCLAW_ENABLE_TEST_HOOKS)
  target_sources(config_store PRIVATE src/testonly/reload_control.cc)
  target_compile_definitions(config_store PUBLIC XCLAW_ENABLE_TEST_HOOKS=1)
endif()

install(TARGETS config_store ARCHIVE DESTINATION lib)
EOF
cat > "$REPO/tools/testonly_control_validator.sh" <<'EOF'
#!/usr/bin/env bash
set -euo pipefail

[[ "$#" -eq 2 && "$1" == --gatespec-lane ]]
lane="${2:-}"
[[ "$lane" == default-off || "$lane" == explicit-on ]]

repo=$(git rev-parse --show-toplevel)
fixture_tmp=$(mktemp -d "/tmp/gatespec-test-control.${lane}.XXXXXX")
trap 'rm -rf "$fixture_tmp"' EXIT HUP INT TERM
build="$fixture_tmp/build"
install_root="$fixture_tmp/install"

hash_stream() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi
}

hash_file() { hash_stream < "$1" | awk '{print $1}'; }
hash_manifest() { LC_ALL=C sort -u "$1" | hash_stream | awk '{print $1}'; }

if [[ "$lane" == default-off ]]; then
  cmake -S "$repo" -B "$build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_root" > "$fixture_tmp/configure.log"
else
  cmake -S "$repo" -B "$build" -DCMAKE_BUILD_TYPE=Release \
    -DCMAKE_INSTALL_PREFIX="$install_root" -DXCLAW_ENABLE_TEST_HOOKS=ON \
    > "$fixture_tmp/configure.log"
fi
cmake --build "$build" > "$fixture_tmp/build.log"
(cd "$build" && ctest --verbose) > "$fixture_tmp/ctest.log"
cmake --install "$build" > "$fixture_tmp/install.log"

compile_manifest="$fixture_tmp/compile.manifest"
find "$build" -type f \( -name '*.o' -o -name '*.obj' \) -print | LC_ALL=C sort |
  while IFS= read -r file; do
    printf '%s\t%s\n' "${file#"$build"/}" "$(hash_file "$file")"
  done > "$compile_manifest"
normalized_compile_commands="$fixture_tmp/compile-commands.normalized"
sed -e "s#$repo#<SOURCE>#g" -e "s#$build#<BUILD>#g" \
  "$build/compile_commands.json" > "$normalized_compile_commands"
printf 'compile-commands\t%s\n' "$(hash_file "$normalized_compile_commands")" \
  >> "$compile_manifest"
cache_switch=$(sed -n \
  's/^XCLAW_ENABLE_TEST_HOOKS:BOOL=\(ON\|OFF\)$/\1/p' "$build/CMakeCache.txt")
[[ "$cache_switch" == ON || "$cache_switch" == OFF ]]
printf 'cache-switch\t%s\n' "$cache_switch" >> "$compile_manifest"
compile=$(hash_manifest "$compile_manifest")

dependency_manifest="$fixture_tmp/dependency.manifest"
dependency_files="$fixture_tmp/dependency.files"
find "$build" -type f \( -name '*.d' -o -name 'depend.make' -o \
    -name 'depend.internal' -o -name 'compiler_depend.make' -o \
    -name 'compiler_depend.internal' \) -print | LC_ALL=C sort > "$dependency_files"
[[ -s "$dependency_files" ]]
while IFS= read -r file; do
  normalized="$fixture_tmp/dependency.normalized"
  sed -e "s#$repo#<SOURCE>#g" -e "s#$build#<BUILD>#g" "$file" > "$normalized"
  printf '%s\t%s\n' "${file#"$build"/}" "$(hash_file "$normalized")"
done < "$dependency_files" > "$dependency_manifest"
[[ -s "$dependency_manifest" ]]
dependency=$(hash_manifest "$dependency_manifest")

artifact_manifest="$fixture_tmp/artifact.manifest"
artifact_symbols="$fixture_tmp/artifact.symbols"
: > "$artifact_symbols"
find "$build" -type f \( -name 'libconfig_store.a' -o \
    -name 'config_store_normal_test' \) \
    -print | LC_ALL=C sort |
  while IFS= read -r file; do
    printf '%s\t%s\n' "${file#"$build"/}" "$(hash_file "$file")"
    if command -v c++filt >/dev/null 2>&1; then
      nm -g "$file" 2>/dev/null | c++filt >> "$artifact_symbols"
    else
      nm -g "$file" 2>/dev/null >> "$artifact_symbols"
    fi
  done > "$artifact_manifest"
artifact=$(hash_manifest "$artifact_manifest")

install_manifest="$fixture_tmp/install-symbol.manifest"
install_symbols="$fixture_tmp/install.symbols"
: > "$install_symbols"
find "$install_root" -type f -print | LC_ALL=C sort |
  while IFS= read -r file; do
    printf 'file\t%s\t%s\n' "${file#"$install_root"/}" "$(hash_file "$file")"
    if command -v c++filt >/dev/null 2>&1; then
      nm -g "$file" 2>/dev/null | c++filt |
        sed -E 's/^[[:xdigit:]]+[[:space:]]+/ADDRESS /' |
        tee -a "$install_symbols" |
        sed "s#^#symbol\t${file#"$install_root"/}\t#"
    else
      nm -g "$file" 2>/dev/null |
        sed -E 's/^[[:xdigit:]]+[[:space:]]+/ADDRESS /' |
        tee -a "$install_symbols" |
        sed "s#^#symbol\t${file#"$install_root"/}\t#"
    fi
  done > "$install_manifest"
install_hash=$(hash_manifest "$install_manifest")

test_manifest="$fixture_tmp/test.manifest"
{
  (cd "$build" && ctest -N) |
    awk '/Test #[0-9]+:/ {sub(/^.*Test #[0-9]+: /, ""); print "test=" $0}'
  sed -n -E \
    's/^.*(NORMAL_ASSERTIONS_PASS|HOOK_CONSUMER_PASS).*$/result=\1/p' \
    "$fixture_tmp/ctest.log"
} | LC_ALL=C sort -u > "$test_manifest"
tests=$(hash_manifest "$test_manifest")

compile_scan="$fixture_tmp/compile.scan"
cp "$normalized_compile_commands" "$compile_scan"
dependency_scan="$fixture_tmp/dependency.scan"
while IFS= read -r file; do
  sed -e "s#$repo#<SOURCE>#g" -e "s#$build#<BUILD>#g" "$file"
done < "$dependency_files" > "$dependency_scan"

compile_hits=$(awk '
  /ENABLE_TEST_HOOKS|[/]testonly[/]/ &&
  $0 !~ /XCLAW_ENABLE_TEST_HOOKS|src[/]testonly[/]reload_control[.]cc/ {hits++}
  END {print hits + 0}
' "$compile_scan")
dependency_hits=$(awk '
  /ENABLE_TEST_HOOKS|[/]testonly[/]/ &&
  $0 !~ /XCLAW_ENABLE_TEST_HOOKS|src[/]testonly[/]reload_control[.](h|cc)/ {hits++}
  END {print hits + 0}
' "$dependency_scan")
artifact_hits=$(awk '
  /testonly|TestOnly|test_only|ENABLE_TEST_HOOKS/ &&
  $0 !~ /xclaw::testonly::ReloadControl|xclaw::testonly::ObserveReload/ {hits++}
  END {print hits + 0}
' "$artifact_symbols")
install_hits=$(awk '
  /testonly|TestOnly|test_only|ENABLE_TEST_HOOKS/ &&
  $0 !~ /xclaw::testonly::ReloadControl|xclaw::testonly::ObserveReload/ {hits++}
  END {print hits + 0}
' "$install_symbols")

grep -Fx test=config_store_normal "$test_manifest" >/dev/null
grep -Fx result=NORMAL_ASSERTIONS_PASS "$test_manifest" >/dev/null
if [[ "$lane" == default-off ]]; then
  [[ "$cache_switch" == OFF ]]
  ! grep -F XCLAW_ENABLE_TEST_HOOKS "$compile_scan" >/dev/null
  ! grep -F src/testonly/reload_control.cc "$compile_scan" >/dev/null
  ! grep -F 'xclaw::testonly' "$install_symbols" >/dev/null
  ! grep -Fx result=HOOK_CONSUMER_PASS "$test_manifest" >/dev/null
  scope=production-install-package-when-present
  source_coverage=absent
  test_coverage=not-applicable
else
  [[ "$cache_switch" == ON ]]
  grep -F XCLAW_ENABLE_TEST_HOOKS "$compile_scan" >/dev/null
  grep -F src/testonly/reload_control.cc "$compile_scan" >/dev/null
  grep -F 'xclaw::testonly::ReloadControl' "$install_symbols" >/dev/null
  grep -F 'xclaw::testonly::ReloadControl' "$artifact_symbols" >/dev/null
  grep -Fx result=HOOK_CONSUMER_PASS "$test_manifest" >/dev/null
  scope=test-build-only
  source_coverage=complete
  test_coverage=complete
fi
[[ "$compile_hits" -eq 0 && "$dependency_hits" -eq 0 && \
   "$artifact_hits" -eq 0 && "$install_hits" -eq 0 ]]

validator_path=tools/testonly_control_validator.sh
printf '| %s | XCLAW_ENABLE_TEST_HOOKS | CMakeLists.txt | bash %s --gatespec-lane %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | %s | PASS |\n' \
  "$validator_path" "$validator_path" "$lane" "$scope" "$compile" "$dependency" "$artifact" \
  "$install_hash" "$tests" "$source_coverage" "$test_coverage" "$compile_hits" \
  "$dependency_hits" "$artifact_hits" "$install_hits"
EOF
git -C "$REPO" add CMakeLists.txt specs src tools/testonly_control_validator.sh
git -C "$REPO" commit -qm 'foundation implementation'
FOUNDATION_SUBJECT=$(git -C "$REPO" rev-parse HEAD)
write_v3_review "$FEATURE" REV-FOUNDATION FOUNDATION "$BASELINE" "$BASELINE" "$FOUNDATION_SUBJECT" T001,T002 \
  'bash tests/unit.sh' not-applicable

NONFINAL_FAILED_REPO="$TEST_TMP/test-control-nonfinal-failed-proof"
cp -R "$REPO" "$NONFINAL_FAILED_REPO"
NONFINAL_FAILED_FEATURE="$NONFINAL_FAILED_REPO/specs/001-hot-reload"
NONFINAL_FAILED_VERDICT="$NONFINAL_FAILED_FEATURE/.gatespec/reviews/REV-FOUNDATION/round-00-verdict.md"
NONFINAL_FAILED_SEAL="$NONFINAL_FAILED_FEATURE/.gatespec/reviews/REV-FOUNDATION/seal.md"
OLD_NONFINAL_FAILED_VERDICT=$(receipt_field "$NONFINAL_FAILED_VERDICT" 'Verdict-SHA256')
rewrite "$NONFINAL_FAILED_VERDICT" \
  's/- \*\*Default-OFF-Proof\*\*: `pending-REV-FINAL`/- **Default-OFF-Proof**: `failed`/'
self_hash "$NONFINAL_FAILED_VERDICT" 'Verdict-SHA256'
NEW_NONFINAL_FAILED_VERDICT=$(receipt_field "$NONFINAL_FAILED_VERDICT" 'Verdict-SHA256')
replace_token "$NONFINAL_FAILED_SEAL" "$OLD_NONFINAL_FAILED_VERDICT" \
  "$NEW_NONFINAL_FAILED_VERDICT"
self_hash "$NONFINAL_FAILED_SEAL" 'Seal-SHA256'
expect_review fail implementation-candidate "$NONFINAL_FAILED_FEATURE" REV-FOUNDATION \
  "a non-final implementation audit cannot use the failed lane-proof state" \
  "non-final implementation proofs must both be pending-REV-FINAL"

mark_task "$FEATURE/tasks.md" T003
expect_review pass implementation-candidate "$FEATURE" REV-FOUNDATION "v3 foundation candidate validates bounded IA in Subject-Commit"
git -C "$REPO" add specs
git -C "$REPO" commit -qm 'REV-FOUNDATION PASS metadata'
expect_review pass implementation-review "$FEATURE" REV-FOUNDATION "v3 foundation committed review passes"

mark_task "$FEATURE/tasks.md" T004
mkdir -p "$REPO/tests/config"
cat > "$REPO/tests/config/store_test.cc" <<'EOF'
#include "config/store.h"
#include <iostream>
#ifdef XCLAW_ENABLE_TEST_HOOKS
#include "testonly/reload_control.h"
#endif

int main() {
  xclaw::ConfigStore store;
  if (store.Reload(11) != 11 || store.value() != 11) return 1;
#ifdef XCLAW_ENABLE_TEST_HOOKS
  xclaw::ConfigStore ordinary;
  int observations = 0;
  {
    xclaw::testonly::ReloadControl control(store, observations);
    store.Reload(1);
    ordinary.Reload(2);
    if (observations != 1 || store.value() != 1) return 1;
  }
  store.Reload(3);
  if (observations != 1 || store.value() != 3 || ordinary.value() != 2) return 1;
  std::cout << "HOOK_CONSUMER_PASS\n";
#endif
  std::cout << "NORMAL_ASSERTIONS_PASS\n";
  return 0;
}
EOF
git -C "$REPO" add specs tests/config
git -C "$REPO" commit -qm 'user story implementation'
US_SUBJECT=$(git -C "$REPO" rev-parse HEAD)
write_v3_review "$FEATURE" REV-US1 US1 "$BASELINE" "$FOUNDATION_SUBJECT" "$US_SUBJECT" T004 \
  'bash tests/integration.sh' not-applicable
mark_task "$FEATURE/tasks.md" T005
expect_review pass implementation-candidate "$FEATURE" REV-US1 "v3 user-story candidate validates automatically"
git -C "$REPO" add specs
git -C "$REPO" commit -qm 'REV-US1 PASS metadata'
expect_review pass implementation-review "$FEATURE" REV-US1 "v3 user-story committed review passes"

mark_task "$FEATURE/tasks.md" T006
git -C "$REPO" add specs
git -C "$REPO" commit -qm 'final validation subject'
FINAL_SUBJECT=$(git -C "$REPO" rev-parse HEAD)
FINAL_DELTA=$(final_delta_hash "$REPO" "$BASE" "$FINAL_SUBJECT")
write_v3_review "$FEATURE" REV-FINAL FINAL "$BASELINE" "$BASE" "$FINAL_SUBJECT" T001,T002,T004,T006 \
  'bash tests/run-all.sh' "$FINAL_DELTA"
mark_task "$FEATURE/tasks.md" T007
if fresh_test_control_rows_match "$FEATURE" "$FINAL_SUBJECT" 00; then
  PASS=$((PASS + 1))
  echo "✓ fresh detached clones reproduce both validator rows byte-for-byte without tracked delta"
else
  FAIL=$((FAIL + 1))
  echo "✗ fresh detached clone validator rows are unstable or dirty"
fi

BAD_SCALE_REPO="$TEST_TMP/test-control-scale-additions"
cp -R "$REPO" "$BAD_SCALE_REPO"
BAD_SCALE_FEATURE="$BAD_SCALE_REPO/specs/001-hot-reload"
BAD_SCALE_VERDICT="$BAD_SCALE_FEATURE/.gatespec/reviews/REV-FINAL/round-00-verdict.md"
BAD_SCALE_SEAL="$BAD_SCALE_FEATURE/.gatespec/reviews/REV-FINAL/seal.md"
OLD_SCALE_VERDICT=$(receipt_field "$BAD_SCALE_VERDICT" 'Verdict-SHA256')
awk '
  /^- \*\*Test-Control-Scale\*\*:/ {
    print "- **Test-Control-Scale**: `additions=2; churn=1; files=6; touchpoints=2`"
    next
  }
  {print}
' "$BAD_SCALE_VERDICT" > "$TEST_TMP/bad-scale-verdict"
mv "$TEST_TMP/bad-scale-verdict" "$BAD_SCALE_VERDICT"
self_hash "$BAD_SCALE_VERDICT" 'Verdict-SHA256'
NEW_SCALE_VERDICT=$(receipt_field "$BAD_SCALE_VERDICT" 'Verdict-SHA256')
replace_token "$BAD_SCALE_SEAL" "$OLD_SCALE_VERDICT" "$NEW_SCALE_VERDICT"
self_hash "$BAD_SCALE_SEAL" 'Seal-SHA256'
expect_review fail implementation-candidate "$BAD_SCALE_FEATURE" REV-FINAL \
  "implementation Test-Control-Scale additions cannot exceed churn" \
  "Test-Control-Scale additions cannot exceed churn"

BAD_TOUCHPOINT_SCALE_REPO="$TEST_TMP/test-control-scale-touchpoints"
cp -R "$REPO" "$BAD_TOUCHPOINT_SCALE_REPO"
BAD_TOUCHPOINT_SCALE_FEATURE="$BAD_TOUCHPOINT_SCALE_REPO/specs/001-hot-reload"
BAD_TOUCHPOINT_SCALE_VERDICT="$BAD_TOUCHPOINT_SCALE_FEATURE/.gatespec/reviews/REV-FINAL/round-00-verdict.md"
BAD_TOUCHPOINT_SCALE_SEAL="$BAD_TOUCHPOINT_SCALE_FEATURE/.gatespec/reviews/REV-FINAL/seal.md"
OLD_TOUCHPOINT_SCALE_VERDICT=$(receipt_field "$BAD_TOUCHPOINT_SCALE_VERDICT" 'Verdict-SHA256')
awk '
  /^- \*\*Test-Control-Scale\*\*:/ {
    print "- **Test-Control-Scale**: `additions=238; churn=238; files=6; touchpoints=1`"
    next
  }
  {print}
' "$BAD_TOUCHPOINT_SCALE_VERDICT" > "$TEST_TMP/bad-touchpoint-scale-verdict"
mv "$TEST_TMP/bad-touchpoint-scale-verdict" "$BAD_TOUCHPOINT_SCALE_VERDICT"
self_hash "$BAD_TOUCHPOINT_SCALE_VERDICT" 'Verdict-SHA256'
NEW_TOUCHPOINT_SCALE_VERDICT=$(receipt_field "$BAD_TOUCHPOINT_SCALE_VERDICT" 'Verdict-SHA256')
replace_token "$BAD_TOUCHPOINT_SCALE_SEAL" "$OLD_TOUCHPOINT_SCALE_VERDICT" \
  "$NEW_TOUCHPOINT_SCALE_VERDICT"
self_hash "$BAD_TOUCHPOINT_SCALE_SEAL" 'Seal-SHA256'
expect_review fail implementation-candidate "$BAD_TOUCHPOINT_SCALE_FEATURE" REV-FINAL \
  "implementation Test-Control-Scale binds the exact declared touchpoint count" \
  "touchpoints must equal 2 unique declared production path::symbol touchpoint(s)"

MISSING_AUDIT_REPO="$TEST_TMP/test-control-missing-audit"
cp -R "$REPO" "$MISSING_AUDIT_REPO"
MISSING_AUDIT_FEATURE="$MISSING_AUDIT_REPO/specs/001-hot-reload"
MISSING_AUDIT_VERDICT="$MISSING_AUDIT_FEATURE/.gatespec/reviews/REV-FINAL/round-00-verdict.md"
MISSING_AUDIT_SEAL="$MISSING_AUDIT_FEATURE/.gatespec/reviews/REV-FINAL/seal.md"
OLD_AUDIT_VERDICT=$(receipt_field "$MISSING_AUDIT_VERDICT" 'Verdict-SHA256')
awk '
  /^## Test Control Audit$/ {skip=1; next}
  skip && /^## Blockers$/ {skip=0}
  !skip {print}
' "$MISSING_AUDIT_VERDICT" > "$TEST_TMP/missing-audit-verdict"
mv "$TEST_TMP/missing-audit-verdict" "$MISSING_AUDIT_VERDICT"
self_hash "$MISSING_AUDIT_VERDICT" 'Verdict-SHA256'
NEW_AUDIT_VERDICT=$(receipt_field "$MISSING_AUDIT_VERDICT" 'Verdict-SHA256')
replace_token "$MISSING_AUDIT_SEAL" "$OLD_AUDIT_VERDICT" "$NEW_AUDIT_VERDICT"
self_hash "$MISSING_AUDIT_SEAL" 'Seal-SHA256'
expect_review fail implementation-candidate "$MISSING_AUDIT_FEATURE" REV-FINAL \
  "v3 implementation verdict cannot omit Test Control Audit" "Test Control Audit"

MISSING_EVIDENCE_REPO="$TEST_TMP/test-control-missing-evidence"
cp -R "$REPO" "$MISSING_EVIDENCE_REPO"
MISSING_EVIDENCE_FEATURE="$MISSING_EVIDENCE_REPO/specs/001-hot-reload"
rm -f "$MISSING_EVIDENCE_FEATURE/.gatespec/reviews/REV-FINAL/round-00-default-off-evidence.md"
expect_review fail implementation-candidate "$MISSING_EVIDENCE_FEATURE" REV-FINAL \
  "isolated REV-FINAL requires default-off evidence" "default-off evidence"

SWAPPED_EVIDENCE_REPO="$TEST_TMP/test-control-swapped-evidence"
cp -R "$REPO" "$SWAPPED_EVIDENCE_REPO"
SWAPPED_EVIDENCE_FEATURE="$SWAPPED_EVIDENCE_REPO/specs/001-hot-reload"
SWAPPED_REVIEW="$SWAPPED_EVIDENCE_FEATURE/.gatespec/reviews/REV-FINAL"
mv "$SWAPPED_REVIEW/round-00-default-off-evidence.md" "$TEST_TMP/default-evidence"
mv "$SWAPPED_REVIEW/round-00-explicit-on-evidence.md" "$SWAPPED_REVIEW/round-00-default-off-evidence.md"
mv "$TEST_TMP/default-evidence" "$SWAPPED_REVIEW/round-00-explicit-on-evidence.md"
expect_review fail implementation-candidate "$SWAPPED_EVIDENCE_FEATURE" REV-FINAL \
  "REV-FINAL rejects swapped lane evidence"

WRONG_SUBJECT_REPO="$TEST_TMP/test-control-wrong-subject-evidence"
cp -R "$REPO" "$WRONG_SUBJECT_REPO"
WRONG_SUBJECT_FEATURE="$WRONG_SUBJECT_REPO/specs/001-hot-reload"
WRONG_SUBJECT_EVIDENCE="$WRONG_SUBJECT_FEATURE/.gatespec/reviews/REV-FINAL/round-00-default-off-evidence.md"
replace_token "$WRONG_SUBJECT_EVIDENCE" "$FINAL_SUBJECT" "$US_SUBJECT"
self_hash "$WRONG_SUBJECT_EVIDENCE" 'Evidence-SHA256'
rebind_final_evidence_chain "$WRONG_SUBJECT_FEATURE" 'Default-OFF-Evidence-SHA256' "$WRONG_SUBJECT_EVIDENCE"
expect_review fail implementation-candidate "$WRONG_SUBJECT_FEATURE" REV-FINAL \
  "REV-FINAL rejects evidence bound to the wrong Subject"

STALE_EVIDENCE_REPO="$TEST_TMP/test-control-stale-evidence"
cp -R "$REPO" "$STALE_EVIDENCE_REPO"
STALE_EVIDENCE_FEATURE="$STALE_EVIDENCE_REPO/specs/001-hot-reload"
STALE_EVIDENCE="$STALE_EVIDENCE_FEATURE/.gatespec/reviews/REV-FINAL/round-00-default-off-evidence.md"
STALE_CLOSURE=$(receipt_field "$STALE_EVIDENCE" 'Test-Control-Closure-SHA256')
replace_token "$STALE_EVIDENCE" "$STALE_CLOSURE" 0000000000000000000000000000000000000000000000000000000000000000
self_hash "$STALE_EVIDENCE" 'Evidence-SHA256'
rebind_final_evidence_chain "$STALE_EVIDENCE_FEATURE" 'Default-OFF-Evidence-SHA256' "$STALE_EVIDENCE"
expect_review fail implementation-candidate "$STALE_EVIDENCE_FEATURE" REV-FINAL \
  "REV-FINAL rejects evidence bound to a stale Test Control Closure"

EXPLICIT_OFF_REPO="$TEST_TMP/test-control-explicit-off-evidence"
cp -R "$REPO" "$EXPLICIT_OFF_REPO"
EXPLICIT_OFF_FEATURE="$EXPLICIT_OFF_REPO/specs/001-hot-reload"
EXPLICIT_OFF_EVIDENCE="$EXPLICIT_OFF_FEATURE/.gatespec/reviews/REV-FINAL/round-00-default-off-evidence.md"
rewrite "$EXPLICIT_OFF_EVIDENCE" 's/`omitted-default-off`/`explicit-off`/'
self_hash "$EXPLICIT_OFF_EVIDENCE" 'Evidence-SHA256'
rebind_final_evidence_chain "$EXPLICIT_OFF_FEATURE" 'Default-OFF-Evidence-SHA256' "$EXPLICIT_OFF_EVIDENCE"
expect_review fail implementation-candidate "$EXPLICIT_OFF_FEATURE" REV-FINAL \
  "default-off evidence cannot pass an explicit OFF override"

FORBIDDEN_HIT_REPO="$TEST_TMP/test-control-forbidden-hit"
cp -R "$REPO" "$FORBIDDEN_HIT_REPO"
FORBIDDEN_HIT_FEATURE="$FORBIDDEN_HIT_REPO/specs/001-hot-reload"
FORBIDDEN_HIT_EVIDENCE="$FORBIDDEN_HIT_FEATURE/.gatespec/reviews/REV-FINAL/round-00-default-off-evidence.md"
rewrite "$FORBIDDEN_HIT_EVIDENCE" 's/| 0 | 0 | 0 | 0 | PASS |/| 1 | 0 | 0 | 0 | PASS |/'
self_hash "$FORBIDDEN_HIT_EVIDENCE" 'Evidence-SHA256'
rebind_final_evidence_chain "$FORBIDDEN_HIT_FEATURE" 'Default-OFF-Evidence-SHA256' "$FORBIDDEN_HIT_EVIDENCE"
expect_review fail implementation-candidate "$FORBIDDEN_HIT_FEATURE" REV-FINAL \
  "default-off evidence rejects undeclared compile hits"

expect_review pass implementation-candidate "$FEATURE" REV-FINAL "v3 cumulative REV-FINAL reconciles Source paths, Test Controls, and raw delta"
read -r ACTUAL_TC_ADDITIONS ACTUAL_TC_CHURN ACTUAL_TC_FILES < <(
  git -C "$REPO" diff --numstat "$BASE" "$FINAL_SUBJECT" -- \
    CMakeLists.txt src/config/store.h src/config/store.cc src/testonly \
    tools/testonly_control_validator.sh |
    awk '
      {additions += $1; deletions += $2; files++}
      END {
        # Exclude the ordinary Source-designed Reload declaration/function:
        # one header line plus signature/result/brace/spacing in store.cc.
        additions -= 5
        printf "%d %d %d\n", additions, additions + deletions, files
      }
    '
)
if [[ "$ACTUAL_TC_ADDITIONS" -eq 238 && "$ACTUAL_TC_CHURN" -eq 238 && \
      "$ACTUAL_TC_FILES" -eq 6 ]]; then
  PASS=$((PASS + 1))
  echo "✓ exact Test-Control scale is reproducible separately from overlapping Production files"
else
  FAIL=$((FAIL + 1))
  echo "✗ exact Test-Control scale (got additions=$ACTUAL_TC_ADDITIONS churn=$ACTUAL_TC_CHURN files=$ACTUAL_TC_FILES)"
fi
git -C "$REPO" add specs
git -C "$REPO" commit -qm 'REV-FINAL PASS metadata'
FINAL_REVIEW_COMMIT=$(git -C "$REPO" rev-parse HEAD)
expect_review pass implementation-review "$FEATURE" REV-FINAL "v3 committed REV-FINAL passes without user checkpoint approval"

POST_SEAL_REPO="$TEST_TMP/test-control-post-seal-source"
git clone -q --local --no-hardlinks "$REPO" "$POST_SEAL_REPO"
git -C "$POST_SEAL_REPO" config user.name 'GateSpec Source Fixture'
git -C "$POST_SEAL_REPO" config user.email 'source-fixture@example.invalid'
POST_SEAL_FEATURE="$POST_SEAL_REPO/specs/001-hot-reload"
printf '%s\n' '// changed after REV-FINAL seal' >> "$POST_SEAL_REPO/src/testonly/reload_control.h"
git -C "$POST_SEAL_REPO" add src/testonly/reload_control.h
git -C "$POST_SEAL_REPO" commit -qm 'mutate Test Control after final seal'
expect_review fail implementation-review "$POST_SEAL_FEATURE" REV-FINAL \
  "post-seal Test Control source changes invalidate REV-FINAL"

SYMLINK_VALIDATOR_REPO="$TEST_TMP/test-control-symlink-validator"
git clone -q --local --no-hardlinks "$REPO" "$SYMLINK_VALIDATOR_REPO"
git -C "$SYMLINK_VALIDATOR_REPO" checkout -q -b symlink-validator "$FINAL_SUBJECT"
git -C "$SYMLINK_VALIDATOR_REPO" config user.name 'GateSpec Source Fixture'
git -C "$SYMLINK_VALIDATOR_REPO" config user.email 'source-fixture@example.invalid'
SYMLINK_VALIDATOR_FEATURE="$SYMLINK_VALIDATOR_REPO/specs/001-hot-reload"
mv "$SYMLINK_VALIDATOR_REPO/tools/testonly_control_validator.sh" \
  "$SYMLINK_VALIDATOR_REPO/tools/testonly_control_validator_real.sh"
ln -s testonly_control_validator_real.sh \
  "$SYMLINK_VALIDATOR_REPO/tools/testonly_control_validator.sh"
git -C "$SYMLINK_VALIDATOR_REPO" add tools
git -C "$SYMLINK_VALIDATOR_REPO" commit -qm 'replace validator with a symlink'
SYMLINK_VALIDATOR_SUBJECT=$(git -C "$SYMLINK_VALIDATOR_REPO" rev-parse HEAD)
SYMLINK_VALIDATOR_DELTA=$(final_delta_hash "$SYMLINK_VALIDATOR_REPO" "$BASE" "$SYMLINK_VALIDATOR_SUBJECT")
write_v3_review "$SYMLINK_VALIDATOR_FEATURE" REV-FINAL FINAL "$BASELINE" "$BASE" \
  "$SYMLINK_VALIDATOR_SUBJECT" T001,T002,T004,T006 'bash tests/run-all.sh' "$SYMLINK_VALIDATOR_DELTA"
mark_task "$SYMLINK_VALIDATOR_FEATURE/tasks.md" T007
expect_review fail implementation-candidate "$SYMLINK_VALIDATOR_FEATURE" REV-FINAL \
  "REV-FINAL Subject manifest rejects a symlink validator" "symlink"

IA_CONTROL_REPO="$TEST_TMP/test-control-ia-wiring"
git clone -q --local --no-hardlinks "$REPO" "$IA_CONTROL_REPO"
git -C "$IA_CONTROL_REPO" checkout -q -b ia-control-wiring "$FINAL_SUBJECT"
git -C "$IA_CONTROL_REPO" config user.name 'GateSpec Source Fixture'
git -C "$IA_CONTROL_REPO" config user.email 'source-fixture@example.invalid'
IA_CONTROL_FEATURE="$IA_CONTROL_REPO/specs/001-hot-reload"
cat >> "$IA_CONTROL_FEATURE/.gatespec/implementation-adjustments.md" <<'EOF'
### IA2: late test hook wiring change
- **Source refs**: `SD-F1`
- **Task ID**: `T006`
- **Changed Paths**: `CMakeLists.txt, src/testonly/reload_control.h`
- **Changed Symbols**: `XCLAW_ENABLE_TEST_HOOKS, ReloadControl`
- **Reason**: The implementation attempted to alter the registered control wiring.
- **Boundary Impact**: `none`
- **Verification**: The final review must reject this as outside bounded IA.
EOF
git -C "$IA_CONTROL_REPO" add specs
git -C "$IA_CONTROL_REPO" commit -qm 'record late Test Control wiring as IA'
IA_CONTROL_SUBJECT=$(git -C "$IA_CONTROL_REPO" rev-parse HEAD)
IA_CONTROL_DELTA=$(final_delta_hash "$IA_CONTROL_REPO" "$BASE" "$IA_CONTROL_SUBJECT")
write_v3_review "$IA_CONTROL_FEATURE" REV-FINAL FINAL "$BASELINE" "$BASE" \
  "$IA_CONTROL_SUBJECT" T001,T002,T004,T006 'bash tests/run-all.sh' "$IA_CONTROL_DELTA"
mark_task "$IA_CONTROL_FEATURE/tasks.md" T007
expect_review fail implementation-candidate "$IA_CONTROL_FEATURE" REV-FINAL \
  "IA cannot change registered Test Control wiring" "Test Control"

expect fail acceptance "$FEATURE" "REV-FINAL alone cannot complete without acceptance" "explicit final user acceptance is missing"
expect pass acceptance-candidate "$FEATURE" "final delivery is ready for one user acceptance" \
  "Actual production files: 3"
if grep -F 'Actual production additions: 32' "$TEST_TMP/out" >/dev/null &&
   grep -F 'Actual production churn: 32' "$TEST_TMP/out" >/dev/null &&
   grep -F 'Actual production files: 3' "$TEST_TMP/out" >/dev/null &&
   grep -F 'Binary production files without line counts: 0' "$TEST_TMP/out" >/dev/null; then
  PASS=$((PASS + 1)); echo "✓ Production metrics retain full wiring/touchpoint files while Test-Control scale separately overlaps dedicated hook lines"
else
  FAIL=$((FAIL + 1)); echo "✗ final Git delivery metrics"; sed 's/^/    /' "$TEST_TMP/out"
fi

FINAL_SEAL="$FEATURE/.gatespec/reviews/REV-FINAL/seal.md"
IA_HASH=$(file_hash "$FEATURE/.gatespec/implementation-adjustments.md")
TASKS_HASH=$(normalized_tasks_hash "$FEATURE/tasks.md")
FINAL_SEAL_HASH=$(receipt_field "$FINAL_SEAL" 'Seal-SHA256')
{
  printf '%s\n' '# GateSpec Implementation Acceptance' '- **Protocol-Version**: `3`' '- **Status**: `Accepted`' '- **Accepted-At**: `2026-08-24T14:00:00Z`'
  printf -- '- **Spec-Content-SHA256**: `%s`\n' "$(content_hash "$FEATURE/spec.md")"
  printf -- '- **Plan-Content-SHA256**: `%s`\n' "$(content_hash "$FEATURE/plan.md")"
  printf -- '- **Design-Attachments-SHA256**: `%s`\n' "$(printf '' | sha_stream | awk '{print $1}')"
  printf -- '- **Tasks-Definition-SHA256**: `%s`\n' "$TASKS_HASH"
  printf '%s\n' '- **Test-Control-Mode**: `isolated`'
  printf -- '- **Test-Control-Closure-SHA256**: `%s`\n' "$(receipt_field "$FINAL_SEAL" 'Test-Control-Closure-SHA256')"
  printf -- '- **Test-Control-Subject-Manifest-SHA256**: `%s`\n' "$(receipt_field "$FINAL_SEAL" 'Test-Control-Subject-Manifest-SHA256')"
  printf -- '- **Default-OFF-Evidence-SHA256**: `%s`\n' "$(receipt_field "$FINAL_SEAL" 'Default-OFF-Evidence-SHA256')"
  printf -- '- **Explicit-ON-Evidence-SHA256**: `%s`\n' "$(receipt_field "$FINAL_SEAL" 'Explicit-ON-Evidence-SHA256')"
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
write_v3_review "$IA_MISMATCH_FEATURE" REV-FOUNDATION FOUNDATION "$BASELINE" "$BASELINE" "$FOUNDATION_SUBJECT" T001,T002 \
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
write_v3_review "$UNRECORDED_FEATURE" REV-FINAL FINAL "$BASELINE" "$BASE" "$UNRECORDED_SUBJECT" T001,T002,T004,T006 \
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

MATERIAL_IA_REPO="$TEST_TMP/material-ia-boundary"
git clone -q --local --no-hardlinks "$REPO" "$MATERIAL_IA_REPO"
git -C "$MATERIAL_IA_REPO" checkout -q -b material-ia "$FINAL_SUBJECT"
git -C "$MATERIAL_IA_REPO" config user.name 'GateSpec Source Fixture'
git -C "$MATERIAL_IA_REPO" config user.email 'source-fixture@example.invalid'
MATERIAL_IA_FEATURE="$MATERIAL_IA_REPO/specs/001-hot-reload"
cat > "$MATERIAL_IA_FEATURE/.gatespec/implementation-adjustments.md" <<EOF
# GateSpec Implementation Adjustments
- **Execution-Epoch**: \`E1\`
- **Source-Design-Content-SHA256**: \`$CONTENT_HASH\`
## Adjustments
### IA1: material boundary change
- **Source refs**: \`SD-F1\`
- **Task ID**: \`T002\`
- **Changed Paths**: \`src/config/store.cc\`
- **Changed Symbols**: \`xclaw::ConfigStore::Reload\`
- **Reason**: This fixture attempts to record a material Source departure.
- **Boundary Impact**: \`material\`
- **Verification**: The implementation review must reject this entry.
EOF
git -C "$MATERIAL_IA_REPO" add specs/001-hot-reload/.gatespec/implementation-adjustments.md
git -C "$MATERIAL_IA_REPO" commit -qm 'record a material Source departure as IA'
MATERIAL_IA_SUBJECT=$(git -C "$MATERIAL_IA_REPO" rev-parse HEAD)
MATERIAL_IA_DELTA=$(final_delta_hash "$MATERIAL_IA_REPO" "$BASE" "$MATERIAL_IA_SUBJECT")
write_v3_review "$MATERIAL_IA_FEATURE" REV-FINAL FINAL "$BASELINE" "$BASE" \
  "$MATERIAL_IA_SUBJECT" T001,T002,T004,T006 'bash tests/run-all.sh' "$MATERIAL_IA_DELTA"
mark_task "$MATERIAL_IA_FEATURE/tasks.md" T007
expect_review fail implementation-candidate "$MATERIAL_IA_FEATURE" REV-FINAL \
  "material Source boundary cannot masquerade as IA" "must declare Boundary Impact 'none'"

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
cp "$FEATURE/plan.md" "$NO_SOURCE/plan.md"
seal_gate "$NO_SOURCE/plan.md"
sed \
  -e '/^\*\*Source-Design-Content-SHA256\*\*:/d' \
  -e 's/| REV-FOUNDATION | D1, FR-002, SD-ALG1, SD-F1, SD-F3, SD-FLOW1, SD-U1, SD1 |/| REV-FOUNDATION | D1, FR-002 |/' \
  -e 's/| REV-US1 | FR-001, SD-F2, SD-FAIL1, SD-TEST1 |/| REV-US1 | FR-001 |/' \
  "$TEST_TMP/tasks-good" > "$NO_SOURCE/tasks.md"
NO_SOURCE_ORIGINAL=$(git -C "$REPO" rev-parse HEAD)
cat > "$NO_SOURCE/.gatespec/execution-state.md" <<EOF
# GateSpec Execution State
- **Protocol-Version**: \`3\`
- **Execution-Epoch**: \`E1\`
- **Original-Implementation-Baseline**: \`$NO_SOURCE_ORIGINAL\`
- **Task-Handoff-Commit**: \`pending\`
- **Source-Design-Content-SHA256**: \`not-applicable\`
- **Preserved-Reviews-SHA256**: \`not-applicable\`
- **Execution-State-SHA256**: \`pending\`
EOF
self_hash "$NO_SOURCE/.gatespec/execution-state.md" 'Execution-State-SHA256'
git -C "$REPO" add specs/002-no-source
git -C "$REPO" commit -qm 'protocol v3 no-source handoff'
HANDOFF=$(git -C "$REPO" rev-parse HEAD)
replace_token "$NO_SOURCE/.gatespec/execution-state.md" '`pending`' "\`$HANDOFF\`"
self_hash "$NO_SOURCE/.gatespec/execution-state.md" 'Execution-State-SHA256'
write_v3_review "$NO_SOURCE" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  'Not run — task-plan review' not-applicable
git -C "$REPO" add specs/002-no-source
git -C "$REPO" commit -qm 'protocol v3 no-source REV-TASKS'
expect pass task-review "$NO_SOURCE" "Protocol v3 without Source uses not-applicable Source and IA bindings"

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
