# Vendor unlock runtime integration

The board binds the live-only [vendor reveal presenter](vendor-unlock-presenter.md)
after a scene's trade geometry and finalized quest state are restored. The actual
quest-completed signal triggers activation, FIFO presentation, source-position
camera focus and highlighting. A normal UI refresh never manufactures an unlock.
This is independently authored Godot behavior verified against the locked source;
no Unity process or original code/media redistribution was used.

## Input and clocks

- New card presses, convenience card transactions and ordinary camera navigation
  are blocked during a reveal. A pointer grant made before the reveal still owns
  its motion and release, including a release over a menu. The held-stack helper
  and original-crafting-stack exception remain unchanged.
- Equipment-panel visibility clicks retain their separate source behavior. The
  reveal lock does not block them. Menu and end-cycle phase rules still apply.
- Selected pace and Escape menu controls remain independent. Changing pace does
  not remove the reveal's external pause, and finishing a reveal does not close
  or release a menu pause. Day-cycle confirmation retains its own existing rules.
- The board samples external pause ownership at frame start. If the reveal ends
  during that frame, the frame's time is not retroactively applied to gameplay.
- Camera focus, reveal timing, combat travel/impact/return and cycle waits advance
  with real time. Day elapsed time, crafting/AI/production, idle combat action
  accumulation and lethal combat's scaled death wait remain stopped.

The reveal uses its own noninteractive notice rather than replacing ordinary
messages such as save failures. End-cycle modal phases hide the lower-priority
reveal notice while its real-time clock continues.

## Lifecycle and saves

Scene/session entry and return to title cancel active/pending presentation before
rebuilding views. The presenter disconnects the old quest tracker, removes only
its highlight/info/focus ownership and establishes a new silent baseline.
Deferred refreshes recheck the current running state before touching the board.
Real Main-to-Island travel uses the same lifecycle. A newer cycle camera focus
is not cleared by the old reveal's cancellation.

The controller never writes `Session.paused`, speed, RNG or save fields. Saving
while a reveal is active preserves real quest progress, vendor payments and
selected pace. Continue reconstructs vendor eligibility without replaying the
animation, carrying its input lock, or restoring its queued UI requests. Existing
native held-card save normalization remains in place.

## Validation

`test_vendor_unlock_board.gd` requires locally imported source data but no Unity
runtime. It completes the first three actual introduction quests through starter
pack draws, berry recipe discovery and mining, then checks the first reveal. It
also verifies multiple real eligibility thresholds, repeated quest notifications,
new-input blocking, equipment-panel routing, existing held release, pace/menu
composition, native save/title/Continue, source payments and Main-to-Island travel.
Separate cases exercise a real combat timeline and overlapping feeding waits.

```sh
bash tools/test_godot.sh res://tests/godot/test_vendor_unlock_board.gd
```

This is headless functional verification. Actual rendered composition, mouse
feel, audio-device behavior and exact Unity coroutine scheduling remain manual
acceptance work; the tests do not claim those checks are complete.
