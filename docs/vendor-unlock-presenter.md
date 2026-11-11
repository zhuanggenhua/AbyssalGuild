# Vendor unlock board adapter

`VendorUnlockPresenter` is a child Node with no automatic process loop. Its weak
board/tracker references and explicit lifecycle keep the old scene's signals from
restarting an interrupted reveal. It composes the independent
[unlock timeline](vendor-unlock-sequence.md) with existing native camera, trade
views and HUD. No original UI assets are copied.

## Integration API

- Add one presenter child to the board.
- Call `cancel()` before leaving a scene/session/title or rebuilding trade views.
  Tree exit also cancels it. Cancellation disconnects the previous quest tracker.
- After the new scene's final `_refresh()`, call `bind(board)` to establish a
  silent baseline and subscribe to the live tracker's `quest_completed` signal.
- Call `update_zones(trade_zones)` after rebuilding geometry. This never enqueues
  an unlock by itself.
- Sample `is_active()` before advancing a frame. OR this with the existing
  external menu pause for scaled simulation. Do not overwrite player pace.
- Call `advance(real_delta)` after camera motion, including while a menu is open.
- Use `is_active()` to block new world/card presses and ordinary camera input.
  Source CardController checks the input lock on pointer-down only: a previously
  granted drag can still move and release. Do not blanket-reject pointer-up.
  The source equipment-panel visibility UI, time-pace UI and PauseMenu are not
  governed by that lock.

The quest callback first synchronizes all vendor eligibility, then queues newly
active zones. It displays the Sequence-priority information, sets that vendor's
native highlight and starts a 0.5-second source-coordinate camera move. It never
revokes a preexisting drag grant. Completion removes only its own presentation.

The adapter adds a separate noninteractive HUD notice rather than replacing the
ordinary notice label. This prevents a purchase, checkpoint or save error from
accidentally erasing the reveal, while preserving error information. End-cycle
phases hide this lower-priority notice so feeding, selling, encounter and new-day
instructions retain Modal priority. Its timer continues in real time while hidden.

Cancellation clears a still-running camera focus only if it is the identical
focus dictionary created by this reveal. A newer cycle camera request is not
removed. A menu's pause, selected time pace, gameplay state and serialization are
never changed by the presenter.

## Verification

```sh
bash tools/test_godot.sh res://tests/godot/test_vendor_unlock_presenter.gd
```

The synthetic board adapter suite checks actual tracker connections, silent
baseline, focus timing/coordinates, highlight and notice ownership, save-error
preservation, modal precedence, held-drag grant retention, old-session signal
isolation, repeated cancellation, newer camera-focus ownership and tree teardown.
It does not replace full real-board or rendered/manual acceptance.
