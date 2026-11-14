extends SceneTree
## Imported-data actual Continue integration. Explicit private fixtures, not GUI.
const Board = preload("res://scripts/ui/board.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Slots = preload("res://scripts/model/save_slots.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_kind: String) -> bool: return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
var serial := 0
var observations: Array = []
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ",label)
func _init(): call_deferred("run")
func folder() -> String:
	serial += 1
	return "user://cold-craft-%d-%d" % [Time.get_ticks_usec(),serial]
func normalized(s) -> Dictionary:
	var d: Dictionary = s.campaign.capture().duplicate(true)
	d.erase("last_saved")
	d.scenes[s.scene_name].session.erase("crafting")
	return d
func make(catalog, scene: String):
	var s = Session.new(); s.configure(catalog,20261115,scene); s.set_paused(true)
	return s
func add(s,name: String,where: Vector2) -> int:
	return s.spawn_card(s.catalog.find_by_name(name),where,-1,{"refuse_attach":true})
func pair(s,id: int):
	var worker: int = add(s,"Villager",Vector2(0,2))
	check(s.move_to_stack(worker,id),"ordinary legal fixture assembly")
func fixture(catalog,scene: String):
	var s = make(catalog,scene)
	var wood: int = add(s,"Wood",Vector2(-4,0))
	var timber: int = add(s,"Timber",Vector2(4,0))
	pair(s,s.cards[timber].stack_id); pair(s,s.cards[wood].stack_id)
	s.set_paused(false)
	for i in 300: s.tick(1.0/60.0)
	return s
func events(s) -> Array:
	var rows: Array = []; var weak = weakref(s)
	s.event_occurred.connect(func(kind,payload):
		if kind=="crafted": rows.append(weak.get_ref().catalog.fields(payload.definition_guid).displayName))
	return rows
func cold_case(board,scene: String):
	var s = fixture(board.catalog,scene)
	var history: Array = s.crafting.save_state().activation_order.duplicate()
	var registration: Array = []
	for stack in s.stacks.values(): registration.append(stack.id)
	check(history!=registration,"fixture pre-save activation differs")
	var slots = Slots.new(); slots.configure(s.campaign,folder())
	check(slots.create_slot().ok,"normal private save slot creation")
	var path: String = slots.slot_path(1)
	var bytes: PackedByteArray = FileAccess.get_file_as_bytes(path)
	var raw = make(board.catalog,scene)
	check(raw.campaign.load_file(path).ok,"ordinary model file read")
	check(raw.crafting.save_state().activation_order==history,"generic Codec/file read preserves native history")
	var expected := normalized(raw)
	board.slot_root=path.get_base_dir(); board.selected_slot=1
	board._continue_game()
	check(board.running and board.active_slot==1 and board.session.scene_name==scene,"actual Continue succeeds")
	check(board.session.crafting.save_state().activation_order==registration,"actual cold Continue restores source saved stack task order")
	check(normalized(board.session)==expected,"cold order changes no card/ID/position/gear/clock/pause/quests/RNG/inactive data")
	check(FileAccess.get_file_as_bytes(path)==bytes,"Continue does not rewrite input slot")
	check(not board.source_restore_report.get("ok",false),"active-craft geometry guard stays closed")
	var state: Dictionary = board.session.crafting.save_state()
	for i in 4: board._sync_views(0.0)
	check(board.session.crafting.save_state()==state,"view frames cannot reapply cold task schedule")
	check(board._save_active_slot().ok,"normal private Save after cold load")
	var saved = make(board.catalog,scene)
	check(saved.campaign.load_file(path).ok and normalized(saved)==expected,"ordinary save/re-read outside task order unchanged")
	check(saved.crafting.save_state().activation_order==registration,"new save retains corrected cold continuation")
	board._continue_game()
	check(board.session.crafting.save_state().activation_order==registration and normalized(board.session)==expected,"second cold load is stable")
	var output: Array = events(board.session)
	# Pure production model ticking isolates task order from viewport collision.
	board.session.spawn_target_selector=Callable(); board.session.spawn_layout_resolver=Callable()
	for i in 301: board.session.tick(1.0/60.0)
	check(output==["Wooden Stick","Timber"],"cold actual output follows source restored order")
	observations.append({"scene":scene,"history":history,"restored":registration,"actual_events":output})
	# Non-cold game entry must preserve intentionally different native history.
	board.session=fixture(board.catalog,scene)
	var before: Array = board.session.crafting.save_state().activation_order.duplicate()
	board._enter_game()
	check(board.session.crafting.save_state().activation_order==before,"non-cold entry does not reorder ongoing activations")
func fallback_case(board, scene: String, kind: String):
	var s = fixture(board.catalog,scene)
	if kind == "deadline": s.elapsed=s.day_duration
	if kind == "near_deadline": s.elapsed=s.day_duration-0.00000001
	if kind == "feeding": check(s.cycle.request_end_day(),"normal end-day fixture enters feeding")
	if kind == "paused_task": s.stacks.values()[0].paused=true
	if kind == "near_complete": s.stacks.values()[0].progress=9.99999999
	if kind == "combat":
		var hero: int=add(s,"Villager",Vector2(-1,2));var enemy: int=add(s,"Goblin",Vector2(1,2))
		check(s.combat.start_combat([hero],[enemy])>0,"normal combat fixture")
	var previous: Dictionary=s.crafting.save_state()
	var expected: Dictionary={"phase":s.phase,"cycle":s.cycle.stage,"day":s.day,"elapsed":s.elapsed,"paused":s.paused,"combat_tasks":s.combat.tasks.keys(),"membership":s.combat.membership.duplicate(true)}
	var stack_fields: Array=[]
	for st in s.stacks.values():stack_fields.append([st.id,st.recipe_guid,st.progress,st.paused,st.card_ids.duplicate()])
	var slots=Slots.new();slots.configure(s.campaign,folder())
	check(slots.create_slot().ok,kind+" private slot validates")
	var path: String=slots.slot_path(1);var bytes: PackedByteArray=FileAccess.get_file_as_bytes(path)
	var old_owner=board.session
	board.slot_root=path.get_base_dir();board.selected_slot=1;board._continue_game()
	check(board.session!=old_owner and board.running and board.active_slot==1 and board.session.scene_name==scene,kind+" really loaded a new cold session")
	var loaded=board.session
	var actual: Dictionary={"phase":loaded.phase,"cycle":loaded.cycle.stage,"day":loaded.day,"elapsed":loaded.elapsed,"paused":loaded.paused,"combat_tasks":loaded.combat.tasks.keys(),"membership":loaded.combat.membership.duplicate(true)}
	var actual_stacks: Array=[]
	for st in loaded.stacks.values():actual_stacks.append([st.id,st.recipe_guid,st.progress,st.paused,st.card_ids.duplicate()])
	check(actual==expected and actual_stacks==stack_fields,kind+" loaded exact relevant fallback input fields")
	var report: Variant=null
	for property in board.get_property_list():
		if property.name=="source_crafting_report":report=board.get("source_crafting_report")
	check(report is Dictionary and report.get("ok")==false and not str(report.get("reason","")).is_empty(),kind+" reports explicit old-path refusal")
	check(board.session.crafting.save_state()==previous,scene+" "+kind+" cold entry retains original task history")
	check(FileAccess.get_file_as_bytes(path)==bytes,kind+" original fixture file unchanged")

func run():
	var board=Board.new();board.feedback.free();board.feedback=SilentFeedback.new()
	board.slot_root=folder();board.options_path="user://cold-craft-options.json";board.legacy_paths.clear()
	root.add_child(board);await process_frame;board.set_process(false)
	if board.data_error!=OK:
		print("Source cold crafting board: SKIP private data unavailable")
		board.queue_free();await process_frame;quit();return
	for scene in ["Main","Island"]:
		cold_case(board,scene)
		for kind in ["deadline","near_deadline","feeding","paused_task","near_complete","combat"]: fallback_case(board,scene,kind)
	var owner=board.session
	board.selected_slot=0;board._continue_game()
	check(board.session==owner,"empty selection does not mutate active session")
	board.slot_root=folder();DirAccess.make_dir_recursive_absolute(board.slot_root)
	var file=FileAccess.open(board.slot_root+"/SaveSlot001.json",FileAccess.WRITE);file.store_string("broken");file.close()
	board.selected_slot=1;board._continue_game()
	check(board.session==owner,"invalid slot never reaches cold correction")
	print("COLD_CRAFTING_BOARD_OBSERVATIONS ",JSON.stringify(observations))
	board.queue_free();await process_frame;await process_frame
	print("Source cold crafting board: %d checks, %d failures; actual headless Continue" % [checks,failures])
	quit(1 if failures else 0)
