# Crafting task activation and checkpoint order

This slice independently implements the task-list ordering established by static
inspection of the locked StackCraft reference. It does not run Unity or copy its
source or licensed content into this repository.

## Source contract

The relevant reference is `Scripts/Crafting/CraftingManager.cs`, particularly
`StartCraftingTask`, `Update`, `PerformCraftingAction`, task pause/resume/stop and
validation, plus `Scripts/Crafting/CraftingTask.cs` and the card-stack removal and
held-stack interaction call sites.

- Activation appends a task independently of when its stack was registered.
- The manager starts at the last task existing at the start of its update and
  walks backward. A newly appended task does not receive that frame's delta.
- This includes auto-repeat, reselection after cancellation, and recipes started
  by a result card attaching to another stack during completion callbacks.
- Pause/resume retains the task's original activation position and elapsed time.
  Cancellation removes that identity. A replacement on the same stack is new.
- A task adds delta only when it is neither paused nor already complete. The
  manager still executes an already-complete task while its task pause is set.
  Unity's update continues at zero scaled delta during a global time pause.
- Completion runs the selected action and its existing effects before repeat
  selection. Repeat appends a new task; it receives neither leftover frame time
  nor a second update that frame. Existing recipe-selection RNG draws stay in
  that completion order.

The native `CraftingOrder` helper owns activation order, not recipes, ingredients,
RNG, or the gameplay clock. `Stack.craft_generation` invalidates old task identities
on cancellation/replacement. Each update snapshots task identities, verifies that
its stack is still registered, and visits that snapshot newest first. This guards
against stale stack IDs and replacements created during callbacks. Successful
travel returns immediately from the old-scene cursor, leaving destination time
and destination tasks untouched until a later tick. It intentionally does not
reproduce unsafe stale-list/reentrant iteration failures in the original manager.

`Session.tick_paused` is shared by manual/global pause, non-playing cycle phases,
and the board's external menu/vendor-reveal pause. It advances existing real-time
combat/cycle waits and checks completed crafts with zero scaled delta. Incomplete
crafting, elapsed day time and source whole-stack/partial-tail hold behavior are
unchanged. The headless paused-completion test uses an explicitly constructed
completed-save edge fixture; all 90 imported recipe durations are positive.

## Native version-1 saves

New native saves add this session field:

```json
"crafting": {"activation_order": [12, 4, 27]}
```

The list contains stack IDs in oldest-to-newest **task activation** order, not
completion order. Recipe, progress and task pause remain in the existing stack
rows. Generation counters are live-only implementation identities and are not
serialized. Restore rebuilds independent identities without recipe reselection,
RNG draws, discovery or completion callbacks. Capture is read-only, including
when called by the departure checkpoint callback.

With the field present, staging requires every nonempty stack recipe exactly
once and rejects malformed, fractional, duplicate, missing, unknown and inactive
references before any live mutation. It does not rematch ingredients or infer
inactivity from a zero timer. A zero-progress task and a deliberately incomplete,
paused original during a partial hold are legitimate task states. Held-checkpoint
normalization uses the same ordered state in its isolated clone, then follows the
existing ordinary-release policy.

**Earlier native v1 saves without `crafting` remain supported.** They did not save
activation history. Their saved stack-row order becomes the deterministic fallback
activation order, so those tasks update in reverse saved row order. This cannot
recover their historical activation order and is not presented as doing so. Once
saved again, the explicit order preserves continuation. A present but malformed
field is rejected rather than silently replaced with fallback order. Campaign
active and inactive scenes independently carry this field through `SaveCodec`.

## Verification

```sh
bash tools/test_godot.sh res://tests/godot/test_crafting_order.gd
bash tools/test_godot.sh res://tests/godot/test_crafting_order_source.gd
bash tools/test_godot.sh res://tests/godot/test_crafting_order_board.gd
```

- Synthetic model/helper coverage includes different stack/activation orders,
  cancellation/replacement, callbacks, task/global/external pauses, exact weighted
  repeat draw assignment over six cycles, save validation/continuation, legacy
  fallback, partial holds and whole-stack dragging.
- Source-data probes require the private catalog and use legal assembly and
  elapsed ticks, with no injected timers, task ordering, quest completion state
  or modified recipes. Wood + Villager followed by Timber + Villager, assembled
  while paused, completes as **Wooden Stick, Timber** after 601 ticks of 1/60 s.
  A fixed-registration/opposite-activation case proves that reversing the stack
  dictionary would not suffice.
- The source quest probe plays through the preceding six introduction quests.
  The earlier Stick event cannot credit the Get a Stick quest activated by the
  later Timber event. A subsequent real Stick craft completes it normally.
- Source probes also cover output-triggered new work, midpoint JSON continuation,
  travel before older tasks, independent inactive-scene order, return travel and
  replay of a completed departure checkpoint while paused.
- The board probe checks manual pause, menu, Options, vendor reveal, partial-tail
  hold and whole-stack hold through the actual board clock route. This is
  headless integration, not GPU, manual mouse or visual acceptance.

Existing intentionally forced save/presentation/unsupported-recipe fixtures
explicitly activate their synthetic tasks. They do not manufacture runtime
activation history by silently scanning stack registration order.
