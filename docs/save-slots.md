# Native save slots and title workflow

`save_slots.gd` provides inventory and persistence over the Campaign codec. `scripts/ui/board.gd` now connects it to the title picker, New, Continue, explicit Save, checkpoints and confirmed game-over return. Merely launching the title lists slots without rewriting, adopting or deleting existing files.

## Source audit

Static reference: CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`, within `Assets/StackCraft/Scripts`: `Core/GameDirector.cs`, `Core/DayCycleManager.cs`, `SaveSystem/GameData.cs`, `SaveSystem/SaveSystem.cs`, `UI/Title/TitleScreen.cs`, `SavedGamesUI.cs`, and `SavedGameSlot.cs`. No `DataManager` file exists in the restored Scripts tree; GameDirector owns these operations.

- GameDirector startup reads all valid JSON games through SaveSystem. The original reader logs/skips invalid JSON. NewGame chooses the lowest unused positive SlotNumber from loaded games. SaveGame collects manager state, records LastSaved and writes `SaveSlotNNN.json` (minimum three digits, not a three-digit limit).
- The title slot label shows slot number, current scene, quest percentage and LastSaved. It does **not** show day. Native day metadata below is an added presentation option derived from the active scene snapshot.
- DayCycleManager saves after the player confirms Start Day and StartNewDay runs. Game-over deletion is deferred until the player clicks Return to Title on its modal, not immediately when the last character dies.
- BackToTitle and InitiateTravel call SaveGame. OnApplicationQuit saves outside Title except while DayCycleManager.IsEndingCycle. GameOver deletes the current save and returns to Title. Title deletion and Clear Games use confirmation dialogs.
- This helper deliberately preserves evidence of corrupt files instead of making their numbers available for overwrite, and uses recoverable removal rather than the original irreversible delete. The board adapter implements the checkpoint and confirmation behavior documented below.

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

## Title and checkpoint integration

- New creates a fresh candidate session and commits the lowest available slot before replacing the live game. This initial immediate checkpoint is a deliberate safety addition to the source flow. Failed allocation leaves the current session intact.
- The title picker shows slot number, current scene, quest percentage, file modification time in UTC, and backup-recovery status. The timestamp is filesystem metadata, not Unity LastSaved. Invalid slots stay visible with errors and cannot be continued; their artifacts remain reserved.
- Continue validates the selected slot into a separate candidate before switching. Loading a different slot replaces its collection/discovery state; it does not union progress from the previously active slot.
- Explicit Save and ordinary Return to Title write only the active valid slot. Failed writes keep the live session open and display an error. Corrupt-only slots are not silently overwritten.
- Confirmed Start Day first calls `start_day`, then checkpoints the new day. A failure preserves the advanced live day and reports that Save must be retried; it does not pretend to have persisted or revert the day.
- `campaign.before_travel` checkpoints the current source session only after the travel candidate validates. Save failure aborts before live travel mutation. The native departure checkpoint contains the unchanged pre-travel source; the original consumes before SaveGame with deferred-destruction ambiguity. After scene change the board checkpoints the destination and the frozen source-scene snapshot. A destination-write failure keeps the live destination open with a visible warning; the source checkpoint remains available.
- Application close while playing checkpoints first and refuses to close on save failure. During feeding, selling, ready or game-over, quit skips autosave like source IsEndingCycle. The adapter adds a warning confirmation before quitting during those phases so the user knows only the previous checkpoint is retained. Closing from the title writes nothing.
- Game-over detection does not archive or overwrite the last checkpoint. The Return to Title action asks for confirmation. Acceptance moves only the active slot and its backup/temp artifacts to the recoverable `.deleted` archive. Failure keeps the ended live game open. Success reports the archive path. There is no permanent purge.

## Legacy adoption

When `user://session.json`, `user://campaign.json`, or their backup exists, the title offers **Copy legacy save into a new slot**. These are earlier native formats, not Unity saves. No adoption happens merely by opening the app or refreshing the picker.

The explicit action loads the chosen legacy primary/backup into an isolated configured candidate. Only a valid candidate is saved into the next unoccupied slot, and only successful creation switches the live game. Original and backup bytes stay unchanged, including after failed adoption. Success reports the new slot and any backup recovery. A corrupt legacy file cannot create an empty replacement. Repeating the explicit action creates another copy rather than overwriting the previous copy.

## Phase input policy

Card dragging, sale and trade are allowed while playing or selling, and blocked during feeding, ready and game-over. A manual pause does not disable playing-phase interactions. Inspection and navigation remain available. Explicit Save is available before game-over; game-over Save instead explains the confirmed archive flow. This adapter still lacks original animated/modal presentation and original title styling.

## Verification and remaining gaps

`tests/godot/test_save_slots.gd` uses a unique temporary `user://test-save-slots-…` directory and a synthetic catalog. It checks lowest-free allocation, corruption and reservations, byte preservation, metadata and nonmutating enumeration, backup recovery, filename/header mismatch, save failures, recoverable deletion, reuse, ignored legacy files and invalid roots. Cleanup is restricted to that test-owned directory. No existing user slot or legacy save is touched.

`tests/godot/test_slot_ui.gd` exercises title selection, safe New, independent slot progress, Start Day/quit/travel checkpoints, phase locks, failed saves, legacy preservation and confirmed game-over archive using unique test-owned local directories. Existing UI smoke and combat/layout suites use their own slot directories too. Normal title-slot deletion, delete-all, archive restore UI, and local-time timestamp formatting remain unimplemented. This helper is not evidence of full title/save-slot parity or Unity-save compatibility. Linux Godot headless tests do not prove Windows rename or real power-loss behavior.
