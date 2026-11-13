# Screenshot state audit: avoid unsupported visual fixes

Reference source: StackCraft `a11a89b04cea8370476f2559b639bb9b4cbc08d8`.
Native screenshot: Godot 4.6.3, 2026-11-13 UTC, gameplay viewport 1233×771.
The captured implementation tree was `bb8fb509408074bec8bdb8ef89aa24d68579aa55`
(public commit `78ff9db`, local content-equivalent commit `e14cd49`).
Original art and screenshots remain private, not part of this repository.

The native run created a new default 120-second/non-friendly game, opened three
Starter outputs, then moved Rock, Berry Bush, Villager and the remaining pack by
real pointer drags. A real wheel zoom also changed the camera. The final capture
shows Day 1 and 3/24 cards, unpaused, with the Villager information panel. F8
stopped the test. No code injection or image editing constructed this frame.
The final in-memory game was not saved; the image, version/input hashes and
interaction record are retained as evidence, not an exact replay save.

The user confirms that both use the same Unity repository. The basic template
is the requested migration target; `a11a89` is our selected traceable snapshot,
not a hash the user explicitly chose. A text-language difference does not prove
a different code version or template variant. Earlier speculation to that effect
is withdrawn. The actual checkout, active scene, renderer/quality settings,
camera transform and equipment state still need direct comparison. Unknown
settings are not evidence that they differ. Do not switch the migration baseline
or explain the screenshot discrepancy by assuming another source version.

## Grass: present, but outside the initial view

The actual native source-background node has one textured built-in plane:
10×10 mesh, scale (10,1,10), position (0,-10,0), matching Main's Grass instance.
The actual imported Board is present, with bounds X ±6 and Z ±4, at Y=-.05.

Main's source CameraController starts at (0,10,-1), pitch 85°, vertical FOV 30.
It does not fit the board on startup. In the reflected native coordinate system,
a 16:10 viewport's four corner rays hit the board plane at approximately:

- (-4.429,-.05,-2.658), (4.429,-.05,-2.658)
- (-4.226,-.05,2.772), (4.226,-.05,2.772)

All lie inside the board. The background cannot appear around this view simply
because its texture exists. A wider camera can expose it without changing any
board/background geometry. Adding a grass texture to the board, shrinking the
board, or inventing initial auto-zoom would not repair a demonstrated omission.
`test_starter_framing.gd` now asserts the corner intersections and the transition
to exposed background after real Viewport wheel events at two viewport sizes.
Its checks are synthetic projection/input evidence, not pixel acceptance.

## Top Sell/vendor strip: camera state, not an absent hide branch

`TradeManager.Awake` creates the buyer and vendor objects. The source positions
them at the board header: max Z minus half the top margin, Z=3.25 here. They are
not hidden merely because this is Day 1. The native placement follows that rule.

At the source initial camera and a 1233×771 viewport, the zone collider's lower edge is
about screen Y=-6.5. Moving backward one unit along camera forward puts it around
Y=28.2, with the Sell title around Y=7.3. This accounts for the strip in the new
capture after its real wheel input. Hiding these objects to match a differently
framed image would add a rule not found in the source.

## Card proportions and empty equipment panel

The imported Character and Resource faces have effective dimensions about
0.8×1.0 and unit root scale. Their native binding applies source transforms and
the coordinate bridge, without a screenshot-based scale factor. The two images
have similar card width/height ratios but different screen sizes and framing.
Do not resize card meshes before matching the camera and world positions.

`EquipmentPanel.Awake` initializes its slots and calls `UpdatePanelVisibility`.
The latter enables its renderer/collider only when the animated equipment list
is nonempty. Starter's Villager has no initial equipment. The native empty-panel
hide follows this source condition. A visible panel in another screenshot is
not evidence to invent always-visible empty slots.

## Color remains a separate audit

The native Board really uses Body_01 on the Body surface and Header_01 on Header;
an actual imported-mesh probe and independent source FBX material-index review
agree. A simple swapped material-slot explanation is ruled out. Numeric material
inputs alone do not establish cross-engine lighting/BRDF equivalence.

The locked project uses Linear color space and URP pipeline assets; SimpleLit
contains both Built-in and Universal targets. Selecting a target only by its
name, sampling a replacement gray from this screenshot, or changing gamma until
it looks close would not be a source-equivalent fix. Lighting/pipeline analysis
must remain separate from these demonstrated geometry and lifecycle facts.
