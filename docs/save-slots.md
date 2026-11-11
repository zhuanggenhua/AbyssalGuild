# Native save-slot helper (not yet wired to UI)

`save_slots.gd` is a standalone inventory and persistence adapter over the existing Campaign codec. It does not change the title screen, application-quit handling, game-over handling or campaign gameplay. No real user save is moved, adopted or deleted by adding this helper.

## Source audit

Static reference: CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`, within `Assets/StackCraft/Scripts`: `Core/GameDirector.cs`, `Core/DayCycleManager.cs`, `SaveSystem/GameData.cs`, `SaveSystem/SaveSystem.cs`, `UI/Title/TitleScreen.cs`, `SavedGamesUI.cs`, and `SavedGameSlot.cs`. No `DataManager` file exists in the restored Scripts tree; GameDirector owns these operations.

- GameDirector startup reads all valid JSON games through SaveSystem. The original reader logs/skips invalid JSON. NewGame chooses the lowest unused positive SlotNumber from loaded games. SaveGame collects manager state, records LastSaved and writes `SaveSlotNNN.json` (minimum three digits, not a three-digit limit).
- The title slot label shows slot number, current scene, quest percentage and LastSaved. It does **not** show day. Native day metadata below is an added presentation option derived from the active scene snapshot.
- DayCycleManager saves after the player confirms Start Day and StartNewDay runs. Game-over deletion is deferred until the player clicks Return to Title on its modal, not immediately when the last character dies.
- BackToTitle and InitiateTravel call SaveGame. OnApplicationQuit saves outside Title except while DayCycleManager.IsEndingCycle. GameOver deletes the current save and returns to Title. Title deletion and Clear Games use confirmation dialogs.
- This helper deliberately preserves evidence of corrupt files instead of making their numbers available for overwrite, and uses recoverable removal rather than the original irreversible delete. Original autosave triggers and game-over UI transitions are **not implemented here**.

## API

Instantiate and call `configure(campaign, root = "user://slots")`. Root is a caller-controlled local directory, not a user-entered filename. The campaign must already have a catalog and configured scene. Operations are synchronous. Use a single writer per store; the create reservation protects competing allocation calls, but this is not a general multi-process locking protocol.

- `slot_path(slot)` returns canonical `SaveSlot%03d.json` under root, or an empty string for IDs outside 1…999999. Numeric IDs prevent path traversal.
- `list_slots()` returns `{ok, slots, ignored}`. Slot entries contain ID, canonical path, validity, selected primary/backup path when valid, recovery status, artifacts and diagnostic errors. Valid entries additionally expose current scene, day, quest percentage and `modified_unix` from the selected file's modification time. This is **filesystem metadata, not Unity LastSaved**. Listing validates all saved scenes using Campaign staging and does not mutate the live game or its RNG.
- `next_slot()` returns an advisory lowest free ID/path. Any recognized primary, backup, temp, backup-temp or reservation occupies its number, even when corrupt. Unknown filenames are reported in `ignored` and never overwritten or deleted. The reserved `.deleted` archive directory is not a playable slot.
- `create_slot()` rechecks allocation, acquires a reservation directory and saves the current campaign into a fresh number through Campaign's validated atomic writer. Success updates campaign.slot_number and returns slot/path. Failure restores the previous campaign slot number; any interrupted temp remains occupied, and existing save artifacts are not overwritten. It does not start a new game: initialize a fresh session before calling when that is the intended action.
- `save_slot(slot)` requires the campaign's slot number to match and an existing valid primary or backup. It delegates to Campaign's atomic save/backup implementation. A primary belonging to a different slot is explicitly rejected so it cannot displace a healthy matching backup. Call create_slot for new storage.
- `load_slot(slot)` validates filename/header identity and chooses a valid primary before backup, then delegates loading to Campaign. Recovery is reported and does not rewrite the corrupt primary. A corrupt-only slot is returned as a failure without resetting the live game. An unrelated campaign cannot be loaded through a mismatched filename.
- `delete_slot(slot)` is an **explicit logical deletion** for future user-approved deletion/game-over flows. It moves that slot's primary, backup and temporary artifacts into a unique same-store `.deleted` directory, reports its path, and leaves unrelated files alone. No permanent purge exists. On partial rename failure it attempts rollback and reports any rollback failures. Busy reservations and unexpected directory objects are refused. Successful removal makes the number reusable and removes backups from automatic recovery, preventing resurrection. Recovery/archive management UI is not yet implemented.

## Deliberate recovery rules

A backup-only slot remains loadable. A malformed primary plus healthy backup appears as valid/recovered with the primary diagnostic retained. Temporary files are never treated as committed games and never auto-promoted; temporary-only entries reserve their numbers for explicit review. Enumeration does not rewrite, delete or repair any artifact. Campaign's existing flush, verification, backup and rename behavior applies; see `save-format.md` for the power-loss and platform limitations.

## Legacy adoption plan

Do not automatically scan/adopt or remove `user://session.json`, `user://session.json.bak`, or the earlier `user://campaign.json`. They are separate native single-save formats, not Unity data. The UI should offer explicit adoption when those files exist: load the chosen file through Campaign into an isolated configured candidate session (Campaign already wraps native single-session envelopes), show recovery/errors, then use a separate slot helper on that candidate to create the next unoccupied campaign slot. Only switch the live session after the new save succeeds. Keep the original and backup unchanged; report the new slot to the user. This adoption workflow is a documented integration plan, **not an implemented slot-helper action**. A corrupt legacy file must never cause an empty new game to be saved as its replacement.

## Verification and remaining gaps

`tests/godot/test_save_slots.gd` uses a unique temporary `user://test-save-slots-…` directory and a synthetic catalog. It checks lowest-free allocation, corruption and reservations, byte preservation, metadata and nonmutating enumeration, backup recovery, filename/header mismatch, save failures, recoverable deletion, reuse, ignored legacy files and invalid roots. Cleanup is restricted to that test-owned directory. No existing user slot or legacy save is touched.

Slot selection, New Game integration, modal confirmations, Start Day/quit/title/travel autosave timing, game-over removal, delete-all UI, archive recovery UI, and timestamp localization remain unwired. This helper is not evidence of full title/save-slot parity or Unity-save compatibility. Linux Godot headless tests do not prove Windows rename or real power-loss behavior.
