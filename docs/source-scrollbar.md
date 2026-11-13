# SavedGames Scrollbar: source-backed vertical branch

## Sources and missing behavior

Official Unity-Technologies/uGUI commit b394b8ab4f985d25230da1bb02268dcb3c85cb19 (Unity6000.5.4f1, package2.5.0), Runtime/UGUI/UI/Core/Scrollbar.cs: Set228, UpdateVisuals274, UpdateDrag312, OnBeginDrag365, ClickRepeat417, OnMove442 and FindSelectableUp/Down500. Reference source remains outside repository.

Title component92994284: BottomToTop2, NumberOfSteps0, Automatic navigation3, ColorTint1, .1s fade. Target1771954239 is null-sprite Image, gray.638; parent SlidingArea401161735 inset10 all sides. Handle1771954238 retains sizeDelta(+20,+20); UpdateVisuals drives anchors only, so its height is containerHeight*fraction+20. Native bar minimum-handle heuristics were not equivalent.

A live Godot4.6.3 probe disproved the proposed quantization cause: VScrollBar default step is0.0, and assigning.375 retains.375. No step fix is claimed.

ClickRepeat is NOT a page-size increment: it calls UpdateDrag at original press point whenever that point is outside handle, initially and at each end-of-frame. Pointer drag has no pixel threshold. Vertical Automatic navigation intentionally returns no adjacent selectable for Up/Down, so each move changes continuous value by.1. PageUp/Down has no source Scrollbar branch.

## InputSystem evidence and correction

Locked package is InputSystem1.19.0. Official Unity-Technologies/InputSystem tag1.19.0, Packages/com.unity.inputsystem/InputSystem/Plugins/UI/InputSystemUIInputModule.cs: ProcessNavigation820-876 maps direction with .5s initial/.1s repeat; strictly time>last+interval, at most one dispatch per frame, count resets on direction change. Title serialized fields confirm .5/.1. Exact referenced Assets/InputSystem_Actions.inputactions GUID052faa... maps keyboard W/S and arrows to UI Navigate vertical. Only that keyboard vertical subset is implemented here; joystick/gamepad/horizontal automatic navigation remain out of scope.

OnScrollCallback2248 transforms `(raw / InputSystem.scrollWheelDeltaPerTick) * scrollDeltaPerTick`; ProcessPointerScroll792 forwards it directly to IScrollHandler. Title's scrollDeltaPerTick=6 was omitted previously. Host now maps a Godot wheel tick factor to UI delta6, including over scrollbar because IScrollHandler is on its parent. Camera raw wheel is unchanged. This does not assert equivalent cross-platform raw mouse units or high-resolution device sampling.

## Integration manifest

Only merge these original implementation files, not the entire snapshot or private assets/data:
- new scripts/ui/source_scrollbar_adapter.gd
- modified scripts/ui/source_saved_slot_host.gd (source bar creation/sync, metadata wheel factor, bar-area wheel route)
- scoped source_title_view.gd install_saved_rows changes (source scrollbar reference resolution and InputSystem field forwarding)
- new tests/godot/test_source_scrollbar.gd
- modified tests/godot/test_source_saved_slots_board.gd
- this document

Adapter uses direct source normalized value (not native Range page/value translation), preserving unbounded overscroll values while clamping visual anchors. Size fraction is clamped0..1. ColorTint uses existing unscaled SelectableTint helper. Signals emit only on actual value changes; ScrollRect synchronization is silent. Transaction/modal guard stays in force. No asset substitutions or fabricated background added.

Remaining unsupported: other directions, stepped values, non-ColorTint transitions, non-null sprites, automatic horizontal spatial focus search, full global InputSystem navigation state across focus changes, gamepad/joystick/touch/multi-display, exact engine end-of-render coroutine scheduling. Key repeat is source-timed, not OS echo. No native visual verification claimed. Source null-sprite handle is rendered by flat ColorRect.

Important raycast boundary: source ScrollbarVertical92994282 and SlidingArea401161734 have no Graphic/Image component. Only handle has raycast Image. The adapter's hit-test therefore admits only actual handle pixels (flat rectangle); an empty-track press falls through to ScrollView background and starts content drag, NOT Scrollbar.ClickRepeat. ClickRepeat implementation is tested by direct component dispatch, but ordinary empty-track clicks must not invent native page behavior. Host input excludes actual handle from content drag and includes uncovered track. Wheel anywhere still reaches parent ScrollView.

Reference hashes: Scrollbar.cs SHA256dd5cd169c4fb5906050660cc2db37e03ac98638194753379b7143f09ab1eaee0; InputSystemUIInputModule1.19.0 SHA2561334661b7a824ead8b3b0a8ff3ce17e93f80a369ec3e3e37cd796d90f13223e2.

Verified headless: source scrollbar synthetic (including exact strict repeat thresholds and changing direction), first-layout row760/clip780, private source SavedGames board (actual metadata/gray/null sprite and repeat params; ×6 wheel over content and scrollbar; existing drag/release/modal/archive/restore/load), ScrollRect18/18, Title24, focus64, slot management24. Synthetic and strict-private runners register the new scrollbar suite. This is bounded source/input verification, not complete device/navigation equivalence.
