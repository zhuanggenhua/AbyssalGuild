extends SceneTree
## Imported-source Board lifecycle test. Headless state/material assertions, not native screenshots.
const Board = preload("res://scripts/ui/board.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_kind: String) -> bool: return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
func check(ok: bool, message: String):
	checks += 1
	if not ok: failures += 1; printerr("FAIL ",message)
func _init(): call_deferred("run")
func pair(b, name: String, x: float):
	var id: int = b.session.spawn_card(b.catalog.find_by_name(name),Vector2(x,0),-1,{"refuse_attach":true})
	var worker: int = b.session.spawn_card(b.catalog.find_by_name("Villager"),Vector2(x+1,0),-1,{"refuse_attach":true})
	check(b.session.move_to_stack(worker,b.session.cards[id].stack_id),"source recipe assembly")
	return b.session.stacks[b.session.cards[id].stack_id]
func run():
	for condition in ["ordinary","task_paused","held_tail","menu","options","unverified","complete_tail","near_complete_tail","two_ready_travels"]:
		var b=Board.new();b.feedback.free();b.feedback=SilentFeedback.new()
		var path="user://view-%d"%Time.get_ticks_usec();b.slot_root=path+"/slots";b.options_path=path+"/options.json";b.legacy_paths.clear()
		root.add_child(b);await process_frame;b.start_new();b.set_process(false)
		b.vendor_unlock.cancel();b.session.cycle.reset();b.session.phase="playing";b.session.paused=false;b.pause_overlay.hide();b.session.elapsed=0
		for id in b.session.cards.keys():b.session._remove_card(id)
		b.session.spawn_target_selector=Callable();b.session.spawn_layout_resolver=Callable()
		var timber=pair(b,"Wood",-5);b.session.crafting.advance(2)
		if condition=="task_paused":timber.paused=true
		if condition=="complete_tail":timber.progress=10
		if condition=="near_complete_tail":timber.progress=9.99999999
		if condition=="held_tail":check(b.session.drag.begin(timber.card_ids.back()).ok,"held original pause")
		var portal=pair(b,"Grand Portal",5)
		# Exact Board request, no injected pending flag or transition action.
		check(b.session.crafting.advance(5),"travel request")
		var owner=b.session
		if condition=="two_ready_travels":
			var second=pair(b,"Grand Portal",9);second.progress=5
		if condition=="menu":b.pause_overlay.show()
		if condition=="options":b.options_panel.show()
		var provenance=b.catalog.data.provenance.source_commit
		if condition=="unverified":b.catalog.data.provenance.source_commit="unverified"
		var before=Codec.capture(owner)
		var events: Array=[]
		owner.event_occurred.connect(func(k,_p):events.append(k))
		b._sync_card_feedback()
		var admitted=condition in ["ordinary","task_paused","held_tail"]
		check(b.craft_progress.bars.has(timber.id)==admitted,condition+" admission")
		check(not b.craft_progress.bars.has(portal.id),condition+" completed travel bar absent")
		if admitted:
			var bar=b.craft_progress.bars[timber.id].root
			check(is_equal_approx(bar.material_override.get_shader_parameter("ratio"),0.2),"old task source ratio")
			check(bool(bar.get_meta("paused")) == (condition!="ordinary"),condition+" task pause flag unchanged")
		check(Codec.capture(owner)==before and events.is_empty(),condition+" drawing changes no model or events")
		check(b.scene_transition.blocks_input() and not b._camera_input_enabled() and not b._text_button_allowed(b.day_clock),condition+" input remains blocked")
		b.catalog.data.provenance.source_commit=provenance
		b.pause_overlay.hide();b.options_panel.hide()
		b._process(0.25)
		check(b.session==owner and b.scene_transition.alpha==0.25,"pre-black owner retained")
		var old_nodes: Array=[]
		for value in b.craft_progress.bars.values(): old_nodes.append(weakref(value.root))
		b._process(0.75)
		check(b.session!=owner and b.session.scene_name=="Island" and b.scene_transition.alpha==1,"swap at black")
		await process_frame
		check(old_nodes.all(func(w):return w.get_ref()==null),"old progress nodes freed at black")
		b._process(1)
		check(b.scene_transition.phase=="idle" and b.craft_progress.bars.is_empty(),"no stale departing progress after fade-in")
		b.queue_free();await process_frame
	print("Source fade progress: %d checks, %d failures"%[checks,failures])
	quit(1 if failures else 0)
