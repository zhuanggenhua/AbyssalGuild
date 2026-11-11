# Source day clock and day-boundary navigation

Static reference: locked StackCraft `Scripts/UI/DayTimeUI.cs`,
`Scripts/UI/CardStatsUI.cs`, `Scripts/UI/Menu/MenuToggle.cs`,
`Scripts/Core/TimeManager.cs`, and `Prefabs/UI/UIRoot.prefab`.
Both Main and Island reference the shared UIRoot prefab.

The native persistent header now includes the current day, a normalized horizontal
progress fill and a clickable pace control. The scene's actual prefab reference
selects DayTimeUI; its serialized timeProgress reference supplies the fill tint
and its paceIcons array supplies the three private sprite GUIDs. The existing
private visual loader loads these assets when present. Missing/broken references
or missing media leave a labeled native text fallback and an explanatory tooltip,
not an assertion that original artwork was loaded. No source art is redistributed.

Clicking uses the existing authoritative cycle_time_pace API: Normal → Fast →
Paused → Normal. Menu/options and title/phase guards reject stale clicks without
rewriting the user's selected pace. External vendor reveal locks continue owning
scaled time separately, as they do for existing source-supported pace controls.
Progress updates during normal live frames, clamps to 0–1 and does not advance
while gameplay is externally paused.

The source-equivalent clock/stat regions disappear at the actual day-ended event
and the journal closes once on that transition. The journal can be reopened
without every refresh closing it. Neither behavior cancels captured card drags.
The persistent day-action button and notice remain independent and available;
new-day state restores clock/stats and source Normal pace. The market heading
uses the current scene instead of always saying Main.

Validation:
- `test_day_clock.gd`: 16 synthetic resolver/view/phase/pace checks.
- `test_day_clock_board.gd`: 29 actual-source/private-media checks, including both scenes and
  all six scene/icon bindings, live clicks, title/menu/options locks and day boundaries.
  A data-only import runs 21 checks, verifies the live text fallback, and emits
  an explicit artwork SKIP. An existing manifest requires every referenced
  texture; successful private bindings emit a positive imported-runner marker.
- Existing cycle-action and held-stack board regressions cover discoverability
  and carried pointer releases across day-end boundaries.

The native button/progress geometry and fonts are not a reconstruction of Unity
Canvas layout. Journal closing is immediate rather than the source's unscaled
0.5-second slide. Original TMP font GUID
`8f586378b4e144a9851e7b34d9b748ee` is referenced but absent from the locked subtree.
Headless resource/input tests do not establish rendered legibility, physical
pointer/controller behavior, original-font or pixel parity. No Unity execution,
display-server workaround or Windows acceptance is involved.
