# Private card and pack mesh bindings

This stage replaces the generated box with the locally imported source card/pack
mesh **only when its entire binding is available**. It is a static, resource-level
migration check, not rendered visual acceptance.

## Private input boundary

The public repository contains independently written adapter/shader/test code.
No FBX, PNG, Unity prefab, material, shader graph, or generated manifest is included.
The existing static visual importer writes those bindings under ignored
`assets/imported/`; run it again after updating this stage. Godot must also have
imported the private FBX files before the original mesh can be used.

The importer now resolves a MeshRenderer's MeshFilter by matching their owner,
rather than accidentally selecting a text child's mesh. A SkinnedMeshRenderer's
own mesh still takes precedence, preserving the existing board path. It retains
an explicit transform chain, the material's shader source reference, and a directly
parented Title's pose, color and rectangle size. Those records stay private.

## Audited behavior

Static references: `Prefabs/Cards/`, `Prefabs/PackInstance.prefab`,
`Models/Card.fbx`, `Models/Pack.fbx`, `Materials/Cards/`, `Materials/Pack.mat`,
`Shaders/Card.shadergraph`, and card initialization in `Scripts/Card/CardInstance.cs`
within the source locked by `docs/source-lock.json`. Unity was not launched.

- The audited card family has one mesh surface, identity source root poses and
  zero-height source geometry. The adapter retains the imported mesh and UVs;
  it does not approximate the outline, stretch it to fit a box, or copy vertices
  into public code.
- The project's Unity-to-Godot convention reflects world Z. The FBX mesh bridge
  turns the directly imported mesh by half a turn around Y. Static UV/vertex
  checks verify that texture U increases left to right and that the PNG top row
  points toward Godot negative Z. Imported node transforms and the source prefab
  pose are composed explicitly.
- The new opaque, double-sided material samples the base texture and the
  definition's artwork (or the material's default artwork when no definition art
  is assigned). The source offset and scale operate in bottom-left UV space;
  sampling converts back to Godot's top-left texture convention.
- The art is multiplied by its tint and a screen-space rectangle mask, then
  blended over the base using its resulting alpha. Flash blends toward white
  and increases brightness. Metallic is zero and roughness is one.
- Stored `_Color`, hue, saturation and brightness material entries are not wired
  into the audited graph and therefore do not tint the new source material.
- The shader is used only for the audited shader source identity. Missing media,
  missing import cache, unresolved pose, unknown shader, invalid overlay scale,
  absent UVs or an unsupported mesh/surface count returns to the existing box/art
  fallback. It does not silently choose a different source model.
- Title anchor/color are applied from private metadata. Label3D font, wrapping and
  typography remain a Godot adapter, not TextMeshPro parity.
- Existing CardView configure/caption/body/material/highlight entry points remain.
  A separate per-card ShaderMaterial prevents selection state leaking between
  cards. The StandardMaterial3D property remains the fallback/highlight state.
- Collision X/Z dimensions remain sourced from the existing prefab footprint.
  The existing minimum Godot pick thickness remains because a zero-height box
  is not used for physics. The visual mesh itself remains flat.

The selection emission is a migration UI affordance, not a recreated source
outline effect. The flash input is bound but this stage adds no flash animation
or gameplay trigger. EquipmentPanel, price/stat labels, original fonts,
engine lighting, color management, mip/sampler behavior and post-processing still
require separate work or rendered comparison.

## Checks

Synthetic Python tests cover owner matching, child-mesh rejection, skinned mesh
precedence, explicit pose and title metadata, and shader identity references.
The source-free Godot test covers nested mesh poses, UV conversion with unequal
offsets, composition arithmetic, texture/tint/scale/flash binding, independent
materials, title positioning, collider dimensions and incomplete-input fallbacks.

```sh
python3 -m unittest discover -s tests -p 'test_card_mesh_import.py' -v
bash tools/test_godot.sh res://tests/godot/test_card_mesh_binding.gd
```

The latter deliberately has no project import cache, so the private branch prints
a clear SKIP. To verify actual cached models, run the same script against the real
project with writable user-data directories:

```sh
TEMP="$(mktemp -d)"
mkdir -p "$TEMP"/{home,cache,config,data}
HOME="$TEMP/home" XDG_CACHE_HOME="$TEMP/cache" \
XDG_CONFIG_HOME="$TEMP/config" XDG_DATA_HOME="$TEMP/data" \
python3 tools/run_godot_test.py godot --headless --path . \
  --script res://tests/godot/test_card_mesh_binding.gd
rm -rf "$TEMP"
```

The private branch checks all scene category bindings, aggressive mobs, packs,
and definition art overrides against the real cached resources. It checks
transforms, UV direction, exact vertex footprint, material/texture parameters,
title pose/color and collision size. It skips explicitly if private inputs or
cache are absent. A successful headless run is **not** GPU shader/pixel, screenshot,
mouse-input or manual visual acceptance. No display was available for those stages.
