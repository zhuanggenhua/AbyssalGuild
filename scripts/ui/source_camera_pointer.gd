extends RefCounted
## Camera-only shared pointer state for one touchscreen plus physical mouse.
## InputSystem 1.19.0 primaryTouch remains pressed/orphaned until all contacts end.
## Does not choose UI hit receivers, capture cards, or consume native input events.
const MAX_CONTACTS := 10 # Locked TouchscreenState.MaxTouches.
var contacts: Dictionary = {}
var primary_index := -1
var primary_active := false
var orphan := false
var primary_position := Vector2.ZERO
var position := Vector2.ZERO
var known := false

func suppress_emulated_camera_event(event: InputEvent) -> bool:
	# Godot sends its touch-emulated mouse event BEFORE the corresponding touch.
	# Once a primary exists, only the actual touch event owns camera state/edges.
	return primary_active and event.device == -1 and (event is InputEventMouseButton or event is InputEventMouseMotion)

func observe(event: InputEvent) -> Dictionary:
	var result := {"sample": false, "released": false}
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		if not suppress_emulated_camera_event(event) and event.position.is_finite():
			position = event.position
			known = true
			result.sample = event is InputEventMouseMotion
		return result
	if not event is InputEventScreenTouch and not event is InputEventScreenDrag: return result
	if not event.position.is_finite(): return result
	var index: int = event.index
	if event is InputEventScreenTouch:
		if event.pressed and not event.canceled:
			if contacts.has(index) or contacts.size() >= MAX_CONTACTS: return result
			contacts[index] = true
			if not primary_active:
				primary_index = index
				primary_active = true
				orphan = false
				primary_position = event.position
		else:
			if not contacts.has(index): return result
			contacts.erase(index)
			if index == primary_index and not orphan:
				primary_position = event.position
				orphan = not contacts.is_empty()
			if contacts.is_empty():
				primary_active = false
				orphan = false
				primary_index = -1
				result.released = true
	else:
		if not contacts.has(index): return result
		if index == primary_index and not orphan: primary_position = event.position
	# Every accepted touchscreen update makes its shared Pointer current again.
	# Secondary motion/end never supplies its own position to the camera.
	position = primary_position
	known = true
	result.sample = true
	return result
