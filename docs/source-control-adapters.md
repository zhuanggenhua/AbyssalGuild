# Source control, Options and Pause mapping

This batch replaces native control drawing with the referenced source component
geometry. It does not replace save, archive, settings, reset-confirmation or
capability-check transactions.

## Controls

`source_control_metadata.gd` follows component references inside the selected
source documents. Slider fill/handle parents, flat Image tints, direction and
Selectable ColorBlock come from those references, not object-name guesses.
Only the audited left-to-right, ColorTint, null-sprite Image subset is accepted.

`source_slider_adapter.gd` leaves the original Range as the value/signal owner.
Its child owns input and focus. Own drawing/input on the old widget is disabled;
external value updates still refresh the new drawing. Fill and handle anchors
are rebuilt as Unity Slider's driven anchors, including the cross-axis stretch,
rather than using editor-time zeroed anchors as live positions. Handle drag
retains the grab offset; track click uses the handle-container bounds. Keyboard
steps are 1 for whole numbers and 10% of the range otherwise. Source Options
volume values are continuous (step 0), not the previous native .01 increments.

The Prefs handle is 20×40; Options handles are 10×20. Their different fill,
background and handle geometry/tints remain separate runtime source inputs.
Selectable only tints the target graphic, in disabled/pressed/selected/hover/
normal priority, using source fade duration and elapsed unscaled time.

FriendlyToggle has graphic=null. `source_text_toggle_adapter.gd` draws its
referenced Label, no checkbox icon, with header font size and the source inline
secondary size. Existing toggled and pressed listeners remain on the original
button. Guards prevent activation behind Options or reset modals. Title and
Options focus rings now target the adapters, not the hidden native widgets.
Original TMP font/metrics have now been located in the full locked tree but are not yet bound in this batch; source font sizes, alignment and
relative text hierarchy are mapped, not claimed pixel-identical.

## Options/Pause trees

`source_prefab_documents.gd` applies supported local serialized overrides before
layout rebuilding. Title's GameOptionsUI overrides include zeroed driven
rectangles. These are not final rendered dimensions: vertical groups, horizontal
footer groups, ContentSizeFitter and Slider rebuild them.

`source_panel_view.gd` maps the source Canvas height scale and referenced prefab
subtrees. Options uses its 400-wide preferred-height panel (670 at source sizes),
source order and colors, source heading, volume groups and footer. Pause uses the
UIRoot/PauseMenu subtree with width 400 and computed preferred height 290, source
heading and three source button labels. Previous invented explanatory headings
and panel dimensions are not shown. Source font colors remain constant through
text-button hover/press, retaining TextButton's underline behavior.

Options keeps original hardware capability gates. Source-sized concise labels
are displayed; detailed capability explanations remain in tooltips and warning/
error status beneath the panel. No success explanation is added to the source
panel. The reset scope remains application options only, not Unity's destructive
PlayerPrefs.DeleteAll. Archive behavior is unchanged.

## Validation and limits

Public synthetic controls test covers nonzero ranges, geometry, existing
callbacks, bidirectional updates and duplicate binding. Gated private tests read
the existing catalog, not a copied source fixture: all three sliders, Toggle,
32/23 label sizes, fade interpolation, Options/Pause panel sizes, component refs,
focus and modal guards. No original source JSON or media was added to public
files. A bounded native Godot 4.6.3 / Mesa llvmpipe run at 1280×800 verified
Options from Title and Pause, source panel containment, the duration slider,
Friendly text-toggle, cancel/reset-to-default Prefs reopening, nested Escape back,
and Continue to Play. It exposed a real missing synchronization: Options used
set_value_no_signal after adapter binding, leaving 100% volume handles at zero.
The caller now refreshes adapter geometry after silent assignment; a failing
regression was reproduced, then passed, and a fresh native process showed both
100% handles correctly at the right edge. Reopen with a silent 25% model update
is also covered. No audio setting was changed by the native check.

This was not pixel comparison against running Unity. Audio output is dummy,
embedded-window fullscreen is unsupported, and the existing display warnings
remain visible. Combat tween mathematics does not receive GPU acceptance from
this menu test.

Source saved-slot prefab/list and elastic ScrollRect remain the next independent
migration step. Slider touch and out-of-window pointer behavior are not yet
validated. The source font is not yet bound, so dynamic text preferred-width parity
cannot be asserted. Options' fixed-width footer is mapped; SavedGames' dynamic
preferred-width footer remains outstanding. The UIRoot nested GameOptions instance was also audited: its 22 overrides only
set root transform/name and modal binding, not control skins or layout. The
shared Options content therefore matches that subtree as well; gameplay modal
ownership remains the native controller’s existing binding.
