# Source desktop face mapping

## Narrow correction

Locked Unity source is a11a89b04cea8370476f2559b639bb9b4cbc08d8. Its
SimpleLit.shadergraph has UniversalTarget RenderFace=2 (Front), opaque surface,
material overrides disabled and unmodified vertex/normal slots. URP
[UniversalTarget.cs](https://github.com/Unity-Technologies/Graphics/blob/c930feab9f105738328d183bb3c32758d8da0ac3/Packages/com.unity.render-pipelines.universal/Editor/ShaderGraph/Targets/UniversalTarget.cs)
maps Front to Cull.Back, not double-sided. The graph byte digest is pinned as
ecac38c65d483b39fdb2d6032cfbb0bad6d3d856b5183ea657da8c455a1ce0fe.

Main's Board01 and Island's Board02 use the same Board.fbx and four authored
SimpleLit Body/Header materials. Source scene overrides retain identity rotation
and unit scale, and set Y=-0.05. Godot's existing conversion reflects Z; this
changes triangle face classification, but must not add a sign to the independent
inverse-transpose normal transform. No geometry, normal, triangle index, morph,
coordinate conversion, color, light, shadow or camera setting is changed here.

The material importer now emits SimpleLit-only schema 3 with render_face=2,
cull_mode=back, double_sided=false and
normal_policy=inverse_transpose_no_face_flip. Runtime requires the exact graph
digest and the existing opaque, geometry, pipeline and renderer contract. Old
schema 2 desktop metadata fails closed and requires a fresh private import.
Unknown graphs/contexts keep the existing fallback. The actual board factory
sets source_board_cull=back; the flat-composition binder additionally requires
that marker, its exact shader and all previous live context checks. Its original
material and replacement use Cull.Back, and fallback restores the same original
object. Card metadata/output and shader fragment/direct-light function are
unchanged. A fifth SimpleLit material (TradeZone) gets truthful imported metadata
but gains no new runtime binding from this board-only change.

## Reversible and native evidence boundaries

The previous native actual-FBX diagnostic used official Godot 4.6.3 Compatibility
on llvmpipe, with real root 682x512. Current old production and source-lit were
identical at center RGB 63/73/88; direct-only was zero. Effective fragment normal
was -Y while independent inverse-transpose normal was +Y. Face diagnostic was
back-facing and N dot L was approximately -0.707. Only diagnostic Cull.Back
restored direct-only RGB 93/97/88, without changing indices/light/shadows. Its
157/170/176 ambient+direct color was not the final combined-correction target.
This is causal Godot evidence, not a Unity screenshot/GI comparison.

The actual-FBX headless test is reversible against the unchanged 775c324e base.
It checks Main/Island, both surfaces, boost 0/1, indices/normals, reflected
determinant, inverse-transpose +Y, material/fallback identity and unchanged Card
bytes. It explicitly says structure only, not pixels.

The separate native probe uses current production factory and binder on real
privately imported Main/Island FBX. Controlled orthographic cameras target an
interior triangle on each surface (not original gameplay screenshots). It captures
28 cases: both scenes/surfaces and boost 0/1, ambient/direct-only/below-face, plus
real shadow-only blockers. It checks the existing flat-linear+direct formula,
back-face absence, measurable shadow attenuation and ambient invariance. Original
source lighting/shadow values stay intact; only background is diagnostic black.
Headless returns NOT RUN / 2 and cannot pass. Actual native results are recorded
separately with hashes and exact candidate tree. Each isolated probe detaches its
world synchronously before constructing the next one and records the actual
WorldEnvironment/light inventory. Immediate admission and readback admission both
must pass; this is not a relaxation of the pixel tolerance.

A separate native `board_face_probe/lifecycle.gd` exercises a single real
production Board world across Main/Island/Main, rebuilds, boost 0/1/0 from
diagnostic generation of existing source booster definitions, extra-light and
transparency fallback/restoration, Title cleanup and final destruction. It waits
for real GPU frames and checks material identity. This is a diagnostic fixture,
not natural gameplay or pixel parity. The invoking runner must also reject
engine errors even if a script's own assertions pass.

The first paired native run of the face correction passed the candidate's pixel,
back-face and shadow assertions but failed two immediate binding checks and
reported backend null-material errors. That run remains a failed acceptance,
not a pass. Its causal attribution must be kept separate from later deterministic
fixture and actual production-lifecycle results; no tolerance was changed.

Commands:

```sh
GODOT_RENDERING_METHOD=gl_compatibility bash tools/test_godot.sh res://tests/godot/test_board_face_mapping.gd
bash tools/test_all.sh
bash tools/test_imported.sh
# Only on an explicitly coordinated native display, isolated HOME/XDG:
godot --audio-driver Dummy --rendering-method gl_compatibility --path . --script res://tests/rendering/board_face_probe/probe.gd -- --output=/private/output
```

No original assets/images belong in this repository. Native probe output is
private. This does not establish Unity unknown SH/GI, exact shadow filtering,
other renderers/devices, the Card back-face path, or full visual equivalence.
