# Runnable Godot board

This is an independently implemented Godot 4.6 UI over source-audited gameplay.
It is a functional migration slice, not visual parity or final manual acceptance.
The public repository includes no original third-party assets or exported content.

## Run

1. Follow `data-import.md` to generate local `data/stackcraft.json` from a licensed
   source copy. Optional private media import is described in `visual-import.md`.
2. Open `project.godot` in Godot 4.6, or run `godot --path .`.
3. Choose New Game, set day duration/friendly mode, then Confirm. Load Game opens
   the native save picker; choose a slot and Continue. Cancel/Back returns home.

Missing data blocks starting and displays an import command. No mock replacement
is loaded. Save/Continue selects a native multi-scene slot under
`user://slots/SaveSlotNNN.json`, with staged validation and healthy backup recovery.
Legacy single-save files are offered for explicit copy into a fresh slot and kept
unchanged. Unity saves are not supported. See `save-slots.md`.

## Controls and features

- Click a pack to draw. Right-click selects without opening. Drag a card and its
  trailing cards to another eligible stack, or onto open space to split/move.
  Tail pickup splits immediately and pauses only the original craft. Returning
  it resumes the same timer. A captured release over UI or after opening Pause/
  Options still resolves that hold once; it does not silently cancel or roll back.
  See [held-stack lifecycle](held-stack-lifecycle.md).
- The bottom Market & controls button opens the native trade controls. The
  right inspection/journal panel starts open from source UIRoot metadata and
  toggles with << / >> using the source 0.5-second real-time slide. Repeated
  clicks while it moves are ignored. Missing metadata uses an explicit closed
  fallback. The independent native market starts collapsed.
- Select a card to inspect source text and state. Sell card and sell stack are
  separate commands. Currency can be dropped onto a chest; a sole selected chest
  can withdraw a coin. Source matrix and active-crafting eligibility apply.
- Drop a single equipment card onto a character to equip. Unequip returns gear.
  Select an enemy and Engage to start combat with the nearest available friendly.
  Autonomous mobs also move, produce items and engage using imported AI settings.
- Escape opens the pause menu during play; its Options panel preserves the
  selected pace, applies supported preferences and reports unsupported mappings.
  Ending-cycle locks prevent opening it during feeding/selling/encounter/ready/game-over.
  See `options-ui.md`. Space pauses. The always-visible day clock shows progress
  and cycles Normal → Fast → Paused; separate buttons select supported speed.
  WASD or middle-drag pans; the wheel zooms.
  Imported camera metadata supplies perspective FOV, clip planes and source pose.
- Scene-specific shops expose their configured packs, quest locks and prices.
  Source-positioned buyer/vendor plates now accept dropped card tails, including
  partial coin and chest payments. Whole-price buy buttons remain available.
  Vendor labels show collection counts or COMPLETED.
- End day advances real-time focus, food travel/consumption and encounter waits,
  then requires selling excess cards before advancing.
  Daily encounters and friendly-mode filtering are connected. Starvation can end
  a session. Active/completed quests stay under their configured groups; discovered
  recipes group by source category. Headers collapse without marking rows read.
  Hovering a visible individual row marks its raw item ID read; opening tabs marks nothing.
- Completing actual TravelRecipes changes Main/Island, vendors, quests and clock;
  scene contents and timers persist. User scene changes fade to black for one real
  second, commit, and fade back for one second. Departure travel/title checkpoints
  are captured before fade; failures retain the current game. Save & title stays
  open if saving fails.
- New Game opens preferences without allocating; Confirm creates a fresh slot
  without overwriting existing games. Confirmed Start Day
  and travel checkpoint automatically. Game-over Return asks before archiving the
  ended slot; no deletion happens merely on death. The title picker reports scene,
  quest percentage, UTC file time and backup recovery.
- New card drag/sale/trade presses allow playing and selling only. Feeding,
  encounter, ready and game-over lock new presses; a previously granted held drag
  may finish across the boundary. Manual pause retains playing-phase card interaction.

## Geometry and placement

The model retains source X/Z. The view reflects Z consistently for cards, board,
lighting, camera and pointer rays. The original imported FBX board uses its real
vertex/morph bounds; without media a generated surface uses verified source
12x8-to-24x16 bounds. Card geometry uses source colliders even without textures.
Private Card/Pack FBX and an independently rewritten UV shader can now be used
when the licensed assets and import cache are available. Generated geometry remains
the fallback. Source title destinations, gameplay preferences, day clock, journal
groups and transitions are connected in native controls. Original fonts and exact
Title/Main/Island canvas geometry are not reproduced; GPU/rendered acceptance is
still required.

Stack footprints include the source margin, trailing step and first-card size.
The source iteration-limited separation solver handles stack overlap and board
shrink. Pack draws keep the pack locked and remove the former artificial sideways
spawn. The central factory attempts eligible nearby attachment before creation events,
with explicit exclusions for processing stacks, encounters, restoration and
withdrawal. Friendly mode applies to every ordinary factory output.
See `board-layout.md` for the boundary between exact target math and approximate
broad phase. Combat rectangles, fighter rows, drag-to-join/start and attacker-only flee are
now connected. Initial center/cell spacing persists through native saves; the
AI uses that actual center. Saved combat phases now drive source-timed hit/return/death behavior and native
attack/projectile/hurt views; interpolation and rendered acceptance remain separate.

Source sound mappings play pickup/drop, purchases, sales, normal craft and combat
feedback when the private WAV files exist. The restored background music is
bound and structurally tested; missing optional music still stays silent.
No listening-level validation has been performed.

## Checks and remaining acceptance

Run `bash tools/test_all.sh`. Tests use temporary HOME/XDG directories and do not
write player saves. Missing-data, synthetic, source-data and cached-FBX checks are
reported separately. `migration-progress.md` records the latest verified counts.

Still required: rendered legibility/clipping at 1440x900 and 1280x800; manual
mouse/keyboard/touch acceptance; remaining source animation/presentation fidelity; listening
checks; Windows native execution and export packaging. There is no display server
in the current cloud environment. Unity was not launched, per the user's request.

The HUD is an original functional layout, not the original Title/Main/Island UI.
Camera pan uses the source SmoothDamp parameters; focus/zoom and cycle navigation
locks are covered headlessly. No claim of exact physics
query ordering, shader parity, screenshots or final playability acceptance is made.

## Slot and combat-merge regression suites

`test_slot_ui.gd` covers the new picker/checkpoint/phase workflow. `test_combat_board.gd` additionally covers automatic pre-start and post-resize rectangle overlap merging through pure geometry callbacks, replacing old task rectangles without returning still-fighting units to the board. This uses target-pose rectangle/collider geometry and registration order, not a claim of Unity physics hit order or animated combat parity.

Trade-zone geometry, drop order, nonterminal payments and per-item collection
presentation are documented in `trade-collection-ui.md`.


Realtime cycle details and carried-input boundaries are in
[cycle board UI](cycle-board-ui.md). Source-event Puff requests now use native
private-texture emitters with independent cosmetic randomness and separate real
particle/scaled emitter clocks. See [Puff lifecycle](puff-board-lifecycle.md).
Standard alpha blending approximates the unavailable source built-in shader.


The title screen now offers confirmed selected/all-listed slot archiving and an
archive inventory with validated restore-copy to a fresh slot. Restore remains
on the title and never silently loads/replaces a campaign. Stale confirmation,
invalid archive and interrupted flows preserve existing data. See
[slot management UI](slot-management-ui.md).


Required Feed / Start Day / Game Over actions are always visible in the top
summary, even with both sidebars collapsed. Chest singleton clicks withdraw
one coin; dragged/repeated releases do not. Pace controls expose only source
Normal (1x) and Fast (2x), with ending-phase/menu guards. See
[cycle action visibility](cycle-action-visibility.md). Generated recipe-card
ingredient descriptions now survive pack/research creation and cold Continue.


Title destinations, day-clock bindings, journal groups and source-timed scene/menu
transitions are documented in [title navigation](title-navigation.md),
[day clock](day-clock-ui.md), [journal groups](journal-groups.md),
[scene transitions](scene-transitions.md) and [menu slide](menu-slide.md).


Explicit time-pace changes animate world grayscale; day boundaries animate the
source vignette. External menu/transition pauses do not invent pace events. The
world-only native shader leaves HUD text unfiltered. Source-mapped text controls,
Friendly Mode, journal tabs/groups and modal actions request Click after their
callbacks; native convenience actions are not blanket-mapped. See
[world post-process](world-post-process.md) and [UI feedback](text-button-feedback.md).
These are headless-verified bindings, not rendered or listening acceptance.
