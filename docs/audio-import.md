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

The original prefab configures an eight-player pool, 0.05-second per-event
cooldown and no pitch randomization. The adapter reads those settings; if source
randomization is enabled it uses the source 0.95–1.05 pitch range. It uses 2D
playback. Unity mixer routing, saved volume preferences, positional playback
and interrupt-BGM behavior are not ported. The pool steals a player if full;
Unity's overlapping PlayOneShot behavior is not reproduced exactly.

`play_music()` resolves `_BGMClip` and `_defaultMusicVolume`. KingsFeast.wav is
missing in this restored snapshot, so music returns false and stays silent.
Do not add unlicensed replacement music. Audio files remain private ignored
assets. No sounds are played unless the caller explicitly wires their event.

`test_audio_feedback.gd` checks synthetic event mapping, missing behavior,
cooldown and available restored audio: all 18 source event WAVs decode. These
are structural/headless tests, not listening or perceived-volume validation.
