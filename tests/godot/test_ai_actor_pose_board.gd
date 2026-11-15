extends SceneTree
## Actual imported board wiring; controlled view motion is not Unity visual acceptance.
const Board = preload("res://scripts/ui/board.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_kind: String) -> bool: return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func spawn(board, guid: String, position: Vector2) -> int:
	return board.session.spawn_card(guid, position, -1, {"refuse_attach": true})
func pose(board, id: int, point: Vector3) -> void:
	board.views[id].global_position = Vector3(point.x, point.y + 0.06, -point.z)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Board.new(); board.feedback.free(); board.feedback = SilentFeedback.new()
	var path := "user://ai-actor-pose-%d" % Time.get_ticks_usec()
	board.slot_root = path + "/slots"; board.options_path = path + "/options.json"; board.legacy_paths.clear()
	root.add_child(board); await process_frame
	check(board.data_error == OK, "real private catalog required")
	if board.data_error != OK: board.queue_free(); quit(1); return
	board.start_new(); board.set_process(false); board.vendor_unlock.cancel()
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board.session.spawn_layout_resolver = Callable(); board.session.spawn_target_selector = Callable()
	var mob_guid := ""
	for entry in board.catalog.data.cards:
		if entry.fields.get("isAggressive", false): mob_guid = entry.guid; break
	var mob: int = spawn(board, mob_guid, Vector2.ZERO)
	var first: int = spawn(board, board.catalog.find_by_name("Villager"), Vector2(0.1, 0))
	var second: int = spawn(board, board.catalog.find_by_name("Villager"), Vector2(7, 0))
	board._refresh()
	check(board.session.world.actor_pose_sampler == Callable(board, "_sample_ai_actor_pose"), "actual scene entry installs current-pose adapter")
	check(is_equal_approx(board.views[mob].position.y, 0.06) and board.session.world.actor_pose(mob).y == 0.0, "actual synced ordinary display lift never enters source distance")
	pose(board, mob, Vector3(0, 0, 2)); pose(board, first, Vector3(9, 0, 2)); pose(board, second, Vector3(4, 0, 2))
	check(board.session.world.actor_pose(mob) == Vector3(0, 0, 2), "native horizontal Z reflection with unchanged source height contract")
	board.views[mob].position.y = 0.1
	check(board.session.world.actor_pose(mob) == board.session.card_target_position_3d(mob), "unmodeled changing height rejects entire live sample")
	pose(board, mob, Vector3(0, 0, 2))
	var intent: Dictionary = board.session.world.aggressive_intent(mob)
	check(intent.card_id == second and intent.action == "approach_player", "live view positions win over different stored destinations")
	check(not board.session.combat.membership.has(mob), "intent alone does not create combat")
	# Trigger the real due AI tick, not a replacement movement implementation.
	board.session.ai.agents[mob].move_timer = 0
	board.session.ai.tick(0.01)
	check(not board.session.combat.membership.has(mob), "due AI does not attack stale near destination")
	# Ordinary resolver can move accepted targets around other cards; capture via
	# the real native point validator and accept its real bounded position.
	pose(board, mob, Vector3(-2, 0, 0)); pose(board, first, Vector3(20, 0, 0)); pose(board, second, Vector3(4, 0, 0))
	var native_validator: Callable = board._ai_point_valid
	var captured: Array = []
	board.session.ai.point_validator = func(point, stack): captured.append(point); return native_validator.call(point, stack)
	board.session.ai.agents[mob].move_timer = 0; board.session.ai.tick(0.01)
	check(captured.size() == 1 and captured[0].is_equal_approx(Vector2(-1, 0)), "actual due tick submits ground approach from current view origin")
	board.session.ai.point_validator = board._ai_point_valid
	# Missing/queued nodes explicitly fall back without dereferencing dead views.
	board.views[mob].queue_free()
	check(board.session.world.actor_pose(mob) == board.session.card_target_position_3d(mob), "queued native view uses explicit model fallback")
	board.session.world.actor_pose_sampler = Callable(); board._enter_game()
	check(board.session.world.actor_pose_sampler == Callable(board, "_sample_ai_actor_pose"), "reentry rebinds sampler")
	board.queue_free(); await process_frame; await create_timer(0.1).timeout
	print("AI actor pose board: %d/%d passed; headless integration only" % [checks-failures, checks])
	quit(1 if failures else 0)
