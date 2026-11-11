# Required cycle actions and source click routing

This is a functional Godot UI correction over the existing asynchronous day-cycle
model. It does not reproduce the original InfoPanel's typography or animation.
No model timing, save format, original asset, or imported content data is changed.

## Static reference

Only CardLoop `a11a89b04cea8370476f2559b639bb9b4cbc08d8`, within
`Assets/StackCraft/Scripts`, was inspected:

- `Core/DayCycleManager.cs`: NotificationPhase requests a mandatory Feed People
  action, PrepareForNewDay requests Start Day, and HandleGameOver requests Return
  to Title, all at modal InfoPanel priority.
- `UI/InfoPanel.cs`: the highest-priority information request supplies a single
  action; requests without an action hide that action during processing/selling.
- `Card/Components/CardController.cs` and `Card/Behaviors/ChestLogic.cs`: the
  unmoved-click path dispatches IClickable. A singleton chest withdraws one coin,
  enforcing board placement at the chest's width to the side and requesting the
  Coin sound. A stacked or empty chest does not withdraw.
- `Core/TimeManager.cs` and `UI/DayTimeUI.cs`: Paused, Normal and Fast are the
  source time paces. Day-end hides/disables pace interaction. There is no 3x pace.

Unity was not launched, and source files/assets were not copied into this repo.

## Native adapter changes

- There is still exactly one day-action button. It is now in the persistent
  top summary rather than inside Market & controls. Feed, Start next day and
  Game over remain visible with either or both sidebars collapsed. The summary
  uses two lines to leave space for the button.
- Existing timeline stages still decide when the action is enabled. Feeding and
  encounter progress and the excess-card requirement remain visible as disabled
  action text. The native early End day & feed command remains available during
  play. Game-over return retains the existing recoverable-archive confirmation.
- Paused-menu and Options callbacks cannot invoke background day or pace actions.
  Opening/closing the pause menu refreshes their disabled state immediately.
- An unmoved singleton-chest click and the existing explicit withdrawal command
  share the same placement/withdrawal adapter. The pointer-granted card alone may
  complete its already-valid click across a day boundary or a later Pause/Options
  overlay. Menu toggles preserve the captured pointer rather than canceling it;
  actual pointer-up still completes once. Releasing again, dragging away/back,
  or a new locked-phase click cannot withdraw another coin. New selling-phase
  clicks remain allowed. This corrects the earlier menu-cancellation assumption
  after tracing the source input dispatch; see [held-stack lifecycle](held-stack-lifecycle.md).
- Pace controls offer only 1x (Normal) and 2x (Fast); both refresh the HUD on use.
  During ending-cycle phases they are disabled and their callbacks reject stale
  activation. Manual playing-phase pause still allows selecting a new pace.

The latest operational notice, including save failures, is not overwritten every
frame merely to announce the phase. Required cycle instructions stay visible in
this dedicated persistent button instead.

## Verification

Run `bash tools/test_godot.sh res://tests/godot/test_cycle_action_visibility.gd`.
This suite requires locally imported licensed data and fails rather than silently
skipping it. It uses a unique test-owned user-data directory; the runner isolates
HOME/XDG directories from player saves.

The 76 checks cover real natural day-end, feeding, ready and starvation paths;
all four collapsed/expanded sidebar combinations; one action binding and
nonoverlapping logical bounds; repeated Feed and game-over presses; checkpoint
retention; supported speeds and every ending-phase lock; real Wooden Chest
clicks, empty/stacked/drag/repeated-release cases; held clicks across a boundary;
pause/Options interruptions; title and Continue. Synthetic phase assignments are
explicit lock fixtures, not substitute gameplay content or timeline evidence.

Regression checks also passed: UI smoke 139, slot UI 50, slot management helper
50, slot management UI 24, cycle board 29, equipment board 19, and trade/collection
UI 43, and Options UI 42. Test runner registration remains the release owner's
responsibility.

These are headless scene/control/routing assertions. They do not establish
rendered legibility, real mouse hit-testing, original-art fidelity, sound quality,
or Windows/export acceptance. The existing 1440×900 logical HUD and viewport
stretch behavior remain unchanged.
