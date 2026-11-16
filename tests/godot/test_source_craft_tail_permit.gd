extends SceneTree
const AudioDrain = preload("res://tests/godot/source_test_audio_drain.gd")
const Board=preload("res://scripts/ui/board.gd")
const Permit=preload("res://scripts/ui/source_craft_tail_permit.gd")
const Codec=preload("res://scripts/model/save_codec.gd")
var checks:int=0
func check(value:bool,label:String):
	checks+=1
	if not value:push_error(label);quit(1);assert(value,label)
func _init():call_deferred("run")
func pair(b,name,pos):
	var id=b.session.spawn_card(b.catalog.find_by_name(name),pos,-1,{"refuse_attach":true})
	var worker=b.session.spawn_card(b.catalog.find_by_name("Villager"),pos+Vector2(1,0),-1,{"refuse_attach":true})
	check(b.session.move_to_stack(worker,b.session.cards[id].stack_id),"assemble")
	return b.session.stacks[b.session.cards[id].stack_id]
func unexpected(_kind,_payload):pass
func card_count(owner, guid: String) -> int:
	var count := 0
	for card in owner.cards.values():
		if card.definition_guid == guid: count += 1
	return count
func run():
	check(Permit._source_still_incomplete(2, 5, 10), "source ordinary incomplete")
	check(not Permit._source_still_incomplete(2, 7.9999998, 10), "source float32 completion boundary rejected")
	check(not Permit._source_still_incomplete(9.9999998, 0, 10), "source already-complete rounding rejected")
	check(not Permit._source_still_incomplete(2, 1e300, 10), "source nonfinite conversion rejected")
	var audio_drain := AudioDrain.new()
	for mode in ["admitted","admitted_island","admitted_stick","eligible_far","observer","other_portal","active_receiver","unknown_output","quest_delta","new_task","over_budget","timer_incomplete","timer_paused"]:
		var b=Board.new()
		var path="user://permit-%d"%Time.get_ticks_usec();b.slot_root=path+"/slots";b.options_path=path+"/options";b.legacy_paths.clear()
		root.add_child(b);await process_frame;b.start_new();b.set_process(false)
		audio_drain.observe_music(b.feedback.music)
		# Keep production audio callbacks; do not load additional SFX in this logic fixture.
		b.feedback.assets=null;b.feedback.stream_cache.clear()
		b.vendor_unlock.cancel();b.session.cycle.reset();b.session.phase="playing";b.session.paused=false;b.pause_overlay.hide();b.session.elapsed=0
		for id in b.session.cards.keys():b.session._remove_card(id)
		if mode=="admitted_island":
			pair(b,"Grand Portal",Vector2(4,0));b.session.crafting.advance(5);b._process(1);b._process(1)
			b.vendor_unlock.cancel();b.session.cycle.reset();b.session.phase="playing";b.session.paused=false
			for id in b.session.cards.keys():b.session._remove_card(id)
		var source_scene:String=b.session.scene_name
		var wood=b.catalog.find_by_name("Wooden Stick" if mode in ["new_task","admitted_stick"] else "Timber")
		if mode!="unknown_output":b.session.collection.mark_card(wood)
		var tail=pair(b,"Timber" if mode in ["new_task","admitted_stick"] else "Wood",Vector2(-4,0))
		b.session.crafting.advance(2 if mode in ["timer_incomplete","timer_paused"] else 5)
		if mode=="timer_paused": tail.paused=true
		if mode=="observer":b.session.event_occurred.connect(unexpected)
		if mode=="other_portal":pair(b,"Grand Portal",Vector2(7,0))
		var portal=pair(b,"Grand Portal",Vector2(4,0))
		# A second active task is an explicit outside-scope frame, not a guessed
		# safe completion. Receiver-mutation detail has separate geometry tests.
		if mode=="active_receiver":pair(b,"Wood",Vector2(-3,0))
		if mode=="quest_delta":
			for id in b.session.quest_tracker.definitions:
				if b.session.quest_tracker.definitions[id].title=="Get Timber":
					b.session.quest_tracker._reset();b.session.quest_tracker._activate(id,b.session);b.quest_journal.bind(b.session.quest_tracker);break
		if mode=="over_budget":
			var extra:int=-1
			for i in range(13):
				var id=b.session.spawn_card(b.catalog.find_by_name("Stone"),Vector2(10,0),extra,{"refuse_attach":true});extra=b.session.cards[id].stack_id
		if mode=="new_task":
			var receiver=b.session.spawn_card(b.catalog.find_by_name("Villager"),Vector2(-3.7,0),-1,{"refuse_attach":true})
			var receiver_stack=b.session.cards[receiver].stack_id
			for name in ["Stone","Wooden Stick"]:b.session.spawn_card(b.catalog.find_by_name(name),Vector2(-3.7,0),receiver_stack,{"refuse_attach":true})
			b.session._check_recipe(b.session.stacks[receiver_stack])
			check(b.session.stacks[receiver_stack].recipe_guid.is_empty(),"receiver initially has no task")
			tail.position=Vector2(-4,0);b.session.stacks[receiver_stack].position=Vector2(-3.7,0)
			for id in tail.card_ids:b.session.cards[id].position=tail.position
			for id in b.session.stacks[receiver_stack].card_ids:b.session.cards[id].position=Vector2(-3.7,0)
		if mode=="eligible_far":b.session.spawn_card(wood,Vector2(8,0),-1,{"refuse_attach":true})
		var owner=b.session;var quests=owner.quest_tracker.save_state().duplicate(true)
		var previous_outputs: int = card_count(owner, wood)
		var original_inputs: Array = tail.card_ids.duplicate()
		b.vendor_unlock.bind(b);owner.crafting.advance(5)
		var admitted:bool=tail.recipe_guid.is_empty()
		if mode in ["timer_incomplete","timer_paused"]:
			check(tail.progress == (7 if mode == "timer_incomplete" else 2), "same-frame incomplete timer")
			check(not tail.recipe_guid.is_empty(), "timer-only recipe remains active")
		print("PERMIT mode=",mode," admitted=",admitted," receipt=",b._tail_receipt," active=",owner.crafting._active_serial)
		check(admitted==(mode in ["admitted","admitted_island","admitted_stick"]),"admission "+mode)
		check(card_count(owner, wood) == previous_outputs + (1 if admitted else 0), "exact output count")
		check(owner.cards.has(original_inputs[0]) != admitted and owner.cards.has(original_inputs[1]), "consumption and retained villager")
		check(b.session==owner and owner.travel_pending and b.scene_transition.phase=="out","old owner")
		check(owner.quest_tracker.save_state()==quests,"no quest delta")
		check(owner.crafting._active_serial==0,"frame expired")
		check(b._tail_receipt.is_empty(),"receipt consumed on rejection too")
		var disk_path=b.slots.slot_path(owner.campaign.slot_number)
		var disk=FileAccess.get_file_as_string(disk_path)
		var departure=JSON.parse_string(disk)
		var departure_progress:float=-1
		for row in departure.scenes[source_scene].session.stacks:
			if int(row.id)==tail.id:departure_progress=float(row.progress)
		check(departure_progress==(2 if mode in ["timer_incomplete","timer_paused"] else 5),"first checkpoint not overwritten by tail")
		var at_tail=Codec.capture(owner)
		var serial:int=owner.crafting._frame_serial
		check(not Permit.execute(b,{"stack":tail,"generation":tail.craft_generation,"recipe":tail.recipe_guid},tail.card_ids.duplicate(),5,serial,{"owner":owner.get_instance_id(),"generation":b.scene_transition.generation,"serial":serial}),"spent frame cannot replay")
		check(Codec.capture(owner)==at_tail,"replay changed nothing")
		owner.crafting.advance(99)
		check(Codec.capture(owner)==at_tail,"no later-frame leakage")
		b._process(.25)
		check(b.session==owner,"old owner before black")
		if mode in ["timer_incomplete","timer_paused"]:
			check(b.craft_progress.bars.has(tail.id), "incomplete source progress bar retained")
			var bar = b.craft_progress.bars[tail.id].root
			check(is_equal_approx(float(bar.material_override.get_shader_parameter("ratio")), 0.7 if mode == "timer_incomplete" else 0.2), "updated source progress bar ratio")
		check(FileAccess.get_file_as_string(disk_path)==disk,"no second preblack checkpoint")
		b._process(.75);b._process(1)
		check(b.session!=owner and b.session.scene_name==("Island" if source_scene=="Main" else "Main"),"arrival")
		var saved=b.session.campaign.saved_scenes[source_scene].session
		var saved_progress:float=-1
		for row in saved.stacks:
			if int(row.id)==tail.id:saved_progress=float(row.progress)
		check(saved_progress==(2 if mode in ["timer_incomplete","timer_paused"] else 5),"frozen departure task progress")
		check(b._tail_receipt.is_empty(),"receipt cleared")
		b.feedback.shutdown();await create_timer(.1).timeout
		b.queue_free();await process_frame
	check(await audio_drain.wait_after_teardown(self),"native BGM releases before fixture exit")
	print("Source craft tail permit: %d checks"%checks)
	quit(0)
