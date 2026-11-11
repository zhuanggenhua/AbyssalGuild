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

The board adapter now uses this descriptor at its `combat_hit` handler.
Capture defender position/transform immediately: a card may be removed by
cleanup or another synchronous event. Place popups under a transient effects
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

## Implemented timing and remaining presentation

The coordinated model timeline is now implemented in `combat-timeline.md`:
travel, impact-only RNG, return and scaled death cleanup are separate phases;
progress, reverse task order, paused real-time travel, cancellation and in-flight
save/restore are tested. `combat-feedback-ui.md` documents the live hookup.
Attack audio occurs at start and hit plus Critical occur at impact. Generated
one-second damage popups survive card deletion, and source stat labels show health.

Jump/projectile presentation, private HitUI images, hurt flash/punch and camera
shake are now connected in `combat-presentation.md` and `combat-sprite-binding.md`.
Puff is still separate work. Adapters use audited explicit source parameters but
retain documented native interpolation/noise/font differences, not GPU acceptance
or DOTween-curve equivalence.
Never introduce gameplay waits from UI tweens or hit listeners; the model owns
its two clocks and saveable phase transitions.

## Verification

`bash tools/test_godot.sh res://tests/godot/test_impact_feedback.gd`

50 synthetic checks cover combat style mapping, normal/critical/miss sounds,
critical additive audio, zero damage, icon visibility, explicit source durations,
local offsets, missing private assets, copy isolation, and no change to live
combat snapshot, health or session RNG after repeated descriptor calls.
