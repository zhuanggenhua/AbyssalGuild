extends SceneTree
const Board=preload("res://scripts/ui/board.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_kind:String)->bool:return false
	func play_music()->bool:return false
var checks:=0
var failures:=0
func check(v:bool,s:String):
	checks+=1
	if not v:failures+=1;printerr("FAIL ",s)
func _init():call_deferred("run")
func make_board(path:String):
	var b=Board.new();b.feedback.free();b.feedback=SilentFeedback.new()
	b.slot_root=path+"/slots";b.options_path=path+"/options.json";b.legacy_paths.clear()
	root.add_child(b);return b
func pair(b):
	var a:int=b.session.spawn_card(b.catalog.find_by_name("Grand Portal"),Vector2(5,0),-1,{"refuse_attach":true})
	var w:int=b.session.spawn_card(b.catalog.find_by_name("Villager"),Vector2(6,0),-1,{"refuse_attach":true})
	check(b.session.move_to_stack(w,b.session.cards[a].stack_id),"pair")
func run():
	var expected_source=true
	for mode in ["loss", "save", "quit", "return", "return_save", "unverified", "recipe_hash", "unsupported", "legacy"]:
		expected_source = mode in ["loss", "save", "quit", "return", "return_save"]
		var explicit = mode in ["save", "quit", "return_save"]
		var path="user://arrival-audit-%s-%d"%[mode,Time.get_ticks_usec()]
		var b=make_board(path);await process_frame;b.start_new();b.set_process(false)
		b.vendor_unlock.cancel();b.session.cycle.reset();b.session.phase="playing";b.session.paused=false;b.pause_overlay.hide()
		for id in b.session.cards.keys():b.session._remove_card(id)
		b.session.spawn_target_selector=Callable();b.session.spawn_layout_resolver=Callable()
		if mode.begins_with("return"):
			pair(b);b.session.crafting.advance(5);b._process(1);b._process(1)
			check(b.session.scene_name=="Island","first trip before return")
			for id in b.session.cards.keys():b.session._remove_card(id)
			b.session.phase="playing";b.session.cycle.reset();b.session.paused=false
		if mode=="unverified":b.catalog.data.provenance.source_commit="unverified"
		if mode=="recipe_hash":b.catalog.get_definition("d5d66946e2ba247499709d2b17796dc0").source_sha256="unverified"
		pair(b)
		if mode=="unsupported":
			for card in b.session.cards.values():card.uses_left=2
		var origin=b.session.scene_name
		var destination="Island" if origin=="Main" else "Main"
		b.session.crafting.advance(5)
		check(b.scene_transition.active(),"travel accepted")
		var bound=b.scene_transition._commit.get_bound_arguments()
		check(bound.size()==3,"same commit bound arity")
		if mode=="loss":
			check(not bound[2].get("ok",false) and bound[2].get("source_arrival_no_save",false),"new destination geometry rejection does not erase independent persistence grant")
		var before=FileAccess.get_file_as_string(b._active_slot_path())
		var backup_before=FileAccess.get_file_as_string(b._active_slot_path()+".bak")
		check(JSON.parse_string(before).current_scene==origin,"departure Main")
		b._process(1);b._process(1)
		check(b.running and b.session.scene_name==destination and not b.scene_transition.active(),"arrival unlocked Island")
		check(not b.session.travel_pending,"arrival no pending")
		if mode=="legacy":
			b._on_session_event("scene_changed",{})
			check(b.notice.text.ends_with(" · saved."),"legacy scene_changed retains autosave")
		var after=FileAccess.get_file_as_string(b._active_slot_path())
		check((after==before)==expected_source,"arrival disk mutation policy")
		if expected_source:check(FileAccess.get_file_as_string(b._active_slot_path()+".bak")==backup_before,"arrival preserves backup")
		if mode in ["save", "return_save"]:b._save_game();check(b.notice.text=="Saved locally.","explicit save success")
		if mode=="quit":
			var callbacks=[0]
			b.quit_callback=func():callbacks[0]+=1
			b._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
			check(callbacks[0]==1 and b.quit_dispatched,"normal unlocked close saves and dispatches once")
		if explicit and expected_source:check(FileAccess.get_file_as_string(b._active_slot_path()+".bak")==before,"explicit save/quit backs up departure")
		var expected=origin if expected_source and not explicit else destination
		var disk=JSON.parse_string(FileAccess.get_file_as_string(b._active_slot_path()))
		check(disk.current_scene==expected,"disk scene")
		var slot=b.active_slot;b.queue_free();await process_frame
		var c=make_board(path);await process_frame;c.set_process(false);c.selected_slot=slot;c._continue_game()
		check(c.running and c.session.scene_name==expected,"new Board Continue scene")
		c._process(0.01)
		check(not c.session.travel_pending,"no immediate retravel after Continue")
		print("ARRIVAL_AUDIT mode=",mode," disk=",disk.current_scene," continued=",c.session.scene_name)
		c.queue_free();await process_frame
	print("Arrival persistence audit: ",checks," failures ",failures)
	quit(1 if failures else 0)
