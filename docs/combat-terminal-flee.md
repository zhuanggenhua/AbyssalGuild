# Bounded terminal Flee cleanup

Source pin: CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`.

This slice corrects the last-player-attacker **idle** cleanup transaction in the
real Board adapter. It does not certify the full combat migration.

## Original path and mapped order

`CombatTask.Flee`: remove attacker, leave combat, call `Rect.UpdateLayout`, then
`EndCombat` when the attacker row is empty. `CombatRect.ArrangeRow` uses instant
ground slots. `EndCombat` stops the attack coroutine, marks Finished and closes
its rectangle before iterating remaining attackers then defenders. Each survivor
leaves combat; a singleton is constructed from its **current transform**, then
registered, then given an enforced ground placement target. Only afterwards
`CardController.HandleCombatDrop` registers the departing singleton and resolves
overlaps.

The terminal adapter requires pinned imported provenance, Main/Island source
configuration, identity Board transform, idle execution, and live directly-owned
native survivor nodes that pass the existing atomic layout guards. It updates the
remaining row and records actual native positions, not old combat model slots.
The model removes the task (Finished), closes native logical rectangle state with
a private synchronous callback, then registers survivors in row order before the
departing card. The existing public completion event stays after all singleton
registrations so unrelated observers never consume half-committed membership.
The former nonterminal layout hook and generic death/finish path are unchanged.

## Verification boundary

`test_combat_terminal_flee_board.gd` instantiates the real Board with licensed
source inputs and drives native press/motion/frame/release. It checks post-layout
native transforms, close-before-registration, survivor-before-departing stack IDs,
placement targets and safe public notification. Private runner requires a counted
success marker. These are headless native-node checks, not GPU or screenshot proof.

## Still unaccepted

- The survivor and departing **visual** ground tween (`DOMove`, source duration
  and ease) and ordinary CardView height are not fixed here. Model target order
  must not be mistaken for transform interpolation equivalence.
- Exact per-survivor `LeaveCombat -> CardAI.StartAI` timing and random draws are
  not accepted. Existing public AI resynchronization remains after settlement.
- Active actor/target, active coroutines, melee, transformed/invalid views,
  equipment/cycle presentation and complex overlap movement are not expanded.
- The previous held-input slice excludes terminal held-drag semantics; this
  test does not turn that exclusion into an acceptance claim.
- No original assets, screenshots, private input data or source text are included.
