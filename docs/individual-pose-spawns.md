# Individual-position spawn and split follow-up

This slice uses the derived Session pose API without rewriting saved positions.
It follows the original source statically; Unity was not launched.

## Changed consumers

- `Session.kill_card` captures the dying card's settled target before publishing
  the kill notification, unequipping, or removing combat membership. Character/Mob
  loot starts at that captured individual position instead of a stacked root.
  `CardInstance.Kill` is the source reference: loot uses its transform position.
  Existing event order, class restoration, loot eligibility and random draws stay
  unchanged. Snapshotting before synchronous cleanup prevents a changed index
  from relocating loot to a neighboring member's position.
- `SpecialRecipes._grow` captures the seed's target before consuming the grower.
  The seed tail starts there plus source collider width/margin. This matters when
  grower removal changes the seed's index: source `CardStack.DestroyCard` starts
  animated reflow, but `GrowthRecipe.Execute` immediately calls `SplitAt` using the
  seed's still-current transform. The model now retains that pre-consumption pose.
  The subsequent index-zero refusal still applies, so destroying the grower does
  not force a split when the seed becomes the root.
- The partial-tail chest branch of `Session.move_to_stack` creates the dropped
  tail at the incoming member's target. Excess coins left after a limited deposit
  no longer jump to the old source stack root.

## Intentionally unchanged

Grown result spawning remains at the crafting stack root, as do ordinary,
exploration and research outputs. Pack draws remain at the pack stack root with
the existing height hint. Growth still transfers the seed and its whole tail,
with stored member positions in the existing root-valued representation and
subsequent offsets derived exactly once. Serializer and save schema are untouched.

Equipment individual detach/unequip already uses settled targets from the prior
slice. Chest click withdrawal is singleton-gated and receives an explicit spawn
position from the board; the board consumer should use `card_target_position`
plus source width. No new world withdrawal API or board edits are made here.

## Combat clock bridge

At the combat worker's integration boundary, `Session.tick(delta)` passes both
clocks while preserving the existing AI-before-combat order on playing frames:

- Paused or outside playing: `combat.tick(0, delta)`.
- Playing: first `ai.tick(delta * speed)`, then `combat.tick(delta * speed, delta)`.
- Nonpositive delta returns before either clock.

This permits source real-time attack travel/return to finish during pauses while
scaled action progress and death waits stay stopped. The old single-clock combat call is replaced in its original position, not moved
ahead of AI; the source does not establish a mandatory MonoBehaviour update order. The combat subsystem's action state machine and batch
pose snapshots are owned by the separate combat slice, not duplicated here.

## Validation

Godot 4.6.3 `test_individual_pose_spawns.gd`: 26/26 synthetic checks. Covers loot
position and event/RNG preservation, notification-driven reindexing, kept/consumed
grower paths, complete seed tails, unchanged root output, save roundtrips,
index-zero refusal, limited chest deposit, intentional pack root behavior, and
Session's two-clock dispatch and AI-before-combat order across pause/day phases,
speed and zero delta.

The six imported growth recipes previously asserted the old root-Z displacement.
Their shared expectation now includes the source seed's -0.18 step, changing
`(3.9,4)` to `(3.9,3.82)`. All 445 special-recipe checks pass, plus scene-specific
special recipe 20 and runtime 76. Remaining board geometry/render/input acceptance
and Unity animation timing are not claimed by these tests.
