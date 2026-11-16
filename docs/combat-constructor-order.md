# Combat constructor progress boundary

Source lock: Unity CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`.

`CombatTask` constructs its historical list in attacker-then-defender order and
calls `CardCombatant.InitializeCombatActionProgress` on the entire list before
`CombatManager.CreateCombatTaskInternal` calls any `EnterCombat`. Progress uses
one random draw in [0, 0.5] per member. This change implements that boundary for
new standalone and merged tasks. Each `combat_entered` observation therefore
sees the complete constructor list and progress, including members not entered
yet. Membership and detach continue to happen individually in entry order.

The separate `AddCombatants` path intentionally retains its existing
entry-then-progress draw. Save/restore does not call the constructor and does not
reroll progress. No simulation, teardown, serialization, or UI geometry changes
are included.

Consumer audit: production signal subscribers are quest tracking, cycle
tracking, mob AI, and Board. Only Board handles `combat_entered`, clearing drag
highlights; its forwarded world post-process event ignores this event. No
production entry consumer draws RNG or attacks. The tests add an explicit RNG
consumer to detect accidental interleaving, rather than assuming consumers stay
passive forever.

Validation: native `test_combat_order.gd` verifies complete state on every entry,
attacker/defender draw order, callback RNG isolation, exact entry count, invalid
start no-draw guards, unchanged late-join order, and exact restored snapshot.
Native `test_combat_board.gd` exercises actual imported cards and the existing
Board subscribers through drag-to-start; it verifies progress and RNG before
entry callbacks finish. Existing merge and timeline tests cover adjacent paths.

This is not complete combat migration acceptance: new Rect initialization before
task construction and full Unity/Godot presentation and screenshot equivalence
remain separate unaccepted work. Godot and Unity random generators are not
claimed to produce identical bit streams; this establishes draw sequencing and
state visibility within the migrated model.
