# Title gameplay preferences

The independent Godot helper `scripts/ui/title_gameplay_prefs.gd` reads the local
Title scene's `GameplayPrefsUI` references in the private imported catalog. It
resolves the actual duration slider and friendly toggle by file ID, rather than
using the first slider in the scene or relying on fixed source IDs.

The audited source has duration minimum 60, maximum 180, initial value 120 and
whole-number selection enabled. The Godot slider therefore permits 137 seconds,
not just multiples of ten. Its label updates immediately. Both friendly toggle
states use the source's wording (“No enemies will appear” / “Enemies may appear”).
Starting a game transfers the selected integer duration and flag into the native
campaign and initial save. Continue uses the saved campaign, not title controls.

Missing or invalid references explicitly report a control fallback: 60–180
seconds, initial 120, friendly OFF. Missing game data still blocks starting a
game through the existing import guard. The helper does not create mock game
data, write global preferences, or change existing save slots. These native
controls remain on the migration title screen; this is not a claim of pixel-level
Unity panel reproduction or manual mouse/visual acceptance.

Focused checks (use a writable isolated HOME/XDG_DATA_HOME/XDG_CACHE_HOME):

```sh
python3 tools/run_godot_test.py godot --headless --path . --script tests/godot/test_title_gameplay_prefs.gd
python3 tools/run_godot_test.py godot --headless --path . --script tests/godot/test_title_gameplay_prefs_board.gd
```

The first test requires no private data: unequal synthetic settings, decoy
slider, whole/continuous control modes, clamping, missing references and labels.
The second requires the local import: actual source defaults, 137/83-second edits,
both flags, two new slots, persisted settings and Continue's saved-value priority.
No original Unity files or generated private catalog data are published here.
