extends SceneTree
## Real imported board/headless geometry integration; not rendered/manual acceptance.
const Board = preload("res://scripts/ui/board.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Equipment = preload("res://scripts/model/equipment_system.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const Layout = preload("res://scripts/model/board_layout.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_kind: String) -> bool: return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func spawn(board, name: String, position: Vector2) -> int:
	return board.session.spawn_card(board.catalog.find_by_name(name), position, -1, {"refuse_attach": true})
func place(board, id: int, position: Vector2) -> void:
	var stack = board.session.stacks[board.session.cards[id].stack_id]
	stack.position = position
	for member in stack.card_ids: board.session.cards[member].position = position
func separated(board, a: int, b: int) -> bool:
	var states: Dictionary = {}
	for state in board._layout_states(): states[state.id] = state
	return Layout.separation(Layout.stack_bounds(states[board.session.cards[a].stack_id]), Layout.stack_bounds(states[board.session.cards[b].stack_id])).length() < 0.00001
func run() -> void:
	var board = Board.new()
	board.feedback.free(); board.feedback = SilentFeedback.new()
	var path := "user://ai-placement-board-%d" % Time.get_ticks_usec()
	board.slot_root = path + "/slots"; board.options_path = path + "/options.json"; board.legacy_paths.clear()
	root.add_child(board); await process_frame
	check(board.data_error == OK, "real private catalog available")
	if board.data_error != OK: board.queue_free(); quit(1); return
	board.start_new(); board.set_process(false); board.vendor_unlock.cancel()
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board.session.spawn_layout_resolver = Callable(); board.session.spawn_target_selector = Callable()
	var cow: int = spawn(board, "Cow", Vector2.ZERO)
	var wood: int = spawn(board, "Wood", Vector2(3, 0))
	var held: int = spawn(board, "Stone", Vector2(-5, -3))
	board._refresh()
	board._begin_card_press({"card_id": held, "panel_owner": -1}, board.camera.unproject_position(board.views[held].global_position))
	check(board.session.drag.active() and board.dragging == held, "real pointer pickup keeps unrelated held stack active")
	var held_position: Vector2 = board.session.card_target_position(held)
	# Predict the actual first patrol candidate without consuming the session RNG.
	var rng := RandomNumberGenerator.new(); rng.state = board.session.rng.state
	var direction := Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	while direction.length_squared() > 1: direction = Vector2(rng.randf_range(-1, 1), rng.randf_range(-1, 1))
	var target: Vector2 = direction.normalized() * board.session.ai.move_radius
	place(board, wood, target)
	board.session.world.production_timers[cow] = 1000
	board.session.ai.agents[cow].move_timer = 0
	board.session.ai.tick(0.01)
	check(separated(board, cow, wood), "due actual Cow patrol resolves neutral overlap during unrelated drag")
	check(board.session.drag.active() and board.session.card_target_position(held) == held_position, "native held-stack lock preserved")
	check(board.session.cards.size() == 3, "no production/spawn masks movement resolution")
	# Exhausted patrol still resolves current overlaps; source explicit pack locks stay fixed.
	place(board, cow, Vector2.ZERO); place(board, wood, Vector2.ZERO)
	board.layout_locks[board.session.cards[wood].stack_id] = true
	board.session.ai.point_validator = func(_point, _stack): return false
	board.session.ai.agents[cow].move_timer = 0; board.session.ai.tick(0.01)
	check(separated(board, cow, wood) and board.session.card_target_position(wood) == Vector2.ZERO, "failed patrol resolves against locked obstacle without moving lock")
	place(board, cow, Vector2.ZERO)
	board._ensure_layout()
	check(not separated(board, cow, wood), "pickup-only frame guard remains intact")
	board.session.ai.point_validator = board._ai_point_valid
	# Scene entry must restore the adapter even if a previous owner removed it.
	board.session.ai.placement_resolver = Callable(); board._enter_game()
	check(board.session.ai.placement_resolver == Callable(board, "_resolve_layout"), "scene entry rebinds placement adapter")
	board.vendor_unlock.cancel(); board.session.spawn_target_selector = Callable(); board.session.spawn_layout_resolver = Callable()
	var portal: int = spawn(board, "Grand Portal", Vector2(3, 0))
	var stack_id: int = board.session.cards[portal].stack_id
	board.session.spawn_card(board.catalog.find_by_name("Villager"), Vector2(3, 0), stack_id)
	var recipe_guid := ""
	for entry in board.catalog.data.recipes:
		if entry.script_class == "TravelRecipe": recipe_guid = entry.guid
	var result: Dictionary = board.session.campaign.travel(stack_id, recipe_guid)
	check(result.ok and board.session.scene_name == "Island" and board.session.ai.placement_resolver == Callable(board, "_resolve_layout"), "actual travel configure and scene event retain/rebind callback")
	# Real definitions also exercise source registration ties independently of visuals.
	var s = Session.new(); s.configure(board.catalog, 777)
	var enemy_guid := ""
	for entry in board.catalog.data.cards:
		if entry.fields.get("isAggressive", false): enemy_guid = entry.guid; break
	var enemy: int = s.spawn_card(enemy_guid)
	var first: int = s.spawn_card(board.catalog.find_by_name("Villager"), Vector2(-4, 0))
	var second: int = s.spawn_card(board.catalog.find_by_name("Villager"), Vector2(4, 0))
	check(not enemy_guid.is_empty() and s.world.aggressive_intent(enemy).card_id == first, "real aggressive mob initial equidistant player tie")
	Equipment.detach(s, first, Vector2(-4, 0)); Equipment.return_to_board(s, first)
	check(s.world.aggressive_intent(enemy).card_id == second, "real target follows changed registration instead of creation")
	var restored: Dictionary = Codec.restore(s, Codec.capture(s))
	check(restored.ok and s.world.aggressive_intent(enemy).card_id == second, "real catalog checkpoint continues target tie")
	board.queue_free(); await process_frame; await create_timer(0.1).timeout
	print("AI placement board: %d/%d passed; headless integration only" % [checks - failures, checks])
	quit(1 if failures else 0)
