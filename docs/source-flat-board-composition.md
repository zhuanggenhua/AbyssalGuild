# Flat board lighting composition: bounded Compatibility bridge

This fixes the composition of **the existing migrated flat ambient model** for admitted opaque board surfaces. It is not a claim that Unity's actual baked GI / spherical harmonics (SH) have been recovered.

## Evidence and scope

The locked template uses an opaque metallic-zero, smoothness-zero board graph. Its admitted direct-light bridge is unchanged. Actual Main and Island imports both bind one source directional light, flat ambient, no fog, and zero board emission. Main and Island board colors differ; those inputs are preserved. The original Main LightingData / runtime SH remains unavailable, so the scene's sky color is not promoted to a verified SH measurement.

Official Godot 4.6.3 Compatibility has separate base and shadowed-light encoding: its GLES3 scene shader adds encoded ambient/base color to separately encoded shadowed direct color. A source-independent native plane with the production material factory measured RGB8 `(111,120,122)` without shadows but `(157,170,176)` with shadows, despite no occlusion. With ambient disabled both cases measured `(93,97,88)`. Enabling a shadow flag alone must not brighten an unoccluded point.

The isolated single-pass candidate subsequently passed 32 native cases, including real occlusion and backlighting. The production binder has a separate reproducible probe; do not substitute the candidate's result for a production execution.

## The narrow bridge

Let `A` be the current Godot flat-ambient contribution and `D` the existing source-bounded direct BRDF, including engine-provided shadow attenuation. The goal is `encode(A + D)`, not `encode(A) + encode(D)`.

The material disables only the engine's ambient contribution and places `A + D` in the custom light function's final-color accumulator. ALBEDO has already been decoded by the engine. It is applied once; only D is multiplied by ATTENUATION. No texture, authored color, Environment, light parameter, shadow flag/strength, exposure, or renderer is changed. SPECULAR_LIGHT is used as a final-color accumulator here, not as an extra physical specular lobe.

With exactly one non-shadowed light, the sum is encoded once in the base pass. With exactly one shadowed light, the base color is zero and the sum is encoded once in that light's pass. A complete shadow removes direct light but retains ambient. This does not solve arbitrary multi-light composition or transparent framebuffer blending.

## Admission and lifecycle

- Board binds only after the actual source FBX enters the scene, and only for successfully mapped Main/Island light and flat environment.
- Only exact, previously admitted opaque board shaders are considered. Card fragment/overlay/flash/emission, backgrounds, outlines, progress, transparent materials and generated StandardMaterial fallback are unchanged.
- The known official 4.6.3 engine hash and Compatibility renderer are required. Other versions, vertex shading overrides and physical-light units fall back.
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
