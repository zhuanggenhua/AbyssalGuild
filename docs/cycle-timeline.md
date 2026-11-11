# Realtime feeding and day-cycle controller

Independent implementation against the locked source described in
[Cycle order](cycle-order.md). No original source/assets are included and no
Unity executable was run. This is functional timeline coverage, not a claim of
pixel, audio-device, physics or cross-engine coroutine scheduling equivalence.

## Live API and clocks

`GameSession` owns `cycle_controller.gd`. Automatic day timeout invokes
`cycle.request_end_day()`, resets elapsed time to zero, pauses scaled gameplay,
publishes day-ended and waits in `feeding / await_feed`. `end_day()` begins
feeding and returns the current stats immediately. Calling it while feeding is
already running does nothing. The native manual early-end button can request
day-end and feeding together; the source normally reaches this through timeout.

While paused or outside playing, `GameSession.tick(delta)` advances pending
combat with `(0, delta)`, then advances the cycle with real time. AI, production,
crafting, idle combat accumulation and day elapsed time do not advance. Existing
combat travel/return and resulting impacts/Kills still do. Its lethal 0.5-second
death wait remains scaled and stays paused until a new day resumes gameplay.

The controller advances **at most one expired yielded wait per frame**. A large
delta cannot consume the following wait too. Native combat-before-cycle ordering
is deterministic; static source inspection does not establish exact ordering of
simultaneously resumed Unity coroutines across different managers.

Start Day remains accepted only in ready. It clears cycle state, increments the
day, silently resets normal pace, emits day-started and returns. The board then
checkpoints in the same call, preserving existing quest-before-save order. Quit
continues to skip autosave throughout ending-cycle phases. Explicit Save is a
native extension supported by complete controller snapshots.

## Feeding effect boundaries

The initial character and positive-food queues retain source registered-stack
then combat order. Later loot, new characters and initially empty food cannot
enter those queues. Stable nearest-distance ties and leftover tail reinsertion
are retained.

1. Focus the next surviving queued character for 0.5 seconds if that scene has
   its camera controller. Camera presence resolves direct scene components and
   scene-referenced prefabs, independently of a rendered view.
2. Choose nearest food. If none exists, Kill the character and enter its final
   0.5-second wait. Otherwise remove food from the candidate queue and detach
   only that food from a multi-card stack, cancelling that stack's craft.
3. Lift for 0.1 seconds. The food remains registered in a stack and still counts
   toward stats; source creates and registers its new singleton stack immediately.
   There is no special orphan/hidden-food ownership exemption.
4. Sample the character's current position after lift, play CardSwipe and travel
   there for 0.2 seconds at source DragHeight. At arrival play Eat and wait 0.25
   seconds. Nutrition and health remain unchanged until that wait finishes.
5. Subtract nutrition, apply source banker-rounded proportional healing, and Kill
   depleted food. Leftover food moves its model stack to the captured target and
   waits another 0.25 seconds before overlap resolution and tail reinsertion.
6. Publish stats only after that consumption completes. Continue remaining hunger
   or wait 0.5 seconds for the finished character. Only after all character waits
   does the controller check final survivors and enter selling or game-over.

The source reflows the previous stack after travel; the native target-only stack
representation already reflects changed membership. Its precise animated reflow
and nonzero stack-root-height behavior remain renderer/geometry limitations.
Current-pose sampling can improve live nearest selection without pretending that
headless settled poses equal animated Unity transforms.

## Selling and encounters

Selling reacts to stats notifications, including nested first-payout coin events.
It claims `encounter` phase before selecting, so later stats cannot reenter.
`WorldRules.claim_day` performs selection once and records one-time completion.

An encounter notification is published before spawning. A nonempty message waits
2 realtime seconds. Each card then spawns at its own boundary with its own RNG
position draw, focuses for 0.5 seconds when a camera exists, requests Puff, and
waits 0.5 seconds. Start Day cannot appear until the last wait finishes. Queued
combat effects can interleave between these spawns.

`WorldRules.spawn_encounter_card` performs one spawn. `finish_day` remains an
explicit synchronous convenience for isolated rule tests; live session code does
not use it. `encounter` now describes selection/notification with an empty spawned
list. `encounter_completed` contains the final spawned IDs.

## View adapters and events

Model effects never wait for renderer completion callbacks. Scene metadata and
the controller's clock decide timing, including in headless tests.

- `pose_sampler(card_id)` may return the current source-coordinate Vector3. A
  missing/invalid result uses the individual settled target pose. Selected food
  instead uses the controller's reconstructible OutQuad movement, avoiding
  feedback from a renderer that is itself applying that motion.
- `layout_resolver()` runs at leftover settling completion. No gameplay RNG is
  required by these adapters.
- `presentation_state()` returns the selected food's stage, card ID, source/from
  and target/to Vector3, total duration and elapsed time, or an empty dictionary.
  `presentation_pose(id)` returns its computed pose or null. These are read-only.
- `focus_state()` returns a saved target, remaining duration, reason and card ID
  only during active focus. Continue can restore the remaining camera motion
  without replaying sounds or resetting the model's wait.
- `cycle_focus_requested`, `cycle_food_motion`, `cycle_sound` and
  `cycle_stage_changed` expose the same boundaries to the view.
- `puff_requested` carries card ID and captured source-coordinate Vector3. Kill
  publishes its existing early card-killed event, cleans equipment/combat and
  creates loot, then requests Puff immediately before removal. Fully consumed
  food, exhausted packs and starvation use this path; ordinary sale/destruction
  does not. Encounter Puff occurs after focus and before the post-spawn wait.

The board reflects source Z once. Its carried-press exception passes
`open_pack(id, carried_press=true)` only for a verified already-started press.
The default still rejects new pack actions outside playing/selling. Other card
mutations remain subject to the board's input locks. Source selling unlocks camera
and card input; Escape remains blocked throughout the ending cycle.

## Complete-state saves and recovery

The existing format version gains an optional `cycle` subsystem. `SaveCodec`
validates it after staging cards, stacks, combat/equipment and world claims, and
commits it only with the rest of the validated snapshot. The saved state includes
stage/remaining time, ordered initial queues, current cursor/character/food,
remaining hunger, original/captured food poses, old stack identity, focus target,
selected encounter and completed spawn cursor/IDs.

Validation checks phase/stage consistency, finite bounded durations/positions,
integer identities, queue uniqueness/disjointness, source hunger limits, selected
food registration and encounter claim/cursor consistency. Missing historical queue
IDs may be retained after deaths; they are not substituted with new cards. Live
food still requires normal registered stack ownership. Passive states cannot hide
queued work. Encounter snapshots require complete controller state and matching
processed-day/one-time world claims.

Snapshots requested from inside synchronous effect callbacks are rejected as
transitioning rather than saving half a Kill, heal or spawn. Stable active wait
states are saveable. Loading a chew wait applies its effect once later; loading
leftover-settle never applies nutrition/healing again. Invalid data leaves the
live session unchanged.

Legacy snapshots without this subsystem infer passive state from their phase.
Legacy feeding means awaiting Feed confirmation, because the former synchronous
implementation could not produce an active mid-loop snapshot. Legacy encounter
without a cursor is rejected instead of rerolling or duplicating an event.

SaveSlots uses Campaign's strict staged validation for its picker/header checks;
there is no separate phase allowlist to widen. Tests cover active encounter slot
create/list/load and validation of an inactive scene's pending cycle before
switching the active campaign scene.

## Deliberate safety behavior and verification

The source does not guard every reference after a coroutine yield. Native code
skips a vanished character; if selected food disappears, it tries only the
original remaining pool. If the eater disappears, unconsumed food is retained
without charging hunger/healing. This is a safety divergence, not a reproduction
of source dangling-reference exceptions.

Run `test_cycle_timeline.gd` and `test_cycle_order.gd` through `tools/test_godot.sh`.
They cover effect boundaries, no repeated Feed, one boundary per frame, camera
presence, registered in-flight food counts, two-clock combat interleaving, safe
missing references, first-payout selection, sequential encounters, every waited
stage's JSON continuation, corrupt snapshots, legacy saves and native slots.
Private source-data regressions use unmodified Main/Island camera prefabs and food
definitions; public runs explicitly skip those cases when data is absent.

The independently reviewed `test_cycle_save_validation.gd` additionally probes
all saved phases, bounded random encounter positions, no-double-charge invariants,
real selected-food/eater disappearance, slot header corruption and inactive-scene
atomic rejection. A positive leftover requires zero remaining hunger; a living
character cannot already be in its final wait with unsatisfied hunger.

`tests/godot/cycle_test_driver.gd` lets existing final-rule tests advance the real
timeline. It never invokes an immediate feeding bypass. Separate UI tests own
buttons, restored motion and carried input. No live display, listening or Windows
acceptance is implied by these headless checks.
