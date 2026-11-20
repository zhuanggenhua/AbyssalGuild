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

# Source ButtonControl exposes independent pressed/released bits read by
# CameraController.Update. An up event on a button already up is not an edge.
var _physical_buttons: Dictionary = {}
var _left_pressed := false
var _middle_pressed := false
var _released := false

func take_pan_edges() -> Dictionary:
	var result := {"left_pressed":_left_pressed,"middle_pressed":_middle_pressed,"released":_released}
	_left_pressed=false
	_middle_pressed=false
	_released=false
	return result

func _observe_mouse_edge(event: InputEventMouseButton) -> void:
	var index := event.button_index
	if index not in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_MIDDLE]: return
	var was_pressed: bool = _physical_buttons.get(index,false)
	if event.pressed==was_pressed: return
	_physical_buttons[index]=event.pressed
	if not event.pressed:
		_released=true
	elif index==MOUSE_BUTTON_LEFT:
		_left_pressed=true
	else:
		_middle_pressed=true

func suppress_emulated_camera_event(event: InputEvent) -> bool:
	# Godot sends its touch-emulated mouse event BEFORE the corresponding touch.
	# Once a primary exists, only the actual touch event owns camera state/edges.
	return primary_active and event.device == -1 and (event is InputEventMouseButton or event is InputEventMouseMotion)

func observe(event: InputEvent) -> Dictionary:
	var result := {"sample": false, "released": false, "primary_pressed": false}
	if event is InputEventMouseButton or event is InputEventMouseMotion:
		# Fake touch-mouse input may precede native touch. It still belongs
		# to existing card/GUI routing, never the distinct Unity mouse.
		if event.device != InputEvent.DEVICE_ID_EMULATION and event.position.is_finite():
			if event is InputEventMouseButton: _observe_mouse_edge(event)
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
				result.primary_pressed = true
				_left_pressed = true
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
				_released = true
	else:
		if not contacts.has(index): return result
		if index == primary_index and not orphan: primary_position = event.position
	# Every accepted touchscreen update makes its shared Pointer current again.
	# Secondary motion/end never supplies its own position to the camera.
	position = primary_position
	known = true
	result.sample = true
	return result
