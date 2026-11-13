# Remaining verified migration gaps

This is a source-audit checklist, not a claim that the game is complete. Reference:
StackCraft `a11a89b04cea8370476f2559b639bb9b4cbc08d8`. No Unity execution was used.
The private StackCraft subtree passes the 1327-file source lock; supplemental external font inputs have their own same-commit hash lock.

## Source-backed presentation audit (2026-11-12)

The supplied reference image exposed implementation omissions, not merely a need
for visual polish. This batch restores scene-authored Grass/Water planes and flat
ambient fields, Unity height-matched HUD geometry, shared information requests,
source trade meshes/icon/text fields/hover, same-mesh highlights and the Title
artwork/overlay hierarchy. See [world rendering](source-world-rendering.md),
[HUD mapping](source-hud-mapping.md), [trade presentation](source-trade-presentation.md),
[card surface audit](card-surface-source-audit.md) and [Title container](title-source-container.md).

Most importantly, the original card-art PNGs are opaque black-and-white files:
Unity's `alphaUsage=2` generates alpha from grayscale. Copying their stored PNG
alpha was wrong. The adapter now applies that importer semantic to both cached
and raw loads, retaining byte-identical originals. All 115 affected locked-source
textures are grayscale, so this does not guess colored luminance coefficients.

These are not a claim of global one-to-one completion. Source Slider/text-toggle,
Selectable transitions and Options/Pause component trees now have explicit adapters
and synthetic/private tests. See [controls](source-control-adapters.md). Locked
DOTween 1.2.790 OutQuad/jump/punch behavior and actual attack/return Transform captures
are implemented; [tween evidence](source-tween-parity.md) distinguishes these from
unresolved shake/RNG behavior. Source saved-slot templates and callback routing are now connected; source vertical Scrollbar geometry/input and static ASCII card-title autosizing now have bounded adapters. Dynamic TMP defaults/complex text and particle/built-in-shader/lighting differences remain.

Correction: the source TMP font is present in the full locked Git tree, outside
the sparse StackCraft working copy. GUID 8f586378b4e144a9851e7b34d9b748ee resolves to
LiberationSans SDF; the original TTF, SDF metrics/atlas and OFL license have been
retrieved and hash-checked privately. Static 2D/3D components now resolve their actual font references through the private registry; the separate dynamic TMP default reference remains unresolved. Its
250 static characters include no CJK. The supplied Chinese screenshot and locked
English catalog cannot be treated as the same source variant, and no invented
localization is supplied.

See [method audit status](source-method-audit-status.md) for the 824-member
inventory's evidence limits and still-open branches. Source method names or passing
related tests are not exhaustive method equivalence.

Recent source-backed additions: [font bindings](source-fonts.md),
[saved slots](source-saved-slots.md), [progress and effective Board transforms](source-progress-board-mapping.md),
and [optional audio branches](audio-optional-branches.md). The original Board -.05
scene override is retained; the unrelated ProgressUI .08/.002 lifts are removed.
Camera wheel behavior over GUI and unscaled Pause-menu pan/zoom follow the source
InputManager boundary, not the former convenience restriction. Raw hardware scroll
unit equivalence remains unverified.

## Implemented behavior awaiting broader acceptance

1. **Save lifecycle UI is now connected.** Slot selection, safe explicit legacy
   copying, new-day/travel checkpoints, quit failure handling and confirmed
   game-over archive have integration coverage. Archive rather than permanent
   removal is an intentional native safety improvement. Normal title archive-selected,
   archive-all and restore-copy controls are now connected, including stale-file
   checks, recovery and fresh-slot restoration. Platform/manual acceptance and
   further fault-injection testing remain.
2. **Phase action locks are connected.** Playing/selling permit card mutation;
   feeding/encounter/ready/game-over block new presses; a drag granted before the
   boundary may finish, matching source pointer-down behavior. A bounded natural
   campaign exercised day-end locks and feeding; complete boundary/input acceptance remains.
3. **Trade drop zones are connected.** Source-positioned buyer/vendor colliders,
   nearest-zone validation order, tail-only sales, installment payments and
   nonterminal fallthrough have focused UI checks. A native natural campaign
   exercised buyer sales, rejected mixed sales and installment purchases;
   broader scene/currency acceptance remains.
4. **Discovery presentation is connected.** Vendor collection totals and completed
   trackers update without side effects. Individually hovered recipe/quest rows
   mark source raw IDs as read, including completed quest history.
5. **Combat overlap merging is connected.** Pre-start and resize hooks preserve
   source registration order and RNG draws; live board paths are tested. Original
   animation, visual clarity and physics-query ordering still need acceptance.
6. **Menus/options are connected.** Escape preserves the prior playing pace;
   title/pause options persist independent app preferences with retry protection.
   Audio uses app-local gains; unsupported resolution enumeration, Half VSync and
   Unity shadow presets are explicitly reported. Model plans have 90 checks and
   UI has 42, but native display/audio behavior still needs manual acceptance.

## Presentation and platform acceptance

- Original source UI composition, complete rendering/lighting parity, original fonts,
  transient spawn/current-pose details and exact source event/sound timing remain
  distinct from the verified native behavior.  Realtime feeding/encounter stages and native Puff rendering are now
  connected; source built-in shader, Unity random distribution and GPU output
  are not identical or visually verified. Source-parameter camera smoothing, zoom and cycle navigation locks
  are connected, with hierarchy/pointer acceptance limitations documented. Combat jump/projectile/hurt/shake adapters are now
  connected; jump/punch use verified dependency math, while shake/noise remains approximate.
- Original Card/Pack FBX and independently rewritten UV/material composition are
  now bound when complete private inputs exist. This has structural/resource
  coverage, not pixel/GPU acceptance. Source-referenced price/health/nutrition labels
  and compact equipment occupancy panels are now bound, including chest coin
  overrides. Expanded equipment cards now use imported slot poses, source click/day
  rules and independent presentation motion; exact Unity Perlin phases, original
  fonts and broader rendered interaction remain unverified. A bounded natural
  native run did exercise club crafting, equip/class change and unequip dragging.
- Nearby attachment currently uses deterministic target-pose collider geometry,
  not Unity Physics overlap ordering or animated transforms. Source target-layout
  math is covered, but cross-engine physics equivalence is not established.
- Godot headless source-data, synthetic, missing-data and real imported-FBX checks
  pass separately. None substitute for rendered legibility, mouse/touch play,
  listening, Windows execution or export/install acceptance. A later cloud-native display enabled a bounded pointer/keyboard smoke run;
  see [GUI smoke](gui-smoke.md). Broader rendered/platform acceptance remains open.

All 14 source quest types and ordinary/Exploration/Growth/Research/Travel recipe
execution paths have implementations; do not infer they are missing wholesale.
Special recipe templates and growth offsets now resolve the active scene's
CardManager and referenced settings. Twenty synthetic tests use deliberately
unequal scene templates/colliders/margins to expose errors hidden by the shipped
matching references.

The derived settled-pose accessor now covers individual feeding, AI, equipment,
combat batch capture, death/growth and board queries without rewriting stored
positions. Intentional crafting/pack root consumers remain unchanged. Animated
current-pose parity remains separate from these settled positions.

Combat now has explicit travel/return/scaled-death phases, delayed impact RNG,
reverse task update order, actor drag locks and atomic in-flight saves. Source
zero-health merge behavior is retained. Native removal safely cancels invalid
pending references instead of following source dangling-coroutine failures.
The UI advances real combat time while its menu pauses scaled gameplay, emits
attack and additive hit/critical sounds separately, and creates generated damage
popups. Attack/return motion, private Arrow/Magic and HitUI art, hurt flash/punch and
camera shake are now connected through a read-only presentation adapter. Original font binding and shake/noise remain. Attack/return endpoints are now captured from actual three-dimensional presentation poses, not continuously retargeted; legacy native saves without optional visual geometry retain an explicit fallback.

Expanded equipment interaction preserves panel toggles, outside-click equipment
exceptions, day locks and unequip-drag position. Its cosmetic RNG is independent
of gameplay and its Perlin implementation is not Unity-identical. No real pointer,
rendering or listening acceptance is implied by injected/headless checks.

Feeding now snapshots source-ordered characters/food once and advances real-time
focus/lift/travel/chew/settle waits, with nutrition and healing at consumption.
Combat can interleave while scaled gameplay pauses. Selling observes first-payout
transitions and encounters select once before notification and sequential spawns.
Carried drags can finish across a cycle boundary, while new presses are locked.
Complete cycle checkpoints are staged and independently validated, including
active and inactive campaign scenes. Exact cross-engine coroutine resume order
and animated stack reflow remain documented limitations.

SFX now preserve overlapping voices when logical source slots wrap, retain source
cooldown-before-lookup behavior and keep app-local gains without corrupting catalog
settings during reconfiguration. Godot overflow players differ internally from
Unity one-shot voices. Hearing and positional/interrupt-BGM acceptance remain.

`tools/test_imported.sh` creates an isolated copied project, imports every complete
private resource, requires positive completion markers and rejects skipped/error
branches. It complements, rather than replaces, the source-free/public and domain
runners; no GPU, pointer or listening acceptance is implied.

Source assets and generated content remain private and ignored. Public CI tests
only public code/synthetic behavior and explicitly skips licensed-content checks.

Puff metadata, model event sites, CPU simulation and native private-texture
rendering now cover active-scene references, source birth ranges, weighted size
curves, separate real/scaled clocks and board cleanup. Event coverage includes
ordinary recipes, Kill, chests, vendor payment, production and encounter spawning.
The native renderer uses standard alpha blending as an explicit approximation;
source built-in shader and exact Unity random/renderer behavior remain unresolved.


## Reproduced interaction gaps now covered

- Crafting now advances in reverse task activation order, independent of stack
  registration. Explicit activation order persists through active/inactive scene
  saves and held-state normalization. Legacy native v1 files use documented
  deterministic saved-row fallback. See [crafting order](crafting-activation-order.md).
- Live drag-target highlighting, hovered card/equipment information and per-stack
  craft progress are connected to board input and view lifecycle. Menu/modal,
  travel, title, same-ID replacement and focus-loss cleanup have integration
  coverage. See [live feedback](card-feedback-board.md).

These fixes use locked original paths and isolated Godot probes, not Unity
execution. Headless input and resource checks do not establish rendered/manual
acceptance or close the presentation gaps listed above.

Required day-cycle actions now use the source bottom-left InfoPanel priority/action path, independent of
collapsed sidebars. The earlier persistent-header native substitute has been removed. Singleton chest clicks share the existing withdrawal path
with repeated-release and phase protections. Only supported Normal/Fast pace
controls remain. Recipe cards now share one pure scene-aware definition builder
for packs, research, cold saves and traveler restoration; ingredient text and
all template fields survive fresh-catalog continuation. These corrections have
focused synthetic/source-data coverage, not manual input/rendered acceptance.


Held tails now split at pointer-down, pause only the original craft, retain its
progress when returned and resolve source-standard versus terminal drops. Actual
pointer-up remains captured across later UI/menu/phase locks. A native save
settles a cloned held state as an ordinary non-reattached release, without live
RNG/state/signals changing. Source successful-click orphan pauses receive an
explicit safe cleanup; see [held lifecycle](held-stack-lifecycle.md).

Vendor unlocks now queue live notices, highlights, camera focus and independently
owned input/scaled-time pauses. Carried releases, menu/pace/equipment exceptions,
real combat/cycle motion and silent restoration are tested. Explicit title Quit
confirmation and Escape/gamepad-East menu/modal cancellation are also connected,
including real headless Viewport event routing. Physical controller/window
acceptance remains unverified. Source card information/progress/target helpers now have live board wiring and
interruption checks, as described in the completed interaction slice above.


Whole-price convenience purchases now validate each coin's remaining source
stack immediately, stopping invalid recipes without resetting valid excess-input
progress. Staged departure discoveries, collection and read state now reach travel
destinations before first-visit quest activation, and no longer wait until Continue
to become visible. Both changes preserve failed-action atomicity and have actual
source-card reproduction/continuation tests. Save APIs still require frame
boundaries rather than arbitrary reentrant gameplay callbacks.


## AI placement and target-order corrections

Accepted approaches and completed patrols (including exhausted attempts) now
resolve overlaps before another AI movement, even when an unrelated card is
held. Equidistant players use registered-stack/member order rather than card
creation order, including after native save continuation. Existing native held
locks remain deliberate; source physics only uses explicit pack locks.

AI detachment also checks a previously idle surviving stack for a newly valid
recipe. Legal source-card assembly reproduces Cow departure unblocking Fruit
Salad, and verifies authoritative task activation and normal completion. See
[AI placement and ordering](ai-placement-order.md). These are headless runtime
corrections, not a claim of rendered motion or physical-pointer acceptance.


## Drag decisions and lifecycle ordering

Captured drags now move without a screen-pixel dead zone and use final world-space
displacement plus the source click threshold. Returning to the origin, clamped
grab offsets and camera-only movement are covered. Held cards can reach the
source trade header; only final ordinary placement applies its restricted margin. Source-height/current-pose
limitations remain documented in [drag input](card-drag-input.md).

Combat maintains historical participant order independently of faction lists,
including native save continuation, so a later same-faction join cannot skip an
earlier tied opponent. Legacy files lacking this history use their prior
deterministic order; see [combat order](combat-order.md).

Growth seeds resolve before output selection, and returned equipment resolves
immediately rather than waiting for a view refresh. Crowded-board callback order
and all six real growth recipes are covered in [placement lifecycle](placement-lifecycle.md).


## Ordinary motion, title controls and interrupted clicks

Source-parameter ordinary movement, lifted drag heads and exponentially following
tails now have a read-only board adapter. Real-time pause behavior and higher
priority combat/cycle/equipment ownership are covered in [card motion](card-motion.md).
This does not make nearby physics queries Unity-identical or establish rendered
acceptance; crafting/death effects and remaining UI composition remain separate.

Title duration/toggle references now supply their actual source defaults and
whole-second range, with live labels and explicit missing-reference fallbacks.
See [title preferences](title-gameplay-preferences.md).

A surviving killer can flee during scaled death cleanup without skipping its
remaining delay. Later progress reset, cross-combat continuation and safe destroyed
references are covered in [death-wait flee](combat-death-wait-flee.md).

Successful chest clicks return to the original press position after raw offset
coin creation, and picking up an interpolating singleton now aligns its held
root with its visible pose. [Chest lifecycle](chest-click-lifecycle.md) includes
actual headless pointer routing and rejects duplicate or newly phase-locked input.


## Source clock and grouped journal

The persistent day clock now binds the scene's source progress tint and private
pace icons, with Normal/Fast/Paused cycling and explicit text fallback when art
is absent. Actual day-end transitions hide source clock/stats and close the
journal once while retaining the separate required day action. Current scene
headings follow Main/Island. See [day clock](day-clock-ui.md).

Recipe categories and source quest groups now have clickable collapse, source
header tint, discovery filtering and stable completion/activation row order.
Scene changes reset this transient UI state; group metadata cannot mark content
read or activate stale/hidden rows. See [journal groups](journal-groups.md).

Native layout and inline journal detail still differ from the source Canvas and
hover panel. Journal closure is immediate rather than its source slide; the
referenced TMP font is absent from the locked source subtree. Rendered/platform
acceptance and the other cross-engine approximations above remain unresolved.


## Title destinations and source-timed navigation

The title now separates Home, Gameplay Preferences and Saved Games. Opening
preferences does not allocate a slot; Confirm consumes one pending intent,
while Back/Cancel/Escape preserve data and modal/options priority. See
[title navigation](title-navigation.md).

Scene changes now use one-second real-time linear black fades with token-owned
commits. Travel stages a request-time candidate and checkpoints before fade;
Save & Title also saves before fade. Input/scaled-time ownership releases before
fade-in, independently of user/menu/vendor pauses. See
[scene transitions](scene-transitions.md) for native transaction safety policies.

The journal resolves its source initial-open state and uses a half-second
unscaled OutQuad slide, including ignored reentry, admitted click sounds and
source day-end behavior. See [menu slide](menu-slide.md). This supersedes the
previous immediate-close limitation; native panel width/fonts/layout still differ.

A final bounded static audit of equipment/stat rounding, special recipes, world
production/chests/enclosures, trade limits and card-information descriptors found
no additional evidenced functional omission beyond the work above. That is not
a proof of engine, visual, physics, RNG or platform equivalence. Rendered/manual,
listening, Windows and export/install acceptance remain explicitly outstanding.


The bounded enabled-presentation inventory identified source manual-pause
grayscale/day-end vignette and TextButton/toggle/menu Click triggers. Those are
now implemented: [world post-process](world-post-process.md) covers active-scene
binding, event order and real-time tracks; [UI feedback](text-button-feedback.md)
covers callback-before-sound, explicit source control mapping, modal cancellation,
silent row hover and native underline cleanup. This closes the concrete omissions
from that inventory, without claiming exact GPU/canvas/font/physical-input output.


## Native GUI follow-up

A real cloud-native smoke run exposed collapsed journal tabs, truncated inspector
actions and gameplay world state leaking into the title. These now have focused
container/world-lifecycle corrections and explicit regression coverage. See
[GUI smoke and layout](gui-smoke.md) for the tested paths and remaining Starter
edge-framing, audio-device and platform limitations. This is not full visual
parity or final acceptance.


A later natural campaign continued through basic melee combat, an autonomous
Slime encounter, loot payment, full Berry growth and the Day 5 Villager encounter.
It also restored an active fight, exercised reinforcement/flee/rejoin, and grew
a Baby into a third adult in Day 7, unlocking Farmstead.
See [native GUI continuation](gui-smoke.md#natural-combat-and-growth-continuation).
This narrows the basic combat acceptance gap. Later projectile/merge and Linux
export results are recorded below; natural late-game travel, audio listening
and other-platform acceptance remain open.


A separate controlled native UI run now covers five actual portal trips between
Main and Island, Island pack/resource interaction, cold save restoration,
retained scene cards/clocks, Coral installment persistence and Island feeding
through Day 2. It found and corrected unreadable status text over the bright
Island board, with native-window and contrast/input regression checks. See
[Island UI acceptance](gui-smoke.md#island-travel-and-status-legibility-follow-up).
The ordinary campaign reached Day 8 independently. The controlled portal setup
is explicitly not natural late-game progression or Demon Lord combat victory.


## Controlled combat and Linux export follow-up

Native pointer-driven controlled fixtures now verify both Arrow/Magic flight
and impacts, two independent combat rectangles merging through reinforcement,
and normal merged-combat resolution with equipment/survivors/loot preserved.
The natural Day 8 save was not modified. See the
[controlled combat acceptance](gui-smoke.md#controlled-projectile-and-overlap-merge-acceptance)
for exact scope and save-audit results.

A reproducible private Linux x86_64 release export now exists, including a
runtime-only PCK audit and an editor-hosted exported-resource/game-flow probe.
See [Linux export](linux-export.md) for the separate actual-release native
results. This narrows Linux export acceptance only: natural endgame progression,
Windows, physical controller/touch, listening, original fonts and exact
cross-engine output remain unverified. Public redistribution of licensed
content is still not authorized by the available provenance.

## Natural production through Blacksmith

The preserved Day 8 campaign has now been continued normally through Day 11,
with all four adults at full health and 18 nutrition for eight required.
Ordinary food recovery, three Soil plantings, Timber/Plank production, Yard,
Logging Camp, Bonfire, Omelette, Stone Quarry and Steak raised completed quests
from 18 to 26 and unlocked Blacksmith. Three successive day-end feedings,
surplus-card sales, partial-food retention and a cold save restore were observed.
Nine checkpoints passed native restore/capture validation and 63 independent
read-only state checks passed. See the
[natural production acceptance](gui-smoke.md#natural-food-production-and-blacksmith-continuation).

No cards or prerequisites were injected into this campaign, and its original
Day 8 file remains unchanged. This reduces the natural economy/progression gap,
but does not establish Acolyte acquisition, the Altar/Demon Lord/Core chain,
natural portal construction or natural Island arrival. Controlled travel and
combat fixtures remain explicitly separate from natural campaign completion.

A bounded continuation then opened two naturally purchased Blacksmith packs,
defeated both actual Goblin draws, healed through normal feeding and reached
Day 12 with four full-health adults, 15 Coins and 17 nutrition. Three additional
checkpoints passed native restore/capture validation and 36 read-only evidence
checks passed. Neither pack supplied the probabilistic Acolyte prerequisite.
See the [bounded Blacksmith continuation](gui-smoke.md#bounded-natural-blacksmith-combat-continuation)
for the remaining random-grind cost; this does not close natural endgame acceptance.


Source ScrollRect vertical Elastic motion and save-operation LastSaved are now
implemented with focused regression coverage. Remaining boundaries are native
scrollbar skin/minimum handle/page-key behavior, touch, .NET culture formatting
and sub-second timestamp precision. This is not entire ScrollRect/TMP parity.

## Component-lifecycle and text-layout follow-up

[Drag highlight lifetime](drag-highlight-lifecycle.md) now follows source pointer-down, accepted pointer-up, combat-entry and vendor setter events rather than refreshing candidates every frame. Retained target identity and source candidate predicates have live-board tests; destroyed-target exception propagation and secondary-pointer competition remain incomplete.

[Persistent audio slot ownership](audio-slot-lifecycle.md) now retains every admitted voice, including overlapping requests and later null requests. Stop/reconfigure/shutdown cover both node classes. Spatial acoustic policy is deliberately absent in production until listener animation, attenuation and stereo behavior can be mapped, not guessed.

[Source scrollbar](source-scrollbar.md) maps the actual continuous vertical branch, handle-only raycast, driven handle anchors/sizeDelta, unscaled repeat timing and the scene's InputSystem UI wheel multiplier. Other navigation/device branches remain bounded. [Static TMP title layout](source-tmp-single-line.md) measures private source glyph metrics and applies original quantized point-size search; all 406 scene-expanded displayable title cases use that branch, with two unnamed template appearances counted separately. Native glyph raster/SDF baseline/pixel parity remains unproven. [Source label poses](source-label-pose.md) no longer receive invented additional surface lifts.


## Day-boundary and title-baseline follow-up

[Day-clock threshold](day-clock-boundary.md) now preserves the original Update
branch: crossing the duration stays Playing, then the next Update resets elapsed
and triggers day end, even with zero delta or a newly added external pause. The
Pause Continue button has its own source callback and can close an already-open
menu at that boundary without releasing the day/vendor locks; Escape remains
ending-cycle gated. Global Unity MonoBehaviour Update ordering is not established.

[Middle title baseline](source-tmp-baseline.md) now compensates the exact source
SDF FaceInfo baseline versus Godot shaped-line baseline formula for the verified
static ASCII/unit-scale/center-pivot branch. This adjusts text offset, never the
authored physical transform. The actual font's face and all 250 glyph/character
scales are one; nonunit native raster scales are explicitly unsupported. Original
TMP atlas sampling, shader perspective filtering and glyph-edge raster parity
remain separate work.


The remaining existing-Pause Options/Title admission mismatch at day ending is
now addressed in [Pause ending actions](pause-ending-actions.md). Both use their
source button callbacks while new-menu/Escape gates remain in force. Actual
test-owned save/restore/fade, save failure and recoverable game-over archive paths
are tested separately; no silent widening of deletion or save-failure behavior.
