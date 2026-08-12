# Live Engine Test Results

This log records tests performed by a real Factorio executable. It deliberately separates a useful compatibility smoke test from qualification on the mod's supported Factorio 2.1 target.

## 2026-08-11 — Factorio 2.1.14 target smoke

| Field | Value |
|---|---|
| Engine | Factorio 2.1.14, build 87180, macOS ARM64, Steam |
| Expansion | Space Age enabled |
| Mod source | `main` at `73b2b63c9d5697a49e9cc7f97ac9fb8cc1267d66` |
| Installed package | `factorio-the-voyage-home_0.1.0.zip`, SHA-256 `04e968dfd037513cc9d029732d80535a76ef93b4a01bf118d4c0558cf954ab1a` |
| Seed | `246813579` |
| Runtime duration | 180 benchmark ticks |
| User data | Isolated temporary directory; normal saves untouched |
| Result | **Pass — target data-stage and runtime smoke acceptance** |

### What passed

1. The unmodified Factorio 2.1 mod metadata and dependencies were accepted.
2. The complete base, Recycler, Quality, Elevated Rails, Space Age, and Voyage Home data stages loaded.
3. Factorio validated the prototype graph and produced the Voyage Home prototype checksum.
4. Factorio created and saved a deterministic disposable Space Age map.
5. The save loaded again and ran 180 runtime ticks without a script error.
6. The packaged ZIP installed in the normal mods directory produced the same prototype and runtime checksums when loaded from an isolated mod list.

No compatibility shim was used. This qualifies the baseline data-stage, initialization, save creation, save reload, and bounded runtime path on the supported engine line. It does not qualify the interactive or destructive acceptance cases.

## 2026-08-11 — Historical Factorio 2.0.77 compatibility smoke

| Field | Value |
|---|---|
| Engine | Factorio 2.0.77, build 84539, macOS ARM64, Steam |
| Expansion | Space Age enabled |
| Mod source | PR #1 head, `c3a5c2ede43f4cac96eae2789b307bbb53cbed76` |
| Seed | `246813579` |
| Runtime duration | 180 benchmark ticks |
| User data | Isolated temporary directory; normal mods and saves untouched |
| Result | **Pass — compatibility smoke only** |

### What passed

1. The real engine loaded the mod settings stage.
2. The complete base, Quality, Elevated Rails, Space Age, and Voyage Home data stages loaded.
3. Factorio validated the resulting prototype graph and produced a prototype checksum.
4. Factorio created and saved a deterministic disposable Space Age map.
5. The save loaded again and ran 180 runtime ticks without a script error.

### Defect reproduction and fix verification

The same command against `main` at `4386862b2966b457f749d6874642ff9acaa14d13` failed during prototype validation:

```text
Error while loading technology prototype "tvh-interstellar-signal" (technology):
Value must be a string in property tree at
ROOT.technology.tvh-interstellar-signal.research_trigger.trigger_description[1]
```

Running against PR #1 head passed both map creation and the runtime replay. This is real-engine evidence that stringifying the localized-string parameter fixes the observed data-stage blocker.

### Compatibility shim boundary

The installed engine is Factorio 2.0.77, while the mod targets 2.1. The runner changed only the temporary copy:

| Temporary edit | Reason |
|---|---|
| Down-pin `factorio_version` and dependency minimums from 2.1 to 2.0 | Allow the installed engine to consider the copy compatible |
| Convert the recipe's 2.1 `categories` list to 2.0's singular `category` | Express the same recipe category using the 2.0 schema |

The shim does not alter localized strings, runtime logic, state, events, or cargo/reset behavior. Consequently, this result is strong data-stage and startup evidence but **not** a Factorio 2.1 acceptance pass.

## Remaining live qualification

The target smoke can be repeated at any time with:

```sh
npm run test:factorio
```

The full twenty-case matrix remains in [Testing and Acceptance](testing.md). The next live phase should use disposable Factorio 2.1 saves to qualify platform placement, cargo fidelity, force reset, surface regeneration, UI visibility, and save/load resilience.
