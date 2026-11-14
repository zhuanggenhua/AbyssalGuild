extends SceneTree
## Actual Board request -> normal departure save -> fade commit -> arrival save.
## Headless production calls, not GUI/Unity/PhysX or a new natural gameplay run.
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const Travel = preload("res://scripts/ui/source_travel_layout.gd")
const Planner = preload("res://scripts/model/source_restore_layout.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_kind: String) -> bool: return false
	func play_music() -> bool: return false
class ObservedBoard extends "res://scripts/ui/board.gd":
	var commits: Array = []
	var checkpoints: Array = []
	var arrival_events: Array = []
	var arrival_changes: int = 0
	func _checkpoint(label: String) -> Dictionary:
		checkpoints.append(label)
		return super._checkpoint(label)
	func _commit_travel(owner, candidate, provenance: Dictionary = {}) -> void:
		commits.append({"context": provenance.duplicate(true), "context_ref": provenance, "snapshot": candidate.campaign.capture()})
		candidate.event_occurred.connect(func(kind, payload): arrival_events.append([kind, payload.duplicate(true)]))
		candidate.changed.connect(func(): arrival_changes += 1)
		super._commit_travel(owner, candidate, provenance)
var checks := 0
var failures := 0
var serial := 0
var cases: Array = []
var rejections: Array = []
func check(ok: bool, label: String):
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func _init(): call_deferred("run")
func directory() -> String:
	serial += 1
	return "user://travel-layout-%d-%d" % [Time.get_ticks_usec(), serial]
func normalized(data: Dictionary) -> Dictionary:
	var copy := data.duplicate(true); copy.erase("last_saved")
	var active: Dictionary = copy.scenes[copy.current_scene].session
	for card in active.cards: card.erase("position")
	for stack in active.stacks: stack.erase("position")
	active.stacks.sort_custom(func(a, b): return a.id < b.id)
	return copy
func targets(s) -> Array:
	var result: Array = []
	for stack in s.stacks.values(): result.append({"id": stack.id, "cards": stack.card_ids.duplicate(), "position": stack.position})
	return result
func fixture(board, source_scene: String, geared: bool):
	var target := "Island" if source_scene == "Main" else "Main"
	var source = Session.new(); source.configure(board.catalog, 123, source_scene); source.paused = true
	var destination = Session.new(); destination.configure(board.catalog, 123, target); destination._next_id = 1000; destination.paused = true
	for pair in [["Wood", Vector2(-5.55, 0)], ["Wood", Vector2(-5.0, 0.05)], ["Stone", Vector2(-4.5, -0.2)]]:
		destination.spawn_card(board.catalog.find_by_name(pair[0]), pair[1], -1, {"refuse_attach": true})
	source.campaign.saved_scenes[target] = Codec.capture(destination)
	var portal: int = source.spawn_card(board.catalog.find_by_name("Grand Portal"))
	var hero: int = source.spawn_card(board.catalog.find_by_name("Villager"), Vector2.ZERO, source.cards[portal].stack_id)
	if geared:
		for name in ["Sword", "Chainmail", "Vitality Amulet"]:
			var item: int = source.spawn_card(board.catalog.find_by_name(name), Vector2(4, 2), -1, {"refuse_attach": true})
			check(source.equipment.equip(hero, item), "source gear " + name)
	check(source.campaign.restore(source.campaign.capture()).ok, "canonical loaded campaign fixture")
	return source
func prepare(board, source) -> int:
	board.scene_transition.cancel()
	board.session = source; board.slot_root = directory()
	board.slots.configure(source.campaign, board.slot_root)
	var created: Dictionary = board.slots.create_slot(); check(created.ok, "normal private slot creation")
	board.active_slot = int(created.slot); board.selected_slot = board.active_slot
	board._enter_game()
	board.commits.clear(); board.checkpoints.clear(); board.arrival_events.clear(); board.arrival_changes = 0
	for card in source.cards.values():
		if card.definition_guid == board.catalog.find_by_name("Grand Portal"): return card.stack_id
	return -1
func independent_candidate(board, source, sid: int) -> Dictionary:
	var candidate = Session.new(); candidate.configure(board.catalog)
	check(candidate.campaign.restore(source.campaign.capture()).ok, "independent exact frozen candidate")
	var provenance := Travel.capture(source, sid, Travel.RECIPE_GUID)
	var result: Dictionary = candidate.campaign.travel(sid, Travel.RECIPE_GUID)
	check(result.ok, "unchanged model transaction succeeds")
	return {"session": candidate, "result": result, "context": Travel.seal(candidate, result, provenance)}
func probe_board(board, session):
	var probe = preload("res://scripts/ui/board.gd").new()
	probe.catalog = board.catalog; probe.visual_assets = board.visual_assets; probe.session = session
	var boost: float = clampf((session.stats().card_limit - int(board.catalog.settings("CardSettings").get("baseCardLimit", 24))) / 100.0, 0.0, 1.0)
	probe.session.board_bounds = probe.visual_assets.board_local_rect(session.scene_name, boost)
	if not probe.session.board_bounds.has_area(): probe.session.board_bounds = Rect2(Vector2(-6, -4) * (1.0 + boost), Vector2(12, 8) * (1.0 + boost))
	return probe
func free_probe(probe):
	probe.feedback.free(); probe.vendor_unlock.free(); probe.free()
func trip(board, source, label: String, admitted: bool):
	var sid := prepare(board, source)
	check(sid > 0, label + " travel stack present")
	var original_ids: Array = source.stacks[sid].card_ids.duplicate()
	var expected := independent_candidate(board, source, sid)
	var probe = probe_board(board, expected.session)
	var planned := Travel.plan(probe, expected.context)
	check(planned.ok == admitted, label + " independent admission: " + str(planned.get("reason", "")))
	if planned.ok:
		check(planned.trace[0].event == "traveler_initialize", label + " source traveler initializes before saved destination")
		check(Planner.apply(expected.session, planned).ok, label + " independent geometry oracle apply")
		probe.layout_key = probe._layout_signature()
	else:
		probe._ensure_layout() # Unchanged old whole-board fallback, not source replay.
	var expected_targets := targets(expected.session)
	var model_snapshot: Dictionary = expected.session.campaign.capture()
	free_probe(probe)
	var old_events: Array = []; source.event_occurred.connect(func(kind, payload): old_events.append([kind, payload.duplicate(true)]))
	check(board._request_travel(sid, Travel.RECIPE_GUID), label + " real request accepts")
	var departure_path: String = board.slots.slot_path(board.active_slot)
	var departure_bytes := FileAccess.get_file_as_bytes(departure_path)
	var departure = Session.new(); departure.configure(board.catalog)
	check(departure.campaign.load_file(departure_path).ok and departure.scene_name == source.scene_name, label + " checkpoint remains departure before fade")
	check(board.session == source and board.commits.is_empty(), label + " no entry before fade")
	check(not board._request_travel(sid, Travel.RECIPE_GUID), label + " duplicate request rejected without another checkpoint")
	board.scene_transition.advance(0.5)
	check(board.session == source and FileAccess.get_file_as_bytes(departure_path) == departure_bytes, label + " half fade retains departure")
	board.scene_transition.advance(0.5)
	check(board.session != source and board.commits.size() == 1, label + " commit at black exactly once")
	var context: Dictionary = board.commits[0].context
	if admitted:
		check(context.source_ids == original_ids and context.remap == expected.result.traveler_ids, label + " exact source IDs/remap survive checkpoint")
		check(not context.consumed, label + " provenance not applied during staging/checkpoint")
	check(board.source_travel_report.get("ok", false) == admitted, label + " production admission result")
	check(targets(board.session) == expected_targets, label + " exact registered source-order targets or unchanged fallback")
	check(normalized(board.session.campaign.capture()) == normalized(model_snapshot), label + " all nongeometry IDs/equipment/RNG/events/quests/inactive state preserved")
	check(board.arrival_events.is_empty() and board.arrival_changes == 0 and old_events.is_empty(), label + " entry emits no duplicate gameplay signals")
	check(board.checkpoints == ["Travel departure", "Arrived at " + board.session.scene_name], label + " original two checkpoints only")
	var at_entry := targets(board.session)
	for i in 3: board._sync_views(0.0)
	check(targets(board.session) == at_entry, label + " no accidental second placement pass")
	var arrived = Session.new(); arrived.configure(board.catalog)
	check(arrived.campaign.load_file(board.slots.slot_path(board.active_slot)).ok and targets(arrived) == at_entry, label + " real arrival save records final target geometry")
	check(JSON.parse_string(JSON.stringify(normalized(arrived.campaign.capture()), "", true, true)) == JSON.parse_string(JSON.stringify(normalized(model_snapshot), "", true, true)), label + " arrival reread preserves all nongeometry")
	var before := Codec.capture(board.session)
	check(not Travel.apply(board, board.commits[0].context_ref).ok and Codec.capture(board.session) == before, label + " consumed context cannot be reapplied")
	if not admitted: rejections.append({"case": label, "reason": board.source_travel_report.get("reason", "")})
	cases.append({"case": label, "admitted": admitted, "targets": at_entry, "report": board.source_travel_report, "remap": expected.result.traveler_ids, "rng": str(board.session.rng.state)})
	board.scene_transition.advance(1.0)
func rejected(board, label: String, context: Dictionary):
	var before := Codec.capture(board.session)
	var report := Travel.apply(board, context)
	check(not report.ok and Codec.capture(board.session) == before, label + " rejected geometry leaves production state untouched")
	rejections.append({"case": label, "reason": report.get("reason", "")})
func guard_matrix(board):
	var source = fixture(board, "Main", false)
	var sid: int = source.stacks.values()[0].id
	var entry := independent_candidate(board, source, sid)
	var probe = probe_board(board, entry.session)
	check(Travel.plan(probe, entry.context).ok, "guard baseline")
	for phase in ["feeding", "selling", "encounter", "ready", "game_over"]:
		probe.session.phase = phase
		var context: Dictionary = entry.context.duplicate(true); context.snapshot = probe.session.campaign.capture()
		rejected(probe, "phase_" + phase, context)
	probe.session.phase = "playing"
	for stage in ["await_feed", "character_focus", "food_lift", "food_travel", "food_chew", "leftover_settle", "character_wait", "selling", "encounter_notification", "encounter_focus", "encounter_wait"]:
		probe.session.cycle._state.stage = stage
		var context: Dictionary = entry.context.duplicate(true); context.snapshot = probe.session.campaign.capture()
		rejected(probe, "cycle_" + stage, context)
	probe.session.cycle._state.stage = "idle"
	for mode in ["source_selling", "source_cycle", "source_clock", "source_held"]:
		match mode:
			"source_selling": source.phase = "selling"
			"source_cycle": source.cycle._state.stage = "character_focus"
			"source_clock": source.elapsed = source.day_duration
			"source_held": source.drag.card_id = source.stacks[sid].card_ids[0]
		rejected(probe, mode, Travel.capture(source, sid, Travel.RECIPE_GUID))
		source.phase = "playing"; source.cycle._state.stage = "idle"; source.elapsed = 0; source.drag.reset()
	for mode in ["clock", "craft", "combat", "boost"]:
		var original := Codec.capture(probe.session)
		match mode:
			"clock": probe.session.elapsed = probe.session.day_duration
			"craft": probe.session.stacks.values()[0].recipe_guid = Travel.RECIPE_GUID
			"combat": probe.session.combat.membership[probe.session.cards.keys()[0]] = 1
			"boost": probe.session.spawn_card(board.catalog.find_by_name("Warehouse"), Vector2.ZERO, -1, {"refuse_attach": true})
		var context: Dictionary = entry.context.duplicate(true); context.snapshot = probe.session.campaign.capture()
		rejected(probe, "destination_" + mode, context)
		check(Codec.restore(probe.session, original).ok, "guard fixture restored")
	source.campaign.saved_scenes.clear()
	rejected(probe, "new_default", Travel.capture(source, sid, Travel.RECIPE_GUID))
	check(rejections.size() == 25, "25 synthetic boundary cases (plus real expanded target below)")
	# Explicit provenance tampering is not inferred/fixed from IDs or card names.
	for mode in ["missing_map", "repeated_map", "wrong_definition"]:
		var fresh = fixture(board, "Main", false); var stack: int = fresh.stacks.values()[0].id
		var prior := Travel.capture(fresh, stack, Travel.RECIPE_GUID)
		var result: Dictionary = fresh.campaign.travel(stack, Travel.RECIPE_GUID)
		match mode:
			"missing_map": result.traveler_ids.erase(result.traveler_ids.keys()[0])
			"repeated_map": result.traveler_ids[result.traveler_ids.keys()[0]] = result.traveler_ids.values()[1]
			"wrong_definition": fresh.cards[result.traveler_ids.values()[0]].definition_guid = board.catalog.find_by_name("Wood")
		check(not Travel.seal(fresh, result, prior).ok, "explicit provenance rejects " + mode)
	# A stale candidate is refused without partially changing other stack targets.
	var before_stale := Codec.capture(probe.session)
	probe.session.cards.values()[0].health += 1
	var changed := Codec.capture(probe.session)
	check(not Travel.apply(probe, entry.context.duplicate(true)).ok and Codec.capture(probe.session) == changed, "stale candidate snapshot refuses full plan atomically")
	check(Codec.restore(probe.session, before_stale).ok, "stale fixture restored")
	probe.session.campaign.saved_scenes["Main"].session.elapsed += 1
	var campaign_changed: Dictionary = probe.session.campaign.capture()
	check(not Travel.apply(probe, entry.context.duplicate(true)).ok and probe.session.campaign.capture() == campaign_changed, "stale inactive scene rejects plan without any campaign mutation")
	free_probe(probe)
func atomicity(board):
	var source = fixture(board, "Main", false); var sid := prepare(board, source)
	var path: String = board.slots.slot_path(board.active_slot); var bytes := FileAccess.get_file_as_bytes(path)
	var prior := Codec.capture(source); var old_root: String = board.slot_root
	board.slot_root = "/proc/source-travel-invalid"
	check(not board._request_travel(sid, Travel.RECIPE_GUID) and board.session == source and not board.scene_transition.active(), "failed checkpoint never swaps/applies candidate")
	check(FileAccess.get_file_as_bytes(path) == bytes and source.cards.size() == prior.session.cards.size() and source.rng.state == int(prior.session.rng_state), "failure leaves slot/cards/RNG; original craft cancellation policy retained")
	board.slot_root = old_root
	check(board._request_travel(sid, Travel.RECIPE_GUID), "next request after checkpoint failure succeeds")
	board.scene_transition.cancel(); board.scene_transition.advance(2)
	check(board.session == source and board.commits.is_empty(), "cancelled fade discards bound context without entry")
	var candidate := independent_candidate(board, source, sid)
	var unrelated = Session.new(); unrelated.configure(board.catalog)
	board._commit_travel(unrelated, candidate.session, candidate.context)
	check(board.session == source and candidate.session.campaign.capture() == candidate.context.snapshot, "stale owner cannot apply geometry or swap session")
	var wrong_probe = probe_board(board, unrelated)
	check(not Travel.apply(wrong_probe, candidate.context).ok, "candidate reference must match entry")
	free_probe(wrong_probe)
func real_case(board, variable: String, admitted: bool):
	var path := OS.get_environment(variable)
	if path.is_empty(): return
	var before := FileAccess.get_sha256(path)
	var source = Session.new(); source.configure(board.catalog)
	check(source.campaign.load_file(path).ok, variable + " original imported read-only")
	var portal := -1; var hero := -1
	for card in source.cards.values():
		if card.definition_guid == board.catalog.find_by_name("Grand Portal"): portal = card.id
	for id in source.equipment.equipped:
		if source.cards.has(id) and source.stacks.has(source.cards[id].stack_id) and source.stacks[source.cards[id].stack_id].card_ids.size() == 1: hero = id
	check(portal > 0 and hero > 0, variable + " existing portal/equipped character")
	if portal > 0 and hero > 0:
		check(source.move_to_stack(hero, source.cards[portal].stack_id), "production existing-card stack action")
		trip(board, source, variable, admitted)
	check(FileAccess.get_sha256(path) == before, variable + " original bytes unchanged")
func run():
	var board = ObservedBoard.new(); board.feedback.free(); board.feedback = SilentFeedback.new()
	board.slot_root = directory(); board.options_path = "user://travel-layout-options.json"; board.legacy_paths.clear()
	root.add_child(board); await process_frame; board.set_process(false)
	check(board.data_error == OK, "licensed source catalog required")
	if board.data_error != OK: board.queue_free(); await process_frame; quit(1); return
	for scene in ["Main", "Island"]:
		for geared in [false, true]: trip(board, fixture(board, scene, geared), scene + ("_gear" if geared else "_plain"), true)
	guard_matrix(board)
	atomicity(board)
	real_case(board, "SOURCE_TRAVEL_REAL_MAIN", true)
	real_case(board, "SOURCE_TRAVEL_REAL_ISLAND", false)
	check(rejections.size() == 25 + int(not OS.get_environment("SOURCE_TRAVEL_REAL_ISLAND").is_empty()), "complete synthetic and optional real fallback matrix")
	var output := OS.get_environment("SOURCE_TRAVEL_REPORT")
	if not output.is_empty():
		var file := FileAccess.open(output, FileAccess.WRITE); file.store_string(JSON.stringify({"checks": checks, "failures": failures, "cases": cases, "rejections": rejections}, "  ", true, true)); file.close()
	board.queue_free(); await process_frame; await process_frame
	print("Source travel layout board: ", checks, " checks, ", failures, " failures; headless production boundary only")
	quit(1 if failures else 0)
