#!/usr/bin/env bash
# Fixture tests for check-gate.sh. Run from repo root: bash tests/run-tests.sh
set -u
cd "$(dirname "$0")/.."
SCRIPT="scripts/bash/check-gate.sh"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
PASS=0; FAIL=0

expect() { # expect <pass|fail> <mode> <dir> <label>
  local want="$1" mode="$2" dir="$3" label="$4"
  if bash "$SCRIPT" "$mode" "$dir" >"$TMP/out" 2>&1; then got=pass; else got=fail; fi
  if [[ "$got" == "$want" ]]; then
    PASS=$((PASS+1)); echo "✓ $label"
  else
    FAIL=$((FAIL+1)); echo "✗ $label (wanted $want, got $got)"; sed 's/^/    /' "$TMP/out"
  fi
}

hash_of() { sed '/^## Gate Approval/,$d' "$1" | sha256sum | cut -d' ' -f1; }
seal() { # seal <file> — fill in the approval hash placeholder
  sed -i "s/__HASH__/$(hash_of "$1")/" "$1"
}

mk() { mkdir -p "$TMP/$1"; }

# --- Fixture 1: auto-track spec (no marker) → silent pass --------------------
mk auto-track
cat > "$TMP/auto-track/spec.md" <<'EOF'
# Feature Specification: Plain upstream spec
**Status**: Draft
## User Scenarios & Testing
### User Story 1 - X (Priority: P1)
## Requirements
### Functional Requirements
- **FR-001**: System MUST do X (covers FR-001)
## Success Criteria
- **SC-001**: X works
EOF
expect pass spec   "$TMP/auto-track" "auto-track spec: spec gate skips silently"
expect pass design "$TMP/auto-track" "auto-track spec: design gate skips silently"

# --- Fixture 2: fully approved gatespec spec + plan → both pass --------------
mk good
cat > "$TMP/good/spec.md" <<'EOF'
<!-- path: gatespec -->
# Feature Specification: Config hot reload
**Status**: Approved-Requirements (2026-08-07)
## Clarifications
### Session 2026-08-07
- Q: Reload scope? → A: values only, keep connections
## Approved Defaults
| # | Item | Approved Default | Approved |
|---|------|------------------|----------|
| 1 | Watch mechanism | mtime polling | ✅ 2026-08-07 |
## User Scenarios & Testing
### User Story 1 - Hot reload (Priority: P1)
**Acceptance Scenarios**:
1. **Given** daemon running, **When** config saved, **Then** reloaded in 1s (covers FR-001)
## Requirements
### Functional Requirements
- **FR-001**: System MUST reload config without dropping connections
## Success Criteria
### Measurable Outcomes
- **SC-001**: Reload takes effect within 1 second
## Assumptions
- Single-node deployment
## Gate Approval
- **Approved by user**: 2026-08-07
- **Content-SHA256**: `__HASH__`
EOF
seal "$TMP/good/spec.md"

cat > "$TMP/good/plan.md" <<'EOF'
# Implementation Plan: Config hot reload
**Status**: Approved-Design (2026-08-07)
## Summary
Add mtime-polling hot reload.
## Technical Context
**Language/Version**: C++20
## Constitution Check
No violations.
## Decision Log
### D1: Watch mechanism
- **Context**: need file change detection
- **Options**: A. mtime polling — simple, no deps; B. inotify — fast but linux-only
- **Recommendation**: A — portability
- **Approved**: A (2026-08-07)
## Design Detailing
1. **Thread / concurrency model**: watcher thread owns polling; main thread consumes via atomic swap
2. **Object lifetimes & ownership**: Config held in shared_ptr, readers take snapshot copies
3. **Key modules & classes**: ConfigWatcher, ConfigStore
4. **Key internal APIs & interactions**: ConfigStore::swap() called from watcher callback
5. **External interface behavior contracts**: CLI flag --watch; invalid config rejected with log line
6. **Setup / runtime / teardown phase interactions**: setup loads once; runtime reloads; teardown joins watcher
## Project Structure
### Documentation (this feature)
### Source Code (repository root)
src/
## Complexity Tracking
None.
## Gate Approval
- **Approved by user**: 2026-08-07
- **Content-SHA256**: `__HASH__`
EOF
seal "$TMP/good/plan.md"
expect pass spec   "$TMP/good" "approved spec: spec gate passes"
expect pass design "$TMP/good" "approved spec+plan: design gate passes"

# --- Fixture 3: residual clarification → fail --------------------------------
mk residual
sed 's/values only, keep connections/[NEEDS CLARIFICATION: scope?]/' "$TMP/good/spec.md" > "$TMP/residual/spec.md"
seal "$TMP/residual/spec.md"
expect fail spec "$TMP/residual" "residual NEEDS CLARIFICATION: fails"

# --- Fixture 4: unapproved default row → fail --------------------------------
mk unapproved
sed 's/✅ 2026-08-07/ /' "$TMP/good/spec.md" > "$TMP/unapproved/spec.md"
seal "$TMP/unapproved/spec.md"
expect fail spec "$TMP/unapproved" "unapproved default row: fails"

# --- Fixture 5: post-approval drift → fail ------------------------------------
mk drift
cp "$TMP/good/spec.md" "$TMP/drift/spec.md"
sed -i 's/reload config without dropping connections/reload config, connections may drop/' "$TMP/drift/spec.md"
expect fail spec "$TMP/drift" "content drift after approval: fails"

# --- Fixture 6: FR without scenario reference → fail --------------------------
mk orphanfr
sed 's/ (covers FR-001)//' "$TMP/good/spec.md" > "$TMP/orphanfr/spec.md"
seal "$TMP/orphanfr/spec.md"
expect fail spec "$TMP/orphanfr" "orphan FR (no scenario ref): fails"

# --- Fixture 7: unapproved design decision → fail ------------------------------
mk undecided
cp "$TMP/good/spec.md" "$TMP/undecided/spec.md"
sed 's/- \*\*Approved\*\*: A (2026-08-07)/- **Approved**: /' "$TMP/good/plan.md" > "$TMP/undecided/plan.md"
seal "$TMP/undecided/plan.md"
expect fail design "$TMP/undecided" "unapproved decision: fails"

# --- Fixture 8: missing design dimension → fail --------------------------------
mk dim
cp "$TMP/good/spec.md" "$TMP/dim/spec.md"
grep -v 'teardown phase interactions' "$TMP/good/plan.md" > "$TMP/dim/plan.md"
seal "$TMP/dim/plan.md"
expect fail design "$TMP/dim" "missing 6th design dimension: fails"

echo ""
echo "==> $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
