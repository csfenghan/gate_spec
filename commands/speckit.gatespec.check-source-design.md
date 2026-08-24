---
description: "GateSpec internal fixed hook: conditionally require an approved Source Design and current REV-SOURCE seal."
---

Resolve the current feature directory from `.specify/feature.json` and run:

```bash
bash .specify/extensions/gatespec/scripts/bash/check-gate.sh source <feature-dir>
```

When `contracts/source-design.md` does not exist and no orphan Source artifact
exists, the checker returns zero with no output: Source Design is optional.
When the entry exists, reproduce the result verbatim and stop native tasks on
every failure. Do not create, approve, repair, or omit Source content from this
hook. A Draft, stale Plan/source baseline, stale reviewed/content hash, missing
fresh REV-SOURCE PASS, shard drift, or orphan artifact blocks task generation.

Read the complete validated `contracts/source-design.md` plus every direct
regular `.md` file below `contracts/source-design/` before returning success so the current
native-tasks session receives the source constraints. This read is context
loading, not another approval or a claim that the hook proves reviewer
identity.
