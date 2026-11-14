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
combat restoration, expanded boards, custom pack attachment, nested equipment or
other unaccounted-for unstacked records. No partial plan is committed. Expanded
board Awake/Start timing, combat listeners, equipment replacement transforms and
engine-native animations remain separate work.

Travel remains unchanged. Source spawns incoming travelers before destination
restore/defaults and restores each traveler's equipment immediately. The current
campaign stages those differently, and new-scene random draw order also differs.
The planner can test fixed-coordinate travel registration order, but it is not
wired into production travel and does not silently reorder RNG. Equipment visual
noise's Unity random draws are likewise not introduced by this geometry patch.

## Verification

- `test_source_restore_layout.gd`: source-free planner, order, identity, stale
  commit and unsupported graph/metadata guards.
- `test_source_restore_board.gd`: actual production Continue/save/re-read calls
  in headless Godot, Main/Island single/multiple cards and three-slot equipment,
  empty/invalid slots, unchanged nongeometry state and input bytes, no extra
  per-frame resolve, whole-group metadata fallback. Optional read-only real
  saves are copied to isolated private slots before exercising the same path.
- Both tests run in the aggregate suites. Private source-equation oracles and
  actual gameplay saves remain outside the public repository.

Headless scene methods and editor-hosted exported PCK tests are not native GUI,
Unity execution, physical-GPU or complete one-to-one acceptance.
