extends Control
## Original options presentation. Persistence and application are separate steps.
const MenuFocus = preload("res://scripts/ui/menu_focus.gd")
const UserOptions = preload("res://scripts/model/user_options.gd")
signal closed
var model = UserOptions.new()
var play_click: Callable
var adapter: Callable
var path: String = "user://options.json"
var dirty: bool = false
var load_warning: bool = false
var capabilities: Dictionary = {}
var status_label: Label
var buttons: Dictionary = {}
var sliders: Dictionary = {}
var volume_labels: Dictionary = {}
var reset_dialog: ConfirmationDialog
var last_application: Dictionary = {}
var focus_controls: Array = []
var restore_focus: WeakRef

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.04, 0.06, 0.9)
	add_child(shade)
	var panel := PanelContainer.new()
	panel.name = "OptionsSurface"
	panel.position = Vector2(420, 100)
	panel.size = Vector2(600, 700)
	add_child(panel)
	# The default panel is translucent. Keep the active settings readable when
	# the externally paused menu is still present beneath this overlay.
	var surface := panel.get_theme_stylebox("panel").duplicate() as StyleBoxFlat
	if surface == null:
		surface = StyleBoxFlat.new()
		surface.bg_color = Color(0.07, 0.08, 0.09)
	surface.bg_color.a = 1.0
	panel.add_theme_stylebox_override("panel", surface)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]: margin.add_theme_constant_override("margin_" + side, 24)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 12)
	margin.add_child(box)
	var heading := Label.new()
	heading.text = "OPTIONS"
	heading.add_theme_font_size_override("font_size", 28)
	box.add_child(heading)
	for channel in ["sfx", "bgm"]:
		var label := Label.new()
		box.add_child(label)
		volume_labels[channel] = label
		var slider := HSlider.new()
		slider.min_value = 0
		slider.max_value = 1
		slider.step = 0.01
		slider.value_changed.connect(_volume_changed.bind(channel))
		box.add_child(slider)
		sliders[channel] = slider
		focus_controls.append(slider)
	for key in ["resolution", "fullscreen", "vsync", "fps_cap", "shadow_preset"]:
		buttons[key] = _button(box, "", _cycle.bind(key))
	status_label = Label.new()
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.custom_minimum_size = Vector2(540, 110)
	box.add_child(status_label)
	_button(box, "Reset options…", _request_reset)
	_button(box, "Save & close", request_close)
	reset_dialog = ConfirmationDialog.new()
	reset_dialog.title = "Reset application options?"
	reset_dialog.dialog_text = "Restore audio and graphics preferences to their defaults? Saved games and campaign settings will not be changed."
	preload("res://scripts/ui/text_button_feedback.gd").bind_modal(reset_dialog, _confirm_reset, Callable(), _sound)
	add_child(reset_dialog)
	hide()

func _button(parent: Node, label: String, action: Callable) -> Button:
	var button := preload("res://scripts/ui/text_button_feedback.gd").new()
	button.text = label
	button.custom_minimum_size.y = 34
	button.configure(action, _sound, func(): return is_visible_in_tree() and not reset_dialog.visible)
	parent.add_child(button)
	focus_controls.append(button)
	return button

func configure(apply_adapter: Callable, hardware_modes: Array = [], save_path: String = "user://options.json") -> Dictionary:
	adapter = apply_adapter
	path = save_path
	var configured: Dictionary = model.configure(hardware_modes)
	if not configured.ok:
		status_label.text = str(configured.error)
		return configured
	var result: Dictionary = model.load_file(path)
	load_warning = not result.ok
	dirty = false
	last_application = model.apply_with(adapter)
	capabilities = last_application.get("capabilities", {})
	_refresh_controls()
	var summary: String = _application_summary()
	if not result.ok:
		status_label.text = "Invalid options file: defaults are in use; existing files were kept. Change a setting or confirm Reset to save new preferences.\n" + summary
	elif result.get("recovered", false):
		status_label.text = "Options recovered from backup; primary was not rewritten.\n" + summary
	else:
		status_label.text = summary
	return result

func open() -> void:
	if visible: return
	var previous := get_viewport().gui_get_focus_owner()
	restore_focus = weakref(previous) if previous != null else null
	_refresh_controls()
	show()
	MenuFocus.loop(focus_controls)
	sliders.sfx.grab_focus()

func _input(event: InputEvent) -> void:
	if visible and not reset_dialog.visible:
		MenuFocus.recover_navigation(event, focus_controls, get_viewport())

func _refresh_controls() -> void:
	for channel in sliders:
		var value: float = model.volume_slider(channel)
		sliders[channel].set_value_no_signal(value)
		volume_labels[channel].text = "%s · %d%%" % [channel.to_upper(), roundi(value * 100)]
	var values: Dictionary = model.values
	buttons.resolution.text = "Resolution · unavailable (no verified mode list)" if values.resolution.is_empty() else "Resolution · %d × %d" % [values.resolution[0], values.resolution[1]]
	buttons.resolution.disabled = model.resolutions.size() < 2
	buttons.resolution.tooltip_text = "Godot does not expose a portable full hardware-resolution list. No invented modes are offered." if buttons.resolution.disabled else "Cycle verified display modes"
	buttons.fullscreen.text = "Window · " + str(values.fullscreen).capitalize()
	buttons.fullscreen.disabled = not bool(capabilities.get("window_mode", false))
	buttons.vsync.text = "VSync · " + ["Off", "On", "Half (unsupported; not applied)"][int(values.vsync)]
	buttons.vsync.disabled = not bool(capabilities.get("vsync", false))
	buttons.fps_cap.text = "FPS · " + ("Unlimited" if int(values.fps_cap) == -1 else str(values.fps_cap)) + (" (overridden by VSync)" if int(values.vsync) != 0 else "")
	buttons.fps_cap.disabled = not bool(capabilities.get("fps_cap", false))
	buttons.shadow_preset.text = "Shadows · " + ["Off", "Low", "Medium", "High", "Ultra"][int(values.shadow_preset)] + (" (URP mapping unavailable)" if not capabilities.get("shadow_presets", false) else "")
	buttons.shadow_preset.disabled = not bool(capabilities.get("shadow_presets", false))
	if visible: MenuFocus.loop(focus_controls)

func _application_summary() -> String:
	if not last_application.get("ok", false): return "Application failed: " + str(last_application.get("error", "Unknown adapter error"))
	var warnings: Array = last_application.get("warnings", [])
	return "\n".join(warnings) if not warnings.is_empty() else "Supported options applied."

func _volume_changed(value: float, channel: String) -> void:
	var result: Dictionary = model.set_volume(channel, value)
	if not result.ok: status_label.text = str(result.error); return
	_apply_and_save()

func _cycle(key: String) -> void:
	if buttons.has(key) and buttons[key].disabled:
		status_label.text = "This control is unavailable: no verified application mapping."
		return
	var result: Dictionary = model.cycle(key)
	if not result.ok: status_label.text = str(result.error); return
	_apply_and_save()

func _apply_and_save() -> void:
	dirty = true
	last_application = model.apply_with(adapter)
	capabilities = last_application.get("capabilities", capabilities)
	_refresh_controls()
	var result: Dictionary = model.save_file(path)
	if result.ok:
		dirty = false
		load_warning = false
		status_label.text = "Preferences saved.\n" + _application_summary()
	else:
		status_label.text = "Preferences NOT saved: " + str(result.error) + ". Changes remain in this session; retry Save & close.\n" + _application_summary()

func request_close() -> void:
	# Invalid-file fallback is not an implicit request to overwrite evidence.
	if load_warning and not dirty:
		_finish_close()
		return
	var result: Dictionary = model.save_file(path)
	if not result.ok:
		dirty = true
		status_label.text = "Could not save options: " + str(result.error) + ". Options remain open."
		return
	dirty = false
	_finish_close()

func _finish_close() -> void:
	hide()
	MenuFocus.restore(restore_focus)
	restore_focus = null
	closed.emit()

func _request_reset() -> void:
	reset_dialog.popup_centered()

func _confirm_reset() -> void:
	model.reset_defaults()
	_apply_and_save()

func _sound() -> void:
	if play_click.is_valid(): play_click.call()
