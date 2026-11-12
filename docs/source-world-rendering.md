# Scene world rendering mapping

This audit follows the locked StackCraft source, not screenshot color sampling.
Original files and generated metadata remain private.

## Concrete omissions found

- `Scenes/Main.unity`: MeshRenderer `37186789`, owner `37186788`, built-in
  plane mesh `10209` (built-in resources GUID ending `e000000000000000`). Its
  material is `Materials/Backgrounds/Grass.mat` (`dcf9ea3af4487d84183f3b6a25339ca3`).
- `Scenes/Island.unity`: equivalent renderer `150755374`, owner `150755373`,
  material `Materials/Backgrounds/Water.mat` (`573bf8f1a1075a943bc07e1ee8e232bf`).
- Both scene-authored planes had been omitted by the private visual importer.
  Their transform is position `(0,-10,0)`, quaternion `(0,1,0,0)`, scale
  `(10,1,10)`. The Unity built-in plane is 10 units square before scaling.
- Both materials reference built-in shader `10752`, Unlit/Texture, and `_MainTex`
  tiling `(20,20)`, offset zero. The source textures use repeat in both axes,
  bilinear filtering and mipmaps. Unlit/Texture does not consume the stale
  saved `_Color`, `_Glossiness`, normal-map or metallic properties.
- Scene `RenderSettings` were also omitted: flat ambient (`m_AmbientMode=3`),
  ambient color `(0.60480005,0.63552,0.72)`, intensity 1, fog disabled,
  no custom reflection texture. A hardcoded blue-green native environment
  therefore did not represent these source values.

## Supported adapter

`world_visual_metadata.py` preserves scene renderer references, transforms,
shadow flags and RenderSettings. `source_world.gd` supports only the explicitly
recognized built-in plane + Unlit/Texture combination with bilateral repeat
and bilinear sampling; unknown combinations are skipped, never assigned an
invented appearance. Geometry and material tiling are independent of viewport
size. Missing private textures produce no fabricated background.

The public tests use synthetic source records and synthetic white pixels.
They verify transform, mesh size, material mode, UV scale/offset, shadow mode,
ambient fields and unknown/missing input behavior. They are not image parity
proof. Native scene attachment/removal and visual checks are separate.

## Board material audit

`Shaders/SimpleLit.shadergraph` (`c84a8a85a3eea0c4a9265cddfd04e1a5`) has
one connection: `_Color` property to BaseColor. Its constants are metallic 0,
smoothness 0, emission 0 and ambient occlusion 1. There is no texture sampling,
UV animation or custom light function to migrate. Both board surfaces use this
graph through `Materials/Boards/Body_01`, `Header_01`, `Body_02`, `Header_02`.
The Godot adapter explicitly preserves color, roughness 1 and metallic 0.
Adding grass to the board surface or guessing a gray tint from the screenshot
would contradict the source: grass belongs to the separate background plane.

## Remaining boundaries

- StandardMaterial3D is a material-input mapping, not an exact port of Unity's
  Lit BRDF, color-management pipeline, reflection probes or shadow filtering.
- Built-in primitive UV orientation and source-engine mip selection still need
  asymmetric reference-image verification; scale/offset tests alone cannot
  establish texel-for-texel parity.
- RenderSettings sky/gradient ambient, fog, skybox/custom reflection textures,
  and unsupported scene meshes are not implemented by this narrow adapter.
- The source snapshot does not contain Unity's built-in shader implementation.
  The background uses the identified Unlit/Texture semantics, not a copied
  proprietary shader; rendered color-space equality remains unverified.
- Screenshot localization/UI layout and original renderer version may differ;
  no global one-to-one completion claim follows from restoring these omissions.

## Card black-background root cause: importer alpha semantics

The locked `Textures/CardArts/{Rock,BerryBush,Villager}.png.meta` files set
`alphaUsage: 2` (TextureImporterAlphaSource.FromGrayScale), while their original
PNG pixels have opaque input alpha. Merely copying these PNGs and loading them
in Godot loses Unity's import-time alpha generation. The existing graph's
correct `lerp(base, art*tint*rectangle, resulting_art_alpha)` then replaces the
whole artwork rectangle with its black RGB background, instead of preserving
the card's base texture beneath transparent artwork pixels.

Full private-input audit: 173 assets include 150 PNGs; 115 use alphaUsage 2 and
all 115 have equal R/G/B at every source pixel. The remaining 35 use input alpha
(mode 1). Therefore no guessed luminance weighting is necessary: generated alpha
is the grayscale channel. Non-gray mode-2 inputs are explicitly unsupported.

The importer now records `alpha_usage`. Runtime texture binding applies that
semantic to both imported/cached Texture2D images and raw-PNG fallback, without
changing copied source bytes. Mode 0 makes alpha opaque, mode 1 preserves it,
mode 2 derives it from grayscale; unknown modes fail closed. Mipmaps are rebuilt
after alpha conversion. Older manifests without this metadata retain their
previous behavior and must be reimported to obtain the correction.

Independent source-graph audit confirmed the existing artwork lerp order,
rectangle width/height and flash composition, not a missing guessed base color.
A read-only imported-mesh audit found the top surface's 52 normals upward in
Resource, Character and Consumable meshes after the existing coordinate bridge;
no flipped upper normal explains this black rectangle. Source front-face versus
native two-sided culling is a separate remaining difference, not the alpha bug.
