extends SceneTree
## Native transforms and event ordering, not GPU or Unity frame acceptance.
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
	var temp := "user://combat-preenter-%s" % Time.get_ticks_usec()
	board.slot_root = temp + "/slots"; board.options_path = temp + "/options.json"; board.legacy_paths.clear()
	root.add_child(board); await process_frame
	drain.observe_music(board.feedback.music)
	check(board.data_error == OK, "actual imported source catalog")
	if board.data_error != OK: board.free(); quit(1); return
	board.start_new(); board.set_process(false); board.vendor_unlock.cancel()
	var s = board.session
	var friendly := ""; var enemy := ""; var resource := ""
	for entry in board.catalog.data.cards:
		var f: Dictionary = entry.fields
		if int(f.get("category",0)) == 2 and int(f.get("faction",0)) == 1: friendly = entry.guid
		elif int(f.get("category",0)) == 9 and int(f.get("faction",0)) == 2: enemy = entry.guid
		elif int(f.get("category",0)) == 4: resource = entry.guid
	check(not friendly.is_empty() and not enemy.is_empty() and not resource.is_empty(), "authored fighter and unrelated resource fixtures")
	if friendly.is_empty() or enemy.is_empty() or resource.is_empty(): board.free(); quit(1); return
	for reversed in [false,true]:
		for id in s.cards.keys(): s._remove_card(id)
		board._refresh()
		s.spawn_target_selector = Callable(); s.spawn_layout_resolver = Callable()
		var a: int = s.spawn_card(friendly,Vector2(-2,0),-1,{"refuse_attach":true})
		var b: int = s.spawn_card(enemy,Vector2(2,0),-1,{"refuse_attach":true})
		var distant: int = s.spawn_card(resource,Vector2(4,2),-1,{"refuse_attach":true})
		board._refresh()
		# Preserve a normal-world unrelated stack. Entrants have actual horizontal
		# tween progress distinct from their model targets at source-ground height.
		board.views[a].position.x = -0.2
		board.views[b].position.x = 0.4
		s.ai.resync()
		for id in s.ai.agents: s.ai.agents[id].move_timer = 100
		for id in s.world.production_timers: s.world.production_timers[id] = 100
		var attackers := [b] if reversed else [a]
		var defenders := [a] if reversed else [b]
		var center: Vector2 = board._combat_start_center(attackers,defenders)
		var prior_resource: Vector2 = s.card_target_position(distant)
		var expected_rng := RandomNumberGenerator.new()
		expected_rng.state = s.rng.state
		var expected_progress := {}
		for id in attackers + defenders: expected_progress[id] = expected_rng.randf_range(0.0,0.5)
		var observed := []
		var recorder := func(event: String, payload: Dictionary):
			if event != "combat_entered": return
			var task: Dictionary = s.combat.tasks[payload.combat_id]
			check(task.has("layout"), "layout exists before first EnterCombat")
			if not task.has("layout"): return
			check(task.progress == expected_progress and s.rng.state == expected_rng.state, "all constructor RNG completed before first Enter")
			for member in attackers + defenders:
				var slot: Vector2 = task.layout.positions[member]
				check(board.views[member].position == Vector3(slot.x,0,-slot.y), "every native fighter instant grounded before Enter %s" % member)
				check(not board.card_motion.states.has(member), "old ordinary tween cleared before Enter")
			check(s.cards[payload.card_id].position == task.layout.positions[payload.card_id], "detach uses arranged slot rather than stale stack target")
			observed.append(payload.card_id)
		s.event_occurred.connect(recorder)
		var task_id: int = -1
		if reversed:
			check(s.world.aggressive_intent(b).action == "attack_player", "authored AI observes real nearby live player")
			s.ai.agents[b].move_timer = 0
			s.ai.tick(0.01)
			task_id = int(s.combat.membership.get(b,-1))
		else:
			task_id = s.combat.start_combat(attackers,defenders,true)
		s.event_occurred.disconnect(recorder)
		check(task_id >= 0 and observed == attackers + defenders, "real start uses source attacker-then-defender Enter order")
		check(s.combat.tasks[task_id].layout.center.is_equal_approx(center), "clamped source live center retained")
		check(s.card_target_position(distant) == prior_resource, "nonparticipant source overlap pass no-op")
		check(s.stacks.size() == 1 and s.cards[distant].stack_id in s.stacks, "only participating singleton stacks consumed")
		board._refresh()
		for member in attackers + defenders:
			var slot: Vector2 = s.combat.tasks[task_id].layout.positions[member]
			check(board.views[member].position == Vector3(slot.x,0,-slot.y), "next ordinary Board sync retains native slot")
	# Atomic guard: source pre-resolve attempted separation is rejected, even if
	# a boundary clamp could leave a final position unchanged.
	for id in s.cards.keys(): s._remove_card(id)
	board._refresh()
	var a: int = s.spawn_card(friendly,Vector2(-2,0),-1,{"refuse_attach":true})
	var b: int = s.spawn_card(enemy,Vector2(2,0),-1,{"refuse_attach":true})
	var distant: int = s.spawn_card(resource,Vector2(4,2),-1,{"refuse_attach":true})
	board._refresh()
	var before: Vector3 = board.views[a].position
	board._set_board_card_position(distant,s.card_target_position(a))
	check(board._combat_start_layout([a],[b],board._combat_start_center([a],[b])).is_empty(), "pre-resolve collision declines native fast path")
	check(board.views[a].position == before and board.card_motion.states.has(a), "rejected cohort makes no partial write")
	board._set_board_card_position(distant,Vector2.ZERO)
	check(board._combat_start_layout([a],[b],board._combat_start_center([a],[b])).is_empty(), "post-registration new rectangle collision declines fast path")
	check(board.views[a].position == before, "post-resolve guard remains atomic")
	board._set_board_card_position(distant,Vector2(4,2))
	check(board._combat_start_layout([a],[b],Vector2(2,2)).is_empty(), "stale supplied center rejected against fresh complete poses")
	check(board.views[a].position == before, "stale center rejection has no partial native write")
	board.views[b].position.y += 0.1
	check(board._combat_start_layout([a],[b],Vector2.ZERO).is_empty(), "one raised member rejects entire cohort")
	check(board.views[a].position == before, "mixed live pose does not partially arrange")
	board.queue_free(); await process_frame
	check(await drain.wait_after_teardown(self), "native audio drained")
	if failures == 0: print("Combat preenter Board: %d/%d passed" % [checks,checks])
	else: printerr("Combat preenter Board FAILED: %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)
