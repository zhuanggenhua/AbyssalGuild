# Combat rectangle and fighter target geometry

Independent static rewrite of the locked StackCraft source revision
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`:
`Combat/UI/CombatRect.cs`, `Combat/CombatManager.cs`, `Combat/CombatTask.cs`,
`Card/Components/CardController.cs`, `Card/Components/CardAI.cs`, and
`Core/Board.cs`. Source is inspected only; no Unity execution or original source
files are included here.

## Model API and integration

`combat_layout.gd` is pure and does not mutate session, combat or scene nodes.
Input fighter records contain `id`, source-world X/Z `position: Vector2`,
`size: Vector2` (CardInstance.Size, including the card margin), and `faction`.
Use `BoardLayout.prefab_card_size` on the category-selected imported prefab rather
than substituting sprite dimensions.

1. `imported_config(catalog.data, scene_name)` resolves CombatManager's rectangle
   prefab reference, that prefab's transform, WorldCanvas and its ancestor
   transforms from private imported prefab documents. Quaternion/scale composition
   determines the local rectangle XY axes projected onto world XZ. Missing or
   ambiguous canvas/rectangle data returns an error, not a guessed orientation.
2. `initialize(attackers, defenders, config, board, top_margin)` computes the
   fighter-average center, clamps the full rectangle to the board and restricted
   top margin, then returns `center`, `cell`, `size`, `positions`, `bounds`, side
   ID lists, `has_player`, and configuration. The caller can render each fighter
   at `positions[id]` and supply `bounds` to BoardLayout's stack overlap solver.
3. Store that returned state per fight. On additions/removals,
   `update_layout(previous, attackers, defenders)` preserves the initial center
   and initial cell spacing, recomputes rectangle size from the current first
   surviving card, and updates slots. It does not clamp again, matching source.
   Reinitializing every frame would incorrectly move centers/reseed spacing.
4. `task_at_position(layouts, position)` uses registration order and exact local
   rectangle containment for drag-to-join. `closest_relevant_combat` uses strict
   center-distance aggro range and requires player involvement;
   `can_ai_join` uses inclusive 1.5 × AttackRadius distance to that center.
5. `drop_result` permits fleeing only outside the rectangle for the player
   attacking side, and clamps the singleton drop position. Other drops snap back
   to the cached slot. The caller performs the actual CombatSystem.flee/removal.
6. `survivor_positions` clamps CURRENT fighter positions as singleton stacks.
   Source does not invent a new spread formation on exit. If two units share a
   current position, this function leaves equal outputs; separate overlap work
   must not be silently folded into source EndCombat target math.

## Exact distinctions

- Source CombatRect.Margin is static readonly `(0.1, 0.1)`. The prefab has a stale
  serialized `margin` field, but current code does not read it. No separate row
  gap or configurable column count exists in this revision.
- Each cell is initial first-attacker CardInstance.Size + combat margin. Width
  spans the larger side count, height spans exactly two cells, with two outer
  margins added to rectangle dimensions. Each row is independently centered.
- Attackers occupy negative local Y and defenders positive local Y. Faction does
  not flip the rows: a mob-initiated attack still occupies the attacking row.
  Imported WorldCanvas rotation determines which world-Z direction that means.
- Manager bounds use rectangle sizeDelta × lossyScale centered on the transform.
  They do not calculate rotated corner AABBs or adjust for noncentral pivots.
  Pointer containment instead inverts the transform and uses the rectangle pivot;
  minimum edges are included and maximum edges excluded.
- `overlaps` reproduces Unity Bounds.Intersects, including touching edges. This
  differs from the board solver's positive-penetration test.
- `potential_bounds` for pre-start merge detection averages current positions,
  counts Player versus all other factions, uses the first input card size, and
  does NOT apply canvas scaling or board clamping. That source distinction is
  preserved rather than silently making preview and live rectangles identical.
- UpdateLayout changes rectangle dimensions using the new first card's size but
  retains cached original cell size. This is observable with heterogeneous card
  sizes and is intentionally retained.

## Verification and limits

`bash tools/test_godot.sh res://tests/godot/test_combat_layout.gd`

Synthetic fixtures test dimensions, asymmetric rows, center averaging, transform
scale/rotation, clamping, resize behavior, containment edge semantics, merge edge
contact, AI ranges, registration order, flee permissions and survivor placement.
When private imported data is present, the same test additionally resolves Main
and Island configuration. These private source-data checks do not publish data.

The imported transform adapter handles transforms and ancestors within each
prefab. It does not apply arbitrary scene prefab-instance transform overrides or
external scene parents. Static inspection of the locked Main/Island UIRoot
instances found no quaternion/scale overrides to the relevant ancestor chain and
both are root instances, so this limitation does not change their result.
Changed/custom scenes with such overrides need an expanded adapter first.

No jump/projectile animations, attack/return/death delays, UI art, color, sound,
camera shake, live combat membership changes or automatic merge mutation are
implemented here. Correct target geometry is not a claim of visual/runtime parity.

## Live board integration

The board now initializes/updates per-task state, draws a simple generated
rectangle and assigns target fighter slots. It passes bounds to stack separation
and center to AI, supports drag-to-join/start and attacker-only flee, and clamps
survivors when combat ends. Native saves persist only center and initial cell
spacing; scene configuration and derived positions are reconstructed on Continue.
The 32-check combat-board suite covers these paths. Generated rendering,
target-pose collider queries and immediate repositioning are not Unity animation
or exact physics-hit ordering.
