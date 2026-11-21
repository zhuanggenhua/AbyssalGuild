extends SceneTree
const Board=preload("res://scripts/ui/board.gd")
const Session=preload("res://scripts/model/game_session.gd")
const Departure=preload("res://scripts/ui/source_departure_checkpoint.gd")
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
	await _equipped_first_visit()
	await _equipped_revisit()
	print("Source departure checkpoint: ",checks," failures ",failures)
	quit(1 if failures else 0)

func _equipped_first_visit() -> void:
	var b=make_board("user://first-trip-gear-%d"%Time.get_ticks_usec())
	await process_frame
	b.start_new(); b.set_process(false)
	b.vendor_unlock.cancel(); b.session.cycle.reset(); b.session.phase="playing"; b.session.paused=false
	for id in b.session.cards.keys(): b.session._remove_card(id)
	b.session.spawn_target_selector=Callable(); b.session.spawn_layout_resolver=Callable()
	var portal=pair(b,"Grand Portal",5)
	var pid: int=portal.card_ids[0]
	var traveler: int=portal.card_ids[1]
	var club: int=b.session.spawn_card("c7c554e773779c44b935ac769f24c3aa",Vector2(0,0),-1,{"refuse_attach":true})
	if not b.session.equipment.equip(traveler,club):
		check(false,"first trip uses actual class gear")
		b.queue_free()
		await process_frame
		return
	check(true,"first trip uses actual class gear")
	b.session.cards[traveler].health=17
	var wood=pair(b,"Wood",-5)
	b.session.crafting.advance(2)
	var source=b.session
	check(not source.campaign.saved_scenes.has("Island") and not Departure.all_fresh(source,portal.id),
		"first equipped trip does not qualify for fresh close receipt")
	var recipe: String=portal.recipe_guid
	var before: float=portal.progress
	portal.progress=float(source.catalog.fields(recipe).craftingDuration)
	var candidate := Session.new()
	candidate.configure(source.catalog)
	check(candidate.campaign.restore(source.campaign.capture()).ok,"first trip disposable replay staged from authentic board")
	var accepted: Dictionary=candidate.campaign.travel(portal.id,recipe)
	if not accepted.ok or not accepted.traveler_ids.has(traveler) or not accepted.traveler_ids.has(club):
		check(false,"first trip returns an authentic typed traveler/gear remap")
		b.queue_free()
		await process_frame
		return
	check(Departure.admitted(source,portal.id,recipe,accepted,-1,candidate),"strict admit actual first equipped remap")
	check(not Departure.admitted(source,portal.id,recipe,accepted,wood.card_ids[0],candidate),
		"equipped first checkpoint cannot acquire the separate held-card receipt")
	check(not Departure.admitted(source,portal.id,recipe,accepted,-1,source)
		and not Departure.admitted(source,portal.id,recipe,accepted,-1,null),
		"first equipped departure requires separate correct destination")
	var moved: int=accepted.traveler_ids[traveler]
	var moved_club: int=accepted.traveler_ids[club]
	var damaged: Dictionary=accepted.duplicate(true)
	damaged.traveler_ids[club]=moved
	check(not Departure.admitted(source,portal.id,recipe,damaged,-1,candidate),"duplicate typed remap rejected")
	candidate.cards[moved].health=16
	check(not Departure.admitted(source,portal.id,recipe,accepted,-1,candidate),"changed HP rejected")
	candidate.cards[moved].health=17
	candidate.equipment.owners.erase(moved_club)
	check(not Departure.admitted(source,portal.id,recipe,accepted,-1,candidate),"changed gear owner rejected")
	candidate.equipment.owners[moved_club]=moved
	candidate.equipment.class_items.erase(moved)
	check(not Departure.admitted(source,portal.id,recipe,accepted,-1,candidate),"changed class item rejected")
	candidate.equipment.class_items[moved]=moved_club
	# A truly reused first pair still follows the pre-existing fallback, even
	# if presented with a matching staged use count.
	source.cards[pid].uses_left=0
	candidate.cards[accepted.traveler_ids[pid]].uses_left=-1
	check(not Departure.admitted(source,portal.id,recipe,accepted,-1,candidate),"no broadened first visit for spent inputs")
	source.cards[pid].uses_left=1
	portal.progress=before
	b.session.crafting.advance(5)
	check(b.scene_transition.active() and b._source_close_receipt.is_empty() and b._outbound_mouse_hold.is_empty(),
		"equipped first travel starts without close or held receipts")
	var slot: String=b._active_slot_path()
	var primary := FileAccess.get_sha256(slot)
	var backup := FileAccess.get_sha256(slot+".bak")
	var departure=raw(b)
	var state: Dictionary=departure.scenes.Main.session
	check(departure.current_scene=="Main" and not departure.scenes.has("Island")
		and not primary.is_empty() and not backup.is_empty(),"first equipped departure writes valid Main primary/backup")
	check(state.cards.map(func(row): return int(row.id))==Array(wood.card_ids)
		and state.equipment.wearers.is_empty() and int(portal.id) not in state.crafting.activation_order
		and state.stacks.size()==1 and state.stacks[0].progress==wood.progress,
		"saved checkpoint excludes consumed pair and embedded gear, preserves adjacent active craft")
	check(source.cards.has(pid) and source.equipment.owners.get(club)==traveler,
		"pre-fade live origin is not mutated by disk checkpoint")
	b._process(1);b._process(1)
	check(b.session.scene_name=="Island" and FileAccess.get_sha256(slot)==primary and FileAccess.get_sha256(slot+".bak")==backup,
		"while live Island on first equipped visit, neither primary nor backup writes")
	var warriors: Array=b.session.cards.keys().filter(func(id): return b.session.cards[id].definition_guid==b.catalog.find_by_name("Warrior"))
	check(warriors.size()==1,"one transformed class restored on Island")
	if warriors.size()==1:
		var owner: int=warriors[0]
		var item: int=b.session.equipment.class_items.get(owner,-1)
		check(b.session.cards[owner].health==17 and b.session.cards[owner].uses_left==0
			and b.session.equipment.originals.get(owner)==b.catalog.find_by_name("Villager")
			and b.session.equipment.owners.get(item)==owner and b.session.cards[item].uses_left==1,
			"actual first destination retains HP, original class, equipped owner and use counts")
	b._save_game()
	check(raw(b).current_scene=="Island" and FileAccess.get_sha256(slot+".bak")==primary,
		"normal explicit save is first Island disk write and preserves departure backup")
	b.queue_free()
	await process_frame

func _equipped_revisit() -> void:
	var b=make_board("user://normalized-gear-%d"%Time.get_ticks_usec())
	await process_frame
	b.start_new(); b.set_process(false)
	b.vendor_unlock.cancel(); b.session.cycle.reset(); b.session.phase="playing"; b.session.paused=false
	for id in b.session.cards.keys(): b.session._remove_card(id)
	b.session.spawn_target_selector=Callable(); b.session.spawn_layout_resolver=Callable()
	pair(b,"Grand Portal",5); b.session.crafting.advance(5); b._process(1); b._process(1)
	check(b.session.scene_name=="Island","equipped test starts at real prior arrival")
	for id in b.session.cards.keys(): b.session._remove_card(id)
	var portal=pair(b,"Grand Portal",5)
	var pid: int=portal.card_ids[0]
	var traveler: int=portal.card_ids[1]
	var sword: int=b.session.spawn_card(b.catalog.find_by_name("Sword"),Vector2(0,0),-1,{"refuse_attach":true})
	check(b.session.equipment.equip(traveler,sword),"actual class item changes traveler definition")
	var role: String=b.session.cards[traveler].definition_guid
	var base: String=b.session.cards[traveler].base_definition_guid
	check(role!=base and not Departure.all_fresh(b.session,portal.id),"equipped cohort not eligible for fresh close receipt")
	var other: int=b.session.spawn_card(b.catalog.find_by_name("Wood"),Vector2(3,0),-1,{"refuse_attach":true})
	b.session.crafting.advance(5)
	var checkpoint=raw(b)
	check(b.scene_transition.active() and checkpoint.current_scene=="Island","equipped return starts with Island departure save")
	var remaining: Array=checkpoint.scenes.Island.session.cards.map(func(row): return int(row.id))
	check(remaining==[other] and checkpoint.scenes.Island.session.equipment.wearers.is_empty(),"departure save excludes transformed traveler, portal and linked gear only")
	check(b.session.cards.has(sword) and b.session.equipment.owners.get(sword)==traveler,"live departure equipment unchanged before fade")
	var bytes:=FileAccess.get_file_as_string(b._active_slot_path())
	b._process(1); b._process(1)
	check(b.session.scene_name=="Main" and FileAccess.get_file_as_string(b._active_slot_path())==bytes,"equipped arrival does not auto-save")
	var ids: Array=b.session.cards.keys().filter(func(id): return b.session.cards[id].definition_guid==role)
	check(ids.size()==1,"unique transformed traveler at destination")
	if ids.size()==1:
		var owner: int=ids[0]
		var item: int=b.session.equipment.class_items.get(owner,-1)
		check(b.session.equipment.originals.get(owner)==base and b.session.equipment.owners.get(item)==owner and b.session.cards.has(item),"original class and equipment owner retained")
		check(b.session.cards[owner].uses_left==0 and b.session.cards[item].uses_left==1,"deduct travel use but not equipment use")
	b.queue_free()
	await process_frame
