# Live Engine Test Results

This log records tests performed by a real Factorio executable. It deliberately separates a useful compatibility smoke test from qualification on the mod's supported Factorio 2.1 target.

## 2026-08-11 — Factorio 2.0.77 compatibility smoke

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

## Next target-qualified run

Factorio 2.1 is currently available through the official experimental channel. Once a 2.1 executable is installed, the same command loads an unmodified source copy and labels the result as target acceptance:

```sh
npm run test:factorio
```

Wube recommends backing up saves and blueprints before moving a Steam installation to experimental because upgraded saves and blueprints cannot be downgraded. A separate experimental installation is therefore preferable for this mod's destructive acceptance work. See the [official 2.1 experimental announcement](https://www.factorio.com/blog/post/fff-444) and [experimental download page](https://www.factorio.com/download/experimental).

The full twenty-case matrix remains in [Testing and Acceptance](testing.md). The next live phase should use Factorio 2.1 and disposable saves to qualify platform placement, cargo fidelity, force reset, surface regeneration, UI visibility, and save/load resilience.
