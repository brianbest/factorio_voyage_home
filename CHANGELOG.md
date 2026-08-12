# Changelog

All notable changes to this project are documented here. The project follows semantic versioning once the first playable release is tagged.

## [Unreleased]

### Fixed

- The Interstellar Signal `trigger_description` passed the discovery-distance setting as a number, which the engine's prototype property tree rejects ("Value must be a string"), failing the entire data stage. The value is now stringified, and a mock data-stage test guards trigger-description parameter types. Found by loading the mod in a live Factorio engine.

### Added

- Initial MVP architecture, safety model, compatibility boundary, and acceptance-test plan.
- Factorio 2.1 Space Age prototypes for progression, the staging corridor, vessel, and arrival cache.
- Persistent mission state, direction-aware distance discovery, vessel singleton/refund behavior, cargo weight handling, and derived readiness.
- Remote/map-mode mission UI fallback, vessel-relative status, destructive confirmation, and runtime event wiring.
- Guarded reset preflight and transaction with native stack preservation, deterministic reseeding, modifier allowlist, recovery nonce, and dry-run reporting.
- Fail-closed administrator development commands and release-safe status/dry-run commands.
- Automated Lua syntax, localization, module, reset, command, and control-wiring checks.
- An isolated real-engine smoke runner that creates and replays a disposable Space Age save without touching normal Factorio user data.

### Known limitations

- Live Factorio 2.1 data-stage and runtime qualification is pending.
- Factorio's autosave request exposes no completion callback; named-save timing requires live qualification.
- Scheduled platform deletion and Space Map/remote-view UI behavior require live acceptance evidence.
