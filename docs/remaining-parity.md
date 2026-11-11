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
6. **Menus/options are connected.** Escape preserves the prior playing pace;
   title/pause options persist independent app preferences with retry protection.
   Audio uses app-local gains; unsupported resolution enumeration, Half VSync and
   Unity shadow presets are explicitly reported. Model plans have 90 checks and
   UI has 42, but native display/audio behavior still needs manual acceptance.

## Presentation and platform acceptance

- Original source UI composition, complete rendering/lighting parity, original fonts,
  expanded equipment interaction, drag/craft/feed/death/projectile animations, camera
  smoothing/shake and source sound timing remain incomplete.
- Original Card/Pack FBX and independently rewritten UV/material composition are
  now bound when complete private inputs exist. This has structural/resource
  coverage, not pixel/GPU acceptance. Source-referenced price/health/nutrition labels
  and compact equipment occupancy panels are now bound, including chest coin
  overrides. Expanded equipment cards and original fonts remain incomplete.
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

The derived settled-pose accessor now corrects individual feeding distances, AI
selection/detachment/production and equipment placement without changing stored
positions. Thirty checks cover source/synthetic geometry and native save round
trips. Combat batch capture, death/growth and UI individual consumers remain.
Root-based crafting and pack outputs stay root-based; animated pose parity is
separate.

Combat impact feedback has a tested pure descriptor, including both normal-hit
and critical audio rather than replacing one with the other. Live presentation
hookup is pending. A deeper audit confirms current immediate combat resolution
still differs from source attack travel, return and lethal cleanup phases. These
delays affect progress, RNG ordering and health timing, not only visuals; the
in-flight model/save/two-clock integration remains required.

Source assets and generated content remain private and ignored. Public CI tests
only public code/synthetic behavior and explicitly skips licensed-content checks.
