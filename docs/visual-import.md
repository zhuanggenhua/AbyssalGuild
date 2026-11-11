# Private visual import (intermediate adapter)

Run from the repository root after importing the catalog:

    python tools/import_visual_assets.py --source /path/to/Assets/StackCraft --acknowledge-license

Only use a copy you are licensed to use. The command copies supported PNG, WAV
and FBX files without changing bytes into ignored `assets/imported/`. It does
not grant redistribution permission. Never force-add that directory or the
source/catalog to a public commit. No original image, audio, model or generated
manifest is included in the repository. Godot imports FBX with its available
importer; imported models/audio are staged, not yet used by the game.

`manifest.json` records source paths, GUIDs, SHA-256, material colors/textures,
scene category-to-prefab references, colliders, board renderers and camera
settings. Missing files are explicit, not replaced. Repeated imports of the
same input produce identical manifests. Run source-lock verification separately
before import: this adapter records hashes, not a claim of license or lock validity.

The local restored snapshot yields 149 PNG, 18 WAV and 4 FBX files. Its three
missing indexed files are Documentation.pdf, Sounds/KingsFeast.wav and
Sprites/Artwork.png. These counts are observations, not hard-coded assumptions.

Card definitions reference art via `artTexture`. Original `CardInstance.cs`
assigns that texture to `_OverlayTex`. The adapter resolves the same GUID to a
PNG, displayed on a transparent plane. Scene `cardPrefabs`, `packPrefab` and
`aggressiveMobPrefab` choose the actual prefab. The renderer on the collider's
object supplies the material's `_Color`; collider X/Z supply card dimensions.
The original zero-thickness collider gets a 0.02-unit Godot interaction thickness.
The art-plane layout and label placement are adapter choices, not source parity.

Board01/Board02 use SkinnedMeshRenderer with Body_01/Body_02 and Header materials.
The board adapter applies only the body color to the existing generated board.
It does not reproduce board mesh blend shapes or infer playable bounds from
serialized m_AABB. Camera properties and prefab instance modifications are
recorded; source half-height can be applied explicitly, but existing HUD framing
is preserved by default. Camera transforms and overrides are not yet replayed.
Unity shader graphs, overlay composition, base textures, rounded mesh geometry,
fonts, lighting, shadows and effects are not reproduced.

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
