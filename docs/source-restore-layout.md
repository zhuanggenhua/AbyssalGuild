# Source cold-entry registration and target placement

This is a bounded scene-entry correction, not a save-format migration or a claim
that every source restoration branch is implemented.

## Separation of responsibilities

- `SaveCodec.restore` remains pure atomic deserialization. Validation copies,
  inactive campaign scenes and travel staging do not allocate gameplay cards,
  emit events, draw random values or run a presentation solver.
- `source_restore_layout.gd` plans target geometry on a temporary registry and
  validates an explicit commit. It retains existing card/stack identities and
  equipment owners. Its temporary negative labels never become live IDs.
- `source_restore_admission.gd` admits only the verified locked Main/Island cold
  branch. `Board._continue_game` and explicit legacy-copy adoption mark that
  actual cold entry; ordinary `_enter_game` and travel do not.

## Locked source order

At `a11a89`, `CardManager.RestoreStack` creates each saved card in list order.
`CardInstance.Initialize` registers its single-card stack and resolves overlaps
before the caller restores stats and equipment. A normal first-card anchor is
then reset to the saved point. Later cards briefly have independent registered
stacks, are removed from those temporary stacks and appended to the anchor. The
complete normal anchor is reset again at the end. Packs bypass those normal
anchor resets. Every locked pack attaching-category row forbids attachment;
normal restored cards use `RefuseAll`, so these admitted placements do not depend
on Physics hit ordering.

Each supported equipment item is initialized at zero and resolves overlaps
before being equipped. Successful equipment attachment unregisters its temporary
stack without another solver call. Main/Island Character prefabs have the owner
component; Equipment prefabs do not. The admitted graph is therefore depth one,
with unique owner/slot assignments, not an invented recursive equipment restore.

Once the plan is committed, the board initializes its layout signature from the
result. The subsequent view refresh must not add an extra blanket solver pass.
Finite solver iterations and saved-anchor resets can intentionally leave target
overlap. A later explicit load repeats the source entry schedule; ordinary view
frames must not do so.

## Guarded boundaries

The whole cold plan falls back to the previous entry path for missing/unverified
source metadata, unknown scenes, active crafting, ending cycles, held transitions,
combat restoration, unverified expansion metadata, custom pack attachment, nested equipment or
other unaccounted-for unstacked records. No partial plan is committed. Expanded
board branches outside the positive cold-entry contract below, combat listeners, equipment replacement transforms and
engine-native animations remain separate work.

Saved-destination travel uses the separately guarded schedule in
[source-travel-layout.md](source-travel-layout.md). Its separately sealed
live-entry context now admits the same verified positive initial expansion, with
travel-specific lifecycle/provenance guards. Neither path reorders random draws.
New/default destinations remain separate.

## Positive cold-entry expansion

`source_board_expansion.gd` verifies the locked Main/Island prefab and scene
metadata, identity transforms, initial blend weight zero, enabled Board and
renderer, top margin, known positive Warehouse/Yard contributions, and actual
imported FBX base/final vertex bounds. Missing scene dimensions or cache rejects
the entire entry, rather than using the visual fallback rectangle as evidence.
Raw capacity boosts may exceed 100; mesh weight alone is capped at 100.

The source Board Awake caches initial bounds. Unity 6000.5 documents
[sceneLoaded before Start](https://docs.unity.com/zh-cn/engine/6000.5/script-reference/unityengine/scenemanagement/scenemanager/sceneloaded).
Card restoration in OnSceneDataReady therefore resolves against initial bounds.
Board.Start subscribes to stats and reads the snapshot; HandleStatsChanged sets
the positive shape weight and new bounds but calls EnforceBoardLimits only on
shrink. No relative Awake/Start order between objects is assumed here.

The pure entry plan uses base bounds while the presentation retains final
expanded geometry. ApplyTranslation still clamps moved overlap targets;
SetTargetPosition's saved-anchor resets do not. Thus isolated extreme saved
anchors are not blanket-clamped, and expansion adds no post-plan solver pass.
Non-expanded entry remains unchanged. Negative/shrinking, nonzero prefab weight,
new-scene spawning, active crafting/combat/cycle and incomplete metadata remain
outside this branch. A large saved game is not accepted merely because its boost
is now supported: every other admission guard still applies.

## Source-entry performance boundary

The entry-only resolver caches each stack Bounds within one resolver invocation.
Only a translation changes that rectangle; it is recomputed immediately using
the unchanged formula. Pair registration order, clamping, tie/sign rules,
iterations and every per-card restoration call are retained. No scale threshold,
pair skipping, spatial reordering or change to the global drag/combat solver is
introduced. Exact result/iteration and input-immutability regressions compare
this cache with the uncached solver; it is not a no-stall/native performance claim.

## Verification

- `test_source_restore_layout.gd`: source-free planner, order, identity, stale
  commit and unsupported graph/metadata guards.
- `test_source_restore_board.gd`: actual production Continue/save/re-read calls
  in headless Godot, Main/Island single/multiple cards and three-slot equipment,
  empty/invalid slots, unchanged nongeometry state and input bytes, no extra
  per-frame resolve, whole-group metadata fallback. Optional read-only real
  saves are copied to isolated private slots before exercising the same path.
- `test_source_board_expansion.gd`: actual cached FBX, Main/Island boosts 4/36/100/104, extreme saved anchors, Continue/refresh, and whole-group fallback. The source-only runner explicitly skips missing caches; the fresh imported runner requires completion.
- These tests run in the aggregate suites. Private source-equation oracles and
  actual gameplay saves remain outside the public repository.

Headless scene methods and editor-hosted exported PCK tests are not native GUI,
Unity execution, physical-GPU or complete one-to-one acceptance.
