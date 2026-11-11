# Source-timed Puff requests

This checkpoint connects model presentation requests to the source call sites. It does not change the asynchronous cycle's stages, clocks, save format, nutrition, encounter selection, quest completion, or gameplay random draws. Rendering and sound playback are separate adapters; these model tests run without either. Original source and assets remain private.

## Event contract

- `puff_requested`: `{card_id: int, position: Vector3}`. `position` uses source coordinates and preserves individual height. Reflect Z once in a Godot view adapter. The request identifies the card that owns the source effect, not a new output card.
- `recipe_pop_requested`: `{card_id: int, position: Vector3, recipe_guid: String}`. This is the base recipe's explicit Pop cue. It immediately follows its Puff request, before ingredients are consumed, including recipes without an output.
- `crafted` remains a post-creation gameplay notification. It is no longer the correct audio trigger. UI consumers must remove their old `crafted -> Pop` mapping to avoid duplicate or late Pop playback.
- `card_killed` retains its early gameplay meaning. Do not use it to trigger Puff: equipment, combat cleanup, and loot still follow it.

`GameSession.request_puff(id, sampled_position)` accepts an optional already captured source pose. Otherwise it samples the existing current-pose adapter, with an individual settled-pose fallback. It suppresses requests for absent cards and does not draw RNG, serialize effects, or gate gameplay on a listener or visual resource. Base recipe Pop is emitted independently of rendering or audio resource availability. A view can prefer its still-existing card's current world pose at the event, then fall back to the payload after removal.

The Kill path preserves its existing pre-cleanup captured death pose, including an explicit feeding/combat pose supplied by the caller. This checkpoint does not alter loot placement to implement a cosmetic effect. Encounter Puff retains the asynchronous controller's existing pose sampling after camera completion.

## Audited source boundaries

Paths below are relative to the private StackCraft asset root at the locked source revision. Only references and independently written code/tests are published.

| Site | Source reference | Required order |
| --- | --- | --- |
| Kill | `Scripts/Card/CardInstance.cs:483–507` | Early killed notification, equipment/combat cleanup, loot creation, Puff, then removal. |
| Base recipe | `Scripts/Crafting/Definitions/RecipeDefinition.cs:65–86` | `TopCard` Puff, Pop, ingredient consumption, optional output creation, crafted notification. `CardStack.cs:17` defines TopCard as member zero. |
| Deposit | `Scripts/Card/Behaviors/ChestLogic.cs:34–42,54–81` | Validate dropped TopCard, Puff on chest, then capacity/deposit loop. A full valid chest still puffs. |
| Withdraw | `ChestLogic.cs:106–126` | Decrement stored coin, refresh display, Puff on chest, optional board coin creation. `spawnOnBoard=false` also puffs. |
| Vendor chest payment | `Scripts/Trading/PackVendor.cs:214–251` | Call non-board withdrawal once per paid coin, hence one Puff after each decrement. Loose payment coins use DestroyCard, with no Puff. |
| AI production | `Scripts/Card/Components/CardAI.cs:304–316` | Create produce, then Puff on producer. A non-null produce definition still requests Puff if the factory returns no card. |
| Encounter | `Scripts/Encounter/EncounterManager.cs:125–144` | Create one card, finish optional camera focus, Puff, then wait 0.5 real seconds. |

Base-recipe overrides for Growth, Research, Exploration, and Travel do not call the base implementation. They do not receive its Puff or Pop. Ingredient DestroyCard and sale likewise do not imply Kill or Puff. Fully depleted food, exhausted packs, and starvation do use Kill; partially consumed food does not.

The live AI path and the explicit WorldRules production utility both emit the producer request after spawning. The native global `buy_pack` convenience follows the same per-coin chest cue as the source-shaped `pay_vendor` path. These loops preserve their existing single final stats/purchase notifications instead of inserting the standalone withdrawal utility's native stats notification between coins. No unrelated chest audio or transaction semantics are changed here.

## Verification

Run `bash tools/test_godot.sh res://tests/godot/test_puff_events.gd`.

- 74 synthetic checks pass in an isolated project containing only scripts and tests, with no data/assets links. An explicit message reports skipped private checks.
- 87 checks pass with the private source catalog. These include actual Anvil multi-input crafting, Wooden Chest at full capacity, non-board withdrawal, Cow producing Milk, all four recipe overrides, and successful Main-to-Island travel without inherited base cues.
- Event observers record live card IDs, stored coins, equipment owners and combat membership at each boundary. They distinguish pre-consumption from post-consumption recipe effects, early killed from late Puff, and per-coin decrement from a bulk payment effect.
- Source-ordered timing tests cover depleted versus leftover food, exhausted packs, starvation and encounter focus completion before the final wait.
- Cosmetic independence checks compare saved model state and RNG with and without an observer, assert no session/global RNG consumption by a request, and cover missing/invalid pose adapters and safely missing card references.
- Affected existing suites pass: runtime 76, quest integration 70, world rules 76, mob AI 55, vendor payment 20, special recipes 445, trade currency 40, combat/equipment 60 and cycle timeline 127. The source event suite also passes through the engine-error/leak guard.

These checks establish model request boundaries, not a visual or listening acceptance result. The separate `puff-simulation.md` documents particle metadata/math and remaining renderer approximations. Settled fallback does not claim to reproduce an unobserved moving Unity transform. Source exceptions from vanished references are not reproduced; missing cosmetic owners are safely ignored. The synchronous `WorldRules.finish_day` utility remains a rule-test helper, not a replacement for the live cycle's timed encounter effects.
