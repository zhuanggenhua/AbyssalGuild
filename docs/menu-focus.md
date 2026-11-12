# Native pause/options focus ownership

The public board previously opened its pause overlay without assigning a focused
control. A previously focused HUD control could remain underneath it, while
native Tab traversal had no overlay boundary. Options had the same issue.
This is a native UI usability correction, not a claim that its control geometry
or keyboard behavior is a pixel/engine reproduction of the Unity Canvas.

## Behavior

- Opening pause remembers the prior control and focuses Continue. Tab and
  Shift+Tab cycle through Continue, Options and Save & return to title.
  Up/Down use the same ring; Left/Right cannot escape to the HUD.
- Options starts at the SFX slider and loops through its visible enabled
  controls. Unsupported/disabled graphics controls are skipped. Slider arrows
  retain their normal value-editing behavior.
- If focus is cleared while an overlay is open, the next forward/reverse
  navigation starts inside that overlay, not behind it.
- Closing options restores its opener. Opening it directly during gameplay
  first establishes a paused menu, so options never restores focus to a live HUD
  behind the menu. Closing pause restores the original gameplay control, or the
  day clock if the original is hidden, disabled or deleted.
- Return targets use weak references. Failed options saves leave the panel and
  its current focus open. Native reset confirmation keeps input priority; its
  cancellation cannot close the underlying options/menu.
- Space on Continue resumes the menu without also toggling manual pause after
  focus returns. Title options restore their title opener. No native input
  action is removed or remapped.

## Regression

`bash tools/test_godot.sh res://tests/godot/test_menu_focus.gd`

The focused suite passes **63 checks** on Godot 4.6.3, using actual Viewport
keyboard dispatch and an explicitly empty test catalog. It covers repeated
open/close rounds, both traversal directions, directional keys, lost focus,
slider adjustment, modal cancellation, save failure/retry, direct options entry,
title return and invalid return targets. The ordinary and private imported
runners both include it. The Space routing regression remains 35/35.

These checks run headlessly and do not establish physical controller support,
rendered focus visibility, audio listening, imported gameplay or Windows
acceptance. Production still refuses to start gameplay without licensed data.
