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
	for entry in b.catalog.data.cards:
		if int(entry.fields.get("category",0)) == 2 and int(entry.fields.get("faction",0)) == 1 and int(entry.fields.get("combatType",0)) == 1: friendly = entry.guid
		if int(entry.fields.get("category",0)) == 9 and int(entry.fields.get("faction",0)) == 2: hostile = entry.guid
	if friendly.is_empty() or hostile.is_empty(): b.free(); quit(2); return
	var departing: int = s.spawn_card(friendly, Vector2(-2,0), -1, {"refuse_attach":true})
	var first: int = s.spawn_card(hostile, Vector2(1,0), -1, {"refuse_attach":true})
	var second: int = s.spawn_card(hostile, Vector2(4,0), -1, {"refuse_attach":true})
	b._refresh()
	var task: int = s.combat.start_combat([departing],[first,second])
	b._refresh()
	var observation: Dictionary = {}
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
		expect(s.cards[departing].stack_id == -1, "departing not registered during layout")
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
		closer.call(id)
		expect(not b.combat_rectangles.has(id) and not b.combat_layouts.has(id), "close excludes rectangle from live geometry")
	var on_end: Callable = func(kind: String, payload: Dictionary) -> void:
		if kind == "combat_ended" and int(payload.combat_id) == task:
			expect(s.cards[first].stack_id >= 0 and s.cards[second].stack_id >= 0 and s.cards[departing].stack_id >= 0, "public completion event after all registrations")
			expect(not s.combat.membership.has(first) and not s.combat.membership.has(second), "public event after survivors LeaveCombat")
	s.event_occurred.connect(on_end)
	var held_start: Vector3 = b.views[departing].position
	var press := b.camera.unproject_position(held_start)
	b._begin_card_press({"card_id":departing},press)
	var ghost := InputEventMouseMotion.new()
	ghost.position = b.camera.unproject_position(Vector3(s.board_bounds.end.x+5,0,-s.board_bounds.end.y-5))
	b._input(ghost)
	b._advance_running_frame(0.0)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = ghost.position
	b._input(release)
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
	s.combat.terminal_flee_layout_sampler = sampler
	s.combat.terminal_flee_rect_closer = closer
	s.event_occurred.disconnect(on_end)
	on_end = Callable()
	b.queue_free()
	await process_frame
	expect(await drain.wait_after_teardown(self), "native audio drains")
	print("Combat terminal flee Board: %d/%d passed" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
