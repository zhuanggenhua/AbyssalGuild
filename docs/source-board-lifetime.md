# Retired source-tabletop material lifetime

This is separate from the Front/Cull.Back correction. The unchanged `775c324e`
baseline reproduces the same stale-material errors. It is not a reason to revert
source face semantics or previously accepted viewport/flat-lighting work.

## Reproduction and engine boundary

On official Godot 4.6.3, restore original per-surface ShaderMaterials on an
instance of a shared Mesh, queue the old instance for deletion and construct its
replacement in the same frame. The private real-FBX reduction reports two missing
material-RID errors per repeated retirement. A source-free two-surface shared
ArrayMesh reproduces this too. Separate nonshared Mesh resources do not reproduce
that control. Holding original materials prevents the error; holding only flat
replacement materials does not. These are causal controls, not proposed fixes.

The observed error occurs after the old nodes' tree_exiting/tree_exited signals
and before the next process-frame wait returns. Instrumented creation, material
assignment and blend-shape setter calls return before the error. In the official
[MeshInstance3D](https://github.com/godotengine/godot/blob/4.6.3-stable/scene/3d/mesh_instance_3d.cpp)
and [VisualInstance3D](https://github.com/godotengine/godot/blob/4.6.3-stable/scene/3d/visual_instance_3d.cpp)
cleanup sequence, derived material references are released before the base frees
the renderer instance. [RendererSceneCull::free](https://github.com/godotengine/godot/blob/4.6.3-stable/servers/rendering/renderer_scene_cull.cpp)
updates dirty instances before clearing that instance's base. This sequence and
the shared-mesh/strong-reference controls explain the stale RID access. We have
not modified or rebuilt Godot and do not claim an upstream engine fix.

## Narrow ownership fix

`source_board_lifetime.gd` clears only MeshInstance3D **instance** mesh references
inside an already retired, exclusively owned source-tabletop subtree. This clears
its renderer base and surface-RID list before materials are released. It does not
mutate, duplicate or free the shared Mesh resource, change material/light/shadow
values, preserve material references, or wait an arbitrary number of frames.

The Board calls it only on source-tabletop rebuild, return to Title and final
Board pre-deletion. The first two paths already hide and queue that geometry for
deletion. No live tabletop, card, background or unrelated scene subtree is
modified. Tests retain a live sibling sharing the same Mesh and verify its arrays,
blend-shape structure and materials remain unchanged.

## Regression and acceptance boundaries

`test_source_board_lifetime.gd` is source-free. Its `--legacy` mode deliberately
omits detach and reproduces engine errors even when all script assertions pass.
The strict test runner must reject those logs. Normal mode checks that the old
subtree and materials really die; permanent strong-reference retention would
fail the test.

`test_source_board_lifetime_imported.gd` checks the real production Board with
fixed environment/light: Main/Island/Main, rebuild, boost 0/1/0 using diagnostic
creation of actual source booster cards, extra-light and transparency fallback,
Title cleanup and direct active-Board destruction. It is explicitly headless:
logical frame waits and explicit binder refresh replace native rendering signals.
It cannot establish GPU/pixel equivalence. An uncached workspace explicitly skips;
the strict fresh-import runner rejects skips and requires the completion marker.

The separate native `tests/rendering/board_face_probe/lifecycle.gd` entry requires
real Compatibility `frame_post_draw` and rejects headless with NOT RUN / 2. Its
error-log acceptance and the 28-case pixel comparison must be recorded separately.
The initial paired native FAIL remains preserved, including the immediate binder
admission failures; do not erase or retrospectively reclassify that result.
