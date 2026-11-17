extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const Drain = preload("res://tests/godot/source_test_audio_drain.gd")
var failures := 0
var checks := 0
func expect(ok: bool, title: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ",title)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var b := Board.new()
	var drain := Drain.new()
	b.slot_root = "user://terminal-source/slots"; b.options_path = "user://terminal-source/options.json"; b.legacy_paths.clear()
	root.add_child(b)
	await process_frame
	drain.observe_music(b.feedback.music)
	if b.data_error != OK: b.free(); quit(2); return
	b.start_new()
	b.set_process(false)
	b.vendor_unlock.cancel()
	var s = b.session
	for id in s.cards.keys(): s._remove_card(id)
	b._refresh()
	s.spawn_target_selector = Callable()
	s.spawn_layout_resolver = Callable()
	var friendly := ""
	var hostile := ""
	var passive := ""
	for entry in b.catalog.data.cards:
		if int(entry.fields.get("category",0)) == 2 and int(entry.fields.get("faction",0)) == 1 and int(entry.fields.get("combatType",0)) == 1: friendly = entry.guid
		if entry.fields.get("displayName", "") == "Crab": hostile = entry.guid
		if entry.fields.get("displayName", "") == "Chicken": passive = entry.guid
	if friendly.is_empty() or hostile.is_empty() or passive.is_empty(): b.free(); quit(2); return
	var departing: int = s.spawn_card(friendly, Vector2(-2,0), -1, {"refuse_attach":true})
	# Reverse identity/insertion order so a public-event resync cannot pass.
	var second: int = s.spawn_card(hostile, Vector2(4,0), -1, {"refuse_attach":true})
	var first: int = s.spawn_card(passive, Vector2(1,0), -1, {"refuse_attach":true})
	expect(not s.ai.has_ai(departing), "locked departing player prefab has no AI")
	expect(s.ai.has_ai(first) and s.ai.has_ai(second), "locked producer and aggressive prefabs have AI")
	b._refresh()
	# Compare confirmed ordinary input against the combat early-return branch using
	# the real imported AudioManager and actual allocated native audio slots.
	b.feedback.last_played.erase("CardPick")
	b.feedback.last_played.erase("CardDrop")
	var standard_point: Vector2 = b.camera.unproject_position(b.views[departing].global_position)
	var slot_before: int = b.feedback.next_player
	b._begin_card_press({"card_id":departing},standard_point)
	expect(b.dragging == departing and b.feedback.last_played.has("CardPick"), "accepted standard press requests CardPick")
	expect(b.feedback.next_player == (slot_before+1)%b.feedback.pool.size() and b.feedback.pool[slot_before].stream == b.feedback.stream_for_event("CardPick"), "standard CardPick routes original clip to native pool")
	var standard_up := InputEventMouseButton.new()
	standard_up.button_index = MOUSE_BUTTON_LEFT; standard_up.position = standard_point
	b._input(standard_up)
	expect(b.feedback.last_played.has("CardDrop"), "accepted standard release requests CardDrop")
	b.feedback.last_played.erase("CardPick")
	b.feedback.last_played.erase("CardDrop")
	var task: int = s.combat.start_combat([departing],[first,second])
	b._refresh()
	var observation: Dictionary = {}
	var expected: Dictionary = {}
	var held_expected: Array = []
	var sampler: Callable = s.combat.terminal_flee_layout_sampler
	var closer: Callable = s.combat.terminal_flee_rect_closer
	expect(sampler.call(task).is_empty(), "nonterminal task excluded")
	var original_attackers: Array = s.combat.tasks[task].attackers
	s.combat.tasks[task].attackers = []
	s.combat.tasks[task].execution = {"actor": departing, "target": first}
	expect(sampler.call(task).is_empty(), "active execution excluded")
	s.combat.tasks[task].erase("execution")
	b.position = Vector3(0.25, 0, 0)
	expect(sampler.call(task).is_empty(), "transformed board excluded")
	b.position = Vector3.ZERO
	s.combat.tasks[task].attackers = original_attackers
	s.combat.terminal_flee_layout_sampler = func(id: int) -> Dictionary:
		expect(id == task and not s.combat.membership.has(departing), "departing LeaveCombat before terminal layout")
		expect(b.feedback.last_played.has("CardDrop"), "combat CardDrop dispatched before Flee classification and terminal layout")
		expect(s.cards[departing].stack_id == -1, "departing not registered during layout")
		expect(not held_expected.is_empty() and s.cards[departing].position.is_equal_approx(held_expected[0]), "terminal layout observes held position before header placement")
		var receipt: Dictionary = sampler.call(id)
		expect(receipt.get("ok", false), "source-backed native terminal receipt")
		observation.merge(receipt)
		for survivor in [first, second]:
			var actual: Vector3 = b.views[survivor].global_position
			expect(actual.y == 0.0 and receipt.positions[survivor] == Vector2(actual.x,-actual.z), "post-layout actual transform observed")
			expect(s.cards[survivor].stack_id == -1 and s.combat.membership.has(survivor), "survivor still combat-owned before close")
		return receipt
	s.combat.terminal_flee_rect_closer = func(id: int) -> void:
		expect(not s.combat.tasks.has(id), "Finished before Rect.Close")
		expect(s.cards[first].stack_id == -1 and s.cards[second].stack_id == -1 and s.cards[departing].stack_id == -1, "close before all singleton registrations")
		expect(not s.ai.agents[first].running and not s.ai.agents[second].running, "survivor AI still stopped at Rect.Close")
		closer.call(id)
		expect(not b.combat_rectangles.has(id) and not b.combat_layouts.has(id), "close excludes rectangle from live geometry")
	var on_end: Callable = func(kind: String, payload: Dictionary) -> void:
		if kind == "combat_ended" and int(payload.combat_id) == task:
			expect(s.cards[first].stack_id >= 0 and s.cards[second].stack_id >= 0 and s.cards[departing].stack_id >= 0, "public completion event after all registrations")
			expect(is_equal_approx(s.ai.agents[first].move_timer, expected.move_first) and is_equal_approx(s.world.production_timers[first], expected.produce_first) and is_equal_approx(s.ai.agents[second].move_timer, expected.move_second), "ordered timers already settled at public event")
			expect(not s.combat.membership.has(first) and not s.combat.membership.has(second), "public event after survivors LeaveCombat")
	s.event_occurred.connect(on_end)
	s.combat.tasks[task].execution = {"actor":second,"target":departing}
	expect(not b._source_combat_hold_allowed(departing), "terminal active execution never admitted")
	s.combat.tasks[task].erase("execution")
	var missing_view = b.views[first]
	b.views.erase(first)
	expect(not b._source_combat_hold_allowed(departing), "terminal missing survivor node never admitted")
	b.views[first] = missing_view
	var preview: Dictionary = b.CombatLayout.update_layout(b.combat_layouts[task],[],b._fighter_records([first,second]))
	var survivor_target: Vector2 = b._clamp_stack_position(first,preview.positions[first],true)
	expect(not b._source_flee_unobstructed(departing,survivor_target), "terminal contact guard includes newly registered survivor singleton")
	var held_start: Vector3 = b.views[departing].position
	var press := b.camera.unproject_position(held_start + Vector3(-.13,0,.09))
	slot_before = b.feedback.next_player
	b._begin_card_press({"card_id":departing},press)
	expect(not b.feedback.last_played.has("CardPick") and b.feedback.next_player == slot_before, "accepted combat press emits no CardPick request or audio slot")
	expect(b._combat_hold.get("id",-1) == departing, "idle last attacker admitted to source hold")
	expect(b.views[departing].global_position == held_start, "terminal press preserves actual pose until frame")
	var ghost := InputEventMouseMotion.new()
	ghost.position = b.camera.unproject_position(Vector3(s.board_bounds.end.x+5,0,-s.board_bounds.end.y-5))
	b._input(ghost)
	expect(b.views[departing].global_position == held_start, "terminal motion only records pending pointer")
	b._advance_running_frame(0.0)
	var actual: Vector3 = b.views[departing].global_position
	var held_point: Vector2 = b._clamp_stack_position(departing,Vector2(held_start.x,-held_start.z) + b._board_point(ghost.position)-b._board_point(press),false)
	held_expected.append(held_point)
	expect(Vector2(actual.x,-actual.z).is_equal_approx(held_point) and is_equal_approx(actual.y,.1), "terminal frame uses offset and authored held height with physical clamp")
	var settled: Vector2 = b._clamp_stack_position(departing,held_point,true)
	expect(not held_point.is_equal_approx(settled), "held point remains inside restricted header until placement")
	expect(b._source_flee_unobstructed(departing,settled), "terminal no-contact preview includes survivor singletons and excludes closed rectangle")
	# No Update follows this new inside pointer: source release reads actual pose.
	ghost.position = b.camera.unproject_position(held_start)
	b._input(ghost)
	expect(b.views[departing].global_position == actual, "pending inside pointer does not overwrite last held pose")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = ghost.position
	var rng := RandomNumberGenerator.new()
	rng.seed = s.rng.seed
	rng.state = s.rng.state
	expected.move_first = rng.randf_range(.5,1) + s.ai.move_interval
	expected.produce_first = rng.randf_range(.5,1) + float(s.catalog.fields(passive).get("produceInterval",10.0))
	expected.move_second = rng.randf_range(.5,1) + s.ai.move_interval
	var next := rng.randi()
	b._input(release)
	expect(not b.feedback.last_played.has("CardPick"), "combat release never synthesizes missing CardPick")
	expect(b.feedback.next_player == (slot_before+1)%b.feedback.pool.size() and b.feedback.pool[slot_before].stream == b.feedback.stream_for_event("CardDrop"), "combat release allocates only original CardDrop clip")
	expect(s.card_target_position(departing).is_equal_approx(settled), "terminal release applies header placement after Flee despite inside release point")
	expect(b._combat_hold.is_empty(), "terminal hold consumed")
	expect(is_equal_approx(s.ai.agents[first].move_timer, expected.move_first), "producer movement draw first")
	expect(is_equal_approx(s.world.production_timers[first], expected.produce_first), "producer production draw second")
	expect(is_equal_approx(s.ai.agents[second].move_timer, expected.move_second), "next survivor movement draw third")
	expect(s.rng.randi() == next, "public resync does not duplicate restart RNG")

	expect(not s.combat.tasks.has(task) and not b.combat_rectangles.has(task), "terminal rectangle removed from live solver")
	var depart_stack: int = s.cards[departing].stack_id
	var first_stack: int = s.cards[first].stack_id
	var second_stack: int = s.cards[second].stack_id
	expect(first_stack >= 0 and second_stack > first_stack and depart_stack > second_stack, "source defender registration order precedes departing stack")
	expect(s.stacks[depart_stack].card_ids == [departing], "departing stack independent")
	expect(not observation.is_empty(), "native receipt was consumed")
	for survivor in [first, second]:
		expect(s.cards[survivor].position == observation.targets[survivor], "source-enforced placement target retained")
	# Guard rejection is tested with a separately restored callback while the
	# finished task is gone; no receipt may be replayed to close another task.
	expect(sampler.call(task).is_empty(), "finished task cannot produce another receipt")
	# Missing-agent recovery must run register's single restart, not restart again.
	s.ai.agents.erase(first)
	rng.state = s.rng.state
	var missing_move: float = rng.randf_range(.5,1) + s.ai.move_interval
	var missing_produce: float = rng.randf_range(.5,1) + float(s.catalog.fields(passive).get("produceInterval",10.0))
	var missing_next := rng.randi()
	s.ai.leave_combat(first)
	expect(is_equal_approx(s.ai.agents[first].move_timer, missing_move) and is_equal_approx(s.world.production_timers[first],missing_produce), "missing agent starts both timers once")
	expect(s.rng.randi() == missing_next, "missing agent registration no duplicate draw")
	s.combat.terminal_flee_layout_sampler = sampler
	s.combat.terminal_flee_rect_closer = closer
	s.event_occurred.disconnect(on_end)
	on_end = Callable()
	b.queue_free()
	await process_frame
	expect(await drain.wait_after_teardown(self), "native audio drains")
	print("Combat terminal flee Board: %d/%d passed" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
