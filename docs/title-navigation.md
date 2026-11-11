# Native title navigation

Static reference: `Scripts/UI/Title/TitleScreen.cs` wires four separate home actions: New Game opens `GameplayPrefsUI`, Load Game opens `SavedGamesUI`, Options opens `GameOptionsUI`, and Quit requests modal confirmation. `GameplayPrefsUI.cs` separates Cancel from Confirm and only Confirm invokes `GameDirector.NewGame`.

The native board now composes three destinations under its title panel:

- Home: New Game, Load Game, Options, Quit Game.
- Gameplay Preferences: the existing source-reference duration slider and Friendly Mode toggle, Confirm, Cancel. Opening/reopening allocates no slot. Confirm consumes the pending UI intent and begins the scene transition, which calls the preserved programmatic `start_new()` method at black. Failure leaves preferences and the error visible for explicit retry.
- Saved Games: existing native slot selection and Continue, recoverable archive controls, restore-copy inventory, optional legacy-copy controls, and Back. Native archive/restore extensions remain recoverable and retain their previous confirmation and validation semantics.

Cancel, Back, Escape, and synthetic gamepad East return to Home. A visible archive/quit/reset modal gets priority; closing it does not also change destination. Options retains its existing save-on-close behavior, including staying open on failed persistence. Destination changes and Confirm cannot bypass an open options panel. Returning from or entering gameplay clears pending preference confirmation. `title_status` stays outside the changing destination containers so data/save errors remain available everywhere.

The helper `scripts/ui/title_navigation.gd` tracks destination and one-use confirmation intent. The board owns actual visibility, focus, source-backed controls, save creation, and modal priority. Programmatic start/continue/archive APIs remain compatible; this is UI composition, not a save-format migration.

## Verification

Headless test commands (each uses the existing isolated runner):

- `bash tools/test_godot.sh res://tests/godot/test_title_navigation.gd`: 5 helper checks.
- `bash tools/test_godot.sh res://tests/godot/test_title_navigation_board.gd`: 23 checks with imported data, including repeated clicks, stale Confirm, keyboard/gamepad cancellation, options persistence failure/recovery, archive modal priority, missing-data Quit, and slot creation only on Confirm.
- Existing regressions passed: navigation UI 56, title gameplay preferences board 11, slot management UI 24, options UI 42.

These are static source comparison and synthetic/headless behavior tests. No Unity launch, desktop/display workaround, physical-controller test, screenshot equivalence, or manual visual acceptance was performed. The native title retains Godot controls/layout. Original source font rendering, TextMeshPro rich text, source art placement, and pixel-exact title styling are not claimed or fabricated.
