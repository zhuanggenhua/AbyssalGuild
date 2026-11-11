# Remaining verified migration gaps

This is a source-audit checklist, not a claim that the game is complete. Reference:
StackCraft `a11a89b04cea8370476f2559b639bb9b4cbc08d8`. No Unity execution was used.
The full private source and assets now pass the 1327-file source lock.

## Functional work still required

1. **Save lifecycle UI is now connected.** Slot selection, safe explicit legacy
   copying, new-day/travel checkpoints, quit failure handling and confirmed
   game-over archive have integration coverage. Archive rather than permanent
   removal is an intentional native safety improvement. Continue platform/manual
   acceptance and fault-injection testing, not a missing-feature claim.
2. **Phase action locks are connected.** Playing/selling permit card mutation;
   feeding/ready/game-over block it. Still requires manual input acceptance.
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
6. **Menus/options.** The validated native options store and application plans
   have 90 checks; full Escape/options UI and actual application are still pending.
   Unsupported Unity display/shadow modes must be disclosed rather than silently
   substituted.

## Presentation and platform acceptance

- Original source UI composition, complete rendering/lighting parity, original fonts,
  equipment/price overlays, drag/craft/feed/death/projectile animations, camera
  smoothing/shake and source sound timing remain incomplete.
- Original Card/Pack FBX and independently rewritten UV/material composition are
  now bound when complete private inputs exist. This has structural/resource
  coverage, not pixel/GPU acceptance. Equipment panels and full stat overlays
  remain incomplete.
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

A newly audited gap remains: stacked cards store their root position while the
view adds per-card offsets. Individual-distance feeding, AI, combat and selected
spawn consumers need a derived settled-pose accessor; root-based crafting and
pack outputs must remain root-based. Animated current-pose parity is separate.

Source assets and generated content remain private and ignored. Public CI tests
only public code/synthetic behavior and explicitly skips licensed-content checks.
