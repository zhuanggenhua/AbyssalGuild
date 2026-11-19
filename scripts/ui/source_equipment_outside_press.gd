extends RefCounted
## EquipmentPanel.Update 独立读取共享 Pointer 与实体射线，不是 GUI Click。
var _outside_press_pending := false
var _outside_mouse_down := false
var _outside_window_position := Vector2.ZERO


func observe(event: InputEvent, camera_sample: Dictionary, window_position: Vector2) -> void:
	if event.device == InputEvent.DEVICE_ID_EMULATION: return
	if event is InputEventMouse:
		if not event.position.is_finite(): return
		_outside_window_position = window_position
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			var down: bool = event.pressed and not event.canceled
			if down and not _outside_mouse_down: _outside_press_pending = true
			_outside_mouse_down = down
	elif camera_sample.sample:
		_outside_window_position = window_position
		if camera_sample.primary_pressed: _outside_press_pending = true


func take_press() -> Variant:
	if not _outside_press_pending: return null
	_outside_press_pending = false
	return _outside_window_position
