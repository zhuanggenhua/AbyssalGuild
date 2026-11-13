# Method-level migration audit status

Reference: StackCraft at `a11a89b04cea8370476f2559b639bb9b4cbc08d8`.
A lexical declaration pass found 102 C# files and 113 classes, with 824 records:
629 methods/constructors, 188 properties, three interface members and four
pure-data/enum file records. Overloads are separate. This inventory is **not**
824 verified equivalent implementations. Related class/test names alone are not
proof of a method's branches, side effects or lifecycle. The detailed inventory
and original source remain private.

## What this review changed

- Sparse-checkout absence is not source absence. Full locked Git-tree lookup found
  the exact DOTween 1.2.790 DLL, original LiberationSans TTF/TMP data, Unity
  6000.5.4f1 project version, uGUI 2.5.0 lock and global audio settings.
- Board Y=-.05 is a real scene instance override, despite prefab Y=0. ProgressUI
  .8×.05 is likewise real. In contrast, the progress .08/.002 lifts had no source
  basis. Inspect effective component/ancestor transforms before changing a value.
- TextureImporter alphaUsage=2 was a missing importer semantic, not a dark theme.
  Original black-and-white art must generate alpha from grayscale.
- DOTween's locked default ease is OutQuad, despite a stale XML comment. Nested
  jump easing, delayed Join insertion and additive punch require separate mapping.
- InfoPanel gives every submitted request a new RequestID, even if its text is
  unchanged. Text-write suppression belongs in UpdateInfo, not priority ordering.
  A public regression now checks identical renewed requests win equal priority.
- An attempted display-mode setting is not an applied setting. Native embedded
  preview rejected fullscreen. The platform adapter now checks the observed mode
  and reports rejection without rewriting the saved preference.

## Substantive branches that remain open

1. **Audio spatial rendering.** Optional positional requests require verified
   per-source defaults, listener mapping and cross-engine attenuation/doppler.
   A contract or explicit unsupported result is not an implemented acoustic path.
   Existing locked callers use the default non-positional path.
2. **Display/quality application.** Real hardware resolution enumeration and
   resolution switching, Half VSync and URP shadow preset application are not
   completed by cycling/storing an option. Unsupported controls remain explicit.
   Native three-cascade/distance/resolution combinations must not be replaced by
   a convenient unrelated Godot preset and called equivalent.
3. **Touch and lock composition.** Primary-touch/mouse selection, touch release/
   cancellation and overlapping day-cycle/vendor lock lifetimes require concrete
   native event tests. Boolean gates and emulation flags are not proof by themselves.
4. **Saved timestamp and scroll.** Newly written native saves now persist the save
   operation's local wall-clock field; legacy saves cannot recover an absent
   timestamp. .NET culture formatting and sub-second precision remain open.
   Exact-version vertical Elastic drag, inertia, bounds and normalized position
   now have source-derived implementations and tests. The actual continuous vertical
   Scrollbar handle geometry, handle-only hit test and keyboard repeat branch are
   also mapped; arbitrary axes, global focus navigation, touch and exact end-of-
   render coroutine timing remain outside the scoped SavedGames adapter.
5. **Typography and rendering.** Accurate font identity is necessary but does not
   implement all TMP layout/SDF rasterization. The bounded static ASCII single-line
   point-size search now uses original glyph metrics, while native glyph raster,
   baseline and complex text remain distinct. Static label font references and
   the still-unresolved dynamic TMP default are tracked independently. Original lighting/BRDF,
   built-in material shaders, particle blending, Unity random/Perlin behavior and
   competing tween writes still have engine-specific boundaries.
6. **All remaining method bodies.** Model-family tests establish their asserted
   cases, not exhaustive equivalence of every constructor/property/helper in the
   lexical inventory. Continue body-level review with concrete assertions before
   promoting an individual branch to verified.

## Intentional native safety differences

Recoverable archive/restore replaces permanent source save deletion. Reset is
scoped to application preferences, not Unity PlayerPrefs.DeleteAll across unrelated
state. Invalid save handling is atomic and preserves recoverable data. These are
explicit differences, not missing branches to silently make destructive.

Public/synthetic, private source-data, fresh-import cache and bounded native
pointer checks are separate evidence. None alone establishes cross-engine pixels,
listening, Windows installation, touch or whole-game one-to-one completion.


## Component follow-up verification (2026-11-12 UTC)

The frozen component batch passed 145 Python tests and 139 Godot groups (90
source-independent plus 49 catalog-backed). A separate clean public checkout
passed its 90 Godot groups with licensed branches explicitly absent. A fresh
private import passed all 72 required suites without skip substitution, including
406 source-metric title cases, 139 actual cached card/pack mesh bindings and 294
card-overlay checks (22 private labels, two panels). The native scrollbar/title
observations and their remaining framing limits are recorded in `gui-smoke.md`.
These counts do not promote unresolved method branches or framebuffer/audio
behavior to equivalent.
