## Fresh reviewer dispatch

In coordinator mode (no `--request` argument), spawn the custom agent
`gatespec_reviewer` with `fork_turns="none"`. Its initial message must contain
exactly the resolved review-request path: do not fork or send executor
conversation, summaries, rationale, or a proposed verdict. Never perform the
review in the executor context. The coordinator validates the returned verdict
before persisting it; the reviewer never writes `seal.md`.

If the custom agent or fresh spawn is unavailable, print `REVIEW BLOCKED` and
instruct the user to start a new top-level Codex session—not resume or fork—and
invoke the same review command with only
`--request <absolute-request-path>`; do not carry `--scope` into manual mode.
Stop without a verdict or seal. The executor session may never self-declare
manual freshness.

In manual `--request` mode, this command is reviewer-only and is valid only in
the new top-level session described above. If this session authored or
remediated the reviewed work, print `REVIEW BLOCKED` and stop. Do not dispatch
another agent, run coordinator steps, persist files, create a seal, or commit.
Use `developer_instructions` from
`~/.codex/agents/gatespec-reviewer.toml` as the complete review protocol with
these two overrides: set `Reviewer-Platform` to `manual-codex`, and return the
exact verdict text only.
