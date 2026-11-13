extends Control
## Existing Range owns value and callbacks; this adapter owns source hit geometry.
const Metadata = preload("res://scripts/ui/source_control_metadata.gd")
const Tint = preload("res://scripts/ui/selectable_tint.gd")
var allowed: Callable
var model: Range
var metadata: Dictionary
var tint = Tint.new()
var background := ColorRect.new()
var fill := ColorRect.new()
var handle := ColorRect.new()
var dragging := false
var drag_offset := 0.0
var hovered := false
var last_time := 0
func bind(existing: Range, source: Dictionary) -> bool:
	if source.is_empty() or model != null: return false
	model = existing
	metadata = source
	model.add_child(self)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	model.self_modulate.a = 0
	model.mouse_filter = Control.MOUSE_FILTER_IGNORE
	model.focus_mode = Control.FOCUS_NONE
	focus_mode = Control.FOCUS_ALL
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	tint.configure(metadata.control.m_Colors)
	for node in [background, fill, handle]:
		add_child(node)
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.color = Metadata.color(metadata.background.image.m_Color)
	fill.color = Metadata.color(metadata.fill_image.m_Color)
	handle.color = Metadata.color(metadata.handle_image.m_Color)
	model.value_changed.connect(_value_changed)
	resized.connect(refresh)
	mouse_entered.connect(func(): hovered = true)
	mouse_exited.connect(func(): hovered = false)
	last_time = Time.get_ticks_msec()
	refresh()
	return true
func _value_changed(_value: float) -> void: refresh()
func refresh() -> void:
	if model == null or size.x <= 0: return
	var bg := Metadata.rectangle(metadata.background.rect, size)
	background.position = bg.position
	background.size = bg.size
	var fill_parent := Metadata.rectangle(metadata.fill_parent, size)
	var fill_rect: Dictionary = metadata.fill.duplicate(true)
	fill_rect.m_AnchorMin = {"x":0.0,"y":0.0}
	fill_rect.m_AnchorMax = {"x":1.0,"y":1.0}
	fill_rect.m_AnchorMax.x = normalized()
	var fr := Metadata.rectangle(fill_rect, fill_parent.size)
	fill.position = fill_parent.position + fr.position
	fill.size = fr.size
	var hp := Metadata.rectangle(metadata.handle_parent, size)
	var hr: Dictionary = metadata.handle.duplicate(true)
	hr.m_AnchorMin = {"x":normalized(),"y":0.0}
	hr.m_AnchorMax = {"x":normalized(),"y":1.0}
	hr.m_AnchorMax.x = normalized()
	var rect := Metadata.rectangle(hr, hp.size)
	handle.position = hp.position + rect.position
	handle.size = rect.size
func normalized() -> float: return 0.0 if model.max_value == model.min_value else (model.value-model.min_value)/(model.max_value-model.min_value)
func update_drag(point: Vector2) -> void:
	var track := Metadata.rectangle(metadata.handle_parent, size)
	var value := clampf((point.x-track.position.x-drag_offset)/track.size.x, 0, 1)
	var requested := lerpf(model.min_value, model.max_value, value)
	if bool(metadata.control.m_WholeNumbers): requested = roundf(requested)
	model.value = requested
func disabled() -> bool: return model is Slider and not model.editable
func _gui_input(event: InputEvent) -> void:
	if disabled() or (allowed.is_valid() and not allowed.call()): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		dragging = event.pressed
		if dragging:
			grab_focus()
			drag_offset = event.position.x - handle.position.x - handle.size.x/2 if Rect2(handle.position,handle.size).has_point(event.position) else 0.0
			update_drag(event.position)
		accept_event()
	elif event is InputEventMouseMotion and dragging:
		update_drag(event.position)
		accept_event()
	elif event.is_action_pressed("ui_left") or event.is_action_pressed("ui_right"):
		var step := 1.0 if bool(metadata.control.m_WholeNumbers) else (model.max_value-model.min_value)*0.1
		model.value += step * (-1 if event.is_action_pressed("ui_left") else 1)
		accept_event()
func _process(_delta: float) -> void:
	var now := Time.get_ticks_msec()
	tint.set_state("Disabled" if disabled() else ("Pressed" if dragging else ("Selected" if has_focus() else ("Highlighted" if hovered else "Normal"))))
	handle.color = Metadata.color(metadata.handle_image.m_Color) * tint.advance((now-last_time)/1000.0)
	last_time = now
