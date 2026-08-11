# Compatibility

## Supported target

The mod targets **Factorio 2.1 with Space Age** as required by the MVP specification. It uses 2.1 runtime capabilities including native inventory-to-inventory transfer and the current space-platform APIs.

## Development environment

The workstation used for initial implementation has a prior Factorio 2.0.60 Space Age log, but no Factorio executable is currently available. That older record is useful only as environment context; it cannot qualify a 2.1 mod or exercise 2.1-only runtime methods. Consequently:

- Static checks and pure Lua tests may be completed locally.
- Prototype work is checked against the official 2.1 API and focused data-stage doubles.
- Final data-stage and in-game acceptance require a Factorio 2.1 installation.
- No acceptance test is marked passed solely because a similar 2.0 prototype exists.

## Compatibility promises

| Environment | Support |
|---|---|
| Factorio 2.1 + Space Age, single player | MVP target |
| Factorio 2.0 | Unsupported |
| Multiplayer | Explicitly unsupported |
| Vanilla game without Space Age | Unsupported |
| Cosmetic and UI mods | Best effort |
| Overhaul mods | No progression guarantee |
| Custom surfaces from other mods | Preserved, but not progression-tested |

The reset touches only player-force space platforms and surfaces associated with vanilla Space Age planets. It intentionally does not clear arbitrary custom surfaces.

## High-risk API areas

| Area | Risk | Mitigation |
|---|---|---|
| Space Map-only visibility | Public state may not uniquely identify solar-system view | Approved map-mode button fallback; explicit view matrix |
| Planet regeneration | Surface seed/chunk lifecycle is destructive and engine-sensitive | Dry-run, named autosave, explicit allowlist, disposable-save qualification |
| Force reset | Unlock effects can vary with other mods | Reset then enforce starting locks; document overhaul limitation |
| Rich stack transfer | Equipment/tags/quality must remain intact | Native direct transfer plus count/slot verification |
| Platform deletion timing | Objects may invalidate at end of tick | Snapshot first, avoid retained object references, verify all platforms scheduled |
