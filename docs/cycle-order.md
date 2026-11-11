# Feeding eligibility and cycle event order

Independent model implementation audited statically against StackCraft revision
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`. No Unity process was launched. This
eligibility checkpoint established selection and event order. The live feeding
path now uses the asynchronous controller documented in [Cycle timeline](cycle-timeline.md).

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
while the session is selling. Transitioning to encounter before claiming the
event prevents nested spawn notifications from selecting it again. Selection
remains synchronous; notification, spawns and ready use the realtime controller.
The originating sale or pack draw still
finishes even if its notification changes phase midway through that operation.
For example, encounter card-created can precede the first payout coin's
card-created notification, although the coin already exists on the board.

Pack opening is allowed in playing and selling, but remains rejected atomically
in feeding, encounter, ready and game-over, except for a verified carried press.
Original root-position pack spawning and individual-position feeding/death rules
are preserved. The save format version remains compatible through a validated cycle
subsystem. `end_day()` now starts work without completing it synchronously;
Start Day remains ready-only.

## Limits and source quirks

- Feeding and encounter waits now advance the model itself, allowing pending
  real-time combat effects to interleave. See the timeline document for effect
  boundaries, clock behavior and save invariants.
- Distances use an injected current-pose sampler when available, with settled
  individual 3D targets as the explicit headless fallback. The controller
  reconstructs its own selected-food movement. Other source transform/physics
  and nonzero stack-root heights are not established as cross-engine identical.
- Source callbacks can leave dead references after coroutine yields. Native code
  safely skips missing characters/foods and nonpositive remaining food rather
  than reproducing exceptions or zero-progress consumption loops. The initial
  food list still cannot acquire replacements. Combat enumeration avoids feeding
  duplicate IDs if malformed/transitional membership repeats a registered card.
- Shipped characters drop Corpse, not food. The starvation-to-food regression is
  deliberately synthetic. Several shipped mobs can drop food, and one can drop
  a character; their in-flight combat deaths now interleave with the timed cycle.
- Equipping changes board membership without a source stats notification. This
  checkpoint does not invent one. A later real stats event can finish selling.
- Source selling checks excess only. It does not re-run the post-feeding
  game-over test on every later stats event. That quirk is retained.
- Source input locks prevent new card presses, but an already-started drag keeps
  updating and can complete after day-end. The original eligibility checkpoint
  did not implement that exception. Carried-input and
  camera behavior are covered by the separate cycle UI integration, not this
  model-only audit. Selling removes the cycle input lock, including camera input.
- Source blocks normal quit autosave throughout the ending cycle. Native explicit
  mid-cycle Save is an existing extension. The controller now persists complete
  pending state and refuses captures inside a synchronous effect transition.

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

## Asynchronous integration

The implemented contract, effect boundaries, complete-state persistence and
remaining renderer limitations are documented in [Cycle timeline](cycle-timeline.md).
The shared test driver advances the real controller; legacy final-rule tests no
longer assume synchronous feeding. `WorldRules.finish_day` remains an explicit
synchronous utility for isolated encounter-rule tests, not the live session path.
