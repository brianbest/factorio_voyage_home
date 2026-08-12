# Factorio: The Voyage Home

**The Voyage Home** is a single-player New Game Plus experiment for Factorio: Space Age. The MVP adds one earned interstellar jump: discover a signal beyond the Solar System Edge, research interstellar navigation, carry a weight-limited vessel to a staging point, and deliberately trade the current solar system for a fresh one.

> [!WARNING]
> The jump intentionally erases the current solar system. The mod performs a full preflight and requests a named recovery autosave before destructive work, but this is still pre-release software. Keep an independent save while testing.

## MVP loop

| Stage | Player goal | Persistent result |
|---|---|---|
| Discovery | Travel 100,000 km toward the Shattered Planet | `Interstellar Signal` completes once |
| Preparation | Research `Interstellar Navigation` | Vessel recipe and staging point unlock |
| Departure | Build, place, and load one Interstellar Vessel | Cargo is constrained by item weight |
| Staging | Reach the Interstellar Staging Point with the engineer aboard | Readiness checklist becomes actionable |
| Jump | Confirm the irreversible transition twice | A fresh solar system is generated |
| Arrival | Recover vessel cargo from the arrival cache | Allowlisted force modifiers survive |

The MVP deliberately supports exactly one transition. It does not add multiple systems, custom planets, prestige choices, interstellar logistics, multiplayer support, or a campaign ending.

## Requirements

- Factorio 2.1
- Space Age
- A single-player freeplay save

The implementation is based on the 2.1 runtime API. See [Compatibility](docs/compatibility.md) for the development environment caveat.

## Installation

1. Package the repository as `factorio-the-voyage-home_0.1.0.zip`, preserving the top-level directory inside the archive.
2. Copy it into the Factorio `mods` directory.
3. Enable **Factorio: The Voyage Home** and **Space Age**.
4. Start a new Space Age freeplay game or load an existing endgame save.

During development, a symlink from the Factorio mods directory to this repository is convenient.

## Configuration

| Startup setting | Default | Purpose |
|---|---:|---|
| Discovery distance | 100,000 km | First journey threshold and staging-route length |
| Cargo capacity multiplier | 1.0 | Multiplies the default rocket lift weight |
| Development commands | Off | Enables state-changing administrator commands |

Startup settings are baked into prototypes and require Factorio to restart.

## Safety model

The transition follows a guarded transaction:

1. Recalculate readiness and perform a dry-run preflight.
2. Request `tvh-pre-interstellar-jump` as a recovery autosave.
3. Move vessel stacks into a script-owned inventory without flattening metadata.
4. Snapshot only the documented modifier allowlist.
5. Move the engineer to an isolated transit surface.
6. Delete player platforms, regenerate vanilla planet surfaces, and reset the force.
7. Restore modifiers and vessel cargo into an arrival cache on Nauvis.
8. Mark the voyage complete only after restoration is verified.

No handler trusts the GUI's enabled state. The full readiness check runs again when the player confirms.

## Developer guide

| Document | Contents |
|---|---|
| [Architecture](docs/architecture.md) | Modules, invariants, events, and transaction boundaries |
| [Runtime guide](docs/runtime.md) | State machine, readiness, interface fallback, and events |
| [Reset and recovery](docs/reset-transaction.md) | Preflight, commit sequence, carryover, and recovery |
| [Testing](docs/testing.md) | Automated checks, in-game test workflow, and acceptance matrix |
| [Live engine results](docs/live-engine-results.md) | Real Factorio versions, commands, evidence, and qualification limits |
| [Compatibility](docs/compatibility.md) | Supported game version and known API risks |
| [Contributing](CONTRIBUTING.md) | Repository workflow and coding conventions |
| [Changelog](CHANGELOG.md) | Human-readable release history |

Useful administrator commands are documented in [Testing](docs/testing.md). State-changing commands are disabled unless the development startup setting is enabled.

## Project status

This repository implements the MVP described in the product and technical specification. Release readiness is tracked against twenty acceptance tests in [Testing](docs/testing.md); tests requiring a live 2.1 Space Age runtime remain explicitly marked until exercised in-game.

## License

See [LICENSE](LICENSE).
