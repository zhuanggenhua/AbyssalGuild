extends SceneTree
const Board=preload("res://scripts/ui/board.gd")
const Codec=preload("res://scripts/model/save_codec.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_event:String)->bool:return false
	func play_music()->bool:return false
var checks:=0
var failures:=0
func check(v:bool,s:String):
	checks+=1
	if not v: failures+=1;printerr("FAIL ",s)
func _init():call_deferred("run")
func portal(b):
	var id=b.session.spawn_card(b.catalog.find_by_name("Grand Portal"),Vector2(3,0),-1,{"refuse_attach":true})
	var worker=b.session.spawn_card(b.catalog.find_by_name("Villager"),Vector2(4,0),-1,{"refuse_attach":true})
	check(b.session.move_to_stack(worker,b.session.cards[id].stack_id),"portal assembled")
	check(b.session.crafting.advance(5),"travel started")
func clean(b):
	b.vendor_unlock.cancel();b.session.cycle.reset();b.session.phase="playing";b.session.paused=false;b.pause_overlay.hide();b.options_panel.hide();b.session.elapsed=0
	for id in b.session.cards.keys():b.session._remove_card(id)
	b.session.spawn_target_selector=Callable();b.session.spawn_layout_resolver=Callable()
func run():
	for scene in ["Main","Island"]:
		var b=Board.new();b.feedback.free();b.feedback=SilentFeedback.new()
		var dir="user://wheel-%d"%Time.get_ticks_usec();b.slot_root=dir+"/slots";b.options_path=dir+"/options";b.legacy_paths.clear()
		root.add_child(b);await process_frame;b.start_new();b.set_process(false);clean(b)
		if scene=="Island":
			portal(b);b._process(1);b._process(1);clean(b)
		check(b.session.scene_name==scene,"active source scene")
		portal(b)
		var owner=b.session;var saved=Codec.capture(owner)
		b.camera.position=Vector3(0,12,1);b.camera_motion.configure(b.camera.position);b._clamp_camera()
		var before=b.camera_motion.target;var position=b.camera.position
		var wheel=InputEventMouseButton.new();wheel.button_index=MOUSE_BUTTON_WHEEL_UP;wheel.pressed=true;wheel.factor=.5;wheel.position=Vector2(40,40)
		# Deliver through the viewport so the production fade input gate executes.
		root.push_input(wheel,true)
		check(b.camera_motion.target==before and is_equal_approx(b._camera_scroll_sample,.5),"accept raw wheel but wait for departing Update")
		var expected=before+(-b.camera.global_basis.z)*.5*float(b.camera_motion.settings.zoomSpeed)
		var middle := InputEventMouseButton.new()
		middle.button_index = MOUSE_BUTTON_MIDDLE; middle.pressed = true
		root.push_input(middle, true)
		check(not b.panning, "middle pan remains blocked during fade")
		var left := InputEventMouseButton.new()
		left.button_index = MOUSE_BUTTON_LEFT; left.pressed = true
		root.push_input(left, true)
		check(b.dragging < 0 and not b._text_button_allowed(b.day_clock), "card and HUD input remain blocked")
		b._process(.1)
		check(b.camera_motion.target.is_equal_approx(expected),"unchanged existing wheel conversion once on Update")
		check((b.camera.position!=position),"visible camera motion before black")
		check(b.session==owner and is_equal_approx(b.scene_transition.alpha,.1),"old owner and early fade")
		check(Codec.capture(owner)==saved,"wheel does not change saved model")
		check(not b._camera_input_enabled() and not b.panning and b.scene_transition.blocks_input(),"no broad input enabled")
		for mode in ["menu","options","vendor","cycle","pan","drag","focus","unverified","release","nan"]:
			var original_commit=b.catalog.data.provenance.source_commit
			if mode=="menu":b.pause_overlay.show()
			if mode=="options":b.options_panel.show()
			if mode=="vendor":b.vendor_unlock.sequence.stage="hold"
			if mode=="cycle":b.session.phase="feeding"
			if mode=="pan":b.panning=true
			if mode=="drag":b.dragging=999
			if mode=="focus":b.camera_motion.focus={"start":Vector3.ZERO,"end":Vector3.ONE,"duration":1.0,"elapsed":0.0}
			if mode=="unverified":b.catalog.data.provenance.source_commit="unknown"
			wheel.pressed=mode!="release";wheel.factor=NAN if mode=="nan" else .5
			before=b.camera_motion.target;root.push_input(wheel,true)
			check(b.camera_motion.target==before and b._camera_scroll_owner==0,mode+" blocked")
			b.pause_overlay.hide();b.options_panel.hide();b.vendor_unlock.sequence.stage="idle";b.session.phase="playing";b.panning=false;b.dragging=-1;b.camera_motion.focus.clear();b.catalog.data.provenance.source_commit=original_commit
		wheel.pressed=true;wheel.factor=.5;wheel.button_index=MOUSE_BUTTON_WHEEL_DOWN
		before=b.camera_motion.target;root.push_input(wheel,true)
		check(b.camera_motion.target==before and is_equal_approx(b._camera_scroll_sample,-.5),"opposite wheel direction queued")
		# Diagnostic controller cancellation/restart: an old wheel grant
		# cannot authorize smoothing in a new generation of the same owner.
		var commit: Callable = b.scene_transition._commit
		b.scene_transition.cancel()
		check(b.scene_transition.begin(commit),"restart diagnostic transition")
		var frozen: Vector3 = b.camera.position
		b._update_camera_motion(.05)
		check(b.camera.position==frozen and b._fade_wheel_owner==0,"stale wheel generation rejected")
		root.push_input(wheel,true)
		check(b._camera_scroll_owner==owner.get_instance_id() and b._camera_scroll_generation==b.scene_transition.generation,"fresh wheel admits new generation")
		b._update_camera_motion(.05)
		check(b._fade_wheel_owner==owner.get_instance_id() and b.camera_motion.target!=before,"new generation resolves only its own opposite movement")
		b._process(1);check(b.session!=owner,"swap owns new camera")
		var after=b.camera_motion.target;b._process(.01)
		check(b._fade_wheel_owner==0,"fade permission reset after swap")
		b._process(1);check(b.scene_transition.phase=="idle","normal finish")
		b.queue_free();await process_frame
	print("Source fade wheel: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
