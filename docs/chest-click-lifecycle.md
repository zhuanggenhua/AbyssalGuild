# Chest click and withdrawal lifecycle

Static references: locked StackCraft `ChestLogic.OnClick`,
`ChestLogic.TryWithdrawCoin`, and `Board.EnforcePlacementRules`. Unity was not run.

A successful chest click creates a coin using the chest's current position plus
its width, then resets the chest stack to the pointer-down position and resolves
overlaps again. Small movements below the click threshold still count as clicks;
keeping their release position incorrectly causes the chest to drift. The board
now passes the captured pointer-down X/Z position to the withdrawal helper and
restores it only after a successful coin withdrawal. Empty and rejected clicks
retain the ordinary failed-click/drop path. Inspection-panel withdrawal is an
explicit convenience without a pointer-down origin; it does not borrow stale
pointer state.

The source calls `EnforcePlacementRules(spawnPos, null)`, which returns its input
unchanged. A zero-size stack is not equivalent: it still clamps coordinates. Coin
spawning now receives the raw offset position, including positions outside the
board, so the normal factory performs attachment queries before resolving layout.

`tests/godot/test_chest_click_lifecycle.gd` passes 19 source-data checks: successful
sub-threshold motion, output-query position before reset, raw boundary queries,
originating-stack exclusion, failed/empty withdrawal, inspection convenience,
repeated release and carried release across a day-phase boundary. A real mouse-picking regression also covers an interpolating singleton: whole-stack
presses now immediately set the held root to the captured visible X/Z position,
matching the source initial drag update while preserving source stack-height
click semantics. Without this update an unmoved release could fail the threshold
because its model target was already far ahead of its visible pose. The existing
cycle action suite separately covers stacked chests and menu/options locks.

This correction concerns source call ordering and settled X/Z coordinates. It
does not establish animated Unity transform, physics-query, rendered or physical
pointer equivalence. No original source code or assets are included in these tests.
