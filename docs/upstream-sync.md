# Upstream Sync Policy

GateSpec contains **zero upstream code** — it is a pure spec-kit extension.
"Upstream sync" therefore means two cheap rituals, not merges.

## Routine (after any spec-kit upgrade)

1. Upgrade spec-kit itself (`specify` CLI) as usual — nothing in this repo
   changes.
2. Skim upstream's `templates/commands/specify.md`, `plan.md`, `clarify.md`
   changelog. Anything worth borrowing gets **manually** ported into
   gatespec's command files. This is optional, low-frequency, and never
   blocks you.
3. Bump `requires.speckit_version` in `extension.yml` if you rely on a newer
   upstream feature. If upstream ever breaks a contract we depend on, the
   version requirement turns a silent failure into an explicit install-time
   error.

## Contracts we depend on (watch these)

| Contract | Consumer | Failure mode if upstream changes it |
|----------|----------|-------------------------------------|
| `spec.md` mandatory sections (User Scenarios & Testing / Requirements / Success Criteria) | upstream tasks/implement reading our specs | tasks mis-parse — caught by our gate's section checks |
| `plan.md` sections (Technical Context / Constitution Check / Project Structure) | upstream tasks | same |
| `.specify/feature.json` (`feature_directory`) | gatespec.check, check-gate.sh | gate can't resolve dir — explicit error |
| `setup-plan.sh --json` output fields | gatespec.plan | explicit parse error |
| Extension hook events (`before_plan`, `before_tasks`) | gates auto-wiring | gates stop auto-firing — **verify after upgrades** (see below) |
| Command-name validation `speckit.{ext}.{cmd}` + free-form aliases | installation | install-time error (explicit) |
| `speckit.analyze` availability | gatespec.plan step 3 | graceful: skip with a note |

## Post-upgrade smoke check (2 minutes)

In a scratch project:

```bash
specify extension add --dev /path/to/gatespec
# 1. gated track: create a spec via /gatespec.specify, leave it unapproved,
#    then run core /speckit.plan — the before_plan hook MUST block it.
# 2. auto track: create a spec via /speckit.specify, run /speckit.plan —
#    hooks MUST stay silent (no gatespec marker).
```

If (1) stops blocking, upstream changed the hook execution path — pin
`requires.speckit_version` to the last known-good range and open an issue.

## Reference copy

A pristine upstream checkout may be kept in `spec-kit/` (gitignored,
extension-ignored) purely for diffing templates during ritual 2.
