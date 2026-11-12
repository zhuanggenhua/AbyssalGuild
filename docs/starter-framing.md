# Starter framing audit and synthetic recovery regression

Reference: StackCraft revision `a11a89b04cea8370476f2559b639bb9b4cbc08d8`.
This checkpoint changes no production camera, spawn or placement behavior.
Unity was not launched. No licensed source files or assets are included.

## Static finding

The initial crop is consistent with the source camera and placement rules; the
available evidence does not identify a Z-reflection or viewport conversion bug.
This is not a claim that the original author deliberately wanted cropped cards.

- `Scenes/Main.unity` gives the camera root position `(0,10,-1)` and an actual
  quaternion corresponding to X rotation +85 degrees. Its Euler hint is not the
  authoritative pose. `Prefabs/Core/CameraController.prefab` gives vertical FOV
  30, near 2, far 40 and the complete normalized viewport.
- `Scripts/Core/CameraController.cs` starts its movement target at the existing
  transform. It does not fit the board or focus the initial pack on startup.
- Main's spawn center is X=-3.5, Z=0.6 with radius 1.2. At Z=0.6 and aspect
  16:10, the initial camera sees approximately 4.33 world units on each side of
  its center. The possible left spawn extent reaches X=-4.7 before card width.
- `Scripts/Pack/PackInstance.cs` locks the pack and creates an output at its target
  XZ. `Scripts/Card/CardPhysicsSolver.cs` chooses the smaller penetration axis;
  coincident centers use positive sign, so a locked earlier stack can push the
  new output left. `Scripts/Core/Board.cs` constrains physical board bounds,
  not the visible camera rectangle.
- The native adapter keeps model XZ unchanged, reflects world Z for rendering,
  and uses vertical FOV with KEEP_HEIGHT. These choices agree with that source.

Changing the lens, initial pack position, solver direction or adding auto-focus
would therefore be a native usability change, not a demonstrated parity repair.

## Source-free regression

Run:

```sh
bash tools/test_godot.sh res://tests/godot/test_starter_framing.gd
```

`test_starter_framing.gd` constructs an explicit numeric camera fixture from the
statically audited pose/lens facts. It uses an empty catalog, a synthetic pack
position X=-4.5/Z=0.6, invented 1.2x1.8 footprints and a generated card view. It
performs two synthetic output registrations through the production overlap
helper. It does not open real Starter slots, reproduce actual imported collider
sizes, sample the source RNG, or assert the original game's exact draw outcomes.

At viewport sizes 1440x900 and 1233x771 it checks:

- Godot projections against an independent Unity-space pinhole equation for
  four world points, including the separated edge output.
- The pack remains locked and a coincident output separates left and is cropped.
- Middle-button press, motion and release sent through the actual Viewport move
  the production camera and expose the complete synthetic card footprint.
- Wheel-down events through the Viewport independently recover the same card
  after resetting the camera. Both recovery paths retain physics picking.
- Neither recovery changes the synthetic card's model or view position.

The focused suite passed **28/28** on Godot 4.6.3 headless. HUD controls are hidden
to isolate camera routing. Camera smoothing is advanced deterministically, and
picking is checked with the production ray query after physics synchronization.
This is not physical mouse, rendered/native-window, private imported Starter,
HUD occlusion, controller, audio or Windows acceptance. In particular it does
not establish that a player will discover pan/zoom without guidance. The earlier
rendered observation in `gui-smoke.md` remains a separate acceptance record.
