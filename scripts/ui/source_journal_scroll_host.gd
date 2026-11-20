extends Control
## Journal's active-but-CanvasGroup-hidden ScrollRect. Viewport has no scrollbar.
## Layout/padding belongs to content rows; position is the source Y-up offset.
var content := Control.new()
var background := ColorRect.new()
var motion = preload("res://scripts/ui/source_scrollrect_vertical.gd").new()
var tab_active := true
var pending_drag := false
var suppress_click := false
var press_screen := Vector2.ZERO
var drag_threshold := 10.0
var scroll_delta_per_tick := 6.0
var last_tick := 0
var source_scroll_bound := false
var source_pointer_managed := false
const PointerInput := preload("res://scripts/ui/source_journal_pointer_input.gd")

func configure_source_scroll(contract: Dictionary) -> bool:
	var scroll: Variant = contract.get("scroll")
	var admitted: bool = scroll is Dictionary and motion.configure(scroll)
	if not admitted:
		motion.configure({})
		if source_scroll_bound: reset_scroll()
	source_scroll_bound = admitted
	set_meta("scroll_layout_status", "source_vertical_rect" if admitted else "unverified_native_fallback")
	return admitted

func _init() -> void:
	clip_contents = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	process_mode = Node.PROCESS_MODE_ALWAYS
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.color = Color(0,0,0,0.9019608)
	add_child(background)
	content.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(content)
	resized.connect(_resize_viewport)

func _ready() -> void:
	last_tick = Time.get_ticks_usec()
	_resize_viewport()

func set_background(color: Color) -> void: background.color = color

func set_tab_active(active: bool) -> void:
	tab_active = active
	visible = active
	mouse_filter = Control.MOUSE_FILTER_STOP if active else Control.MOUSE_FILTER_IGNORE
	# CanvasGroup hides appearance/raycast, not an already captured pointer drag.
	# The admitted owner keeps receiving motion/release until the physical release.

func can_click() -> bool:
	return tab_active and is_visible_in_tree() and not suppress_click

func reset_scroll() -> void:
	motion.position = 0
	motion.previous = 0
	motion.velocity = 0
	motion.scrolling = false
	motion.end_drag()
	pending_drag = false
	suppress_click = false
	_apply_motion()

func set_content_height(height: float) -> void:
	if not is_finite(height): return
	content.size = Vector2(size.x,maxf(0,height))
	motion.content_height = content.size.y
	_resize_viewport()

func _resize_viewport() -> void:
	background.size = size
	content.size.x = size.x
	motion.viewport_height = size.y
	_apply_motion()

func _apply_motion() -> void: content.position = Vector2(0,-motion.position)

func advance_unscaled(dt: float) -> void:
	if not is_finite(dt) or dt < 0: return
	motion.step(dt)
	_apply_motion()

func _process(_delta: float) -> void:
	var now := Time.get_ticks_usec()
	var elapsed := (now-last_tick)/1000000.0
	last_tick = now
	advance_unscaled(elapsed)

func scroll_ticks(ticks: Vector2) -> void:
	if not ticks.is_finite() or ticks == Vector2.ZERO: return
	motion.wheel(ticks*scroll_delta_per_tick)
	_apply_motion()

func _gui_input(event: InputEvent) -> void:
	if not tab_active or not is_visible_in_tree(): return
	if event is InputEventMouseButton and event.pressed:
		var ticks := Vector2.ZERO
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP: ticks.y = event.factor
			MOUSE_BUTTON_WHEEL_DOWN: ticks.y = -event.factor
			MOUSE_BUTTON_WHEEL_LEFT: ticks.x = -event.factor
			MOUSE_BUTTON_WHEEL_RIGHT: ticks.x = event.factor
			MOUSE_BUTTON_LEFT:
				if source_pointer_managed and PointerInput.physical_mouse(event): return
				motion.initialize_drag()
				pending_drag = true
				suppress_click = false
				# GUI event coordinates are local, input coordinates are viewport pixels.
				press_screen = _physical_pointer(get_global_transform_with_canvas()*event.position)
		if ticks != Vector2.ZERO: scroll_ticks(ticks)
	# Board's source camera observes input separately before this GUI dispatch.

func _input(event: InputEvent) -> void:
	# The framed physical mouse route and touch-emulated capture cannot double run.
	if source_pointer_managed and PointerInput.physical_mouse(event): return
	# Only an admitted GUI press owns a drag. Rectangle tests here would bypass modals.
	if not pending_drag: return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		pending_drag = false
		motion.end_drag()
		# Keep suppression during this event's subsequent row click dispatch.
		call_deferred("_release_click_guard")
	elif event is InputEventMouseMotion:
		var local: Vector2 = get_global_transform_with_canvas().affine_inverse()*event.position
		var distance := press_screen.distance_to(_physical_pointer(event.position))
		# The viewport/physical round trip uses float vectors. An exact pixel
		# threshold may come back a few ULPs short under fractional scaling.
		if not motion.dragging and (distance >= drag_threshold or is_equal_approx(distance, drag_threshold)):
			motion.begin_drag(-local.y)
			suppress_click = true
		if motion.dragging:
			motion.drag(-local.y)
			_apply_motion()

func source_drag(kind: String, point: Vector2) -> void:
	var local: Vector2 = get_global_transform_with_canvas().affine_inverse()*point
	match kind:
		"initialize_drag": motion.initialize_drag()
		"begin_drag": motion.begin_drag(-local.y)
		"drag":
			motion.drag(-local.y)
			_apply_motion()
		"end_drag": motion.end_drag()

func _physical_pointer(viewport_position: Vector2) -> Vector2:
	return get_viewport().get_final_transform()*viewport_position

func _release_click_guard() -> void: suppress_click = false
