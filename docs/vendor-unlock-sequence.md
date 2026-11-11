# Vendor unlock reveal

Independent Godot implementation based on static inspection of the locked
StackCraft template. No Unity process was run and no original implementation or
media is included. Functional tests do not claim pixel or cross-engine coroutine
scheduling equivalence.

## Source behavior

The relevant contracts are `TradeManager.HandleQuestCompleted`,
`TryStartNextSequence`, `PlayActivationSequence`, `PackVendor.TryActivate`,
`RestoreState`, `GetInfo`, `TimeManager.SetExternalPause`,
`CameraController.MoveTo`, `InputManager`, `InfoPanel`, `DayTimeUI` and `PauseMenu`.

- Only a quest-completed notification queues reveals. All newly eligible vendors
  become active immediately, in offered-pack order, before their reveals begin.
  A repeated quest notification cannot activate an already active vendor again.
- Each reveal owns a general input lock and an external time-pause lock. External
  time pauses are counted independently of the user's selected time pace.
- It requests the Sequence-priority heading `Pack Unlocked`, with the vendor body
  `You can buy <display name> card pack here.`, then highlights the vendor.
- Camera movement uses the source default of 0.5 seconds, with unscaled update.
  After movement completes, a separate 2-second realtime wait begins.
- Cleanup removes the vendor highlight, input lock, info request and only that
  reveal's external pause. The next queued reveal starts immediately afterward.
- Restoration uses finalized quest count and saved vendor payment. Eligible
  vendors are restored silently, not queued for a replay.

The input lock is **not** a general UI disable switch. Source card/world input and
camera navigation respect it; the day-time pace button and the pause menu's
Escape handler do not. Pace can be changed during a reveal without allowing
scaled gameplay to advance. Menu pause is independent and must remain in effect
after the reveal ends. End-cycle input/info restrictions still have priority.

## Native controller contract

`VendorUnlockSequence` is live-only and does not hold a Session, write selected
pace, publish synthetic time-pace events, or add save fields.

- `restore(zones)` cancels old presentation and records initially active vendors.
- `update_zones(zones)` updates geometry only. Refreshing a UI never creates a
  quest completion or silently acknowledges a future unlock.
- `on_quest_completed(zones)` claims newly active vendors and queues them by zone
  index. Distinct vendor instances offering the same pack remain distinct.
- `is_active()` is this controller's own pause/input ownership, not total global
  pause. Compose it with existing menu/cycle rules without changing those owners.
- `advance(real_delta)` crosses at most one yielded boundary per frame. Excess
  frame time does not shorten the subsequent wait or a queued vendor's move.
- `sequence_started(zone)` supplies source coordinates for camera focus and the
  zone to highlight. `info()` supplies the request text.
- `sequence_finished(zone)` fires after controller state becomes idle; listeners
  remove only this presentation's ownership. A synchronous cancellation or scene
  rebind cannot restart the stale queue.
- `cancel()` is idempotent and discards both active and pending presentation. It
  is required for title, scene/session replacement, restore and teardown.

The queue samples a vendor's latest geometry when that vendor's reveal begins.
The running move retains its original target, matching the source tween. The
native outline is independent authored line geometry; it does not change trade
colliders or imported material data. A caption/geometry refresh keeps the outline
active until its owner releases it.

## Board integration requirements

Connect to the live `quest_tracker.quest_completed` signal only after the scene's
silent restore baseline is established. Disconnect the previous tracker on
session replacement. On a completion, synchronize trade zones before offering
those zones to the controller. Ordinary `_sync_trade_zones` calls update geometry
but do not enqueue reveals.

Update camera motion and the reveal using real frame time. If the reveal was
active at frame start, keep scaled day time, AI, production, crafting, idle combat
accumulation and scaled death waits stopped for that frame. Existing combat
travel/return and cycle realtime waits must still advance. Do not call
`session.set_paused` to implement the external pause: that would alter player
pace, notify pace quests and pollute an otherwise normal save.

World/card and camera entry points must reject new input during a reveal while
leaving menu and pace behavior independent. Do not let another transaction's
ordinary notice overwrite the reveal's Sequence-priority text. End-cycle modal
information outranks the reveal. A restored native save reconstructs eligibility
from quests/payments and starts with no reveal lock, timer or queued UI request.

## Verification

`tests/godot/test_vendor_unlock_sequence.gd` is a source-free synthetic suite for
silent restoration, offered order, duplicate events, same-pack vendor instances,
0.5 + 2-second boundaries, oversized/invalid frames, geometry refresh, interrupted
queues, callback reentry, independent native highlight, selected pace, camera
realtime progression and unchanged model/save state.

Run:

```sh
bash tools/test_godot.sh res://tests/godot/test_vendor_unlock_sequence.gd
```

This controller-level suite is not a substitute for board integration or visual
acceptance. The board wiring and full real-data flow require their own checks.
