# UI click and hover feedback

Static references: `Scripts/UI/TextButton.cs`, `Title/GameplayPrefsUI.cs`,
`GameOptionsUI.cs`, `ModalWindow.cs`, `InfoPanel.cs`, `Menu/MenuView.cs` and
journal group constructors in the licensed source. No source assets are copied.

`text_button_feedback.gd` admits visible, enabled, live buttons with a callback
and an optional context guard. It invokes the action before requesting `Click`,
even when the action hides its panel or changes the audio volume. No handler
means no sound. Hover and leave are silent. Audio remains silent without imported
private clips; no substitute audio is fabricated.

The explicit mapping is title New/Load/Options/Quit, gameplay Confirm/Cancel,
saved-slot Continue/Back and archive selected/all (the recoverable native
substitutes for SavedGameSlot delete and SavedGamesUI clear), pause Continue/Options/return, graphics option cycling,
options reset/close, modal accept/decline, and the day InfoPanel action. Friendly
Mode has its own change listener. Showing a journal tab and toggling a group each
request Click; per-row hover/mark-read does not. Native restore/import,
market purchase, manual save, selected-card convenience actions and pace shortcuts
are not blanket-mapped to TextButton. Existing day-clock and journal slide sounds
retain their original owners. Day-end can legitimately request an additional
Click when it also auto-closes an open journal: these are distinct source events.

Native modal confirmation normally hides before emitting `confirmed`. The helper
owns accept hiding instead so visibility can reject stale signals before invoking
the action, then hides and requests sound. Cancel uses the existing native route.

Source TextButton underlines on pointer enter and clears on exit/disable.
Opt-in native text buttons draw a centered underline using the current native
font, clipped to available width. Journal metadata uses underline-on-hover.
This preserves behavior, not TextMeshPro font metrics, glyph wrapping, baseline,
rich-text styling, exact hit geometry, or original font assets. Native dialog
buttons retain their platform/theme hover appearance rather than claiming exact
source TextButton typography.

`test_text_button_feedback.gd` counts playback requests with a spy; cooldown or
voice allocation cannot conceal duplicate requests. Tests are synthetic/headless,
not listening, rendered typography acceptance, or physical-device input QA.

Public clean snapshot (no data, assets, or .godot): 19 checks pass, seven gameplay
checks explicitly skipped. Imported project: all 26 checks pass without SKIP.
Missing-audio silence is checked on both paths. Separate regressions passed:
navigation UI 56, slot management UI 24, options UI 42, title navigation 23,
and title gameplay preferences 11 checks.
