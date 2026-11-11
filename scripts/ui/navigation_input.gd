extends RefCounted
## Keep source Escape / gamepad-East cancellation available to native UI too.

static func ensure_cancel_bindings() -> void:
	if not InputMap.has_action("ui_cancel"):
		InputMap.add_action("ui_cancel")
	var escape := InputEventKey.new()
	escape.keycode = KEY_ESCAPE
	var east := InputEventJoypadButton.new()
	east.device = -1
	east.button_index = JOY_BUTTON_B
	for event in [escape, east]:
		if not InputMap.action_has_event("ui_cancel", event):
			InputMap.action_add_event("ui_cancel", event)

static func is_cancel_press(event: InputEvent) -> bool:
	# The default allow_echo=false rejects keyboard autorepeat; releases do not act.
	return event.is_action_pressed("ui_cancel")

static func enable_modal_cancel(dialog: ConfirmationDialog) -> void:
	# Godot's native popup dismissal accepts keyboard input only. Give gamepad
	# East the same cancel-button path, without accepting or bypassing the dialog.
	var callback: Callable = _modal_cancel_input.bind(dialog)
	if not dialog.window_input.is_connected(callback):
		dialog.window_input.connect(callback)

static func _modal_cancel_input(event: InputEvent, dialog: ConfirmationDialog) -> void:
	if not dialog.visible or not event is InputEventJoypadButton or not is_cancel_press(event): return
	dialog.get_cancel_button().pressed.emit()
	dialog.set_input_as_handled()
