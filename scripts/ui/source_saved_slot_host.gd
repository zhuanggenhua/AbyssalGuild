extends Control
## Source vertical Elastic motion and source-backed flat-image scrollbar.
const Slot = preload("res://scripts/ui/source_saved_slot.gd")
const Layout = preload("res://scripts/ui/source_saved_layout.gd")
const Bridge = preload("res://scripts/ui/saved_slot_callback_bridge.gd")
const Focus = preload("res://scripts/ui/menu_focus.gd")
var content := Control.new()
var rows: Array = []
var source: Dictionary
var bridge = Bridge.new()
var padding := Vector4.ZERO
var spacing := 0.0
var play_click: Callable
var font_resolver: Callable
var footer_controls: Array = []
var status := "source_vertical_elastic_source_scrollbar"
var motion = preload("res://scripts/ui/source_scrollrect_vertical.gd").new()
var bar = preload("res://scripts/ui/source_scrollbar_adapter.gd").new()
var clip := Control.new()
var pending_drag := false
var press_screen := Vector2.ZERO
var suppress_click := false
var transaction_guard: Callable
var last_tick := 0
var drag_threshold := 10.0
var scroll_delta_per_tick := 1.0
func get_v_scroll_bar() -> Control: return bar
func _admitted() -> bool:
	return is_visible_in_tree() and not suppress_click and (not transaction_guard.is_valid() or transaction_guard.call())
func configure(documents: Array, content_fields: Dictionary, selector: OptionButton, load_action: Callable, archive_action: Callable, guard: Callable) -> bool:
	source = Slot.metadata(documents)
	if source.is_empty(): return false
	var p: Dictionary = content_fields.get("m_Padding",{})
	padding = Vector4(float(p.get("m_Left",0)),float(p.get("m_Top",0)),float(p.get("m_Right",0)),float(p.get("m_Bottom",0)))
	spacing = float(content_fields.get("m_Spacing",0))
	bridge.selector = selector
	bridge.load_action = load_action
	bridge.archive_action = archive_action
	transaction_guard = guard
	bridge.allowed = _admitted
	if not motion.configure(content_fields.get("scrollrect",{})): return false
	drag_threshold = float(content_fields.get("drag_threshold",10))
	scroll_delta_per_tick = float(content_fields.get("scroll_delta_per_tick",1))
	clip.clip_contents = true
	clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(clip)
	add_child(bar)
	bar.custom_minimum_size.x = float(content_fields.get("scrollbar_width",0))
	if not bar.configure(content_fields.get("scrollbar",{}),_admitted): return false
	bar.value_changed.connect(func(value): motion.set_normalized(value); _apply_motion())
	clip.add_child(content)
	last_tick = Time.get_ticks_usec()
	resized.connect(relayout)
	return true
func sync(entries: Array) -> void:
	var previous_slot := -1
	var previous_archive := false
	var focused := get_viewport().gui_get_focus_owner()
	for row in rows:
		if focused == row.load_button or focused == row.archive_button:
			previous_slot = row.slot_id
			previous_archive = focused == row.archive_button
		row.hide()
		row.queue_free()
	rows.clear()
	for entry in entries:
		var row = Slot.new()
		row.play_click = play_click
		row.font_resolver = font_resolver
		content.add_child(row)
		if not row.configure(entry,source,func(id): bridge.request(id,false),func(id): bridge.request(id,true),bridge.allowed):
			row.queue_free()
			continue
		rows.append(row)
	relayout()
	update_focus()
	for row in rows:
		if row.slot_id == previous_slot:
			var target: Control = row.archive_button if previous_archive else row.load_button
			if Focus.eligible(target): target.grab_focus()
func relayout() -> void:
	if source.is_empty(): return
	var heights: Array = []
	for row in rows: heights.append(row.custom_minimum_size.y)
	var clip_width := maxf(0,size.x-bar.custom_minimum_size.x)
	var result := Layout.rows(clip_width,heights,padding,spacing)
	clip.size = Vector2(clip_width,size.y)
	bar.position = Vector2(clip.size.x,0)
	bar.size = Vector2(bar.custom_minimum_size.x,size.y)
	content.size = Vector2(clip.size.x,result.preferred_height)
	motion.viewport_height = clip.size.y
	motion.content_height = content.size.y
	_apply_motion()
	for index in rows.size():
		rows[index].position = result.rectangles[index].position
		rows[index].size = result.rectangles[index].size

func update_focus() -> void:
	var ring: Array = []
	for row in rows: ring.append_array([row.load_button,row.archive_button])
	ring.append_array(footer_controls)
	Focus.loop(ring)

func _apply_motion() -> void:
	content.position.y = -motion.position
	bar.sync(motion.normalized(),motion.bar_fraction())

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var elapsed := (now-last_tick)/1000000.0
	last_tick = now
	if not is_visible_in_tree():
		motion.end_drag()
		motion.velocity = 0
		motion.scrolling = false
		suppress_click = false
		pending_drag = false
		return
	motion.step(elapsed)
	_apply_motion()
func _input(event: InputEvent) -> void:
	if not is_visible_in_tree() or (transaction_guard.is_valid() and not transaction_guard.call()): return
	if event is InputEventMouseButton:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse()*event.position
		var inside := Rect2(Vector2.ZERO,size).has_point(local) and not bar._has_point(local-bar.position)
		if event.pressed and Rect2(Vector2.ZERO,size).has_point(local) and event.button_index in [MOUSE_BUTTON_WHEEL_UP,MOUSE_BUTTON_WHEEL_DOWN,MOUSE_BUTTON_WHEEL_LEFT,MOUSE_BUTTON_WHEEL_RIGHT]:
			var delta := Vector2.ZERO
			if event.button_index == MOUSE_BUTTON_WHEEL_UP: delta.y = event.factor
			if event.button_index == MOUSE_BUTTON_WHEEL_DOWN: delta.y = -event.factor
			if event.button_index == MOUSE_BUTTON_WHEEL_LEFT: delta.x = -event.factor
			if event.button_index == MOUSE_BUTTON_WHEEL_RIGHT: delta.x = event.factor
			motion.wheel(delta*scroll_delta_per_tick)
			_apply_motion()
			# Do not accept: source camera reads wheel even when pointer is over UI.
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed and inside:
				motion.initialize_drag()
				pending_drag = true
				press_screen = event.position
			elif not event.pressed:
				pending_drag = false
				motion.end_drag()
				call_deferred("_release_click_guard")
	elif event is InputEventMouseMotion and pending_drag:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse()*event.position
		if not motion.dragging and press_screen.distance_squared_to(event.position) >= drag_threshold*drag_threshold:
			# StandaloneInputModule begins drag at current cursor, then invokes OnDrag.
			motion.begin_drag(-local.y)
			suppress_click = true
		if motion.dragging:
			motion.drag(-local.y)
			_apply_motion()
func _release_click_guard() -> void: suppress_click = false
