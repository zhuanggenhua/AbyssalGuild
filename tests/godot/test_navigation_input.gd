extends SceneTree
const NavigationInput = preload("res://scripts/ui/navigation_input.gd")
var checks: int = 0
var failures: int = 0

func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)

func key(code: Key, pressed: bool = true, echo: bool = false) -> InputEventKey:
	var event := InputEventKey.new()
	event.keycode = code
	event.pressed = pressed
	event.echo = echo
	return event

func joy(button: JoyButton, pressed: bool = true, device: int = 0) -> InputEventJoypadButton:
	var event := InputEventJoypadButton.new()
	event.button_index = button
	event.pressed = pressed
	event.device = device
	return event

func _init() -> void:
	call_deferred("run")

func run() -> void:
	# The isolated pinned engine currently supplies Escape only. Do not depend on
	# that omission: future engine defaults may already contain the East binding.
	var existing: Array[InputEvent] = InputMap.action_get_events("ui_cancel")
	var unrelated: Array[InputEvent] = InputMap.action_get_events("ui_accept")
	NavigationInput.ensure_cancel_bindings()
	var count: int = InputMap.action_get_events("ui_cancel").size()
	NavigationInput.ensure_cancel_bindings()
	check(InputMap.action_get_events("ui_cancel").size() == count, "repeated setup does not duplicate bindings")
	for event in existing:
		check(InputMap.action_has_event("ui_cancel", event), "existing cancel binding is preserved")
	check(InputMap.action_get_events("ui_accept") == unrelated, "other native UI actions are untouched")
	check(NavigationInput.is_cancel_press(key(KEY_ESCAPE)), "Escape press cancels")
	check(not NavigationInput.is_cancel_press(key(KEY_ESCAPE, false)), "Escape release does not cancel")
	check(not NavigationInput.is_cancel_press(key(KEY_ESCAPE, true, true)), "Escape key echo does not cancel")
	check(not NavigationInput.is_cancel_press(key(KEY_SPACE)), "selected-pace key is not cancel")
	for device in [0, 1, 7]:
		check(NavigationInput.is_cancel_press(joy(JOY_BUTTON_B, true, device)), "gamepad East press cancels for device %d" % device)
		check(not NavigationInput.is_cancel_press(joy(JOY_BUTTON_B, false, device)), "gamepad East release does not cancel for device %d" % device)
	check(not NavigationInput.is_cancel_press(joy(JOY_BUTTON_A)), "gamepad South is not cancel")
	var custom := key(KEY_F10)
	InputMap.action_add_event("ui_cancel", custom)
	NavigationInput.ensure_cancel_bindings()
	check(NavigationInput.is_cancel_press(custom), "an existing custom cancel mapping is honored")
	InputMap.action_erase_event("ui_cancel", custom)
	# No fake game or licensed data is required to test actual native modal routing.
	root.gui_embed_subwindows = true
	var dialog := ConfirmationDialog.new()
	root.add_child(dialog)
	var results := {"accepted": 0, "canceled": 0}
	dialog.confirmed.connect(func(): results.accepted += 1)
	dialog.canceled.connect(func(): results.canceled += 1)
	NavigationInput.enable_modal_cancel(dialog)
	NavigationInput.enable_modal_cancel(dialog)
	for event in [key(KEY_ESCAPE), joy(JOY_BUTTON_B)]:
		dialog.popup_centered()
		await process_frame
		for ignored in [key(KEY_ESCAPE, false), key(KEY_ESCAPE, true, true), joy(JOY_BUTTON_B, false)]:
			root.push_input(ignored)
		await process_frame
		check(dialog.visible and results.accepted == 0, "modal ignores releases and keyboard echo")
		root.push_input(event)
		await process_frame
		check(not dialog.visible and results.accepted == 0, "native modal cancel closes without accepting")
		root.push_input(event)
	check(results.canceled == 2, "both keyboard and gamepad emit native canceled signal exactly once")
	dialog.queue_free()
	await process_frame
	print("Navigation input checks: %d passed / %d total" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
