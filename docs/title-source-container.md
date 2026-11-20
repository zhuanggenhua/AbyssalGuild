# Title source container API

`source_title_view.gd` is a caller-wired visual shell, not a replacement save or
settings implementation. Its private inputs are the already imported Title
scene documents and VisualAssets. It does not require an importer change.

## Source evidence

- `TitleScreen.Start` invokes GameplayPrefsUI.Open, SavedGamesUI.Open,
  GameOptionsUI.Open, and a quit modal. None hides Home.
- GameplayPrefsUI and SavedGamesUI independently activate/deactivate their own
  full-screen overlay. This differs from native mutually exclusive pages.
- Title Canvas uses ScaleWithScreenSize, reference height 1080, height match 1.
- MenuPanel is a left-anchored width-500 full-height vertical group. Child order,
  padding, fixed heights, extra flexible space and alignment come from the scene.
- Artwork Background is stretched; MenuPanel/Title preserves image aspect.
  The similarly named GameplayPrefsUI/MainPanel/Title is text, not that logo.
- Preferences has a centered 500×330 panel; saves has a centered 800×800 panel.
  Their full-screen backgrounds have their own scene image tint/raycast state.

## Caller integration

1. Create `SourceTitleView`, add it to the intended layer, size it to the viewport.
2. `configure(catalog.data, visual_assets)` returns false if supported Title
   Canvas metadata is absent. No fabricated source artwork is generated.
3. `mount(role, existing_control)` reparents a control without changing values,
   signals or transaction callbacks. The four Home buttons use the actual
   source TMP caption and alignment; other mounted controls keep caller text.
   Supported roles: `new`, `load`,
   `options`, `quit`, `duration_label`, `duration`, `friendly`, `confirm`, `cancel`,
   `saves_close`, `saves_clear`. It maps scene geometry and font size/color, not
   save/delete semantics. Never wire native archive to source permanent-delete
   behavior merely because the scene calls the corresponding button Clear.
4. `set_overlay("preferences", active)` and `set_overlay("saves", active)` each
   change only their own overlay. Home stays visible. Caller retains modal/input
   gates, transition ownership, focus restoration and mutual exclusion if needed
   for native safety, without hiding Home artwork.
5. Exposed `home`, `preferences_overlay`, `saves_overlay`, `preference_content`,
   `saves_content`, `nodes` permit caller placement. The source Content rectangle
   is an insertion point, not a ported SavedGameSlot list/scroll implementation.
6. `relayout()` runs on resize and applies source reference coordinates beneath
   the canvas scale. Source child-path resolution avoids duplicate-name matches.

## Deliberate limits

`board.gd` now installs this shell after catalog/media loading, reparents existing
controls without replacing their callbacks, and keeps Options/faders above it.
Home stays visible beneath preference/save overlays but cannot receive focus or
button activation until the overlay closes. Gameplay return releases the private
board and hides generated 3D geometry behind the Title Canvas. Existing native
options, save archives, legacy adoption, modal transactions and settings remain
caller-owned. The save viewport hosts a native scrollable transaction list; its
footer says Archive All and retains recoverable archiving, not permanent deletion.
Original TMP font is unresolved, and character spacing/glyph metrics are not
claimed equivalent. Mounted Prefs slider/toggle widgets now use the source component adapters
described in source-control-adapters.md; source TMP glyph metrics and untested
touch/out-of-window pointer behavior remain explicit limits. Horizontal footer layouts currently use serialized source
RectTransforms; dynamic preferred-text-width relayout is not implemented.
External modal/options prefab instances and screen fade remain caller-owned.
Source version text runtime updates and saved-slot prefab population are not
implemented here. Tests validate geometry and control ownership, not native
visual acceptance or full Title parity.

## Integrated regression checks

Title navigation (24), gameplay preferences (7), menu focus (64), GUI layout /
Title reset (52) checks passed after integration. These include repeated
New Game/Confirm, cancel, modal priority, error handling and repeated return to
Title. The helper private-scene test also passed.

## Native Title text and backing

The four authored Home TMP captions are left aligned with middle vertical
alignment in their existing 400×50 design rows. Native buttons now use each
caption and horizontal alignment, including `Game Options` (not `Options`).
The hover underline starts at the same alignment edge. Only the authored
Home rows are affected; the fallback and settings transactions are unchanged.

With licensed data, run `test_source_title_frame.gd` from a rendered Godot
desktop. It samples 1152×648 and 960×720 on cold startup and after the real
Pause → Title path, verifies the fully opaque original backing covers the
world clear, compares uncovered samples with the source image, and reads
actual left-aligned, vertically centered button ink and the hover-signal underline.
Clicking the real Game Options button must still open the settings overlay.
This is native Godot behavior, not Unity/Godot framebuffer equivalence or
exact TMP character spacing, fallback glyph metrics or baseline. The normal
resolved backing needed no camera change; no claim about a partially
populated private configuration without the artwork.
