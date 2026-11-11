extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	var events: Array = []
	func play_event(event_name: String) -> bool: events.append(event_name); return false
	func play_music() -> bool: return false
class PuffProbe extends Node3D:
	var real_age: float = 0
	var scaled_age: float = 0
	func advance(real_delta: float, scaled_delta: float) -> void:
		real_age += real_delta; scaled_age += scaled_delta
	func is_expired() -> bool: return scaled_age >= 1.1
var checks := 0
var failures := 0
var seeds: Array = []
var render_available := true
func make_puff(_scene: String, seed_value: int) -> Node3D:
	seeds.append(seed_value)
	return PuffProbe.new() if render_available else null
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Board.new()
	board.feedback.free(); board.feedback = SilentFeedback.new()
	board.puff_factory = make_puff
	var path := "user://puff-board-%d" % Time.get_ticks_usec()
	board.slot_root = path + "/slots"; board.options_path = path + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board); await process_frame
	board.start_new(); board.set_process(false)
	board.session.set_paused(true)
	var wood: int = board.session.spawn_card(board.catalog.find_by_name("Wood"),Vector2(1,1),-1,{"refuse_attach":true})
	board._sync_views()
	board.views[wood].position = Vector3(7,2,-8)
	var model_position: Vector2 = board.session.cards[wood].position
	var rng_state: int = board.session.rng.state
	board.feedback.events.clear()
	board._on_session_event("puff_requested",{"card_id":wood,"position":Vector3(99,99,99)})
	check(board.puffs.size() == 1 and board.puffs[0].global_position == Vector3(7,2,-8), "event captures current view before model fallback")
	check(board.session.cards[wood].position == model_position and board.session.rng.state == rng_state, "presentation creation never writes model pose or gameplay RNG")
	check(board.feedback.events == ["Puff"] and seeds.size() == 1, "one Puff sound and independent presentation seed")
	var first = board.puffs[0]
	board._process(0.6)
	check(is_equal_approx(first.real_age,0.6) and first.scaled_age == 0, "manual pause ages particles in real time but retains emitter")
	board.pause_overlay.show()
	board.session.set_paused(false)
	board._process(0.6)
	check(is_equal_approx(first.real_age,1.2) and first.scaled_age == 0, "external pause supplies zero destruction time")
	board.pause_overlay.hide()
	board.session.set_speed(2)
	board._process(0.3)
	check(is_equal_approx(first.scaled_age,0.6) and board.puffs.size() == 1, "normal time pace scales emitter destruction")
	board._process(0.25)
	check(board.puffs.is_empty() and first.is_queued_for_deletion(), "scaled 1.1-second expiry removes lifecycle entry")
	board.session.set_paused(true)
	board._on_session_event("puff_requested",{"card_id":-1,"position":Vector3(2,3,4)})
	check(board.puffs[0].global_position == Vector3(2,3,-4), "missing view uses source fallback with one Z reflection")
	board._clear_puffs()
	render_available = false
	board.feedback.events.clear()
	board._on_session_event("puff_requested",{"card_id":-1,"position":Vector3.ZERO})
	check(board.puffs.is_empty() and board.feedback.events == ["Puff"], "missing renderer never suppresses source sound")
	board.feedback.events.clear()
	board._on_session_event("crafted",{})
	check(board.feedback.events.is_empty(), "generic crafted no longer duplicates Pop")
	board._on_session_event("recipe_pop_requested",{"card_id":-1,"position":Vector3.ZERO,"recipe_guid":"test"})
	check(board.feedback.events == ["Pop"], "exact base-recipe source cue plays one Pop")
	render_available = true
	board._sync_views()
	var death_origin: Vector3 = board.views[wood].global_position
	board.session.kill_card(wood)
	check(not board.session.cards.has(wood) and board.puffs.size() == 1 and board.puffs[0].global_position == death_origin, "real Kill cue captures view before deletion")
	board._clear_puffs()
	var recipe: Dictionary = {}
	for entry in board.catalog.data.recipes:
		if entry.script_class == "RecipeDefinition": recipe = entry; break
	var stack_id: int = -1
	var top: int = -1
	for ingredient in recipe.fields.requiredIngredients:
		for count in int(ingredient.count):
			top = board.session.spawn_card(board.catalog.ref_guid(ingredient.card),Vector2(-3,0),stack_id,{"refuse_attach":true})
			stack_id = board.session.cards[top].stack_id
	board.session.stacks[stack_id].recipe_guid = recipe.guid
	board._sync_views()
	top = int(board.session.stacks[stack_id].card_ids.front()) # Source TopCard means index zero.
	var craft_origin: Vector3 = board.views[top].global_position
	board.feedback.events.clear()
	board.session._complete_recipe(board.session.stacks[stack_id])
	check(board.feedback.events == ["Puff","Pop"], "actual ordinary source recipe emits Puff then Pop exactly once")
	check(board.puffs.size() == 1 and board.puffs[0].global_position == craft_origin, "ordinary recipe captures pre-consumption top-card view")
	board._enter_game()
	check(board.puffs.is_empty(), "scene/session entry clears old emitters")
	if not board.visual_assets.puff_configuration(board.session.scene_name).is_empty():
		board.puff_factory = Callable()
		board._on_session_event("puff_requested",{"card_id":-1,"position":Vector3(1,0,2)})
		check(board.puffs.size() == 1 and board.puffs[0].global_position == Vector3(1,0,-2), "actual private Puff renderer attaches at reflected captured origin")
		board._advance_puffs(2.0,0.0)
		check(board.puffs.size() == 1 and not board.puffs[0].is_expired(), "real particles can expire while scaled emitter remains paused")
		board._advance_puffs(0.0,1.1)
		check(board.puffs.is_empty(), "real renderer scaled expiry is pruned")
		board.puff_factory = make_puff
	board.session.spawn_card(board.catalog.find_by_name("Villager"),Vector2.ZERO,-1,{"refuse_attach":true})
	board.session.cycle.request_end_day(); board.session.cycle.begin_feeding()
	board.pause_overlay.show()
	var before_wait: float = board.session.cycle.remaining
	board._process(0.1)
	check(is_equal_approx(board.session.cycle.remaining,before_wait-0.1), "external modal branch still advances realtime cycle wait")
	board._on_session_event("puff_requested",{"card_id":-1,"position":Vector3.ZERO})
	board._show_title()
	check(board.puffs.is_empty(), "title clears retained paused emitters")
	board.queue_free(); await process_frame; await create_timer(0.5).timeout
	print("Puff board checks: %d passed / %d total" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
