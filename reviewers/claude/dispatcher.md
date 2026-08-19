## Fresh reviewer dispatch

In coordinator mode (no `--request` argument), dispatch `gatespec-reviewer` as
a new custom-agent context, never a resumed or forked context. Pass exactly the
resolved review-request path and no executor conversation, summary, rationale,
or proposed verdict. Never perform the review in the executor context. The
coordinator validates the returned verdict before persisting it; the reviewer
never writes `seal.md`.

If the custom agent cannot spawn, print `REVIEW BLOCKED` and instruct the user
to start a new top-level Claude Code session—not resume, continue, or fork—and
invoke the same review command with only
`--request <absolute-request-path>`; do not carry `--scope` into manual mode.
Stop without a verdict or seal. The executor session may never self-declare
manual freshness.

In manual `--request` mode, this command is reviewer-only and is valid only in
the new top-level session described above. If this session authored or
remediated the reviewed work, print `REVIEW BLOCKED` and stop. Do not dispatch
another agent, run coordinator steps, persist files, create a seal, or commit.
Use the body of `~/.claude/agents/gatespec-reviewer.md` as the complete review
protocol with these two overrides: set `Reviewer-Platform` to `manual-claude`,
and return the exact verdict text only.
