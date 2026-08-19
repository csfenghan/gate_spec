#!/usr/bin/env bash
# Deterministic fixtures for scripts/bash/check-gate.sh.

set -u
cd "$(dirname "$0")/.." || exit 1
SCRIPT="$PWD/scripts/bash/check-gate.sh"
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gatespec-tests.XXXXXX") || exit 1
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM
PASS=0
FAIL=0

hash_of() {
  if command -v sha256sum >/dev/null 2>&1; then
    sed '/^## Gate Approval/,$d' "$1" | sha256sum | awk '{print $1}'
  else
    sed '/^## Gate Approval/,$d' "$1" | shasum -a 256 | awk '{print $1}'
  fi
}

seal() {
  local file="$1" digest tmp
  digest=$(hash_of "$file")
  tmp="$file.tmp"
  awk -v digest="$digest" '
    /^- \*\*Content-SHA256\*\*:/ { print "- **Content-SHA256**: `" digest "`"; next }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

rewrite() {
  local file="$1" expression="$2" tmp
  tmp="$file.tmp"
  sed "$expression" "$file" > "$tmp" && mv "$tmp" "$file"
}

clone_good() {
  mkdir -p "$TEST_TMP/$1"
  cp "$TEST_TMP/good/spec.md" "$TEST_TMP/$1/spec.md"
  cp "$TEST_TMP/good/plan.md" "$TEST_TMP/$1/plan.md"
}

sha_stream() {
  if command -v sha256sum >/dev/null 2>&1; then
    sha256sum
  else
    shasum -a 256
  fi
}

file_digest() {
  sha_stream < "$1" | awk '{print $1}'
}

normalized_tasks_digest() {
  local file="$1" cr
  cr=$(printf '\r')
  sed -E -e "s/${cr}\$//" \
    -e 's/^(- \[)[xX](\] T[0-9][0-9][0-9]([[:space:]]|$))/\1 \2/' "$file" \
    | sha_stream | awk '{print $1}'
}

attachments_digest() {
  local feature="$1" source rel digest manifest="$TEST_TMP/attachment-manifest"
  : > "$manifest"
  for rel in research.md data-model.md quickstart.md; do
    source="$feature/$rel"
    if [[ -f "$source" ]]; then
      digest=$(file_digest "$source")
      printf '%s\t%s\n' "$rel" "$digest" >> "$manifest"
    fi
  done
  if [[ -d "$feature/contracts" ]]; then
    while IFS= read -r source; do
      [[ -f "$source" ]] || continue
      rel=${source#"$feature"/}
      digest=$(file_digest "$source")
      printf '%s\t%s\n' "$rel" "$digest" >> "$manifest"
    done < <(find "$feature/contracts" -type f -print)
  fi
  LC_ALL=C sort "$manifest" | sha_stream | awk '{print $1}'
}

receipt_field() {
  local file="$1" label="$2"
  awk -v prefix="- **${label}**: \`" '
    index($0, prefix) == 1 && substr($0, length($0), 1) == "`" {
      print substr($0, length(prefix) + 1, length($0) - length(prefix) - 1)
      exit
    }
  ' "$file"
}

seal_self_hash() {
  local file="$1" label="$2" digest tmp="$1.tmp"
  digest=$(sed "/^- \*\*${label}\*\*:/,\$d" "$file" | sha_stream | awk '{print $1}')
  awk -v label="$label" -v digest="$digest" '
    $0 ~ "^- \\*\\*" label "\\*\\*:" {
      print "- **" label "**: `" digest "`"
      next
    }
    { print }
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

make_tasks() {
  local feature="$1"
  cat > "$feature/tasks.md" <<'EOF'
# Tasks: Config hot reload

## Phase 1: Setup

- [ ] T001 Create the feature scaffolding

## Phase 2: Foundational

- [ ] T002 Implement the configuration store
- [ ] T003 GateSpec review checkpoint REV-FOUNDATION: run speckit.gatespec.review-implementation --scope REV-FOUNDATION and require .gatespec/reviews/REV-FOUNDATION/seal.md before continuing

## Phase 3: User Story 1 - Hot reload

- [ ] T004 [US1] Implement hot reload
- [ ] T005 [US1] GateSpec review checkpoint REV-US1: run speckit.gatespec.review-implementation --scope REV-US1 and require .gatespec/reviews/REV-US1/seal.md before continuing

## Phase 4: Polish & Cross-Cutting Concerns

- [ ] T006 Run complete feature validation
- [ ] T007 GateSpec review checkpoint REV-FINAL: run speckit.gatespec.review-implementation --scope REV-FINAL and require .gatespec/reviews/REV-FINAL/seal.md before continuing
EOF
}

changed_paths_digest() {
  local repo="$1" base="$2" subject="$3"
  git -C "$repo" diff --name-only --no-renames "$base" "$subject" \
    | LC_ALL=C sort | sha_stream | awk '{print $1}'
}

write_pass_review() {
  local feature="$1" id="$2" scope="$3" baseline="$4" base="$5" subject="$6" task_ids="$7"
  local request_tests="$8" verdict_tests="$9" limitations="${10-- None}"
  local round="${11:-00}" previous="${12:-none}" status="${13:-PASS}"
  local blocker_body="${14:-- BLOCKER: fixture remediation required}"
  local directory request verdict seal_file repo changed
  local spec_hash plan_hash attachments_hash tasks_hash request_hash verdict_hash label
  directory="$feature/.gatespec/reviews/$id"
  request="$directory/round-${round}-request.md"
  verdict="$directory/round-${round}-verdict.md"
  seal_file="$directory/seal.md"
  mkdir -p "$directory"
  spec_hash=$(hash_of "$feature/spec.md")
  plan_hash=$(hash_of "$feature/plan.md")
  attachments_hash=$(attachments_digest "$feature")
  tasks_hash=$(normalized_tasks_digest "$feature/tasks.md")
  if [[ "$scope" == 'TASKS' ]]; then
    changed='not-applicable'
  else
    repo=$(git -C "$feature" rev-parse --show-toplevel)
    changed=$(changed_paths_digest "$repo" "$base" "$subject")
  fi
  cat > "$request" <<EOF
- **Protocol-Version**: \`1\`
- **Review-ID**: \`$id\`
- **Round**: \`$round\`
- **Scope**: \`$scope\`
- **Spec-Content-SHA256**: \`$spec_hash\`
- **Plan-Content-SHA256**: \`$plan_hash\`
- **Design-Attachments-SHA256**: \`$attachments_hash\`
- **Tasks-Definition-SHA256**: \`$tasks_hash\`
- **Implementation-Baseline**: \`$baseline\`
- **Base-Commit**: \`$base\`
- **Subject-Commit**: \`$subject\`
- **Task-IDs**: \`$task_ids\`
- **Changed-Paths-SHA256**: \`$changed\`
- **Previous-Verdict-SHA256**: \`$previous\`

## Required Tests

$request_tests

- **Request-SHA256**: \`pending\`
EOF
  seal_self_hash "$request" 'Request-SHA256'
  request_hash=$(receipt_field "$request" 'Request-SHA256')
  cat > "$verdict" <<EOF
- **Protocol-Version**: \`1\`
- **Review-ID**: \`$id\`
- **Round**: \`$round\`
- **Request-SHA256**: \`$request_hash\`
- **Reviewer-Platform**: \`manual-codex\`
- **Reviewer-Context-ID**: \`fixture-$id-$round\`
- **Isolation**: \`fresh\`
- **Status**: \`$status\`

## Tests Run

$verdict_tests

## Blockers

- None

## Observations

- Receipt fixture is structurally valid.

## Limitations

$limitations

- **Verdict-SHA256**: \`pending\`
EOF
  if [[ "$status" == 'BLOCKED' ]]; then
    rewrite "$verdict" 's/^- None$/'"$blocker_body"'/'
  fi
  seal_self_hash "$verdict" 'Verdict-SHA256'
  verdict_hash=$(receipt_field "$verdict" 'Verdict-SHA256')
  if [[ "$status" != 'PASS' ]]; then
    return
  fi
  cat > "$seal_file" <<EOF
- **Protocol-Version**: \`1\`
- **Review-ID**: \`$id\`
- **Round**: \`$round\`
- **Status**: \`PASS\`
- **Request-SHA256**: \`$request_hash\`
- **Verdict-SHA256**: \`$verdict_hash\`
EOF
  for label in Spec-Content-SHA256 Plan-Content-SHA256 Design-Attachments-SHA256 \
    Tasks-Definition-SHA256 Implementation-Baseline Base-Commit Subject-Commit; do
    # Literal Markdown backticks are intentional; printf substitutions supply the values.
    # shellcheck disable=SC2016
    printf -- '- **%s**: `%s`\n' "$label" "$(receipt_field "$request" "$label")" >> "$seal_file"
  done
  cat >> "$seal_file" <<'EOF'
- **Sealed-At**: `2026-08-18T12:00:00Z`
- **Seal-SHA256**: `pending`
EOF
  seal_self_hash "$seal_file" 'Seal-SHA256'
}

init_feature_repo() {
  local repo="$1" feature
  feature="$repo/specs/001-hot-reload"
  mkdir -p "$feature"
  cp "$TEST_TMP/good/spec.md" "$feature/spec.md"
  cp "$TEST_TMP/good/plan.md" "$feature/plan.md"
  make_tasks "$feature"
  git -C "$repo" init -q
  git -C "$repo" symbolic-ref HEAD refs/heads/feature
  git -C "$repo" config user.name 'GateSpec Fixture'
  git -C "$repo" config user.email 'fixture@example.invalid'
  printf '%s' "$feature"
}

expect() {
  local wanted="$1" mode="$2" dir="$3" label="$4" diagnostic="${5:-}"
  local got rc=0
  bash "$SCRIPT" "$mode" "$dir" > "$TEST_TMP/out" 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then got=pass; else got=fail; fi
  if [[ "$got" == "$wanted" ]] && { [[ -z "$diagnostic" ]] || grep -F "$diagnostic" "$TEST_TMP/out" >/dev/null 2>&1; }; then
    PASS=$((PASS + 1))
    echo "✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "✗ $label (wanted $wanted, got $got/$rc)"
    [[ -n "$diagnostic" ]] && echo "    required diagnostic: $diagnostic"
    sed 's/^/    /' "$TEST_TMP/out"
  fi
}

expect_silent() {
  local mode="$1" dir="$2" label="$3" rc=0
  bash "$SCRIPT" "$mode" "$dir" > "$TEST_TMP/out" 2>&1 || rc=$?
  if [[ "$rc" -eq 0 && ! -s "$TEST_TMP/out" ]]; then
    PASS=$((PASS + 1)); echo "✓ $label"
  else
    FAIL=$((FAIL + 1)); echo "✗ $label (rc=$rc, expected zero output)"; sed 's/^/    /' "$TEST_TMP/out"
  fi
}

expect_review() {
  local wanted="$1" mode="$2" dir="$3" id="$4" label="$5" diagnostic="${6:-}"
  local got rc=0
  bash "$SCRIPT" "$mode" "$dir" "$id" > "$TEST_TMP/out" 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then got=pass; else got=fail; fi
  if [[ "$got" == "$wanted" ]] && { [[ -z "$diagnostic" ]] || grep -F "$diagnostic" "$TEST_TMP/out" >/dev/null 2>&1; }; then
    PASS=$((PASS + 1))
    echo "✓ $label"
  else
    FAIL=$((FAIL + 1))
    echo "✗ $label (wanted $wanted, got $got/$rc)"
    [[ -n "$diagnostic" ]] && echo "    required diagnostic: $diagnostic"
    sed 's/^/    /' "$TEST_TMP/out"
  fi
}

# Canonical valid artifacts --------------------------------------------------
mkdir -p "$TEST_TMP/good"
cat > "$TEST_TMP/good/spec.md" <<'EOF'
<!-- path: gatespec -->
# Feature Specification: Config hot reload
**Status**: Approved-Requirements (2026-08-07)
## Clarifications
### Session 2026-08-07
- Q: [R1] What reload scope is required? → A: Replace values without dropping connections.
## Approved Defaults
| # | Item | Approved Default | Approved |
|---|------|------------------|----------|
| 1 | Watch mechanism | mtime polling | ✅ 2026-08-07 |
## Constraint Basis
- **Project constitution**: absent — SHA-256: `absent`
- **Project GateSpec constraints**: absent — SHA-256: `absent`
- **User GateSpec constraints**: absent — SHA-256: `absent`
- **Effective constraints**: portable watcher; connections remain active.
- **Conflicts and resolutions**: None — sources do not conflict.
## User Scenarios & Testing
### User Story 1 - Hot reload (Priority: P1)
**Acceptance Scenarios**:
1. **Given** a running daemon, **When** its configuration is saved, **Then** new values apply within one second (covers FR-001)
2. **Given** active clients, **When** configuration reloads, **Then** their connections remain active (covers FR-002)
## Requirements
### Functional Requirements
- **FR-001**: System MUST apply saved configuration values within one second.
- **FR-002**: System MUST keep active connections during reload.
## Success Criteria
### Measurable Outcomes
- **SC-001**: All supported configuration changes apply within one second.
## Assumptions
- Deployment is single-node.
## Gate Approval
- **Approved by user**: 2026-08-07
- **Content-SHA256**: `pending`
EOF
seal "$TEST_TMP/good/spec.md"
SPEC_HASH=$(hash_of "$TEST_TMP/good/spec.md")

cat > "$TEST_TMP/good/plan.md" <<EOF
# Implementation Plan: Config hot reload
**Status**: Approved-Design (2026-08-07)
**Requirements Content-SHA256**: \`$SPEC_HASH\`
## Summary
Add portable polling and atomic snapshot replacement.
## Technical Context
**Language/Version**: C++20
## Constitution Check
All effective constraints are satisfied.
## Decision Log
### D1: Watch mechanism
- **Context**: configuration changes must be portable.
- **Options**: A. polling; B. platform notification.
- **Recommendation**: A — it behaves the same on supported systems.
- **Approved**: A (2026-08-07)
## Design Detailing
1. **Thread / concurrency model**: A watcher thread polls; the main thread atomically swaps snapshots.
2. **Object lifetimes & ownership**: Readers hold shared immutable snapshots; teardown joins the watcher before release.
3. **Key modules & classes**: ConfigWatcher detects changes and ConfigStore validates and publishes snapshots.
4. **Key internal APIs & interactions**: ConfigWatcher calls ConfigStore::Reload, which validates before publishing.
5. **External interface behavior contracts**: Invalid updates retain the prior configuration and emit one diagnostic.
6. **Setup / runtime / teardown phase interactions**: Setup loads once, runtime polls, and teardown stops then joins.
## Implementation Freedoms
- Poll interval representation — constraints: preserve the one-second acceptance bound.
## Implementation Review Contract
- **Protocol Version**: \`1\`
- **Required Checkpoints**: \`REV-FOUNDATION, REV-US1, REV-FINAL\`
- **Review Root**: \`.gatespec/reviews\`
- **Task Review**: \`REV-TASKS after speckit.analyze; PASS required before speckit.implement\`
- **Reviewer Isolation**: \`fresh-context-required; manual-new-session-on-unavailable; same-context-forbidden\`
- **Parallel Policy**: \`same-phase-disjoint-only; join-before-review; cross-checkpoint-forbidden\`
- **Git Policy**: \`clean-feature-branch; local-checkpoint-commits; no-push\`
- **Remediation Limit**: \`2\`
### Checkpoint Test Mapping
| Checkpoint | Required test command(s) |
|------------|--------------------------|
| REV-FOUNDATION | bash tests/unit.sh |
| REV-US1 | bash tests/integration.sh |
| REV-FINAL | bash tests/run-all.sh |
- **Final Validation**: \`bash tests/run-all.sh\`
## Project Structure
### Documentation (this feature)
### Source Code (repository root)
src/config/
## Complexity Tracking
None.
## Gate Approval
- **Approved by user**: 2026-08-07
- **Content-SHA256**: \`pending\`
EOF
seal "$TEST_TMP/good/plan.md"

expect pass spec "$TEST_TMP/good" "approved requirements pass"
expect pass design "$TEST_TMP/good" "approved requirements and design pass"

clone_good legacy-clarification
rewrite "$TEST_TMP/legacy-clarification/spec.md" 's/\[R1\] //'
seal "$TEST_TMP/legacy-clarification/spec.md"
expect pass spec "$TEST_TMP/legacy-clarification" "legacy unnumbered clarification remains valid"

clone_good chinese-constraint-basis
rewrite "$TEST_TMP/chinese-constraint-basis/spec.md" 's/portable watcher; connections remain active\./必须使用可移植的监视机制，并保持现有连接。/'
rewrite "$TEST_TMP/chinese-constraint-basis/spec.md" 's/None — sources do not conflict\./无 — 约束源之间不存在冲突。/'
seal "$TEST_TMP/chinese-constraint-basis/spec.md"
expect pass spec "$TEST_TMP/chinese-constraint-basis" "Chinese Constraint Basis values pass"

# Track marker and feature resolution ---------------------------------------
mkdir -p "$TEST_TMP/auto"
printf '# Upstream spec\n**Status**: Draft\n' > "$TEST_TMP/auto/spec.md"
expect_silent spec "$TEST_TMP/auto" "unmarked auto-track requirements are truly silent"
expect_silent design "$TEST_TMP/auto" "unmarked auto-track design is truly silent"
expect_silent tasks-structure "$TEST_TMP/auto" "unmarked auto-track tasks structure is truly silent"
expect_silent task-review "$TEST_TMP/auto" "unmarked auto-track task review is truly silent"
expect_silent implementation-candidate "$TEST_TMP/auto" "unmarked auto-track implementation candidate is truly silent"
expect_silent implementation-review "$TEST_TMP/auto" "unmarked auto-track implementation review is truly silent"

clone_good displaced-marker
rewrite "$TEST_TMP/displaced-marker/spec.md" '1{h;d;};2{G;}'
expect fail spec "$TEST_TMP/displaced-marker" "marker on a later line fails" "not line 1"
expect fail tasks-structure "$TEST_TMP/displaced-marker" "displaced marker fails before tasks structure" "not line 1"
expect fail task-review "$TEST_TMP/displaced-marker" "displaced marker fails before task review" "not line 1"
expect fail implementation-candidate "$TEST_TMP/displaced-marker" "displaced marker fails before implementation candidate" "not line 1"
expect fail implementation-review "$TEST_TMP/displaced-marker" "displaced marker fails before implementation review" "not line 1"

mkdir -p "$TEST_TMP/json-root/.specify" "$TEST_TMP/json-root/features/with space"
cp "$TEST_TMP/good/spec.md" "$TEST_TMP/json-root/features/with space/spec.md"
cat > "$TEST_TMP/json-root/.specify/feature.json" <<'EOF'
{
  "feature_directory": "features/with space"
}
EOF
rc=0
(cd "$TEST_TMP/json-root" && bash "$SCRIPT" spec) > "$TEST_TMP/out" 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]] && grep -F 'GATE PASSED' "$TEST_TMP/out" >/dev/null; then
  PASS=$((PASS + 1)); echo "✓ pretty feature.json and path with spaces resolve"
else
  FAIL=$((FAIL + 1)); echo "✗ pretty feature.json resolution"; sed 's/^/    /' "$TEST_TMP/out"
fi

mkdir -p "$TEST_TMP/constraint-root/.specify/memory" "$TEST_TMP/constraint-root/features/current"
printf '%s\n' '# Constitution' '- MUST preserve compatibility.' > "$TEST_TMP/constraint-root/.specify/memory/constitution.md"
cp "$TEST_TMP/good/spec.md" "$TEST_TMP/constraint-root/features/current/spec.md"
constitution_hash=$(hash_of "$TEST_TMP/constraint-root/.specify/memory/constitution.md")
rewrite "$TEST_TMP/constraint-root/features/current/spec.md" "s|\*\*Project constitution\*\*: absent — SHA-256: \`absent\`|**Project constitution**: .specify/memory/constitution.md — SHA-256: \`$constitution_hash\`|"
seal "$TEST_TMP/constraint-root/features/current/spec.md"
rc=0
(cd "$TEST_TMP/constraint-root" && bash "$SCRIPT" spec features/current) > "$TEST_TMP/out" 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]]; then PASS=$((PASS + 1)); echo "✓ matching constitution snapshot passes"; else FAIL=$((FAIL + 1)); echo "✗ matching constitution snapshot"; fi
printf '%s\n' '- MUST add a new rule.' >> "$TEST_TMP/constraint-root/.specify/memory/constitution.md"
rc=0
(cd "$TEST_TMP/constraint-root" && bash "$SCRIPT" spec features/current) > "$TEST_TMP/out" 2>&1 || rc=$?
if [[ "$rc" -ne 0 ]] && grep -F 'Requirements re-approval is required' "$TEST_TMP/out" >/dev/null; then
  PASS=$((PASS + 1)); echo "✓ constitution drift forces requirements re-approval"
else
  FAIL=$((FAIL + 1)); echo "✗ constitution drift enforcement"; sed 's/^/    /' "$TEST_TMP/out"
fi

mkdir -p "$TEST_TMP/user-drift-root/.specify" "$TEST_TMP/user-drift-root/features/current" "$TEST_TMP/user-drift-home/.gatespec"
cp "$TEST_TMP/good/spec.md" "$TEST_TMP/user-drift-root/features/current/spec.md"
printf '%s\n' '# Updated personal constraints' > "$TEST_TMP/user-drift-home/.gatespec/constraints.md"
rc=0
(cd "$TEST_TMP/user-drift-root" && HOME="$TEST_TMP/user-drift-home" bash "$SCRIPT" spec features/current) > "$TEST_TMP/out" 2>&1 || rc=$?
if [[ "$rc" -eq 0 ]] && grep -F 'user constraints changed after snapshot' "$TEST_TMP/out" >/dev/null; then
  PASS=$((PASS + 1)); echo "✓ personal constraint drift warns without invalidating approval"
else
  FAIL=$((FAIL + 1)); echo "✗ personal constraint drift semantics"; sed 's/^/    /' "$TEST_TMP/out"
fi

# Approval structure and snapshot -------------------------------------------
clone_good missing-approval
rewrite "$TEST_TMP/missing-approval/spec.md" '/Approved by user/d'
seal "$TEST_TMP/missing-approval/spec.md"
expect fail spec "$TEST_TMP/missing-approval" "missing approval date fails with a fresh hash" "missing or duplicate 'Approved by user'"

clone_good missing-approval-hash
rewrite "$TEST_TMP/missing-approval-hash/spec.md" '/Content-SHA256/d'
expect fail spec "$TEST_TMP/missing-approval-hash" "missing approval hash fails" "Content-SHA256 must"

clone_good approval-tail
printf '%s\n' '- unexpected tail' >> "$TEST_TMP/approval-tail/spec.md"
seal "$TEST_TMP/approval-tail/spec.md"
expect fail spec "$TEST_TMP/approval-tail" "content after approval fields fails" "may contain only"

clone_good later-h2
printf '%s\n' '## Added Later' 'text' >> "$TEST_TMP/later-h2/spec.md"
seal "$TEST_TMP/later-h2/spec.md"
expect fail spec "$TEST_TMP/later-h2" "Gate Approval must be final H2" "must be the final H2"

clone_good duplicate-heading
# shellcheck disable=SC1004
rewrite "$TEST_TMP/duplicate-heading/spec.md" '/## Success Criteria/a\
## Requirements'
seal "$TEST_TMP/duplicate-heading/spec.md"
expect fail spec "$TEST_TMP/duplicate-heading" "duplicate mandatory H2 fails" "expected exactly one '## Requirements'"

clone_good drift
rewrite "$TEST_TMP/drift/spec.md" 's/within one second/within two seconds/'
expect fail spec "$TEST_TMP/drift" "post-approval drift fails" "snapshot mismatch"

clone_good date-mismatch
rewrite "$TEST_TMP/date-mismatch/spec.md" 's/Approved-Requirements (2026-08-07)/Approved-Requirements (2026-08-06)/'
seal "$TEST_TMP/date-mismatch/spec.md"
expect fail spec "$TEST_TMP/date-mismatch" "status and user approval dates must agree" "does not match Approved by user"

# Requirements section scoping and empty states -----------------------------
clone_good chinese-constraint-placeholder
rewrite "$TEST_TMP/chinese-constraint-placeholder/spec.md" 's/portable watcher; connections remain active\./[按优先级排列的中文有效约束，包含已批准的豁免]/'
seal "$TEST_TMP/chinese-constraint-placeholder/spec.md"
expect fail spec "$TEST_TMP/chinese-constraint-placeholder" "Chinese Constraint Basis placeholder fails" "still contains placeholders"

clone_good placeholder-clarification
rewrite "$TEST_TMP/placeholder-clarification/spec.md" 's/Replace values without dropping connections./[NEEDS CLARIFICATION: reload scope]/'
seal "$TEST_TMP/placeholder-clarification/spec.md"
expect fail spec "$TEST_TMP/placeholder-clarification" "placeholder clarification fails" "template/residual marker"

clone_good placeholder-default
rewrite "$TEST_TMP/placeholder-default/spec.md" 's/mtime polling/[default value]/'
seal "$TEST_TMP/placeholder-default/spec.md"
expect fail spec "$TEST_TMP/placeholder-default" "placeholder default fails" "template/residual marker"

clone_good unconcluded-clarification
rewrite "$TEST_TMP/unconcluded-clarification/spec.md" 's/ → A: Replace values without dropping connections\.//'
seal "$TEST_TMP/unconcluded-clarification/spec.md"
expect fail spec "$TEST_TMP/unconcluded-clarification" "unconcluded clarification fails" "unconcluded or malformed"

clone_good unapproved-default
rewrite "$TEST_TMP/unapproved-default/spec.md" 's/✅ 2026-08-07/ /'
seal "$TEST_TMP/unapproved-default/spec.md"
expect fail spec "$TEST_TMP/unapproved-default" "default row without approval fails" "malformed or unapproved"

clone_good duplicate-fr
# shellcheck disable=SC1004
rewrite "$TEST_TMP/duplicate-fr/spec.md" '/FR-002\*\*:/a\
- **FR-001**: System MUST duplicate this identifier.'
seal "$TEST_TMP/duplicate-fr/spec.md"
expect fail spec "$TEST_TMP/duplicate-fr" "duplicate FR definition fails" "defined 2 times"

clone_good orphan-fr
rewrite "$TEST_TMP/orphan-fr/spec.md" 's/ (covers FR-002)//'
seal "$TEST_TMP/orphan-fr/spec.md"
expect fail spec "$TEST_TMP/orphan-fr" "orphan FR fails" "FR-002 has no Acceptance Scenario"

clone_good undefined-fr
rewrite "$TEST_TMP/undefined-fr/spec.md" 's/(covers FR-002)/(covers FR-999)/'
seal "$TEST_TMP/undefined-fr/spec.md"
expect fail spec "$TEST_TMP/undefined-fr" "undefined scenario FR fails" "references undefined FR-999"

clone_good misplaced-fr
# shellcheck disable=SC1004
rewrite "$TEST_TMP/misplaced-fr/spec.md" '/## Assumptions/i\
- **FR-003**: System MUST not be defined here.'
seal "$TEST_TMP/misplaced-fr/spec.md"
expect fail spec "$TEST_TMP/misplaced-fr" "FR definition outside Functional Requirements fails" "outside '### Functional Requirements'"

clone_good uncovered-scenario
rewrite "$TEST_TMP/uncovered-scenario/spec.md" 's/ (covers FR-001)//'
seal "$TEST_TMP/uncovered-scenario/spec.md"
expect fail spec "$TEST_TMP/uncovered-scenario" "every acceptance line needs covers" "every Acceptance Scenario"

clone_good empty-states
awk '
  /^## Clarifications/ {print; print "- None — all behavior was supplied in the request."; skip="clar"; next}
  /^## Approved Defaults/ {print; print "- None — no routine choice remained open."; skip="defaults"; next}
  skip == "clar" && /^## Approved Defaults/ {print; print "- None — no routine choice remained open."; skip="defaults"; next}
  skip == "defaults" && /^## Constraint Basis/ {skip=""; print; next}
  skip == "" {print}
' "$TEST_TMP/good/spec.md" > "$TEST_TMP/empty-states/spec.md"
seal "$TEST_TMP/empty-states/spec.md"
expect pass spec "$TEST_TMP/empty-states" "fixed empty clarification/default states pass"

# Design blocks, dimensions, and requirements basis -------------------------
clone_good d1-d10
awk '
  /^## Design Detailing/ {
    print "### D10: Reload failure response"
    print "- **Context**: invalid input must preserve service."
    print "- **Options**: A. retain prior state; B. stop service."
    print "- **Recommendation**: A — clients remain available."
    print "- **Approved**: A (2026-08-07)"
  }
  {print}
' "$TEST_TMP/good/plan.md" > "$TEST_TMP/d1-d10/plan.md.tmp" && mv "$TEST_TMP/d1-d10/plan.md.tmp" "$TEST_TMP/d1-d10/plan.md"
seal "$TEST_TMP/d1-d10/plan.md"
expect pass design "$TEST_TMP/d1-d10" "D1 and D10 use exact independent block boundaries"

clone_good duplicate-decision
# shellcheck disable=SC1004
rewrite "$TEST_TMP/duplicate-decision/plan.md" '/## Design Detailing/i\
### D1: Duplicate identifier\
- **Approved**: B (2026-08-07)'
seal "$TEST_TMP/duplicate-decision/plan.md"
expect fail design "$TEST_TMP/duplicate-decision" "duplicate decision ID fails" "decision ID D1 is duplicated"

clone_good unapproved-decision
rewrite "$TEST_TMP/unapproved-decision/plan.md" 's/- \*\*Approved\*\*: A (2026-08-07)/- **Approved**: /'
seal "$TEST_TMP/unapproved-decision/plan.md"
expect fail design "$TEST_TMP/unapproved-decision" "decision without explicit approval fails" "must contain exactly one"

clone_good zero-decision
awk '
  /^## Decision Log/ {print; print "- None — implementation is fully fixed by the approved requirements and existing architecture."; skip=1; next}
  skip && /^## Design Detailing/ {skip=0}
  !skip {print}
' "$TEST_TMP/good/plan.md" > "$TEST_TMP/zero-decision/plan.md.tmp" && mv "$TEST_TMP/zero-decision/plan.md.tmp" "$TEST_TMP/zero-decision/plan.md"
seal "$TEST_TMP/zero-decision/plan.md"
expect pass design "$TEST_TMP/zero-decision" "fixed zero-decision state passes"

clone_good missing-dimension
rewrite "$TEST_TMP/missing-dimension/plan.md" '/^6\. \*\*Setup \/ runtime \/ teardown/d'
seal "$TEST_TMP/missing-dimension/plan.md"
expect fail design "$TEST_TMP/missing-dimension" "missing core dimension fails" "requires exactly one '6. **Setup / runtime / teardown"

clone_good duplicate-dimension
# shellcheck disable=SC1004
rewrite "$TEST_TMP/duplicate-dimension/plan.md" '/^2\. \*\*Object lifetimes/a\
2. **Object lifetimes & ownership**: duplicate.'
seal "$TEST_TMP/duplicate-dimension/plan.md"
expect fail design "$TEST_TMP/duplicate-dimension" "duplicate core dimension fails" "requires exactly one '2. **Object lifetimes"

clone_good wrong-dimension
rewrite "$TEST_TMP/wrong-dimension/plan.md" 's/^6\. \*\*Setup/7. **Setup/'
seal "$TEST_TMP/wrong-dimension/plan.md"
expect fail design "$TEST_TMP/wrong-dimension" "wrong core dimension number fails" "requires exactly one '6. **Setup / runtime / teardown"

clone_good no-reason-na
rewrite "$TEST_TMP/no-reason-na/plan.md" 's/A watcher thread polls; the main thread atomically swaps snapshots./N\/A/'
seal "$TEST_TMP/no-reason-na/plan.md"
expect fail design "$TEST_TMP/no-reason-na" "N/A without reason fails" "uses N/A without"

clone_good reasoned-na
rewrite "$TEST_TMP/reasoned-na/plan.md" 's/A watcher thread polls; the main thread atomically swaps snapshots./N\/A — execution is single-threaded in this variant./'
seal "$TEST_TMP/reasoned-na/plan.md"
expect pass design "$TEST_TMP/reasoned-na" "N/A with a reason passes"

clone_good stale-basis
rewrite "$TEST_TMP/stale-basis/spec.md" 's/within one second/within 900 milliseconds/g'
seal "$TEST_TMP/stale-basis/spec.md"
expect fail design "$TEST_TMP/stale-basis" "re-approved spec invalidates stale plan basis" "Requirements basis mismatch"

clone_good plan-placeholder
rewrite "$TEST_TMP/plan-placeholder/plan.md" 's/C++20/[e.g., C++20]/'
seal "$TEST_TMP/plan-placeholder/plan.md"
expect fail design "$TEST_TMP/plan-placeholder" "known plan template remnant fails" "template/residual marker"

# Native tasks and checkpoint structure -------------------------------------
clone_good tasks-good
make_tasks "$TEST_TMP/tasks-good"
expect pass tasks-structure "$TEST_TMP/tasks-good" "native task checkpoints pass structural validation"

clone_good mapping-pipeline
make_tasks "$TEST_TMP/mapping-pipeline"
rewrite "$TEST_TMP/mapping-pipeline/plan.md" 's#| REV-FOUNDATION | bash tests/unit.sh |#| REV-FOUNDATION | bash tests/unit.sh | tee unit.log |#'
seal "$TEST_TMP/mapping-pipeline/plan.md"
expect fail tasks-structure "$TEST_TMP/mapping-pipeline" "mapping pipelines require an unambiguous script wrapper" "rows must have exactly two columns"

clone_good missing-review-contract
awk '
  /^## Implementation Review Contract/ {skip=1; next}
  skip && /^## / {skip=0}
  !skip {print}
' "$TEST_TMP/good/plan.md" > "$TEST_TMP/missing-review-contract/plan.md"
seal "$TEST_TMP/missing-review-contract/plan.md"
expect fail design "$TEST_TMP/missing-review-contract" "design requires the implementation review contract" "Implementation Review Contract"

clone_good task-id-gap
make_tasks "$TEST_TMP/task-id-gap"
rewrite "$TEST_TMP/task-id-gap/tasks.md" 's/T004 \[US1\]/T009 [US1]/'
expect fail tasks-structure "$TEST_TMP/task-id-gap" "task IDs must be continuous in file order" "strictly continuous from T001"

clone_good checkpoint-parallel
make_tasks "$TEST_TMP/checkpoint-parallel"
rewrite "$TEST_TMP/checkpoint-parallel/tasks.md" 's/T003 GateSpec/T003 [P] GateSpec/'
expect fail tasks-structure "$TEST_TMP/checkpoint-parallel" "checkpoint tasks cannot be parallel" "must not be marked [P]"

clone_good checkpoint-not-explicit
make_tasks "$TEST_TMP/checkpoint-not-explicit"
rewrite "$TEST_TMP/checkpoint-not-explicit/tasks.md" 's/speckit\.gatespec\.review-implementation/review-implementation/'
expect fail tasks-structure "$TEST_TMP/checkpoint-not-explicit" "checkpoint names the explicit independent reviewer command" "must name speckit.gatespec.review-implementation"

clone_good checkpoint-not-last
make_tasks "$TEST_TMP/checkpoint-not-last"
rewrite "$TEST_TMP/checkpoint-not-last/tasks.md" 's|T002 Implement the configuration store|T002 GateSpec review checkpoint REV-FOUNDATION: run speckit.gatespec.review-implementation --scope REV-FOUNDATION and require .gatespec/reviews/REV-FOUNDATION/seal.md before continuing|'
rewrite "$TEST_TMP/checkpoint-not-last/tasks.md" 's|T003 GateSpec review checkpoint REV-FOUNDATION: run speckit.gatespec.review-implementation --scope REV-FOUNDATION and require .gatespec/reviews/REV-FOUNDATION/seal.md before continuing|T003 Implement the configuration store|'
expect fail tasks-structure "$TEST_TMP/checkpoint-not-last" "checkpoint must be phase-final" "must be the final task in its phase"

clone_good story-checkpoint-label
make_tasks "$TEST_TMP/story-checkpoint-label"
rewrite "$TEST_TMP/story-checkpoint-label/tasks.md" 's/T005 \[US1\] GateSpec/T005 GateSpec/'
expect fail tasks-structure "$TEST_TMP/story-checkpoint-label" "story checkpoint carries its story label" "must carry [US1]"

clone_good actual-story-mismatch
make_tasks "$TEST_TMP/actual-story-mismatch"
rewrite "$TEST_TMP/actual-story-mismatch/tasks.md" 's/User Story 1 - Hot reload/User Story 2 - Hot reload/'
expect fail tasks-structure "$TEST_TMP/actual-story-mismatch" "every actual story phase has its matching checkpoint" "User Story 2 phase requires exactly one REV-US2"

rc=0
bash "$SCRIPT" tasks-structure "$TEST_TMP/tasks-good" REV-FINAL > "$TEST_TMP/out" 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]] && grep -F 'does not accept a REV-ID' "$TEST_TMP/out" >/dev/null; then
  PASS=$((PASS + 1)); echo "✓ non-review modes reject a REV-ID"
else
  FAIL=$((FAIL + 1)); echo "✗ non-review mode REV-ID CLI boundary"; sed 's/^/    /' "$TEST_TMP/out"
fi

rc=0
bash "$SCRIPT" spec "$TEST_TMP/good" REV-FINAL extra > "$TEST_TMP/out" 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]] && grep -F 'Usage:' "$TEST_TMP/out" >/dev/null; then
  PASS=$((PASS + 1)); echo "✓ checker rejects a fourth argument"
else
  FAIL=$((FAIL + 1)); echo "✗ checker arity boundary"; sed 's/^/    /' "$TEST_TMP/out"
fi

# Task-review receipt, hash binding, and Git handoff ------------------------
task_repo="$TEST_TMP/task-review-repo"
task_feature=$(init_feature_repo "$task_repo")
write_pass_review "$task_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review'
git -C "$task_repo" add -- .
git -C "$task_repo" commit -qm 'Seal task review baseline'
expect_review pass task-review "$task_feature" REV-TASKS "valid task-review receipt is clean, tracked, and bound"

printf '%s\n' 'untracked handoff dirt' > "$task_repo/untracked.txt"
expect_review fail task-review "$task_feature" REV-TASKS "task review rejects a dirty worktree" "worktree must be clean"
mv "$task_repo/untracked.txt" "$TEST_TMP/task-review-untracked.txt"

rewrite "$task_feature/tasks.md" 's/^- \[ \] T001/- [x] T001/'
git -C "$task_repo" add -- specs/001-hot-reload/tasks.md
git -C "$task_repo" commit -qm 'Complete one task checkbox'
expect_review pass task-review "$task_feature" REV-TASKS "checkbox-only task progress preserves the normalized definition hash"

git -C "$task_repo" checkout -q --detach
expect_review fail task-review "$task_feature" REV-TASKS "task review rejects detached HEAD" "attached to a local feature branch"
git -C "$task_repo" checkout -q feature

rewrite "$task_feature/tasks.md" 's/Create the feature scaffolding/Create revised feature scaffolding/'
git -C "$task_repo" add -- specs/001-hot-reload/tasks.md
git -C "$task_repo" commit -qm 'Drift task definition'
expect_review fail task-review "$task_feature" REV-TASKS "task definition drift invalidates the receipt" "normalized tasks definition hash is stale"

empty_request_repo="$TEST_TMP/empty-request-tests-repo"
empty_request_feature=$(init_feature_repo "$empty_request_repo")
write_pass_review "$empty_request_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '' '- Not run — task-plan review'
git -C "$empty_request_repo" add -- .
git -C "$empty_request_repo" commit -qm 'Receipt with empty required tests'
expect_review fail task-review "$empty_request_feature" REV-TASKS "request self-hash cannot masquerade as Required Tests body" "at least one well-formed bullet"

empty_limit_repo="$TEST_TMP/empty-limitations-repo"
empty_limit_feature=$(init_feature_repo "$empty_limit_repo")
write_pass_review "$empty_limit_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' ''
git -C "$empty_limit_repo" add -- .
git -C "$empty_limit_repo" commit -qm 'Receipt with empty limitations'
expect_review fail task-review "$empty_limit_feature" REV-TASKS "verdict self-hash cannot masquerade as Limitations body" "## Limitations must contain"

canonical_repo="$TEST_TMP/canonical-receipt-repo"
canonical_feature=$(init_feature_repo "$canonical_repo")
write_pass_review "$canonical_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review'
awk 'BEGIN {print "# Injected heading"} {print}' \
  "$canonical_feature/.gatespec/reviews/REV-TASKS/round-00-request.md" \
  > "$canonical_feature/.gatespec/reviews/REV-TASKS/round-00-request.md.tmp"
mv "$canonical_feature/.gatespec/reviews/REV-TASKS/round-00-request.md.tmp" \
  "$canonical_feature/.gatespec/reviews/REV-TASKS/round-00-request.md"
git -C "$canonical_repo" add -- .
git -C "$canonical_repo" commit -qm 'Inject noncanonical request heading'
expect_review fail task-review "$canonical_feature" REV-TASKS "request rejects an extra H1 heading" "non-canonical heading, field, or prose"

write_pass_review "$canonical_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review'
awk '/^- \*\*Seal-SHA256\*\*:/ {print "injected prose"} {print}' \
  "$canonical_feature/.gatespec/reviews/REV-TASKS/seal.md" \
  > "$canonical_feature/.gatespec/reviews/REV-TASKS/seal.md.tmp"
mv "$canonical_feature/.gatespec/reviews/REV-TASKS/seal.md.tmp" \
  "$canonical_feature/.gatespec/reviews/REV-TASKS/seal.md"
git -C "$canonical_repo" add -- .
git -C "$canonical_repo" commit -qm 'Inject noncanonical seal prose'
expect_review fail task-review "$canonical_feature" REV-TASKS "seal rejects extra prose outside its fields" "non-canonical heading, field, or prose"

task_round_repo="$TEST_TMP/task-remediation-repo"
task_round_feature=$(init_feature_repo "$task_round_repo")
write_pass_review "$task_round_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- None' 00 none BLOCKED
task_blocked_hash=$(receipt_field "$task_round_feature/.gatespec/reviews/REV-TASKS/round-00-verdict.md" 'Verdict-SHA256')
write_pass_review "$task_round_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- None' 01 "$task_blocked_hash" PASS
git -C "$task_round_repo" add -- .
git -C "$task_round_repo" commit -qm 'Repeat task review without remediation'
expect_review fail task-review "$task_round_feature" REV-TASKS "task retry cannot repeat the same task definition" "remediation must change Tasks-Definition-SHA256"

rewrite "$task_round_feature/tasks.md" 's/Create the feature scaffolding/Create reviewed feature scaffolding/'
write_pass_review "$task_round_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- None' 01 "$task_blocked_hash" PASS
git -C "$task_round_repo" add -- .
git -C "$task_round_repo" commit -qm 'Remediate task definition and reseal'
expect_review pass task-review "$task_round_feature" REV-TASKS "task retry passes only after definition remediation"

task_basis_repo="$TEST_TMP/task-basis-drift-repo"
task_basis_feature=$(init_feature_repo "$task_basis_repo")
write_pass_review "$task_basis_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- None' 00 none BLOCKED
task_basis_blocked_hash=$(receipt_field "$task_basis_feature/.gatespec/reviews/REV-TASKS/round-00-verdict.md" 'Verdict-SHA256')
rewrite "$task_basis_feature/tasks.md" 's/Create the feature scaffolding/Create basis-drift scaffolding/'
rewrite "$task_basis_feature/plan.md" 's/Add portable polling/Add revised portable polling/'
seal "$task_basis_feature/plan.md"
write_pass_review "$task_basis_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- None' 01 "$task_basis_blocked_hash" PASS
git -C "$task_basis_repo" add -- .
git -C "$task_basis_repo" commit -qm 'Attempt task remediation across design basis drift'
expect_review fail task-review "$task_basis_feature" REV-TASKS "task remediation cannot bridge a changed design basis" "must retain Spec, Plan, and Design-Attachments hashes"

ignored_handoff_repo="$TEST_TMP/ignored-task-handoff-repo"
ignored_handoff_feature=$(init_feature_repo "$ignored_handoff_repo")
printf '%s\n' 'specs/001-hot-reload/.gatespec/reviews/' > "$ignored_handoff_repo/.gitignore"
write_pass_review "$ignored_handoff_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review'
git -C "$ignored_handoff_repo" add -- .gitignore specs/001-hot-reload/spec.md \
  specs/001-hot-reload/plan.md specs/001-hot-reload/tasks.md
git -C "$ignored_handoff_repo" commit -qm 'Ignore rather than track task receipt'
expect_review fail task-review "$ignored_handoff_feature" REV-TASKS "ignored task receipt cannot bypass tracked handoff" "must be tracked at HEAD"

# Implementation phase seals and cumulative final review -------------------
implementation_repo="$TEST_TMP/implementation-repo"
implementation_feature=$(init_feature_repo "$implementation_repo")
write_pass_review "$implementation_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review'
git -C "$implementation_repo" add -- .
git -C "$implementation_repo" commit -qm 'Seal task review baseline'
implementation_baseline=$(git -C "$implementation_repo" rev-parse HEAD)

mkdir -p "$implementation_repo/src"
printf '%s\n' 'foundation' > "$implementation_repo/src/implementation.txt"
rewrite "$implementation_feature/tasks.md" 's/^- \[ \] T001/- [x] T001/'
rewrite "$implementation_feature/tasks.md" 's/^- \[ \] T002/- [x] T002/'
git -C "$implementation_repo" add -- src/implementation.txt specs/001-hot-reload/tasks.md
git -C "$implementation_repo" commit -qm 'Implement foundation'
foundation_first_subject=$(git -C "$implementation_repo" rev-parse HEAD)
write_pass_review "$implementation_feature" REV-FOUNDATION FOUNDATION "$implementation_baseline" \
  "$implementation_baseline" "$foundation_first_subject" T001,T002 '- bash tests/unit.sh' \
  '- bash tests/unit.sh — FAIL' '- None' 00 none BLOCKED
foundation_blocked_hash=$(receipt_field "$implementation_feature/.gatespec/reviews/REV-FOUNDATION/round-00-verdict.md" 'Verdict-SHA256')
expect_review fail implementation-candidate "$implementation_feature" REV-FOUNDATION "candidate mode rejects a BLOCKED round without a seal" "PASS seal not found"
git -C "$implementation_repo" add -- \
  specs/001-hot-reload/.gatespec/reviews/REV-FOUNDATION/round-00-request.md \
  specs/001-hot-reload/.gatespec/reviews/REV-FOUNDATION/round-00-verdict.md
git -C "$implementation_repo" commit -qm 'Record foundation review finding'
foundation_finding=$(git -C "$implementation_repo" rev-parse HEAD)
write_pass_review "$implementation_feature" REV-FOUNDATION FOUNDATION "$implementation_baseline" \
  "$implementation_baseline" "$foundation_first_subject" T001,T002 '- bash tests/unit.sh' \
  '- bash tests/unit.sh — PASS' '- None' 01 "$foundation_blocked_hash" PASS
rewrite "$implementation_feature/tasks.md" 's/^- \[ \] T003/- [x] T003/'
expect_review fail implementation-candidate "$implementation_feature" REV-FOUNDATION "implementation retry cannot reuse its prior subject" "remediation must advance Subject-Commit"

write_pass_review "$implementation_feature" REV-FOUNDATION FOUNDATION "$implementation_baseline" \
  "$implementation_baseline" "$foundation_finding" T001,T002 '- bash tests/unit.sh' \
  '- bash tests/unit.sh — PASS' '- None' 01 "$foundation_blocked_hash" PASS
expect_review fail implementation-candidate "$implementation_feature" REV-FOUNDATION "finding metadata commit cannot masquerade as remediation subject" "must strictly descend from the finding commit"

printf '%s\n' 'foundation-remediation' >> "$implementation_repo/src/implementation.txt"
git -C "$implementation_repo" add -- src/implementation.txt
git -C "$implementation_repo" commit -qm 'Remediate foundation review'
foundation_subject=$(git -C "$implementation_repo" rev-parse HEAD)
write_pass_review "$implementation_feature" REV-FOUNDATION FOUNDATION "$implementation_baseline" \
  "$implementation_baseline" "$foundation_subject" T001,T002 '- bash tests/unit.sh' \
  '- bash tests/unit.sh — PASS' '- None' 01 "$foundation_blocked_hash" PASS
rewrite "$implementation_feature/.gatespec/reviews/REV-FOUNDATION/round-01-verdict.md" 's/fixture-REV-FOUNDATION-01/tampered-context/'
expect_review fail implementation-candidate "$implementation_feature" REV-FOUNDATION "candidate mode rejects a tampered verdict" "Verdict-SHA256 self-hash mismatch"
write_pass_review "$implementation_feature" REV-FOUNDATION FOUNDATION "$implementation_baseline" \
  "$implementation_baseline" "$foundation_subject" T001,T002 '- bash tests/unit.sh' \
  '- bash tests/unit.sh — PASS' '- None' 01 "$foundation_blocked_hash" PASS
expect_review pass implementation-candidate "$implementation_feature" REV-FOUNDATION "foundation candidate binds baseline, subject, tests, and checkbox"
git -C "$implementation_repo" add -- specs/001-hot-reload/tasks.md \
  specs/001-hot-reload/.gatespec/reviews/REV-FOUNDATION
git -C "$implementation_repo" commit -qm 'Commit foundation review metadata and progress'
expect_review pass implementation-review "$implementation_feature" REV-FOUNDATION "clean committed foundation review passes the after-hook mode"

printf '%s\n' 'user-story-1' >> "$implementation_repo/src/implementation.txt"
rewrite "$implementation_feature/tasks.md" 's/^- \[ \] T004/- [x] T004/'
git -C "$implementation_repo" add -- src/implementation.txt specs/001-hot-reload/tasks.md
git -C "$implementation_repo" commit -qm 'Implement user story one'
us1_subject=$(git -C "$implementation_repo" rev-parse HEAD)
write_pass_review "$implementation_feature" REV-US1 US1 "$implementation_baseline" \
  "$foundation_subject" "$us1_subject" T004 '- bash tests/integration.sh' '- bash tests/integration.sh — PASS'
rewrite "$implementation_feature/tasks.md" 's/^- \[ \] T005/- [x] T005/'
expect_review pass implementation-candidate "$implementation_feature" REV-US1 "user-story seal starts at the preceding checkpoint subject"
git -C "$implementation_repo" add -- specs/001-hot-reload/tasks.md \
  specs/001-hot-reload/.gatespec/reviews/REV-US1
git -C "$implementation_repo" commit -qm 'Commit user-story review metadata and progress'
expect_review pass implementation-review "$implementation_feature" REV-US1 "clean committed user-story review passes"

printf '%s\n' 'final-validation' >> "$implementation_repo/src/implementation.txt"
rewrite "$implementation_feature/tasks.md" 's/^- \[ \] T006/- [x] T006/'
git -C "$implementation_repo" add -- src/implementation.txt specs/001-hot-reload/tasks.md
git -C "$implementation_repo" commit -qm 'Complete final implementation'
final_subject=$(git -C "$implementation_repo" rev-parse HEAD)

write_pass_review "$implementation_feature" REV-FINAL FINAL "$implementation_baseline" \
  "$implementation_baseline" "$final_subject" T006 '- bash tests/run-all.sh' '- bash tests/run-all.sh — PASS'
expect_review fail implementation-candidate "$implementation_feature" REV-FINAL "final Task-IDs cannot omit feature implementation tasks" "Task-IDs must exactly match"

write_pass_review "$implementation_feature" REV-FINAL FINAL "$implementation_baseline" \
  "$us1_subject" "$final_subject" T001,T002,T004,T006 '- bash tests/run-all.sh' '- bash tests/run-all.sh — PASS'
expect_review fail implementation-candidate "$implementation_feature" REV-FINAL "final review cannot use only the last phase diff" "Base-Commit must equal Implementation-Baseline"

write_pass_review "$implementation_feature" REV-FINAL FINAL "$implementation_baseline" \
  "$implementation_baseline" "$final_subject" T001,T002,T004,T006 '- bash tests/run-all.sh' '- bash tests/run-all.sh — PASS'
expect_review fail implementation-candidate "$implementation_feature" REV-FINAL "final seal requires every task checkbox complete" "requires every valid task checkbox"

rewrite "$implementation_feature/tasks.md" 's/^- \[ \] T007/- [x] T007/'
expect_review pass implementation-candidate "$implementation_feature" REV-FINAL "cumulative final candidate and all phase seals pass"
expect_review fail implementation-review "$implementation_feature" REV-FINAL "after-hook mode rejects an uncommitted candidate" "requires a clean worktree"

write_pass_review "$implementation_feature" REV-FINAL FINAL "$implementation_baseline" \
  "$implementation_baseline" "$final_subject" T001,T002,T004,T006 '- echo substitute-test' '- echo substitute-test — PASS'
expect_review fail implementation-candidate "$implementation_feature" REV-FINAL "request cannot replace the approved checkpoint test" "must exactly match the approved checkpoint mapping"

write_pass_review "$implementation_feature" REV-FINAL FINAL "$implementation_baseline" \
  "$implementation_baseline" "$final_subject" T001,T002,T004,T006 '- bash tests/run-all.sh' '- bash tests/run-all.sh'
expect_review fail implementation-candidate "$implementation_feature" REV-FINAL "verdict must record an outcome for every approved test" "plus its result"

final_tree=$(git -C "$implementation_repo" rev-parse "$final_subject^{tree}")
alternate_subject=$(printf '%s\n' 'alternate final without stage ancestry' | \
  git -C "$implementation_repo" commit-tree "$final_tree" -p "$implementation_baseline")
write_pass_review "$implementation_feature" REV-FINAL FINAL "$implementation_baseline" \
  "$implementation_baseline" "$alternate_subject" T001,T002,T004,T006 '- bash tests/run-all.sh' '- bash tests/run-all.sh — PASS'
expect_review fail implementation-candidate "$implementation_feature" REV-FINAL "final subject must contain every previously sealed stage" "must descend from the preceding checkpoint Subject-Commit"

write_pass_review "$implementation_feature" REV-FINAL FINAL "$implementation_baseline" \
  "$implementation_baseline" "$final_subject" T001,T002,T004,T006 '- bash tests/run-all.sh' '- bash tests/run-all.sh — PASS'
expect_review pass implementation-candidate "$implementation_feature" REV-FINAL "restored cumulative final candidate passes"
git -C "$implementation_repo" add -- specs/001-hot-reload/tasks.md \
  specs/001-hot-reload/.gatespec/reviews/REV-FINAL
git -C "$implementation_repo" commit -qm 'Commit final review metadata and progress'
expect_review pass implementation-review "$implementation_feature" REV-FINAL "clean tracked final review passes after_implement"

printf '%s\n' 'specs/001-hot-reload/.gatespec/reviews/REV-FOUNDATION/seal.md' \
  >> "$implementation_repo/.git/info/exclude"
git -C "$implementation_repo" rm -q --cached -- \
  specs/001-hot-reload/.gatespec/reviews/REV-FOUNDATION/seal.md
git -C "$implementation_repo" commit -qm 'Simulate ignored earlier checkpoint seal'
expect_review fail implementation-review "$implementation_feature" REV-FINAL "final committed mode verifies every earlier scope receipt" "REV-FOUNDATION/seal.md' must be tracked at HEAD"

prechecked_tree=$(git -C "$implementation_repo" rev-parse 'HEAD^{tree}')
prechecked_subject=$(printf '%s\n' 'malicious prechecked final subject' | \
  git -C "$implementation_repo" commit-tree "$prechecked_tree" -p "$us1_subject")
write_pass_review "$implementation_feature" REV-FINAL FINAL "$implementation_baseline" \
  "$implementation_baseline" "$prechecked_subject" T001,T002,T004,T006 \
  '- bash tests/run-all.sh' '- bash tests/run-all.sh — PASS'
expect_review fail implementation-candidate "$implementation_feature" REV-FINAL "review subject cannot pre-complete its own checkpoint" "checkpoint checkbox must be open in the subject commit"

bad_baseline_repo="$TEST_TMP/disallowed-baseline-repo"
bad_baseline_feature=$(init_feature_repo "$bad_baseline_repo")
write_pass_review "$bad_baseline_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review'
mkdir -p "$bad_baseline_repo/src"
printf '%s\n' 'product code committed too early' > "$bad_baseline_repo/src/premature.txt"
git -C "$bad_baseline_repo" add -- .
git -C "$bad_baseline_repo" commit -qm 'Invalid task baseline containing product code'
bad_baseline=$(git -C "$bad_baseline_repo" rev-parse HEAD)
printf '%s\n' 'foundation change' >> "$bad_baseline_repo/src/premature.txt"
rewrite "$bad_baseline_feature/tasks.md" 's/^- \[ \] T001/- [x] T001/'
rewrite "$bad_baseline_feature/tasks.md" 's/^- \[ \] T002/- [x] T002/'
git -C "$bad_baseline_repo" add -- src/premature.txt specs/001-hot-reload/tasks.md
git -C "$bad_baseline_repo" commit -qm 'Foundation on invalid baseline'
bad_baseline_subject=$(git -C "$bad_baseline_repo" rev-parse HEAD)
write_pass_review "$bad_baseline_feature" REV-FOUNDATION FOUNDATION "$bad_baseline" \
  "$bad_baseline" "$bad_baseline_subject" T001,T002 '- bash tests/unit.sh' '- bash tests/unit.sh — PASS'
rewrite "$bad_baseline_feature/tasks.md" 's/^- \[ \] T003/- [x] T003/'
expect_review fail implementation-candidate "$bad_baseline_feature" REV-FOUNDATION "implementation baseline commit cannot smuggle product or test paths" "checkpoint commit contains disallowed path"

missing_baseline_repo="$TEST_TMP/missing-baseline-handoff-repo"
missing_baseline_feature=$(init_feature_repo "$missing_baseline_repo")
printf '%s\n' \
  'specs/001-hot-reload/.gatespec/reviews/REV-TASKS/round-*-request.md' \
  'specs/001-hot-reload/.gatespec/reviews/REV-TASKS/round-*-verdict.md' \
  >> "$missing_baseline_repo/.git/info/exclude"
write_pass_review "$missing_baseline_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review'
git -C "$missing_baseline_repo" add -- .
git -C "$missing_baseline_repo" commit -qm 'Baseline missing ignored task request and verdict'
missing_baseline=$(git -C "$missing_baseline_repo" rev-parse HEAD)
mkdir -p "$missing_baseline_repo/src"
printf '%s\n' 'foundation' > "$missing_baseline_repo/src/foundation.txt"
rewrite "$missing_baseline_feature/tasks.md" 's/^- \[ \] T001/- [x] T001/'
rewrite "$missing_baseline_feature/tasks.md" 's/^- \[ \] T002/- [x] T002/'
git -C "$missing_baseline_repo" add -- src/foundation.txt specs/001-hot-reload/tasks.md
git -C "$missing_baseline_repo" commit -qm 'Foundation after incomplete handoff'
missing_baseline_subject=$(git -C "$missing_baseline_repo" rev-parse HEAD)
write_pass_review "$missing_baseline_feature" REV-FOUNDATION FOUNDATION "$missing_baseline" \
  "$missing_baseline" "$missing_baseline_subject" T001,T002 '- bash tests/unit.sh' '- bash tests/unit.sh — PASS'
rewrite "$missing_baseline_feature/tasks.md" 's/^- \[ \] T003/- [x] T003/'
expect_review fail implementation-candidate "$missing_baseline_feature" REV-FOUNDATION "implementation baseline must contain the complete task-review handoff" "round-00-request.md' is absent from the baseline commit"

echo ''
echo "==> checker fixtures: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
