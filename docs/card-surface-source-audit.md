# Card surface / highlight source audit

This audit concerns the locked template, not screenshot-derived styling. It is
not a claim of renderer or font pixel parity.

## Existing card composition retained

`Shaders/Card.shadergraph` connects UV minus OverlayOffset divided by
OverlayScale to the artwork sample and a unit rectangle mask. The sample is
multiplied by OverlayTint and mask; its resulting alpha controls the base/art
lerp. FlashAmount blends that result to white, then multiplies by
`1 + 0.5 * FlashAmount`. Metallic and smoothness are zero, target opaque,
both faces, with cast/receive shadows enabled. The native card surface already
represents this graph; the audit found no evidence to recolor or reposition
artwork based on the supplied screenshot.

`CardInstance.Initialize` and its definition refresh replace OverlayTex only
when ArtTexture exists. The material adapter already preserves this fallback.
Native UV adaptation flips the imported PNG convention at its boundary.
Original TMP font equivalence remains unverified; no font substitution was
introduced by this batch.

## Actual missing mapping repaired

`CardManager.HighlightStackableStacks` highlights eligible **bottom cards**,
not the lifted/selected card. `CardInstance.SetHighlighted` constructs
`VFX/Highlight` with the same mesh and `CardSettings.OutlineMaterial`, no cast
shadows. `Default_Card_Settings` references a negative-fileID ShaderGraph
default material, rather than a standalone Material YAML. The previous importer
lost this reference, while native presentation used gold collider boxes and
selected-card emission.

The importer now follows scene CardManager → CardSettings → outlineMaterial,
reads the referenced graph defaults into ignored private metadata, and records
the graph input hash. The new adapter shares the actual imported card mesh and
its transform. It converts mesh coordinates to the reflected source card space
before expanding X/Z by `1 + OutlineSize`; the object-space view-direction Y
bias is subtracted before converting back. The graph uses an unlit transparent
front-face target, forced depth write, and a cyan/default-material color with
an angular alpha sweep: atan2(UV−0.5), plus unscaled time × RotationSpeed,
divided by the graph's full-turn constant, fraction, then lerp(1, MinAlpha).
Color and scalar properties are runtime private inputs, not screenshot guesses.

`GraphicsManager` supplies unscaled time; the adapter uses a real-time clock
and processes while paused. Source selected-card emission was removed. The
public missing-media fallback remains explicitly approximate; only a resolved
source mesh + outline metadata takes the source path. The existing eligibility
and drag-target call sites remain unchanged.

## Validation boundary

Synthetic metadata tests verify reference resolution and graph defaults;
Godot tests verify same-mesh binding, coordinate inverse, parameters, no shadow,
unscaled clock and numeric angular-alpha cases. They do not prove GPU shader
compilation, final occlusion/culling, or screenshot equivalence. Native draw
inspection is required before claiming visual acceptance. The original
Highlight constructor's initial activation quirk is not introduced into the
native lazy path: first creation occurs only on a positive target request.
