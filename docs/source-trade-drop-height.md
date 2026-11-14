# Held-card height in trade overlap queries

Scope: locked StackCraft `a11a89b04cea8370476f2559b639bb9b4cbc08d8`,
starting from the runtime tree of `b13a780`.

## Source chain

- `Scripts/Card/Components/CardController.cs:250-256` projects the pointer
  through the camera onto the Y=0 ground plane. This locates the drag; it is
  not the transaction query.
- The same file, lines 114-120, adds the initial pointer offset, assigns the
  scene-bound `DragHeight`, and clamps X/Z to the board.
- `Scripts/Core/Board.cs:113-128` preserves Y while clamping. In
  `Scripts/Card/CardStack.cs:244-266`, the held root is positioned instantly;
  only trailing cards are damped. `CardInstance.cs:592-600` writes that
  position without forcing it to ground.
- On release, `CardController.cs:135-152` flattens a **local value**, not the
  transform. Lines 193-210 attempt trade before ordinary grounded placement.
- Lines 259-281 query a sphere at the still-held transform and choose the
  nearest zone before checking eligibility. This is not a release ray hit.
- Main references `Default_Card_Settings.asset`: height 0.1, radius 0.25.
  The buyer/vendor source boxes have zero Y size. The manager places their
  centers at Y=0 and applies the source X/Z scaling.

## Native correction and bounded evidence

The native held view already used the scene-bound drag height. The transaction
query incorrectly flattened its center to Y=0. Only the Y argument in
`Board._try_trade_drop` now uses the same `CardDragInput.source_settings`
binding as that view. Release has already cleared the active drag ID, so
using it to decide whether to retain height would recreate the bug. No changes
were made to picking rays, X/Z projection, pointer offsets, bounds clamps,
collider sizes, candidate priority, eligibility, or other overlap queries.

For a point outside one face of the raw zero-height box, the horizontal reach
at Y=0.1 is sqrt(0.25^2 - 0.1^2) = 0.2291288, rather than 0.25. At a horizontal
distance of 0.24, the raw-box distance is 0.26. The old Godot production drop
consumed a sellable card there; the corrected query rejects it. Distances 0.22
and 0.26 respectively remain a hit and a miss. An isolated headless fixture
also observed the lifted view at Y=0.1 and a release ray hitting the held card,
not the trade zone.

`test_trade_drop_height.gd` exercises the real native press/update/release
methods with an injected initial pick, plus the existing direct-drop adapter.
It covers buyer and vendor center/edge transactions, unchanged raw bounds,
scene-reference precedence over a decoy global setting, and modified private
fixture heights 0.2 and 0.0. These non-default values are binding tests, not a
claim that the locked template uses them. The regression produced 125/139 on
the old implementation (14 failed assertions), and 139/139 with the correction.

This is **not Unity/PhysX execution**. The original engine's handling of a
zero-height BoxCollider has not been observed. The source-side edge result
is a static pose and raw-geometry prediction; the native transaction result
is executed evidence. It does not establish pixel, input-device, or complete
physics parity. No Unity process or desktop gameplay state was used.

## Reproduction

After a verified private source import:

```sh
bash tools/test_godot.sh res://tests/godot/test_trade_drop_height.gd
bash tools/test_all.sh
bash tools/test_imported.sh
```

For a reversible old/new check, run the same new test with only
`scripts/ui/board.gd` restored to its parent version in a disposable copy.
The old implementation must fail the 0.24 boundary and the 0.2-height/0.16
boundary. Do not alter collider thickness to make either version pass.
