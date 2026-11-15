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

## Source graphics option mouse buttons

Only the five successfully source-mounted graphics option TextButtons opt in
to left, right and middle mouse input, with the locked catalog revision and an
enabled original TextButton component required. The exact Title and gameplay
UIRoot input modules bind all three mouse buttons to the UI action asset, and
the locked Input System 1.19.0 forwards each to pointer click. TextButton does
not filter that event by mouse button. The previous default Godot Button mask
excluded the two alternative buttons.

This only changes which sequential mouse clicks can activate an otherwise
admitted option. Disabled controls, the reset confirmation flow, Close,
native fallback controls, settings application, and all other menus retain
their existing rules. The headless viewport test exercises down/up, outside
release and guards; the private layout test verifies the actual imported
bindings. It does not establish Unity same-frame batching, simultaneous
button ownership, hardware option capabilities or cross-engine pixels.


### Options 自身 Close 的来源绑定

仅锁定 a11 的 `GameOptionsUI.Start` → `closeButton.SetOnClick(Close)`
这条路径扩展为顺序左/右/中键抬起触发。准入核对 prefab GUID、启用的
GameOptionsUI、精确 closeButton fileID、启用的 TextButton 脚本及 GameObject、
实际挂载的 Close 宿主。未匹配时保留普通左键，不扩大 Reset、确认框或 fallback。
原 `Close` 的保存后隐藏语义沿用现有 `request_close`，包括保存失败保持打开的
迁移安全保护；不改持久化实现。回归通过 viewport 实际投递验证按下无动作、
区域外释放、关闭后隐藏、重复打开、生命周期中断、禁用及模态遮挡。
这不是 Unity 原生截图或同时多键序列的等价验收。
