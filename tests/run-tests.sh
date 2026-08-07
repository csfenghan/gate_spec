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

# Canonical valid artifacts --------------------------------------------------
mkdir -p "$TEST_TMP/good"
cat > "$TEST_TMP/good/spec.md" <<'EOF'
<!-- path: gatespec -->
# Feature Specification: Config hot reload
**Status**: Approved-Requirements (2026-08-07)
## Clarifications
### Session 2026-08-07
- Q: What reload scope is required? → A: Replace values without dropping connections.
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

# Track marker and feature resolution ---------------------------------------
mkdir -p "$TEST_TMP/auto"
printf '# Upstream spec\n**Status**: Draft\n' > "$TEST_TMP/auto/spec.md"
expect_silent spec "$TEST_TMP/auto" "unmarked auto-track requirements are truly silent"
expect_silent design "$TEST_TMP/auto" "unmarked auto-track design is truly silent"

clone_good displaced-marker
rewrite "$TEST_TMP/displaced-marker/spec.md" '1{h;d;};2{G;}'
expect fail spec "$TEST_TMP/displaced-marker" "marker on a later line fails" "not line 1"

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

echo ''
echo "==> checker fixtures: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
