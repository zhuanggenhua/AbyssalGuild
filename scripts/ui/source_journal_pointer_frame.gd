extends RefCounted
## Mouse click/drag admission for the pinned Input System 1.19.0 UI module.
## A caller supplies one processed frame, its final raycast receivers and
## physical pixel position. Zero IDs mean no handler. Not a native GUI picker.
const BUTTONS := [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]
var _captures: Dictionary = {}
var _receiver := 0
var _eligible := false

func reset() -> void:
	_captures.clear()
	_receiver = 0
	_eligible = false

func advance(point: Vector2, moved: bool, edges: Dictionary, click_receiver: int,
		down_receiver: int, drag_receiver: int, threshold: float, ignored: Array = []) -> Array[Dictionary]:
	var dispatch: Array[Dictionary] = []
	for button in BUTTONS:
		if button in ignored: _eligible = false
		var edge: Vector2i = edges.get(button, Vector2i.ZERO)
		if edge.x != 0:
			# A fresh press resets event delta for this and subsequent buttons
			# in this frame, not the stored origin of an already held button.
			moved = false
			_receiver = click_receiver
			_eligible = true
			_captures[button] = {"press":down_receiver if down_receiver != 0 else click_receiver,
				"drag":drag_receiver, "origin":point, "dragging":false}
			if drag_receiver!=0:
				dispatch.append({"kind":"initialize_drag","button":button,"receiver":drag_receiver})
		var capture: Dictionary = _captures.get(button, {})
		if edge.y != 0:
			if _eligible and _receiver != 0 and _receiver == click_receiver:
				dispatch.append({"kind":"click", "button":button, "receiver":_receiver})
			_eligible = false
			if capture.get("dragging",false):
				dispatch.append({"kind":"end_drag", "button":button, "receiver":capture.drag})
			_captures.erase(button)
			continue
		if not moved or capture.get("drag",0) == 0: continue
		if not capture.dragging:
			var distance := point.distance_to(capture.origin)
			# Same float round-trip tolerance as the ScrollRect host.
			if distance < threshold and not is_equal_approx(distance,threshold): continue
			capture.dragging = true
			dispatch.append({"kind":"begin_drag", "button":button, "receiver":capture.drag})
		if capture.press != capture.drag:
			_eligible = false
			capture.press = 0
		dispatch.append({"kind":"drag", "button":button, "receiver":capture.drag})
	return dispatch
