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

`tests/godot/test_chest_click_lifecycle.gd` covers source-data cases: successful
sub-threshold motion, output-query position before reset, raw boundary queries,
originating-stack exclusion, failed/empty withdrawal, inspection convenience,
repeated release and carried release across a day-phase boundary. A real mouse-picking regression also covers an interpolating singleton: whole-stack
presses now immediately set the held root to the captured visible X/Z position,
matching the source initial drag update while preserving source stack-height
click semantics. Without this update an unmoved release could fail the threshold
because its model target was already far ahead of its visible pose. The existing
cycle action suite separately covers stacked chests and menu/options locks.

The focused repeat-input cases in [Card drag input](card-drag-input.md) also
exercise the captured three-dimensional press calculation and lateral return
on a surviving singleton. An overlap translation clears the retained height.
This does not establish animated Unity transforms, physics query timing,
rendered or physical input, or cold persistence of a nonzero target. No
original source code or assets are included in these tests.

## Deposit and withdrawal presentation order

Locked `ChestLogic.OnStack` puffs first, including a drop onto a full chest.
Only a deposit that consumes at least one coin updates the chest's price label
and requests `Coins`, once for the whole transfer rather than once per coin.
`TryWithdrawCoin` decrements and updates that label before puffing; only the
board-spawn branch requests the singular `Coin`, after creation. The board now
handles those cues from the chest lifecycle itself rather than assuming a single
click caller. This change does not alter global stats, admission geometry,
placement, or mixer cooldown behavior.

The locked-data chest lifecycle test drives ordinary board mouse input
for the partial and full chest drops and observes the visible Label3D text
and remaining card IDs at each sound request. It does not test speaker output,
Unity frame timing, or the currently unresolved Unity collider admission edge.
