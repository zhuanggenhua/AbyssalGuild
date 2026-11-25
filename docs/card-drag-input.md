# Board-space drag and click decisions

Static reference: locked `Scripts/Card/Components/CardController.cs`, specifically
`UpdateDragPosition` and `OnPointerUp`. No Unity execution was used.

The source moves held cards immediately and measures a click from the final
flattened world position to the original three-dimensional position. Its
`clickThreshold` is a world distance, not a screen-pixel dead zone. Moving away
and returning can therefore be a click. The imported default is 0.02.

The board previously ignored pointer movement below seven pixels and permanently
latched movement after crossing that threshold. This could open a pack or withdraw
chest currency after a genuine small drag, or reject a valid return-to-origin
click. Captured presses now use the active scene's CardManager settings and final
board-space displacement. The original source stack height is captured before
splitting; the native mesh's display clearance is not mistaken for source height.

Held cards use physical board bounds, allowing them into the source trade header.
Only final nonterminal placement applies the restricted top margin; applying it
while dragging had prevented real pointer drops from reaching vendors.

Held motion now preserves the initial grab offset while clamped at the board edge.
It recomputes the target each frame, so a stationary pointer follows camera motion
even during an already-authorized menu/phase-crossing drag. New input permissions,
actual release capture and non-reentrant save behavior remain unchanged. Legacy
programmatic tests that submit a release without a captured press retain their
explicit click/drag input; real pointer events always use world displacement.

`test_card_drag_input.gd` has twelve synthetic checks for distance, strict boundary,
height, invalid values and unequal scene settings. `test_card_drag_board.gd` has
21 source-backed integration checks for tiny motion, accidental chest withdrawal,
return-to-origin, duplicate release, edge-clamp return, camera-only movement,
menu-held release, active-scene thresholds and real pointer vendor payment. A previous integration expectation
that rejected return-to-origin clicks was corrected to the locked source behavior.

Unity ordinary PointerDown samples the held leader immediately. Native mouse
now joins the existing touch press path, so a press/release within one frame
does not skip the source sample. Ordinary attachment queries the lifted
leader's final held X/Z and authored height, not the separate grounded placement
destination; successful trade and special release routes retain their logic.

On a handled native pack click, `PackInstance.PullFromNextSlot` creates the
draw at the still-locked, lifted stack target plus its 0.1 offset before
decrementing the slot count. The normal press now passes its verified held
source target, just as the already separate portal path supplies its own
sample. With authored 0.1 lift the factory queries at 0.2; the surviving pack
lands at its grounded target, and the final slot's destruction puff originates
from the pack's still-lifted pose. Direct model and uncaptured programmatic
calls retain their existing grounded fallback.

With Starter on its authored last Wood slot, physical mouse and touch capture
exercise the actual Godot spawn selector before layout. At X offsets 1.370,
1.387 and 1.405 the settled receiver respectively wins, loses and loses at Y=0.2.
At Y=0.1 the middle case used to merge. This is a Godot routing regression,
not a measurement of Unity collider extents or animation timing.

Collider admission and compatibility checks are unchanged. Only ordinary
captured release can then rank admitted compatible stacks by all members'
current positions, when each eligible stack has a complete, identity-checked
ordinary horizontal pose mapping. If a receiver is unsettled vertically or
has another presentation owner, the entire query retains the prior settled
ranking. Spawn and equipment still use their unchanged settled ranking.
The receiver collider-sync model, hit-order ties, original animated press
height and same-frame Unity rendering remain unaccepted.

Board regression covers no-motion mouse/touch, rejected vendor and grounded
placement, two already-admitted stacks where only an animated nonfirst member
is nearest, incompatible receiver, and complete fallback for a transformed
receiver. Headless input injection is not physical mouse, rendered or
cross-engine physics acceptance.

### Re-press during a successful singleton click's settling motion

The source card controller captures the three-dimensional position at pointer
down, then compares it to the flattened drop position with a strict 0.02
threshold. PackInstance grounds its held stack after drawing; ChestLogic
restores the original full press pose after a successful withdrawal. A
grounded chest pressed and restored at unchanged XZ has the same vertical
settling curve as the retained pack. The authored leading-card drag sets
Y=0.1 instantaneously; the independent 0.1-second OutQuad movement leaves
Y=0.016 at 60 ms. Do not subtract render clearance from the animated view.

Godot samples this curve only from a successful captured ordinary singleton
click with the same stack, card, view and final layout target. A chest that
is not moved by layout can retain the captured nonzero target height beyond
the second tween. A changed owner or relocated layout target invalidates
the sample. A sub-threshold sideways chest release also seeds lateral motion
from the synchronous held point, before the view catches up. Native board
clearance is independent of the press height used for classification.

The headless pointer fixture covers grounded pack/chest controls; a third
stationary chest press after 60 ms rejects at Y=.02944 while the 90 ms case
withdraws at Y=.01684. A same-frame .012 sideways release starts its return
at the held XZ, reaches .00192 X after .06 seconds, and another captured
click restores that interpolated press origin. If layout actually translates
the chest, the grounded control withdraws on a fresh .013 drag. These are
not native Unity timing/rendered results; cold-save height and broader
physics/tween ownership remain outside this check.

Final ordinary pack and successful ordinary chest clicks now pass the sampled
held Transform to the actual Puff node, even before the card view has caught
up with the input frame. The chest label is already decremented at Puff; its
coin still queries from held XZ plus card width at Y=0 before the chest returns
to the press origin. The pack's draw query is independently lifted to Y=0.2.
Other Puff calls retain their current-view priority and model fallback. A
headless probe instantiates the authored Puff node and checks its world origin,
not its final appearance or same-engine screenshots.

### Standard drop: equipment and combat

In the locked Unity `CardController.HandleStandardDrop`, trade precedes
equipment, combat-rectangle join, new combat, and ordinary placement.
Equipment and new combat use an overlap sphere at the still-held transform.
For a supported captured `Main` / `Island` hold, the Godot adapter keeps that
source lift for loose equipment and new combat, including motion and release
in the same frame before the view updates. Combat ranks individual overlapping
cards before testing the winning stack's faction; ordinary attachment still
uses its separate stack ranking. A combat-rectangle join remains an X/Z test.

This covers the captured release and grounded target fixtures, not native
PhysX overlap order, moving target synchronization, or every collider edge.
The existing deferred equipped-card, trade-mutated stack, and uncaptured
adapter paths retain their prior fallbacks.
