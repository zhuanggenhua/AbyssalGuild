extends SceneTree
class BoardAdapter extends "res://scripts/ui/board.gd":
	var hit := {"card_id":-1,"panel_owner":-1}
	func _pick_target(_point: Vector2) -> Dictionary: return hit
class WheelPanel extends Control:
	var wheels := 0
	func _gui_input(event: InputEvent) -> void:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_WHEEL_UP:
			wheels += 1
			accept_event()
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_event: String) -> bool: return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",label)
func _init() -> void: call_deferred("run")
func sample(board: Node, factor:=1.0, index:=MOUSE_BUTTON_WHEEL_UP) -> void:
	var wheel := InputEventMouseButton.new()
	wheel.factor=factor;wheel.button_index=index;wheel.pressed=true
	board._input(wheel)
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
	sample(board)
	check(board.camera.position == start and board.camera_motion.target == start, "wheel is sampled without teleporting or precommitting the target")
	board.session.paused = true
	board._process(0.016)
	check(board.camera.position != start and board.camera_motion.target != start, "manual gameplay pause applies wheel and retains unscaled smoothing")
	for phase in ["feeding","ready","game_over"]:
		board.session.phase = phase
		var target: Vector3 = board.camera_motion.target
		var current: Vector3 = board.camera.position
		sample(board)
		board._process(0.1)
		check(board.camera_motion.target == target and board.camera.position == current, phase + " blocks zoom and ordinary camera smoothing")
	board.session.phase = "selling"
	var selling_target: Vector3 = board.camera_motion.target
	sample(board); board._update_camera_motion(0.016)
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
	sample(board); board._process(0.1)
	check(board.camera.position != current, "source external pause retains normal unscaled camera input")
	board.pause_overlay.hide()
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT; press.pressed = true
	board._input(press); board._unhandled_input(press)
	check(not board.panning,"input receipt does not mutate camera before Update")
	board._update_camera_motion(.016)
	check(board.panning, "empty board left press starts pan")
	var motion := InputEventMouseMotion.new(); motion.relative = Vector2(25,10); motion.position = Vector2(25,10)
	var target: Vector3 = board.camera_motion.target
	board._input(motion); board._update_camera_motion(.016)
	check(board.camera_motion.target != target, "pan motion changes only target")
	press.pressed = false; board._input(press); board._update_camera_motion(.016)
	check(not board.panning, "global release clears pan even if consumed by GUI")
	press.button_index = MOUSE_BUTTON_MIDDLE; press.pressed = true
	board._input(press); board._update_camera_motion(.016)
	check(board.panning, "middle press handled before GUI consumption")
	press.pressed = false; board._input(press); board._update_camera_motion(.016)
	press.pressed = true
	board.hit.card_id = board.session.cards.keys()[0]
	press.button_index = MOUSE_BUTTON_LEFT
	board._input(press); board._unhandled_input(press); board._update_camera_motion(.016)
	check(not board.panning, "card press cannot simultaneously pan and drag")
	board.dragging = -1; board.session.combat.dragged.clear()
	press.pressed=false; board._input(press); board._update_camera_motion(.016)
	board.hit.card_id=-1
	board.camera.h_offset = 0.07; board.camera.v_offset = -0.03
	board._update_camera_motion(0.016)
	check(is_equal_approx(board.camera.h_offset, 0.07) and is_equal_approx(board.camera.v_offset, -0.03), "motion helper leaves combat shake offsets independent")
	# Real viewport delivery: source camera sees wheel before a GUI consumer.
	var panel := WheelPanel.new()
	panel.position = Vector2(10,10); panel.size = Vector2(200,200)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	board.hud.add_child(panel)
	panel.move_to_front()
	var hover := InputEventMouseMotion.new(); hover.position = Vector2(40,40)
	root.push_input(hover,true)
	var wheel := InputEventMouseButton.new()
	wheel.position = Vector2(40,40); wheel.button_index = MOUSE_BUTTON_WHEEL_UP; wheel.pressed = true
	board.camera_motion.configure(Vector3(0,12,6))
	board._clamp_camera()
	var before_wheel: Vector3 = board.camera_motion.target
	root.push_input(wheel,true)
	check(panel.wheels == 1 and board.camera_motion.target == before_wheel,"GUI consumes wheel without immediate camera mutation")
	board._update_camera_motion(.016)
	check(board.camera_motion.target != before_wheel,"one camera frame still applies the GUI-consumed wheel")
	var once: Vector3 = board.camera_motion.target
	board._unhandled_input(wheel)
	check(board.camera_motion.target == once,"wheel is not dispatched twice through unhandled path")
	board.pause_overlay.show()
	board._input(wheel); board._update_camera_motion(.016)
	check(board.camera_motion.target != once,"pause menu does not create an input lock")
	press.button_index = MOUSE_BUTTON_MIDDLE; press.pressed = true; press.position = Vector2(40,40)
	board._input(press); board._update_camera_motion(.016)
	motion.position = Vector2(50,50)
	target = board.camera_motion.target
	board._input(motion); board._update_camera_motion(.016)
	check(board.panning and board.camera_motion.target != target,"pause middle-pan bypasses GUI")
	board.session.phase = "feeding"
	board.vendor_unlock.sequence.stage = "hold"
	target = board.camera_motion.target
	board._input(wheel)
	board.session.phase = "selling"
	board._input(wheel)
	check(board.camera_motion.target == target and not board._camera_input_enabled(),"releasing day lock cannot release vendor lock")
	board.vendor_unlock.sequence.stage = "idle"
	check(board._camera_input_enabled(),"last input lock removed even while menu pause remains")
	# Source Update skips HandlePan entirely while locked: neither reset nor release.
	board.session.phase = "feeding"
	press.pressed = false
	board._input(press)
	motion.position = Vector2(80,90)
	board._input(motion); board._update_camera_motion(.016)
	check(board.panning and board.camera_motion.target == target,"lock preserves drag state and skips release/movement")
	board.session.phase = "playing"
	board._update_camera_motion(.016)
	check(board.camera_motion.target != target,"unlock samples accumulated source dragOrigin delta")
	board._input(press); board._update_camera_motion(.016)
	check(board.panning,"duplicate up cannot manufacture an unlocked release")
	press.pressed=true; board._input(press)
	press.pressed=false; board._input(press); board._update_camera_motion(.016)
	check(not board.panning,"new physical pair has independent press/release bits, release wins")
	# Near the source minimum, opposite detents must cancel before either
	# step can constrain the target. A per-event implementation fails this.
	board.pause_overlay.hide()
	var facing: Vector3 = -board.camera.global_basis.z
	board.camera_motion.configure(-facing*5.25)
	board._clamp_camera()
	var original: Vector3 = board.camera_motion.target
	sample(board,.5); sample(board,.5,MOUSE_BUTTON_WHEEL_DOWN)
	board._update_camera_motion(.016)
	check(board.camera_motion.target==original,"same-frame +/- rejects order-dependent intermediate zoom")
	board.camera_motion.configure(-facing*5.25)
	original=board.camera_motion.target
	sample(board,.17); sample(board,.17)
	board._update_camera_motion(.016)
	check(board.camera_motion.target==original,"two acceptable individual ticks form one rejected oversize step")
	board.camera_motion.configure(-facing*10.)
	board._clamp_camera()
	original=board.camera_motion.target
	sample(board,.006); sample(board,.006); sample(board,4.,MOUSE_BUTTON_WHEEL_RIGHT); sample(board,NAN)
	board._update_camera_motion(.016)
	var committed: Vector3 = board.camera_motion.target
	check(committed.is_equal_approx(original+facing*.012),"two sub-threshold ticks accumulate; horizontal and NaN ignored")
	board._update_camera_motion(.016)
	check(board.camera_motion.target==committed,"wheel reset next frame")
	sample(board)
	board.session.phase="feeding"
	board._update_camera_motion(.016)
	board.session.phase="playing"
	board._update_camera_motion(.016)
	check(board.camera_motion.target==committed,"frame-time lock discards pending ordinary wheel")
	# Wheel arrives before the motion event, but source Update pans first.
	board.camera_motion.configure(-facing*10.)
	board._clamp_camera()
	var far_edge: float = board.camera_motion.bounds.end.y+float(board.camera_motion.settings.panPadding)
	board.camera_motion.target.z=far_edge-0.05
	var to_viewport := root.get_final_transform().affine_inverse()
	press.button_index=MOUSE_BUTTON_MIDDLE; press.pressed=true; press.position=to_viewport*Vector2(40,90)
	board._input(press); board._update_camera_motion(.016)
	sample(board,.5)
	motion.position=to_viewport*Vector2(40,10)
	board._input(motion)
	check(is_equal_approx(board.camera_motion.target.z,far_edge-.05),"motion and wheel do not mutate target before Update")
	board._update_camera_motion(.016)
	check(is_equal_approx(board.camera_motion.target.z,far_edge+facing.z*.5),
		"real camera Update zooms inward after clamped pan even when wheel event arrived first")
	press.pressed=false; board._input(press)
	# Deliberately batch several receipts without drawing a camera frame.
	press.pressed=false; board._input(press); board._update_camera_motion(.016)
	board.camera.position=Vector3(0,10,1)
	board.camera_motion.configure(board.camera.position)
	board._clamp_camera()
	var x_min: float=board.camera_motion.bounds.position.x-float(board.camera_motion.settings.panPadding)
	board.camera_motion.target.x=x_min+.25
	var batch: Vector3=board.camera_motion.target
	var pointer_base := Vector2(520,360)
	press.position=to_viewport*pointer_base
	press.pressed=true; board._input(press)
	motion.position=to_viewport*(pointer_base+Vector2(15,0))
	board._input(motion); board._update_camera_motion(.016)
	check(board.panning and board.camera_drag_origin.is_equal_approx(pointer_base+Vector2(15,0))
		and board.camera_motion.target==batch,"down plus motion shares final origin and cannot move in its first frame")
	motion.position=to_viewport*(pointer_base+Vector2(300,0)); board._input(motion)
	motion.position=to_viewport*(pointer_base+Vector2(15,0)); board._input(motion)
	board._update_camera_motion(.016)
	check(board.camera_motion.target==batch,"opposing motion across a clamp has no boundary ratchet")
	motion.position=to_viewport*(pointer_base+Vector2(45,0)); board._input(motion)
	press.position=motion.position; press.pressed=false; board._input(press)
	board._update_camera_motion(.016)
	check(not board.panning and board.camera_motion.target==batch,"held movement with release is ignored even if movement arrived first")
	press.button_index=MOUSE_BUTTON_LEFT; press.pressed=true; press.position=to_viewport*pointer_base
	board._input(press); board._update_camera_motion(.016)
	check(board.panning,"physical left independently holds a blank frame")
	var middle: InputEventMouseButton = press.duplicate()
	middle.button_index=MOUSE_BUTTON_MIDDLE
	press.pressed=false; board._input(press); board._input(middle)
	board._update_camera_motion(.016)
	check(not board.panning,"left release wins even if middle-down was later in the same frame")
	middle.pressed=false; board._input(middle); board._update_camera_motion(.016)
	middle.pressed=true; board._input(middle)
	board._update_camera_motion(.016)
	board._focus_camera_position(Vector3(1,0,1),.1)
	check(not board.panning and board.camera_drag_origin.is_equal_approx(board.camera_pointer.position),
		"explicit source focus clears drag and resamples its current physical origin")
	middle.pressed=false; board._input(middle); board._update_camera_motion(.016)
	board.scene_transition.phase = "out"
	check(not board._camera_input_enabled(),"scene transition retains independent input lock")
	board.scene_transition.cancel()
	panel.queue_free()
	board.pause_overlay.hide()
	board._show_title()
	board.queue_free(); await process_frame; await create_timer(0.5).timeout
	print("Camera board checks: %d passed / %d total" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
