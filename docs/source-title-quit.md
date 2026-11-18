# Original Title Quit overlay

On the locked Title scene, its enabled Quit Game TextButton opens its own linked
ModalWindow. The Godot overlay is above the Title menu within the title layer
and below the scene fade. The locked scene's MatchHeight scale applies to the
centered 500-wide panel, not a fixed-height copy of the prefab: Title resets
driven heights and the content is measured again. The original padding, spacing,
text, button extents, background shade, and panel tint come from the source
layout. The existing font registry binds the original font when available;
Godot's font measurement, emboldening, and line baseline do not establish TMP
visual parity. Licensed assets are not bundled.

Opening the dialog and selecting No or Yes works on release with the left,
right or middle mouse button. Outside releases do not activate it. The shade
blocks underlying controls and does not dismiss on click. No closes; Yes
requests quit before closing; the feedback path requests one Click after the
action. Escape, keyboard-submit, and gamepad East do not operate this source
modal. If the source linkage cannot be established, the native confirmation
remains. Day-end, Options, archive, checkpoint, and production audio drain keep
their existing ownership.

Run `test_source_title_quit.gd` for viewport input/resizing and fallback.
It is not a Unity screenshot comparison. The installed font, preferred rect,
and baseline still need a paired Unity/Godot rendered capture for pixel parity.
