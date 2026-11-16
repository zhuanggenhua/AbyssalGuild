extends SceneTree
## Private imported fixtures required. Native node assertions, not rendered-image proof.
const Board = preload("res://scripts/ui/board.gd")
const AudioDrain = preload("res://tests/godot/source_test_audio_drain.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ",label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Board.new()
	var drain := AudioDrain.new()
	var temp := "user://ranged-resize-%s" % Time.get_ticks_usec()
	board.slot_root = temp + "/slots"; board.options_path = temp + "/options.json"; board.legacy_paths.clear()
	root.add_child(board); await process_frame
	drain.observe_music(board.feedback.music)
	check(board.data_error == OK, "actual imported source catalog")
	if board.data_error != OK: board.free(); quit(1); return
	board.start_new(); board.set_process(false); board.vendor_unlock.cancel()
	var s = board.session
	var guids := {1:"",2:"",3:"",4:""}
	for entry in board.catalog.data.cards:
		var f: Dictionary = entry.fields
		var type := int(f.get("combatType",0))
		if int(f.get("category",0)) == 2 and int(f.get("faction",0)) == 1 and type in [1,2,3]: guids[type] = entry.guid
		elif int(f.get("category",0)) == 9 and int(f.get("faction",0)) == 2: guids[4] = entry.guid
	for type in guids:
		check(not guids[type].is_empty(), "source card type %d" % type)
		if guids[type].is_empty(): board.free(); quit(1); return
	for type in [2,3]:
		for phase in ["travel", "return"]:
			for id in s.cards.keys(): s._remove_card(id)
			board._refresh()
			s.spawn_target_selector = Callable(); s.spawn_layout_resolver = Callable()
			var actor: int = s.spawn_card(guids[type],Vector2(-2,0),-1,{"refuse_attach":true})
			var target: int = s.spawn_card(guids[4],Vector2(0,0),-1,{"refuse_attach":true})
			board._refresh()
			var task_id: int = s.combat.start_combat([actor],[target])
			board._refresh()
			s.cards[target].health = 10000 # Keep fixture alive regardless of source card chosen.
			var hits: Array = []
			var recorder := func(event: String, payload: Dictionary):
				if event == "combat_hit": hits.append(payload.duplicate(true))
			s.event_occurred.connect(recorder)
			s.combat.tasks[task_id].progress[actor] = 50.0
			s.combat.resolve_turn(task_id)
			board._sync_views()
			var presentation = board.combat_presentation
			var node: Node3D = presentation.projectiles.get(task_id)
			check(node is Sprite3D, "actual authored projectile type %d" % type)
			if node == null: board.free(); quit(1); return
			var captured: Dictionary = s.combat.tasks[task_id].visual_motion.duplicate(true)
			check(captured.duration == 0.5, "source prefab duration")
			presentation.advance(0.2); s.combat.tick(0,0.2); board._sync_views()
			check(node.global_position.is_equal_approx(captured.start.lerp(captured.finish,0.4)), "actual native midtravel")
			if phase == "return":
				presentation.advance(0.31); s.combat.tick(0,0.31); board._sync_views()
				presentation.advance(0.1); s.combat.tick(0,0.1); board._sync_views()
				check(hits.size() == 1, "source impact before return")
			var task: Dictionary = s.combat.tasks[task_id]
			check(task.execution.phase == phase, "actual requested execution phase")
			var execution: Dictionary = task.execution.duplicate(true)
			var visual: Dictionary = task.visual_motion.duplicate(true)
			var flights: Dictionary = presentation.projectile_flights.duplicate(true)
			var motions: Dictionary = presentation.motions.duplicate(true)
			var hit_count := hits.size()
			var hp: int = s.cards[target].health
			var prior: Vector3 = board.views[actor].position
			# Add enough same-side real recruits to resize an existing row.
			var recruits: Array = []
			for i in range(4): recruits.append(s.spawn_card(guids[1],Vector2(5+i,0),-1,{"refuse_attach":true}))
			board._refresh()
			var observed := [false]
			s.combat.resize_overlap_selector = func(id):
				var overlaps: Array = board._combat_resize_overlaps(id)
				observed[0] = true
				check(overlaps.is_empty(), "isolated fixture has no unrelated merge")
				for member in task.attackers + task.defenders:
					var slot: Vector2 = board.combat_layouts[id].positions[member]
					check(board.views[member].position == Vector3(slot.x,0,-slot.y), "instant source slot at overlap observation %d/%s" % [type,phase])
					check(not board.card_motion.states.has(member), "instant source placement clears ordinary card motion")
				return overlaps
			check(s.combat.add_combatants(task_id,recruits) and observed[0], "real AddCombatants invokes native resize")
			check(board.views[actor].position != prior, "existing fighter actually rearranged")
			check(task.execution == execution, "exact execution payload and remaining timer unchanged by resize")
			check(task.visual_motion == visual and presentation.motions == motions, "captured phase motion unchanged by resize")
			check(presentation.projectile_flights == flights, "independent flight endpoint and age unchanged by resize")
			check(s.cards[target].health == hp and hits.size() == hit_count, "resize neither damages nor resumes execution")
			if phase == "travel":
				presentation.advance(0.1); s.combat.tick(0,0.1); board._sync_views()
				check(node.global_position.is_equal_approx(captured.start.lerp(captured.finish,0.6)), "flight retains original world endpoint after target slots changed")
				check(hits.is_empty(), "no premature damage at 0.3 seconds")
				presentation.advance(0.201); s.combat.tick(0,0.201); board._sync_views()
				check(hits.size() == 1 and task.execution.phase == "return", "single source impact at original duration")
			else:
				presentation.advance(0.1); s.combat.tick(0,0.1); board._sync_views()
				check(task.execution.phase == "return" and is_equal_approx(task.execution.remaining,0.1), "return wait continues original clock")
				check(hits.size() == 1, "return resize causes no second hit")
			# Retain rejection/fallback of unrelated or incomplete active states.
			var original: Dictionary = task.execution.duplicate(true)
			for bad in [{"actor":actor}, {"actor":actor,"target":target,"combat_type":1,"phase":"travel","remaining":0.2}, {"actor":actor,"target":target,"combat_type":2,"phase":"death_wait","remaining":0.2}, {"actor":actor,"target":target,"combat_type":2,"phase":"unknown","remaining":0.2}, {"actor":actor,"target":target,"combat_type":2,"phase":"travel"}]:
				task.execution = bad
				board.views[actor].position.x += 1
				var before: Vector3 = board.views[actor].position
				check(not board._combat_resize_native_slots(task_id) and board.views[actor].position == before, "unknown/melee/death-wait guard stays atomic")
			task.execution = original
			s.combat.dragged[actor] = true
			var before_drag: Vector3 = board.views[actor].position
			check(not board._combat_resize_native_slots(task_id) and board.views[actor].position == before_drag, "ranged dragged guard stays atomic")
			s.combat.dragged.erase(actor)
			s.combat.resize_overlap_selector = board._combat_resize_overlaps
			s.event_occurred.disconnect(recorder)
	board.queue_free(); await process_frame
	check(await drain.wait_after_teardown(self), "native audio drained")
	if failures == 0: print("Combat ranged resize Board: %d/%d passed" % [checks,checks])
	else: printerr("Combat ranged resize Board FAILED: %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
