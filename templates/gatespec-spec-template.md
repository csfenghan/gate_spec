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
  Format per session (compatible with core speckit.clarify):
-->

### Session [YYYY-MM-DD]

- Q: [question asked] → A: [user's final answer]

## Approved Defaults *(gatespec: mandatory)*

<!--
  GATESPEC: Non-blocking unknowns resolved via batch-approved defaults.
  Blocking decisions NEVER go here — they belong to ## Clarifications.
  Each row must carry an approval mark (✅ + date) before the gate can pass.
  Any row may be pulled out for full discussion at the user's request.
-->

| # | Item | Approved Default | Approved |
|---|------|------------------|----------|
| 1 | [item] | [default value] | ✅ [YYYY-MM-DD] |

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

## Gate Approval *(gatespec: mandatory)*

<!--
  GATESPEC: Written ONLY on explicit user approval of the ≤20-line summary
  (or of a diff round). `Content-SHA256` is the hash of this file with the
  Gate Approval section blanked out — the gate fails if content drifts after
  approval. Format:
-->

- **Approved by user**: [YYYY-MM-DD]
- **Content-SHA256**: `[64 hex chars]`
