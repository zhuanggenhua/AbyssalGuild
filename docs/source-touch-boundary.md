# Touch migration boundary, not a completed replacement

The reference template remains `a11a89b04cea8370476f2559b639bb9b4cbc08d8`.
Its dependency lock names InputSystem 1.19.0; official dependency commit
`ca8d898356596a91bda6505e506cc1a4bb3a9fa6` identifies that version. The retrieved
Touchscreen, TouchPressControl, Pointer and UI input module source files were
verified against their official Git blob hashes. Original dependency files and
experimental inputs remain private. Unity was not executed.

## Camera primary-touch lifetime now mapped

`StackCraftInput` reads shared `Pointer.current` position (with primaryTouch
fallback), and `CameraController.HandlePan` observes primary press/release edges,
not each individual touch's release. InputSystem Touchscreen aliases its Pointer
position/press to primaryTouch. When that first contact ends or is canceled while
another remains, primary becomes an orphan: it is still pressed, takes the first
contact's final position, and stays there until the last contact ends/cancels.
Secondary motion and a new contact joining the orphan do not take over primary.
A sole primary release instead stops camera dragging before its final position
delta is applied. The source admits up to ten active contacts.

Godot's mouse-from-touch emulation releases its mouse when the first contact
ends, and can generate a new mouse press for a later contact during source orphan
lifetime. Actual `Input.parse_input_event` delivery confirmed that each emulated
mouse event arrives before its corresponding touch event. Previously those events
stopped the camera early, lost the primary final delta, or started another pan.

`source_camera_pointer.gd` now tracks camera-only shared position and primary
lifetime for one touchscreen. Once a primary exists, its actual touch events own
camera movement/release; preceding synthesized mouse events are ignored **only by
the camera paths**. The original card/UI/native event delivery is not consumed or
replaced. First blank-board press admission still uses the existing native GUI
routing and physics hit result. Real mouse left/middle release remains effective.
Device state advances during input locks, but camera handling still early-returns:
locked releases are neither automatically repaired nor replayed on unlock.

The camera's pointer sample is separate from card/hover position so newly emulated
secondary mouse motion cannot move an orphaned camera. Existing focus/feedback
cleanup invalidates the camera sample without inventing device-reset semantics.
No gameplay model, save data, card receiver/hold architecture, wheel behavior,
rendering, or UI hit-test implementation is changed.

## Executable evidence and limits

- Public helper tests cover orphan creation/final position, ordinary/canceled
  release, no secondary/third-contact takeover, fresh sequences, real-mouse
  distinction, invalid events and the ten-contact limit.
- The private Board suite uses real Godot event delivery and actual empty-board
  ray picking. Its frame-separated sequence covers primary movement, two/three
  contacts, first and final cancellation, native GUI-consumed initial presses,
  a fresh single contact, real mouse
  left/middle edges, input locks and no card/held-stack mutation. Eight assertions
  fail on the previous production Board and pass with this mapping.
- Existing camera and card/equipment/held-stack suites remain distinct regressions.
  Injected input is not physical touchscreen, GPU or Unity runtime acceptance.

The source UI retains a separate press receiver per touch while CardController
uses shared pointer position. Different-card concurrent holds and repeated-card
press behavior still need that independent architecture. The older isolated
candidate for per-touch cards was not merged: filtering all synthesized mouse
would remove existing blank-board pan, and conservative Control rectangles are
not an equivalent UI raycaster. This camera-only helper is not that candidate.

Exact source EventSystem masking/sorting, its current-pointer/previous-frame
cache, mixed-device event order, more than one physical touchscreen, accumulated
multiple edges within a frame, hardware acceptance and device-reset/focus
cancellation remain open. In particular, InputSystem device reset cancels primary
and all active contacts directly; the current native focus notification is not
claimed equivalent to that reset. No full touch migration claim follows from
this bounded branch's tests.
