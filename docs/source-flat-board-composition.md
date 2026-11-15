# Flat board lighting composition: bounded Compatibility bridge

This fixes the composition of **the existing migrated flat ambient model** for admitted opaque board surfaces. It is not a claim that Unity's actual baked GI / spherical harmonics (SH) have been recovered.

## Evidence and scope

The locked template uses an opaque metallic-zero, smoothness-zero board graph. Its admitted direct-light bridge is unchanged. Actual Main and Island imports both bind one source directional light, flat ambient, no fog, and zero board emission. Main and Island board colors differ; those inputs are preserved. The original Main and Island LightingData / runtime SH remain unavailable, so neither scene's sky color is promoted to a verified SH measurement.

The private visual importer preserves each Unity scene's serialized
`LightmapSettings` next to `RenderSettings`. This retains scene-local baked-data
references, flags and explicit nulls for further investigation; it does not
resolve a reference, generate a lightmap, obtain runtime SH or change the Godot
renderer. Main and Island must remain separate even if some authored settings
match. An exact audit of all 10,719 tracked metadata files found neither scene's
referenced LightingData GUID, including in the rest of the Unity repository.
This rules out a matching asset definition in the tracked metadata, not
untracked bake artifacts, external packages or a live Unity binding. The
generated manifest stays private.

Official Godot 4.6.3 Compatibility has separate base and shadowed-light encoding: its GLES3 scene shader adds encoded ambient/base color to separately encoded shadowed direct color. A source-independent native plane with the production material factory measured RGB8 `(111,120,122)` without shadows but `(157,170,176)` with shadows, despite no occlusion. With ambient disabled both cases measured `(93,97,88)`. Enabling a shadow flag alone must not brighten an unoccluded point.

The isolated single-pass candidate subsequently passed 32 native cases, including real occlusion and backlighting. The production binder has a separate reproducible probe; do not substitute the candidate's result for a production execution.

## The narrow bridge

Let `A` be the current Godot flat-ambient contribution and `D` the existing source-bounded direct BRDF, including engine-provided shadow attenuation. The goal is `encode(A + D)`, not `encode(A) + encode(D)`.

The material disables only the engine's ambient contribution and places `A + D` in the custom light function's final-color accumulator. ALBEDO has already been decoded by the engine. It is applied once; only D is multiplied by ATTENUATION. No texture, authored color, Environment, light parameter, shadow flag/strength, exposure, or renderer is changed. SPECULAR_LIGHT is used as a final-color accumulator here, not as an extra physical specular lobe.

With exactly one non-shadowed light, the sum is encoded once in the base pass. With exactly one shadowed light, the base color is zero and the sum is encoded once in that light's pass. A complete shadow removes direct light but retains ambient. This does not solve arbitrary multi-light composition or transparent framebuffer blending.

## Admission and lifecycle

- Board binds only after the actual source FBX enters the scene, and only for successfully mapped Main/Island light and flat environment.
- Only exact, previously admitted opaque board shaders are considered. Card fragment/overlay/flash/emission, backgrounds, outlines, progress, transparent materials and generated StandardMaterial fallback are unchanged.
- The known official 4.7.2 engine hash `ed1daf0bf001b61586d9930840f2f1394092c079` and Compatibility renderer are required. Other versions, vertex shading overrides and physical-light units fall back.
- Before drawing, the binder rechecks actual World3D nodes and live properties. Exactly one effective directional light is required; zero/multiple, invisible, sky-only, non-positive-energy or excluded-layer contexts restore originals.
- Reflection/GI probes, lightmaps, camera environment/exposure, non-flat ambient, fog, nonlinear tone/exposure changes, glow/adjustment, overlay, instance transparency/fade, material changes and mesh ownership/resource changes reject the bridge.
- The original per-surface material object is retained and restored verbatim. External replacement is never overwritten. Main/Island travel and geometry growth rebind; Title clears all references. The binder is created only when the world is built, so headless Board subclasses that omit UI construction do not leak an orphan Node.
- The node-based world ownership contract does not monitor arbitrary bare RenderingServer light/GI RIDs. Production does not create them. Adding such a renderer path requires revisiting admission rather than assuming support.

## Verification commands

```
GODOT_RENDERING_METHOD=gl_compatibility bash tools/test_godot.sh res://tests/godot/test_flat_board_lighting.gd
bash tools/test_all.sh
bash tools/test_imported.sh
python3 tests/rendering/flat_board_probe/prepare.py
# Only on an explicitly coordinated native display, with isolated HOME/XDG:
godot --audio-driver Dummy --path tests/rendering/flat_board_probe -- --output=/private/output/result.json
```

Headless lifecycle and algebra checks make no pixel claim. The native probe refuses headless execution. It copies current first-party scripts, hashes them, uses synthetic geometry only, and produces 32 PNGs plus numerical readback: stock/binder × ambient off/on × shadow off/on × clear/blocked/edge/backlit. Assertions cover unchanged direct light, unchanged unshadowed composition, no-occlusion shadow-toggle invariance, actual occlusion, and constant ambient across attenuation. No licensed source assets are included by the probe.

## Desktop face contract

The actual original board and its linear-composition replacement both use the
explicit SimpleLit schema 3 Front/Cull.Back contract and source_board_cull=back
metadata. Unsupported contexts restore the same Cull.Back original material
reference. This corrects the real reflected-FBX face path independently of the
linear-composition formula. See [source-board-faces.md](source-board-faces.md).
Synthetic QuadMesh results alone do not establish actual FBX front/back behavior.

## 4.7.2 revalidation and single supported target

The historical 4.6.3 evidence above is retained, not relabeled. The project, public CI and private release workflow now target only official 4.7.2. The full official commit matches the verified Linux editor. Its GLES3 base/additive composition still needs this bounded bridge; the engine upgrade alone does not eliminate it.

On the real imported Main/Island FBX, 28 stock cases (binder disabled) produced 14 expected formula failures, maximum linear error 0.548410. The identical 28 cases with the strict 4.7.2 binder passed, maximum error 0.002433 within 0.008. Shadowed ambient residuals were 0.177263/0.490358 stock versus 0.001142/0.001224 candidate. Measured direct-light occlusion reductions remained identical at 0.050002/0.150432. Both retain source shadow strength 0.7 and Cull.Back. The actual GPU lifecycle passed 389 checks with no script/engine error diagnostics (VSync unsupported warning only). These are controlled Godot framebuffer and lifecycle results, not Unity SH or scene-image equivalence. Private images and original licensed input are not published.
