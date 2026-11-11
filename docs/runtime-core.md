# StackCraft core runtime slice

This is an original GDScript implementation based on static inspection of the authorized baseline `CardLoop` commit `a11a89b04cea8370476f2559b639bb9b4cbc08d8`, under `Assets/StackCraft`. Unity was not launched. No C# or third-party artwork is included in these runtime files.

## Public entry points

- `catalog.gd`: `load_file()`, `get_definition(guid)`, `fields(guid)`, `find_by_name(name, group)`, `settings(class)`, `stacking_rules()`. Serialized fields remain untouched; `stacking_rules()` decodes Unity's little-endian int32 hex string on demand.
- `game_session.gd`: `configure(catalog, seed)`, `start_new_game()`, `spawn_card(guid, position, target_stack)`, `open_pack(card_id)`, `can_stack(bottom_guid, top_guid)`, `move_to_stack(card_id, stack_id)`, `split_stack(card_id, position)`, `tick(delta)`, `stats()`, `sell_card(id)`, `sell_stack(id)`, `buy_pack(guid)`, `pay_vendor(guid, stack_id)`, `end_day()`, `start_day()`, `kill_card(id)`.
- `card.gd`: instance `id`, `definition_guid`, `base_definition_guid`, `stack_id`, `uses_left`, `nutrition`, `health`, `position`, `stored_coins`.
- `stack.gd`: ordered bottom-to-top `card_ids`, `position`, `recipe_guid`, elapsed recipe `progress`, `paused`.
- Session exposes `cards`, `stacks`, `discovered_recipes` keyed by original recipe ID, `completed_quests`, `vendor_payments`, `day`, `elapsed`, `day_duration`, `phase`, `paused`, `speed`. Signals are `changed` and `event_occurred(kind, payload)`.

All positions use the original Unity board-plane coordinates `(x,z)` in world meters. The renderer maps the second component to its chosen Godot Z direction. The main scene starter uses the original center `(-3.5,0.6)` and 1.2-radius sphere projected to the board. Pack/crafting output is initially at the source stack's board position; collision resolution, spawn attachment, animations and vertical placement are rendering/board responsibilities. Do not treat these positions as pixels.

## Rules implemented

1. Main new game creates only Starter. Each click draws one slot, in order: Villager, Berry Bush, Rock, Wood. Uses are slot count, independent of card durability.
2. Pack slots first roll recipe chance when a possible-recipe list exists, filter undiscovered nonempty IDs, mark the chosen recipe discovered, then emit a recipe card. If no undiscovered candidate remains, use weighted entries. Valid entry weights clamp to at least one. RNG is injectable by seed, reproducible within Godot, not bit-compatible with Unity's RNG.
3. The 12-by-12 serialized stacking matrix supports None, CategoryWide and SameDefinition. Stack movement moves the selected card and its tail; follows the source call's incoming-bottom/target-bottom ordering. Active strict crafts reject joins. Workstations accept only required ingredient definitions and preserve progress.
4. Ordinary RecipeDefinition matching requires exact non-resource counts and no unrelated cards. Resources permit surplus count. `allowExcessIngredients` permits surplus/unrelated cards. Matching recipes are chosen by nonnegative random weights with uniform zero-total fallback. Starting a craft discovers its recipe.
5. Craft progress uses seconds, respects pause and speed, and cancels when required composition breaks. Consume reduces uses; Keep does not change a card; Destroy ignores durability. Only required counts are consumed. Results spawn outside the processing stack. Consuming/continuous crafts repeat when valid, except Character/Mob outputs, preventing infinite breeding.
6. Selling checks sellability and rejects coin-filled chests, creates physical Coin instances, and supports whole-stack qualification. `buy_pack` is an all-at-once convenience using physical currency/contained coins, with quest gates and existing installment credit. `pay_vendor` follows source dropped-stack partial payment and retains unpaid progress. The UI must expose only scene-offered packs, not Starter or arbitrary catalog packs.
7. Nutrition, currency, character count and owned-card stats exclude packs/currency from capacity and apply LimitBooster boostAmount. Feeding chooses the nearest positive-nutrition Consumable per character, detaches only that food card from a multi-card stack and cancels the old craft, moves it to the eater, retains excess nutrition, heals proportionally using Unity midpoint-to-even rounding, and kills a character if any required hunger remains unfilled. Character/Mob deaths draw one source loot entry using positive weights (including null-card probability); sales, crafting destruction and consumption do not trigger death loot. Default need is 2 and capacity 24, read from CardSettings.
8. At 120 seconds (configurable), tick enters `feeding` and pauses simulation until `end_day()`. After feeding, `game_over`, `selling` or `ready` is selected. Excess sales unblock `ready`; explicit `start_day()` increments the day. This slice omits the encounter phase between selling and ready.

## Deliberate boundaries, not completed parity

Special `ExplorationRecipe`, `GrowthRecipe`, `ResearchRecipe`, and `TravelRecipe` actions are not executed as ordinary recipes. Combat, equipment/class changes, mob AI/production, chest deposit/withdraw UI, enclosure behavior, quests and rewards, encounters, world travel, save/load, friendly mode and Unity physics are not implemented here. `completed_quests` is an integration input, not an invented achievement counter. Chest coin storage is represented for payment/sale eligibility but the full chest behavior is not provided. Dynamic recipe cards retain source ID/title/category/value conventions; tooltip formatting is left to UI.

Automatic nearby spawn merging and physics-based spawn separation are not modeled. Source static positions must be rendered/resolved by the board rather than changing model units. Do not market the current build as complete gameplay parity.

## Verification

Run with Godot 4.6 (tested 4.6.3):

```sh
HOME=/tmp/godot-runtime-home XDG_CACHE_HOME=/tmp/godot-runtime-cache \
XDG_DATA_HOME=/tmp/godot-runtime-data \
godot --headless --path . --script res://tests/godot/test_runtime.gd
```

Use writable HOME/XDG directories in restricted containers. The first attempt using the default unwritable Godot user directory failed before script startup; the writable-directory run passed. The test is independent of a UI scene and returns a nonzero exit code on assertion failure.

Tests cover source-data loading; matrix decode and same-definition restrictions; exact starter sequence/exhaustion; recipe start/progress/pause/auto-repeat; Keep/Consume/Destroy; surplus matching; weighted zero/empty behavior; sale and rejection; vendor installments and purchases; partial nutrition/healing; starvation; excess-capacity selling and explicit day advancement. This is executable domain evidence, not evidence of visual or full-game parity.

For a fresh checkout or to isolate logic tests from the UI, run `bash tools/test_godot.sh`. This creates a temporary minimal Godot project pointing at the same files, with writable user-data directories. Imported data is required; the command fails rather than substitute sample content.
