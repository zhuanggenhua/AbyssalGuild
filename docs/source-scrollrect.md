# SavedGames vertical ScrollRect motion

Integrated source-derived implementation. Original Godot implementation; no Unity source or licensed assets belong in this patch.

## Evidence

Locked CardLoop a11a89b04cea8370476f2559b639bb9b4cbc08d8 uses Unity6000.5.4f1 and built-in uGUI2.5.0. Official Unity-Technologies/uGUI mirror commit b394b8ab4f985d25230da1bb02268dcb3c85cb19 identifies that exact editor. ScrollRect.cs SHA256 a4230d47d755c990c221a54531d01866c4e3db05487b9ab8ae84634644323b3c:
- OnScroll648: dominant-axis wheel, sensitivity, scrolling flag; no elastic wheel clamp.
- OnInitializePotentialDrag/BeginDrag/Drag: clear velocity, cursor/content origins, offset then RubberDelta.
- LateUpdate830: unscaled dt, elastic SmoothDamp, scrolling smoothTime×3, inertia pow(rate,dt), speed cutoff1, sampled drag velocity Lerp(dt×10).
- SetNormalizedPosition1064: threshold.01 and zero velocity; RubberDelta1084.
- AdjustBounds1332 and InternalCalculateOffset1386: top pivot short-content expansion, .001 threshold.
- UpdateScrollbars915: visible fraction shrinks during overscroll.
- PointerInputModule.ProcessDrag: screen-space squared threshold, begin at current pointer, cancel click when drag begins.

Title.unity component420698986 has vertical1/horizontal0, Elastic1, .1 elasticity, inertia1, .135 rate, sensitivity1, permanent vertical bar. Content1104074887 is top pivot and top-stretched; EventSystem threshold10. This adapter supports that axis-aligned branch only, not arbitrary rotated bounds, horizontal/two-axis or alternate movement modes.

SmoothDamp is mapped from official UnityCsReference6000.5 branch pinned10c26351b76d5bac78613f94abd7bb1ff331adb2, Runtime/Export/Math/Mathf.cs. This helper evidence is same release family, not independently verified exact editor mirror. Infinite maximum speed is the sole mapped overload. GDScript double arithmetic is not claimed bitwise identical to C# float.

## API and integration

source_scrollrect_vertical.gd owns source upward-positive anchored position, velocity and frame state. configure(fields) rejects unsupported axes/movement; wheel, initialize_drag, begin_drag, drag, end_drag, step(unscaled_seconds), set_normalized and bar_fraction expose the mapped behaviors.

source_saved_slot_host.gd replaces native ScrollContainer with a clipped Control, avoiding native clamping and duplicate wheel/inertia. Content.y=-source.position. It reads a real monotonic clock rather than scaled simulation delta. Mouse input observes without accepting wheel, preserving camera wheel-over-UI. Drag threshold uses screen pixels; local cursor uses inverse canvas transform. Click callbacks are guarded through release after drag. Save/load/archive transactions are untouched. Hiding resets drag/velocity/scrolling as source OnDisable does.

source_title_view.gd forwards actual ScrollRect fields and EventSystem drag threshold.

## Remaining boundaries

Native VScrollBar appearance, minimum handle size, scrollbar page-click repeat/key navigation are still Godot-native, not original Scrollbar equivalence. Native rectangular clip does not claim source soft-mask edge parity. Input regression uses injected mouse events and callback assertions, not actual rendered pointer QA. Touch/multi-pointer and arbitrary transforms are unsupported. No full 1:1 UI claim. Source wheel state is preserved by non-consumption; actual simultaneous camera response still needs parent's native QA.

## Verification and integration manifest

Passed headless Godot4.6.3: numerical state18/18; synthetic slots; source SavedGames board with injected drag below/above threshold, rubber overscroll, no click during drag or release frame, one-step wheel, archive/cancel/confirm/restore/load; Title navigation24; menu focus64; slot management UI24; slot UI50. Invalid guessed test filenames were corrected and actual named suites rerun. No native screenshot test claimed.

Regression caught scrollbar range synchronization emitting value_changed and resetting overscroll. Programmatic page/value updates now suppress signals. Godot Range maps handle fraction as page/max and value span as max-page; adapter converts this to source normalized value explicitly. This does not replace the remaining native scrollbar input/skin.

Scoped implementation files:
- new scripts/ui/source_scrollrect_vertical.gd
- modified scripts/ui/source_saved_slot_host.gd
- scoped install_saved_rows parameter-forwarding addition in scripts/ui/source_title_view.gd
- new tests/godot/test_source_scrollrect.gd
- modified tests/godot/test_source_saved_slots_board.gd
- this document

Do NOT copy the entire snapshot, its assets symlink, data, or reference directory into public git. Parent must merge scoped Title changes and add the numeric test to public test_all registration. Main repo was not modified. Official Mathf pinned raw bytes verified identical SHA25635f1020cfd7a979ad39761cda31d8537f7525a044d0c1a1021c1e3ade3923044.

First-layout regression: before entering tree, native bar.size.x is zero even after custom_minimum_size.x=20. Previous row calculation produced width780 inside clip780 with10px padding on each side (20px too wide). relayout now resolves clip_width once from source allocation and uses it for both row layout and clip. New public test_source_scrollrect_layout.gd asserts first synchronous row760/clip780/content780 without awaiting any resize callback. Both source board and18 numeric checks rerun PASS.

PageUp/Down audit: no explicit PageUp/Down/ui_page action binding found in project scripts/project.godot, and source ScrollRect defines no OnMove/OnSubmit key handlers. Current native VScrollBar may receive engine-default focused navigation; this is not evidence of source key equivalence. No new key routing added; original Scrollbar/EventSystem keyboard mapping remains outside this patch.


Integrated native check: at 1280×800 a real pointer drag visibly displaced four
rows into top overscroll, compressed the handle, then settled back without
activating row actions. No overflowing long list or native scrollbar keyboard
acceptance is claimed. A zero-initial-width bar regression now requires first
row 760 / clip 780 with 20 source units of horizontal padding, before any resize callback can repair
it. All programmatic sizing uses one resolved clip width.
