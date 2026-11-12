extends RefCounted
## Native keyboard/controller focus stays in the active overlay, without changing bindings.

static func eligible(control: Control) -> bool:
	return is_instance_valid(control) and not control.is_queued_for_deletion() and control.is_visible_in_tree() and control.focus_mode != Control.FOCUS_NONE and (not control is BaseButton or not control.disabled)

static func loop(controls: Array) -> Array:
	var available: Array = []
	for control in controls:
		if eligible(control): available.append(control)
	for index in available.size():
		var control: Control = available[index]
		var previous: NodePath = control.get_path_to(available[(index - 1 + available.size()) % available.size()])
		var following: NodePath = control.get_path_to(available[(index + 1) % available.size()])
		control.focus_previous = previous
		control.focus_next = following
		control.focus_neighbor_top = previous
		control.focus_neighbor_bottom = following
		control.focus_neighbor_left = control.get_path_to(control)
		control.focus_neighbor_right = control.get_path_to(control)
	return available

static func restore(reference: WeakRef, fallback: Control = null) -> void:
	var control = reference.get_ref() if reference != null else null
	if control is Control and eligible(control): control.grab_focus()
	elif fallback != null and eligible(fallback): fallback.grab_focus()

static func recover_navigation(event: InputEvent, controls: Array, viewport: Viewport) -> bool:
	var backward: bool = event.is_action_pressed("ui_focus_prev") or event.is_action_pressed("ui_up")
	var forward: bool = event.is_action_pressed("ui_focus_next") or event.is_action_pressed("ui_down")
	if not backward and not forward: return false
	var available: Array = loop(controls)
	if available.is_empty() or available.has(viewport.gui_get_focus_owner()): return false
	# If a popup/window change cleared focus, native traversal must not restart
	# at an unrelated HUD control behind this overlay.
	var target: Control = available.back() if backward else available.front()
	target.grab_focus()
	viewport.set_input_as_handled()
	return true
