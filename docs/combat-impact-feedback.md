# Combat impact presentation and timing audit

Static-only audit of locked StackCraft revision
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`. No Unity launch, listening assessment,
visual acceptance or copied source/assets.

## Small, timing-safe implementation

`impact_feedback.gd` describes presentation for an already resolved hit without
changing health, membership, loot, turn timers or RNG. Its public functions are:

- `attack_sound(combat_type)` returns the source AttackMelee/Ranged/Magic event.
- `hit_ui_fields(data, scene_name)` resolves scene CombatManager.hitUIPrefab into
  private imported HitUI fields. Missing source assets return empty fields.
- `describe(combat_type, result, hit_ui_fields={})` returns ordered impact sounds,
  damage text, imported sprite references and exact flash/popup/punch/shake inputs.

Critical impact must play both Hit<Type> and Critical, in that order. The existing
board handler selected Critical instead of Hit<Type>, losing the first sound.
Miss plays only Miss and never flashes/shakes. Zero-damage normal/critical results
still play hit effects. The descriptor deliberately does not bundle attack sound
with impact: source attack audio occurs before travel, not at the hit.

The source HitUI shows no damage number on miss. Normal/critical show the integer
damage including zero. Effectiveness icons follow advantage independently. All
sprite references come from the privately imported scene-referenced prefab, not
hard-coded GUIDs or public asset copies.

A board adapter can use this descriptor at its existing `combat_hit` handler.
Capture defender position/transform immediately: the current model may remove a
lethally hit card before the next frame. Place popups under a transient effects
root, independent of the card's lifetime. Flash only surviving valid views, cancel
previous hurt tweens, and restore visual state on interruption. Apply card rotation
only to visual children, never collider/gameplay positions. `flash_amount` already
exists in `scripts/ui/shaders/card_surface.gdshader`. Use a local/cosmetic RNG for
camera noise, never session.rng. Dispose tweens/popups on scene changes or unload.

## Exact source evidence

Paths below are relative to `Assets/StackCraft/Scripts`.

- `Combat/CombatTask.cs:125–150`: enter ExecutingTurn, set attacking flag, play
  attack sound; Melee/None jumps to defender +0.05 world Y, jump power 1, one jump,
  0.3 seconds unscaled. Ranged/Magic awaits projectile arrival.
- `Combat/UI/CombatProjectile.cs:Fire`: linear unscaled travel, horizontal facing,
  destroy projectile at completion. C# default is 0.6 seconds, but both referenced
  private Arrow/Magic prefabs serialize 0.5 seconds. A future timing implementation
  must read the actual scene-referenced prefab duration rather than use the default.
- `Combat/CombatTask.cs:153–172`: roll hit/critical at impact, apply damage, shake
  camera, play type-specific impact audio, then additional Critical if applicable.
  Spawn HitUI using defender.TransformPoint(0.3, 0.1, 0.4), not a world-space offset.
- `Card/CardInstance.cs:458–476`: health clamps at zero and display updates before
  hurt effects. Replace prior hurt sequence. Flash rises to 1 over 0.1 seconds,
  delayed 0.05 seconds, two yoyo legs. Join Y-rotation punch 15 degrees lasting
  0.25 seconds, vibrato 25. Entire sequence is unscaled.
- `Core/CameraController.cs:179–182`: additive unscaled camera shake with defaults
  0.3 seconds, strength 0.1.
- `Combat/UI/HitUI.cs:Initialize`: hit/effectiveness sprites and number rules above;
  scale punch (0.15, 0.15, 0), duration 1 second unscaled, then destroy popup.
  DOTween default easing/punch internals were not reverse-engineered here; supplied
  metadata reproduces explicit source parameters, not a claim of identical curves.
- `Combat/CombatTask.cs:174–210`: return jump lasts 0.3 seconds unscaled for melee;
  ranged/magic wait 0.3 real seconds. Then clear attacking flag. Lethal victims are
  removed/killed, layout updates, then wait 0.5 SCALED seconds. Only afterward reset
  actor progress and end combat or return to Idle.
- `Card/CardInstance.cs:483–507`: Kill publishes card-killed, cancels movement/
  combat tweens, unequips, removes combat membership, rolls loot, creates puff,
  then destroys the card. `Card/VFX/PuffParticle.cs:Awake` plays Puff and destroys
  the particle after its imported particle-system duration +0.1 seconds.
- `Core/AudioManager.cs:115–125,145–178`: optional random pitch draws Unity's shared
  Random; locked AudioManager prefab disables pitch randomization. Cooldowns use
  unscaled time. Source uses PlayOneShot on pooled sources; current Godot adapter
  stops/replaces its selected player, another possible audio-overlap distinction.

## Later gameplay timing work, explicitly excluded

Current CombatSystem resolves target selection, hit RNG, health update, hit event,
actor reset and lethal cleanup synchronously in one turn. It has no ExecutingTurn
phase. Current board plays attack/impact sounds together and has no projectile,
per-card health display, flash, punch, camera shake, hit popup or puff effect.
Health can be read in the selection inspector.

Adding travel/return delays is NOT safely cosmetic if presented as source parity.
`CombatTask.cs:69–87` accumulates living fighters' action progress during both Idle
and ExecutingTurn, but decrements the one-second turn timer only while Idle.
Delayed actor reset discards progress gained during execution. Other fighters keep
that progress, changing future turn order. Hit RNG occurs after travel; loot RNG
occurs after return. Their ordering relative to other simulation systems changes.
Attack/return effects continue while paused (unscaled), whereas the post-death
0.5-second wait stops with scaled time. Immediate model death currently prevents
showing an alive zero-health victim during the return phase.

A separate coordinated timing slice should introduce explicit phases with both
scaled and unscaled deltas, immutable attack/target context, impact-only rolls,
return/death cleanup events, and cancellation on external kill/merge/scene change.
It also needs a policy for mid-turn save/restore and tests for pause during every
phase, speed changes, exact RNG sequence, simultaneous fights, external removal,
merge cancellation, actor reset timing, and dead defenders not accumulating.
Do not hide these changes inside UI awaits/tweens or defer model actions from
`combat_hit` listeners. This feedback-only slice leaves existing timing unchanged.

## Verification

`bash tools/test_godot.sh res://tests/godot/test_impact_feedback.gd`

50 synthetic checks cover combat style mapping, normal/critical/miss sounds,
critical additive audio, zero damage, icon visibility, explicit source durations,
local offsets, missing private assets, copy isolation, and no change to live
combat snapshot, health or session RNG after repeated descriptor calls.
