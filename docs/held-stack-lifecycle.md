# Held stacks and crafting lifecycle

Static behavioral reference: CardLoop
`a11a89b04cea8370476f2559b639bb9b4cbc08d8`, under `Assets/StackCraft`.
Reviewed `CardController.OnPointerDown`, `OnPointerUp`, `HandleStandardDrop`,
`CardStack.SplitAt`, `CardInstance.TryAttachToNearbyStack`, the crafting
pause/resume/validate methods, `TradeZone`, `ChestLogic`, `PackInstance`,
`InputManager`, `PauseMenu`, `TimeManager`, `GameOptionsUI`, and the UIRoot/camera
prefab input components. Unity was not launched. Original code/assets were not
copied into the public implementation.

## Pickup and release

`session.drag` is a live-only `held_stack.gd` helper. `begin(card_id, position)`
registers the trailing split immediately at pointer-down, before any frame can
advance crafting. Only a split from an active craft pauses the remaining original
stack, retaining its recipe and elapsed progress even if its ingredients are
temporarily incomplete. An idle remaining base is checked for recipes at pickup;
the held tail is not checked until release. Picking array index zero holds the
whole existing stack without splitting, pausing or replacing its identity.

`original_stack_id(card_id)` supplies the genuine held stack's original ID to
candidate selection and `move_to_stack`. The original active-recipe exception
does not bypass physical matrix compatibility and cannot be borrowed by an
unrelated incoming stack. Reattaching resumes the old timer without rerolling a
recipe. Ordinary release elsewhere validates the original's current task:
resume if still valid, otherwise stop it. It does not select a replacement recipe
for a broken original. An unattached idle tail is checked once on release.

`finish_standard(attached_stack_id=-1)` performs that cleanup after ordinary
placement/attachment. Handled chest deposits count as attachment even if they
leave cards behind. `finish_terminal()` stops the original task after a successful
terminal sale/payment, equipment attachment or combat action. Accepted vendor
payments with leftovers are not terminal. Failed targets do not force a merge or
roll cards back to their pre-press arrangement. Same-card repeated model presses
are idempotent; different presses cannot overwrite an existing hold. Board presses
are ignored while an earlier pointer is held. A destroyed held card is cleaned
up safely, and successful load/new game/scene transition invalidate old IDs.

The board now uses these methods on both moved and unmoved ordinary releases.
Moving the captured pointer updates the registered held stack, not only its
drawing. Ordinary placement constraints run before attachment, as in the source.
Pickup alone does not trigger overlap resolution that would push the original
stack away before a click can return its tail. The existing native equipment-tail
guard remains: it does not claim a successful terminal equip or cancel the
original task when it rejects that combination.

## Menu, UI and phase boundaries

The initial press requires enabled input. A previously granted hold can still
move/release during a later day-end or menu lock. GUI pointer-up is delivered to
the original captured press and performs ordinary resolution instead of silently
discarding a paused task. Opening Pause/Options changes time/UI state, not that
existing pointer grant. New card presses and background day/pace actions remain
blocked. Releasing a granted chest/pack click during a menu can therefore finish
it once; another release cannot repeat the click.

The locked UIRoot has an enabled EventSystem and InputSystemUIInputModule
(`01614664b831546d2ae94a42149d80ac`), and the camera has an enabled PhysicsRaycaster.
The project's input lock manager does not disable these components or their
actions. PauseMenu changes canvas blocking and external time scale. For the
engine dispatch mechanism, the official
[InputSystemUIInputModule 1.11.2 implementation](https://github.com/Unity-Technologies/InputSystem/blob/1.11.2/Packages/com.unity.inputsystem/InputSystem/Plugins/UI/InputSystemUIInputModule.cs)
sends pointer-up to the stored pressed object before its conditional click/drop
dispatch. CardController implements pointer-down/up rather than IDragHandler.
The exact Unity package version is outside the locked Assets subset, so this
dependency inspection is not a claim of running the original project.

## Explicit native safety differences

The source successful-click path returns before original-craft cleanup. A chest
lifted from an excess-allowing craft can therefore strand that original task
paused after a successful withdrawal. Native successful chest/pack clicks perform
ordinary non-reattached validation to close that lifecycle: resume a valid
remainder, stop an invalid one, never roll back or invoke terminal cancellation.
Missing original/held cards likewise cannot leave a reusable drag grant. This is
a deliberate safe cleanup, not a claim that the source already handled it.

## Native checkpoints during a hold

Pointer identity is not persisted. Capture first snapshots actual split
membership/positions, then restores an isolated model and settles the hold there
as an ordinary non-reattached release. It does not search spatial targets, replay
a click, trade, equip, enter combat or undo the split. The old recipe resumes at
the retained progress if the remaining ingredients qualify; otherwise it stops.
An eligible detached tail may select its own recipe in the clone.

Recipe selection, RNG state, recipe discovery and quest effects in the snapshot
are exactly those of this settlement. Capture emits no live signals and does not
change live RNG, knowledge, timers, model references or the ongoing pointer hold.
Repeated captures of the same held state are identical. Loading that snapshot
continues exactly as a real immediate non-reattached release would; choosing a
different eventual live drop can naturally produce a different continuation.
An unpaused whole-stack craft keeps its identity/progress. Reentrant capture
during a half-applied held transition is explicitly rejected. Failed loads leave
the live hold intact; successful loads clear it. Travel uses the same policy for
the frozen departure scene, including when another stack is being carried.

## Verification and limits

Run with the isolated `tools/test_godot.sh` runner:

- `test_held_stack.gd`: 73 synthetic checks, including strict/excess recipes,
  original-return and physical rejection, repeated input, new-target drops,
  sale/equip/combat, partial vendor payments, disappeared/replaced tasks,
  reentrant rejection, clone-only capture, JSON/disk load and next-tick RNG.
- `test_held_stack_source.gd`: 17 private-data checks, including actual
  Apple/Berry Fruit Salad at 9.9 seconds, restored split membership, whole-stack
  versus traveler-tail pickup, and held unrelated cards in departure snapshots.
- `test_held_stack_board.gd`: 32 private-data adapter checks, including actual
  press-before-tick ordering, click/away-and-back returns, registered motion,
  GUI/menu release, save while held, whole-stack completion, invalid matrix,
  terminal sale, successful chest-click cleanup and day-boundary grants.

The source-data suites fail if their licensed local inputs are absent. Existing
SaveCodec 534 and cycle validation 144 checks remain separate regression gates.
UI smoke uses lawful in-board chest/portal fixtures now that the adapter enforces
source placement-before-attachment; its former outside-board coordinates tested
an invalid ordering. The equipment-panel fixture explicitly finishes its prior
model hold when it manually clears the simulated pointer. These injected/headless
tests do not establish real mouse/touch capture, rendered clarity, GPU animation,
audio or Windows/export acceptance. Existing native pixel movement threshold,
settled target geometry and presentation approximations remain.
