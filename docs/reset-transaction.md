# Reset Transaction and Recovery

## Safety promise

The reset is a guarded, single-tick transaction with a named recovery point. It is designed to fail before mutation whenever possible and to leave an auditable `TRANSITIONING` state if an engine error occurs after destructive work begins.

> [!CAUTION]
> Factorio's autosave API requests a save but exposes no completion callback. The mod requests `tvh-pre-interstellar-jump` immediately before cargo is moved, but live Factorio qualification must confirm the practical save timing. Keep a separate manual save during MVP testing.

## Preflight

No mutation occurs unless all blockers are absent.

| Area | Validation |
|---|---|
| Session | Valid player; single-player game |
| Mission | Phase `ENABLED`; no committed nonce |
| Readiness | Full derived checklist passes again |
| Nauvis | Valid surface associated with vanilla Nauvis |
| Transit | Reserved surface name is unused |
| Arrival cache | Prototype exists with at least 48 slots |
| Vessel cargo | Valid inventory; slot count fits cache |
| Plan | Vanilla planet surfaces and player platforms are enumerated without mutation |

`/tvh-dry-run-reset` exposes the same report, including planned seeds, planet surfaces, platforms, warnings, and blockers.

## Commit sequence

| Step | Durable marker | Operation |
|---:|---|---|
| 1 | — | Request `tvh-pre-interstellar-jump` autosave |
| 2 | — | Transfer every vessel slot into a 48-slot script inventory and verify count, occupied slots, and weight |
| 3 | — | Snapshot five force fields and positive per-recipe productivity |
| 4 | `nonce-committed` | Store deterministic seed/nonce; enter `TRANSITIONING` |
| 5 | `creating-transit-surface` | Create a finite, always-day lab-tile surface |
| 6 | `moving-player-to-transit` | Move the physical character off the old platform |
| 7 | `destroying-platforms` | Schedule every player-force platform for deletion at tick offset zero |
| 8 | `regenerating-planets` | Reseed and clear generated vanilla planet surfaces, pollution, chart, and evolution |
| 9 | `resetting-force` | Reset technologies, recipes, modifiers, research, and location access |
| 10 | `restoring-modifiers` | Restore only the fixed allowlist |
| 11 | `creating-arrival` | Generate safe Nauvis terrain, place cache, and transfer slots directly |
| 12 | `moving-player-to-nauvis` | Teleport character to spawn and restore full health |
| 13 | `committing` | Delete temporary inventory/surface, enable cache mining, enter `COMPLETE` |

Every marker and nonce is written to storage and the log before its operation. This makes a post-failure save explain where execution stopped.

## What is preserved

| Category | Values |
|---|---|
| Vessel cargo | Native stacks, including supported quality, durability, spoilage, tags, and equipment state |
| Robot progress | Worker robot speed and storage |
| Production progress | Mining productivity and positive per-recipe productivity |
| Research infrastructure | Laboratory speed and productivity |
| Save metadata | Blueprint libraries, personal settings, playtime, and unrelated custom surfaces |

Everything else in the old vanilla solar system is intentionally reset or removed.

## Failure handling

### Before nonce commit

Cargo snapshot and modifier snapshot are reversible. If either verification fails, transferred stacks are returned slot-for-slot, the temporary inventory is destroyed, and phase remains `ENABLED`.

### After nonce commit

The mod does not attempt a speculative rollback after platforms or chunks may have been deleted. It records the failed step, leaves phase `TRANSITIONING`, logs the nonce, and directs the tester to the named pre-jump autosave.

### Platform deletion timing

`LuaSpacePlatform.destroy(0)` schedules deletion at the engine boundary rather than invalidating every platform object synchronously. Cargo and player relocation happen first, and no old platform reference is used afterward. The clean-save destructive acceptance test must verify that no scheduled platform survives the completed transition.
