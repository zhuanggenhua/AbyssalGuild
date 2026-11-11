# Remaining verified migration gaps

This is a source-audit checklist, not a claim that the game is complete. Reference:
StackCraft `a11a89b04cea8370476f2559b639bb9b4cbc08d8`. No Unity execution was used.
The full private source and assets now pass the 1327-file source lock.

## Functional work still required

1. **Save lifecycle UI.** Native multi-slot storage is implemented and tested as a
   helper, but the title still uses one Continue path. Connect slot selection,
   safe legacy adoption, confirmed-new-day and travel checkpoints, and close
   handling. Source game-over removal happens when the player confirms Return to
   Title, not at the instant the last character dies. The current UI still saves
   that dead session. Native deletion should use the helper's recoverable archive,
   which is an intentional improvement over the original permanent file removal.
2. **Phase action locks.** The source locks notification/feeding/encounter/ready
   and game-over interactions, reopening card actions while selling excess.
   Current drag/sale commands need one consistent phase policy and tests.
3. **Trade drop zones.** Source drop order is trade, equipment, combat, then regular
   stacking. Native buyer/vendor logic and source positions exist, including
   Main Coin versus Island Coral payouts, but trade remains button-driven.
   Connect zone colliders, whole-stack validation and vendor installments.
4. **Global discovery and unread state.** Recipe discovery exists. Source
   `DiscoveredCards` (including friendly-suppressed factory outputs), menu
   `SeenItems`, and pack collection progress are not yet persisted or displayed.
5. **Combat overlap merging.** Fighter rows, live rectangles, AI center, join/start,
   flee and native layout snapshots are connected. The logical merge API and
   geometry tests exist, but source pre-start overlap merging and merge-on-resize
   are not yet connected through every initiation path.
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
