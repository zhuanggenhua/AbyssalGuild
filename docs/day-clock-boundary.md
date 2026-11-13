# Day-clock threshold Update branch

Locked source `Scripts/Core/TimeManager.cs`, `Update`, tests the old currentTime
before adding Time.deltaTime. A frame that reaches or exceeds dayDuration still
runs the increment branch. Only the following Update resets currentTime to zero,
sets Paused, updates time scale and invokes OnDayEnded. The ending branch does
not check externalPauseLocks or require a positive delta.

`GameSession._advance_day_clock` now preserves that branch choice. Ordinary
`tick` supplies its scaled increment; `tick_paused` supplies zero, including the
Board menu/vendor external-pause route. Both entry points process an already
reached threshold at zero delta. The existing cycle controller resets elapsed,
pauses and enters feeding before emitting day_ended then cycle_stage_changed.
Automatic ending does not invent a time_pace_changed event. Subsequent updates
cannot replay the boundary while the phase is no longer playing.

The crossing-frame elapsed value may exceed dayDuration. SaveCodec already
accepts and restores that value; no serialization migration or clamp was added.
Normal and Fast pace, pause introduced after crossing, no catch-up days, exact
threshold and large overshoot have focused checks. Board tests exercise normal,
menu, vendor and overlapping pause owners and ensure releasing those owners
does not release the day-cycle input lock.

The old automatic-timeout assertion in test_cycle_timeline expected immediate
ending from tick(1) at duration 1. It now first asserts playing at elapsed 1,
then uses tick(0) to assert the following Update's feeding transition.

This maps TimeManager's own branch and native callback boundary. It does not
establish Unity's relative execution order among different MonoBehaviour Update
methods, rendered input acceptance, or a global cross-engine frame equivalence.
No Unity execution was used.

Verification on isolated ce5f525:
- test_day_clock_boundary: 44 checks.
- test_day_clock_boundary_board: 23 checks (private source catalog).
- Existing cycle timeline/order/save/presentation/board, day-clock board,
  endgame source, runtime, combat timeline, vendor board and scene-transition
  board suites pass. The day-clock artwork assertion explicitly skips when the
  optional private visual manifest is absent from this isolated snapshot.

## Continue remains independent of Cancel input

The pending-threshold frame can open Pause before the following Update begins
feeding. Source `UI/PauseMenu.cs` wires ContinueButton directly to
ToggleActiveState; only the Update/Cancel route checks IsEndingCycle. Native
Continue previously shared that gate and could not close the already-open menu.
Its own close-only callback and admission guard now remove the menu owner while
preserving day/vendor owners. The existing Escape and new-menu gates are unchanged.

The Board suite now passes 34 checks, including actual Continue `pressed` signal
routing in menu-only and overlapping-vendor cases, ending-cycle Escape rejection,
hidden-repeat rejection and preservation of the day input lock. The pre-fix board
fails those new close/repeat assertions. Pause input, navigation, source pause
layout, options UI, vendor and cycle Board regressions also pass.
