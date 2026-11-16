extends SceneTree
## Real imported stack rules and Board sampler; controlled motion, not image parity.
const Board = preload("res://scripts/ui/board.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_kind: String) -> bool: return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Board.new(); board.feedback.free(); board.feedback = SilentFeedback.new()
	var path := "user://ai-detach-pose-%d" % Time.get_ticks_usec()
	board.slot_root = path + "/slots"; board.options_path = path + "/options.json"; board.legacy_paths.clear()
	root.add_child(board); await process_frame
	check(board.data_error == OK, "private imported catalog required")
	if board.data_error != OK: board.queue_free(); quit(1); return
	board.start_new(); board.set_process(false); board.vendor_unlock.cancel()
	for id in board.session.cards.keys(): board.session._remove_card(id)
	var s = board.session
	s.spawn_layout_resolver = Callable(); s.spawn_target_selector = Callable()
	var cow: int = s.spawn_card(board.catalog.find_by_name("Cow"), Vector2(5, 5), -1, {"refuse_attach": true})
	var other: int = s.spawn_card(board.catalog.find_by_name("Cow"), Vector2(8, 5), -1, {"refuse_attach": true})
	check(s.move_to_stack(other, s.cards[cow].stack_id), "imported source rules allow Cow stack")
	var old = s.stacks[s.cards[cow].stack_id]
	check(old.card_ids == [cow, other] and old.recipe_guid.is_empty(), "first Cow has ground index in noncrafting stack")
	board._refresh()
	board.views[cow].global_position = Vector3(-2, 0.06, -1)
	check(s.world.actor_pose(cow) == Vector3(-2, 0, 1), "actual Board adapter admits steady-ground detached actor")
	for id in s.ai.agents: s.ai.agents[id].move_timer = 100
	for id in s.world.production_timers: s.world.production_timers[id] = 100
	var candidates: Array = []
	s.ai.point_validator = func(point, _stack): candidates.append(point); return false
	s.ai.placement_resolver = Callable()
	s.ai.agents[cow].move_timer = 0; s.ai.tick(0.01)
	check(old.card_ids == [other] and s.cards[cow].stack_id != old.id, "due real AI detaches only first Cow")
	check(old.position == Vector2(5, 5), "remaining stack keeps old target")
	check(s.card_target_position(cow) == Vector2(-2, 1), "rejected patrol retains sampled detach origin instead of queued endpoint")
	check(candidates.size() == s.ai.max_attempts, "normal patrol still exhausts imported attempts")
	for candidate in candidates:
		check(is_equal_approx(candidate.distance_to(Vector2(-2, 1)), s.ai.move_radius), "patrol uses new stack target from live detach")
	board.queue_free(); await process_frame; await create_timer(0.1).timeout
	print("AI detach pose Board: %d/%d passed; controlled ground motion only" % [checks-failures, checks])
	quit(1 if failures else 0)
