# Title Preferences and Saved Games raw Cancel ownership

Locked source `a11a89b04cea8370476f2559b639bb9b4cbc08d8` has
TitleScreen.Start wiring New/Load to GameplayPrefsUI.Open/SavedGamesUI.Open.
Neither overlay handles raw Cancel. Preferences' explicit Cancel calls Close;
Confirm invokes NewGame with current preferences and closes. Saved Games'
explicit Close deactivates its panel. Existing native recoverable archive and
confirmation workflows remain native; this correction does not replace them
with the original permanent-delete behavior.

Only a legitimate source-mounted New/Load opening from Home admits suppression
of Escape/gamepad East. The record-linked actual overlay, destination, source
Title adapter and catalog data identity must agree. A source overlay retains
focus and pending transaction after raw Cancel; no slot is created, loaded,
archived or saved. Explicit Cancel/Close and Confirm transactions are unchanged.
Unknown source and native/fallback shortcuts retain their existing behavior.

Options, transitions, recovery and archive/reset/quit modals, and simultaneous
Preferences/Saves overlaps are excluded. Modal dismissal can return to the same
still-open owner. Hidden panels, destination/source replacement, transition and
title/game lifecycle invalidate tokens; direct visibility cannot create one.
Source record scans occur at admission, not each frame. This does not alter
Options behavior, gameplay time, archive semantics or commit ordering.

Tests exercise both real overlays with keyboard/gamepad input, echo/releases,
focus and pending intent, modal/Options/overlap exclusion, explicit close stale
Confirm protection, visibility revocation, replacement and true unsupported
fallback. Existing title navigation tests retain exact-one-slot creation, load,
explicit failure/confirmation and archive handling. No Unity runtime, framebuffer
or overall migration parity is claimed.

## Explicit pointer buttons

Locked TitleScreen.Start wires New Game, Load Game and Game Options to their
panel Open callbacks. GameplayPrefsUI.Start wires Cancel to Close and
SavedGamesUI.Start wires Close to Close. Their enabled source TextButton
components use the same unfiltered OnPointerClick as the graphics controls;
they do not restrict PointerEventData.button to left.

The Title adapter admits left/right/middle only for these five mounted roles,
after verifying the locked source graph, exact component ID and script GUID,
enabled state, owner GameObject and mounted node. Confirm, Quit, archive,
recovery, native fallback and shared feedback defaults remain primary-only.
The Options panel's own Close is not widened by this change. Sequential release,
not press, executes the existing guarded callbacks and sound. Tests include
outside cancellation and modal ownership; simultaneous-button ownership and
physical-device/Unity-side event timing are not established by these tests.
