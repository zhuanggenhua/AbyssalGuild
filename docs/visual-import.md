# Private visual import (intermediate adapter)

Run from the repository root after importing the catalog:

    python tools/import_visual_assets.py --source /path/to/Assets/StackCraft --acknowledge-license

Only use a copy you are licensed to use. The command copies supported PNG, WAV
and FBX files without changing bytes into ignored `assets/imported/`. It does
not grant redistribution permission. Never force-add that directory or the
source/catalog to a public commit. No original image, audio, model or generated
manifest is included in the repository. Godot imports FBX with its available
importer; the current board uses imported board models, card art and audio.

`manifest.json` records source paths, GUIDs, SHA-256, material colors/textures,
scene category-to-prefab references, colliders, board renderers, resolved camera
transform chains, scalar instance overrides and directional-light records. Missing files are explicit, not replaced. Repeated imports of the
same input produce identical manifests. Run source-lock verification separately
before import: this adapter records hashes, not a claim of license or lock validity.

The complete restored snapshot yields 150 PNG, 19 WAV and 4 FBX files (173
private assets). Source-lock verification covers all 1327 original files. Both
missing-file reports are empty, including the recovered PDF, KingsFeast music
and Artwork atlas. Repeated strict imports produce byte-identical outputs.
These counts are observations, not hard-coded assumptions.

Card definitions reference art via `artTexture`. Original `CardInstance.cs`
assigns that texture to `_OverlayTex`. The adapter resolves the same GUID to a
PNG, displayed on a transparent plane. Scene `cardPrefabs`, `packPrefab` and
`aggressiveMobPrefab` choose the actual prefab. The renderer on the collider's
object supplies the material's `_Color`; collider X/Z supply card dimensions.
The original zero-thickness collider gets a 0.02-unit Godot interaction thickness.
That generated art-plane fallback remains an adapter. Complete private bindings
now use actual Card/Pack FBX and an independently written UV compositor; see
`card-mesh-binding.md`. Source title pose/color is retained, while typography
and full pixel parity remain unverified.

Board01/Board02 use SkinnedMeshRenderer with Body_01/Body_02 and Header materials.
The adapter uses the actual privately imported FBX, material slots and Scale
blend shape when its Godot cache is available. A generated fallback uses the
verified geometry bounds otherwise. Source camera/light mappings are described
below. Card shader-graph behavior is independently rewritten for the audited base/art
composition without copying the graph itself. Other shaders, fonts and effects
remain incomplete, and lighting is not visually calibrated.

Validation:

    python -m unittest discover -s tests -p test_import_visual_assets.py
    bash tools/test_godot.sh res://tests/godot/test_visual_assets.gd

Tests use synthetic data/art, exercise deterministic copying, hashes, missing
reports, traversal rejection, art binding, material color and dimensions.
Headless tests do not establish pixel parity. A temporary dummy-Xorg attempt
failed because local/unix listening sockets could not be established; no visual
comparison or screenshot was possible in that environment.

Headless FBX vertex inspection succeeded. `mesh.get_aabb()` includes the morph
range and must NOT be treated as the base bound. Actual base vertex union is
X[-6,6], Z[-4,4] (12 by 8). The normalized Scale target is X[-12,12], Z[-8,8]
(24 by 16). Body base Z[-4,2.5], header Z[2.5,4]; target body Z[-8,6.5],
header Z[6.5,8]. Both board prefabs have identity rotation/scale and zero morph
weight; Main/Island override position to (0,-0.05,0). `board_local_rect` derives
bounds from actual imported vertices at a supplied normalized morph weight,
not the mesh AABB. It returns an empty rect if unavailable. This does not
establish rendered pixel parity. A licensed local export must include the
manifest JSON in its non-resource filters and the imported PNG/FBX resources.
Do not publish such an export until redistribution rights are established.

## Original board mesh adapter

`create_board_mesh(scene_name, normalized_boost)` returns the privately imported
FBX Node3D, or null when unavailable. Body/Header material slots get the colors
from that scene's actual board prefab. `update_board_mesh_boost(node, value)`
updates the source Scale blend shape, clamped to [0,1]. The caller places the
returned model at the scene's board position; this snapshot uses (0,-0.05,0).
The API does not add collisions or change world rules. The actual model is used,
but its Unity shaders are approximated by StandardMaterial3D color mapping.

The synthetic test exercises the normalized morph and clamping. After importing
private assets with Godot, run `tests/godot/test_source_board_mesh.gd` in the
actual project to test Main/Island meshes, Body/Header slots, weights and bounds.
The isolated test runner lacks the editor's resource cache and reports a skip
for this optional source test.

## Source camera, lighting and coordinate convention

The model retains original Unity X/Z values. The view maps model (x,z) to Godot
Vector3(x,y,-z); pointer rays must invert Z on their way back to the model.
The imported board geometry currently retains source-sign coordinates, so the
board view reflects its root Z scale. Card local caption/art layout remains
upright. Never mix reflected camera coordinates with unreflected card positions.

`camera_configuration(scene)` and `apply_source_camera(camera, scene)` resolve
parent/child transforms from serialized quaternion values after prefab instance
scalar overrides. Euler hints are deliberately ignored: Main's root hint says
zero even though its actual quaternion is an 85-degree X rotation. External
unresolved parents and missing required data return no configuration/false;
there is no invented camera fallback in this API.

Main and Island have the same source perspective camera: Unity (0,10,-1),
rotation X +85 degrees, child identity, vertical FOV30, near2, far40. The view
conversion yields Godot (0,10,1), rotation X -85 degrees. CameraController does
not overwrite the starting pose in Awake/Start. Its original pan/zoom behavior
and camera-shake animations are separate work, not implemented by these APIs.

`directional_light_configuration` / `apply_source_light` expose the original
scene light, including reflected pose, color, intensity, enabled shadows and
shadow strength. Main/Island use intensity1, RGB(1,.95686275,.8392157), shadow
strength .7. The source quaternion is (.1464466,.8535535,-.35355338,.35355338).
Cross-engine shadow filtering, exposure and perceived lighting are not verified.
Tests check source metadata, effective pose/projection/clips and light fields,
not screenshots or pixel parity.

The board now applies both source camera and directional light on scene entry.
Card stack positions, detached combat cards and ray-plane coordinates use the
same Z reflection; imported board root uses scale.z=-1. Wheel zoom moves along
the source camera forward axis, rejects distances outside [5,20], and clamps
planar position to board bounds plus .5 padding. Middle drag and keyboard pan
remain immediate UI controls; Unity SmoothDamp, pointer blocking details and
shake/tween timing are not reproduced. The original HUD layout is not recreated.
UI tests exercise source perspective settings, model/ray roundtrip, physics
picking and zoom followed by drop. These are headless tests, not visual approval.
