# Contributing

## Principles

- Keep gameplay constants in `scripts/config.lua` or startup settings, never scattered through handlers.
- Persist only irreversible mission progress. Derive readiness from live objects.
- Treat all GUI state as advisory and revalidate on the server-side handler.
- Add localization for every player-visible string.
- Keep destructive operations behind preflight, explicit confirmation, and a named autosave.
- Do not broaden the surface reset allowlist without a specification change and dedicated tests.

## Commit shape

Commits should be small enough to review as one idea and should update documentation or tests with behavior changes. Suggested prefixes:

- `docs:` architecture, user guidance, or test evidence
- `feat:` player-facing behavior
- `fix:` defect correction
- `test:` automated or in-game coverage
- `chore:` packaging and repository maintenance

## Local checks

Run the repository validation command before committing. Then load the mod in Factorio 2.1 with Space Age and inspect `factorio-current.log` for prototype or runtime errors.

Destructive transition testing belongs in a disposable save with an independent copy. Record the game version, save fixture, commands, and result in `docs/testing.md`.

## Review checklist

- Does the change preserve the one-transition invariant?
- Could an invalid Lua object survive across a tick or save/load boundary?
- Is the operation proportional to platform count during normal play?
- Are all items transferred as native stacks?
- Does cancellation leave state and inventory unchanged?
- Is the error localized and actionable?
- Does the acceptance matrix need an evidence update?
