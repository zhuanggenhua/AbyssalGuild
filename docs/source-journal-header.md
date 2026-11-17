# Journal header source mapping

This batch ports the locked UIRoot QuestsToggle/RecipesToggle header separately from the existing body ownership. The original Unity source is unchanged.

- Resolve Toggle, its separate flat Image `graphic`, TMP `m_TargetGraphic`, and no-switch-off ToggleGroup by local component references. Settings text-only Toggle adapter is not broadened.
- Keep the Header Image as one background below both transparent native buttons. Equal horizontal expansion and the existing source Canvas reference geometry remain unchanged.
- The checked blue graphic interpolates alpha for 0.1 unscaled seconds, independently of the TMP ColorBlock transition. Pressed/selected/hover/disabled only tint the target label. Reversal starts at current alpha. An active-tab click repeats its existing callback and restarts its own unfinished alpha fade; the other already-off Toggle does not restart.
- Retain source strings, size, exact private font binding. With private TMP face metrics, place the native text baseline by `(height + (ascent + descent) * fontSize / pointSize * faceScale) / 2`. Font shaping/placement is recomputed only at configuration or actual resize, not every frame. This is a native-glyph rendering bridge, not a TMP SDF pixel parity claim.
- Missing metadata remains a visible conventional text button; missing font metrics retain explicit native text-layout fallback. No private font, image or source document is published.

Focused private checks (27/27) exercise actual board start, exact references, geometry, source face binding, separate fade/tint targets, reversal, re-click, source body callback, ordinary HUD refresh, actual viewport left-click release and right/disabled rejection, and zero-time-scale processing. Existing journal body and 2D font suites remain applicable. The strict imported runner requires its completion marker.

Not accepted by this change: source ScrollRect body geometry/physics, TMP SDF appearance, complete uGUI directional focus-search ordering across all controls, real desktop input, full-frame Unity-vs-Godot screenshots, whole migration completion. Native Button admission retains the existing board menu/modal guard.
