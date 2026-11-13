# Bounded source direct-light migration

## Reconstruction status

This candidate was reconstructed after the earlier, uncommitted 26-file direct-light
snapshot became unavailable. It is **not** a byte-for-byte recovery of that snapshot.
The preserved base is local `b7cd193` / tree
`0fb41fea693dfb3d7ade72adc3480258129ab00a`. Historical test counts and screenshots do
not validate these newly reconstructed bytes.

## What causes the difference

The source files named `Card.shadergraph` and `SimpleLit.shadergraph` have an active
Universal Lit target. The filename “SimpleLit” is not a shader-model declaration.
For the admitted source graphs, metallic and smoothness are both zero, the surface
is opaque and double-sided, and the graph does not override vertex position,
vertex normal/tangent or tangent-space normal. Import-time metadata proves this
bounded contract and records the actual graph hash. Material keywords, target,
geometry, pipeline and render mode must pass runtime admission; unsupported input
retains the existing fallback rather than being labelled equivalent.

The source reference is Unity Graphics commit
[`c930feab9f105738328d183bb3c32758d8da0ac3`](https://github.com/Unity-Technologies/Graphics/tree/c930feab9f105738328d183bb3c32758d8da0ac3).
The relevant branches are `InitializeBRDFData`, `DirectBRDFSpecular` and
`DirectBRDF` in
[`BRDF.hlsl`](https://github.com/Unity-Technologies/Graphics/blob/c930feab9f105738328d183bb3c32758d8da0ac3/Packages/com.unity.render-pipelines.universal/ShaderLibrary/BRDF.hlsl).
These are not Godot's stock Burley/Schlick-GGX equations. A screenshot-derived
color multiplier would not reproduce the angle-dependent difference.

For full-float desktop arithmetic, metallic 0 and smoothness 0 simplify the
source direct-light response to:

- Diffuse reflectance: `0.96 * linear_albedo`.
- `H = SafeNormalize(L + V)`; `LoH = saturate(dot(L, H))`.
- Specular reflectance: `0.04 / (6 * max(0.1, LoH²) * 1.00001²)`.
- Final direct RGB: `(diffuse + specular) * light_rgb * attenuation * saturate(N·L)`.

This branch does not add a separate `pow(1 - LoH, 5)` Fresnel term.
`SafeNormalize(float3)` uses the minimum normalized positive float
`1.175494351e-38`, as specified in the same commit's
[`Common.hlsl`](https://github.com/Unity-Technologies/Graphics/blob/c930feab9f105738328d183bb3c32758d8da0ac3/Packages/com.unity.render-pipelines.core/ShaderLibrary/Common.hlsl)
and
[`Macros.hlsl`](https://github.com/Unity-Technologies/Graphics/blob/c930feab9f105738328d183bb3c32758d8da0ac3/Packages/com.unity.render-pipelines.core/ShaderLibrary/Macros.hlsl).
An arbitrary epsilon or `normalize(0)` is not substituted.
The FP16 `REAL_IS_HALF` correction is outside this desktop full-float subset.

## Godot boundary

In nonphysical Compatibility lighting, `LIGHT_COLOR` includes PI and Godot applies
`ALBEDO` to the diffuse accumulator after `light()`. The custom light function
therefore adds `0.96 / PI` times irradiance to `DIFFUSE_LIGHT` and the source
specular coefficient divided by PI to `SPECULAR_LIGHT`. It replaces the stock
direct BRDF, rather than applying the source BRDF on top of it.

The board's authored `_Color` is passed unchanged through `VisualAssets.source_color`
to a `source_color` uniform. The existing card texture, overlay, UV, flash and
emission fragment remains unchanged. No global gamma, tint, camera, scene
lighting, ambient strength or display correction is added here.

## New candidate validation

Reconstruction validation completed for this document:

- 11 CPU equation tests pass, including 2,295 angle/intensity/attenuation cases
  comparing the Godot accumulator mapping with the source formula.
- Exact-opposite and near-opposite half-vector cases are finite in the CPU tests.
  These are **not GPU-tested** by this evidence.
- Both isolated Godot probe projects pass headless editor parsing in installed
  Godot `4.6.3.stable.official.7d41c59c4`.
- Both refuse headless rendering with exit code 2 and `NOT RUN`, so a logic-only
  execution cannot produce a false GPU success.
- **New native GPU readback has not run:** this environment has no `DISPLAY` or
  X11 socket, DRM device, running Xorg/Wayland session, or installed Xvfb/Weston path.
  Xorg and GL libraries exist, but the installed Godot headless mode uses the
  dummy renderer rather than a standalone EGL readback path. No display server
  was started, installed or configured for this check.
- The previous snapshot reportedly passed eight native source/factory readbacks,
  with maximum linear error about `0.00136811`. Its artifacts are unavailable;
  that historical result is not a pass for this reconstruction.

Run CPU tests:

```sh
python3 -m unittest discover -s tests -p test_source_lit_equations.py -v
```

With a working native display, run these source-independent synthetic probes:

```sh
godot --path tests/rendering/source_lit_probe -- --output=/absolute/path/source-result.json
python3 tests/rendering/source_lit_factory_probe/prepare.py
godot --path tests/rendering/source_lit_factory_probe -- --output=/absolute/path/factory-result.json
```

Both use a QuadMesh, no ambient/reflected light, one unshadowed directional light,
an orthographic camera, an unchanged authored color `(0.4, 0.2, 0.6)`, and four
`(light, view)` angle pairs: `(0,0)`, `(35,0)`, `(60,30)`, `(75,-30)` degrees.
Each sample averages a center 4×4 pixel block in a 128×128 framebuffer and compares
linear readback to the CPU formula with a `0.006` maximum-channel tolerance.
The first probe records four source-formula cases plus four stock-material
**diagnostics**, which are not asserted to equal the source. The factory probe
asserts eight source-formula/actual-production-factory cases. Its prepare step
copies only owned runtime scripts into an ignored directory and records hashes;
it does not import private assets or substitute a mock material factory.

No complete new-candidate regression suite, private-resource suite, PCK/export,
standalone build or native framebuffer result is claimed by these focused checks.
The coordinating validation report must record those separately.

## Explicit limits

This bounded direct-light change does not establish ambient/GI/SH, reflections,
SSAO, source shadow filtering, tone mapping, FP16/mobile, transparency, physical
light units, other renderers, unknown ShaderGraph schemas, per-pixel normal
changes, full card flash/overlay framebuffer equivalence, or complete-scene
Unity/Godot parity. It is not an assertion that the user's Unity screenshot
matches any particular runtime scene/state. No different source repository or
version is assumed from screenshot differences, and no source baseline is changed.
