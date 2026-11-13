# Source Middle baseline, separate from SDF rendering

## Evidence

Original project: CardLoop a11a89b04cea8370476f2559b639bb9b4cbc08d8. Actual card/pack titles use TMP vertical alignment512 (Middle), center RectTransform pivot(0.5,0.5), static font GUID8f586378b4e144a9851e7b34d9b748ee, and shared material fileID2180264 of that font asset. The authored label transform already includes y=0.001 separation; this change does not alter that pose.

Exact editor package: Unity-Technologies/uGUI b394b8ab4f985d25230da1bb02268dcb3c85cb19, `com.unity.ugui/Runtime/TMP/TextMeshPro.cs`4191-4206: Middle baseline is rectangle vertical center minus half of (source ascender + top margin + source negative descender - bottom margin). Equivalently: content-center y minus half of (source ascender + source negative descender). Source metrics are scaled by selected pointSize/sourceFacePointSize*sourceFaceScale*(orthographic?1:0.1). Glyph geometry subsequently uses source horizontal bearings, vertical bearings, padding and glyph adjustments at2839-2857.

Godot4.6.3 commit7d41c59c4 `scene/3d/label_3d.cpp`574-608: CENTER starts at half shaped line height, then subtracts TextServer shaped ascent before generating glyphs. Thus native baseline is content-center y + (native shaped lineHeight/2 - native shaped ascent)*pixel_size. It is not necessarily the source SDF FaceInfo baseline even when the source TTF family and point size are bound correctly.

## Bounded correction

For supported source single-line ASCII layout only, TMP Middle + centered pivot + unit static glyph/character scales, compute both baselines using their own verified metrics. Apply their difference to Label3D text offset.y, not position/transform, size, source mesh, depth behavior or fitted point size. Native text shaping uses the same bound font, font size, language and text direction. Rect pivot is now retained from original metadata rather than assumed. Unsupported alignment/pivot/glyph scales/native label mode remain explicitly reported in source_baseline_result and do not receive a guessed offset.

Source stat text with other vertical alignment, non-ASCII, rich text and full TMP geometry/SDF renderer are outside this patch. Existing native glyph shaping and horizontal positioning remain separate parity limitations.

## Exact material/atlas reference and why this is not raster parity

The source SDF material's shader GUIDfe393ace9b354375a9cb14cdbbc28be4 is exactly `Assets/TextMesh Pro/Shaders/TMP_SDF-Mobile.shader` (verified same-lock .meta), shader name `TextMeshPro/Mobile/Distance Field`, blob b899d6e9d78c7885a8c90e39574fdc6252d11fe0. Material_MainTex and font m_AtlasTextures both point to embedded Texture2D fileID28684132378477856, 1024x1024 Alpha8, one mip, bilinear filter. Material GradientScale10, PerspectiveFilter0.875, FaceDilate0, OutlineWidth0, OutlineSoftness0, WeightNormal0; face white modulates source text color.

This shader uses premultiplied blending `One OneMinusSrcAlpha` (79), projection-dependent screen pixel scale (144), view-normal perspective filtering (146), weighted bias (154), then samples original atlas alpha and applies threshold coverage (210-215). Godot Label3D currently rasterizes the original TTF using native font resources; it does not sample this original atlas or reproduce those vertex/pixel calculations. Corrected baseline therefore cannot establish glyph edge/SDF/material/framebuffer equivalence. Original atlas, font and source shader are NOT distributed in this patch.

## Tests and integration

Public synthetic `test_tmp_title_baseline.gd` checks source baseline algebra, very different ascent/descent (95/-1 versus1/-95), world0.1 scale, immutable physical pose/point size/horizontal offset, noncenter/missing pivot, unsupported alignment and element scale. Marker `Source TMP Middle baseline: PASS`.

Strict private `test_tmp_baselines_imported.gd` reads ignored manifest/catalog/font metrics at runtime. Current regenerated source inventory: 406 displayable scene-expanded card/pack/recipe titles, all supported with baseline formula equality and unchanged physical transform; two unnamed recipe template appearances are separately reported. Marker `Imported source TMP title baselines: PASS`. No copied original fixture or source shader is needed by the tests.

Re-run private visual importer after integration to retain rect_pivot. Older manifests explicitly leave baseline uncorrected with missing-pivot status. Font supplement inputs do not change in this patch. Run public synthetic and strict private markers above. This is source/formula and runtime-metric testing, not Unity-rendered image comparison.

The locked font was rechecked: FaceInfo scale is1, and all250 glyphs and250
characters have scale1. The native-raster source-layout branch now explicitly
rejects missing/nonunit face or element scales. TMPLayout can measure scaled
metrics, but that is not sufficient proof that Label3D rasterizes independently
scaled elements. `test_tmp_native_scale_guard.gd` exercises actual Title.fit for
unit success and nonunit face/glyph/character fallback.
