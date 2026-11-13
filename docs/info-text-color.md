# InfoPanel source text-color mapping

This is one bounded template-source omission, not a screenshot adjustment or
whole-HUD equivalence claim. The reference remains StackCraft
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`; neither another repository's logic nor
later same-repository scene implementations are substituted.

## Cause and source identity

`Prefabs/UI/UIRoot.prefab` (GUID `5e2985d7789c5254b831d166e6931134`)
contains `UICanvas/InfoPanel/InfoText`. The `InfoPanel.infoText` reference points
to its TMP component, file ID `6875133755084796725`, whose `m_fontColor` is
RGBA `(1, 1, 1, 0.8)`. Vertex gradient is disabled. Both `Scenes/Main.unity`
and `Scenes/Island.unity` reference this prefab; applying their 94 and 87
instance modifications respectively leaves this value unchanged. They add or
remove no components/objects in this instance and have no external parent.
The InfoText-to-UIRoot ancestor chain contains no CanvasGroup. The panel Image's
own alpha is background color, not inherited text opacity.

`InfoPanel.UpdateInfo` combines header/body using size tags and writes text only.
It does not replace the component color. Input strings can still contain TMP
rich-text tags; the native panel's pre-existing plain-text limitation is separate.

The migrated panel splits that one source text component into a native Label
and RichTextLabel. Font binding preserved identity but not `m_fontColor`; both
native theme colors were observed as opaque white, with ancestor modulation
also white. Thus the source's text alpha was lost, not already inherited.

## Bounded correction

Board resolves the exact existing `InfoPanel/InfoText` component record and
passes its four color channels to `card_hover_view.gd`. Only the Label's
`font_color` and RichTextLabel's `default_color` are overridden. Container
modulation, background, independent action button, font, text, vertical alignment,
geometry, request priority and gameplay/save state are untouched.

Missing or malformed color data removes these source overrides and restores
native theme defaults, including after a previously valid binding. It does not
invent white/0.8 or retain a previous source's color. This is a metadata-to-native
text-color mapping, not TMP SDF rasterization, rich-text or pixel equivalence.

## Evidence boundaries

The public synthetic suite checks non-white RGBA, transparent alpha, descriptor
changes, relayout, no background/modulation changes, and missing/malformed
replacement fallback. The private HUD suite checks the actual source value,
both native text nodes, separate action color, update and relayout retention.
Before the production change the four native source-color assertions failed;
after it they pass. Original resources and private evidence stay out of Git.

The equipment-panel camera-pan candidate was disproved independently: its real
collider supplies both wearer `card_id` and `panel_owner`, so the existing left
press gate already blocks panning. No camera or input code changes are part of
this batch. HUD vertical alignment lacks a separate preferred-height/layout
proof, so no top/center/bottom guess is applied. Headless tests are not physical
pointer/touch tests or visual acceptance.
