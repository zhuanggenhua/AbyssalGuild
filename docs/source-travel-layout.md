# Saved-destination travel registration geometry

This deliberately narrow adapter runs at the actual native Board scene-entry
boundary, not inside model deserialization or the staged travel transaction.
It retains the current migration's RNG, event, ID and checkpoint contracts.
It does not claim Unity Random/PhysX or all future gameplay equivalence.

## Locked source schedule

Reference: `a11a89b04cea8370476f2559b639bb9b4cbc08d8`, paths relative to
`Assets/StackCraft/Scripts/`:

- `Core/GameDirector.cs:58–69,180–229`: save/capture departure, fade, spawn incoming
  travelers in their original list order, then dispatch saved scene data. Each
  traveler samples its position before its own restoration call.
- `Card/CardManager.cs:247–290,304–317,348–365`: every traveler initializes an
  individual stack; its gear initializes at zero and immediately unregisters on
  equip; only then does the next traveler initialize. Saved destination stacks
  follow, including their per-card initialization and saved-anchor resets.
- `Core/TimeManager.cs:47–59`: external pause does not suppress an already-reached
  day boundary. Both departure and destination clocks must be below duration.
- `Core/Board.cs:24–77`: Awake caches authored base bounds; Start subscribes
  and reads the complete stats snapshot. Positive first expansion does not call
  the shrinking-only EnforceBoardLimits. `Combat/CombatManager.cs:85–132` and
  `Crafting/CraftingManager.cs:110–131` still need separate restoration proofs.

The supported travel recipe is the locked `Recipe_Travel_Island` resource:
one Grand Portal plus one Villager base-definition, strict counts and no extra
ingredients. Consumption and source delayed-destruction uncertainty remain as
documented in [travel.md](travel.md). The source's
traveler list therefore has **two card IDs**, not one; equipped items are mapped
separately. Multiple/unknown characters and different recipes are not admitted.

## Transaction boundary and identity

`Board._request_travel` captures the exact source stack's card order, equipment,
and saved destination before the unchanged candidate `campaign.travel` call.
It seals the actual returned `traveler_ids` map **before** the departure checkpoint
replaces the result dictionary. The bound scene-transition callable owns this
live-only context. No IDs are guessed from ranges, names, order of final registry,
or positions; no data is added to campaign/save serialization.

At the existing black-frame `_commit_travel`, the validated candidate swap is
unchanged. `_enter_game` establishes destination geometry, then admits the
one-shot context before the first view refresh. Complete candidate identity,
snapshot, saved-stack membership/anchors, equipment owner/slot/class, and source
metadata must still match. The existing shadow planner computes the complete
schedule before its atomic geometry/order apply. Its signature suppresses a
second ordinary whole-board solver pass. Consumed, cancelled or stale contexts
cannot later attach to a different entry.

Departure-save rejection, duplicate request, cancel/stale-owner behavior and
arrival-save handling remain the existing native policy. Geometry admission
failure is **not** travel failure: it retains the old whole-board entry path.
The adapter never invokes spawn/equip, samples RNG, emits gameplay signals,
allocates entity IDs, writes a slot, or runs on a normal refresh. Arrival's normal
checkpoint records the resulting targets; the departure checkpoint remains the
same pre-transition snapshot. No geometry operation is inserted into validation
copies or the preserved saved-quest subscription window.

## Positive initial destination expansion

Unity documents [sceneLoaded before Start](https://docs.unity.com/zh-cn/engine/6000.5/script-reference/unityengine/scenemanagement/scenemanager/sceneloaded).
The locked traveler list contributes no capacity booster. Saved boosters become
registered during synchronous OnSceneDataReady restoration, but Board has not
subscribed yet. All per-card overlap/anchor work therefore uses authored initial
bounds. Board.Start then reads the full registered snapshot and expands the mesh;
it does not run the shrink-only limit enforcement. No relative Start ordering
between different objects is assumed.

The existing `source_board_expansion.gd` descriptor validates source prefab/scene
hashes, initial weight zero, transforms and actual FBX base/final bounds, plus
known positive Warehouse/Yard contributions. Its base bounds drive the shadow
plan while final presentation bounds are retained. Raw capacity may exceed100;
mesh weight alone caps100. Isolated anchors and attachment-forbidden packs are
not blanket-clamped. A later refresh cannot replay the entry schedule.

## Explicit exclusions

Only already-saved Main↔Island destinations, with the locked source metadata and
zero or verified positive initial destination boost, are admitted. Departure and destination must be
playing/idle, below day duration, unheld and without combat. Other departure
crafting and any destination active crafting are excluded; the travel recipe's
own completing stack is allowed. New/default destinations, negative/shrinking or unverified expansion,
nonzero authored weight, all day-end/selling states, nested/replacement equipment, custom pack attachment,
missing metadata and incomplete or stale provenance all fall back as a group.
Expanded departure alone does not invalidate an otherwise admitted destination.

The registration order and geometry intentionally change. Future feeding queues,
equal-distance AI targeting and distance queries may therefore change. Equal
current RNG state and equal next raw samples do **not** prove equal future draw
counts, association, or gameplay outcomes. Source equipment visuals consume
Unity random values not reproduced here. This work is a conditional source-order
geometry correction given the migration's existing spawn coordinates, not a
new random algorithm or full Unity engine execution.

## Reproducible verification

`test_source_travel_layout_board.gd` runs actual Board request/checkpoint/fade
commit/arrival save/readback calls headlessly in isolated user data. It covers
both directions, with/without three-slot gear, positive boosts4/14/100/110,
base-before-final phase counterexamples, saved packs, strict provenance rejection,
one-shot entry and no subsequent solver, failed departure save, duplicate/cancel
and stale-owner routes. It checks nongeometry state, exact IDs, RNG state,
equipment, quests and inactive scenes; JSON readback is normalized only for
JSON numeric representations, intended target positions and stack order.

Optional `SOURCE_TRAVEL_REAL_MAIN` / `SOURCE_TRAVEL_REAL_ISLAND` input paths test
existing portal and equipped-character actions on authentic old saved copies.
Input hashes are checked unchanged. Only normal save APIs write isolated copies.
`SOURCE_TRAVEL_REPORT` writes a private machine-readable report. These are model
and production-Board sequence tests, not GUI/natural travel or rendered acceptance.
The private independent source-equation/fixed-coordinate oracle remains separate
from the public test to avoid distributing source resources or private saves.

## Source-locked ordinary arrival persistence

The accepted ordinary original travel receipt now leaves the departure file and
backup unchanged at arrival, matching the locked source save callsites. Live
arrival layout is checked before explicit Save; disk geometry is checked after
that Save. Unsupported or unverified requests retain native arrival autosave.
See [arrival persistence](source-arrival-persistence.md).
