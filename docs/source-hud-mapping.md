# Source HUD mapping audit

This batch ports the locked `UIRoot.prefab` screen-space HUD, not the Title scene.
No screenshot-derived translation or replacement assets are included.

## Cause of the mismatch

The original UICanvas uses ScaleWithScreenSize, 1920×1080, MatchHeight=1.
A source coordinate is scaled by viewport height / 1080; the logical width varies
with aspect ratio. The previous 1440×900 fixed native panels were not this mapping.
`source_hud_layout.gd` resolves the imported GameObject/component references and
RectTransform anchor, position, pivot and extent. The native project stretch is
unchanged; an inner HUD transform preserves the source height scaling.

The source DayTimeUI is top-left (30,30), 300×50. CardStatsUI starts (360,30),
height 50 with content-preferred width. MenuPanel is right-anchored, full-height,
400 wide, with 60-high tabs and a 60×60 toggle at (-60,60) relative to the panel.
InfoPanel is 400 wide at bottom-left (30,30), using preferred text height.
Watermark is bottom-centred 600×40. These are extracted, not screenshot guesses.

## Behavior

Day progress fills the complete background, not a native bottom progress strip.
Stats are nutrition/need, currency, cards/limit using their source sprite references.
Journal items use short source rows; descriptions/progress/ingredients are hover
information, not inline replacements. Unread markers are trailing red dots.
The shared InfoPanel request queue arbitrates Hover < Sequence < Modal and recent
requests of equal priority. Vendor unlocks and day-cycle instructions use that
panel. Feed People, Start Day and Return to Title remain gated through the existing
safe action dispatcher; natural day end replaces the added manual End Day control.
Native inspection/convenience actions remain explicitly named debug controls and
are not inserted above the source journal. They are hidden by default; F3 opens
them without adding a replacement button to the source HUD. Ordinary diagnostic notices are visible
with that debug panel, not a replacement source watermark.

## Known limits, not claimed parity

The locked subtree and full supplied CardLoop checkout do not contain the TMP font
GUID `8f586378b4e144a9851e7b34d9b748ee`; native font rendering remains a fallback.
Thus preferred text measurements, baseline and glyph shape cannot be called 1:1.
Godot native text wrapping and rich-text handling are not Unity TMP rendering.
For exceptionally long descriptions the native panel caps to the available screen
height and scrolls, rather than allowing the source preferred-height panel to leave
the viewport; ordinary descriptions retain their preferred height.
The source source strings are English. The user's reference screenshot is Chinese;
that translation is not present in the locked data and has not been fabricated.
Title, pause/options typography, save-management layout and the optional debug UI
are outside this batch. Static/headless tests are not rendered visual acceptance.
