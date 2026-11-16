extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const Geometry = preload("res://scripts/model/combat_merge_geometry.gd")
const AudioDrain = preload("res://tests/godot/source_test_audio_drain.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ",label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Board.new()
	var audio_drain := AudioDrain.new()
	var temp := "user://combat-merge-pose-%d" % Time.get_ticks_usec()
	board.slot_root = temp + "/slots"; board.options_path = temp + "/options.json"; board.legacy_paths.clear()
	root.add_child(board); await process_frame
	audio_drain.observe_music(board.feedback.music)
	check(board.data_error == OK,"actual imported catalog")
	if board.data_error != OK: board.queue_free(); quit(1); return
	board.start_new(); board.set_process(false); board.vendor_unlock.cancel()
	var s = board.session
	for id in s.cards.keys(): s._remove_card(id)
	s.spawn_target_selector = Callable(); s.spawn_layout_resolver = Callable()
	var player: String = board.catalog.find_by_name("Villager")
	var mob := ""
	for entry in board.catalog.data.cards:
		if int(entry.fields.get("category",0)) == 9 and int(entry.fields.get("faction",0)) == 2:
			mob = entry.guid; break
	var p0: int = s.spawn_card(player,Vector2.ZERO,-1,{"refuse_attach":true})
	var m0: int = s.spawn_card(mob,Vector2.ZERO,-1,{"refuse_attach":true})
	var initial: int = s.combat.start_combat([p0],[m0])
	board._refresh()
	check(initial >= 0 and board.combat_layouts.has(initial),"existing real combat layout")
	var center: Vector2 = board.combat_layouts[initial].center
	var far := center + Vector2(12,0)
	var p1: int = s.spawn_card(player,far,-1,{"refuse_attach":true})
	var m1: int = s.spawn_card(mob,far,-1,{"refuse_attach":true})
	board._refresh()
	# Ordinary grounded view position differs from its queued endpoint.
	for id in [p1,m1]: board.views[id].global_position = Vector3(center.x,0.06,-center.y)
	check(board._sample_ai_actor_pose(p1) == Vector3(center.x,0,center.y),"current grounded view has proven source mapping")
	check(Geometry.before_start(board._fighter_records([p1]),board._fighter_records([m1]),board.combat_layouts).is_empty(),
		"old target-only preview would incorrectly miss")
	var target_before: Vector2 = s.card_target_position(p1)
	var rng_before: int = s.rng.state
	check(board._combat_start_overlaps([p1],[m1]) == [initial],"native pre-start selector finds current overlap")
	check(s.card_target_position(p1) == target_before and s.rng.state == rng_before,"selection does not move targets or draw randomness")
	for id in [p1,m1]:
		board._set_board_card_position(id,center)
		board.views[id].global_position = Vector3(far.x,0.06,-far.y)
	check(board._combat_start_overlaps([p1],[m1]).is_empty(),"current far cards do not merge solely due to stale near targets")
	# Rejected vertical state keeps previously documented target fallback.
	for id in [p1,m1]: board.views[id].global_position.y = 0.2
	check(board._sample_ai_actor_pose(p1) == null,"elevated/unproven view is not flattened")
	check(board._combat_start_overlaps([p1],[m1]) == [initial],"unsupported vertical view explicitly falls back to settled preview")
	for id in [p1,m1]:
		board._set_board_card_position(id,far)
		board.views[id].global_position = Vector3(center.x,0.06,-center.y)
	var merged: int = s.combat.start_combat([p1],[m1])
	check(merged >= 0 and merged != initial and not s.combat.tasks.has(initial),"real start merges old task selected from live observations")
	check(s.combat.tasks.size() == 1 and s.combat.tasks[merged].attackers.size() == 2
		and s.combat.tasks[merged].defenders.size() == 2,"all imported fighters belong to single merged combat")
	board.queue_free(); await process_frame
	check(await audio_drain.wait_after_teardown(self),"native BGM releases before fixture exit")
	print("Combat merge pose Board: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
