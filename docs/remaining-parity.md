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
3. **Trade drop zones.** Source drop order is trade, equipment, combat, then regular
   stacking. Native buyer/vendor logic and source positions exist, including
   Main Coin versus Island Coral payouts, but trade remains button-driven.
   Connect zone colliders, whole-stack validation and vendor installments.
4. **Discovery presentation remains.** Global card discovery, recipe collection
   totals and hover-only SeenItems semantics now persist atomically across scenes
   and slots. Vendor collection trackers and individually hoverable menu rows are
   not yet connected to the existing aggregate ledger.
5. **Combat overlap merging is connected.** Pre-start and resize hooks preserve
   source registration order and RNG draws; live board paths are tested. Original
   animation, visual clarity and physics-query ordering still need acceptance.
6. **Menus/options.** No full Escape options menu, persisted user audio/display
   choices, completed-quest history view or original unread-item presentation.

## Presentation and platform acceptance

- Original source UI composition, rounded card meshes/shaders, original fonts,
  equipment/price overlays, drag/craft/feed/death/projectile animations, camera
  smoothing/shake and source sound timing remain incomplete.
- Nearby attachment currently uses deterministic target-pose collider geometry,
  not Unity Physics overlap ordering or animated transforms. Source target-layout
  math is covered, but cross-engine physics equivalence is not established.
- Godot headless source-data, synthetic, missing-data and real imported-FBX checks
  pass separately. None substitute for rendered legibility, mouse/touch play,
  listening, Windows execution or export/install acceptance. No working display
  server was available for screenshot/manual verification in this environment.

All 14 source quest types and ordinary/Exploration/Growth/Research/Travel recipe
execution paths have implementations; do not infer they are missing wholesale.
A narrower scene-resolution issue still needs review: SpecialRecipes' CardManager
lookup takes the first scene rather than the active one; identical current prefab
references can conceal the difference.

Source assets and generated content remain private and ignored. Public CI tests
only public code/synthetic behavior and explicitly skips licensed-content checks.
