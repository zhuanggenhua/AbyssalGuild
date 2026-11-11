# Godot session save format, version 1

`save_codec.gd` implements a new Godot-native JSON format. It is **not a Unity save importer**. Static reference: CardLoop commit `a11a89b04cea8370476f2559b639bb9b4cbc08d8`, `Assets/StackCraft/Scripts/SaveSystem/GameData.cs`, `SaveSystem.cs`, and `Core/GameDirector.cs`. No original source was copied and Unity was not launched.

## API and integration

Preload `res://scripts/model/save_codec.gd`, then call:

- `capture(session)`: detached JSON-compatible dictionary.
- `restore(session, snapshot)`: validate, stage, then commit. Returns `{ok: true}` or `{ok: false, error: String}`.
- `save_file(session, path = "user://session.json")`: returns `ok`, plus `path` on success.
- `load_file(session, path = "user://session.json")`: returns `ok`, resolved `path`, and `recovered` when a backup was used.

Configure the session/catalog first. Do not call `start_new_game()` after restore. Show errors and backup-recovery status to the player; do not replace failed loads with a new game or overwrite their files automatically. Save/load calls are synchronous and assume one writer per path. Call at frame boundaries rather than from an in-progress gameplay callback. Use separate caller-selected paths for separate slots; the codec does not enumerate or delete slots.

No `game_session.gd` changes are needed for the base codec. Optional session properties `equipment` and `combat` must offer `save_state()`, `stage_state(raw, staged_cards)`, `apply_state(staged)` and `reset()`. Staging must return `ok`, `error` on failure, and an `unstacked` array accounting for its stackless cards on success. The codec rejects overlaps with stacks/other helpers. Missing subsystem fields reset that helper on successful load, allowing earlier v1 saves to load without stale combat/equipment. Saved subsystem data is rejected if its helper is unavailable.

## Persisted state

The envelope has `format: "abyssal-guild-session"`, `version: 1`, and `session`:

- Clock: day, elapsed time, day duration, phase, pause and speed.
- Cards: stable instance ID, current/base definition GUIDs, stack ID, uses remaining, health, nutrition, stored coins, and 2D position.
- Stacks: stable ID, bottom-to-top card IDs, position, recipe GUID, craft progress and pause.
- Progress: discovered recipe IDs, vendor installment amounts, completed quest IDs and active quest counters through QuestTracker's snapshot API.
- Determinism: next instance ID and RNG seed/state.
- Optional equipment/combat helper snapshots, including their persistent references and active state. Transient drag state is intentionally not persisted.

RNG values are signed decimal **strings**, not JSON numbers: JSON's float representation cannot preserve all 64-bit RNG states. Seed is restored before state. Other integral values are validated as exact nonnegative integers within JSON's safe integer range (IDs are positive, stackless card stack ID is -1). Full-precision JSON float encoding is used.

Generated `Recipe:<id>` cards are reconstructed from the current audited catalog, not arbitrary serialized code or definitions. Static definitions and scene quest topology must be available in the configured catalog. Unknown card/recipe/active quest references fail. Unknown completed quest IDs are retained, matching existing QuestTracker behavior. `QuestProgress` is informational and recalculated by the tracker; active quests are restored without reevaluation. The tracker may emit activation notifications after the complete session has been committed; the session emits one `changed` notification. Old card/stack object references must be reacquired from the restored ID maps.

## Validation and recovery

Restore validates types, finite numeric values, required fields, catalog references, unique IDs, next-ID monotonicity, nonempty stacks, exact single membership and quest duplicates before modifying any live model or catalog. Failed validation emits no session change and leaves the live state intact. Reads are bounded to 8 MiB; collection counts are bounded to 100,000. Unsupported envelope versions fail explicitly; no implicit migration is attempted. Additional unknown fields are currently ignored, so future required subsystem additions should introduce explicit validation and bump the version when necessary.

Writes use a same-directory `.tmp`, flush/close, then reread and validate. If a primary exists and validates, it is copied to `.bak.tmp` and renamed to `.bak`. A malformed primary never overwrites a healthy backup. The new temporary is renamed over the primary only after these steps succeed. Any error is returned instead of deleting the current primary. Loading tries the primary first and then the backup; it never auto-promotes `.tmp`, and it does not rewrite a recovered file. Temporary files may remain after failures and are overwritten by the next save attempt.

Same-filesystem rename provides atomic replacement on supported platforms; Godot does not expose a portable directory fsync here, so this is **not a guarantee against all power-loss/storage failures**. If replacement is unsupported or denied, the operation fails and leaves existing files available. Linux headless replacement/backup paths are tested; Windows behavior and real power-loss scenarios are not tested. Concurrent writes to the same path are unsupported.

## Scope relative to Unity

Unity's GameData includes multiple saved scenes, slot metadata, gameplay preferences, discovered/seen items and completed encounters. Its SceneData contains stacks, equipment, combats, quests, vendors and time. This format persists the implemented Godot session, not every original GameData concept. Multi-scene travel/world state and encounter persistence need their own model and versioned serialization extension. The original writes directly to JSON and records a save timestamp; this codec deliberately adds staged validation, backups and RNG continuity. No real Unity save sample has been tested, so byte/schema compatibility and import migration remain unverified.

## Verification

Run `godot --headless --path . --script res://tests/godot/test_save_codec.gd` with writable Godot user/cache directories. Tests use a synthetic catalog and do not require redistribution of template data. They cover JSON round trips, stack order/craft state, recipe cards, partial packs/vendor payments, quests, all phases, exact RNG continuation, malformed states, no mutation/signals on failure, three sequential writes, backup replacement/recovery, corrupt-primary preservation of backup, failed reads and unwritable targets. Helper subsystem tests are additionally required for their schema and invariants.

Combined subsystem verification: 191 save-codec assertions passed on Godot 4.6.3, including a class-changed character with two equipped items inside an active battle; exact helper state/RNG JSON and disk round trips; malformed helper scalars; duplicate items/fighters; missing-helper orphan rejection; and loading an earlier base-only v1 snapshot over a live battle. Combat timers/progress may legitimately be negative after large time steps or stat modifiers, so those fields require finite numbers rather than an invented nonnegative restriction. The separate combat/equipment suite also passed (58 checks at this checkpoint). UI save/continue integration is reviewed separately in the board UI tests.
