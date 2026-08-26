#!/usr/bin/env bash
# Deterministic fixtures for scripts/bash/check-gate.sh.
# shellcheck disable=SC2016 # Fixture Markdown uses literal backticks.

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

strip_delivery_estimate() {
  local file="$1" tmp="$1.tmp"
  awk '
    /^\*\*Delivery Estimate Schema\*\*:/ {next}
    /^## Delivery Estimate([[:space:]]|$)/ {skip=1; next}
    skip && /^## / {skip=0}
    !skip {print}
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

strip_scope_contract() {
  local file="$1" tmp="$1.tmp"
  awk '
    /^\*\*Scope Contract Schema\*\*:/ {next}
    /^## Scope Contract([[:space:]]|$)/ {skip=1; next}
    skip && /^## / {skip=0}
    !skip {print}
  ' "$file" > "$tmp" && mv "$tmp" "$file"
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

## GateSpec Checkpoint Closure *(gatespec: mandatory)*
| Checkpoint | Contract refs | Production tasks | Verification tasks |
|---|---|---|---|
| REV-FOUNDATION | D1, FR-002 | T001 | T002 |
| REV-US1 | FR-001 | none | T004 |
| REV-FINAL | SC-001 | none | T006 |

## GateSpec Prior Review Closure *(gatespec: mandatory)*
| Finding-SHA256 | Source verdict | Required-before | Remediation tasks |
|---|---|---|---|
| none | none | none | none |

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

strip_task_closure() {
  local file="$1" tmp="$1.tmp"
  awk '
    /^## GateSpec Checkpoint Closure \*\(gatespec: mandatory\)\*$/ {skip=1; next}
    skip && /^## Phase / {skip=0}
    !skip {print}
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

strip_prior_closure() {
  local file="$1" tmp="$1.tmp"
  awk '
    /^## GateSpec Prior Review Closure \*\(gatespec: mandatory\)\*$/ {skip=1; next}
    skip && /^## Phase / {skip=0}
    !skip {print}
  ' "$file" > "$tmp" && mv "$tmp" "$file"
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

append_prior_finding() {
  local file="$1" after_source="$2" digest="$3" source="$4" required="$5" tasks="$6" tmp="$1.tmp"
  awk -v marker="| $digest | $after_source |" \
      -v row="| $digest | $source | $required | $tasks |" '
    {print}
    index($0, marker) == 1 {print row}
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

remove_prior_source() {
  local file="$1" source="$2" tmp="$1.tmp"
  awk -v needle="| $source |" '
    index($0, needle) > 0 {next}
    {print}
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

blocker_digest() {
  printf '%s\n' "$@" | sha_stream | awk '{print $1}'
}

changed_paths_digest() {
  local repo="$1" base="$2" subject="$3"
  git -C "$repo" diff --name-only --no-renames "$base" "$subject" \
    | LC_ALL=C sort | sha_stream | awk '{print $1}'
}

final_delta_digest() {
  local repo="$1" original="$2" subject="$3"
  git -C "$repo" diff-tree --raw -z --no-abbrev --no-renames "$original" "$subject" \
    | sha_stream | awk '{print $1}'
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
**Scope Contract Schema**: 1
**Delivery Estimate Schema**: 1
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
## Scope Contract
- **Primary outcome**: An operator saving a supported configuration while the daemon is running observes the complete new values within one second without disconnecting active clients.
- **Core completion refs**: `SC-001`
- **Retained baseline**: Existing configuration syntax plus network and CLI surfaces remain unchanged.
| Capability | Admission | Spec refs | Boundary rationale |
|---|---|---|---|
| CAP-001 — Apply saved configuration without connection loss | `core` | `FR-001, FR-002, SC-001` | Without reload timing or connection continuity, the operator does not receive the stated runtime outcome. |
## Delivery Estimate
- **Production additions**: `120..220`
- **Production churn**: `150..280`
- **Production files**: `3..6`
- **Estimate basis**: The watcher, store publication, lifecycle wiring, and build registration are comparable to one small subsystem change.
- **Production path basis**: src/config/**; include/config/**; CMakeLists.txt
- **Excluded paths**: tests/** — test; specs/** — specification/review; docs/** — documentation
- **Confidence**: medium — repository modules are known but caller cleanup may widen churn.
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
**Design Evidence Schema**: 1
**Delivery Estimate Schema**: 1
## Summary
Add portable polling and atomic snapshot replacement for CAP-001 while retaining existing configuration, network, and CLI behavior.
## Delivery Estimate
- **Production additions**: \`140..210\`
- **Production churn**: \`170..270\`
- **Production files**: \`4..6\`
- **Estimate basis**: Inspected ConfigService, ConfigStore, request handlers, build registration, and the required unit and integration surfaces.
- **Production path basis**: src/config/**; include/config/**; CMakeLists.txt
- **Excluded paths**: tests/** — test; specs/** — specification/review; docs/** — documentation
- **Confidence**: high — concrete modules and callers are identified; only local helper layout remains free.
- **Requirements estimate relation**: \`within\`
- **Requirements estimate rationale**: Design narrows the additions range while retaining the Requirements churn and file ceilings.
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
1. **Thread / concurrency model**:
   - **Execution contexts**: The existing main request thread reads snapshots; a new ConfigWatcher worker owns polling.
   - **Cross-context flow**: ConfigWatcher -> ConfigStore publishes one immutable snapshot; readers only acquire the published handle.
   - **Synchronization contract**: One atomic shared-pointer exchange publishes a fully validated snapshot; teardown cancels and joins the watcher before store destruction.
   - **Technical basis**: CAP-001, FR-001, FR-002, the existing request loop, and research.md#portable-watching.
2. **Object lifetimes & ownership**:
   - **Owned resources**: ConfigService uniquely owns ConfigWatcher and ConfigStore; readers temporarily share immutable ConfigSnapshot values.
   - **Lifetime flow**: Setup constructs the store then watcher; publishing moves a validated snapshot into shared ownership; teardown joins before releasing either owner.
   - **Resource contract**: At most the current and reader-retained prior snapshots remain live; failed parses release their unpublished candidate immediately.
   - **Technical basis**: CAP-001, FR-002, and data-model.md#config-snapshot.
3. **Key modules & classes**:
   - **Repository anchors**: Existing ConfigService is the startup entry point and existing request handlers read ConfigStore.
   - **Change map**: modified ConfigService wires dependencies; new ConfigWatcher detects changes; modified ConfigStore validates and publishes; request handlers remain behaviorally unchanged.
   - **Dependency contract**: ConfigService -> ConfigWatcher -> ConfigStore; handlers -> ConfigStore; ConfigStore never depends on handlers or the watcher.
   - **Technical basis**: CAP-001, FR-001, FR-002, D1, and the inspected src/config integration surface.
4. **Key internal APIs & interactions**:
   - **Existing entry points**: ConfigService::Start and ConfigStore::Current remain the integration entry points.
   - **Core contract skeleton**:
     \`\`\`cpp
     class ConfigWatcher { public: Result Start(); void Stop(); };
     class ConfigStore { public: Result Reload(); std::shared_ptr<const ConfigSnapshot> Current() const; };
     \`\`\`
   - **Primary interaction**: Success: watcher thread -> ConfigStore::Reload -> validate -> atomic publish -> readers observe next snapshot. Failure: validation returns an error, retains the prior snapshot, and emits one diagnostic.
   - **Semantic contract**: Reload never exposes a partial snapshot; Current is thread-safe and non-blocking; Stop is idempotent and joins the worker.
   - **Technical basis**: CAP-001, FR-001, FR-002, D1, and contracts/config-store.md.
5. **External interface behavior contracts**:
   - **Affected surfaces**: Existing configuration files gain hot-reload behavior; network and CLI surfaces remain unchanged.
   - **Behavior contract**: A valid save becomes visible within one second; an invalid save preserves active connections and the prior values while emitting one diagnostic.
   - **Compatibility contract**: Existing configuration syntax and startup validation remain unchanged; no migration or fallback mode is introduced.
   - **Technical basis**: CAP-001, FR-001, FR-002, SC-001, and contracts/config-reload.md.
6. **Setup / runtime / teardown phase interactions**:
   - **States & owner**: ConfigService owns Stopped, Starting, Running, and Stopping transitions; ConfigWatcher cannot transition service state.
   - **Phase flow**: Setup loads once then starts polling; runtime validates and publishes candidates; teardown requests stop, joins, then destroys store state.
   - **Failure / recovery contract**: Initial-load failure aborts startup; runtime reload failure retains Running state; repeated Stop calls perform no extra work.
   - **Technical basis**: CAP-001, FR-001, FR-002, quickstart.md, and the existing service lifecycle.
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

# Scope Contract Schema ------------------------------------------------------
clone_good scope-core-committed-deferred
# shellcheck disable=SC1004
rewrite "$TEST_TMP/scope-core-committed-deferred/spec.md" '/^| CAP-001/a\
| CAP-002 — Preserve an explicitly requested compatibility diagnostic | `committed` | `FR-002, SC-001` | The Primary outcome survives without it, but the user explicitly requested it in this delivery. |\
| CAP-003 — Replace the complete configuration API | `deferred` | `none` | It is outside this delivery and is not a future commitment. |'
seal "$TEST_TMP/scope-core-committed-deferred/spec.md"
expect pass spec "$TEST_TMP/scope-core-committed-deferred" \
  "core, committed, and deferred capabilities share one valid Scope Contract"

clone_good scope-constraint
# shellcheck disable=SC1004
rewrite "$TEST_TMP/scope-constraint/spec.md" '/^| CAP-001/a\
| CAP-002 — Emit the mandated audit event | `constraint` | `FR-002, SC-001` | An effective MUST requires the event even though the Primary outcome does not. |'
seal "$TEST_TMP/scope-constraint/spec.md"
expect pass spec "$TEST_TMP/scope-constraint" "constraint admission is structurally valid"

clone_good scope-schema-missing
rewrite "$TEST_TMP/scope-schema-missing/spec.md" '/^\*\*Scope Contract Schema\*\*:/d'
seal "$TEST_TMP/scope-schema-missing/spec.md"
expect fail spec "$TEST_TMP/scope-schema-missing" "Scope Contract schema is mandatory" \
  "expected exactly one '**Scope Contract Schema**: 1'"

clone_good scope-schema-duplicate
# shellcheck disable=SC1004
rewrite "$TEST_TMP/scope-schema-duplicate/spec.md" '/\*\*Scope Contract Schema\*\*: 1/a\
**Scope Contract Schema**: 1'
seal "$TEST_TMP/scope-schema-duplicate/spec.md"
expect fail spec "$TEST_TMP/scope-schema-duplicate" "duplicate Scope Contract schema fails" \
  "expected exactly one '**Scope Contract Schema**: 1'"

clone_good scope-schema-unknown
rewrite "$TEST_TMP/scope-schema-unknown/spec.md" \
  's/\*\*Scope Contract Schema\*\*: 1/**Scope Contract Schema**: 2/'
seal "$TEST_TMP/scope-schema-unknown/spec.md"
expect fail spec "$TEST_TMP/scope-schema-unknown" "unknown Scope Contract schema fails closed" \
  "unknown schemas are invalid"

clone_good scope-section-duplicate
# shellcheck disable=SC1004
rewrite "$TEST_TMP/scope-section-duplicate/spec.md" '/^## Delivery Estimate/i\
## Scope Contract'
seal "$TEST_TMP/scope-section-duplicate/spec.md"
expect fail spec "$TEST_TMP/scope-section-duplicate" "duplicate Scope Contract section fails" \
  "expected exactly one '## Scope Contract'"

clone_good scope-section-missing
strip_scope_contract "$TEST_TMP/scope-section-missing/spec.md"
# shellcheck disable=SC1004
rewrite "$TEST_TMP/scope-section-missing/spec.md" '/^\*\*Status\*\*:/a\
**Scope Contract Schema**: 1'
seal "$TEST_TMP/scope-section-missing/spec.md"
expect fail spec "$TEST_TMP/scope-section-missing" "partial Scope Contract fails closed" \
  "expected exactly one '## Scope Contract'"

for scope_field in 'Primary outcome' 'Core completion refs' 'Retained baseline'; do
  scope_slug=$(printf '%s' "$scope_field" | tr '[:upper:] ' '[:lower:]-')
  clone_good "scope-empty-$scope_slug"
  rewrite "$TEST_TMP/scope-empty-$scope_slug/spec.md" \
    "s/^- \*\*$scope_field\*\*:.*/- **$scope_field**: /"
  seal "$TEST_TMP/scope-empty-$scope_slug/spec.md"
  expect fail spec "$TEST_TMP/scope-empty-$scope_slug" \
    "Scope Contract $scope_field cannot be empty" "nonempty '$scope_field'"
done

clone_good scope-retained-none-without-reason
rewrite "$TEST_TMP/scope-retained-none-without-reason/spec.md" \
  's/^- \*\*Retained baseline\*\*:.*/- **Retained baseline**: None/'
seal "$TEST_TMP/scope-retained-none-without-reason/spec.md"
expect fail spec "$TEST_TMP/scope-retained-none-without-reason" \
  "Retained baseline None state requires a reason" "None — <reason>"

clone_good scope-duplicate-cap
# shellcheck disable=SC1004
rewrite "$TEST_TMP/scope-duplicate-cap/spec.md" '/^| CAP-001/a\
| CAP-001 — Duplicate reload capability | `committed` | `FR-001, SC-001` | The user requested this duplicate row. |'
seal "$TEST_TMP/scope-duplicate-cap/spec.md"
expect fail spec "$TEST_TMP/scope-duplicate-cap" "duplicate CAP ID fails" "CAP-001 is duplicated"

clone_good scope-invalid-cap
rewrite "$TEST_TMP/scope-invalid-cap/spec.md" 's/CAP-001 —/CAP-01 —/'
seal "$TEST_TMP/scope-invalid-cap/spec.md"
expect fail spec "$TEST_TMP/scope-invalid-cap" "CAP IDs require canonical three digits" \
  "CAP-### — <nonempty capability>"

clone_good scope-invalid-admission
rewrite "$TEST_TMP/scope-invalid-admission/spec.md" 's/`core`/`optional`/'
seal "$TEST_TMP/scope-invalid-admission/spec.md"
expect fail spec "$TEST_TMP/scope-invalid-admission" "unknown Admission fails" \
  "Admission must be core, committed, constraint, or deferred"

clone_good scope-noncanonical-ref
rewrite "$TEST_TMP/scope-noncanonical-ref/spec.md" \
  's/`FR-001, FR-002, SC-001`/`FR-1, FR-002, SC-001`/'
seal "$TEST_TMP/scope-noncanonical-ref/spec.md"
expect fail spec "$TEST_TMP/scope-noncanonical-ref" "Scope refs require canonical three-digit IDs" \
  "must be canonical FR-###/SC-### IDs"

clone_good scope-undefined-ref
rewrite "$TEST_TMP/scope-undefined-ref/spec.md" \
  's/`FR-001, FR-002, SC-001`/`FR-001, FR-999, SC-001`/'
seal "$TEST_TMP/scope-undefined-ref/spec.md"
expect fail spec "$TEST_TMP/scope-undefined-ref" "undefined Scope Contract ref fails" \
  "references undefined FR-999"

clone_good scope-undefined-sc
rewrite "$TEST_TMP/scope-undefined-sc/spec.md" \
  's/`FR-001, FR-002, SC-001`/`FR-001, FR-002, SC-999`/'
seal "$TEST_TMP/scope-undefined-sc/spec.md"
expect fail spec "$TEST_TMP/scope-undefined-sc" "undefined Scope Contract SC ref fails" \
  "references undefined SC-999"

clone_good scope-unmapped-fr
rewrite "$TEST_TMP/scope-unmapped-fr/spec.md" \
  's/`FR-001, FR-002, SC-001`/`FR-001, SC-001`/'
seal "$TEST_TMP/scope-unmapped-fr/spec.md"
expect fail spec "$TEST_TMP/scope-unmapped-fr" "every FR must map to a non-deferred CAP" \
  "FR-002 is not mapped"

clone_good scope-unmapped-sc
# shellcheck disable=SC1004
rewrite "$TEST_TMP/scope-unmapped-sc/spec.md" '/^- \*\*SC-001\*\*:/a\
- **SC-002**: Existing configuration syntax remains accepted without migration.'
seal "$TEST_TMP/scope-unmapped-sc/spec.md"
expect fail spec "$TEST_TMP/scope-unmapped-sc" "every SC must map to a non-deferred CAP" \
  "SC-002 is not mapped"

clone_good scope-cap-missing-sc
rewrite "$TEST_TMP/scope-cap-missing-sc/spec.md" \
  's/`FR-001, FR-002, SC-001`/`FR-001, FR-002`/'
seal "$TEST_TMP/scope-cap-missing-sc/spec.md"
expect fail spec "$TEST_TMP/scope-cap-missing-sc" \
  "every non-deferred CAP needs an FR and an SC" "requires at least one FR and one SC"

clone_good scope-deferred-has-refs
# shellcheck disable=SC1004
rewrite "$TEST_TMP/scope-deferred-has-refs/spec.md" '/^| CAP-001/a\
| CAP-002 — Replace the complete configuration API | `deferred` | `FR-001, SC-001` | It is outside this delivery. |'
seal "$TEST_TMP/scope-deferred-has-refs/spec.md"
expect fail spec "$TEST_TMP/scope-deferred-has-refs" "deferred CAP cannot carry Spec refs" \
  "must use exactly 'none'"

clone_good scope-core-completion-not-core
rewrite "$TEST_TMP/scope-core-completion-not-core/spec.md" 's/| `core` |/| `committed` |/'
seal "$TEST_TMP/scope-core-completion-not-core/spec.md"
expect fail spec "$TEST_TMP/scope-core-completion-not-core" \
  "Core completion SC must belong to a core CAP" "not mapped by a core capability"

clone_good scope-plan-duplicate
# shellcheck disable=SC1004
rewrite "$TEST_TMP/scope-plan-duplicate/plan.md" '/^## Delivery Estimate/i\
**Scope Contract Schema**: 1\
## Scope Contract\
Duplicated scope.'
seal "$TEST_TMP/scope-plan-duplicate/plan.md"
expect fail design "$TEST_TMP/scope-plan-duplicate" "Plan cannot duplicate the Scope Contract" \
  "do not duplicate Scope Contract"

clone_good legacy-scope-no-progress
strip_scope_contract "$TEST_TMP/legacy-scope-no-progress/spec.md"
seal "$TEST_TMP/legacy-scope-no-progress/spec.md"
expect fail spec "$TEST_TMP/legacy-scope-no-progress" \
  "unstarted legacy Requirements without Scope Contract must be revised" \
  "run gatespec.specify --revise before Design"

clone_good legacy-scope-checked-progress
strip_scope_contract "$TEST_TMP/legacy-scope-checked-progress/spec.md"
seal "$TEST_TMP/legacy-scope-checked-progress/spec.md"
make_tasks "$TEST_TMP/legacy-scope-checked-progress"
rewrite "$TEST_TMP/legacy-scope-checked-progress/tasks.md" 's/^- \[ \] T001/- [x] T001/'
expect pass spec "$TEST_TMP/legacy-scope-checked-progress" \
  "checked implementation progress preserves legacy Requirements read-only" \
  "implementation progress already exists"

clone_good legacy-scope-review-progress
strip_scope_contract "$TEST_TMP/legacy-scope-review-progress/spec.md"
seal "$TEST_TMP/legacy-scope-review-progress/spec.md"
mkdir -p "$TEST_TMP/legacy-scope-review-progress/.gatespec/reviews/REV-FOUNDATION"
printf '%s\n' '# implementation review began' \
  > "$TEST_TMP/legacy-scope-review-progress/.gatespec/reviews/REV-FOUNDATION/round-00-request.md"
expect pass spec "$TEST_TMP/legacy-scope-review-progress" \
  "implementation review progress preserves legacy Requirements read-only" \
  "implementation progress already exists"

legacy_scope_product_repo="$TEST_TMP/legacy-scope-product-progress-repo"
legacy_scope_product_feature=$(init_feature_repo "$legacy_scope_product_repo")
strip_scope_contract "$legacy_scope_product_feature/spec.md"
seal "$legacy_scope_product_feature/spec.md"
git -C "$legacy_scope_product_repo" add -- specs/001-hot-reload
git -C "$legacy_scope_product_repo" commit -qm 'Approve legacy scope before implementation'
mkdir -p "$legacy_scope_product_repo/src"
printf '%s\n' 'int scope_delivery_started = 1;' > "$legacy_scope_product_repo/src/runtime.cc"
git -C "$legacy_scope_product_repo" add -- src/runtime.cc
git -C "$legacy_scope_product_repo" commit -qm 'Begin scoped product implementation'
expect pass spec "$legacy_scope_product_feature" \
  "real production delta preserves legacy Requirements read-only" \
  "implementation progress already exists"

clone_good draft-missing-scope
strip_scope_contract "$TEST_TMP/draft-missing-scope/spec.md"
rewrite "$TEST_TMP/draft-missing-scope/spec.md" 's/Approved-Requirements (2026-08-07)/Draft/'
seal "$TEST_TMP/draft-missing-scope/spec.md"
expect fail spec "$TEST_TMP/draft-missing-scope" "Draft cannot omit Scope Contract" \
  "Scope Contract Schema 1 and one Scope Contract section are required"

# Delivery Estimate Schema ---------------------------------------------------
clone_good estimate-missing-field
rewrite "$TEST_TMP/estimate-missing-field/spec.md" '/^- \*\*Production additions\*\*:/d'
seal "$TEST_TMP/estimate-missing-field/spec.md"
expect fail spec "$TEST_TMP/estimate-missing-field" "delivery estimate requires every fixed field" "Production additions"

clone_good estimate-duplicate-schema
# shellcheck disable=SC1004
rewrite "$TEST_TMP/estimate-duplicate-schema/spec.md" '/\*\*Delivery Estimate Schema\*\*: 1/a\
**Delivery Estimate Schema**: 1'
seal "$TEST_TMP/estimate-duplicate-schema/spec.md"
expect fail spec "$TEST_TMP/estimate-duplicate-schema" "duplicate delivery estimate schema fails" "expected exactly one '**Delivery Estimate Schema**: 1'"

clone_good estimate-duplicate-section
# shellcheck disable=SC1004
rewrite "$TEST_TMP/estimate-duplicate-section/spec.md" '/^## User Scenarios & Testing/i\
## Delivery Estimate'
seal "$TEST_TMP/estimate-duplicate-section/spec.md"
expect fail spec "$TEST_TMP/estimate-duplicate-section" "duplicate delivery estimate section fails" "expected exactly one '## Delivery Estimate'"

clone_good estimate-unknown-schema
rewrite "$TEST_TMP/estimate-unknown-schema/spec.md" 's/\*\*Delivery Estimate Schema\*\*: 1/**Delivery Estimate Schema**: 2/'
seal "$TEST_TMP/estimate-unknown-schema/spec.md"
expect fail spec "$TEST_TMP/estimate-unknown-schema" "unknown delivery estimate schema fails closed" "unknown schemas are invalid"

clone_good estimate-plan-unknown-schema
rewrite "$TEST_TMP/estimate-plan-unknown-schema/plan.md" 's/\*\*Delivery Estimate Schema\*\*: 1/**Delivery Estimate Schema**: 9/'
seal "$TEST_TMP/estimate-plan-unknown-schema/plan.md"
expect fail design "$TEST_TMP/estimate-plan-unknown-schema" "unknown Plan delivery estimate schema fails closed" "unknown schemas are invalid"

clone_good estimate-inverted
rewrite "$TEST_TMP/estimate-inverted/spec.md" 's/`120\.\.220`/`220..120`/'
seal "$TEST_TMP/estimate-inverted/spec.md"
expect fail spec "$TEST_TMP/estimate-inverted" "inverted delivery estimate range fails" "lower bound exceeds"

clone_good estimate-illegal
rewrite "$TEST_TMP/estimate-illegal/spec.md" 's/`120\.\.220`/`-1..220`/'
seal "$TEST_TMP/estimate-illegal/spec.md"
expect fail spec "$TEST_TMP/estimate-illegal" "negative delivery estimate range fails" "non-negative 'lower..upper'"

for empty_estimate_field in 'Estimate basis' 'Production path basis' 'Excluded paths' 'Confidence'; do
  estimate_slug=$(printf '%s' "$empty_estimate_field" | tr '[:upper:] ' '[:lower:]-')
  clone_good "estimate-empty-$estimate_slug"
  rewrite "$TEST_TMP/estimate-empty-$estimate_slug/spec.md" "s/^- \*\*$empty_estimate_field\*\*:.*/- **$empty_estimate_field**: /"
  seal "$TEST_TMP/estimate-empty-$estimate_slug/spec.md"
  expect fail spec "$TEST_TMP/estimate-empty-$estimate_slug" \
    "delivery estimate $empty_estimate_field cannot be empty" "nonempty '$empty_estimate_field'"
done

clone_good estimate-additions-over-churn
rewrite "$TEST_TMP/estimate-additions-over-churn/spec.md" 's/`150\.\.280`/`100..200`/'
seal "$TEST_TMP/estimate-additions-over-churn/spec.md"
expect fail spec "$TEST_TMP/estimate-additions-over-churn" "additions cannot exceed churn bounds" "cannot exceed Production churn"

clone_good estimate-generated-without-source
rewrite "$TEST_TMP/estimate-generated-without-source/spec.md" 's|tests/\*\* — test; specs/\*\* — specification/review; docs/\*\* — documentation|generated: src/generated/config.cc — reproducible output|'
seal "$TEST_TMP/estimate-generated-without-source/spec.md"
expect fail spec "$TEST_TMP/estimate-generated-without-source" "generated exclusion requires its source" "generated exclusions must use"

clone_good estimate-generated-valid
rewrite "$TEST_TMP/estimate-generated-valid/spec.md" 's|tests/\*\* — test; specs/\*\* — specification/review; docs/\*\* — documentation|tests/** — test; generated: src/generated/config.cc <- schema/config.proto via protoc|'
seal "$TEST_TMP/estimate-generated-valid/spec.md"
expect pass spec "$TEST_TMP/estimate-generated-valid" "generated exclusion with output, source, and generator passes"

clone_good estimate-large-disclosed
rewrite "$TEST_TMP/estimate-large-disclosed/spec.md" 's/`120\.\.220`/`1000000..2000000`/'
rewrite "$TEST_TMP/estimate-large-disclosed/spec.md" 's/`150\.\.280`/`1200000..3000000`/'
rewrite "$TEST_TMP/estimate-large-disclosed/spec.md" 's/`3\.\.6`/`10000..20000`/'
seal "$TEST_TMP/estimate-large-disclosed/spec.md"
expect pass spec "$TEST_TMP/estimate-large-disclosed" "large xclaw-scale estimate passes when explicitly disclosed"

for estimate_relation in expanded reduced; do
  clone_good "estimate-relation-$estimate_relation"
  rewrite "$TEST_TMP/estimate-relation-$estimate_relation/plan.md" "s/\`within\`/\`$estimate_relation\`/"
  seal "$TEST_TMP/estimate-relation-$estimate_relation/plan.md"
  expect pass design "$TEST_TMP/estimate-relation-$estimate_relation" \
    "Design records a valid $estimate_relation Requirements estimate relation"
done

clone_good estimate-relation-invalid
rewrite "$TEST_TMP/estimate-relation-invalid/plan.md" 's/`within`/`larger`/'
seal "$TEST_TMP/estimate-relation-invalid/plan.md"
expect fail design "$TEST_TMP/estimate-relation-invalid" "invalid Requirements estimate relation fails" "must be within, expanded, or reduced"

clone_good legacy-requirements-estimate
strip_delivery_estimate "$TEST_TMP/legacy-requirements-estimate/spec.md"
seal "$TEST_TMP/legacy-requirements-estimate/spec.md"
expect pass spec "$TEST_TMP/legacy-requirements-estimate" "legacy Approved Requirements without estimate remains warning-only" "legacy Approved Requirements"

clone_good draft-missing-estimate
strip_delivery_estimate "$TEST_TMP/draft-missing-estimate/spec.md"
rewrite "$TEST_TMP/draft-missing-estimate/spec.md" 's/Approved-Requirements (2026-08-07)/Draft/'
seal "$TEST_TMP/draft-missing-estimate/spec.md"
expect fail spec "$TEST_TMP/draft-missing-estimate" "new or revised Draft cannot omit delivery estimate" "Delivery Estimate Schema 1"

clone_good legacy-requirements-design-estimate
strip_delivery_estimate "$TEST_TMP/legacy-requirements-design-estimate/spec.md"
seal "$TEST_TMP/legacy-requirements-design-estimate/spec.md"
legacy_spec_hash=$(hash_of "$TEST_TMP/legacy-requirements-design-estimate/spec.md")
rewrite "$TEST_TMP/legacy-requirements-design-estimate/plan.md" \
  "s/^\*\*Requirements Content-SHA256\*\*:.*/**Requirements Content-SHA256**: \`$legacy_spec_hash\`/"
rewrite "$TEST_TMP/legacy-requirements-design-estimate/plan.md" 's/`within`/`not-applicable`/'
seal "$TEST_TMP/legacy-requirements-design-estimate/plan.md"
expect pass design "$TEST_TMP/legacy-requirements-design-estimate" "Design supplies the first estimate for legacy Requirements"

clone_good legacy-design-estimate-no-progress
strip_delivery_estimate "$TEST_TMP/legacy-design-estimate-no-progress/plan.md"
seal "$TEST_TMP/legacy-design-estimate-no-progress/plan.md"
expect fail design "$TEST_TMP/legacy-design-estimate-no-progress" \
  "legacy Design without implementation progress must be revised" "run gatespec.plan --revise before tasks"

clone_good draft-design-missing-estimate
strip_delivery_estimate "$TEST_TMP/draft-design-missing-estimate/plan.md"
rewrite "$TEST_TMP/draft-design-missing-estimate/plan.md" 's/Approved-Design (2026-08-07)/Draft/'
seal "$TEST_TMP/draft-design-missing-estimate/plan.md"
expect fail design "$TEST_TMP/draft-design-missing-estimate" \
  "new or revised Design Draft cannot omit delivery estimate" "Delivery Estimate Schema 1"

clone_good legacy-design-estimate-progress
strip_delivery_estimate "$TEST_TMP/legacy-design-estimate-progress/plan.md"
seal "$TEST_TMP/legacy-design-estimate-progress/plan.md"
make_tasks "$TEST_TMP/legacy-design-estimate-progress"
rewrite "$TEST_TMP/legacy-design-estimate-progress/tasks.md" 's/^- \[ \] T001/- [x] T001/'
expect pass design "$TEST_TMP/legacy-design-estimate-progress" \
  "legacy Design with checked implementation progress remains valid" "implementation progress already exists"

legacy_product_repo="$TEST_TMP/legacy-design-product-progress-repo"
legacy_product_feature=$(init_feature_repo "$legacy_product_repo")
strip_delivery_estimate "$legacy_product_feature/plan.md"
seal "$legacy_product_feature/plan.md"
git -C "$legacy_product_repo" add -- specs/001-hot-reload
git -C "$legacy_product_repo" commit -qm 'Approve legacy design before implementation'
mkdir -p "$legacy_product_repo/src"
printf '%s\n' 'int implemented_after_plan = 1;' > "$legacy_product_repo/src/runtime.cc"
git -C "$legacy_product_repo" add -- src/runtime.cc
git -C "$legacy_product_repo" commit -qm 'Begin product implementation'
expect pass design "$legacy_product_feature" \
  "legacy Design with a committed product delta remains valid" "implementation progress already exists"

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
expect_silent retask-eligible "$TEST_TMP/auto" "unmarked auto-track retask eligibility is truly silent"
expect_silent implementation-candidate "$TEST_TMP/auto" "unmarked auto-track implementation candidate is truly silent"
expect_silent implementation-review "$TEST_TMP/auto" "unmarked auto-track implementation review is truly silent"

clone_good displaced-marker
rewrite "$TEST_TMP/displaced-marker/spec.md" '1{h;d;};2{G;}'
expect fail spec "$TEST_TMP/displaced-marker" "marker on a later line fails" "not line 1"
expect fail tasks-structure "$TEST_TMP/displaced-marker" "displaced marker fails before tasks structure" "not line 1"
expect fail task-review "$TEST_TMP/displaced-marker" "displaced marker fails before task review" "not line 1"
expect fail retask-eligible "$TEST_TMP/displaced-marker" "displaced marker fails before retask eligibility" "not line 1"
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

clone_good scenario-first-decision
awk '
  /^## Decision Log/ {
    print
    print "### D1: Should operators trade portability for immediate reload?"
    print "- **Scenario**: An operator saves a valid config while the service is handling requests; reload should become visible without a restart."
    print "- **Fixed boundary**: Invalid config must retain the prior snapshot and supported platforms cannot change."
    print "- **Why this needs you**: The choice changes reload latency and platform-specific maintenance cost."
    print "- **Options**:"
    print "  - A. Every platform observes the update within one second — mechanism: portable polling; constraint result: satisfies all constraints."
    print "  - B. Supported native platforms observe it immediately — mechanism: platform notifications; constraint result: requires per-platform adapters."
    print "- **Recommendation**: A — the bounded delay buys one portable behavior."
    print "- **Technical basis**: FR-001, FR-002, ConfigWatcher, and the supported-platform constraint."
    print "- **Approved**: A (2026-08-07)"
    skip=1
    next
  }
  skip && /^## Design Detailing/ {skip=0}
  !skip {print}
' "$TEST_TMP/good/plan.md" > "$TEST_TMP/scenario-first-decision/plan.md.tmp" && mv "$TEST_TMP/scenario-first-decision/plan.md.tmp" "$TEST_TMP/scenario-first-decision/plan.md"
seal "$TEST_TMP/scenario-first-decision/plan.md"
expect pass design "$TEST_TMP/scenario-first-decision" "structured decision blocks remain checker-compatible after presentation change"

clone_good zero-decision
awk '
  /^## Decision Log/ {print; print "- None — no design choice required individual human approval."; skip=1; next}
  skip && /^## Design Detailing/ {skip=0}
  !skip {print}
' "$TEST_TMP/good/plan.md" > "$TEST_TMP/zero-decision/plan.md.tmp" && mv "$TEST_TMP/zero-decision/plan.md.tmp" "$TEST_TMP/zero-decision/plan.md"
seal "$TEST_TMP/zero-decision/plan.md"
expect pass design "$TEST_TMP/zero-decision" "fixed zero-decision state passes"

clone_good missing-design-evidence-schema
rewrite "$TEST_TMP/missing-design-evidence-schema/plan.md" '/^\*\*Design Evidence Schema\*\*:/d'
seal "$TEST_TMP/missing-design-evidence-schema/plan.md"
expect fail design "$TEST_TMP/missing-design-evidence-schema" "design evidence schema is mandatory" "Design Evidence Schema"

clone_good unsupported-design-evidence-schema
rewrite "$TEST_TMP/unsupported-design-evidence-schema/plan.md" 's/^\*\*Design Evidence Schema\*\*: 1/**Design Evidence Schema**: 2/'
seal "$TEST_TMP/unsupported-design-evidence-schema/plan.md"
expect fail design "$TEST_TMP/unsupported-design-evidence-schema" "unknown design evidence schema fails closed" "Design Evidence Schema"

clone_good duplicate-design-evidence-schema
# shellcheck disable=SC1004
rewrite "$TEST_TMP/duplicate-design-evidence-schema/plan.md" '/^\*\*Design Evidence Schema\*\*: 1/a\
**Design Evidence Schema**: 1'
seal "$TEST_TMP/duplicate-design-evidence-schema/plan.md"
expect fail design "$TEST_TMP/duplicate-design-evidence-schema" "design evidence schema must be unique" "Design Evidence Schema"

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
awk '
  /^1\. \*\*Thread \/ concurrency model\*\*:/ {print "1. **Thread / concurrency model**: N/A"; skip=1; next}
  skip && /^2\. \*\*Object lifetimes/ {skip=0}
  !skip {print}
' "$TEST_TMP/no-reason-na/plan.md" > "$TEST_TMP/no-reason-na/plan.md.tmp" && mv "$TEST_TMP/no-reason-na/plan.md.tmp" "$TEST_TMP/no-reason-na/plan.md"
seal "$TEST_TMP/no-reason-na/plan.md"
expect fail design "$TEST_TMP/no-reason-na" "N/A without reason fails" "uses N/A without"

clone_good reasoned-na
awk '
  /^1\. \*\*Thread \/ concurrency model\*\*:/ {print "1. **Thread / concurrency model**: N/A — execution is single-threaded and changes no cross-context contract."; skip=1; next}
  skip && /^2\. \*\*Object lifetimes/ {skip=0}
  !skip {print}
' "$TEST_TMP/reasoned-na/plan.md" > "$TEST_TMP/reasoned-na/plan.md.tmp" && mv "$TEST_TMP/reasoned-na/plan.md.tmp" "$TEST_TMP/reasoned-na/plan.md"
seal "$TEST_TMP/reasoned-na/plan.md"
expect pass design "$TEST_TMP/reasoned-na" "N/A with a reason passes"

clone_good mixed-na-structure
rewrite "$TEST_TMP/mixed-na-structure/plan.md" 's/^1\. \*\*Thread \/ concurrency model\*\*:/1. **Thread \/ concurrency model**: N\/A — no concurrency change./'
seal "$TEST_TMP/mixed-na-structure/plan.md"
expect fail design "$TEST_TMP/mixed-na-structure" "inline N/A cannot retain structured evidence" "cannot mix inline N/A"

clone_good shallow-design-detail
awk '
  /^3\. \*\*Key modules & classes\*\*:/ {print "3. **Key modules & classes**: Add ConfigWatcher."; skip=1; next}
  skip && /^4\. \*\*Key internal APIs/ {skip=0}
  !skip {print}
' "$TEST_TMP/shallow-design-detail/plan.md" > "$TEST_TMP/shallow-design-detail/plan.md.tmp" && mv "$TEST_TMP/shallow-design-detail/plan.md.tmp" "$TEST_TMP/shallow-design-detail/plan.md"
seal "$TEST_TMP/shallow-design-detail/plan.md"
expect fail design "$TEST_TMP/shallow-design-detail" "legacy shallow detail cannot satisfy schema 1" "must use its structured fields"

clone_good missing-design-detail-field
rewrite "$TEST_TMP/missing-design-detail-field/plan.md" '/^[[:space:]]*- \*\*Cross-context flow\*\*:/d'
seal "$TEST_TMP/missing-design-detail-field/plan.md"
expect fail design "$TEST_TMP/missing-design-detail-field" "missing structured design field fails" "requires exactly one 'Cross-context flow'"

clone_good duplicate-design-detail-field
# shellcheck disable=SC1004
rewrite "$TEST_TMP/duplicate-design-detail-field/plan.md" '/^[[:space:]]*- \*\*Cross-context flow\*\*:/a\
   - **Cross-context flow**: duplicate.'
seal "$TEST_TMP/duplicate-design-detail-field/plan.md"
expect fail design "$TEST_TMP/duplicate-design-detail-field" "duplicate structured design field fails" "requires exactly one 'Cross-context flow'"

clone_good empty-design-detail-field
rewrite "$TEST_TMP/empty-design-detail-field/plan.md" 's/^[[:space:]]*- \*\*Cross-context flow\*\*:.*/   - **Cross-context flow**:/'
seal "$TEST_TMP/empty-design-detail-field/plan.md"
expect fail design "$TEST_TMP/empty-design-detail-field" "empty structured design field fails" "is empty or still a placeholder"

clone_good placeholder-design-detail-field
rewrite "$TEST_TMP/placeholder-design-detail-field/plan.md" 's/^[[:space:]]*- \*\*Execution contexts\*\*:.*/   - **Execution contexts**: [existing and planned threads]/'
seal "$TEST_TMP/placeholder-design-detail-field/plan.md"
expect fail design "$TEST_TMP/placeholder-design-detail-field" "structured design placeholder fails" "is empty or still a placeholder"

clone_good na-technical-basis
awk '
  !done && /^[[:space:]]*- \*\*Technical basis\*\*:/ {print "   - **Technical basis**: N/A — no trace recorded."; done=1; next}
  {print}
' "$TEST_TMP/na-technical-basis/plan.md" > "$TEST_TMP/na-technical-basis/plan.md.tmp" && mv "$TEST_TMP/na-technical-basis/plan.md.tmp" "$TEST_TMP/na-technical-basis/plan.md"
seal "$TEST_TMP/na-technical-basis/plan.md"
expect fail design "$TEST_TMP/na-technical-basis" "populated dimension requires technical basis" "Technical basis' cannot be N/A"

clone_good prose-core-contract
# Literal Markdown fences in the sed program must remain single quoted.
# shellcheck disable=SC2016
rewrite "$TEST_TMP/prose-core-contract/plan.md" '/^[[:space:]]*```cpp$/d; /^[[:space:]]*```$/d'
seal "$TEST_TMP/prose-core-contract/plan.md"
expect fail design "$TEST_TMP/prose-core-contract" "core contract requires code or reasoned N/A" "requires a language-tagged code fence"

clone_good empty-core-contract
rewrite "$TEST_TMP/empty-core-contract/plan.md" '/class ConfigWatcher/d; /class ConfigStore/d'
seal "$TEST_TMP/empty-core-contract/plan.md"
expect fail design "$TEST_TMP/empty-core-contract" "core contract code fence requires declarations" "has no declaration content"

clone_good no-core-contract
awk '
  /^   - \*\*Core contract skeleton\*\*:/ {print "   - **Core contract skeleton**: N/A — this configuration-only variant changes no executable interface."; skip=1; next}
  skip && /^   - \*\*Primary interaction\*\*:/ {skip=0}
  !skip {print}
' "$TEST_TMP/no-core-contract/plan.md" > "$TEST_TMP/no-core-contract/plan.md.tmp" && mv "$TEST_TMP/no-core-contract/plan.md.tmp" "$TEST_TMP/no-core-contract/plan.md"
seal "$TEST_TMP/no-core-contract/plan.md"
expect pass design "$TEST_TMP/no-core-contract" "reasoned no-code contract remains valid"

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

clone_good closure-missing
make_tasks "$TEST_TMP/closure-missing"
strip_task_closure "$TEST_TMP/closure-missing/tasks.md"
expect fail tasks-structure "$TEST_TMP/closure-missing" "new tasks require both mandatory Closure sections"

clone_good closure-half
make_tasks "$TEST_TMP/closure-half"
strip_prior_closure "$TEST_TMP/closure-half/tasks.md"
expect fail tasks-structure "$TEST_TMP/closure-half" "one Closure section cannot use legacy grandfathering"

clone_good closure-header
make_tasks "$TEST_TMP/closure-header"
rewrite "$TEST_TMP/closure-header/tasks.md" 's/| Contract refs |/| Contract references |/'
expect fail tasks-structure "$TEST_TMP/closure-header" "Closure table headers are exact protocol tokens"

clone_good closure-placement
make_tasks "$TEST_TMP/closure-placement"
awk '
  /^## Phase 1/ {print "## Native Notes"; print ""}
  {print}
' "$TEST_TMP/closure-placement/tasks.md" > "$TEST_TMP/closure-placement/tasks.md.tmp"
mv "$TEST_TMP/closure-placement/tasks.md.tmp" "$TEST_TMP/closure-placement/tasks.md"
expect fail tasks-structure "$TEST_TMP/closure-placement" "Closure sections must be the final two H2 sections before phases"

clone_good closure-checkpoint-order
make_tasks "$TEST_TMP/closure-checkpoint-order"
rewrite "$TEST_TMP/closure-checkpoint-order/tasks.md" 's/^| REV-FOUNDATION |/| REV-TEMP |/; s/^| REV-US1 |/| REV-FOUNDATION |/; s/^| REV-TEMP |/| REV-US1 |/'
expect fail tasks-structure "$TEST_TMP/closure-checkpoint-order" "Closure checkpoint rows follow approved Plan order"

clone_good closure-task-duplicate
make_tasks "$TEST_TMP/closure-task-duplicate"
rewrite "$TEST_TMP/closure-task-duplicate/tasks.md" 's/| REV-FOUNDATION | D1, FR-002 | T001 | T002 |/| REV-FOUNDATION | D1, FR-002 | T001 | T001, T002 |/'
expect fail tasks-structure "$TEST_TMP/closure-task-duplicate" "each non-checkpoint task appears globally exactly once in Closure"

clone_good closure-task-interval
make_tasks "$TEST_TMP/closure-task-interval"
rewrite "$TEST_TMP/closure-task-interval/tasks.md" 's/| REV-FOUNDATION | D1, FR-002 | T001 | T002 |/| REV-FOUNDATION | D1, FR-002 | T001 | T004 |/; s/| REV-US1 | FR-001 | none | T004 |/| REV-US1 | FR-001 | none | T002 |/'
expect fail tasks-structure "$TEST_TMP/closure-task-interval" "Closure task assignments stay inside their strict checkpoint interval"

clone_good closure-no-verification
make_tasks "$TEST_TMP/closure-no-verification"
rewrite "$TEST_TMP/closure-no-verification/tasks.md" 's/| REV-FINAL | SC-001 | none | T006 |/| REV-FINAL | SC-001 | T006 | none |/'
expect fail tasks-structure "$TEST_TMP/closure-no-verification" "every checkpoint Closure row has verification work"

clone_good closure-ref-coverage
make_tasks "$TEST_TMP/closure-ref-coverage"
rewrite "$TEST_TMP/closure-ref-coverage/tasks.md" 's/| REV-FINAL | SC-001 |/| REV-FINAL | D1 |/'
expect fail tasks-structure "$TEST_TMP/closure-ref-coverage" "Closure refs cover every Requirements and approved Design ID"

clone_good closure-ref-order
make_tasks "$TEST_TMP/closure-ref-order"
rewrite "$TEST_TMP/closure-ref-order/tasks.md" 's/| REV-FOUNDATION | D1, FR-002 |/| REV-FOUNDATION | FR-002, D1 |/'
expect fail tasks-structure "$TEST_TMP/closure-ref-order" "Closure refs use C-sort and comma-space formatting"

clone_good closure-ref-range
make_tasks "$TEST_TMP/closure-ref-range"
rewrite "$TEST_TMP/closure-ref-range/tasks.md" 's/| REV-FOUNDATION | D1, FR-002 |/| REV-FOUNDATION | D1-FR-002 |/'
expect fail tasks-structure "$TEST_TMP/closure-ref-range" "Closure refs reject ranges and require original IDs"

clone_good closure-cap-ref
make_tasks "$TEST_TMP/closure-cap-ref"
rewrite "$TEST_TMP/closure-cap-ref/tasks.md" \
  's/| REV-FOUNDATION | D1, FR-002 |/| REV-FOUNDATION | CAP-001, D1, FR-002 |/'
expect fail tasks-structure "$TEST_TMP/closure-cap-ref" \
  "CAP IDs stay out of task Closure" "contains invalid identifier 'CAP-001'"

clone_good prior-multiline
make_tasks "$TEST_TMP/prior-multiline"
write_pass_review "$TEST_TMP/prior-multiline" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- Fixture limitation.' 00 none BLOCKED
awk '
  $0 == "- BLOCKER: fixture remediation required" {
    print "- BLOCKER: Add rollback verification before implementation."
    print "  The verification must retain an active connection across reload."
    next
  }
  {print}
' "$TEST_TMP/prior-multiline/.gatespec/reviews/REV-TASKS/round-00-verdict.md" \
  > "$TEST_TMP/prior-multiline/.gatespec/reviews/REV-TASKS/round-00-verdict.md.tmp"
mv "$TEST_TMP/prior-multiline/.gatespec/reviews/REV-TASKS/round-00-verdict.md.tmp" \
  "$TEST_TMP/prior-multiline/.gatespec/reviews/REV-TASKS/round-00-verdict.md"
seal_self_hash "$TEST_TMP/prior-multiline/.gatespec/reviews/REV-TASKS/round-00-verdict.md" 'Verdict-SHA256'
multiline_finding=$(blocker_digest \
  '- BLOCKER: Add rollback verification before implementation.' \
  '  The verification must retain an active connection across reload.')
set_prior_finding "$TEST_TMP/prior-multiline/tasks.md" "$multiline_finding" \
  '.gatespec/reviews/REV-TASKS/round-00-verdict.md#B01' REV-FOUNDATION T002
expect pass tasks-structure "$TEST_TMP/prior-multiline" \
  "Prior Review Closure binds the full LF-delimited multiline BLOCKER item"

clone_good prior-blank-continuation
make_tasks "$TEST_TMP/prior-blank-continuation"
write_pass_review "$TEST_TMP/prior-blank-continuation" REV-TASKS TASKS \
  not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' \
  '- Fixture limitation.' 00 none BLOCKED
awk '
  $0 == "- BLOCKER: fixture remediation required" {
    print "- BLOCKER: Add rollback verification before implementation."
    print ""
    print "  This visually indented paragraph must not escape the blocker digest."
    next
  }
  {print}
' "$TEST_TMP/prior-blank-continuation/.gatespec/reviews/REV-TASKS/round-00-verdict.md" \
  > "$TEST_TMP/prior-blank-continuation/.gatespec/reviews/REV-TASKS/round-00-verdict.md.tmp"
mv "$TEST_TMP/prior-blank-continuation/.gatespec/reviews/REV-TASKS/round-00-verdict.md.tmp" \
  "$TEST_TMP/prior-blank-continuation/.gatespec/reviews/REV-TASKS/round-00-verdict.md"
seal_self_hash \
  "$TEST_TMP/prior-blank-continuation/.gatespec/reviews/REV-TASKS/round-00-verdict.md" \
  'Verdict-SHA256'
blank_truncated_finding=$(blocker_digest \
  '- BLOCKER: Add rollback verification before implementation.')
set_prior_finding "$TEST_TMP/prior-blank-continuation/tasks.md" "$blank_truncated_finding" \
  '.gatespec/reviews/REV-TASKS/round-00-verdict.md#B01' REV-FOUNDATION T002
expect fail tasks-structure "$TEST_TMP/prior-blank-continuation" \
  "a blank line cannot make an indented BLOCKER continuation disappear from Closure binding"

clone_good prior-duplicate-text
make_tasks "$TEST_TMP/prior-duplicate-text"
write_pass_review "$TEST_TMP/prior-duplicate-text" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- Fixture limitation.' 00 none BLOCKED
duplicate_round00_hash=$(receipt_field \
  "$TEST_TMP/prior-duplicate-text/.gatespec/reviews/REV-TASKS/round-00-verdict.md" 'Verdict-SHA256')
rewrite "$TEST_TMP/prior-duplicate-text/tasks.md" \
  's/Create the feature scaffolding/Create duplicate-finding scaffolding/'
write_pass_review "$TEST_TMP/prior-duplicate-text" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- Fixture limitation.' 01 "$duplicate_round00_hash" BLOCKED
duplicate_finding=$(blocker_digest '- BLOCKER: fixture remediation required')
set_prior_finding "$TEST_TMP/prior-duplicate-text/tasks.md" "$duplicate_finding" \
  '.gatespec/reviews/REV-TASKS/round-00-verdict.md#B01' REV-FOUNDATION T001
append_prior_finding "$TEST_TMP/prior-duplicate-text/tasks.md" \
  '.gatespec/reviews/REV-TASKS/round-00-verdict.md#B01' "$duplicate_finding" \
  '.gatespec/reviews/REV-TASKS/round-01-verdict.md#B01' REV-FOUNDATION T002
expect pass tasks-structure "$TEST_TMP/prior-duplicate-text" \
  "identical blocker text in distinct verdict items remains two Closure rows"

cp -R "$TEST_TMP/prior-multiline" "$TEST_TMP/prior-finding-hash"
rewrite "$TEST_TMP/prior-finding-hash/tasks.md" "s/$multiline_finding/0000000000000000000000000000000000000000000000000000000000000000/"
expect fail tasks-structure "$TEST_TMP/prior-finding-hash" "Prior Review Closure rejects a stale finding hash"

cp -R "$TEST_TMP/prior-multiline" "$TEST_TMP/prior-finding-missing"
clear_prior_finding "$TEST_TMP/prior-finding-missing/tasks.md" "$multiline_finding"
expect fail tasks-structure "$TEST_TMP/prior-finding-missing" "current matching REV-TASKS blockers cannot be omitted from Closure"

cp -R "$TEST_TMP/prior-multiline" "$TEST_TMP/prior-remediation-late"
rewrite "$TEST_TMP/prior-remediation-late/tasks.md" 's/| REV-FOUNDATION | T002 |$/| REV-FOUNDATION | T004 |/'
expect fail tasks-structure "$TEST_TMP/prior-remediation-late" \
  "finding remediation must exist, be executable, and precede Required-before"

cp -R "$TEST_TMP/prior-multiline" "$TEST_TMP/prior-archive"
mkdir -p "$TEST_TMP/prior-archive/.gatespec/archive/20260824T031415Z-retask/reviews"
cp "$TEST_TMP/prior-archive/tasks.md" \
  "$TEST_TMP/prior-archive/.gatespec/archive/20260824T031415Z-retask/tasks.md"
clear_prior_finding \
  "$TEST_TMP/prior-archive/.gatespec/archive/20260824T031415Z-retask/tasks.md" \
  "$multiline_finding"
mv "$TEST_TMP/prior-archive/.gatespec/reviews/REV-TASKS" \
  "$TEST_TMP/prior-archive/.gatespec/archive/20260824T031415Z-retask/reviews/REV-TASKS"
rewrite "$TEST_TMP/prior-archive/tasks.md" \
  's|.gatespec/reviews/REV-TASKS/round-00-verdict.md#B01|.gatespec/archive/20260824T031415Z-retask/reviews/REV-TASKS/round-00-verdict.md#B01|'
expect pass tasks-structure "$TEST_TMP/prior-archive" "retask archives remain finding sources"

cp -R "$TEST_TMP/prior-multiline" "$TEST_TMP/prior-restart-archive"
mkdir -p "$TEST_TMP/prior-restart-archive/.gatespec/archive/20260824T031415Z-restart/reviews"
mv "$TEST_TMP/prior-restart-archive/.gatespec/reviews/REV-TASKS" \
  "$TEST_TMP/prior-restart-archive/.gatespec/archive/20260824T031415Z-restart/reviews/REV-TASKS"
clear_prior_finding "$TEST_TMP/prior-restart-archive/tasks.md" "$multiline_finding"
expect pass tasks-structure "$TEST_TMP/prior-restart-archive" "non-retask archives are not Prior Review finding sources"

clone_good prior-retask-missing-review
make_tasks "$TEST_TMP/prior-retask-missing-review"
mkdir -p "$TEST_TMP/prior-retask-missing-review/.gatespec/archive/20260824T031416Z-retask"
cp "$TEST_TMP/prior-retask-missing-review/tasks.md" \
  "$TEST_TMP/prior-retask-missing-review/.gatespec/archive/20260824T031416Z-retask/tasks.md"
expect fail tasks-structure "$TEST_TMP/prior-retask-missing-review" \
  "a retask archive cannot erase blocker lineage by omitting its REV-TASKS directory"

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
bash "$SCRIPT" retask-eligible "$TEST_TMP/tasks-good" REV-TASKS > "$TEST_TMP/out" 2>&1 || rc=$?
if [[ "$rc" -eq 2 ]] && grep -F 'does not accept a REV-ID' "$TEST_TMP/out" >/dev/null; then
  PASS=$((PASS + 1)); echo "✓ retask-eligible rejects a REV-ID"
else
  FAIL=$((FAIL + 1)); echo "✗ retask-eligible REV-ID CLI boundary"; sed 's/^/    /' "$TEST_TMP/out"
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

grandfather_repo="$TEST_TMP/grandfather-repo"
grandfather_feature=$(init_feature_repo "$grandfather_repo")
strip_task_closure "$grandfather_feature/tasks.md"
write_pass_review "$grandfather_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review'
git -C "$grandfather_repo" add -- .
git -C "$grandfather_repo" commit -qm 'Legacy task review before Closure schema'
expect pass tasks-structure "$grandfather_feature" \
  "legacy tasks without Closure are grandfathered only by a current tracked clean PASS seal"
expect pass retask-eligible "$grandfather_feature" \
  "a valid legacy PASS handoff remains retask-eligible before implementation"

grandfather_archive_repo="$TEST_TMP/grandfather-canonical-retask-archive-repo"
git clone -q --local --no-hardlinks "$grandfather_repo" "$grandfather_archive_repo"
git -C "$grandfather_archive_repo" config user.name 'GateSpec Fixture'
git -C "$grandfather_archive_repo" config user.email 'fixture@example.invalid'
grandfather_archive_feature="$grandfather_archive_repo/specs/001-hot-reload"
grandfather_archive_root="$grandfather_archive_feature/.gatespec/archive/20260824T051500Z-retask"
mkdir -p "$grandfather_archive_root/reviews"
cp "$grandfather_archive_feature/tasks.md" "$grandfather_archive_root/tasks.md"
cp -R "$grandfather_archive_feature/.gatespec/reviews/REV-TASKS" \
  "$grandfather_archive_root/reviews/REV-TASKS"
git -C "$grandfather_archive_repo" add -- \
  specs/001-hot-reload/.gatespec/archive/20260824T051500Z-retask
git -C "$grandfather_archive_repo" commit -qm 'Record a canonical legacy retask archive'
rewrite "$grandfather_archive_feature/.gatespec/reviews/REV-TASKS/seal.md" \
  's/2026-08-18T12:00:00Z/2026-08-20T12:00:00Z/'
seal_self_hash "$grandfather_archive_feature/.gatespec/reviews/REV-TASKS/seal.md" \
  'Seal-SHA256'
git -C "$grandfather_archive_repo" add -- \
  specs/001-hot-reload/.gatespec/reviews/REV-TASKS/seal.md
git -C "$grandfather_archive_repo" commit -qm \
  'Refresh the current PASS seal after canonical archival'
expect pass tasks-structure "$grandfather_archive_feature" \
  "a canonical legacy retask archive preserves Closure grandfathering"
expect pass retask-eligible "$grandfather_archive_feature" \
  "a canonical legacy retask archive remains eligible for replacement"

for archive_hidden_bit in assume-unchanged skip-worktree; do
  archive_hidden_repo="$TEST_TMP/grandfather-retask-archive-hidden-$archive_hidden_bit"
  git clone -q --local --no-hardlinks "$grandfather_archive_repo" "$archive_hidden_repo"
  git -C "$archive_hidden_repo" config user.name 'GateSpec Fixture'
  git -C "$archive_hidden_repo" config user.email 'fixture@example.invalid'
  archive_hidden_feature="$archive_hidden_repo/specs/001-hot-reload"
  archive_hidden_review="$archive_hidden_feature/.gatespec/archive/20260824T051500Z-retask/reviews/REV-TASKS"
  archive_hidden_verdict="$archive_hidden_review/round-00-verdict.md"
  archive_hidden_seal="$archive_hidden_review/seal.md"
  old_archive_verdict_hash=$(receipt_field "$archive_hidden_verdict" 'Verdict-SHA256')
  rewrite "$archive_hidden_verdict" \
    "s/Receipt fixture is structurally valid/Archive receipt is internally coherent under $archive_hidden_bit/"
  seal_self_hash "$archive_hidden_verdict" 'Verdict-SHA256'
  new_archive_verdict_hash=$(receipt_field "$archive_hidden_verdict" 'Verdict-SHA256')
  rewrite "$archive_hidden_seal" \
    "s/$old_archive_verdict_hash/$new_archive_verdict_hash/"
  seal_self_hash "$archive_hidden_seal" 'Seal-SHA256'
  git -C "$archive_hidden_repo" update-index "--$archive_hidden_bit" -- \
    specs/001-hot-reload/.gatespec/archive/20260824T051500Z-retask/reviews/REV-TASKS/round-00-verdict.md \
    specs/001-hot-reload/.gatespec/archive/20260824T051500Z-retask/reviews/REV-TASKS/seal.md
  expect fail tasks-structure "$archive_hidden_feature" \
    "tasks structure rejects internally coherent archive receipt drift hidden by $archive_hidden_bit"
done

for archive_extra in product reviews-sibling; do
  archive_extra_repo="$TEST_TMP/grandfather-retask-archive-extra-$archive_extra"
  git clone -q --local --no-hardlinks "$grandfather_archive_repo" "$archive_extra_repo"
  git -C "$archive_extra_repo" config user.name 'GateSpec Fixture'
  git -C "$archive_extra_repo" config user.email 'fixture@example.invalid'
  archive_extra_feature="$archive_extra_repo/specs/001-hot-reload"
  archive_extra_root="$archive_extra_feature/.gatespec/archive/20260824T051500Z-retask"
  case "$archive_extra" in
    product)
      printf '%s\n' 'product content must never enter a retask archive' \
        > "$archive_extra_root/product.cc"
      archive_extra_date='2026-08-21T12:00:00Z'
      ;;
    reviews-sibling)
      mkdir -p "$archive_extra_root/reviews/REV-FOUNDATION"
      printf '%s\n' '# unexpected implementation review sibling' \
        > "$archive_extra_root/reviews/REV-FOUNDATION/round-00-request.md"
      archive_extra_date='2026-08-22T12:00:00Z'
      ;;
  esac
  git -C "$archive_extra_repo" add -- \
    specs/001-hot-reload/.gatespec/archive/20260824T051500Z-retask
  git -C "$archive_extra_repo" commit -qm \
    "Add forbidden $archive_extra content to the retask archive"
  rewrite "$archive_extra_feature/.gatespec/reviews/REV-TASKS/seal.md" \
    "s/2026-08-20T12:00:00Z/$archive_extra_date/"
  seal_self_hash "$archive_extra_feature/.gatespec/reviews/REV-TASKS/seal.md" \
    'Seal-SHA256'
  git -C "$archive_extra_repo" add -- \
    specs/001-hot-reload/.gatespec/reviews/REV-TASKS/seal.md
  git -C "$archive_extra_repo" commit -qm \
    "Refresh the PASS seal after forbidden $archive_extra archival"
  expect fail tasks-structure "$archive_extra_feature" \
    "tasks structure rejects a canonical retask archive plus $archive_extra content"
  expect fail retask-eligible "$archive_extra_feature" \
    "retask eligibility rejects a canonical archive plus $archive_extra content"
done

grandfather_bad_archive_repo="$TEST_TMP/grandfather-bad-retask-archive-repo"
git clone -q --local --no-hardlinks "$grandfather_repo" "$grandfather_bad_archive_repo"
git -C "$grandfather_bad_archive_repo" config user.name 'GateSpec Fixture'
git -C "$grandfather_bad_archive_repo" config user.email 'fixture@example.invalid'
grandfather_bad_archive_feature="$grandfather_bad_archive_repo/specs/001-hot-reload"
mkdir -p \
  "$grandfather_bad_archive_feature/.gatespec/archive/20260824T041500Z-retask"
cp "$grandfather_bad_archive_feature/tasks.md" \
  "$grandfather_bad_archive_feature/.gatespec/archive/20260824T041500Z-retask/tasks.md"
git -C "$grandfather_bad_archive_repo" add -- \
  specs/001-hot-reload/.gatespec/archive/20260824T041500Z-retask/tasks.md
git -C "$grandfather_bad_archive_repo" commit -qm \
  'Add an incomplete legacy retask archive'
rewrite "$grandfather_bad_archive_feature/.gatespec/reviews/REV-TASKS/seal.md" \
  's/2026-08-18T12:00:00Z/2026-08-19T12:00:00Z/'
seal_self_hash \
  "$grandfather_bad_archive_feature/.gatespec/reviews/REV-TASKS/seal.md" \
  'Seal-SHA256'
git -C "$grandfather_bad_archive_repo" add -- \
  specs/001-hot-reload/.gatespec/reviews/REV-TASKS/seal.md
git -C "$grandfather_bad_archive_repo" commit -qm \
  'Refresh the legacy PASS handoff after the archive commit'
expect fail retask-eligible "$grandfather_bad_archive_feature" \
  "legacy Closure grandfathering cannot hide a malformed retask archive"

pass_unknown_repo="$TEST_TMP/pass-unknown-receipt-repo"
pass_unknown_feature=$(init_feature_repo "$pass_unknown_repo")
strip_task_closure "$pass_unknown_feature/tasks.md"
write_pass_review "$pass_unknown_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review'
printf '%s\n' 'unknown receipt content' \
  > "$pass_unknown_feature/.gatespec/reviews/REV-TASKS/notes.md"
git -C "$pass_unknown_repo" add -- .
git -C "$pass_unknown_repo" commit -qm 'Seal task review with unknown receipt content'
expect fail retask-eligible "$pass_unknown_feature" \
  "sealed PASS review directories reject unknown or nested receipt content"

pass_product_repo="$TEST_TMP/pass-product-cocommit-repo"
pass_product_feature=$(init_feature_repo "$pass_product_repo")
strip_task_closure "$pass_product_feature/tasks.md"
write_pass_review "$pass_product_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review'
mkdir -p "$pass_product_repo/src"
printf '%s\n' 'product hidden in PASS baseline' > "$pass_product_repo/src/pass-product.txt"
git -C "$pass_product_repo" add -- .
git -C "$pass_product_repo" commit -qm 'Seal task review together with product work'
expect fail retask-eligible "$pass_product_feature" \
  "v1 PASS baseline commit cannot co-commit product work with the task seal"

pass_prior_product_repo="$TEST_TMP/pass-prior-product-repo"
pass_prior_product_feature=$(init_feature_repo "$pass_prior_product_repo")
strip_task_closure "$pass_prior_product_feature/tasks.md"
git -C "$pass_prior_product_repo" add -- .
git -C "$pass_prior_product_repo" commit -qm 'Record native tasks before review'
mkdir -p "$pass_prior_product_repo/src"
printf '%s\n' 'product committed before the PASS seal' \
  > "$pass_prior_product_repo/src/pre-seal-product.txt"
git -C "$pass_prior_product_repo" add -- src/pre-seal-product.txt
git -C "$pass_prior_product_repo" commit -qm 'Begin product work before task review'
write_pass_review "$pass_prior_product_feature" REV-TASKS TASKS \
  not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review'
git -C "$pass_prior_product_repo" add -- \
  specs/001-hot-reload/.gatespec/reviews/REV-TASKS
git -C "$pass_prior_product_repo" commit -qm 'Seal task review after product work'
expect fail retask-eligible "$pass_prior_product_feature" \
  "v1 PASS eligibility rejects product work committed before the final seal commit"

hidden_product_base_repo="$TEST_TMP/pass-hidden-product-base-repo"
hidden_product_base_feature=$(init_feature_repo "$hidden_product_base_repo")
mkdir -p "$hidden_product_base_repo/src"
printf '%s\n' 'pre-existing product baseline' \
  > "$hidden_product_base_repo/src/existing-product.cc"
git -C "$hidden_product_base_repo" add -- src/existing-product.cc
git -C "$hidden_product_base_repo" commit -qm 'Record pre-existing product baseline'
write_pass_review "$hidden_product_base_feature" REV-TASKS TASKS \
  not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review'
git -C "$hidden_product_base_repo" add -- specs/001-hot-reload
git -C "$hidden_product_base_repo" commit -qm \
  'Seal a valid task review after the product baseline'
expect pass retask-eligible "$hidden_product_base_feature" \
  "v1 PASS permits an unchanged product path that predates the first Plan boundary"
for hidden_product_bit in assume-unchanged skip-worktree; do
  hidden_product_repo="$TEST_TMP/pass-hidden-product-$hidden_product_bit"
  git clone -q --local --no-hardlinks "$hidden_product_base_repo" "$hidden_product_repo"
  git -C "$hidden_product_repo" config user.name 'GateSpec Fixture'
  git -C "$hidden_product_repo" config user.email 'fixture@example.invalid'
  hidden_product_feature="$hidden_product_repo/specs/001-hot-reload"
  git -C "$hidden_product_repo" update-index "--$hidden_product_bit" -- \
    src/existing-product.cc
  printf '%s\n' 'product implementation changed after task review' \
    > "$hidden_product_repo/src/existing-product.cc"
  expect fail retask-eligible "$hidden_product_feature" \
    "v1 PASS rejects tracked product drift hidden by $hidden_product_bit"
done

printf '%s\n' 'dirty grandfather state' > "$grandfather_repo/untracked.txt"
expect fail tasks-structure "$grandfather_feature" \
  "dirty state cannot grandfather tasks that omit Closure"
mv "$grandfather_repo/untracked.txt" "$TEST_TMP/grandfather-untracked.txt"

grandfather_malformed_repo="$TEST_TMP/grandfather-malformed-repo"
grandfather_malformed_feature=$(init_feature_repo "$grandfather_malformed_repo")
rewrite "$grandfather_malformed_feature/tasks.md" 's/| Contract refs |/| Contract references |/'
write_pass_review "$grandfather_malformed_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review'
git -C "$grandfather_malformed_repo" add -- .
git -C "$grandfather_malformed_repo" commit -qm 'Malformed Closure with current PASS receipt'
expect fail tasks-structure "$grandfather_malformed_feature" \
  "a PASS seal cannot grandfather partial or malformed Closure"
expect fail retask-eligible "$grandfather_malformed_feature" \
  "retask eligibility rejects malformed Closure even with a current PASS seal"

grandfather_partial_repo="$TEST_TMP/grandfather-partial-repo"
grandfather_partial_feature=$(init_feature_repo "$grandfather_partial_repo")
strip_prior_closure "$grandfather_partial_feature/tasks.md"
write_pass_review "$grandfather_partial_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review'
git -C "$grandfather_partial_repo" add -- .
git -C "$grandfather_partial_repo" commit -qm 'Partial Closure with current PASS receipt'
expect fail retask-eligible "$grandfather_partial_feature" \
  "retask eligibility never grandfathers exactly one Closure section"

grandfather_indented_repo="$TEST_TMP/grandfather-indented-closure-repo"
grandfather_indented_feature=$(init_feature_repo "$grandfather_indented_repo")
rewrite "$grandfather_indented_feature/tasks.md" \
  's/^## GateSpec Checkpoint Closure/ ## GateSpec Checkpoint Closure/'
write_pass_review "$grandfather_indented_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review'
git -C "$grandfather_indented_repo" add -- .
git -C "$grandfather_indented_repo" commit -qm 'Seal tasks with an indented malformed Closure heading'
expect fail retask-eligible "$grandfather_indented_feature" \
  "indented malformed Closure headings cannot enter the legacy-absent path"

retask_round_repo="$TEST_TMP/retask-round02-repo"
retask_round_feature=$(init_feature_repo "$retask_round_repo")
git -C "$retask_round_repo" add -- .
git -C "$retask_round_repo" commit -qm 'Pre-review native task handoff'
write_pass_review "$retask_round_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- Fixture limitation.' 00 none BLOCKED
retask_round00_hash=$(receipt_field \
  "$retask_round_feature/.gatespec/reviews/REV-TASKS/round-00-verdict.md" 'Verdict-SHA256')
retask_finding=$(blocker_digest '- BLOCKER: fixture remediation required')
rewrite "$retask_round_feature/tasks.md" 's/Create the feature scaffolding/Create the reviewed feature scaffolding/'
set_prior_finding "$retask_round_feature/tasks.md" "$retask_finding" \
  '.gatespec/reviews/REV-TASKS/round-00-verdict.md#B01' REV-FOUNDATION T001
write_pass_review "$retask_round_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- Fixture limitation.' 01 "$retask_round00_hash" BLOCKED
retask_round01_hash=$(receipt_field \
  "$retask_round_feature/.gatespec/reviews/REV-TASKS/round-01-verdict.md" 'Verdict-SHA256')
rewrite "$retask_round_feature/tasks.md" 's/Implement the configuration store/Implement and verify the configuration store/'
append_prior_finding "$retask_round_feature/tasks.md" \
  '.gatespec/reviews/REV-TASKS/round-00-verdict.md#B01' "$retask_finding" \
  '.gatespec/reviews/REV-TASKS/round-01-verdict.md#B01' REV-FOUNDATION T002
write_pass_review "$retask_round_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- Fixture limitation.' 02 "$retask_round01_hash" BLOCKED
git -C "$retask_round_repo" add -- .
git -C "$retask_round_repo" commit -qm 'Exhaust REV-TASKS remediation rounds'
expect pass retask-eligible "$retask_round_feature" \
  "a complete valid round-02 BLOCKED chain without a seal is retask-eligible"

retask_checked_restored_repo="$TEST_TMP/retask-checked-then-restored-repo"
git clone -q --local --no-hardlinks "$retask_round_repo" "$retask_checked_restored_repo"
git -C "$retask_checked_restored_repo" config user.name 'GateSpec Fixture'
git -C "$retask_checked_restored_repo" config user.email 'fixture@example.invalid'
retask_checked_restored_feature="$retask_checked_restored_repo/specs/001-hot-reload"
rewrite "$retask_checked_restored_feature/tasks.md" 's/^- \[ \] T001/- [x] T001/'
git -C "$retask_checked_restored_repo" add -- specs/001-hot-reload/tasks.md
git -C "$retask_checked_restored_repo" commit -qm 'Temporarily complete a product task'
rewrite "$retask_checked_restored_feature/tasks.md" 's/^- \[x\] T001/- [ ] T001/'
git -C "$retask_checked_restored_repo" add -- specs/001-hot-reload/tasks.md
git -C "$retask_checked_restored_repo" commit -qm 'Restore the task checkbox before retask'
expect fail retask-eligible "$retask_checked_restored_feature" \
  "retask rejects implementation progress even when a checked task was later restored"

for hidden_index_bit in assume-unchanged skip-worktree; do
  hidden_source_repo="$TEST_TMP/retask-hidden-source-$hidden_index_bit"
  git clone -q --local --no-hardlinks "$retask_round_repo" "$hidden_source_repo"
  git -C "$hidden_source_repo" config user.name 'GateSpec Fixture'
  git -C "$hidden_source_repo" config user.email 'fixture@example.invalid'
  hidden_source_feature="$hidden_source_repo/specs/001-hot-reload"
  hidden_request="$hidden_source_feature/.gatespec/reviews/REV-TASKS/round-02-request.md"
  hidden_verdict="$hidden_source_feature/.gatespec/reviews/REV-TASKS/round-02-verdict.md"
  old_hidden_tasks_hash=$(receipt_field "$hidden_request" 'Tasks-Definition-SHA256')
  old_hidden_request_hash=$(receipt_field "$hidden_request" 'Request-SHA256')
  rewrite "$hidden_source_feature/tasks.md" \
    's/Implement and verify the configuration store/Implement and independently verify the configuration store/'
  new_hidden_tasks_hash=$(normalized_tasks_digest "$hidden_source_feature/tasks.md")
  rewrite "$hidden_request" "s/$old_hidden_tasks_hash/$new_hidden_tasks_hash/"
  seal_self_hash "$hidden_request" 'Request-SHA256'
  new_hidden_request_hash=$(receipt_field "$hidden_request" 'Request-SHA256')
  rewrite "$hidden_verdict" "s/$old_hidden_request_hash/$new_hidden_request_hash/"
  seal_self_hash "$hidden_verdict" 'Verdict-SHA256'
  git -C "$hidden_source_repo" update-index "--$hidden_index_bit" -- \
    specs/001-hot-reload/tasks.md \
    specs/001-hot-reload/.gatespec/reviews/REV-TASKS/round-02-request.md \
    specs/001-hot-reload/.gatespec/reviews/REV-TASKS/round-02-verdict.md
  expect fail retask-eligible "$hidden_source_feature" \
    "retask rejects archive-source drift hidden by $hidden_index_bit"
done

for hidden_clean_source_bit in assume-unchanged skip-worktree; do
  hidden_clean_source_repo="$TEST_TMP/retask-hidden-clean-source-$hidden_clean_source_bit"
  git clone -q --local --no-hardlinks "$retask_round_repo" "$hidden_clean_source_repo"
  git -C "$hidden_clean_source_repo" config user.name 'GateSpec Fixture'
  git -C "$hidden_clean_source_repo" config user.email 'fixture@example.invalid'
  hidden_clean_source_feature="$hidden_clean_source_repo/specs/001-hot-reload"
  git -C "$hidden_clean_source_repo" update-index "--$hidden_clean_source_bit" -- \
    specs/001-hot-reload/tasks.md
  expect fail retask-eligible "$hidden_clean_source_feature" \
    "retask rejects a byte-clean tasks archive source marked $hidden_clean_source_bit"
done

make_untracked_retask_chain() {
  local feature="$1" round00_hash round01_hash finding
  write_pass_review "$feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
    '- Not run — task-plan review' '- Not run — task-plan review' '- Fixture limitation.' 00 none BLOCKED
  round00_hash=$(receipt_field \
    "$feature/.gatespec/reviews/REV-TASKS/round-00-verdict.md" 'Verdict-SHA256')
  finding=$(blocker_digest '- BLOCKER: fixture remediation required')
  rewrite "$feature/tasks.md" 's/Create the feature scaffolding/Create untracked-cycle scaffolding/'
  set_prior_finding "$feature/tasks.md" "$finding" \
    '.gatespec/reviews/REV-TASKS/round-00-verdict.md#B01' REV-FOUNDATION T001
  write_pass_review "$feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
    '- Not run — task-plan review' '- Not run — task-plan review' '- Fixture limitation.' 01 "$round00_hash" BLOCKED
  round01_hash=$(receipt_field \
    "$feature/.gatespec/reviews/REV-TASKS/round-01-verdict.md" 'Verdict-SHA256')
  rewrite "$feature/tasks.md" 's/Implement the configuration store/Implement untracked-cycle verification/'
  append_prior_finding "$feature/tasks.md" \
    '.gatespec/reviews/REV-TASKS/round-00-verdict.md#B01' "$finding" \
    '.gatespec/reviews/REV-TASKS/round-01-verdict.md#B01' REV-FOUNDATION T002
  write_pass_review "$feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
    '- Not run — task-plan review' '- Not run — task-plan review' '- Fixture limitation.' 02 "$round01_hash" BLOCKED
}

retask_untracked_repo="$TEST_TMP/retask-untracked-chain-repo"
retask_untracked_feature=$(init_feature_repo "$retask_untracked_repo")
git -C "$retask_untracked_repo" commit --allow-empty -qm 'Repository baseline'
git -C "$retask_untracked_repo" add -- \
  specs/001-hot-reload/spec.md specs/001-hot-reload/plan.md
git -C "$retask_untracked_repo" commit -qm 'Approve current plan'
make_untracked_retask_chain "$retask_untracked_feature"
expect pass retask-eligible "$retask_untracked_feature" \
  "v1 wholly untracked task-review chain uses the parent of its exact Plan commit"

retask_ignored_repo="$TEST_TMP/retask-ignored-untracked-chain-repo"
cp -R "$retask_untracked_repo" "$retask_ignored_repo"
retask_ignored_feature="$retask_ignored_repo/specs/001-hot-reload"
printf '%s\n' 'specs/001-hot-reload/tasks.md' >> "$retask_ignored_repo/.git/info/exclude"
expect fail retask-eligible "$retask_ignored_feature" \
  "wholly untracked retask archive sources must not be hidden by ignore rules"

retask_symlink_repo="$TEST_TMP/retask-symlink-source-repo"
cp -R "$retask_untracked_repo" "$retask_symlink_repo"
retask_symlink_feature="$retask_symlink_repo/specs/001-hot-reload"
mv "$retask_symlink_feature/tasks.md" "$TEST_TMP/retask-symlink-target-tasks.md"
ln -s "$TEST_TMP/retask-symlink-target-tasks.md" "$retask_symlink_feature/tasks.md"
expect fail retask-eligible "$retask_symlink_feature" \
  "retask rejects a symlinked tasks archive source"

retask_untracked_product_repo="$TEST_TMP/retask-untracked-plan-product-repo"
retask_untracked_product_feature=$(init_feature_repo "$retask_untracked_product_repo")
git -C "$retask_untracked_product_repo" commit --allow-empty -qm 'Repository baseline'
mkdir -p "$retask_untracked_product_repo/src"
printf '%s\n' 'product work hidden in plan commit' \
  > "$retask_untracked_product_repo/src/plan-product.txt"
git -C "$retask_untracked_product_repo" add -- \
  specs/001-hot-reload/spec.md specs/001-hot-reload/plan.md src/plan-product.txt
git -C "$retask_untracked_product_repo" commit -qm 'Approve plan with forbidden product delta'
make_untracked_retask_chain "$retask_untracked_product_feature"
expect fail retask-eligible "$retask_untracked_product_feature" \
  "v1 wholly untracked fallback inspects the Plan commit itself for product paths"

retask_parent_product_repo="$TEST_TMP/retask-round00-parent-product-repo"
retask_parent_product_feature=$(init_feature_repo "$retask_parent_product_repo")
git -C "$retask_parent_product_repo" add -- .
git -C "$retask_parent_product_repo" commit -qm 'Record native tasks before review'
mkdir -p "$retask_parent_product_repo/src"
printf '%s\n' 'product committed in the parent of the first review request' \
  > "$retask_parent_product_repo/src/pre-round00-product.txt"
git -C "$retask_parent_product_repo" add -- src/pre-round00-product.txt
git -C "$retask_parent_product_repo" commit -qm \
  'Begin product work before REV-TASKS round 00'
make_untracked_retask_chain "$retask_parent_product_feature"
git -C "$retask_parent_product_repo" add -- \
  specs/001-hot-reload/tasks.md \
  specs/001-hot-reload/.gatespec/reviews/REV-TASKS
git -C "$retask_parent_product_repo" commit -qm \
  'Exhaust task-review rounds after product work'
expect fail retask-eligible "$retask_parent_product_feature" \
  "v1 BLOCKED eligibility inspects the parent commit of first-added round 00"

retask_dirty_repo="$TEST_TMP/retask-allowed-dirt-repo"
retask_dirty_feature=$(init_feature_repo "$retask_dirty_repo")
git -C "$retask_dirty_repo" add -- .
git -C "$retask_dirty_repo" commit -qm 'Pre-review native task handoff'
write_pass_review "$retask_dirty_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- Fixture limitation.' 00 none BLOCKED
retask_dirty00_hash=$(receipt_field \
  "$retask_dirty_feature/.gatespec/reviews/REV-TASKS/round-00-verdict.md" 'Verdict-SHA256')
git -C "$retask_dirty_repo" add -- .
git -C "$retask_dirty_repo" commit -qm 'Record REV-TASKS round 00 finding'
rewrite "$retask_dirty_feature/tasks.md" 's/Create the feature scaffolding/Create dirty-cycle scaffolding/'
set_prior_finding "$retask_dirty_feature/tasks.md" "$retask_finding" \
  '.gatespec/reviews/REV-TASKS/round-00-verdict.md#B01' REV-FOUNDATION T001
write_pass_review "$retask_dirty_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- Fixture limitation.' 01 "$retask_dirty00_hash" BLOCKED
retask_dirty01_hash=$(receipt_field \
  "$retask_dirty_feature/.gatespec/reviews/REV-TASKS/round-01-verdict.md" 'Verdict-SHA256')
git -C "$retask_dirty_repo" add -- .
git -C "$retask_dirty_repo" commit -qm 'Record REV-TASKS round 01 finding'
rewrite "$retask_dirty_feature/tasks.md" 's/Implement the configuration store/Implement dirty-cycle verification/'
append_prior_finding "$retask_dirty_feature/tasks.md" \
  '.gatespec/reviews/REV-TASKS/round-00-verdict.md#B01' "$retask_finding" \
  '.gatespec/reviews/REV-TASKS/round-01-verdict.md#B01' REV-FOUNDATION T002
write_pass_review "$retask_dirty_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- Fixture limitation.' 02 "$retask_dirty01_hash" BLOCKED
git -C "$retask_dirty_repo" add -- \
  specs/001-hot-reload/tasks.md \
  specs/001-hot-reload/.gatespec/reviews/REV-TASKS/round-02-request.md \
  specs/001-hot-reload/.gatespec/reviews/REV-TASKS/round-02-verdict.md
expect pass retask-eligible "$retask_dirty_feature" \
  "retask permits staged tasks and REV-TASKS dirt when index and working bytes are identical"

retask_mm_repo="$TEST_TMP/retask-mm-snapshot-repo"
cp -R "$retask_dirty_repo" "$retask_mm_repo"
retask_mm_feature="$retask_mm_repo/specs/001-hot-reload"
printf '%s\n' '' >> "$retask_mm_feature/tasks.md"
expect fail retask-eligible "$retask_mm_feature" \
  "retask rejects MM tasks state whose index and working snapshots differ"

retask_am_repo="$TEST_TMP/retask-am-snapshot-repo"
cp -R "$retask_dirty_repo" "$retask_am_repo"
retask_am_feature="$retask_am_repo/specs/001-hot-reload"
printf '%s\n' '' >> \
  "$retask_am_feature/.gatespec/reviews/REV-TASKS/round-02-verdict.md"
expect fail retask-eligible "$retask_am_feature" \
  "retask rejects AM receipt state whose index and working snapshots differ"

retask_round01_repo="$TEST_TMP/retask-round01-repo"
retask_round01_feature=$(init_feature_repo "$retask_round01_repo")
git -C "$retask_round01_repo" add -- .
git -C "$retask_round01_repo" commit -qm 'Pre-review native task handoff'
write_pass_review "$retask_round01_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- Fixture limitation.' 00 none BLOCKED
retask_short00_hash=$(receipt_field \
  "$retask_round01_feature/.gatespec/reviews/REV-TASKS/round-00-verdict.md" 'Verdict-SHA256')
rewrite "$retask_round01_feature/tasks.md" 's/Create the feature scaffolding/Create revised scaffolding/'
write_pass_review "$retask_round01_feature" REV-TASKS TASKS not-applicable not-applicable not-applicable none \
  '- Not run — task-plan review' '- Not run — task-plan review' '- Fixture limitation.' 01 "$retask_short00_hash" BLOCKED
git -C "$retask_round01_repo" add -- .
git -C "$retask_round01_repo" commit -qm 'Stop at REV-TASKS round 01'
expect fail retask-eligible "$retask_round01_feature" \
  "round-00 and round-01 BLOCKED task reviews are not retask-eligible"

for retask_variant in checked impl-receipt acceptance ia product product-inside invalid orphan stale task-drift missing-prior; do
  retask_variant_repo="$TEST_TMP/retask-$retask_variant"
  git clone -q --local --no-hardlinks "$retask_round_repo" "$retask_variant_repo"
  git -C "$retask_variant_repo" config user.name 'GateSpec Fixture'
  git -C "$retask_variant_repo" config user.email 'fixture@example.invalid'
  retask_variant_feature="$retask_variant_repo/specs/001-hot-reload"
  case "$retask_variant" in
    checked)
      rewrite "$retask_variant_feature/tasks.md" 's/^- \[ \] T001/- [x] T001/'
      ;;
    impl-receipt)
      mkdir -p "$retask_variant_feature/.gatespec/reviews/REV-FOUNDATION"
      printf '%s\n' '# implementation review started' \
        > "$retask_variant_feature/.gatespec/reviews/REV-FOUNDATION/round-00-request.md"
      ;;
    acceptance)
      printf '%s\n' '# GateSpec Implementation Acceptance' \
        > "$retask_variant_feature/.gatespec/acceptance.md"
      ;;
    ia)
      printf '%s\n' '# GateSpec Implementation Adjustments' '## Adjustments' '- IA1: already changed' \
        > "$retask_variant_feature/.gatespec/implementation-adjustments.md"
      ;;
    product)
      mkdir -p "$retask_variant_repo/src"
      printf '%s\n' 'product implementation began' > "$retask_variant_repo/src/product.txt"
      ;;
    product-inside)
      printf '%s\n' 'product implementation hidden in feature evidence' \
        > "$retask_variant_feature/product.cc"
      ;;
    invalid)
      rewrite "$retask_variant_feature/.gatespec/reviews/REV-TASKS/round-02-verdict.md" \
        's/fixture-REV-TASKS-02/tampered-context/'
      ;;
    orphan)
      mv "$retask_variant_feature/.gatespec/reviews/REV-TASKS/round-01-request.md" \
        "$TEST_TMP/orphan-round-01-request.md"
      ;;
    stale)
      rewrite "$retask_variant_feature/plan.md" \
        's/Add portable polling and atomic snapshot replacement/Add portable polling with a revised handoff/'
      seal "$retask_variant_feature/plan.md"
      ;;
    task-drift)
      rewrite "$retask_variant_feature/tasks.md" \
        's/Implement and verify the configuration store/Implement a drifted unchecked configuration store/'
      ;;
    missing-prior)
      remove_prior_source "$retask_variant_feature/tasks.md" \
        '.gatespec/reviews/REV-TASKS/round-00-verdict.md#B01'
      ;;
  esac
  git -C "$retask_variant_repo" add -- .
  git -C "$retask_variant_repo" commit -qm "Make retask ineligible: $retask_variant"
  expect fail retask-eligible "$retask_variant_feature" \
    "retask rejects $retask_variant state"
done

retask_transient_repo="$TEST_TMP/retask-transient-product-repo"
git clone -q --local --no-hardlinks "$retask_round_repo" "$retask_transient_repo"
git -C "$retask_transient_repo" config user.name 'GateSpec Fixture'
git -C "$retask_transient_repo" config user.email 'fixture@example.invalid'
retask_transient_feature="$retask_transient_repo/specs/001-hot-reload"
mkdir -p "$retask_transient_repo/src"
printf '%s\n' 'transient product implementation' > "$retask_transient_repo/src/transient.txt"
git -C "$retask_transient_repo" add -- src/transient.txt
git -C "$retask_transient_repo" commit -qm 'Temporarily add product implementation'
git -C "$retask_transient_repo" rm -q -- src/transient.txt
git -C "$retask_transient_repo" commit -qm 'Delete transient product implementation'
expect fail retask-eligible "$retask_transient_feature" \
  "retask inspects the union of committed paths even when product work is later deleted"

retask_detached_repo="$TEST_TMP/retask-detached"
git clone -q --local --no-hardlinks "$retask_round_repo" "$retask_detached_repo"
retask_detached_feature="$retask_detached_repo/specs/001-hot-reload"
git -C "$retask_detached_repo" checkout -q --detach
expect fail retask-eligible "$retask_detached_feature" "retask rejects detached HEAD"

rewrite "$grandfather_feature/tasks.md" 's/^- \[ \] T001/- [x] T001/'
git -C "$grandfather_repo" add -- specs/001-hot-reload/tasks.md
git -C "$grandfather_repo" commit -qm 'Begin implementation after PASS handoff'
expect fail retask-eligible "$grandfather_feature" \
  "a valid PASS handoff stops being retask-eligible after any task is checked"

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
task_round_finding=$(blocker_digest '- BLOCKER: fixture remediation required')
set_prior_finding "$task_round_feature/tasks.md" "$task_round_finding" \
  '.gatespec/reviews/REV-TASKS/round-00-verdict.md#B01' REV-FOUNDATION T001
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

legacy_acceptance_repo="$TEST_TMP/legacy-acceptance-repo"
git clone -q "$implementation_repo" "$legacy_acceptance_repo"
git -C "$legacy_acceptance_repo" config user.name 'GateSpec Fixture'
git -C "$legacy_acceptance_repo" config user.email 'fixture@example.invalid'
legacy_acceptance_feature="$legacy_acceptance_repo/specs/001-hot-reload"
legacy_final_review_commit=$(git -C "$legacy_acceptance_repo" rev-parse HEAD)
legacy_final_delta=$(final_delta_digest "$legacy_acceptance_repo" "$implementation_baseline" "$final_subject")
legacy_acceptance="$legacy_acceptance_feature/.gatespec/acceptance.md"
cat > "$legacy_acceptance" <<EOF
# GateSpec Implementation Acceptance

- **Protocol-Version**: \`1\`
- **Status**: \`Accepted\`
- **Accepted-At**: \`2026-08-24T12:00:00Z\`
- **Spec-Content-SHA256**: \`$(hash_of "$legacy_acceptance_feature/spec.md")\`
- **Plan-Content-SHA256**: \`$(hash_of "$legacy_acceptance_feature/plan.md")\`
- **Design-Attachments-SHA256**: \`$(attachments_digest "$legacy_acceptance_feature")\`
- **Tasks-Definition-SHA256**: \`$(normalized_tasks_digest "$legacy_acceptance_feature/tasks.md")\`
- **Execution-Epoch**: \`not-applicable\`
- **Source-Design-Content-SHA256**: \`not-applicable\`
- **Implementation-Adjustments-SHA256**: \`not-applicable\`
- **Original-Implementation-Baseline**: \`$implementation_baseline\`
- **Final-Subject-Commit**: \`$final_subject\`
- **REV-FINAL-Seal-SHA256**: \`$(receipt_field "$legacy_acceptance_feature/.gatespec/reviews/REV-FINAL/seal.md" 'Seal-SHA256')\`
- **Final-Review-Commit**: \`$legacy_final_review_commit\`
- **Final-Delta-SHA256**: \`$legacy_final_delta\`
- **Acceptance-SHA256**: \`pending\`
EOF
seal_self_hash "$legacy_acceptance" 'Acceptance-SHA256'
git -C "$legacy_acceptance_repo" add -- specs/001-hot-reload/.gatespec/acceptance.md
git -C "$legacy_acceptance_repo" commit -qm 'Accept final GateSpec implementation'
expect pass acceptance "$legacy_acceptance_feature" "legacy Protocol v1 also requires and validates final acceptance"

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
