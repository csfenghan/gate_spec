<!-- path: gatespec -->
# Feature Specification: [FEATURE NAME]

**Feature Branch**: `[###-feature-name]`

**Created**: [DATE]

**Status**: Draft

**Input**: User description: "$ARGUMENTS"

<!--
  GATESPEC GATE FIELDS (do not remove):
  - Line 1 marker `<!-- path: gatespec -->` identifies this spec as gatespec-track.
    Gate checks silently skip specs without it (upstream auto track stays untouched).
  - **Status** transitions: Draft → Approved-Requirements (YYYY-MM-DD).
    Set ONLY by explicit user approval. Any post-approval edit MUST revert
    Status to Draft and go through diff re-approval (see ## Gate Approval).
-->

## Clarifications *(gatespec: mandatory)*

<!--
  GATESPEC: Every clarification round lands here AND its conclusion MUST be
  applied to the body sections below (self-containment: a reader who never saw
  the conversation can implement from this file alone).
  Only approval-eligible human decisions belong here: each had ≥2 viable
  options with materially different human consequences. Purely technical
  matters are deferred to Design, not recorded as Clarifications or Defaults.
  Stable R<n> IDs map adaptive decision cards to their explicit answers.
  Legacy concluded entries without an ID remain valid and are not rewritten.
  Format per session (compatible with core speckit.clarify):
-->

### Session [YYYY-MM-DD]

- Q: [R1] [question asked] → A: [user's final answer]

<!-- If no clarification was needed, replace the session and example with:
- None — <specific reason no blocking decision was required>
-->

## Approved Defaults *(gatespec: mandatory)*

<!--
  GATESPEC: Routine non-blocking unknowns resolved via batch-approved defaults.
  Blocking decisions NEVER go here — they belong to ## Clarifications.
  Purely technical matters also NEVER go here — they are deferred to Design.
  Each row must carry an approval mark (✅ + date) before the gate can pass.
  Any row may be pulled out for full discussion at the user's request.
-->

| # | Item | Approved Default | Approved |
|---|------|------------------|----------|
| 1 | [item] | [default value] | ✅ [YYYY-MM-DD] |

<!-- If no default was proposed, replace the table with:
- None — <specific reason no non-blocking default was required>
-->

## Constraint Basis *(gatespec: mandatory)*

<!--
  固化生成本规格时使用的约束源，合并优先级为：
  constitution > project GateSpec constraints > user GateSpec constraints。
  缺失的约束源写 `absent`，否则记录其小写 SHA-256。
  标题与五个字段名是固定英文协议标记；除非更高优先级约束要求其他语言，
  其余可读字段值统一使用简体中文。路径、哈希和技术标识符保持原样。
  影响需求的结论还必须写入 FR、场景、Assumption 或明确的范围边界。
-->

- **Project constitution**: [源路径或 absent] — SHA-256: `[哈希或 absent]`
- **Project GateSpec constraints**: [源路径或 absent] — SHA-256: `[哈希或 absent]`
- **User GateSpec constraints**: [源路径或 absent] — SHA-256: `[哈希或 absent]`
- **Effective constraints**: [按优先级排列的中文有效约束，包含已批准的豁免]
- **Conflicts and resolutions**: [用中文逐项记录冲突、胜出规则与原因，或 无 — 原因]

## User Scenarios & Testing *(mandatory)*

<!--
  IMPORTANT: User stories should be PRIORITIZED as user journeys ordered by importance.
  Each user story/journey must be INDEPENDENTLY TESTABLE - meaning if you implement just ONE of them,
  you should still have a viable MVP (Minimum Viable Product) that delivers value.

  Assign priorities (P1, P2, P3, etc.) to each story, where P1 is the most critical.

  GATESPEC: Acceptance Scenarios MUST reference the FR IDs they exercise
  (e.g. "(covers FR-001, FR-003)"), so the gate can verify every FR has at
  least one scenario.
-->

### User Story 1 - [Brief Title] (Priority: P1)

[Describe this user journey in plain language]

**Why this priority**: [Explain the value and why it has this priority level]

**Independent Test**: [Describe how this can be tested independently - e.g., "Can be fully tested by [specific action] and delivers [specific value]"]

**Acceptance Scenarios**:

1. **Given** [initial state], **When** [action], **Then** [expected outcome] (covers FR-001)
2. **Given** [initial state], **When** [action], **Then** [expected outcome]

---

### User Story 2 - [Brief Title] (Priority: P2)

[Describe this user journey in plain language]

**Why this priority**: [Explain the value and why it has this priority level]

**Independent Test**: [Describe how this can be tested independently]

**Acceptance Scenarios**:

1. **Given** [initial state], **When** [action], **Then** [expected outcome]

---

### Edge Cases

- What happens when [boundary condition]?
- How does system handle [error scenario]?

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: System MUST [specific capability, e.g., "allow users to create accounts"]
- **FR-002**: System MUST [specific capability, e.g., "validate email addresses"]
- **FR-003**: Users MUST be able to [key interaction, e.g., "reset their password"]

*GATESPEC: unclear requirements keep the `[NEEDS CLARIFICATION: ...]` marker
until the user explicitly answers — the agent MUST NOT guess. The gate fails
while any marker remains.*

- **FR-006**: System MUST authenticate users via [NEEDS CLARIFICATION: auth method not specified - email/password, SSO, OAuth?]

### Key Entities *(include if feature involves data)*

- **[Entity 1]**: [What it represents, key attributes without implementation]
- **[Entity 2]**: [What it represents, relationships to other entities]

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: [Measurable metric, e.g., "Users can complete account creation in under 2 minutes"]
- **SC-002**: [Measurable metric, e.g., "System handles 1000 concurrent users without degradation"]

## Assumptions

- [Assumption about target users, e.g., "Users have stable internet connectivity"]
- [Assumption about scope boundaries, e.g., "Mobile support is out of scope for v1"]

<!--
  GATESPEC: Written ONLY on explicit user approval of the ≤20-line summary
  (or of a diff round). Gate Approval MUST be the unique final H2 and contain
  only the two fields below. `Content-SHA256` hashes everything before it.
-->

## Gate Approval *(gatespec: mandatory)*

- **Approved by user**: [YYYY-MM-DD]
- **Content-SHA256**: `[64 hex chars]`
