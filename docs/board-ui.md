# Runnable Godot board

This is an independently implemented Godot 4.6 UI over source-audited gameplay.
It is a functional migration slice, not visual parity or final manual acceptance.
The public repository includes no original third-party assets or exported content.

## Run

1. Follow `data-import.md` to generate local `data/stackcraft.json` from a licensed
   source copy. Optional private media import is described in `visual-import.md`.
2. Open `project.godot` in Godot 4.6, or run `godot --path .`.
3. Choose day duration/friendly mode and New game, or Continue a native save.

Missing data blocks starting and displays an import command. No mock replacement
is loaded. Save/Continue uses `user://session.json`, a multi-scene campaign file
with staged validation and healthy backup recovery. Unity saves are not supported.

## Controls and features

- Click a pack to draw. Right-click selects without opening. Drag a card and its
  trailing cards to another eligible stack, or onto open space to split/move.
  Releasing over a UI panel cancels dragging.
- Bottom buttons open Market & controls and Inspect & journal. Sidebars start
  collapsed so the source perspective camera's starter area is not covered.
- Select a card to inspect source text and state. Sell card and sell stack are
  separate commands. Currency can be dropped onto a chest; a sole selected chest
  can withdraw a coin. Source matrix and active-crafting eligibility apply.
- Drop a single equipment card onto a character to equip. Unequip returns gear.
  Select an enemy and Engage to start combat with the nearest available friendly.
  Autonomous mobs also move, produce items and engage using imported AI settings.
- Space pauses. Buttons select speed. WASD or middle-drag pans; the wheel zooms.
  Imported camera metadata supplies perspective FOV, clip planes and source pose.
- Scene-specific shops expose their configured packs, quest locks and prices.
  Buying is a whole-price button, not the source drag-to-vendor installment UI.
- End day feeds villagers, then requires selling excess cards before advancing.
  Daily encounters and friendly-mode filtering are connected. Starvation can end
  a session. Quests and discovered recipes have separate ledgers.
- Completing actual TravelRecipes changes Main/Island, vendors, quests and clock;
  scene contents and timers persist. Save & title stays open if saving fails.

## Geometry and placement

The model retains source X/Z. The view reflects Z consistently for cards, board,
lighting, camera and pointer rays. The original imported FBX board uses its real
vertex/morph bounds; without media a generated surface uses verified source
12x8-to-24x16 bounds. Card geometry uses source colliders even without textures.
Original shaders, fonts, frame/slot artwork and card meshes are not reproduced.

Stack footprints include the source margin, trailing step and first-card size.
The source iteration-limited separation solver handles stack overlap and board
shrink. Pack draws keep the pack locked and remove the former artificial sideways
spawn. Draws, purchases and passive production attempt eligible nearby attachment.
See `board-layout.md` for the boundary between exact target math and approximate
broad phase. Combat rectangles and source animation timing remain separate work.

Source sound mappings play pickup/drop, purchases, sales, normal craft and combat
feedback when the private WAV files exist. Missing background music stays silent.
No listening-level validation has been performed.

## Checks and remaining acceptance

Run `bash tools/test_all.sh`. Tests use temporary HOME/XDG directories and do not
write player saves. Missing-data, synthetic, source-data and cached-FBX checks are
reported separately. `migration-progress.md` records the latest verified counts.

Still required: rendered legibility/clipping at 1440x900 and 1280x800; manual
mouse/keyboard/touch acceptance; source animation/combat presentation; listening
checks; Windows native execution and export packaging. There is no display server
in the current cloud environment. Unity was not launched, per the user's request.

The HUD is an original functional layout, not the original Title/Main/Island UI.
Camera pan is immediate rather than Unity SmoothDamp. No claim of exact physics
query ordering, shader parity, screenshots or final playability acceptance is made.
