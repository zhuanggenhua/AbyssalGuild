# Combat overlap merge integration

Static reference: locked StackCraft revision
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`, CombatManager.StartCombat,
FindOverlappingTasks, CheckAndMergeCombats, MergeCombats and
CombatTask.AddCombatants. No Unity execution or original assets are included.

## Adapter hooks

CombatSystem exposes two optional Callables:

- `start_overlap_selector(attackers: Array, defenders: Array) -> Array`
  receives card-instance IDs and returns existing task IDs. It runs after initial
  validation, before detachment, task allocation or action-progress RNG.
- `resize_overlap_selector(task_id: int) -> Array` receives an existing task after
  valid reinforcements have entered. It returns other task IDs overlapping its
  updated rectangle. Returning the source ID is harmless; it is excluded.

The board adapter should synchronize cached combat layouts in both callbacks.
For start, return `CombatMergeGeometry.before_start(fighter_records(attackers),
fighter_records(defenders), combat_layouts)`. For resize, return
`CombatMergeGeometry.after_resize(task_id, combat_layouts)` after calling
CombatLayout.update_layout with existing center/cell. The helper uses exact
CombatLayout.potential_bounds for proposed fights and manager_bounds for live
rectangles. Bounds touching at an edge count as intersecting.

Callbacks only select geometry: do not invoke combat creation, merge or joining
from them. Reentry into those operations is blocked. Missing hooks preserve
standalone model behavior. Missing layout should return an empty array rather
than invent dimensions. Unknown task IDs, non-arrays, fractional/string IDs and
other malformed results are rejected. Start then fails without new task/RNG;
a successful reinforcement remains joined if its merge selection is invalid.
Incoming cards and merge targets are revalidated after callback execution.

## Mutation and ordering

Start with overlap creates only the final merged task. It does not first create
the proposed fight, so each final fighter draws initial progress exactly once.
Adding reinforcements differs intentionally: each entrant initializes progress
on joining, then if resizing causes a merge all final fighters initialize again.
This reproduces the source order rather than trying to optimize away RNG draws.

`merge_combats(task_ids, initial_attackers=[], initial_defenders=[])` accepts
optional new fighters or the resized source side arrays. All inputs are validated
before old tasks are removed. Fighters are collected from initial attacker then
defender arrays, then existing tasks in registration order. Duplicates are
removed while preserving first appearance. Player units become the attacking
side regardless of who initiated the old/new fights.

Old tasks are removed directly: no combat-ended event, survivor world stacks or
normal end-of-combat placement. Their drag exclusions are cleared. The final
internal creation emits combat_started and receives a new ID, fresh timer,
progress and layout. It bypasses overlap callbacks, preventing recursive merge
chains and duplicate draws. A subsequent independent source-driven join can
trigger a later merge normally.

Only the source's direct overlap set is merged in each operation; this is not a
recursive transitive connected-components algorithm.

## Persistence and checks

The existing combat snapshot representation and stage/apply implementation are
unchanged. Cached center/cell survives save/restore and is used by subsequent
resize checks. Derived bounds/configuration are reconstructed by the adapter.
Callbacks are runtime scene dependencies and are not serialized.

Run `bash tools/test_godot.sh res://tests/godot/test_combat_merge.gd`.
Synthetic cases cover pre-start overlap, no-overlap, mob-initiated normalization,
join-resize overlap, exact RNG draw counts, first-appearance/registration order,
no survivor cleanup, callback reentry, malformed/stale outputs, input mutation
revalidation, touching rectangles, and cached-layout save/restore compatibility.
