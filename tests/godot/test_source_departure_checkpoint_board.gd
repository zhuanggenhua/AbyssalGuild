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
func pair(b,n:String,x:float):
	var a:int=b.session.spawn_card(b.catalog.find_by_name(n),Vector2(x,0),-1,{"refuse_attach":true})
	var w:int=b.session.spawn_card(b.catalog.find_by_name("Villager"),Vector2(x+1,0),-1,{"refuse_attach":true})
	check(b.session.move_to_stack(w,b.session.cards[a].stack_id),"pair")
	return b.session.stacks[b.session.cards[a].stack_id]
func has_timber(session)->bool:
	for card in session.cards.values():
		if card.definition_guid==session.catalog.find_by_name("Timber"):return true
	return false
func raw(b):return JSON.parse_string(FileAccess.get_file_as_string(b._active_slot_path()))
func saved_has_timber(b,snap)->bool:
	for card in snap.scenes[snap.current_scene].session.cards:
		if card.definition_guid==b.catalog.find_by_name("Timber"):return true
	return false
func travel_shape(b,snap):
	for stack in snap.scenes[snap.current_scene].session.stacks:
		var cards=[]
		var portal=false
		for card in snap.scenes[snap.current_scene].session.cards:
			if card.id in stack.card_ids:
				cards.append({"guid":card.definition_guid,"uses":card.uses_left})
				if card.definition_guid==b.catalog.find_by_name("Grand Portal"):portal=true
		if portal:return {"cards":cards,"progress":stack.progress,"recipe":stack.recipe_guid}
	return {}
func run():
	for mode in ["accepted","arrival","reserved","unsupported","invalid_recipe","island","island_reserved","unverified","later_save","two_portals"]:
		var path="user://normalize-%s-%d"%[mode,Time.get_ticks_usec()]
		var b=make_board(path);await process_frame;b.start_new();b.set_process(false)
		b.vendor_unlock.cancel();b.session.cycle.reset();b.session.phase="playing";b.session.paused=false;b.pause_overlay.hide()
		for id in b.session.cards.keys():b.session._remove_card(id)
		b.session.spawn_target_selector=Callable();b.session.spawn_layout_resolver=Callable()
		if mode.begins_with("island"):
			pair(b,"Grand Portal",5);b.session.crafting.advance(5);b._process(1);b._process(1)
			check(b.session.scene_name=="Island","real first journey supplies Island owner")
			for id in b.session.cards.keys():b.session._remove_card(id)
		var origin=b.session.scene_name
		var target="Island" if origin=="Main" else "Main"
		var wood=pair(b,"Wood",-5);b.session.crafting.advance(2)
		if mode=="two_portals":pair(b,"Grand Portal",9)
		var portal=pair(b,"Grand Portal",5)
		if mode=="unsupported":b.session.cards[portal.card_ids[0]].uses_left=2
		var original=b.session.campaign.capture().duplicate(true)
		var stamp=b.session.campaign.last_saved.duplicate(true)
		var disk_before=FileAccess.get_file_as_string(b._active_slot_path())
		if mode in ["reserved","island_reserved"]:DirAccess.make_dir_absolute(b._active_slot_path()+".reserved")
		var old_source=b.catalog.data.provenance.source_commit
		if mode=="unverified":b.catalog.data.provenance.source_commit="unverified"
		var ok=false
		if mode=="invalid_recipe":ok=b._request_travel(portal.id,"invalid")
		else:
			b.session.crafting.advance(5)
			ok=b.scene_transition.active()
		check(ok==(mode in ["accepted","arrival","unsupported","island","unverified","later_save","two_portals"]),"request result "+mode)
		check(b.slots.campaign==b.session.campaign,"slot writer restored to live owner")
		check(b.session.cards.has(portal.card_ids[0]) and b.session.stacks.has(portal.id),"live portal retained")
		check(b.session.stacks[wood.id].progress==(7 if mode in ["reserved","island_reserved"] else 2),"live old task unchanged")
		if mode in ["reserved","island_reserved","invalid_recipe"]:
			check(FileAccess.get_file_as_string(b._active_slot_path())==disk_before,"failure preserves file")
			check(not b.scene_transition.active(),"failure no transition")
			check(b.session.campaign.last_saved==stamp,"failure keeps last-saved timestamp")
			if mode in ["reserved","island_reserved"]:
				check(b.notice.text=="Travel failed: Slot allocation is busy","failure keeps normal checkpoint banner")
				DirAccess.remove_absolute(b._active_slot_path()+".reserved")
				b.session._check_recipe(portal);b.session.crafting.advance(5)
				check(b.scene_transition.active() and travel_shape(b,raw(b)).is_empty(),"retry after reservation release normalizes and travels")
				check(b.slots.campaign==b.session.campaign,"retry retains writer owner")
		else:
			var saved=raw(b)
			check(JSON.parse_string(JSON.stringify(b.session.campaign.last_saved))==saved.last_saved,"successful copied writer advances live timestamp")
			check(travel_shape(b,saved).is_empty()==(mode in ["accepted","arrival","island","later_save"]),"checkpoint portal shape")
			check(saved.scenes[origin].session.quests==JSON.parse_string(JSON.stringify(original.scenes[origin].session.quests)),"quest preservation")
			check(saved.scenes[origin].session.stacks[0].progress==2,"other task saved")
			if mode=="arrival":
				b._process(1);b._process(1)
				check(b.session.scene_name=="Island","destination candidate untouched")
				var travelers=0
				for card in b.session.cards.values():
					if card.definition_guid in [b.catalog.find_by_name("Grand Portal"),b.catalog.find_by_name("Villager")]:
						travelers+=1;check(card.uses_left==0,"native destination already captures consumed uses")
				check(travelers==2,"both destination travelers retained")
				b.catalog.data.provenance.source_commit=old_source
				b.queue_free();await process_frame
				continue
			check(b.notice.text=="Travel departure · saved.","normal departure status")
			if mode=="later_save":
				b._save_game();check(not travel_shape(b,raw(b)).is_empty(),"later explicit save deliberately unchanged")
			b.catalog.data.provenance.source_commit=old_source
			var slot=b.active_slot
			b.catalog.data.provenance.source_commit=old_source
			b.queue_free();await process_frame
			var c=make_board(path);await process_frame;c.set_process(false);c.selected_slot=slot;c._continue_game()
			check(c.running and c.session.scene_name==origin,"actual Continue from departure")
			c._process(0.01)
			check(c.session.travel_pending==(mode in ["unsupported","unverified","later_save","two_portals"]),"normalized has no retravel; unsupported retains prior retravel")
			if mode in ["accepted","island"]:check(c.session.cards.size()==2,"only old wood pair restored")
			c.queue_free();await process_frame
			continue
		b.catalog.data.provenance.source_commit=old_source
		b.queue_free();await process_frame
	print("Source departure checkpoint: ",checks," failures ",failures)
	quit(1 if failures else 0)
