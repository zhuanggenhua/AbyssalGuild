# Native journal menu slide

`menu_slide.gd` ports the behavior in the locked `Scripts/UI/Menu/MenuToggle.cs`:

- Right-aligned open x = 0, closed x = panel width relative to its native open position.
- 0.5-second OutQuad interpolation, advanced by real frame delta before game/menu pause checks.
- Toggle requests during animation are ignored, including their sound request. The button remains enabled, matching source's guard rather than a disabled visual.
- `<<` / `>>` updates at completion. Click audio is requested only for an admitted toggle through the existing source-backed audio adapter; missing audio remains silent.
- Day end closes only when current relative x <= 0. It does not reverse an opening panel at x > 0, force an active animation to restart, or close again on refresh.
- Scene/load/new-game entry and return to title cancel animation and restore the referenced source initial state on gameplay entry; title cancels into the hidden native shell.

The native panel remains visible and owns GUI input while sliding. At the fully closed endpoint it is hidden, retaining the existing journal visible-row/typed-metadata protections. Explicit native show/hide calls synchronize position and cancel pending animation; ancestor HUD visibility changes do not change the local endpoint.

## Deliberate adaptation limits

This is behavior parity, not a source-canvas reproduction. The locked UIRoot target rect is 400 pixels wide and initially open. Gameplay entry resolves MenuToggle.targetRect in imported UIRoot and follows its initial anchored x (open in the locked source). Missing/dangling rect metadata produces an explicit non-source-backed closed fallback descriptor. The existing Godot layout keeps its 248-pixel panel, fixed bottom toggle, native fonts and native geometry. The source toggle is a child of its panel; the native toggle stays accessible outside it. No original TMP/font rendering, exact prefab layout, visible-window interaction, or pixel acceptance is claimed. Hiding the completed closed panel also avoids native offscreen/sliver interaction. No source assets or mock catalog are introduced.

## Checks

Run through the isolated HOME/XDG test wrapper:

```
bash tools/test_godot.sh res://tests/godot/test_menu_slide.gd
```

Synthetic checks always run: exact easing midpoint/endpoints, label timing, ignored rapid clicks, admitted sound count, negative/oversized delta, day-end at rest and during animation, input ownership, explicit visibility changes, ancestor visibility, lifecycle cancellation. Private-data integration additionally checks the actual board toggle, unscaled progression under game/menu pause, event wiring, hidden-row read rejection, and title/game reset. Missing private source data emits an explicit integration SKIP. Existing board-integration and day-clock expectations now advance the journal animation instead of requiring an immediate hide.
