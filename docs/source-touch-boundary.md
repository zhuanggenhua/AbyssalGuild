# Touch migration boundary, not a completed replacement

The source InputSystem 1.19.0 Touchscreen aliases pointer position to primaryTouch.
When the first contact ends while another remains, primary becomes an orphan:
its final position stays fixed until the final contact ends. Secondary contacts
do not become independent world-drag positions. CardController uses shared
Pointer.current position, while the UI retains a separate press receiver per
touch. Camera pan consumes primary press edges, not each card's release edge.

Source StackCraftInput.cs and CameraController.cs explicitly support blank-board
touch pan. A real Input.parse_input_event probe confirms the existing native
first-contact pan works, but stops when the first contact lifts, earlier than the
source orphan-primary lifetime. This remains a real unimplemented branch.

An isolated candidate proved standard same-card repeated down/up through real
physics picking and native event delivery. It also exposed Godot emulated mouse
arriving before touch. That candidate was NOT merged: filtering all synthesized
mouse would remove existing blank-board pan, and conservative Control rectangles
are not an equivalent UI raycaster. Passing those narrow tests is not full touch
implementation. No candidate helper is used by production.

Remaining architecture must separate shared device state, per-touch UI hit/press
capture and primary-camera edges, establish event/frame-phase ordering, preserve
GUI masking/sorting and handle different-card concurrent holds. Mixed-device,
secondary GUI, focus reset and touch hardware acceptance remain open. Unity was
not executed. Original dependency source and experimental inputs remain private.
