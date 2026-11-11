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

This remains a settled-pose input adapter. Drag height, trailing-card sway and
animated current-pose physics queries are separate presentation work. Headless
input injection is not physical mouse, rendered or cross-engine physics acceptance.
