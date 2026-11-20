extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_event: String) -> bool: return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL ", label)

func press(button: MouseButton, down: bool, point: Vector2, factor := 1.0) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = button
	event.pressed = down
	event.position = point
	event.factor = factor
	root.push_input(event, true)

func motion(point: Vector2) -> void:
	var event := InputEventMouseMotion.new()
	event.position = point
	root.push_input(event, true)

func portal(b) -> void:
	var id: int = b.session.spawn_card(b.catalog.find_by_name("Grand Portal"),Vector2(3,0),-1,{"refuse_attach":true})
	var worker: int = b.session.spawn_card(b.catalog.find_by_name("Villager"),Vector2(4,0),-1,{"refuse_attach":true})
	check(b.session.move_to_stack(worker,b.session.cards[id].stack_id),"portal assembled")
	check(b.session.crafting.advance(5) and b.session.travel_pending,"original travel starts")

func clean(b) -> void:
	b.vendor_unlock.cancel()
	b.session.cycle.reset()
	b.session.phase = "playing"
	b.session.paused = false
	b.pause_overlay.hide()
	b.options_panel.hide()
	b.session.elapsed = 0
	for id in b.session.cards.keys(): b.session._remove_card(id)
	b.session.spawn_target_selector = Callable()
	b.session.spawn_layout_resolver = Callable()
	b._sync_views()

func guard_inputs(b, point: Vector2) -> void:
	for mode in ["menu","options","vendor","cycle","drag","focus","unverified"]:
		var source_commit: String = b.catalog.data.provenance.source_commit
		match mode:
			"menu": b.pause_overlay.show()
			"options": b.options_panel.show()
			"vendor": b.vendor_unlock.sequence.stage = "hold"
			"cycle": b.session.phase = "feeding"
			"drag": b.dragging = 999
			"focus": b.camera_motion.focus = {"start":Vector3.ZERO,"end":Vector3.ONE,"duration":1.0,"elapsed":0.0}
			"unverified": b.catalog.data.provenance.source_commit = "unknown"
		var before: Vector3 = b.camera_motion.target
		press(MOUSE_BUTTON_WHEEL_UP,true,point,.5)
		press(MOUSE_BUTTON_MIDDLE,true,point)
		b._update_camera_motion(0)
		check(b.camera_motion.target == before and not b.panning,mode+" guards wheel and new middle edge")
		press(MOUSE_BUTTON_MIDDLE,false,point); b._update_camera_motion(0)
		b.pause_overlay.hide()
		b.options_panel.hide()
		b.vendor_unlock.sequence.stage = "idle"
		b.session.phase = "playing"
		b.dragging = -1
		b.camera_motion.focus.clear()
		b.catalog.data.provenance.source_commit = source_commit

func run() -> void:
	for scene in ["Main","Island"]:
		var b := Board.new()
		b.feedback.free()
		b.feedback = SilentFeedback.new()
		var dir := "user://fade-camera-%d" % Time.get_ticks_usec()
		b.slot_root = dir+"/slots"
		b.options_path = dir+"/options"
		b.legacy_paths.clear()
		root.add_child(b)
		await process_frame
		b.start_new(); b.set_process(false); clean(b)
		if scene == "Island":
			portal(b); b._process(1); b._process(1); clean(b)
		check(b.session.scene_name == scene,"active locked source scene")
		var zero := Vector3(0,12,1)
		b.camera.position = zero
		b.camera_motion.configure(zero)
		b._clamp_camera()
		var point := Vector2.ZERO
		for uv in [Vector2(.44,.45), Vector2(.50,.36), Vector2(.60,.12), Vector2(.3,.6),Vector2(.55,.3)]:
			point = root.get_visible_rect().size * uv
			motion(point)
			if not b._camera_left_blocked(): break
		var transform: Transform2D = root.get_final_transform()
		var forward := -b.camera.global_basis.z
		var world_pixel := float(b.camera_motion.settings.panSpeed) * zero.y / 10.0
		motion(point)
		check(not b._camera_left_blocked(),"blank viewport point before the fader")
		press(MOUSE_BUTTON_LEFT,true,point); b._update_camera_motion(0)
		check(b.panning,"left pan captured in the real old viewport")
		press(MOUSE_BUTTON_WHEEL_UP,true,point,.25)
		check(b.camera_motion.target==zero,"pre-fade wheel waits for camera Update")
		portal(b)
		press(MOUSE_BUTTON_WHEEL_UP,true,point,.25)
		check(is_equal_approx(b._camera_scroll_sample,.5),"same-owner wheel spans start of fade as one dynamic frame")
		var owner = b.session
		var saved: Dictionary = Codec.capture(owner)
		check(b.panning and not b._camera_input_enabled() and b.scene_transition.blocks_input(),"portal keeps already-started camera pan but not broad input")
		var moved := point + Vector2(20,0)
		motion(moved)
		var pixels := transform * moved - transform * point
		var expected := zero + Vector3(-pixels.x,0,-pixels.y)*world_pixel + forward*.5
		b._process(.1)
		check(b.panning and b.camera_motion.target.is_equal_approx(expected) and b.camera.position != zero,
			"captured pan survives portal and shares the real outgoing camera frame")
		check(b.session==owner and is_equal_approx(b.scene_transition.alpha,.1) and Codec.capture(owner)==saved,
			"old owner and saved model unchanged through early fade")

		var before: Vector3 = b.camera_motion.target
		var settled: Vector3 = b.camera.position
		moved += Vector2(24,0)
		motion(moved)
		press(MOUSE_BUTTON_LEFT,false,moved)
		press(MOUSE_BUTTON_WHEEL_UP,true,moved,.5)
		b._process(.1)
		check(not b.panning and b.camera_motion.target.is_equal_approx(before+forward*.5),
			"release cancels final drag sample before wheel, but not zoom")
		check(b.camera.position!=settled,"release does not freeze outgoing damping")

		before = b.camera_motion.target
		press(MOUSE_BUTTON_LEFT,true,point)
		motion(moved)
		b._process(.1)
		check(not b.panning and b.camera_motion.target==before and b.dragging<0
			and not b._text_button_allowed(b.day_clock),"fade raycast blocks fresh left, card and HUD")
		press(MOUSE_BUTTON_LEFT,false,moved); b._update_camera_motion(0)
		press(MOUSE_BUTTON_MIDDLE,true,point)
		motion(moved)
		b._process(.1)
		check(b.panning and b.camera_drag_origin.is_equal_approx(transform*moved)
			and b.camera_motion.target==before,"fresh middle bypasses fader and uses final sample as unchanged origin")

		# Force a boundary on the old board: incoming wheel is processed AFTER
		# the final pan clamp, despite having arrived before movement.
		var bounds: Rect2 = b.camera_motion.bounds
		var padding := float(b.camera_motion.settings.panPadding)
		var direction := -signf(forward.z)
		var edge: float = bounds.end.y+padding if direction>0 else bounds.position.y-padding
		b.camera_motion.target.z = edge-direction*.04
		press(MOUSE_BUTTON_WHEEL_UP,true,moved,.5)
		moved += transform.affine_inverse().basis_xform(Vector2(0,-direction*8))
		motion(moved)
		b._process(.1)
		check(b.panning and is_equal_approx(b.camera_motion.target.z,edge+forward.z*.5),
			"simultaneous pan clamps first; signed wheel then moves inward")
		before = b.camera_motion.target
		moved += Vector2(24,0)
		motion(moved)
		press(MOUSE_BUTTON_LEFT,true,moved); press(MOUSE_BUTTON_LEFT,false,moved)
		b._process(.1)
		check(not b.panning and b.camera_motion.target==before,"left release stops a held middle pan before final movement")
		press(MOUSE_BUTTON_MIDDLE,false,moved); b._update_camera_motion(0)
		settled = b.camera.position
		b._process(.1)
		check(b.camera.position!=settled and b.camera_motion.target==before,"old target keeps smoothing without new wheel or pan")
		guard_inputs(b,moved)
		press(MOUSE_BUTTON_WHEEL_UP,false,moved,.5)
		press(MOUSE_BUTTON_WHEEL_UP,true,moved,NAN)
		b._update_camera_motion(0)
		check(b.camera_motion.target==before,"release and nonfinite wheel do not reach the old target")

		press(MOUSE_BUTTON_MIDDLE,true,moved)
		press(MOUSE_BUTTON_WHEEL_DOWN,true,moved,.5)
		check(is_equal_approx(b._camera_scroll_sample,-.5),"last old frame owns the accumulated wheel")
		if scene=="Main":
			var commit: Callable = b.scene_transition._commit
			b.scene_transition.cancel()
			check(b.scene_transition.begin(commit),"diagnostic generation replacement")
			var frozen: Vector3 = b.camera.position
			b._update_camera_motion(.03)
			press(MOUSE_BUTTON_WHEEL_DOWN,true,moved,.5); b._update_camera_motion(.03)
			check(not b.panning and b.camera.position==frozen and b.camera_motion.target==before,
				"unowned replacement generation cannot replay old events or authorize new input")
		b._process(1)
		check(b.session!=owner and b.scene_transition.phase=="in" and not b.panning
			and b.camera_motion.target==b.camera.position and b.camera_motion.velocity==Vector3.ZERO,
			"black installs fresh scene camera and no departing drag/velocity")
		var arrived: Vector3 = b.camera_motion.target
		motion(point)
		b._process(.05)
		check(not b.panning and b.camera_motion.target==arrived and b._camera_scroll_sample==0,
			"held physical button or queued old wheel cannot act on incoming camera")
		press(MOUSE_BUTTON_MIDDLE,false,point); b._update_camera_motion(0)
		press(MOUSE_BUTTON_MIDDLE,true,point); b._update_camera_motion(0)
		check(b.panning,"fresh inbound button press uses the normal camera path")
		press(MOUSE_BUTTON_MIDDLE,false,point)
		b._process(1)
		check(b.scene_transition.phase=="idle","normal finish")
		b.queue_free()
		await process_frame
	print("Source fade camera: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
