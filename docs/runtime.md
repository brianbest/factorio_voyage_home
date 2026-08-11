# Runtime Guide

## Mission state

The mod stores only five durable phases. Everything that can change through ordinary gameplay is derived again from live objects.

| Phase | Meaning | Exit condition |
|---|---|---|
| `LOCKED` | Signal has not been found | Any force platform proves the configured outward distance |
| `DISCOVERED` | Signal technology completed | Interstellar Navigation finishes |
| `ENABLED` | Vessel and staging are available | Player confirms a passing preflight |
| `TRANSITIONING` | Destructive transaction has committed | Cargo is verified in the arrival cache |
| `COMPLETE` | The one MVP jump is finished | None |

Vessel presence, platform identity, location, cargo weight, engineer presence, and personal inventory contents are never persisted as phases. Mining the vessel or leaving staging immediately changes readiness without a state repair.

## Readiness contract

`scripts/readiness.lua` produces one structured result used by the mission panel, vessel panel, confirmation dialog, status command, dry run, and final transition handler.

| Check | Passing condition |
|---|---|
| Mission enabled | Force is exactly in `ENABLED` |
| Navigation researched | Technology exists and is researched |
| Vessel present | Registered unit resolves to a valid entity on this force |
| Vessel on platform | Vessel surface owns a valid space platform |
| At staging | Platform is stopped at staging, with no active connection/distance |
| Engineer aboard | Character's physical surface is the vessel platform surface |
| Cargo within limit | Native `LuaInventory.weight` is at or below capacity |
| Personal inventory empty | Main, guns, ammo, armor, trash, and cursor contain nothing |
| Transition idle | Force is neither transitioning nor complete |

The confirmation window does not authorize a jump. `scripts/reset.lua` calls the same readiness evaluator again after **Confirm Jump** is clicked.

## Interface behavior

The public API does not provide a proven, unique “solar-system Space Map” flag across every remote-view path. The implementation therefore uses the fallback approved by the MVP specification:

- No mission interface appears before discovery.
- No permanent interface appears in ordinary character view.
- A compact Voyage Home button appears only in remote/map view after discovery.
- The button opens the mission panel on demand.
- Opening the vessel attaches status beside its native container GUI.
- The final dialog identifies erased data, preserved data, and the recovery autosave.

The in-game view matrix in [Testing](testing.md) remains release-blocking because remote/map transitions and relative GUI anchoring require a live Factorio 2.1 client.

## Runtime event table

| Event group | Work performed |
|---|---|
| Initialization/configuration | Migrate storage, reconcile technology phase, recover vessel registration, enforce staging lock |
| Every 60 ticks | Scan force platforms for discovery; refresh connected-player UI |
| Research finished | Enter `ENABLED`, unlock staging, notify the force |
| Build events | Enforce platform-only, enabled-phase, single-vessel placement |
| Mine/die/destroy events | Clear only the matching vessel registration |
| Platform state change | Refresh readiness without polling delay |
| GUI/controller/surface events | Rebuild, hide, or act on the relevant interface |

Normal repeated work is proportional to force platform count and connected player count. It does not scan planetary entities or surfaces.

## Save/load behavior

Stored references use unit number, platform index, and object-destruction registration number. On configuration change, the mod resolves the registered unit again and can search platform surfaces for a replacement registration. If multiple pre-existing vessels are discovered, it registers the lowest unit number and logs the duplicates without deleting player property.

The five-phase save/load matrix still requires live qualification. In particular, a save captured during `TRANSITIONING` is intentionally diagnostic, not resumable; restore `tvh-pre-interstellar-jump` instead of attempting an automatic partial transaction replay.
