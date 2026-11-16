# Ranged admission: immediate native slots, unchanged projectile clock

Scope: source-equivalent native card placement during `AddCombatants`, only for
known ranged/magic `travel` and `return` executions. This is not completion of the
migration, a framebuffer comparison, or proof of active merge-center geometry.

## Locked source evidence

Unity CardLoop commit `a11a89b04cea8370476f2559b639bb9b4cbc08d8`:

- `Assets/StackCraft/Scripts/Combat/CombatTask.cs`, `AddCombatants`: append and
  enter all admitted cards, then `Rect.UpdateLayout`, then `CheckAndMergeCombats`.
- `Combat/UI/CombatRect.cs`, `UpdateLayout` / `ArrangeRow`: resize rectangle and
  immediately apply each row slot using `SetTargetInstant(..., forceGround: true)`.
- `Card/CardInstance.cs`, `SetTargetInstant`: cancel card following/tweens and
  directly write the grounded position.
- `CombatTask.cs`, `AttackSequenceCoroutine`: ranged/magic capture world launch
  and target positions for an independent projectile. They wait for that tween,
  resolve one hit, then wait 0.3 real seconds. Neither phase starts a card combat
  tween. Resetting card slots therefore cannot retarget the existing projectile,
  advance its clock, deliver damage early, or finish the return wait.

## Implementation boundary

`Board._combat_resize_native_slots` previously rejected every nonempty execution.
It now permits types 2/3 only in travel/return, with valid opposite-side current
actor/target membership and a finite nonnegative remaining timer. Existing
identity, complete-view, coordinate-frame, drag, equipment, cycle, position and
card-tween checks still precede all writes. Writes only clear ordinary card motion
and set card positions; no execution/presentation record is changed.

Melee, death-wait, unknown/incomplete executions and unsupported observations
retain conservative target fallback. Active old-member merge-center inference is
unchanged and deliberately not expanded.

## Regression evidence

`tests/godot/test_combat_ranged_resize_board.gd` requires the privately imported
source data and authored assets. It instantiates actual Board and Sprite3D
projectiles, exercises arrow and magic both midtravel and midreturn, and admits
four source-backed recruits through real `add_combatants` calls. It observes
actual resized card slots synchronously at the overlap selector, not a synthetic
layout-only call.

- Baseline `8b73ddea141e6ce0b338bea356b02ed61e5c3e59`: exit 1, 94/134 checks pass;
  the 40 failures are native slot placement, ordinary-motion cancellation, and
  existing-card rearrangement.
- Candidate: 134/134 pass. Exact execution payload/remaining time, presentation
  capture, independent flight age/endpoints and health/hit count survive resize.
  The shot still follows its original world segment and impacts only at its
  original duration. Return retains its remaining real-time wait without a
  second hit. Unknown/melee/death-wait and dragged rejections remain atomic.

Run with Godot headless and privately restored imported data/assets:

```
godot --headless --path . --script res://tests/godot/test_combat_ranged_resize_board.gd
```

No Unity runtime capture, screenshot, source media or imported data is included
in this change. Runtime node assertions do not establish rendered equivalence.
