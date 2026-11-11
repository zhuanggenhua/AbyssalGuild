# Autonomous mobs and production

`mob_ai.gd` independently implements the control flow of source `CardAI`, its
`CardCombatant.EnterCombat/LeaveCombat` lifecycle, and the point-validation rule
of `Board.IsPointValid`. The audited source revision is
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`; no Unity runtime was launched.

## Integration contract

1. Construct after session world/combat helpers: `ai.configure(session,
   session.world, scene_name)`. Configuration reads the selected scene's actual
   CardManager category/prefab mapping and scans imported prefab components for
   CardAI. This avoids assigning AI to all characters or guessed categories.
   Aggressive Mob prefab overrides use the same source precedence. Real Main
   and Island Mob prefabs have AI; Character prefab does not.
2. Configure `point_validator(candidate: Vector2, stack_id: int) -> bool` from
   the board/view. Coordinates are source X/Z. `AI.point_in_board(point, bounds,
   footprint, top_margin)` reproduces the source boundary test when provided
   the actual board bounds, stack width and source TopCard depth. Without the
   callback, movement is rejected rather than inventing physical board bounds.
3. Optionally configure `combat_geometry() -> Array` of `{id, ongoing,
   has_player, position: Vector2}` snapshots from actual combat rectangles.
   Rectless combats must be omitted. Without geometry, mobs can hunt and begin
   fights but cannot seek/join existing fight rectangles.
4. Optionally configure `produce_spawner(guid, position, ignored_stack_id)` to
   connect production to source-style automatic nearby-stack attachment and
   overlap handling. The default calls `session.spawn_card`, creating the card
   at its producer's position in a new stack.
5. Call `tick(scaled_delta)` during active gameplay, once per frame alongside
   crafting/combat. Do not additionally call `world.tick_production`, which
   would process the same timers twice. Global pause, day-end pause and speed
   scaling belong to the session caller.
6. Call `reset()` on a new game. Card-created events register new AI-bearing
   cards automatically. For a native AI checkpoint, restore with `apply_state` and do **not** call
   `resync` during restore. For a legacy save without AI state, reset first;
   the next active tick recreates missing AI and consumes its startup RNG draws.

`configure` disconnects its previous session's signal when reused. It holds a
weak session reference and does not edit or own session persistence fields.

## Implemented behavior

- Both movement and production start after independent 0.5–1 second random
  delays plus their respective full first interval. Movement defaults from
  actual CardSettings are interval 5, radius 1, attempts 5. The normal loop
  resets each wake to a full interval, with no huge-delta catch-up bursts.
- Dragged, crafting, or engaged cards do not move or produce. A blocked wake is
  spent rather than banked. Source CanMove does **not** reject a mob just because
  it is stacked or another card is above it.
- A passive card retained by the first enclosure's raw list-position capacity
  skips movement only. It remains eligible to produce.
- Before autonomous movement, a card is detached into a singleton stack, and
  the old stack is rechecked for a recipe. Only that card detaches, not all
  later cards as in a player split-stack drag.
- Patrol draws a random direction and tests at most MaxAttemptsPerMove points
  exactly MoveRadius away. Invalid attempts leave the stack in place.
- Aggressive mobs prioritize relevant ongoing combat geometry within their
  aggro radius, joining at attack radius × 1.5, otherwise moving one full radius
  toward its rectangle. Next they hunt the nearest free Player-faction card.
  As in the audited source, the player hunt ignores its radius parameter.
- In attack range, Character/Mob members of the two stacks start combat with
  `player_is_attacker = false`. Entering combat stops both AI loops immediately;
  ending combat restarts their initial delays. Membership reconciliation also
  handles combat additions/removals without a public event.
- Production creates the configured produce card at the producer position.
  Aggressive cards never start or continue production. Destroyed AI cards are
  removed during the next tick's reconciliation.

## Deliberate presentation limits

Movement updates logical stack/card positions immediately; Unity's DOTween
motion, sway, particles, sounds, camera motion, and overlap animation are not
recreated here. Frame-delta scheduling combines initial coroutine startup delay
and first interval into a single logical timer rather than emulating Unity's
individual WaitForSeconds yield/frame quantization. RNG distributions match;
Unity and Godot random streams are not claimed bit-identical.

Board blend-shape geometry and real combat-rectangle layout must be supplied by
the view. The helper does not manufacture a centroid or fixed world bounds and
call it source parity. Contact-driven manual combat, rectangle overlap/merging,
and view selection/drag interactions remain outside this autonomous controller.

## Tests

`tests/godot/test_mob_ai.gd`: 32 checks cover real prefab eligibility and settings,
first movement timing, fixed radius, singleton detachment, enclosure/production,
stacked production, drag/craft gates, patrol rejection attempts, missing board
adapter, distant player hunting, battle initiation and side designation, combat
join geometry, stop/restart lifecycle, dead-state cleanup, board boundaries,
and load/reset reconciliation. Run with Godot 4 headless and writable XDG roots.

## Native deterministic checkpoint extension

The Godot-native save intentionally differs from Unity's coroutine restart:
`save_state()` preserves each live AI card's running flag, movement timer and
(optional) production timer. This retains precise native random-stream and
remaining-time continuity. It is not a claim of Unity save-format compatibility.
Serialization is read-only and consumes no random draws. Dead records are
excluded. If a card joined combat between ticks, serialization records its
stopped state without mutating live state or drawing randomness, matching the
stop that the next live reconciliation would perform.

`stage_state(raw, cards)` validates scene identity, complete and unique coverage
of actual AI-eligible staged cards, numeric finite nonnegative timers, strict
boolean running flags, and required production timers only for running passive
producers. Invalid state leaves live agents, world timers and RNG unchanged.
Its result includes `unstacked: []` for SaveCodec compatibility.

After staging all subsystems, SaveCodec must call
`AI.validate_combat_state(staged_ai, staged_combat.membership)` (empty membership
if no combat state exists). Running AI in combat is invalid. A stopped agent
outside combat may be awaiting its next-tick restart and is valid. `apply_state`
copies staged dictionaries directly without resync or RNG. Apply world state
**before** AI state because world restoration clears production timers.

JSON serialization must use `JSON.stringify(value, "", true, true)` to retain
full floating-point precision, as the native SaveCodec already does. Tests
verify this roundtrip and the unchanged RNG state. Current AI suite: 52 checks,
including 20 checkpoint/validation checks in addition to the original 32.

## Session/view integration

Session configures this helper by scene, clears it on New, and ticks it with
scaled gameplay time before logical combat. Native saves stage/apply world then
AI and validate combat membership, preserving timers and RNG. Campaign swaps
reconfigure scene prefab eligibility before restore. The board supplies source
footprint/bounds validation and an average-fighter combat-position adapter; this
last adapter is not an exact recreation of animated source combat rectangles.
