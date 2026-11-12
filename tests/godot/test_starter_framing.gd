extends SceneTree
## Synthetic source-free geometry, not an imported Starter or visual acceptance.
const Board = preload("res://scripts/ui/board.gd")
const SourceCamera = preload("res://scripts/ui/source_camera.gd")
const Layout = preload("res://scripts/model/board_layout.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
var checks := 0
var failures := 0

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)

func scene_fixture() -> Dictionary:
	# Numeric pose/lens facts audited at a11a89b; no private serialized file.
	return {"cameras": [{"resolved_pose": true, "orthographic": false,
		"field_of_view": 30.0, "near": 2.0, "far": 40.0, "fov_axis": 0,
		"transform_chain": [{"m_LocalPosition": {"x": 0, "y": 10, "z": -1},
		"m_LocalRotation": {"x": sin(deg_to_rad(42.5)), "y": 0, "z": 0, "w": cos(deg_to_rad(42.5))},
		"m_LocalScale": {"x": 1, "y": 1, "z": 1}}]}]}

func expected_projection(point: Vector2, size: Vector2) -> Vector2:
	# Independent Unity-space pinhole formula, not camera transform inversion.
	var pitch := deg_to_rad(85.0)
	var depth := 10.0 * sin(pitch) + (point.y + 1.0) * cos(pitch)
	var up := -10.0 * cos(pitch) + (point.y + 1.0) * sin(pitch)
	var half_height := depth * tan(deg_to_rad(15.0))
	return Vector2(size.x * 0.5 + point.x * size.y / (2.0 * half_height),
		size.y * 0.5 - up * size.y / (2.0 * half_height))

func button(index: MouseButton, pressed: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = pressed
	event.position = point
	event.global_position = point
	root.push_input(event)

func settle(board) -> void:
	for i in 120: board._update_camera_motion(1.0 / 60.0)

func fully_visible(camera: Camera3D, position: Vector2, size: Vector2) -> bool:
	var viewport := Rect2(Vector2.ZERO, camera.get_viewport().get_visible_rect().size)
	for x in [-0.6, 0.6]:
		for z in [-0.9, 0.9]:
			if not viewport.has_point(camera.unproject_position(Vector3(position.x + x, 0.04, -position.y - z))): return false
	return viewport.size.is_equal_approx(size)

func _init() -> void: call_deferred("run")

func run() -> void:
	root.gui_embed_subwindows = true
	# The imported runner preserves the real project canvas stretch settings.
	# This projection fixture owns logical viewport dimensions in both runners.
	root.content_scale_size = Vector2i.ZERO
	root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	var board = Board.new()
	var path := "user://starter-framing-%d" % Time.get_ticks_usec()
	board.options_path = path + "/options.json"
	board.slot_root = path + "/slots"
	board.legacy_paths.clear()
	board.options_apply_adapter = func(_plan): return {"ok": true, "capabilities": {}, "warnings": []}
	root.add_child(board)
	await process_frame
	board.set_process(false)
	board.catalog.configure({})
	board.session.configure(board.catalog)
	board.title_panel.hide()
	board.hud.hide() # Isolate board input, not HUD occlusion or UI usability.
	board.running = true
	board.session.phase = "playing"
	board.session.board_bounds = Rect2(-6, -4, 12, 8)
	# Synthetic 1.2x1.8 footprint; exercise source separation, not actual pack slots.
	var pack := Layout.stack_state(1, Vector2(-4.5, 0.6), Vector2(1.2, 1.8), 1, true)
	var states: Array = [pack]
	for id in [2, 3]:
		states.append(Layout.stack_state(id, pack.position, Vector2(1.2, 1.8), 1))
		states = Layout.resolve_overlaps(states, [], board.session.board_bounds).stacks
	check(states[0].position == pack.position, "locked pack stays at its edge fixture position")
	check(states[1].position.x < pack.position.x, "coincident output separates left under source rules")
	var position: Vector2 = states[1].position
	var card = CardView.new()
	card.configure(2, "Synthetic framing card", 1, false, null, {}, "Main", Vector3(1.2, 0.04, 1.8))
	board.add_child(card)
	card.position = Vector3(position.x, 0.04, -position.y)
	var original_pose: Vector3 = card.position
	await physics_frame
	await physics_frame
	for dimensions in [Vector2i(1440, 900), Vector2i(1233, 771)]:
		root.size = dimensions
		await process_frame
		var size := Vector2(dimensions)
		check(SourceCamera.apply(board.camera, scene_fixture()), "synthetic camera configuration accepted")
		board.camera_motion.configure(board.camera.position)
		for point in [Vector2.ZERO, Vector2(-4.5, 0.6), position, Vector2(2, -1)]:
			var actual: Vector2 = board.camera.unproject_position(Vector3(point.x, 0, -point.y))
			check(actual.distance_to(expected_projection(point, size)) < 0.01, "independent projection at %s for %s" % [dimensions, point])
		check(not fully_visible(board.camera, position, size), "edge output is initially cropped at %s" % dimensions)
		var center := size * 0.5
		button(MOUSE_BUTTON_MIDDLE, true, center)
		var motion := InputEventMouseMotion.new()
		motion.position = center + Vector2(350, 0)
		motion.relative = Vector2(350, 0)
		motion.button_mask = MOUSE_BUTTON_MASK_MIDDLE
		root.push_input(motion)
		button(MOUSE_BUTTON_MIDDLE, false, motion.position)
		settle(board)
		check(not board.panning and board.camera.position.x < -3.0, "Viewport middle pan moves left and releases")
		check(fully_visible(board.camera, position, size), "pan recovers whole synthetic card")
		check(board._pick(board.camera.unproject_position(card.position)) == 2, "recovered card is physics-pickable")
		SourceCamera.apply(board.camera, scene_fixture())
		board.camera_motion.configure(board.camera.position)
		for i in 6:
			button(MOUSE_BUTTON_WHEEL_DOWN, true, center)
			button(MOUSE_BUTTON_WHEEL_DOWN, false, center)
		settle(board)
		check(board.camera.position.y > 15.0, "Viewport wheel zoom increases distance")
		check(fully_visible(board.camera, position, size), "zoom recovers whole synthetic card")
		check(board._pick(board.camera.unproject_position(card.position)) == 2, "zoom-recovered card is physics-pickable")
		check(card.position == original_pose and states[1].position == position, "camera recovery never changes fixture positions")
	board.queue_free()
	await process_frame
	await create_timer(0.2).timeout
	print("Starter framing: %d/%d passed (synthetic, no private data or rendered acceptance)" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
