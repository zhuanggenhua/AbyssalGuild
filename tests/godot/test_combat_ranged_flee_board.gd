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
	var temp := "user://ranged-flee-%s" % Time.get_ticks_usec()
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
			var allies: Array = []
			for i in range(4): allies.append(s.spawn_card(guids[1],Vector2(5+i,0),-1,{"refuse_attach":true}))
			board._refresh()
			var task_id: int = s.combat.start_combat([actor] + allies,[target])
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
			var fleeing: int = allies.back()
			var observed := [false]
			var rng_before: int = s.rng.state
			var progress_before: Dictionary = task.progress.duplicate()
			progress_before.erase(fleeing)
			var resize_calls := [0]
			s.combat.resize_overlap_selector = func(_id): resize_calls[0] += 1; return []
			s.combat.flee_layout_updater = func(id):
				check(id == task_id and not s.combat.membership.has(fleeing), "flee scope after membership removal")
				check(fleeing not in task.combatants and s.cards[fleeing].stack_id == -1, "fleer left task but no departing stack registered before layout")
				board._combat_flee_layout(id)
				observed[0] = true
				for member in task.attackers + task.defenders:
					var slot: Vector2 = board.combat_layouts[id].positions[member]
					check(board.views[member].position == Vector3(slot.x,0,-slot.y), "survivor native slot immediately inside Flee %d/%s" % [type,phase])
					check(not board.card_motion.states.has(member), "flee clears surviving ordinary movement")
			check(s.combat.flee(fleeing) and observed[0], "real nonterminal Flee invokes native layout")
			check(s.cards[fleeing].stack_id >= 0 and s.stacks.has(s.cards[fleeing].stack_id), "departing stack registered after Flee layout")
			check(resize_calls[0] == 0, "Flee never invokes join overlap or merge")
			check(s.rng.state == rng_before and task.progress == progress_before, "flee preserves survivor progress and RNG")
			observed[0] = false
			check(not s.combat.flee(fleeing) and not observed[0], "second flee rejected without layout")
			check(not s.combat.flee(target) and not observed[0], "defender flee rejected without layout")
			check(board.views[actor].position != prior, "existing fighter actually rearranged")
			check(task.execution == execution, "exact execution payload and remaining timer unchanged by flee")
			check(task.visual_motion == visual and presentation.motions == motions, "captured phase motion unchanged by flee")
			check(presentation.projectile_flights == flights, "independent flight endpoint and age unchanged by flee")
			check(s.cards[target].health == hp and hits.size() == hit_count, "flee neither damages nor resumes execution")
			if phase == "travel":
				presentation.advance(0.1); s.combat.tick(0,0.1); board._sync_views()
				check(node.global_position.is_equal_approx(captured.start.lerp(captured.finish,0.6)), "flight retains original world endpoint after survivor slots changed")
				check(hits.is_empty(), "no premature damage at 0.3 seconds")
				presentation.advance(0.201); s.combat.tick(0,0.201); board._sync_views()
				check(hits.size() == 1 and task.execution.phase == "return", "single source impact at original duration")
			else:
				presentation.advance(0.1); s.combat.tick(0,0.1); board._sync_views()
				check(task.execution.phase == "return" and is_equal_approx(task.execution.remaining,0.1), "return wait continues original clock")
				check(hits.size() == 1, "return flee causes no second hit")
			# Direct actor removal retains the prior safety cancellation; it must not
			# acquire the idle branch after execution has been erased.
			s.combat.flee_layout_updater = func(_id): observed[0] = true
			observed[0] = false
			check(s.combat.flee(actor) and not observed[0], "active actor flee does not masquerade as idle resize")
			check(not task.has("execution"), "existing dangling actor safety cancellation retained")
			# Generic removals and terminal Flee are outside this hook.
			s.combat.remove_combatant(allies[0])
			check(not observed[0], "generic RemoveCombatant does not acquire Flee behavior")
			s.combat.remove_combatant(allies[1])
			check(s.combat.flee(allies[2]) and not observed[0] and not s.combat.tasks.has(task_id), "terminal Flee does not call surviving layout")
			s.combat.resize_overlap_selector = board._combat_resize_overlaps
			s.combat.flee_layout_updater = board._combat_flee_layout
			s.event_occurred.disconnect(recorder)
	board.queue_free(); await process_frame
	check(await drain.wait_after_teardown(self), "native audio drained")
	if failures == 0: print("Combat ranged flee Board: %d/%d passed" % [checks,checks])
	else: printerr("Combat ranged flee Board FAILED: %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
