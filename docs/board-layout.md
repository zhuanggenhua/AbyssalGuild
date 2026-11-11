# Source-based board layout helper

`scripts/model/board_layout.gd`
implements deterministic target-position math separately from Session and the
view. It was checked statically against the licensed local original at revision
`a11a89b04…`; no Unity runtime was launched. Original C# and generated private
data/media are not included in this change.

## Verified source behavior

- `CardInstance.Initialize`: logical size is local `BoxCollider.size.x/z` plus
  `CardSettings.Margin` (not collider world bounds, and not twice the margin).
  Settings in the imported original: margin `(0.1,0.1)`, step `(0,0.002,-0.18)`,
  spawn attach radius `1`, release attach radius `0.25`, solver budget `8`.
- `CardStack.Width/FullDepth`: the first array card (`TopCard` in original
  terminology) controls width/depth. Depth is its size plus `(count-1)*abs(step.z)`.
  Do not take the largest card dimensions. Original names conflict with some
  comments: `TopCard` is index zero, `BottomCard` is the last element. The existing
  Godot model describes these as bottom-to-top IDs; use its FIRST ID for footprint.
- Solver bounds are centered between the first and last target Z. Per-card target
  is root plus each card's own step times its index. The shared-source settings
  make the helper's single step equivalent for this project.
- `Board.ClampToBounds` accounts for the whole trailing stack at the negative-Z
  boundary. `EnforcePlacementRules` then lowers its positive-Z edge below the
  header and flattens Y. Header margin is `1.5`. `IsPointValid` intentionally checks
  only the first card depth; it is not equivalent to whole-stack containment.
- `CardPhysicsSolver.ResolveOverlaps`: each pass processes combat rectangles in
  enumeration order, then stack pairs in registration order (i,j with j>i).
  Touching edges are not overlap. Smaller penetration wins, ties choose Z.
  Unity `Mathf.Sign(0)` returns +1, so identical centers move rather than stall.
  Locked stacks stay fixed; otherwise both move half the correction. Each move
  immediately enforces board placement. This may prevent convergence at edges;
  the source stops at its iteration budget rather than finding a guaranteed fit.
- `CardManager.EnforceBoardLimits`: skip locked stacks, only change positions
  whose squared correction exceeds `0.001`, and invoke separation only if a stack
  moved. The unused arguments in the original ResolveOverlaps overload do not
  exclude a stack or limit solving to one combat rectangle.
- `PackInstance.OnClick/PullFromNextSlot`: lock pack stack; spawn at its target
  plus `(0,0.1,0)`; initialize/attempt attachment/resolve; consume slot; flatten
  and unlock any surviving pack. There is NO fixed sideways spawn offset.
  `CreatePackInstance` also calls normal initialization and attachment.
- `TryAttachToNearbyStack`: first gather `Physics.OverlapSphere` collider hits.
  Reject self, ignored stack, invalid crafting join and disallowed stacking.
  Deduplicate stacks, rank by the nearest member's actual 3D transform distance
  (not root distance), and retain the first candidate on an equal-distance tie.
  `RefuseAll` short-circuits attachment but not initialization's subsequent solver.

## Integration contract

Preload `res://scripts/model/board_layout.gd`. All planar Vector2 values are
**(world X, world Z)**; no screen-axis inversion occurs inside this helper.

1. Resolve the correct scene category prefab (aggressive mob override first,
   pack prefab for packs). Call `prefab_card_size(prefab, margin)` on its exported
   `referenced_prefabs` dictionary, or `card_size(raw_collider_size, margin)`.
   The first API returns zero when missing; the caller must report/handle missing
   source data, not mistake zero for a valid card. Prefab variants and transform
   overrides must be resolved by the importer/caller before passing the collider.
2. Build ordered snapshots with
   `stack_state(id, position, top_size, count, locked, step)`.
   Dictionary fields are `id`, `position`, `size`, `count`, `locked`, `step`.
   Supply board world-space `Rect2` and top margin from the current scene. The
   verified private mesh bounds are centered 12x8 at boost zero and 24x16 at 100;
   visual mesh adapter supplies interpolated/transformed bounds. Do not use the
   Unity renderer's oversized serialized AABB as the current baked mesh bounds.
3. On release use `enforce_placement(position, state, board, top_margin)`.
   Call `resolve_overlaps(states, combat_rects, board, top_margin, max_iterations)`
   where combat rectangles are already world XZ bounds. Write returned positions
   to matching Session stacks and synchronize member card positions via existing
   model paths. The input snapshots are not mutated. Result contains `stacks`,
   `iterations`, `separated_last_pass`. The last field reports work in the last
   pass, NOT proof of remaining overlap or proof of successful convergence.
4. On board shrink use `enforce_board_limits` with the same arguments. On spawning,
   register the new singleton, attempt eligible attachment, then resolve. Keep a
   pack locked throughout draw initialization/resolve; use `pack_draw_position`
   for the 3D spawn point before converting to Session's planar coordinates.
   The source does not unconditionally clamp a newly registered isolated card:
   solving only clamps stacks when actually translated. Do not silently add a
   pre-clamp if claiming literal parity.
5. For attachment, collect collider hits in physics query order at the appropriate
   radius, then pass candidate dictionaries to `choose_attach_candidate`:
   `{"id": stack_id, "eligible": bool, "card_positions": Array[Vector3]}`.
   `eligible` must already include source matrix/crafting rules. Arguments are
   `(position:Vector3, candidates:Array, own_stack_id:int,
   ignored_stack_id:int=-1, refuse_all:bool=false)`. Return is stack ID or `-1`.
   Repeated candidate IDs are allowed and deduplicated. No center-distance radius
   filter belongs here: a collider may intersect the search sphere while its
   center is farther away. `sphere_intersects_aabb(center,radius,raw_bounds)` is
   supplied for axis-aligned, already transformed raw collider bounds only.
6. The caller owns the successful merge and its side effects: original crafting
   resume, dropped-stack craft stop, `IOnStackable` chest/enclosure interaction,
   unregister only if fully emptied, target relayout, and idle recipe check.
   Choosing a target does not authorize bypassing these gameplay checks.

## Deliberate limits

This is target-layout math, not Unity physics/animation equivalence. It does not
simulate DOTween easing, drag sway, delayed transforms, rotated collider sphere
queries, Unity overlap-hit ordering, or Y lift/stack animation in Session. Use
actual view transforms for source-like attachment when available. Using target
poses and deterministic registration order for an approximate broad phase is a
reasonable explicit model adapter, but must not be labeled exact query parity.
Combat rectangle world transforms, locks, board morph geometry, source settings,
and ownership of IDs remain caller responsibilities. Oversized stacks retain the
source clamp order (including minimum > maximum behavior), not a new packing rule.

## Tests

Run `bash tools/test_godot.sh res://tests/godot/test_board_layout.gd`.
Godot 4.6.3: **38/38 passed** with private source data present. Covers source
margin/step dimensions, signed footprint center, all board edges/header, source
point-valid quirk, pack offset, solver axis ties and sign-zero, touching edges,
lock combinations, input isolation, combat-first ordering, iteration limit,
board shrink threshold, collider rather than center-radius eligibility, nearest
member/tie/ignore/refuse/crafting candidate selection, and imported colliders.
This test does not assert Unity execution, integrated drag behavior, or visual
acceptance. The unit checks isolate target math; current view integration is described below.

## Board adapter checkpoint

The board now uses the helper for source margin/footprints, release placement,
shrink enforcement and iteration-limited stack separation. Model/source XZ remains
unchanged; the rendering adapter reflects Z. Position/composition changes trigger
separation before view synchronization; active drag and pack draw locks are passed
explicitly. Pack opening no longer adds a fixed side offset. Purchases use the
source vendor position, and passive production has an injected placement adapter.
Draws, purchases and passive production try automatic stacking first.

The current nearby broad phase uses target-pose axis-aligned raw source colliders,
including zero source collider height. It does not use margin-expanded bounds or
center-distance eligibility. Query candidate ordering is deterministic stack
registration order, not Unity Physics.OverlapSphere hit order. The pure model
eligibility gate runs before ranking; source chest handling runs in the merge.
Regular spawn attachment never invokes the drag-only equipment action.

Generic craft/loot/encounter spawns currently participate in separation but not all
source initialization-time attachment paths. Combat presentation still exposes
points rather than source rects; the board deliberately does not fabricate combat
rectangles for separation. Smooth movement, original drag splitting timing and
physics-engine hit ordering remain unverified. The helper's combat-rect math is
unit-tested but not yet supplied with an equivalent live combat rectangle.
