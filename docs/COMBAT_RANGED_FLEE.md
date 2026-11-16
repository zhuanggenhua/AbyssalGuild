# Flee: immediate surviving card slots

This bounded migration is not full combat, pixel, or whole-project acceptance.

## Locked source

CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`:

- `Combat/CombatTask.cs` `Flee`: remove the player attacker from the attacker and
  historical lists, call `LeaveCombat`, then `Rect.UpdateLayout`. It does not call
  the `AddCombatants` overlap/merge selector. An empty attacker side ends combat.
- `Combat/UI/CombatRect.cs` `UpdateLayout` / `ArrangeRow`: resize the same rectangle
  and apply surviving slots with `SetTargetInstant(..., forceGround: true)`.
- `Card/Components/CardController.cs` `HandleCombatDrop`: the departing stack is registered
  and placed, then overlaps resolved, only after `Flee` returns.
- The ranged/magic attack coroutine uses its captured projectile world segment
  and unscaled travel/return clocks, not a card combat tween.

## Scope and ordering

A separate optional `flee_layout_updater` runs only on nonterminal Flee. Its
eligibility is captured before removal: the departing member cannot be the
current execution's actor or target. This avoids treating the existing dangling
actor/target cancellation as an eligible idle state. The public generic
`remove_combatant` API never requests the hook.

The internal removal helper runs the hook after membership/history/progress/drag
removal and before registering the departing stack. The Board updates only this
combat's layout, sharing the previous full-sync implementation without changing
its one-config-lookup behavior, then uses the existing atomic native slot guards.
Known ranged/magic travel/return and ordinary idle layouts are admitted; melee,
death-wait, invalid identities, missing views, unsupported transforms, survivor
drag and active card tween guards retain their existing fallback. No overlap
selection or ranged merge-center receipt is created by Flee.

This preserves ongoing execution dictionaries, projectile clocks and captured
endpoints, survivor progress and RNG. Terminal layout/EndCombat ordering,
direct actor/target departures, post-Flee overlap resolution and melee coroutine
cancellation are not claimed as newly migrated by this change.

## Evidence

`tests/godot/test_combat_ranged_flee_board.gd` uses private imported source data,
actual Board nodes and authored arrow/magic projectile resources. Both projectile
types are tested in actual travel and return phases. The test observes survivors
inside the synchronous layout callback before departing stack registration and
before Board refresh; after return it verifies stack registration. It verifies
slot changes, unchanged execution/presentation/health/flight/RNG/progress, then
original flight endpoint/impact or remaining return wait. Repeated/defender Flee,
actor-cancellation, generic removal and terminal Flee do not acquire the hook.

The exact equal-count completion marker is registered in the private runner and
its fake-engine regression, as well as the imported branch of `test_all.sh`.
Headless native node assertions are not rendered screenshot equivalence.
