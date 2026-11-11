# Stack eligibility static audit

Reference: locked StackCraft revision
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`, specifically
`Card/CardStack.cs`, `Card/CardInstance.cs`, `Card/CardManager.cs`,
`Card/Components/CardController.cs`, `Card/Behaviors/ChestLogic.cs`, and
`Crafting/CraftingManager.cs`. This is a behavioral audit, not copied source.

The source names are counterintuitive: `TopCard` is array index zero and
`BottomCard` is the last entry. Addition appends to the array. Godot retains that
array order. The old regular-merge gate incorrectly compared the first target
entry; it now compares the last entry without reversing the serialized matrix
arguments. The incoming/lifted card's current definition is the first argument.
Same-definition matrix rules compare effective definition GUIDs, not base identity.

`can_move_to_stack(card_id, target_id, original_crafting_stack_id=-1)` is a pure
filter for nearby-candidate selection. It does not move cards, deposit currency,
resume crafting, draw RNG, or publish events. `move_to_stack` calls that same gate.
Call the gate before choosing the nearest candidate so an incompatible nearer
stack cannot hide a compatible farther stack. Distance/spatial selection belongs
to the board adapter, not this method.

An active target accepts an incoming card only when its recipe allows excess
and the incoming effective definition is a listed ingredient. The source checks
only the lifted card, not every trailing member. It does not accept recipe outputs
unless they are also ingredients. The original crafting stack is the exception:
passing its ID bypasses this ingredient gate and resumes its paused task without
resetting progress. Physical matrix compatibility is still required. The optional
ID is ephemeral drag context, not saved state; callers must only pass the actual
stack from which a drag paused crafting. A whole source stack's craft stops when
merged into another target. An active target's timer is retained.

Only ChestLogic implements `IOnStackable`. It is consulted on the LAST target
card after eligibility and before ordinary append. If the incoming FIRST card is
the configured currency, deposits consume valid currency in source order until
capacity is reached. A full chest still handles the interaction, leaving the
incoming stack intact; leftovers from partial deposits remain registered.
A buried chest does not handle the merge, and currency later in an incoming stack
does not trigger handling when its first card is not currency.

Enclosure capacity is an AI movement-retention rule, not a stacking limit.
Equipment attachment is a separate terminal drop action in CardController,
preceding regular stacking (and combat join/initiation). Thus a regular merge does
not silently equip or engage combat, and ordinary spawn attachment must not acquire
those drag-only actions. The view must perform the higher-priority drop actions
before selecting an ordinary merge candidate.

Verification: `bash tools/test_godot.sh res://tests/godot/test_stacking.gd` uses
synthetic asymmetric matrix entries and mixed stacks to distinguish first/last
ordering, effective/base definitions, active-craft gates/resume, and chest handling.
No Unity runtime or original content assets are required.
