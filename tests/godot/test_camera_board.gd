extends SceneTree
class BoardAdapter extends "res://scripts/ui/board.gd":
	var hit := {"card_id":-1,"panel_owner":-1}
	func _pick_target(_point: Vector2) -> Dictionary: return hit
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_event: String) -> bool: return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = BoardAdapter.new()
	board.feedback.free(); board.feedback = SilentFeedback.new()
	var path := "user://camera-board-%d" % Time.get_ticks_usec()
	board.slot_root = path + "/slots"; board.options_path = path + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.start_new(); board.set_process(false)
	check(board.camera.fov == 30 and board.camera.near == 2 and board.camera.far == 40, "imported camera lens preserved")
	check(board.camera_motion.settings.panSpeed == 0.01 and board.camera_motion.settings.smoothTime == 0.15, "actual controller fields loaded")
	var start: Vector3 = board.camera.position
	board._zoom_camera(1)
	check(board.camera.position == start and board.camera_motion.target != start, "scroll updates target instead of teleporting camera")
	board.session.paused = true
	board._process(0.016)
	check(board.camera.position != start, "manual gameplay pause retains unscaled camera smoothing")
	for phase in ["feeding","ready","game_over"]:
		board.session.phase = phase
		var target: Vector3 = board.camera_motion.target
		var current: Vector3 = board.camera.position
		board._zoom_camera(1)
		board._process(0.1)
		check(board.camera_motion.target == target and board.camera.position == current, phase + " blocks zoom and ordinary camera smoothing")
	board.session.phase = "selling"
	var selling_target: Vector3 = board.camera_motion.target
	board._zoom_camera(1)
	check(board._camera_input_enabled() and board.camera_motion.target != selling_target, "selling removes cycle input lock for camera")
	board._handle_escape()
	check(not board.pause_overlay.visible, "selling still blocks Escape through ending-cycle flag")
	board.session.phase = "feeding"
	board._focus_camera_position(Vector3(2,0.4,3),0.5)
	var focus_end: Vector3 = board.camera_motion.focus.end
	board._process(0.5)
	check(board.camera.position.is_equal_approx(focus_end), "explicit focus runs during ending cycle")
	check(board.camera.position.is_equal_approx(Vector3(2,0.4,-3) + board.camera.global_basis.z*8), "focus reflects Z and retains source height")
	board.session.phase = "playing"
	board.pause_overlay.show()
	var current: Vector3 = board.camera.position
	board._zoom_camera(1); board._process(0.1)
	check(board.camera.position == current, "options pause blocks normal camera input")
	board.pause_overlay.hide()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	board._unhandled_input(press)
	check(board.panning, "empty board left press starts pan")
	var motion := InputEventMouseMotion.new(); motion.relative = Vector2(25,10)
	var target: Vector3 = board.camera_motion.target
	board._input(motion)
	check(board.camera_motion.target != target, "pan motion changes only target")
	press.pressed = false; board._input(press)
	check(not board.panning, "global release clears pan even if consumed by GUI")
	press.button_index = MOUSE_BUTTON_MIDDLE; press.pressed = true
	board._input(press)
	check(board.panning, "middle press handled before GUI consumption")
	board.hit.card_id = board.session.cards.keys()[0]
	press.button_index = MOUSE_BUTTON_LEFT
	board._unhandled_input(press)
	check(not board.panning, "card press cannot simultaneously pan and drag")
	board.dragging = -1; board.session.combat.dragged.clear()
	board.camera.h_offset = 0.07; board.camera.v_offset = -0.03
	board._update_camera_motion(0.016)
	check(is_equal_approx(board.camera.h_offset, 0.07) and is_equal_approx(board.camera.v_offset, -0.03), "motion helper leaves combat shake offsets independent")
	board._show_title()
	board.queue_free(); await process_frame; await create_timer(0.5).timeout
	print("Camera board checks: %d passed / %d total" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
