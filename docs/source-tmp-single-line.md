# Bounded static TMP title layout

Original project lock a11a89b04cea8370476f2559b639bb9b4cbc08d8 uses Unity6000.5.4f1. Exact official uGUI2.5.0 source reference is Unity-Technologies/uGUI commit b394b8ab4f985d25230da1bb02268dcb3c85cb19, `com.unity.ugui/Runtime/TMP/TextMeshPro.cs` and `TMP_Text.cs`. Reference files remain outside the distributable patch.

Source call chain: StackCraft `Scripts/Card/CardInstance.cs:98,534` assigns Definition.DisplayName directly to titleText. It does not call preferredWidth. World TextMeshPro.OnPreRenderObject reparses input and starts at clamped m_fontSizeBase (2149), with the source min/max; repeated GenerateTextMesh calls settle the point size (2169). GenerateTextMesh scale uses pointSize/sourceFacePointSize*faceScale*(orthographic?1:0.1) (2232). Horizontal bound is the current advance plus current glyph advance (3037). Vertical overflow shrinks (3075), no-wrap horizontal overflow shrinks (3542-3580), successful upper search grows (4137). Steps are max(half remaining interval,0.05), rounded to 0.05 point; 100 iteration guard. Minimum is not violated even if overflow remains.

TMP_Text.GetPreferredWidth (3695) is a DIFFERENT request: uses max point size when autosizing and infinite margins, then CalculatePreferredValues. It is not the title autosize algorithm and this change does not route title fitting through preferredWidth. No unsupported preferred-width equivalence claim is made.

Plain single-line glyph advances, character/word spacing and horizontal pair adjustments are measured from hash-verified private static SDF metadata, not native Font.get_string_size. Legacy m_enableKerning maps to kern in TMP_Text.LoadDefaultSettings (6030); the locked prefab has no newer feature list. Additional importer fields retain actual serialized values. normalSpacingOffset is now retained from the locked SDF; it is not guessed. Card_Resource title source max1.2/min0.4 and PackInstance max1/min0.4 control layout. PackInstance's directly parented Title previously lacked font/layout metadata in the fallback extraction branch; it now retains the same source fields and exact GUID.

Supported branch: static glyphs, normal400 style, ASCII printable single line, ordinary no-wrap/overflow, left/center/right alignment, zero character-width compression, ordinary pair flags and no vertical pair adjustment. Rich tags, missing glyphs/metadata, multiline/non-ASCII, nonnormal style, compression, other overflow/alignment and nonzero feature flags explicitly return unsupported. Existing native fitting remains explicitly tagged unsupported_native_fallback, not silently claimed as parity.

The selected source point size controls physical label scale with the source perspective multiplier. Godot font_size is only raster resolution (source atlas sampling point size); it no longer chooses fitted point size. Per-glyph raster shape, baseline/alignment, native kerning/shaping, SDF atlas sampling and framebuffer pixels are NOT proven equivalent. A title may therefore still need rendering-level migration despite correctly selected source point size.

Validation: synthetic source-metric fixtures cover bounds, min/max, quantized horizontal/vertical search, perspective multiplier, kerning, disabled autosize, and explicit unsupported text. Private isolated audit covered 12 source card prefab title records plus PackInstance, each with 4 test strings (52 cases), including exact-font registry binding and physical scale assertion. This is algorithm/source-data validation without Unity execution, not rendered Unity/Godot differential testing. Private audit inputs and reference source are deliberately excluded from integration.patch.

Integration requires rerunning private font supplement importer and visual importer so new metrics hashes and source layout fields are present. Older manifests intentionally select explicit fallback. The public runner registers test_tmp_single_line_layout.gd with marker `Source TMP ASCII fit: PASS`.

## Strict full-title test and regeneration

`tests/godot/test_tmp_titles_imported.gd` reads only the actual ignored visual/font manifests and catalog at runtime. Missing inputs fail, never SKIP. It resolves every static displayable card/pack title in Main and Island, plus every dynamic recipe title produced by the existing source-mapped RecipeCardDefinition factory. Unnamed recipe template assets are separately counted and must match that scene's actual recipeCardTemplate GUID; they are not renamed or counted as successfully laid-out titles. Unsupported displayable cases print individual reason and fail the test. Each supported case also tests explicit unsupported-rich-tag fallback.

Measured current inventory after fresh isolated reimport: 406/406 displayable titles supported (204 card,22 pack,180 dynamic recipe), 2 unnamed template appearances separately reported, 0 minimum-overflow cases, 0 unsupported displayable cases. These are scene-expanded counts, not 406 unique assets. Marker: `Imported source TMP titles: PASS`.

At the source minimum, exact TextMeshPro.cs Overflow cases at3094 and3593 explicitly ignore vertical/horizontal bounds and continue rendering. The adapter retains the minimum and overflow flag; it does not shrink below minimum to satisfy an invented no-overflow invariant. The synthetic test covers that branch even though the current title inventory has no such case.

Run from the project root after code integration (all outputs remain private/ignored):

```sh
python3 tools/import_source_fonts.py --source source/font-supplement --lock source/font-supplement/lock.json --catalog data/stackcraft.json --output assets/imported/fonts --acknowledge-license
python3 tools/import_visual_assets.py --source source/CardLoop/Assets/StackCraft --catalog data/stackcraft.json --output assets/imported --acknowledge-license
bash tools/test_godot.sh res://tests/godot/test_tmp_titles_imported.gd
```

The font input bundle includes its original SDF/TTF/meta/license/TMP Settings and the existing commit/hash lock. No supplemental source scope is broadened. The strict private runner registers the full-title test with the exact marker above; the synthetic test is in the public runner. Neither test copies private inputs into tracked fixtures.
