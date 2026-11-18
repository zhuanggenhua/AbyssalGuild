# Options and Pause own different things

Locked source `a11a89b04cea8370476f2559b639bb9b4cbc08d8`:
`PauseMenu.Update` observes a fresh Cancel unless the day cycle is ending.
`ToggleActiveState` changes only that menu's CanvasGroup and adds/removes its
one TimeManager external pause lock. Its Options button invokes
`GameOptionsUI.Open`. That independent sibling activates itself; it does not
acquire a pause lock. Only its explicit Close saves preferences and hides it.

Native Board previously interpreted Escape above Options as Save & close,
leaving Pause active. The admitted source path now toggles only Pause while
Options remains visible, dirty, focused and input-blocking. Source audio and
session/scaled-effect sampling use a separate temporal owner predicate; all
other `_ui_pause_active` input gates remain unchanged. Selected pace, vendor
locks, day-cycle waits, and scene-transition ownership are not replaced.

Admission requires a real ordinary playing Pause-to-Options opening token,
locked provenance and linked PauseMenu/nested GameOptionsUI records, an
actual source-referenced Main/Island UIRoot, and both mounted source panels.
The cache belongs to that session, scene, catalog data identity and Options
view. Direct programmatic Options.open cannot mint it. Closure, transition,
title, configuration/replacement and teardown revoke it. Reset confirmation
suspends admission without replacing the still-live opening token; canceling
that modal may resume the same ordinary owner. Unknown or malformed source
and native fallback retain previous behavior. No per-frame prefab scan is
needed after admission.

The fresh Cancel is consumed before GUI input exactly once; releases and
key-repeat do not toggle. During ending-cycle phases it is consumed without
changing either panel. Options continues blocking Feed People and card input
when the day ends behind it. Failed explicit Close keeps Options dirty and
visible. These are settled-frame state/ownership contracts, not claims about
Unity-versus-Godot same-frame Update phase order or pixel equivalence.

Regression: actual Main/Island Board test includes fresh/echo/release,
reacquisition, source audio and gameplay progression, vendor lock overlap,
reset/transition ownership, explicit Close failure, day-end and blocked Feed,
title/fallback, unknown data replacement, and direct programmatic opening.

## Pause buttons: original mouse release ownership

In the locked UIRoot, `PauseMenu.Awake` wires its Continue, Options and Title
`TextButton` records. The original `TextButton.OnPointerClick` does not inspect
the mouse button, and the UI input module binds left, right and middle clicks.
The three mounted Godot source buttons formerly accepted only left click.
Enable all three buttons only when the pinned PauseMenu controller, its matching
enabled serialized TextButton, and the actual mounted host agree. Do not
broaden source-free controls or safety/recovery dialogs. Existing callback and
Click sound order is unchanged.

The actual Board viewport test follows Pause → Options → Close → Continue
and Pause → Save & Title → load the same slot, for each of the three mouse
buttons. It checks press versus release, outside release, Options input
ownership, callback-before-sound, saved clock restoration and failed-save
retention. It also rejects altered source/controller/button references and an
incorrect mounted host. This is not a platform/device or Unity visual acceptance.
