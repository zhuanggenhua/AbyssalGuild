# Source combat execution timeline

Independent static implementation based on locked StackCraft revision
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`. Relevant source:
`Combat/CombatTask.cs` (Update, AttackSequenceCoroutine, removal/merge),
`Combat/CombatManager.cs` (reverse Update iteration, SpawnProjectile),
`Combat/UI/CombatProjectile.cs`, `Card/Components/CardCombatant.cs`, and
`Card/Components/CardController.cs`. No Unity runtime or original source copying.

## Clocks and phases

`combat.tick(scaled_delta, real_delta)` advances one frame. One-argument calls use
that delta for both clocks for existing headless callers. Session's bridge calls
this with zero scaled delta when paused or not playing, otherwise delta × speed;
real delta is the unscaled input delta. Playing frames retain the existing AI then
combat ordering; source MonoBehaviour ordering is not explicitly declared. The board
must call only `combat.tick(0, delta)` when an external menu lock skips Session.tick,
not both paths in one frame. This adapter is essential for paused-time parity.

A task without `execution` is Idle. Its one-second timer decreases only while
Idle. Timeout chooses the greatest-progress non-dragged fighter and draws target
RNG, then begins travel. During all phases, living participants gain AttackSpeed ×
scaled delta. Zero-health participants do not gain progress: the source outer loop
visits them, but CardCombatant.AddActionProgress checks CurrentHealth > 0.

- `travel`: melee/None uses 0.3 real seconds. Ranged/Magic resolves the scene's
  referenced projectile component duration. Locked Arrow/Magic imports specify
  0.5; the C# 0.6 default applies only when a present component omits the field.
- At impact, resolve hit/crit RNG and stats NOW, not at selection. Health changes,
  combat_hit emits, and return begins. Captured combat type controls presentation;
  current definitions/stats still control damage/RPS, matching the source.
- `return`: 0.3 real seconds. Actor remains attacking and cannot begin a UI drag.
  A lethal defender remains registered with zero health during this phase.
- After return, clear attacking. If target has zero health, unlink it without
  normal immediate-end logic, Kill it (including loot), and begin `death_wait`.
  Otherwise reset actor progress and return to Idle.
- `death_wait`: 0.5 scaled seconds. Other living progress continues. At completion,
  reset actor progress and end the fight if a side is empty, else return to Idle.

Resetting after execution discards the actor's accumulated execution progress;
other living fighters retain theirs. Tasks update newest registration first, as
CombatManager.Update does, so shared target/hit RNG ordering is reproducible.
Only one phase boundary resumes per frame; unused elapsed time is not carried
through a chain of coroutine yields. This is an explicit discrete-frame model,
not a claim of exact DOTween execution-order equivalence on every Unity frame.

## Events and interaction

- `combat_attack_started`: combat_id, attacker_id, defender_id, captured
  combat_type, duration, and attacker_position/defender_position Vector2 snapshots.
- `combat_hit`: combat_id, attacker_id, defender_id, captured combat_type, result.
- `combat_return_started`: same IDs/type and duration 0.3.
- `combat_attack_blocked`: combat_id, attacker_id, reason for missing projectile.

`is_attacking(card_id)` is true only for the active actor in travel/return.
`can_drag_combatant(card_id)` also requires the player attacking side, as
CardController's pointer gate does. It becomes true again during death_wait.
Backend Flee remains source-permissive; the UI must use the drag gate. Forced
external removal remains possible and is covered separately below.

The model never schedules visual tweens or delays from event listeners. Moving
attack sound to started and impact audio to hit avoids duplicate/mistimed sounds.
Actual jumps/projectiles/return animations remain presentation work. Positions
are settled logical targets, not simulated intermediate jump transforms.

## Pose capture, merge and safety decisions

Before creating or joining, capture ALL participant settled positions using
Session.capture_card_targets, then detach using those snapshots. Removing an
earlier stack member must not shift later members' recorded starting positions.
The same batch capture runs for the final combined group in a merge.

Merge directly discards old execution state without normal survivor cleanup,
creates the replacement task and reinitializes progress once. A noteworthy source
edge is preserved: merging during a lethal return cancels that return but retains
the zero-health victim. It can later act from initial random progress despite not
gaining further progress. Save validation therefore cannot infer invalidity solely
from zero health, even for an actor or a non-target member.

Source RemoveCombatant does not cancel a dangling coroutine when an externally
removed actor/target leaves both sides populated. Native code safely cancels that
execution instead of accessing a destroyed object or rerolling a replacement.
If a side empties externally, normal removal ends the fight immediately. Flee of
the executing actor has the same safe cancellation when invoked directly; normal
UI drag initiation is blocked until its attacking flag clears.

Source SpawnProjectile unconditionally instantiates the referenced prefab and
calls Fire. It does not actually return null for missing source prefabs; that
would throw despite the caller's null-tween guard. Native code fails closed with
combat_attack_blocked, remains idle, and does not fabricate impact/duration.
A later normal turn may retry after configuration is repaired.

## Atomic snapshots

Optional `execution` stores exactly phase, remaining, actor, target, combat_type,
attacker_position and defender_position. Pose arrays are JSON-safe. A death-wait
target is -1 because the killed card has already been removed. A side may be empty
only during death_wait; its actor must still exist. Travel/return actor and target
must be opposing members. Remaining is finite, nonnegative and bounded by the
actual phase duration. Captured types and coordinates are validated before commit.
`stage_state(raw, cards, scene_name="")` accepts explicit validated snapshot scene
context for projectile lookup without mutating the live scene. An omitted context
defaults to the live scene for legacy direct callers. No Callables, tweens or scene
objects are serialized. Legacy tasks lacking
execution remain valid Idle saves. Restored return/death phases never reroll hits
or apply damage twice; paused saves retain both timeline and gameplay RNG.

## Verification

`bash tools/test_godot.sh res://tests/godot/test_combat_timeline.gd`

The focused synthetic suite covers exact delay transitions, scaled/real clocks,
paused impacts, late equipment/stat/type changes, target versus impact RNG timing,
actor reset, zero-health progress guard, delayed lethal end, valid projectile
configuration/default/missing cases, reverse concurrent-task RNG order, mid-phase
atomic save/restore, invalid snapshot nonmutation, legacy saves, merge/removal/flee
cancellation, source-legal zero-health merged actors, and batched stack pose capture.
The existing combat suite was updated to expect deferred completion, not instant
hits. Save codec adversarial tests provide additional cross-state coverage.

The suite also resolves actual private Main/Island CombatManager references and
runs ranged/magic travel-to-return transitions from their imported cards and
projectile prefabs when local data exists (59 checks with private data). Public
runs without that data explicitly print a skip and run 45 synthetic checks.
