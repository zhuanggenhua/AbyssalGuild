# Remaining verified migration gaps

This is a source-audit checklist, not a claim that the game is complete. Reference:
StackCraft `a11a89b04cea8370476f2559b639bb9b4cbc08d8`. No Unity execution was used.
The full private source and assets now pass the 1327-file source lock.

## Functional work still required

1. **Save lifecycle UI is now connected.** Slot selection, safe explicit legacy
   copying, new-day/travel checkpoints, quit failure handling and confirmed
   game-over archive have integration coverage. Archive rather than permanent
   removal is an intentional native safety improvement. Normal title archive-selected,
   archive-all and restore-copy controls are still being finished; platform/manual
   acceptance and further fault-injection testing remain.
2. **Phase action locks are connected.** Playing/selling permit card mutation;
   feeding/encounter/ready/game-over block new presses; a drag granted before the
   boundary may finish, matching source pointer-down behavior. Still requires manual input acceptance.
3. **Trade drop zones are connected.** Source-positioned buyer/vendor colliders,
   nearest-zone validation order, tail-only sales, installment payments and
   nonterminal fallthrough have 43 focused UI checks. Manual drag acceptance is
   still outstanding.
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
  some drag/craft/death interpolation and source event/sound timing remain
  incomplete. Realtime feeding/encounter stages and native Puff rendering are now
  connected; source built-in shader, Unity random distribution and GPU output
  are not identical or visually verified. Source-parameter camera smoothing, zoom and cycle navigation locks
  are connected, with hierarchy/pointer acceptance limitations documented. Combat jump/projectile/hurt/shake adapters are now
  connected but use documented interpolation/noise approximations.
- Original Card/Pack FBX and independently rewritten UV/material composition are
  now bound when complete private inputs exist. This has structural/resource
  coverage, not pixel/GPU acceptance. Source-referenced price/health/nutrition labels
  and compact equipment occupancy panels are now bound, including chest coin
  overrides. Expanded equipment cards now use imported slot poses, source click/day
  rules and independent presentation motion; exact Unity Perlin phases, original
  fonts and rendered interaction remain unverified.
- Nearby attachment currently uses deterministic target-pose collider geometry,
  not Unity Physics overlap ordering or animated transforms. Source target-layout
  math is covered, but cross-engine physics equivalence is not established.
- Godot headless source-data, synthetic, missing-data and real imported-FBX checks
  pass separately. None substitute for rendered legibility, mouse/touch play,
  listening, Windows execution or export/install acceptance. No working display
  server was available for screenshot/manual verification in this environment.

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
camera shake are now connected through a read-only presentation adapter. Native
fonts, easing/noise and current-target approximations remain.

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
