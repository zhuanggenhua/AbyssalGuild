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
	var task: int = s.combat.start_combat([departing],[first,second])
	b._refresh()
	var target: Vector3 = b.views[departing].position
	var start: Vector2 = b.camera.unproject_position(target)
	b._begin_card_press({"card_id":departing},start)
	expect(b._combat_hold.has("return_slot"), "native grounded slot captured before lift")
	var move := InputEventMouseMotion.new()
	move.position = b.camera.unproject_position(target+Vector3(.12,0,.1))
	b._input(move)
	b._advance_running_frame(0)
	var held: Vector3 = b.views[departing].position
	expect(held.y > 0 and held != target, "real sampled held offset")
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = start
	b._input(release)
	expect(b._combat_slot_returns.has(departing), "inside release retains same combat and owns return")
	expect(b.views[departing].position.is_equal_approx(held), "release does not snap")
	expect(s.cards[departing].stack_id == -1 and s.combat.membership[departing]==task, "no temporary stack retained")
	b._sync_views(.025)
	expect(b.views[departing].position.is_equal_approx(held.lerp(target,.4375)), "source OutQuad quarter")
	b._refresh()
	expect(b.views[departing].position.is_equal_approx(held.lerp(target,.4375)), "refresh does not restart return")
	s.paused=true
	b._advance_running_frame(.025)
	expect(b.views[departing].position.is_equal_approx(held.lerp(target,.75)), "paused source real time half")
	b._sync_views(.05)
	expect(b.views[departing].position==target, "arrives at original cached XYZ")
	b._sync_views(.2)
	expect(b.views[departing].position==target, "stable completion")
	expect(not b._combat_slot_returns.has(departing), "completed owner retired")
	b._begin_combat_slot_return(departing,task,held,target+Vector3(.01,0,0))
	expect(not b._combat_slot_returns.has(departing), "old cached target rejected against changed current slot")
	b._begin_combat_slot_return(departing,task,held,target)
	expect(b._combat_slot_returns.has(departing), "direct bounded return admitted")
	expect(b._combat_resize_native_slots(task), "native same-slot Arrange succeeds")
	expect(not b._combat_slot_returns.has(departing), "actual same-slot Arrange cancels tween")
	s.paused=false
	b._begin_card_press({"card_id":departing},start)
	expect(not b._combat_slot_returns.has(departing), "new press revokes previous return")
	b._input(move); b._advance_running_frame(0); b._input(release)
	expect(b._combat_slot_returns.has(departing), "new accepted return")
	s.combat.tasks[task].execution={"actor":first,"target":departing,"combat_type":1,"phase":"windup"}
	b._sync_views(0)
	expect(not b._combat_slot_returns.has(departing), "new action revokes slot owner")
	s.combat.tasks[task].erase("execution")
	b._refresh()
	b._begin_card_press({"card_id":departing},start)
	b._input(move); b._advance_running_frame(0); b._input(release)
	b.position=Vector3(.1,0,0)
	b._sync_views(0)
	expect(not b._combat_slot_returns.has(departing), "transformed board revokes owner")
	b.position=Vector3.ZERO
	# native audio teardown
	b.free()
	await drain.wait_after_teardown(self)
	if failures==0: print("PASS combat slot return: %d/%d" % [checks,checks])
	quit(1 if failures else 0)
