# Historical combatant order

Static reference: locked StackCraft revision
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`,
`Scripts/Combat/CombatTask.cs`. No Unity execution was used.

The source maintains both faction lists and a distinct combatant list. Construction
registers attackers then defenders; later joins append to the combatant list
regardless of faction. Stable descending action-progress selection uses that
historical list. Removal deletes an entry, and a subsequent rejoin appends it.
Merging constructs a new task with newly grouped sides and resets its order.

Previously the native model rebuilt actor order from attackers plus defenders
every turn. Reproduction: start with player P1 and mob M1, then add player P2.
Set P1's progress below an equal M1/P2 progress. The source selects M1; the old
native loop selected P2. This test deliberately controls the tie rather than
claiming identical cross-engine random streams. The same scenario is tested
with actual imported card definitions in both Main and Island.

Each native combat task now owns `combatants`, used for progress updates and
stable actor selection. Faction lists remain authoritative for target selection,
feeding enumeration, layout, survivor handling and fresh merge construction.
Death, external removal and fleeing remove the historical entry. Duplicate joins
do not add duplicate entries.

Native checkpoints persist the order. If present it must be an array containing
every participant exactly once, with valid integer IDs and no foreign entries.
Validation is staged and rejection preserves the complete live state and RNG.
Old native v1 checkpoints lacking the field use their previous deterministic
attackers-then-defenders order and write that order on the next save. They cannot
recover join history that was never stored. This is not Unity-save compatibility.

`tests/godot/test_combat_order.gd` covers ties, dragged actor exclusion, JSON
continuation, explicit malformed orders, legacy fallback, removal/rejoin, merge,
death cleanup and private source-card continuation. It does not establish manual
pointer, visual or cross-engine RNG acceptance.
