# Godot session save format, version 1

`save_codec.gd` implements a new Godot-native JSON format. It is **not a Unity save importer**. Static reference: CardLoop commit `a11a89b04cea8370476f2559b639bb9b4cbc08d8`, `Assets/StackCraft/Scripts/SaveSystem/GameData.cs`, `SaveSystem.cs`, and `Core/GameDirector.cs`. No original source was copied and Unity was not launched.

## API and integration

Preload `res://scripts/model/save_codec.gd`, then call:

- `capture(session)`: detached JSON-compatible dictionary.
- `restore(session, snapshot)`: validate, stage, then commit. Returns `{ok: true}` or `{ok: false, error: String}`.
- `save_file(session, path = "user://session.json")`: returns `ok`, plus `path` on success.
- `load_file(session, path = "user://session.json")`: returns `ok`, resolved `path`, and `recovered` when a backup was used.

Configure the session/catalog first. Do not call `start_new_game()` after restore. Show errors and backup-recovery status to the player; do not replace failed loads with a new game or overwrite their files automatically. Save/load calls are synchronous and assume one writer per path. Call at frame boundaries rather than from an in-progress gameplay callback. Use separate caller-selected paths for separate slots; the codec does not enumerate or delete slots.

Integrated session properties `equipment`, `combat`, `world` and `ai` must offer `save_state()`, `stage_state(raw, staged_cards)`, `apply_state(staged)` and `reset()`. Staging must return `ok`, `error` on failure, and an `unstacked` array accounting for its stackless cards on success. The codec rejects overlaps with stacks/other helpers. Missing subsystem fields reset that helper on successful load, allowing earlier v1 saves to load without stale subsystem state. Helpers apply in equipment, combat, world, AI order: world application clears production timers, so AI must restore those timers afterward. The configured scene must match the snapshot; Campaign prepares destination scene helpers before restoring. Saved subsystem data is rejected if its helper is unavailable.

## Persisted state

The envelope has `format: "abyssal-guild-session"`, `version: 1`, and `session`:

- Clock/preferences: day, elapsed time, day duration, phase, pause, speed, scene name and friendly mode.
- Cards: stable instance ID, current/base definition GUIDs, stack ID, uses remaining, health, nutrition, stored coins, and 2D position.
- Stacks: stable ID, bottom-to-top card IDs, position, recipe GUID, craft progress and pause.
- Progress: discovered recipe IDs, vendor installment amounts, completed quest IDs and active quest counters through QuestTracker's snapshot API.
- Determinism: next instance ID and RNG seed/state.
- Equipment/combat helper snapshots, including their persistent references and active state. Transient drag state is intentionally not persisted.
- World helper snapshot: scene, completed encounters and processed encounter days.
- AI helper snapshot: configured scene and one record per live imported CardAI prefab, recording running status, movement wait and (for running nonaggressive producers) production wait. These native checkpoints preserve exact continuation rather than recreating Unity coroutines.

RNG values are signed decimal **strings**, not JSON numbers: JSON's float representation cannot preserve all 64-bit RNG states. Seed is restored before state. Other integral values are validated as exact integers within JSON's safe integer range. IDs are positive; stackless card stack ID is -1; durability uses may be negative where runtime semantics permit; remaining counters are nonnegative. Full-precision JSON float encoding is used.

Generated `Recipe:<id>` cards are reconstructed from the current audited catalog, not arbitrary serialized code or definitions. Static definitions and scene quest topology must be available in the configured catalog. Unknown card/recipe/active quest references fail. Unknown completed quest IDs are retained, matching existing QuestTracker behavior. `QuestProgress` is informational and recalculated by the tracker; active quests are restored without reevaluation. The tracker may emit activation notifications after the complete session has been committed; the session emits one `changed` notification. Old card/stack object references must be reacquired from the restored ID maps.

## Validation and recovery

Restore validates types, finite numeric values, required fields, catalog references, unique IDs, next-ID monotonicity, nonempty stacks, exact single membership and quest duplicates before modifying any live model or catalog. Failed validation emits no session change and leaves the live state intact. Reads are bounded to 8 MiB; collection counts are bounded to 100,000. Unsupported envelope versions fail explicitly; no implicit migration is attempted. Additional unknown fields are currently ignored, so future required subsystem additions should introduce explicit validation and bump the version when necessary.

Writes use a same-directory `.tmp`, flush/close, then reread and validate. If a primary exists and validates, it is copied to `.bak.tmp` and renamed to `.bak`. A malformed primary never overwrites a healthy backup. The new temporary is renamed over the primary only after these steps succeed. Any error is returned instead of deleting the current primary. Loading tries the primary first and then the backup; it never auto-promotes `.tmp`, and it does not rewrite a recovered file. Temporary files may remain after failures and are overwritten by the next save attempt.

Same-filesystem rename provides atomic replacement on supported platforms; Godot does not expose a portable directory fsync here, so this is **not a guarantee against all power-loss/storage failures**. If replacement is unsupported or denied, the operation fails and leaves existing files available. Linux headless replacement/backup paths are tested; Windows behavior and real power-loss scenarios are not tested. Concurrent writes to the same path are unsupported.

## Scope relative to Unity

Unity's GameData includes multiple saved scenes, slot metadata, gameplay preferences, discovered/seen items and completed encounters. Its SceneData contains stacks, equipment, combats, quests, vendors and time. This format persists the implemented Godot session, not every original GameData concept. World/encounter state is now included in the session helper snapshot. The separate `campaign.gd` envelope (`abyssal-guild-campaign`) manages multiple scene snapshots and slot metadata; use its save/load API to retain an entire campaign rather than saving only the current session. The original writes directly to JSON and records a save timestamp; this codec deliberately adds staged validation, backups and RNG continuity. No real Unity save sample has been tested, so byte/schema compatibility and import migration remain unverified.

## Verification

Run `godot --headless --path . --script res://tests/godot/test_save_codec.gd` with writable Godot user/cache directories. Tests use a synthetic catalog and do not require redistribution of template data. They cover JSON round trips, stack order/craft state, recipe cards, partial packs/vendor payments, quests, all phases, exact RNG continuation, malformed states, no mutation/signals on failure, three sequential writes, backup replacement/recovery, corrupt-primary preservation of backup, failed reads and unwritable targets. Helper subsystem tests are additionally required for their schema and invariants.

Combined subsystem verification: 534 save-codec assertions passed on Godot 4.6.3, including a class-changed character with two equipped items inside an active battle; exact helper state/RNG JSON and disk round trips; malformed helper scalars; duplicate items/fighters; missing-helper orphan rejection; and loading an earlier base-only v1 snapshot over a live battle. Combat timers/progress may legitimately be negative after large time steps or stat modifiers, so those fields require finite numbers rather than an invented nonnegative restriction. The separate combat/equipment suite also passed (60 checks at this checkpoint). UI save/continue integration is reviewed separately in the board UI tests.


## AI checkpoint validation and legacy behavior

A native AI checkpoint must contain every live AI-enabled card exactly once, with imported prefab mapping and configured scene checked. Movement/production waits must be finite nonnegative numbers; a running producer must have its production wait, while stopped/aggressive/nonproducer agents must not. An agent cannot be running when its card belongs to staged combat. Failed checks preserve cards, world timers, AI state and RNG and emit no session-change signal. Capture and restore do not consume RNG or restart waits.

For an earlier v1 snapshot with no `ai` field, restore clears AI agents and production timers without drawing randomness. A paused session leaves them absent. The first positive unpaused gameplay tick registers imported AI cards, draws new movement waits and producer waits in model order, then advances those waits by the tick delta. This deliberately restarts missing coroutine state rather than pretending that the old snapshot stored it. Exact continuation is guaranteed for checkpoints containing AI state, not for missing legacy timers. Immediate re-save is supported without advancing the simulation: capture emits a stopped pending-restart record (`running: false`, `move_timer: 0`) for each eligible card not yet registered, with no invented production wait. This normalization does not mutate live agents/timers or consume RNG. Loading that checkpoint keeps the agent stopped until the first unpaused tick, preserving the same startup draws.

AI checkpoint verification uses synthetic imported-prefab mapping, including immediate paused legacy re-save and subsequent identical next-tick behavior. Coverage includes exact movement/production/RNG next-tick continuation, world-before-AI application, stopped combat AI restoration, running-in-combat rejection without mutation, malformed/duplicate/missing records and explicit legacy paused/unpaused restart behavior.

## Combat placement checkpoint

A combat task may include `layout: {center: [x, z], cell: [width, depth]}`. Only the battle center and initial cell spacing are persisted. Runtime layout configuration, derived size and fighter positions are intentionally excluded; the board adapter reconstructs these using the current imported scene configuration and the saved center/cell. Restored metadata uses `Vector2` values. The adapter must preserve saved spacing when participants join or leave rather than replacing it with current fighter dimensions.

The serialized layout must contain exactly these two keys. Both values must be two-element numeric arrays with finite axes bounded to absolute value `1e20`, matching the existing card-coordinate cap. Cell axes must be positive and remain positive when converted to the engine's Vector2 representation. Invalid layout shapes, extra fields, strings, booleans, nonfinite values, excessive coordinates and nonpositive/underflowed cell axes fail the whole restore before any live-state or RNG change. Saving also leaves runtime layout data untouched.

Legacy tasks without a layout remain without one after restore and re-save; the board initializes their geometry from the current scene when needed. This preserves compatibility without inventing historical placement metadata. The codec suite now passes 534 checks, including midcombat disk round trips and transactional malformed-layout rejection. Visual placement reconstruction is checked separately by the combat-layout/board suites.


## Active day-cycle checkpoints

The optional `cycle` helper is staged after cards, stacks, world and phase are
validated. It persists ordered eligibility queues, current character/food, hunger,
real-time wait/stage, motion and focus poses, and pending encounter selection/spawn
progress. Food stays owned by a registered stack. Capture during a reentrant
effect transition is rejected rather than producing a half-applied snapshot.

Malformed references, stage/phase pairs, consumed/leftover hunger and encounter
progress fail before changing the live campaign. Legacy feeding without a cycle
cursor resumes at `await_feed`; a legacy encounter without a cursor is rejected
rather than replayed. These native checkpoints extend the source format and do
not claim Unity save compatibility. The independent cycle validation suite adds
144 checks, including active and inactive campaign scenes and no-mutation failures.
See [cycle timeline](cycle-timeline.md) for clock and continuation semantics.

## Held-card checkpoints

The live pointer is never serialized. During a hold, capture normalizes an
isolated clone to an ordinary non-reattached release at the registered held pose.
It preserves actual split membership, resumes a valid original recipe at its
elapsed progress, cancels an invalid original, and checks an idle detached tail.
Any recipe RNG/discovery/quest effects occur only in the clone and are captured
there. Repeated capture is deterministic and emits no live signals or mutations.
Reload continues this settled state, not the still-held live interaction. No
spatial attachment, click or terminal action is replayed. Successful restore
clears old transient IDs; validation failure leaves the live hold unchanged.
Reentrant capture inside a half-applied held transition fails explicitly.
See [held-stack lifecycle](held-stack-lifecycle.md) for the contract and tests.
