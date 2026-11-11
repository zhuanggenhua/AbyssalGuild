# Fleeing during combat death cleanup

Static reference: locked StackCraft revision
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`,
`Scripts/Combat/CombatTask.cs` and `Scripts/Card/Components/CardCombatant.cs`.
No Unity execution was used.

The source clears the killer's attacking flag before the scaled 0.5-second wait
after a kill. A player attacker may therefore flee during that wait. If both
sides still have members, Flee does not cancel the coroutine or restart the idle
turn timer. The old coroutine later resets the killer's card-owned action
progress, even if the killer has joined another combat in the meantime.

Previously the native model erased every executing turn when its actor fled.
A two-player/two-mob reproduction left one member per side after a kill and flee;
0.1 seconds later the native idle timer had decreased from 1.0 to 0.9. Source
semantics require the idle timer to remain 1.0 with 0.4 seconds of death wait left.

The native model now retains death cleanup when its living actor leaves. Its
completion resets the actor's progress through the current combat membership,
including a different task or a rejoin of the original task. Removing the last
member of either side still terminates the task immediately. Real time while
paused cannot consume this scaled wait.

Checkpoints may reference a living former actor outside the original task only
in `death_wait`. The actor must exist and be a valid combatant definition.
Travel/return phases still require actor membership in their own task. Unknown,
zero, nonintegral and invalid negative IDs fail validation atomically.

Deliberate native safety difference: destroying a former actor clears its pending
reference to -1 while preserving the wait. Completion then omits the reset,
rather than following the source destroyed-object coroutine failure. The cleared
reference is persisted and only allowed in death cleanup. Existing travel/return
dangling-reference cancellation is unchanged.

`tests/godot/test_combat_death_wait_flee.gd` tests the boundary, pause behavior,
last-side termination, same-task and cross-task rejoin resets, full-precision
JSON continuation and malformed reference rejection. These are headless model
checks, not physical-pointer or rendered acceptance.
