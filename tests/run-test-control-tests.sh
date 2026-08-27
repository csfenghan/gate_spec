#!/usr/bin/env bash
# Protocol v3 Test Control Closure and structural counterexamples.
# shellcheck disable=SC2016 # Fixture Markdown uses literal backticks.

set -u
cd "$(dirname "$0")/.." || exit 1
SCRIPT="$PWD/scripts/bash/check-gate.sh"
TEST_TMP=$(mktemp -d "${TMPDIR:-/tmp}/gatespec-test-controls.XXXXXX") || exit 1
trap 'rm -rf "$TEST_TMP"' EXIT HUP INT TERM
PASS=0
FAIL=0

sha_stream() {
  if command -v sha256sum >/dev/null 2>&1; then sha256sum; else shasum -a 256; fi
}

content_hash() { sed '/^## Gate Approval/,$d' "$1" | sha_stream | awk '{print $1}'; }

seal_gate() {
  local file="$1" digest tmp="$1.tmp"
  digest=$(content_hash "$file")
  awk -v digest="$digest" '
    /^- \*\*Content-SHA256\*\*:/ {print "- **Content-SHA256**: `" digest "`"; next}
    {print}
  ' "$file" > "$tmp" && mv "$tmp" "$file"
}

sync_plan_basis() {
  local feature="$1" digest tmp
  tmp="$feature/plan.md.tmp"
  digest=$(content_hash "$feature/spec.md")
  awk -v digest="$digest" '
    /^\*\*Requirements Content-SHA256\*\*:/ {
      print "**Requirements Content-SHA256**: `" digest "`"
      next
    }
    {print}
  ' "$feature/plan.md" > "$tmp" && mv "$tmp" "$feature/plan.md"
  seal_gate "$feature/plan.md"
}

rewrite() {
  local file="$1" expression="$2" tmp="$1.tmp"
  sed "$expression" "$file" > "$tmp" && mv "$tmp" "$file"
}

expect() {
  local wanted="$1" feature="$2" label="$3" diagnostic="${4:-}" rc=0 got
  bash "$SCRIPT" tasks-structure "$feature" > "$TEST_TMP/out" 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then got=pass; else got=fail; fi
  if [[ "$got" == "$wanted" ]] &&
     { [[ -z "$diagnostic" ]] || grep -F "$diagnostic" "$TEST_TMP/out" >/dev/null 2>&1; }; then
    PASS=$((PASS + 1)); echo "✓ $label"
  else
    FAIL=$((FAIL + 1)); echo "✗ $label (wanted $wanted, got $got/$rc)"
    [[ -n "$diagnostic" ]] && echo "    required diagnostic: $diagnostic"
    sed 's/^/    /' "$TEST_TMP/out"
  fi
}

expect_mode() {
  local wanted="$1" mode="$2" feature="$3" label="$4" diagnostic="${5:-}" rc=0 got
  bash "$SCRIPT" "$mode" "$feature" > "$TEST_TMP/out" 2>&1 || rc=$?
  if [[ "$rc" -eq 0 ]]; then got=pass; else got=fail; fi
  if [[ "$got" == "$wanted" ]] &&
     { [[ -z "$diagnostic" ]] || grep -F "$diagnostic" "$TEST_TMP/out" >/dev/null 2>&1; }; then
    PASS=$((PASS + 1)); echo "✓ $label"
  else
    FAIL=$((FAIL + 1)); echo "✗ $label (wanted $wanted, got $got/$rc)"
    [[ -n "$diagnostic" ]] && echo "    required diagnostic: $diagnostic"
    sed 's/^/    /' "$TEST_TMP/out"
  fi
}

make_plan_basis() {
  local feature="$1" spec_hash
  mkdir -p "$feature"
  awk '/^cat > "\$TEST_TMP\/good\/spec\.md" <<'"'"'EOF'"'"'$/{on=1;next} on && /^EOF$/{exit} on{print}' \
    tests/run-tests.sh > "$feature/spec.md"
  seal_gate "$feature/spec.md"
  spec_hash=$(content_hash "$feature/spec.md")
  awk -v hash="$spec_hash" '
    /^cat > "\$TEST_TMP\/good\/plan\.md" <<EOF$/ {on=1; next}
    on && /^EOF$/ {exit}
    on {gsub(/\$SPEC_HASH/, hash); gsub(/\\`/, "`"); print}
  ' tests/run-tests.sh > "$feature/plan.md"
  seal_gate "$feature/plan.md"
}

write_none_tasks() {
  local feature="$1"
  cat > "$feature/tasks.md" <<'EOF'
# Tasks: Protocol v3 no test controls

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

## GateSpec Test Control Closure *(gatespec: mandatory)*
- **Mode**: `none`
| Control | Verification gap / production invariant | Test-only surface | Production touchpoint | Allowed effect / lifetime | Build switch / validator | Consumer tasks/tests | Default-build proof task |
|---|---|---|---|---|---|---|---|
| none | none | none | none | none | none | none | none |

## Phase 1: Setup
- [ ] T001 Create the feature scaffolding.
## Phase 2: Foundational
- [ ] T002 Verify the configuration store foundation.
- [ ] T003 GateSpec review checkpoint REV-FOUNDATION: run speckit.gatespec.review-implementation --scope REV-FOUNDATION and require .gatespec/reviews/REV-FOUNDATION/seal.md before continuing
## Phase 3: User Story 1 - Hot reload
- [ ] T004 [US1] Verify hot reload without a production test seam.
- [ ] T005 [US1] GateSpec review checkpoint REV-US1: run speckit.gatespec.review-implementation --scope REV-US1 and require .gatespec/reviews/REV-US1/seal.md before continuing
## Phase 4: Polish & Cross-Cutting Concerns
- [ ] T006 Run complete feature validation.
- [ ] T007 GateSpec review checkpoint REV-FINAL: run speckit.gatespec.review-implementation --scope REV-FINAL and require .gatespec/reviews/REV-FINAL/seal.md before continuing
EOF
}

write_isolated_tasks() {
  local feature="$1"
  cat > "$feature/tasks.md" <<'EOF'
# Tasks: Protocol v3 isolated test control

## GateSpec Checkpoint Closure *(gatespec: mandatory)*
| Checkpoint | Contract refs | Production tasks | Verification tasks |
|---|---|---|---|
| REV-FOUNDATION | D1, FR-002 | T001, T002 | T003 |
| REV-US1 | FR-001 | none | T005 |
| REV-FINAL | SC-001 | none | T007 |

## GateSpec Prior Review Closure *(gatespec: mandatory)*
| Finding-SHA256 | Source verdict | Required-before | Remediation tasks |
|---|---|---|---|
| none | none | none | none |

## GateSpec Test Control Closure *(gatespec: mandatory)*
- **Mode**: `isolated`
| Control | Verification gap / production invariant | Test-only surface | Production touchpoint | Allowed effect / lifetime | Build switch / validator | Consumer tasks/tests | Default-build proof task |
|---|---|---|---|---|---|---|---|
| TC-001 | Deterministically pause one coordinator after checkpoint publication without changing the public Open contract. | llm_gateway/src/testonly/checkpoint_control.h::xclaw::testonly::CheckpointControl | llm_gateway/src/checkpoint_coordinator.cc::xclaw::CheckpointCoordinator::Publish | One named one-shot pause on one coordinator; a typed per-instance RAII guard restores ordinary execution on destruction. | XCLAW_ENABLE_TEST_HOOKS @ llm_gateway/CMakeLists.txt @ llm_gateway/tests/testonly/validate_test_controls.sh | T005 | T003 |

## Phase 1: Setup
- [ ] T001 Wire xclaw::CheckpointCoordinator::Publish in llm_gateway/src/checkpoint_coordinator.cc without changing Open(path).
## Phase 2: Foundational
- [ ] T002 Add TC-001 typed per-instance RAII xclaw::testonly::CheckpointControl in llm_gateway/src/testonly/checkpoint_control.h behind XCLAW_ENABLE_TEST_HOOKS and wire llm_gateway/CMakeLists.txt plus llm_gateway/tests/testonly/validate_test_controls.sh.
- [ ] T003 Prove the ordinary build with bash llm_gateway/tests/testonly/validate_test_controls.sh --gatespec-lane default-off while omitting XCLAW_ENABLE_TEST_HOOKS completely; assert no TC-001 symbol, field, branch, or resource remains.
- [ ] T004 GateSpec review checkpoint REV-FOUNDATION: run speckit.gatespec.review-implementation --scope REV-FOUNDATION and require .gatespec/reviews/REV-FOUNDATION/seal.md before continuing
## Phase 3: User Story 1 - Hot reload
- [ ] T005 [US1] Run the TC-001 consumer test through bash llm_gateway/tests/testonly/validate_test_controls.sh --gatespec-lane explicit-on and prove the RAII guard affects one coordinator then restores it.
- [ ] T006 [US1] GateSpec review checkpoint REV-US1: run speckit.gatespec.review-implementation --scope REV-US1 and require .gatespec/reviews/REV-US1/seal.md before continuing
## Phase 4: Polish & Cross-Cutting Concerns
- [ ] T007 Rerun default-off and explicit-on validator lanes and the complete validation suite.
- [ ] T008 GateSpec review checkpoint REV-FINAL: run speckit.gatespec.review-implementation --scope REV-FINAL and require .gatespec/reviews/REV-FINAL/seal.md before continuing
EOF
}

clone_isolated() {
  local name="$1" feature
  feature="$TEST_TMP/$name"
  mkdir -p "$feature"
  cp "$TEST_TMP/isolated/spec.md" "$feature/spec.md"
  cp "$TEST_TMP/isolated/plan.md" "$feature/plan.md"
  cp "$TEST_TMP/isolated/tasks.md" "$feature/tasks.md"
}

make_plan_basis "$TEST_TMP/none"
write_none_tasks "$TEST_TMP/none"
expect pass "$TEST_TMP/none" "Protocol v3 Mode none accepts the exact all-none closure"

make_plan_basis "$TEST_TMP/isolated"
write_isolated_tasks "$TEST_TMP/isolated"
expect pass "$TEST_TMP/isolated" "Protocol v3 isolated control passes structural closure"

clone_isolated multibundle
awk '
  /^\| TC-001 \|/ {
    print "| TC-001 | Pause one coordinator at checkpoint publication. | llm_gateway/src/testonly/checkpoint_control.h::xclaw::testonly::CheckpointControl | llm_gateway/src/checkpoint_coordinator.cc::xclaw::CheckpointCoordinator::Publish | One named one-shot pause on one coordinator; typed per-instance RAII restores ordinary execution. | XCLAW_ENABLE_TEST_HOOKS @ llm_gateway/CMakeLists.txt @ llm_gateway/tests/testonly/validate_test_controls.sh | T005 | T003 |"
    print "| TC-002 | Count one coordinator retry without exposing product state. | llm_gateway/src/testonly/retry_control.h::xclaw::testonly::RetryControl | llm_gateway/src/checkpoint_coordinator.cc::xclaw::CheckpointCoordinator::Retry | One per-instance counter for one guard lifetime; typed RAII removes the observer. | XCLAW_ENABLE_TEST_HOOKS @ llm_gateway/CMakeLists.txt @ llm_gateway/tests/testonly/validate_test_controls.sh | T005 | T003 |"
    print "| TC-003 | Select one deterministic storage fault without a runtime toggle. | storage/src/testonly/fault_control.h::storage::testonly::FaultControl | storage/src/store.cc::storage::Store::Write | One operation receives one selected fault; typed per-instance RAII restores normal storage. | STORAGE_ENABLE_TEST_HOOKS @ storage/CMakeLists.txt @ storage/tests/testonly/validate_test_controls.sh | T005 | T003 |"
    next
  }
  {print}
' "$TEST_TMP/multibundle/tasks.md" > "$TEST_TMP/multibundle/tasks.md.tmp"
mv "$TEST_TMP/multibundle/tasks.md.tmp" "$TEST_TMP/multibundle/tasks.md"
rewrite "$TEST_TMP/multibundle/tasks.md" \
  's#omitting XCLAW_ENABLE_TEST_HOOKS completely#omitting XCLAW_ENABLE_TEST_HOOKS and STORAGE_ENABLE_TEST_HOOKS completely#'
expect pass "$TEST_TMP/multibundle" \
  "multiple controls may share one validator tuple while another project uses a second tuple"

cp -R "$TEST_TMP/multibundle" "$TEST_TMP/validator-reused-across-tuples"
rewrite "$TEST_TMP/validator-reused-across-tuples/tasks.md" \
  's#storage/tests/testonly/validate_test_controls.sh#llm_gateway/tests/testonly/validate_test_controls.sh#g'
expect fail "$TEST_TMP/validator-reused-across-tuples" \
  "one validator path cannot represent different switch and wiring tuples"

cp -R "$TEST_TMP/multibundle" "$TEST_TMP/tuple-reused-across-validators"
rewrite "$TEST_TMP/tuple-reused-across-validators/tasks.md" \
  's#STORAGE_ENABLE_TEST_HOOKS @ storage/CMakeLists.txt @ storage/tests/testonly/validate_test_controls.sh#XCLAW_ENABLE_TEST_HOOKS @ llm_gateway/CMakeLists.txt @ storage/tests/testonly/validate_test_controls.sh#'
expect fail "$TEST_TMP/tuple-reused-across-validators" \
  "one switch and build-wiring tuple cannot identify different validators"

clone_isolated approved-exception
rewrite "$TEST_TMP/approved-exception/spec.md" \
  's/What reload scope is required? → A: Replace values without dropping connections./Which source-auditable replacements are required for the generated-language test harness? → A: Use the three recorded generated-project replacements in TCE-001 through TCE-003./'
for artifact in spec.md plan.md; do
  rewrite "$TEST_TMP/approved-exception/$artifact" 's/- \*\*Mode\*\*: `none`/- **Mode**: `approved`/'
  # shellcheck disable=SC1004 # sed replacement emits three literal table lines.
  rewrite "$TEST_TMP/approved-exception/$artifact" \
    's#| none | none | none | none | none |#| TCE-001 | source-root | R1 | Generated control source roots end in /generated/src/test_only and the generator manifest enumerates every output. | The generated project cannot emit below the handwritten src tree; the dedicated suffix remains source-auditable. |\
| TCE-002 | switch-identifier | R1 | Dedicated positive hook identifiers match *_HOOKS_TEST_ONLY and the generator manifest enumerates every declaration. | The generator reserves the canonical identifier suffix; the replacement stays dedicated and defaults OFF. |\
| TCE-003 | validator-path-marker | R1 | Generated validators live under tools, end in _control_validator.sh, and are enumerated by the generated-project manifest. | The fixed generated-tools convention supplies an auditable marker without pre-registering a validator path. |#'
done
seal_gate "$TEST_TMP/approved-exception/spec.md"
sync_plan_basis "$TEST_TMP/approved-exception"
rewrite "$TEST_TMP/approved-exception/tasks.md" \
  's#llm_gateway/src/testonly/checkpoint_control.h#llm_gateway/generated/src/test_only/checkpoint_control.h#g'
rewrite "$TEST_TMP/approved-exception/tasks.md" \
  's/XCLAW_ENABLE_TEST_HOOKS/GENERATED_HOOKS_TEST_ONLY/g'
rewrite "$TEST_TMP/approved-exception/tasks.md" \
  's#llm_gateway/tests/testonly/validate_test_controls.sh#tools/generated_control_validator.sh#g'
expect pass "$TEST_TMP/approved-exception" \
  "approved source-root, switch-identifier, and validator-path-marker replacements pass"

cp -R "$TEST_TMP/approved-exception" "$TEST_TMP/approved-lowercase-switch"
for artifact in spec.md plan.md; do
  rewrite "$TEST_TMP/approved-lowercase-switch/$artifact" \
    's/Dedicated positive hook identifiers match \*_HOOKS_TEST_ONLY and the generator manifest enumerates every declaration./Dedicated positive hook identifiers use lower_snake_case and end in _enable_test_hooks; the generator manifest enumerates every declaration./'
  rewrite "$TEST_TMP/approved-lowercase-switch/$artifact" \
    's/The generator reserves the canonical identifier suffix; the replacement stays dedicated and defaults OFF./The generated language reserves that auditable lowercase suffix; the replacement stays dedicated and defaults OFF./'
done
seal_gate "$TEST_TMP/approved-lowercase-switch/spec.md"
sync_plan_basis "$TEST_TMP/approved-lowercase-switch"
rewrite "$TEST_TMP/approved-lowercase-switch/tasks.md" \
  's/GENERATED_HOOKS_TEST_ONLY/generated_enable_test_hooks/g'
expect pass "$TEST_TMP/approved-lowercase-switch" \
  "an approved switch-identifier TCE permits one safe lowercase dedicated identifier"

clone_isolated unapproved-lowercase-switch
rewrite "$TEST_TMP/unapproved-lowercase-switch/tasks.md" \
  's/XCLAW_ENABLE_TEST_HOOKS/generated_enable_test_hooks/g'
expect fail "$TEST_TMP/unapproved-lowercase-switch" \
  "the same lowercase identifier fails without a switch-identifier TCE" \
  "unless Requirements approved the switch-identifier exception"

clone_isolated approved-language-marker
rewrite "$TEST_TMP/approved-language-marker/spec.md" \
  's/What reload scope is required? → A: Replace values without dropping connections./Which source-auditable language marker does the generated harness require? → A: Use the generator-defined namespace marker recorded in TCE-001./'
for artifact in spec.md plan.md; do
  rewrite "$TEST_TMP/approved-language-marker/$artifact" \
    's/- \*\*Mode\*\*: `none`/- **Mode**: `approved`/'
  rewrite "$TEST_TMP/approved-language-marker/$artifact" \
    's#| none | none | none | none | none |#| TCE-001 | language-marker | R1 | Generated C++ control namespaces end in fixture_control, and the generator manifest enumerates every emitted declaration. | The generated language reserves that auditable terminal marker while task-stage registration still names each concrete control. |#'
done
seal_gate "$TEST_TMP/approved-language-marker/spec.md"
sync_plan_basis "$TEST_TMP/approved-language-marker"
rewrite "$TEST_TMP/approved-language-marker/tasks.md" \
  's/xclaw::testonly::CheckpointControl/xclaw::fixture_control::CheckpointControl/g'
expect pass "$TEST_TMP/approved-language-marker" \
  "an approved source-auditable language-marker replacement permits its terminal namespace"

cp -R "$TEST_TMP/approved-exception" "$TEST_TMP/exception-bad-id"
rewrite "$TEST_TMP/exception-bad-id/spec.md" 's/TCE-001/TCE-002/'
seal_gate "$TEST_TMP/exception-bad-id/spec.md"
sync_plan_basis "$TEST_TMP/exception-bad-id"
expect fail "$TEST_TMP/exception-bad-id" "TCE IDs are continuous from TCE-001"

cp -R "$TEST_TMP/approved-exception" "$TEST_TMP/exception-bad-rule"
rewrite "$TEST_TMP/exception-bad-rule/spec.md" 's/| source-root |/| structural-floor |/'
seal_gate "$TEST_TMP/exception-bad-rule/spec.md"
sync_plan_basis "$TEST_TMP/exception-bad-rule"
expect fail "$TEST_TMP/exception-bad-rule" "a TCE cannot exempt a structural or lifecycle floor"

for forbidden_rule in default-off runtime-activation evidence-schema; do
  cp -R "$TEST_TMP/approved-exception" "$TEST_TMP/exception-$forbidden_rule"
  rewrite "$TEST_TMP/exception-$forbidden_rule/spec.md" \
    "s/| source-root |/| $forbidden_rule |/"
  seal_gate "$TEST_TMP/exception-$forbidden_rule/spec.md"
  sync_plan_basis "$TEST_TMP/exception-$forbidden_rule"
  expect fail "$TEST_TMP/exception-$forbidden_rule" \
    "TCE cannot exempt the $forbidden_rule protocol floor"
done

cp -R "$TEST_TMP/approved-exception" "$TEST_TMP/exception-missing-decision"
rewrite "$TEST_TMP/exception-missing-decision/spec.md" 's/| R1 |/| R99 |/'
seal_gate "$TEST_TMP/exception-missing-decision/spec.md"
sync_plan_basis "$TEST_TMP/exception-missing-decision"
expect fail "$TEST_TMP/exception-missing-decision" \
  "each approved TCE row must bind one concluded Requirements decision"

cp -R "$TEST_TMP/approved-exception" "$TEST_TMP/exception-decision-outside-clarifications"
rewrite "$TEST_TMP/exception-decision-outside-clarifications/spec.md" '/^- Q: \[R1\]/d'
awk '
  /^## Assumptions$/ {
    print
    print "- Q: [R1] Which source-auditable replacements are required for the generated-language test harness? → A: Use the three recorded generated-project replacements in TCE-001 through TCE-003."
    next
  }
  {print}
' "$TEST_TMP/exception-decision-outside-clarifications/spec.md" \
  > "$TEST_TMP/exception-decision-outside-clarifications/spec.md.tmp"
mv "$TEST_TMP/exception-decision-outside-clarifications/spec.md.tmp" \
  "$TEST_TMP/exception-decision-outside-clarifications/spec.md"
seal_gate "$TEST_TMP/exception-decision-outside-clarifications/spec.md"
sync_plan_basis "$TEST_TMP/exception-decision-outside-clarifications"
expect fail "$TEST_TMP/exception-decision-outside-clarifications" \
  "a matching R decision outside Clarifications cannot authorize a TCE"

cp -R "$TEST_TMP/approved-exception" "$TEST_TMP/exception-copy-drift"
rewrite "$TEST_TMP/exception-copy-drift/plan.md" \
  's/enumerates every output/enumerates selected outputs/'
seal_gate "$TEST_TMP/exception-copy-drift/plan.md"
expect fail "$TEST_TMP/exception-copy-drift" \
  "Plan must copy the approved Requirements TCE body exactly"

clone_isolated legacy-spec-implicit-none
awk '
  /^### Test Control Policy Exceptions \*\(gatespec: mandatory\)\*$/ {skip=1; next}
  skip && /^## / {skip=0}
  !skip {print}
' "$TEST_TMP/legacy-spec-implicit-none/spec.md" > "$TEST_TMP/legacy-spec-implicit-none/spec.md.tmp"
mv "$TEST_TMP/legacy-spec-implicit-none/spec.md.tmp" "$TEST_TMP/legacy-spec-implicit-none/spec.md"
seal_gate "$TEST_TMP/legacy-spec-implicit-none/spec.md"
sync_plan_basis "$TEST_TMP/legacy-spec-implicit-none"
expect pass "$TEST_TMP/legacy-spec-implicit-none" \
  "legacy Approved Requirements without a TCE section supplies implicit none to a v3 Plan"

clone_isolated draft-spec-missing-exceptions
rewrite "$TEST_TMP/draft-spec-missing-exceptions/spec.md" \
  's/^\*\*Status\*\*: Approved-Requirements (2026-08-07)/**Status**: Draft/'
awk '
  /^### Test Control Policy Exceptions \*\(gatespec: mandatory\)\*$/ {skip=1; next}
  skip && /^## / {skip=0}
  !skip {print}
' "$TEST_TMP/draft-spec-missing-exceptions/spec.md" > "$TEST_TMP/draft-spec-missing-exceptions/spec.md.tmp"
mv "$TEST_TMP/draft-spec-missing-exceptions/spec.md.tmp" "$TEST_TMP/draft-spec-missing-exceptions/spec.md"
rewrite "$TEST_TMP/draft-spec-missing-exceptions/spec.md" '/^## Gate Approval/,$d'
expect_mode fail spec "$TEST_TMP/draft-spec-missing-exceptions" \
  "new Draft Requirements cannot omit Test Control Policy Exceptions"

clone_isolated policy-default-on
rewrite "$TEST_TMP/policy-default-on/plan.md" 's/declared default is `OFF`/declared default is `ON`/'
seal_gate "$TEST_TMP/policy-default-on/plan.md"
expect fail "$TEST_TMP/policy-default-on" \
  "Test Control Policy cannot weaken the declared default to ON" "Test Control Policy"

clone_isolated policy-product-api
rewrite "$TEST_TMP/policy-product-api/plan.md" \
  's/Formal product APIs gain no/Formal product APIs may gain/'
seal_gate "$TEST_TMP/policy-product-api/plan.md"
expect fail "$TEST_TMP/policy-product-api" \
  "Test Control Policy preserves the formal product API prohibition" "Test Control Policy"

clone_isolated policy-many-guards
rewrite "$TEST_TMP/policy-many-guards/plan.md" \
  's/most one visually contiguous dedicated/any number of scattered/'
seal_gate "$TEST_TMP/policy-many-guards/plan.md"
expect fail "$TEST_TMP/policy-many-guards" \
  "Test Control Policy preserves the one-guard readability rule" "Test Control Policy"

for legacy_protocol in 1 2; do
  clone_isolated "active-v$legacy_protocol"
  rewrite "$TEST_TMP/active-v$legacy_protocol/plan.md" \
    "s/Protocol Version\*\*: \`3\`/Protocol Version**: \`$legacy_protocol\`/"
  seal_gate "$TEST_TMP/active-v$legacy_protocol/plan.md"
  expect fail "$TEST_TMP/active-v$legacy_protocol" \
    "active Protocol v$legacy_protocol cannot enter tasks" 'gatespec.plan --revise'
done

expect_mode fail design "$TEST_TMP/active-v2" \
  "active Protocol v2 cannot cross the Design before-tasks boundary" \
  'gatespec.plan --revise'
cp -R "$TEST_TMP/active-v2" "$TEST_TMP/active-v2-source"
mkdir -p "$TEST_TMP/active-v2-source/contracts"
printf '%s\n' '<!-- gatespec: source-design -->' > \
  "$TEST_TMP/active-v2-source/contracts/source-design.md"
expect_mode fail source-candidate "$TEST_TMP/active-v2-source" \
  "active Protocol v2 cannot enter Source review" 'gatespec.plan --revise'

mkdir -p "$TEST_TMP/active-v2/.gatespec"
printf '%s\n' '# untracked acceptance is not history' > "$TEST_TMP/active-v2/.gatespec/acceptance.md"
expect fail "$TEST_TMP/active-v2" "untracked acceptance cannot bypass the active v2 upgrade" \
  'gatespec.plan --revise'

git -C "$TEST_TMP/active-v2" init -q
git -C "$TEST_TMP/active-v2" symbolic-ref HEAD refs/heads/feature
git -C "$TEST_TMP/active-v2" config user.name 'GateSpec Test Control Fixture'
git -C "$TEST_TMP/active-v2" config user.email 'fixture@example.invalid'
git -C "$TEST_TMP/active-v2" add spec.md plan.md tasks.md
git -C "$TEST_TMP/active-v2" commit -qm 'active Protocol v2 fixture'
expect_mode fail retask-eligible "$TEST_TMP/active-v2" \
  "retask cannot upgrade active Protocol v2" 'gatespec.plan --revise'

clone_isolated missing
rewrite "$TEST_TMP/missing/tasks.md" '/^## GateSpec Test Control Closure /,$d'
expect fail "$TEST_TMP/missing" "v3 tasks cannot omit Test Control Closure"

clone_isolated malformed
rewrite "$TEST_TMP/malformed/tasks.md" 's/| Control | Verification gap \/ production invariant |/| Control | Gap |/'
expect fail "$TEST_TMP/malformed" "Test Control Closure rejects a malformed header"

clone_isolated duplicate
sed -n '/^## GateSpec Test Control Closure /,/^## Phase 1/p' "$TEST_TMP/duplicate/tasks.md" > "$TEST_TMP/duplicate-section"
sed '/^## Phase 1/r '"$TEST_TMP/duplicate-section" "$TEST_TMP/duplicate/tasks.md" > "$TEST_TMP/duplicate/tasks.tmp"
mv "$TEST_TMP/duplicate/tasks.tmp" "$TEST_TMP/duplicate/tasks.md"
expect fail "$TEST_TMP/duplicate" "Test Control Closure must be unique"

clone_isolated bad-id
rewrite "$TEST_TMP/bad-id/tasks.md" 's/TC-001/TC-002/g'
expect fail "$TEST_TMP/bad-id" "Test Control IDs must start at TC-001 and remain consecutive"

clone_isolated bad-path
rewrite "$TEST_TMP/bad-path/tasks.md" 's#llm_gateway/src/testonly/checkpoint_control.h#llm_gateway/src/checkpoint_control.h#g'
expect fail "$TEST_TMP/bad-path" "Test Control source must stay below src/testonly"

clone_isolated bad-language-marker
rewrite "$TEST_TMP/bad-language-marker/tasks.md" \
  's/xclaw::testonly::CheckpointControl/xclaw::CheckpointControl/g'
expect fail "$TEST_TMP/bad-language-marker" \
  "Test Control symbols require a terminal testonly marker without an approved replacement"

clone_isolated bad-switch
rewrite "$TEST_TMP/bad-switch/tasks.md" 's/XCLAW_ENABLE_TEST_HOOKS/XCLAW_TEST_HOOKS/g'
expect fail "$TEST_TMP/bad-switch" "hook switch must use the dedicated positive suffix"

clone_isolated bad-validator
rewrite "$TEST_TMP/bad-validator/tasks.md" 's#llm_gateway/tests/testonly/validate_test_controls.sh#llm_gateway/tests/validate_controls.sh#g'
expect fail "$TEST_TMP/bad-validator" "validator path must be testonly-named"

clone_isolated unsafe-wiring-path
rewrite "$TEST_TMP/unsafe-wiring-path/tasks.md" \
  's#llm_gateway/CMakeLists.txt#llm_gateway/CMakeLists.txt;unsafe#g'
expect fail "$TEST_TMP/unsafe-wiring-path" \
  "build wiring paths reject shell metacharacters"

clone_isolated unsafe-validator-path
rewrite "$TEST_TMP/unsafe-validator-path/tasks.md" \
  's#llm_gateway/tests/testonly/validate_test_controls.sh#llm_gateway/tests/testonly/validate_$(unsafe).sh#g'
expect fail "$TEST_TMP/unsafe-validator-path" \
  "validator paths reject command-substitution metacharacters"

clone_isolated leading-dash-validator
rewrite "$TEST_TMP/leading-dash-validator/tasks.md" \
  's#llm_gateway/tests/testonly/validate_test_controls.sh#-testonly-validator.sh#g'
expect fail "$TEST_TMP/leading-dash-validator" \
  "validator paths cannot begin with a dash"

clone_isolated dot-prefixed-surface
rewrite "$TEST_TMP/dot-prefixed-surface/tasks.md" \
  's#llm_gateway/src/testonly/checkpoint_control.h#./llm_gateway/src/testonly/checkpoint_control.h#g'
expect fail "$TEST_TMP/dot-prefixed-surface" \
  "Test Control paths reject a leading dot component"

clone_isolated repeated-slash-wiring
rewrite "$TEST_TMP/repeated-slash-wiring/tasks.md" \
  's#llm_gateway/CMakeLists.txt#llm_gateway//CMakeLists.txt#g'
expect fail "$TEST_TMP/repeated-slash-wiring" \
  "Test Control paths reject repeated slash aliases"

clone_isolated trailing-slash-validator
rewrite "$TEST_TMP/trailing-slash-validator/tasks.md" \
  's#llm_gateway/tests/testonly/validate_test_controls.sh#llm_gateway/tests/testonly/validate_test_controls.sh/#g'
expect fail "$TEST_TMP/trailing-slash-validator" \
  "Test Control paths reject trailing slash aliases"

clone_isolated repeated-dot-name
rewrite "$TEST_TMP/repeated-dot-name/tasks.md" \
  's#checkpoint_control.h#checkpoint..control.h#g'
expect pass "$TEST_TMP/repeated-dot-name" \
  "portable path components may contain repeated dots without becoming dot traversal"

clone_isolated operator-symbol
rewrite "$TEST_TMP/operator-symbol/tasks.md" \
  's/xclaw::CheckpointCoordinator::Publish/xclaw::CheckpointCoordinator::operator[]/g'
expect pass "$TEST_TMP/operator-symbol" \
  "common C++ operator spellings remain valid path::symbol declarations"

clone_isolated bad-task-ref
rewrite "$TEST_TMP/bad-task-ref/tasks.md" 's/| T005 | T003 |/| T999 | T003 |/'
expect fail "$TEST_TMP/bad-task-ref" "control consumers must reference existing tasks"

echo ''
echo "==> Protocol v3 Test Controls: $PASS passed, $FAIL failed"
[[ "$FAIL" -eq 0 ]]
