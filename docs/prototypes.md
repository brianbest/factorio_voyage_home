# Data-stage prototype guide

This document describes the prototypes that make **The Voyage Home** visible and craftable in Factorio 2.1 with Space Age. Runtime mission logic is documented separately in the architecture guide.

## Prototype inventory

| Prototype | Type | Purpose |
|---|---|---|
| `tvh-interstellar-signal` | Technology | Script-triggered discovery milestone completed after the configured Shattered Planet distance. |
| `tvh-interstellar-navigation` | Technology | 5,000-unit endgame research that unlocks the vessel recipe and staging location. |
| `tvh-interstellar-staging` | Space location | Stoppable, surface-less destination beyond the Solar System Edge. |
| `tvh-interstellar-corridor` | Space connection | Configurable route from the Solar System Edge to staging. |
| `tvh-interstellar-vessel` | Item, recipe, container | One-ton launchable item and 48-slot platform cargo container. |
| `tvh-arrival-cache` | Container | Script-created, 48-slot cache for cargo restored on the new Nauvis. |
| `tvh-interstellar-vessel-crafting` | Recipe category | Machine-only crafting category added to the electromagnetic plant. |

## Startup settings

| Setting | Default | Range | Data-stage effect |
|---|---:|---:|---|
| `tvh-discovery-distance-km` | 100,000 km | 1,000–4,000,000 km | Sets the corridor prototype length and the scripted technology's trigger description. Runtime discovery must use the same startup value. |
| `tvh-cargo-capacity-multiplier` | 1.0 | 0.1–100.0 | Has no prototype-stage weight restriction. Runtime code multiplies `prototypes.utility_constants.default.default_rocket_lift_weight` by this value. |
| `tvh-development-commands` | Off | On/off | Enables administrator-only progress-changing commands. Status and dry-run diagnostics remain available when disabled. |

Startup settings are intentional: changing either value changes the rules of the save and therefore requires Factorio to reload prototypes.

## Progression gates

```text
Travel toward Shattered Planet
            │
            ▼
  Interstellar Signal
  (scripted technology)
            │
            ▼
 Interstellar Navigation
   (science research)
        ┌───┴────────────────┐
        ▼                    ▼
Vessel recipe        Staging location
```

Interstellar Signal has no science-unit cost. Runtime code completes its `scripted` research trigger exactly once. Interstellar Navigation consumes all specified endgame science packs, including Promethium science, and is the sole data-stage unlock for both the vessel and staging point.

## Vessel construction and storage

The vessel recipe is assigned only to `tvh-interstellar-vessel-crafting`. During `data-updates.lua`, that category is appended to the Space Age electromagnetic plant. This makes the ten-minute recipe machine-only without creating another large crafting machine.

The placed vessel deliberately uses a **normal** inventory rather than Factorio 2.1's `with_weight_limit` container inventory. The native weight-limited inventory prevents players from inserting excess weight; the product specification instead permits an overweight vessel and requires the readiness UI to explain why jumping is disabled. Runtime code must therefore read `LuaInventory.weight` and enforce the configured capacity at final confirmation.

The prototype has a pressure surface condition of zero as an early placement guard. Runtime placement validation remains authoritative because a non-platform custom surface may also have zero pressure. Runtime code must still check `entity.surface.platform`, progression phase, and the single-vessel rule, then refund rejected construction.

## Corridor asteroid profile

The corridor copies the live `solar-system-edge-shattered-planet` prototype's asteroid definitions after Space Age loads. It selects the opening fraction represented by:

```text
corridor length ÷ vanilla connection length
```

That opening segment is remapped across the corridor's normalized 0–1 distance. With the default 100,000 km setting, the corridor mirrors the first 2.5% of the vanilla four-million-kilometre route. This preserves the intended early-route difficulty and automatically follows compatible adjustments that Space Age makes to the source prototype.

The staging point itself has no parked asteroid spawns. Arrival is intentionally safe so an incomplete platform can wait or schedule a return trip without a hidden reset timer.

## Placeholder graphics

The MVP contains no binary art package. It layers and tints stable vanilla and Space Age icons, and scales the vanilla steel-chest sprite for the two containers.

| Object | Placeholder visual |
|---|---|
| Vessel | Blue steel-chest silhouette with a quantum-processor badge. |
| Arrival cache | Amber steel-chest silhouette with a Promethium badge. |
| Staging point | Cyan Solar System Edge marker with a Promethium badge. |

These placeholders are deliberately centralized in `prototypes/icons.lua`, so final art can replace them without changing technology, recipe, or runtime code.

## Runtime contract

Runtime modules may rely on these guarantees:

- Vessel and arrival-cache inventories contain exactly 48 slots at normal quality.
- Vessel quality does not increase inventory size.
- The vessel item has stack size 1 and weighs one default rocket load (1,000 kg).
- Vessel cargo can exceed the mission weight limit; runtime readiness is authoritative.
- The arrival cache is prototype-minable but can be made temporarily indestructible and unminable through entity runtime properties while cargo restoration is in progress.
- Staging is a stoppable space location, not a planet, and creates no planetary surface.
- Interstellar Navigation unlocks the staging location through a standard `unlock-space-location` technology effect.

## Prototype verification checklist

Perform these checks against Factorio 2.1 with Space Age enabled before release:

| Check | Expected result |
|---|---|
| Load the mod from a clean profile. | Prototype validation completes with no errors or missing sprites. |
| Inspect Interstellar Signal in the technology tree. | The trigger text includes the configured distance and no science-unit cost. |
| Inspect Interstellar Navigation. | The cost is 5,000 × 60 seconds and lists all eleven specified packs. |
| Inspect an electromagnetic plant after navigation research. | The Interstellar Vessel recipe is available there and cannot be hand-crafted. |
| Launch a vessel item. | One normal-quality item consumes one full default rocket lift capacity. |
| Load more cargo than the mission capacity into a vessel. | Insertion succeeds; runtime readiness reports overweight. |
| Place a vessel on platform foundation. | The 5×5 entity is selectable, minable, blueprintable, and exposes 48 slots. |
| Attempt planet placement. | Prototype pressure gating and runtime validation prevent the vessel from remaining there. |
| Open the Space Map before navigation research. | Staging is locked. |
| Complete navigation research. | Staging appears beyond the Solar System Edge and can be used in a platform schedule. |
| Travel the corridor. | Its length equals the startup distance and the asteroid curve resembles the beginning of the Shattered Planet route. |
| Stop at staging. | The platform waits safely and can schedule a return to the Solar System Edge. |

## API basis

The implementation was checked against Wube's official Factorio 2.1.14 prototype definitions and API documentation. In particular, it uses the 2.1 `categories` recipe field, `scripted` technology trigger, `unlock-space-location` technology effect, stoppable `space-location`, `space-connection` asteroid definitions, fixed container inventory size, item weight, and Space Age pressure surface condition.
