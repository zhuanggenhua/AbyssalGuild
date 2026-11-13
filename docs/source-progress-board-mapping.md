# Source Board / ProgressUI mapping

Integrated source bindings use the ignored private visual manifest and cached
Square.png. Unity was not launched. No original asset or exported metadata is
included in public fixtures. Public regression data is synthetic.

## Effective Board transforms

tools/import_visual_assets.py with progress_visual_metadata.py reads each scene's actual PrefabInstance, matches the Board GUID, applies
property overrides to the corresponding prefab documents and retains the full
Transform ancestor chain. It refuses external scene parents rather than treating
an unresolved parent as identity. Both actual source instances are scene roots.

- Main Board01 GUID520b1b5bfc70f3046b560ac3246705d7: scene y=-.05.
- Island Board02 GUID2d5c9720d0a21304a8cb9b8bf644f267: scene y=-.05.
- Both effective rotations identity and scale1. Prefab defaults alone have y0.
- Board.cs does not move these transforms; blendshape changes geometry/bounds.
- Earlier read-only FBX audit found one Model with no Lcl/Geometric overrides,
  base and blendshape vertex Y0. Cached Godot root/mesh transforms were identity.

craft_progress_view.effective_transform maps each source local TRS via reflection
S=diag(1,1,-1), composing full chains. Quaternion mapping=(-qx,-qy,qz,qw).
For raw cached Board mesh coordinates, apply source-to-native geometry reflection
exactly once as well. Existing native Board code reflects mesh Z via scale.z=-1;
the integrated transform composes effective_transform * S, not two mesh
reflections. With identity source rotation this retains the current -.05 result.
Do not set Y0 because the prefab default is0.

## Exact source input mapping

ProgressUI.prefab root rect .8x.05, centered pivot, scale1.
Background color (.25,.25,.25,.8), no sprite. Child fill shares the root plane and
full-stretch rect; color (1,.7974138,0,1), Square.png sprite, Image type3 Filled,
Horizontal method0, left origin0. No +.002 child Y offset exists.

ProgressUI.UpdateUI assigns TargetStack.TargetPosition+displayOffset, where source
serialized displayOffset=(0,0,.55). Neither root nor fill has a surface lift.
CraftingManager instantiates at that world position, parents to WorldCanvas while
preserving world transform, then sets localRotation identity. Both scenes' actual
WorldCanvas hierarchy has rotation+90X, scale1; the resulting plane maps through Z
reflection. The integrated view takes an already-offset source anchor and replaces the
legacy default with the extracted offset, avoiding adding .55 twice.

The importer also resolves effective UIRoot instance overrides for both scenes before
reading WorldCanvas ancestry. Current same-unit scales make basis mapping exact;
if future canvas ancestors have nonunit scale, parent worldPositionStays scale
compensation needs explicit handling, not blindly inheriting scale.

## Coplanar drawing without a fictitious spatial offset

Two transparent meshes on exactly one plane risk unspecified sorting. Instead the
adapter uses ONE QuadMesh and ONE spatial shader. It composes background first,
then source textured fill, within the fragment. It retains depth testing against
world geometry, disables depth writes and uses no_depth_test=false (default).
There is no Y lift, polygon offset, camera-facing displacement or alpha fade.

The source alpha-over equation is represented explicitly:
 A = Af + Ab(1-Af)
 premultipliedRGB = Cf Af + Cb Ab(1-Af)
 output straightRGB = premultipliedRGB/A.

UV.x beyond fill ratio makes fill alpha0 while background remains. UV is not
rescaled into the shrinking filled region. Zero fill hides all foreground, even at
UV.x0. Texture uses linear clamp/no mipmaps as source Square import settings.
One composite fragment guarantees background/fill order inside EACH bar, removing
that z-fighting problem without changing geometry.

## Deliberate acceptance limits

This is not a claim of Unity/Godot framebuffer 1:1. CPU tests verify equations and
resource configuration, not an actual GPU-rendered image. Shader color-space,
blend precision, multisample edge coverage of a shader clip versus Unity's reduced
filled quad, and transparent ordering against OTHER UI/world objects require
rendered comparison. Multiple overlapping bars still need source Canvas hierarchy
ordering mapped explicitly; automatic Godot distance sorting is not proven equal.
No invented render-priority policy is silently supplied here. Source Image's default
UI shader/stencil/Canvas batching are not reproduced wholesale by this shader.

Consequently this integrated implementation is a testable mapping/coplanar-composition
adapter, not a claim that its entire renderer is exact. Known source constants
and no-lift coordinates are verified independently of the rendering limits above.

## Isolated preparation tests (historical)

python3 -B /tmp/abyssal-progress-next/extract.py
  Progress/Board source extraction: PASS (both effective scenes)
godot --headless --path /tmp/abyssal-progress-next --script res://test_progress.gd
  Source progress isolated: PASS (16 checks)

Coverage: both Board overrides, Canvas axes, private sprite dimensions, no extra Y,
source dimensions, single coplanar draw, opaque/transparent/half-alpha compositing,
left/right fill boundary, zero/full fill, paused unchanged state, hierarchy hide,
cancel-hide-before-free and lifecycle cleanup.

## Integrated verification

- test_progress_visual_metadata.py: 3 synthetic tests.
- test_source_progress.gd: 13 composition/coordinate/lifecycle checks.
- test_source_progress_imported.gd: 15 checks requiring both real scene manifests,
  cached Board FBX and original Square texture.
- test_card_interaction_feedback.gd: 130 checks.
- test_source_world_board.gd: scene lifecycle PASS.

The legacy descriptor already adds (0,0,.55). Binding replaces this with imported
offset rather than adding it a second time. Ratios remain model-owned with no
new local clock. Public asset-free fallback uses one white texel explicitly, not
a claim of recovered source artwork.
