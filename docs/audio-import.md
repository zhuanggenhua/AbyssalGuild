# Private source audio adapter

`scripts/ui/audio_feedback.gd` reads AudioId from the imported catalog, then
resolves each numeric `_SFXDataList.audioId` to `_SFXDataList.audioClip.guid` in
the original AudioManager prefab. It does not guess filenames or substitute
missing clips. Configure it with `(catalog, visual_assets)` after adding it to
the tree. `play_event(source_audio_id_name)` returns whether playback started.

Confirmed original call sites (under source Scripts/):

- Card/Components/CardController.cs: CardPick on pickup, CardDrop on drop.
- Card/CardInstance.cs: CardSwipe during the feeding move, Eat when food reaches the character.
- Trading/PackVendor.cs: CashRegister on pack purchase.
- Trading/CardBuyer.cs: Coins on card sale.
- Card/Behaviors/ChestLogic.cs: Coins when opening, Coin during coin output.
- Crafting/Definitions/RecipeDefinition.cs: Pop for recipe completion.
- UI/TextButton.cs and UI/DayTimeUI.cs: Click for button actions.
- Card/VFX/PuffParticle.cs: Puff on the puff effect.
- Combat/CombatTask.cs: AttackMelee/Ranged/Magic and HitMelee/Ranged/Magic
  according to combat type, plus Critical and Miss at those outcomes.

## Source pool, cooldown and gain audit

Static reference: locked CardLoop commit
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`,
`Scripts/Core/AudioManager.cs` (`Awake`, `GetNextSource`, `PlaySFX`) and
`Prefabs/Core/AudioManager.prefab`. No Unity execution is required.

- The prefab configures eight source slots, a 0.05-second per-AudioId cooldown,
  and no pitch randomization. The adapter reads those settings.
- `PlaySFX` records the unscaled request time before looking up the clip. A
  missing AudioId therefore still consumes its cooldown; a rejected repeat
  neither refreshes that timestamp nor advances the round-robin source index.
  The adapter uses monotonic elapsed time, unaffected by gameplay time scaling.
- Unity `PlayOneShot` does not stop earlier sounds when a source slot wraps.
  The adapter now preserves that overlap for both equal and different clips.
  A busy slot keeps its current player and starts a temporary child player,
  freed on completion. Idle base players are reused. Unlike Unity's internal
  voices, Godot overflow voices allocate nodes, but no fixed per-slot voice
  count is introduced and wrapping no longer steals or replaces a sound.
- If pitch randomization is enabled, the source 0.95–1.05 pitch is applied to
  the reused logical slot and its already-playing voices. Other slots keep
  their pitch. This matches changing pitch on the pooled Unity AudioSource.
- `set_user_gains` applies app-local SFX gain to every live voice and composes
  BGM gain with the source's 0.3 clip gain exactly once. It does not change the
  app master bus or host settings. Persistence and option controls are described
  in `options-ui.md`; the Unity mixer asset itself is not recreated.
- Reconfiguration stops and releases every voice, resets cooldown/cache/index
  state and copies source settings without mutating the imported catalog.
  User gains survive reconfiguration. Leaving the tree stops all voices.

Playback remains 2D. Optional positional playback and interrupt-BGM behavior
are not ported; the audited source call sites above use the default arguments.
Platform mixing, voice virtualization, allocation cost and audible quality are
not certified as identical by these structural tests.

`play_music()` resolves `_BGMClip` and `_defaultMusicVolume`. KingsFeast.wav is
now present in the strict private import: stereo 44.1 kHz, 130.168 seconds,
source volume 0.3. The positive playback/stream-length test passes both with
the actual import cache and the isolated buffer decoder. If absent in another
licensed copy, music returns false and stays silent.
Do not add unlicensed replacement music. Audio files remain private ignored
assets. No sounds are played unless the caller explicitly wires their event.

`test_audio_feedback.gd` checks synthetic event mapping, per-event cooldown,
failed-lookup cooldown, round-robin overlap with distinct and repeated clips,
slot-wide pitch, live user gains, one-time BGM gain composition, natural voice
cleanup, repeated configuration and tree exit. With the private import present,
all 18 event WAVs decode and start concurrently across eight logical slots, and
the source music starts with its existing user gain. These are structural,
headless playback checks, not listening or perceived-volume validation.

Run the focused checks with:

```sh
bash tools/test_godot.sh res://tests/godot/test_audio_feedback.gd
bash tools/test_godot.sh res://tests/godot/test_options_ui.gd
```

The first command always runs synthetic checks and reports a skip if private
imports are absent. The options integration check requires imported source data.
