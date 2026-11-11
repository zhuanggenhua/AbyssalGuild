# Feeding eligibility and cycle event order

Independent model implementation audited statically against StackCraft revision
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`. No Unity process was launched. This
checkpoint corrects selection and event order inside the existing synchronous
feeding API; it does **not** implement the source's full cycle timeline.

## Source evidence

Paths below are relative to the private source's `Assets/StackCraft/Scripts`:

- `Card/CardManager.cs:62–75,744–811`: AllCards enumerates registered stacks in
  registration/member order, then ongoing combats in registration order, each
  with attackers before defenders. Feeding snapshots both characters and food
  with positive nutrition once. Selection is stable by current 3D distance.
  Selected food leaves the candidate list before consumption; a leftover is
  appended to its tail afterward. Each completed consumption emits stats.
- `Card/CardInstance.cs:261–316`: consumption detaches only the selected card,
  cancels its previous multi-card stack's craft, moves it, then applies nutrition
  and healing. Fully consumed food uses Kill, not ordinary destruction.
- `Core/DayCycleManager.cs:89–149`: selling listens for every stats notification,
  checks immediately on entry, and stops listening before encounter execution.
  It does not require an actual sale to satisfy the excess-card condition.
- `Trading/CardBuyer.cs:54–67` and `Card/CardManager.cs:476–477`: a sale removes
  the sold stack, creates each payout coin separately, and publishes final stats.
  Each coin creation itself publishes stats before card-created. Selling can
  therefore transition during the first coin creation, not just after payout.
- `Encounter/EncounterManager.cs:77–97`: eligibility counts all board cards,
  including currency and packs. The excess-card count excludes both
  (`Card/CardManager.cs:875–880`). Payout order can change encounter eligibility.
- `Card/Components/CardController.cs:43–47,123–148,240–247` and
  `Pack/PackInstance.cs:13–45`: selling removes the cycle input lock, permitting
  normal pack clicks. Pack drawing has no separate playing-only condition.
- `Core/DayCycleManager.cs:153–171` and `Core/TimeManager.cs:140–147`: Start Day
  advances the day and silently restores Normal pace, publishes day-started,
  then invokes SaveGame. This checkpoint leaves that existing order unchanged.

## Implemented behavior

`GameSession._feeding_card_ids()` supplies source-ordered registered IDs without
changing other independently audited world-card consumers. `end_day()` snapshots
character/food eligibility once. Live positions still decide nearest selection,
but later loot or newly positive food cannot join that initial candidate pool.
Equal-distance ties retain queue order, including leftover tail reinsertion.

The cycle's stats observer is installed once after quest tracking. It checks only
while the session is selling. Transitioning to ready before executing the
existing synchronous encounter helper claims the transition before nested spawn
events, preventing duplicate selection. The originating sale or pack draw still
finishes even if its notification changes phase midway through that operation.
For example, encounter card-created can precede the first payout coin's
card-created notification, although the coin already exists on the board.

Pack opening is allowed in playing and selling, but remains rejected atomically
in feeding, ready and game-over. Original root-position pack spawning and
individual-position feeding/death behavior are unchanged. Save schema and public
day APIs are unchanged.

## Limits and source quirks

- Feeding and encounter execution remain synchronous. This does not establish
  camera, lift/travel/chew, leftover settling, encounter notification or spawn
  timing parity. A UI animation added after synchronous mutation would not fix
  combat interleaving or effect timing.
- Distances use settled individual 3D target poses, not source animated current
  transforms. A moving combatant or already-held drag can change source nearest
  food selection. This remains a separate pose/timeline gap.
- Source callbacks can leave dead references after coroutine yields. Native code
  safely skips missing characters/foods and nonpositive remaining food rather
  than reproducing exceptions or zero-progress consumption loops. The initial
  food list still cannot acquire replacements. Combat enumeration avoids feeding
  duplicate IDs if malformed/transitional membership repeats a registered card.
- Shipped characters drop Corpse, not food. The starvation-to-food regression is
  deliberately synthetic. Several shipped mobs can drop food, and one can drop
  a character; their in-flight combat deaths matter to the future timed cycle.
- Equipping changes board membership without a source stats notification. This
  checkpoint does not invent one. A later real stats event can finish selling.
- Source selling checks excess only. It does not re-run the post-feeding
  game-over test on every later stats event. That quirk is retained.
- Source input locks prevent new card presses, but an already-started drag keeps
  updating and can complete after day-end. The current board still discards its
  locked-phase drop. Source camera pan/zoom is locked in these phases; the native
  board still allows navigation. Neither UI behavior is changed here.
- Source blocks normal quit autosave throughout the ending cycle. Native explicit
  mid-cycle Save is an existing extension. A future asynchronous state must be
  saved completely or refused; it cannot silently restart consumption on load.

## Verification

Run `bash tools/test_godot.sh res://tests/godot/test_cycle_order.gd`.

The synthetic cases differentiate snapshot eligibility, registered stack/combat
order, stable equal-distance leftovers, safe removed references, unrelated stats
events after equipment changes, first-payout encounter thresholds/reentry,
zero-price sales, selling pack draws and locked phases. A day-start regression
checks that no extra time-pace event is introduced.

When the private imported catalog exists, source-data cases additionally use
unmodified Stew/Apple nutrition, a natural 99-card day-seven selling board,
Sword's three-coin price, the weekly encounter's 100-card threshold and actual
Starter Pack slot order. No private data is copied into the test. Missing private
data produces an explicit source-data skip while synthetic checks still run.

## Next checkpoint: proposed asynchronous controller contract

This section is a design, not an implemented API.

1. Add a session-owned `CycleController` with a weak session reference.
   `request_end_day()` resets elapsed time, pauses scaled gameplay, enters the
   existing feeding phase and publishes a day-ended event. `begin_feeding()`
   accepts only the awaiting-feed stage, snapshots the ordered IDs and rejects
   repeated requests. The existing UI's manual early-end action can remain a
   documented extension that calls both operations.
2. `advance(real_delta)` advances at most one yielded wait per frame, with no
   scaled AI/crafting/day-time advancement. Pending combat remains ticked with
   `(0, real_delta)` before cycle advancement in the native frame dispatcher.
   This establishes deterministic native ordering; the static source does not
   prove every Unity coroutine tie across managers, so simultaneous-boundary
   behavior must not be called frame-exact Unity parity.
3. Explicit stages: awaiting-feed; character-focus; food-lift; food-travel;
   food-chew; leftover-settle; character-wait; selling; encounter-notification;
   encounter-focus; encounter-wait; ready; game-over. The public session phase
   needs an encounter value so UI action locks and save validation can represent
   that stage without presenting Start Day early.
4. Source durations are realtime: character/camera focus 0.5s when the scene has
   its camera controller, food lift 0.1s, travel 0.2s, chew 0.25s, leftover settle
   0.25s and per-character wait 0.5s. Detach/craft cancellation occurs before lift;
   the travel destination is sampled after lift; old-stack reflow occurs after
   travel; nutrition/healing/Kill occurs after chew; leftover overlap resolution
   precedes reinsertion and its stats notification. No-food starvation still
   waits the per-character interval. Final survivors are checked after all waits.
5. Adapters expose current 3D pose sampling, camera availability and overlap
   resolution. Model stages emit duration, involved IDs and captured positions
   for the view; the renderer does not own completion callbacks. Headless logic
   uses the same clock and scene configuration. A settled-pose fallback must be
   explicit rather than represented as animated-transform parity.
6. Selling retains the event-driven transition above. Encounter selection happens
   once at that event boundary. Mark one-time completion before its optional 2s
   notification wait, spawn each card only at its own boundary, then focus and
   wait 0.5s. Delay ready until the final wait. Start Day, day-started quests and
   the caller's immediate checkpoint retain their present order.
7. Implement transactional export/stage/apply state before enabling mid-cycle
   saves: stage and remaining time, initial ordered queues, character cursor,
   selected character/food, hunger remaining, captured poses/old stack, selected
   encounter and spawn cursor. Never rerun an already-applied effect after load.
   Normalize or explicitly validate dead queued references under the native safe
   cancellation policy. Legacy feeding saves without controller state mean
   awaiting-feed, since the synchronous implementation cannot save mid-loop.
8. Add boundary, repeated-click, combat interleaving, removed-reference,
   per-stage save roundtrip and event-order tests first. Then connect presentation
   and explicit carried-drag handling, with separate board tests. No new native
   gameplay RNG draws should be introduced by cosmetic effects.
