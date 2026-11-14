# Window-mode request observation

## Scope and captured failure

Base: published `8ff9503302ec3a3c6b31ca7ce44f947641d7f610`, tree
`b94e8a8586853f08fd4e4e0a53e949d562224a53` (local equivalent `b6e87d3`).
This changes only the application-window request/readback reporting. It does not
add hardware-resolution enumeration, change display modes or OS settings, map
URP presets, change the viewport, or alter saved-game state. The existing English
hardware-resolution warning now explicitly says that no hardware/output resolution
was applied; it does not deny a separately successful application-window mode
change. These diagnostic strings have no locale mapping; no other locale changes.

Three separate fresh-settings native X11 trials using the production Board and
Options adapter reproduced the same false warning. After fullscreen → windowed,
the immediate production getter returned **MAXIMIZED (2)**, not old fullscreen.
Later observations returned **WINDOWED (0)** and 1280×800 rather than 1364×1024.
The first observed matches were 272.562, 226.478 and 236.499 ms after the setter;
these are sampling upper bounds, not exact WM completion times. The old rejection
warning remained even after all three successful transitions. Already-windowed
refresh did not reproduce it. Fullscreen could likewise report its new enum
before its client-size update.

A separately created embedded child genuinely remained WINDOWED after requesting
fullscreen. Godot reported “Embedded window only supports Windowed mode.” This
negative boundary must remain visible, not be erased by the fix. The diagnostic
was not a standalone-package acceptance test or a natural gameplay session.

Godot 4.6.3 X11 source explains the asynchronous path: `window_set_mode` updates
cached fullscreen state and sends the EWMH request, while the immediate
`window_get_mode` can still see the WM's maximized properties. Later native-event
processing updates the state. See the official tagged source:
https://github.com/godotengine/godot/blob/4.6.3-stable/platform/linuxbsd/x11/display_server_x11.cpp
(`window_set_mode`, `_set_wm_fullscreen`, `window_get_mode`,
`_window_maximize_check`, and PropertyNotify handling). No claim is made that
this is a universal ordering on other platforms.

## Result contract

- `pending`: the preference is saved independently, but native application is
  still being observed. No final rejection is claimed from one immediate read.
- `succeeded`: requested enum and positive client size match on consistent
  observations separated by at least 100 ms, within the 2 s deadline. Fullscreen
  also requires client size equal to the current main-window screen size.
- `failed` / `timeout`: application was **not confirmed** by the observation
  deadline. This is not proof of OS refusal; the diagnostic preserves the
  embedded-window explanation as a possible cause.
- `unsupported` / `headless`: no native request or display change is made.

Observation is per-frame with elapsed-time bounds, not a fixed number of frames
or a sleep before blindly declaring success. Sampling does not prove continuous
stability between observations. It reports a request outcome, not a perpetual
monitor of later external window changes. Mixed-DPI, Wayland, macOS and Windows
are not claimed as natively accepted by the Linux/X11 trials.

An outstanding same-target request cannot be resubmitted or have its deadline
extended by volume/FPS/refresh events. A failed same-target outcome remains
visible until an explicit initialization, fullscreen change, reset or retry.
Incrementing request IDs reject stale A→B→A observations and stale cancellation.
Panel Close can hide the UI while observation continues. Panel disposal or
reconfiguration cancels its current observation without resetting the OS window.
There are no delayed callbacks retaining the destroyed panel. Updating the
application summary must preserve independent preference-save errors.

## Reproducible automated boundary

`bash tools/test_godot.sh res://tests/godot/test_window_mode_observation.gd`
uses the captured transient enum/size sequence with a controllable clock and the
actual adapter/panel, not an invented display-success response. The same fixture
on the unchanged base fails 19 assertions (11/30 pass; exit 1, no script errors).
The candidate passes all 30. It covers pending/success/timeout/unsupported,
fullscreen dimensions, stale tokens, repeated requests, late polling, preference
persistence/reload, hidden panels, disposal and an actual preference-write failure.
The runner's fake display is only a deterministic state-machine regression;
native candidate and eventual formal-package GUI acceptance remain separate.

This suite is included in normal and clean-public tests, and the fresh licensed
import runner. No private source assets, native screenshots or save files belong
in the public repository.
