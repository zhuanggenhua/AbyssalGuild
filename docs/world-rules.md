# World rules: source parity and integration

This is an independent GDScript implementation audited against source revision
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`. No original C# code is included.
Audited classes: `EncounterDefinition`, `EncounterManager`, `DayCycleManager`,
`ChestLogic`, `EnclosureLogic`, `CardAI`, `CardStack`, and `CardManager`.

## Lifecycle and scene configuration

`WorldRules.configure(session, scene_name = "Main")` reads the selected scene's
serialized EncounterManager and TradeManager from the imported catalog. It does
not merge encounter lists across scenes or fall back to all encounter assets.
Main lists Villager, Slime, Goblin in that order; Island lists no encounters and
uses Coral instead of Coin. `reset()` clears completion/day/production state.

`export_state()` / `save_state()` and `restore_state(dictionary)` persist the scene, completed
Encounter **IDs** (not asset GUIDs), and processed ending days. A scene mismatch
is rejected. `stage_state(raw, cards)` validates without mutation, and
`apply_state(staged)` commits validated state for the transactional SaveCodec.
Unknown/repeated completed IDs and nonpositive, fractional, infinite, or repeated
processed days are rejected. Store this state independently for each scene. Production timers
are deliberately transient, matching source coroutine restart rather than
inventing saved production progress. Card stored coins remain card save data;
source RestoreCoins does not clamp a saved amount to current chest capacity.

## End of day

Call `finish_day(day, friendly, bounds, top_margin)` **after** surviving feeding
and resolving excess-card selling, **before** entering the new-day ready panel
or incrementing the day. Never call it on game over. The helper claims the day
before emitting/spawning, preventing duplicate execution even if notifications
reenter it. No-encounter days are claimed too. Save the guard when saving an
intermediate ending-day phase.

The optional bounds is a `Rect2` in source X/Z world coordinates. `null` means
no Board, which reproduces source origin spawning, not inferred dimensions.
The default top margin is 1.5; scene edge padding is read from EncounterManager.
Spawns respect edge padding and the source's additional one-unit top offset.
Each spawned card has a separate stack (source RefuseAll).

Selection rules:

- Eligibility uses total board cards excluding equipped/unregistered gear,
  completed one-time IDs, aggressive/friendly mode, and inclusive day rules.
- Board-card limit is tested before spawning; a multi-card encounter can take
  the board over the limit. Count is not a post-selection cap.
- Every eligible encounter rolls in serialized order, even if an earlier one
  will win. RNG comparison is inclusive (`roll <= chance`).
- Higher explicit priority wins, then SpecificDay, Recurring, Range, MinimumDay.
  Equal keys preserve serialized order. Only one winner executes.
- One-time completion is marked before spawning. A notification is returned in
  the result and emitted with the `encounter` event; modal display, camera
  focus, puff effects and realtime presentation delays remain UI concerns.
- A zero recurring divisor is rejected defensively rather than throwing.

`select_encounter(day, friendly, optional_roll_callable)` is selection only.
It consumes random rolls but does not execute or mark completion. Do not use it
for a UI preview before `finish_day`, because that would change the RNG stream.

## Chest integration

`deposit_stack(chest_id, stack_id)` returns `{handled, deposited}`. Intercept a
chest drop before ordinary stack merging. The dropped source **TopCard** (`Cards[0]`, despite ambiguous source comments) must have
the scene currency's BaseDefinition. Once accepted, valid coins anywhere in the
stack are consumed in ascending list order until capacity; unrelated and excess cards
remain. Each card is one currency unit. A full chest still reports `handled`
when the top coin is valid, matching source OnStack. Destruction is not Kill:
there is no death event or loot. An active crafting task on a modified dropped
stack is canceled, as in CardStack.DestroyCard.

For a click, first require `can_click_chest(id)`, then call
`withdraw_coin(id, true, spawn_position)`. The caller computes one card-width
to the right and applies Board placement rules. The source only allows click
withdrawal for singleton chest stacks. Trade consumption instead calls
`withdraw_coin(id)` without the click gate and does not spawn a card.
Withdrawal needs a known scene currency and positive balance. Stored coins
must still count toward money stats and prevent selling nonempty chests.

## Enclosures and AI decisions

`should_stay_in_enclosure(id)` finds the **first** enclosure in ascending
stack-list order. A passive card stays only at positions 1 through capacity above
that enclosure. Every intervening card uses a position, not merely mobs. Cards
below it, the enclosure itself, and aggressive cards do not stay. There is no
food cost, capture mechanic, or species restriction in this source behavior.

`can_act(id)` rejects dragging, an active crafting stack, or current combat.
Enclosure retention only suppresses movement, not production.

`start_production(id)` explicitly starts/restarts eligible passive producer
state with the source random 0.5–1 second startup delay plus its first complete
production interval. `tick_production(scaled_delta)` consumes game time, skips
blocked wakes (does not queue them), and produces at most once per frame/wake.
Pass zero when paused. Call registration only for actual AI-bearing cards, not
all cards with an inferred category. Removal cleans dead timers on next tick.

`aggressive_intent(id, combat_snapshots)` returns patrol, join/approach combat,
or attack/approach player. Snapshots are ordered dictionaries with `id`,
`ongoing`, `has_player`, `position: Vector2`; omit combats without source Rect.
Only player-involved ongoing combats strictly within aggro radius qualify;
join range is attack radius × 1.5. Existing combat always outranks a free player.
The nearest free Player-faction card is hunted **without** an aggro-distance
limit: the audited source accepts a radius argument but does not use it.
Equal-distance candidates preserve iteration order; attack range is inclusive.

These AI APIs are decisions and production support, not a full movement loop.
The caller still owns AI prefab lifecycle, 0.5–1 second movement startup delay,
MoveInterval scheduling, detachment, board-valid patrol attempts, movement
radius stepping, combat rectangle snapshots, initiating/joining combat, and
spawn auto-attachment/overlap resolution. Do not claim full autonomous movement
parity until these are integrated. Production currently uses the session spawn
API; automatic nearby-stack attachment is a separate placement concern.

## Verification

`tests/godot/test_world_rules.gd` exercises real scene configuration and
controlled fixtures for date boundaries, stable selection/RNG order, friendly
mode, one-time state, replay guards, spawn count/positions, chest gates and
capacity, enclosure raw positions, production timing/blocked wakes, and AI
combat/player selection. Run Godot headless with writable XDG data/cache/config
roots when the default home is restricted. No Unity editor or player is run.

## Integrated checkpoint

Session now owns `world`, configures it by scene, and executes encounters exactly
once after successful feeding/selling, before the next day starts. Friendly mode
is a saved preference. SaveCodec stages world state transactionally. The board
exposes coin-stack deposit and sole-chest withdrawal controls. Scene-specific
encounter progress is included in campaign travel saves. Dynamic board geometry
is supplied by the view; an absent adapter is not proof of source physics parity.
