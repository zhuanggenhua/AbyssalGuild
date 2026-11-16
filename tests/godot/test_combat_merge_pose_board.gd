extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const Geometry = preload("res://scripts/model/combat_merge_geometry.gd")
const Layout = preload("res://scripts/model/combat_layout.gd")
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
	board._refresh()
	board.views[p0].global_position = Vector3(2,0.06,0)
	board.views[m0].global_position = Vector3(4,0.06,0)
	check(board._combat_start_center([p0],[m0]) == Vector2(3,0),"complete native live average differs from queued origin")
	board.views[m0].global_position.y = 0.2
	check(board._combat_start_center([p0],[m0]) == null,"one unsupported pose rejects whole entrance receipt")
	board.views[m0].global_position.y = 0.06
	var entrance_target: Vector2 = s.card_target_position(p0)
	var entrance_rng: int = s.rng.state
	var entrance_calls := [0]
	s.combat.start_center_sampler = func(a,b):
		entrance_calls[0] += 1
		check(s.combat.membership.is_empty() and s.rng.state == entrance_rng,"center sampled before entry and RNG draws")
		check(s.card_target_position(p0) == entrance_target,"sampling precedes model target changes")
		return board._combat_start_center(a,b)
	var initial: int = s.combat.start_combat([p0],[m0])
	check(entrance_calls[0] == 1,"standalone samples once")
	s.combat.start_center_sampler = board._combat_start_center
	board._refresh()
	check(initial >= 0 and board.combat_layouts.has(initial),"existing real combat layout")
	var center: Vector2 = board.combat_layouts[initial].center
	var cfg: Dictionary = Layout.imported_config(board.catalog.data,s.scene_name)
	var expected: Dictionary = Layout.initialize(board._fighter_records([p0]),board._fighter_records([m0]),cfg,s.board_bounds,s.board_top_margin,Vector2(3,0))
	check(center == expected.center,"native rectangle uses source live average then imported board clamp")
	check(not s.combat.tasks[initial].has("initial_center"),"receipt consumed after initial layout")
	check(not s.combat.save_state().tasks[0].has("initial_center"),"ephemeral receipt absent from saves")
	board.views[p0].global_position.x += 10
	board._sync_combat_layouts()
	check(board.combat_layouts[initial].center == center,"later live view changes cannot recenter existing rectangle")
	# A saved/restored layout is authoritative even if a stale receipt is present.
	s.combat.tasks[initial]["initial_center"] = Vector2(99,99)
	board._sync_combat_layouts()
	check(board.combat_layouts[initial].center == center and not s.combat.tasks[initial].has("initial_center"),"existing saved-layout path ignores and consumes stale receipt")
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
	# Prior deliberate stale old fighter is not an admitted settled observation.
	check(board._combat_merge_center([p0,p1],[m0,m1],{p0:true,m0:true}) == null,"stale old pose after layout change rejects entire center")
	board._refresh()
	for id in [p1,m1]:
		board._set_board_card_position(id,far)
		board.views[id].global_position = Vector3(center.x,0.06,-center.y)
	var old_poses := {p0:true,m0:true}
	var receipt: Variant = board._combat_merge_center([p1,p0],[m1,m0],old_poses)
	check(receipt is Vector2,"settled old and ordinary new views admit complete receipt")
	var old_point: Vector3 = board.views[p0].global_position
	board.views[p0].global_position.y = 0.1
	check(board._combat_merge_center([p1,p0],[m1,m0],old_poses) == null,"old lifted fighter rejects whole group")
	board.views[p0].global_position = old_point
	var old_motion: Variant = board.card_motion.states.get(p0)
	board.card_motion.states[p0] = {"mode":"animated"}
	check(board._combat_merge_center([p1,p0],[m1,m0],old_poses) == null,"old ordinary mode is not combat ground evidence")
	if old_motion == null: board.card_motion.states.erase(p0)
	else: board.card_motion.states[p0] = old_motion
	check(board._combat_merge_center([p1,p0],[m1,m0],{p0:false,m0:true}) == null,"captured drag or execution flag survives task cleanup")
	board.combat_presentation.motions[initial] = {"actor":p0,"combat_type":0,"start":old_point,"finish":old_point,"duration":1.0,"age":1.0}
	check(board._combat_merge_center([p1,p0],[m1,m0],old_poses) == null,"finished but unreleased melee tween rejects even ground endpoint")
	board.combat_presentation.motions.erase(initial)
	board.position.x = 1
	check(board._combat_merge_center([p1,p0],[m1,m0],old_poses) == null,"nonidentity Board coordinate frame is not inferred")
	board.position.x = 0
	var merge_rng: int = s.rng.state
	var merge_sample_calls := [0]
	s.combat.merge_center_sampler = func(a,b,old):
		merge_sample_calls[0] += 1
		check(not s.combat.tasks.has(initial) and s.combat.membership.is_empty(),"merge center observed after old cleanup before new entry")
		check(s.rng.state == merge_rng,"merge center precedes replacement random progress")
		check(a == [p1,p0] and b == [m1,m0] and old == old_poses,"source faction/order and preserved old identity")
		return board._combat_merge_center(a,b,old)
	var merged_calls := [0]
	s.combat.start_center_sampler = func(_a,_b): merged_calls[0] += 1; return Vector2(88,88)
	var merged: int = s.combat.start_combat([p1],[m1])
	check(merged_calls[0] == 0 and merge_sample_calls[0] == 1,"merge creation does not reuse standalone center observer")
	check(merged >= 0 and merged != initial and not s.combat.tasks.has(initial),"real start merges old task selected from live observations")
	check(s.combat.tasks.size() == 1 and s.combat.tasks[merged].attackers.size() == 2
		and s.combat.tasks[merged].defenders.size() == 2,"all imported fighters belong to single merged combat")
	check(s.combat.tasks[merged].get("initial_center") == receipt,"merged receipt uses final complete set rather than entrant center")
	board._refresh()
	var merged_expected: Dictionary = Layout.initialize(board._fighter_records([p1,p0]),board._fighter_records([m1,m0]),cfg,s.board_bounds,s.board_top_margin,receipt)
	check(board.combat_layouts[merged].center == merged_expected.center,"replacement rect clamps source receipt once")
	check(not s.combat.tasks[merged].has("initial_center"),"merged receipt consumed and not serialized")
	s.combat.merge_center_sampler = board._combat_merge_center
	board.queue_free(); await process_frame
	check(await audio_drain.wait_after_teardown(self),"native BGM releases before fixture exit")
	print("Combat merge pose Board: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
