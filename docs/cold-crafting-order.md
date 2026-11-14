# Cold Continue: source crafting task re-registration

This is independent of cold geometry. It does not enable active-craft placement,
combat/day-end restoration, or travel. The general native codec continues to
preserve its explicit activation history for clones and non-cold operations.

## Proven source distinction

The locked template (`a11a89b04cea8370476f2559b639bb9b4cbc08d8`) saves
`StackData.ActiveCraft` with only recipe ID and progress. `SceneData.SaveStacks`
keeps registered stack order. `CardManager.HandleSceneDataReady` restores these
rows sequentially; at each stack's end, `RestoreCraftingTask` calls
`StartCraftingTask` (append), then assigns saved progress. The newly created
manager therefore has **saved stack order**, not the previous session's task
activation history. Its Update visits that list newest first.

Before this correction, two actual base recipes registered as Wood then Timber,
but activated as Timber then Wood, resumed after native cold load as Timber then
Wooden Stick. Re-registering tasks in saved row order yields Wooden Stick then
Timber. Aligned registration/activation controls agree. This is a model/API
counterexample with locked recipe data, not a Unity run or a new natural game.

The source order rule is general. The implementation does **not** whitelist those
two example recipes: they are executable evidence, not source rules. Admission
classifies the original base `RecipeDefinition` by locked catalog provenance,
source metadata and the original script identity. Special subclasses, including
travel, remain out of scope. Metadata is supplied by the existing verified
private-data importer, not independently attested by this helper.

## Narrow production boundary

Only a successful actual `Board._continue_game` calls `SourceColdCrafting.apply`
before entering gameplay. It stages the entire order first and then rebinds the
existing helper's transient task identities. It changes no timer, recipe, task
pause, card/stack/equipment ID, position, quest, RNG, event or saved format. An
invalid/empty slot never reaches it. Ordinary entry, legacy-copy adoption,
travel, codec restore/staging and callback-created tasks do not call it.

The current admission requires Main/Island, playing with idle cycle, before the
day deadline, no held cards or pending travel, and no combat. **All** active tasks
must be verified base recipes, already discovered, unpaused and incomplete, with
finite positive duration. A missing/unverified/mixed special definition rejects
the whole correction, retaining native history. A restored source task can
publish discovery while being registered, so undiscovered recipes also stay on
the prior path rather than inventing a callback here.

The source uses float32 progress/duration. Admission additionally checks their
float32 projection for completion; for example native `9.99999999 < 10` rounds to
source `10 == 10` and must reject. This is a guard only: neither the original
native number nor normal accumulation/comparison is quantized or modified.
The day clock receives the same float32 deadline guard, since source currentTime
and dayDuration are also floats.

This guard matters because the original manager executes an already-complete
task even if a preceding callback canceled it. The existing native generation
safety check skips stale tasks instead. For incomplete tasks, cancellation skips
progress, replacement/new activation appends beyond the old reverse cursor, and
no newly appended task receives the old frame's delta. A separate source-list
oracle tests that narrow cursor behavior. No change is made to the existing
scheduler's intentional reentrancy/stale-task protection.

## Existing native save compatibility

The native version-1 `crafting.activation_order` field remains valid and mandatory
when present. The generic codec retains it exactly. Older files without it still
use their existing row-order fallback; malformed fields still fail validation.
A supported cold Continue now intentionally establishes source cold-entry order.
A subsequent ordinary Save persists that new continuation, while the input slot
is never rewritten just by loading. Remaining incomplete native task-pause,
completed, combat, cycle and special-recipe cases retain the earlier policy.

This is an explicit distinction between native continuation and source scene
reconstruction, not a save-format migration. It must not be implemented by
changing `SaveCodec.restore`, which is also used by private transaction clones,
held-state normalization and travel. Nor should later view refreshes rerun it.

## Verification and limits

- Public source-shaped tests: admission/refusal and atomicity, exact saved fields,
  native/legacy codec isolation, float32 boundary, independent reverse-list
  cancellation/replacement/new-task oracle, and the excluded complete+cancel
  mismatch.
- Private locked-data actual Board Continue: Main/Island, opposite task history,
  Save/Continue again, exact non-order state, unchanged input bytes, inactive
  geometry guard, non-cold entry, empty/corrupt slots, combat/day-end/task-paused
  and near-complete fallback.
- Existing source crafting/quest/travel and full regressions remain required.

The classification establishes **cold task registration order only**, not every
ordinary recipe's subsequent output/AI/neighbor attachment, Unity frame timing,
PhysX, or future RNG equality. Actual GUI acceptance, if performed separately,
must identify its exact build rather than treating headless Continue as GUI.
