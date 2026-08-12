# Testing and Acceptance

## Test layers

| Layer | Tool | What it proves |
|---|---|---|
| Static | Lua parser/linter and repository checks | Syntax, module boundaries, metadata, localization keys |
| Pure module | Lua test harness with API doubles | State transitions, checklist logic, weight rules, modifier snapshots |
| Data stage | Factorio headless/startup load | Prototype validity and dependency ordering |
| Runtime smoke | Disposable Space Age save | Event registration, UI, placement, route scheduling |
| Destructive integration | Named disposable saves | Cargo fidelity, regeneration, force reset, one-jump invariant |

Static and pure-module checks are safe to run repeatedly. Data-stage and runtime tests require Factorio 2.1 with Space Age. Never run a destructive integration test against a valued save.

## Current automated evidence

Run:

```sh
npm install
npm run check
```

The current suite provides the following executable evidence:

| Suite | Checks | Result |
|---|---:|---|
| Repository validation | 26 Lua files, metadata, required files, 167 locale keys | Pass |
| Mock data stage | 12 custom identities, trigger-description string safety, containers, recipe/machine, technology, route/asteroids | 6 pass |
| Core contract tests | State, settings, directional discovery, cargo, vessel singleton/refund, readiness | 15 pass |
| Reset/tooling tests | Modifier allowlist, dry run, full mocked transition, nonce, command gate | 5 pass |
| Control wiring smoke test | Lifecycle, 60-tick cadence, 22 events, two release commands | Pass |

The prototype stream also passes a mocked settings → data → data-updates load with assertions for the 48-slot containers, recipe category, research ingredients, route length, and asteroid endpoint remapping. This is useful development evidence, but it is not labeled an acceptance pass until Factorio 2.1 loads the mod itself.

## Administrator commands

| Command | Release availability | Purpose |
|---|---|---|
| `/tvh-status` | Yes | Print phase, discovery, vessel, platform, cargo, and readiness |
| `/tvh-dry-run-reset` | Yes | Run preflight and describe planned destructive actions |
| `/tvh-set-distance <km>` | Development setting | Set stored maximum distance |
| `/tvh-trigger-signal` | Development setting | Complete the scripted discovery trigger |
| `/tvh-complete-navigation` | Development setting | Complete navigation research |
| `/tvh-spawn-vessel` | Development setting | Give one vessel item |
| `/tvh-unlock-staging` | Development setting | Unlock the custom staging point |
| `/tvh-reset-mission-state` | Development setting | Return mission state to `LOCKED`; does not reset the world |

All commands require administrator permission. State-changing commands also require the development startup setting.

## Recommended in-game sequence

1. Start a new Space Age freeplay save with development commands enabled.
2. Run `/tvh-status`; confirm `LOCKED` and no mission panel.
3. Trigger discovery and complete navigation with the development commands.
4. Spawn the vessel and test rejected placement on Nauvis.
5. Place it on a platform; attempt a second placement.
6. Test cargo just below, equal to, and above capacity.
7. Send the platform to staging without the engineer, then return it.
8. Return to staging with the engineer and one deliberately non-empty character inventory.
9. Empty all personal transfer inventories and open/cancel confirmation.
10. Run `/tvh-dry-run-reset` and save manually.
11. Confirm the jump; compare cache stacks and modifier readings with the pre-jump save.
12. Save/load on arrival and verify a second jump remains impossible.

## Acceptance matrix

`Automated; live pending` means the relevant module behavior passes under API doubles but the corresponding Factorio 2.1 acceptance scenario has not yet been run.

| ID | Requirement | Primary evidence | Status |
|---|---|---|---|
| AT-01 | No premature unlock | Pure state test + clean save | Automated; live pending |
| AT-02 | Distance trigger within 60 ticks | Discovery test + route save | Automated; live pending |
| AT-03 | One-time discovery | Pure state test | Automated; live pending |
| AT-04 | Research gate | Data-stage load + save | Manual pending |
| AT-05 | Platform-only placement/refund | Placement save | Automated; live pending |
| AT-06 | Single active vessel | Placement save | Automated; live pending |
| AT-07 | Cargo weight parity | Cargo test + vessel UI | Automated; live pending |
| AT-08 | Missing engineer blocks jump | Staging save | Automated; live pending |
| AT-09 | Personal inventory bypass blocked | Readiness tests | Automated; live pending |
| AT-10 | Valid readiness | Readiness tests + staging save | Automated; live pending |
| AT-11 | Cancel is non-destructive | Confirmation save | Manual pending |
| AT-12 | Cargo fidelity | Before/after stack audit | Automated; live pending |
| AT-13 | No cargo duplication | Post-jump inventory audit | Automated; live pending |
| AT-14 | Technology reset | Before/after technology audit | Automated; live pending |
| AT-15 | Modifier preservation | Modifier snapshot audit | Automated; live pending |
| AT-16 | Fresh terrain | Seed/chunk/entity audit | Automated; live pending |
| AT-17 | Platform cleanup | Post-jump platform audit | Automated; live pending |
| AT-18 | UI visibility | Space Map view matrix | Manual pending |
| AT-19 | Save/load resilience | Five phase fixtures | Manual pending |
| AT-20 | One-transition limit | Post-completion save | Automated; live pending |

The matrix is updated with exact commands, save names, Factorio version, and observed results during release qualification. A code path existing is not recorded as a pass.

## Space Map UI spike

Test all of the following before marking AT-18 complete:

| Entry/view path | Panel expected |
|---|---|
| Character world view | Hidden |
| Planet map view | Hidden or mission-button fallback only |
| Space Map opened by shortcut | Visible after discovery |
| Space platform selected from Space Map | Visible |
| Zoom between solar-system and planet view | Correctly rebuilt/hidden |
| Save/load while Space Map is open | Correct state restored |
| UI scaling at 75%, 100%, and 150% | No overlap or truncation |

If the public API cannot uniquely identify the Space Map, use the approved remote/map-mode mission button fallback. Do not show a permanent world-view panel.
