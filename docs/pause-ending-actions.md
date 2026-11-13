# Existing Pause buttons during day ending

Source `Scripts/UI/PauseMenu.cs::Awake` binds Options to GameOptionsUI.Open and
Title to GameDirector.BackToTitle. These button callbacks do not use the
IsEndingCycle condition found in PauseMenu.Update's Cancel input route.
GameOptionsUI.Open activates its object, while BackToTitle saves before starting
the title transition. TextButton invokes its callback without a day-cycle gate.

After the source day-clock boundary fix, a menu can open on the threshold-crossing
frame and remain open when the next Update enters feeding. Native button guards
previously rejected Options and Title in that state; Options also had a second
phase check in its own callback.

The existing visible Pause's buttons now retain admission during day ending.
Options additionally permits its callback when Pause is already visible. No new
Pause or Options opening outside that existing menu is allowed during ending.
Escape remains day-gated. Transition, active options, quit and modal guards are
unchanged. Closing Options returns to Pause, without releasing day/vendor locks.

Title uses the unchanged save-before-fade path. Save failure stays in game and
reports the failure. A game-over Title request still requires confirmation and
uses recoverable archive rather than permanent source deletion. These safety
policies were not altered to broaden button admission.

## Verification

`test_pause_ending_actions.gd`: 27 checks using the real source catalog and fresh
test-owned slot/options paths. Actual `pressed.emit()` routes cover Options,
Options Close, Title, and game-over confirmation/cancellation. The success path
writes a real campaign save, validates and restores cards with modified health
and nutrition, completes the fade, and reloads the slot. A test-owned file blocks
saving to prove failure does not leave or start fading. Modal/transition gates,
Escape/new-menu rejection, overlapping vendor/day ownership and confirmed
recoverable archive behavior are also covered. No critical save callback is
stubbed, and no existing user save is changed.

Focused boundary Board, pause input, navigation UI, source pause layout, options
UI, vendor Board, cycle Board, scene-transition Board and slot-management UI
regressions pass. This is headless routing/state verification, not physical input,
rendering, or Unity execution acceptance.

Final frozen integration checks: 145 Python tests; 144 Godot groups including
51 catalog-backed groups; an independent source-free checkout passed93 groups;
a fresh private import passed all76 required suites. The new button/save tests
remain headless; no new physical-input or original-engine visual claim is added.
