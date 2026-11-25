extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	var trace: Array = []
	var observe: Callable
	func play_event(event_name: String) -> bool:
		if event_name in ["Puff", "Coin", "Coins"]:
			trace.append([event_name, observe.call() if observe.is_valid() else []])
		return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
var queried: Array = []
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func fixture(board, position := Vector2.ZERO) -> int:
	board.session.drag.reset()
	board.dragging = -1
	board.drag_grant = -1
	board.drag_delta = Vector2.ZERO
	board.session.phase = "playing"
	board.session.paused = false
	board.session.cycle.reset()
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board.session.spawn_target_selector = Callable()
	board.session.spawn_layout_resolver = Callable()
	var chest: int = board.session.spawn_card(board.catalog.find_by_name("Card_Chest_WoodenChest"), position, -1, {"refuse_attach": true})
	board.session.cards[chest].stored_coins = 2
	board._refresh()
	queried.clear()
	board.session.spawn_target_selector = func(id, ignored):
		queried.append({"position": board.session.cards[id].position, "ignored": ignored})
		return -1
	return chest
func press(board, id: int) -> void:
	board._begin_card_press({"card_id": id, "panel_owner": -1}, Vector2.ZERO)
func drag_coin(board, id: int, chest: int, z_offset := 0.0) -> void:
	var press_event := InputEventMouseButton.new()
	press_event.button_index = MOUSE_BUTTON_LEFT
	press_event.pressed = true
	press_event.position = board.camera.unproject_position(board.views[id].global_position + Vector3(0, 0, z_offset))
	board._unhandled_input(press_event)
	check(board.drag_grant == id, "ordinary board picking captures currency card")
	var at: Vector3 = board.views[chest].global_position
	var move := InputEventMouseMotion.new()
	move.position = board.camera.unproject_position(at + Vector3(0, 0, z_offset))
	move.relative = move.position - press_event.position
	board._input(move)
	var release := InputEventMouseButton.new()
	release.button_index = MOUSE_BUTTON_LEFT
	release.position = move.position
	board._input(release)

func _init() -> void: call_deferred("run")
func run() -> void:
	root.size = Vector2i(1440, 900)
	var board = Board.new()
	board.feedback.free()
	var audio := SilentFeedback.new()
	board.feedback = audio
	board.slot_root = "user://chest-lifecycle-%d" % Time.get_ticks_usec()
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	check(board.data_error == OK, "source data available")
	if board.data_error != OK:
		board.queue_free()
		await process_frame
		quit(1)
		return
	board.start_new()
	board.set_process(false)
	await process_frame
	var chest := fixture(board)
	press(board, chest)
	var origin := Vector2(board.drag_start_position.x, board.drag_start_position.z)
	var width: float = board._card_footprint(chest).x
	board.drag_delta = Vector2(0.01, 0)
	board._finish_drag(Vector2.ZERO)
	check(board.session.cards[chest].stored_coins == 1, "sub-threshold motion withdraws once")
	check(queried.size() == 1 and queried[0].position.is_equal_approx(origin + Vector2(width + 0.01, 0)), "coin attachment queries release position plus width before reset")
	check(board.session.card_target_position(chest).is_equal_approx(origin), "successful click restores pointer-down origin")
	board._finish_drag(Vector2.ZERO)
	check(board.session.cards[chest].stored_coins == 1 and queried.size() == 1, "repeated release cannot withdraw twice")
	# Verify raw spawn query beyond the board edge before ordinary factory layout.
	chest = fixture(board)
	var boundary: Vector2 = Vector2(board.session.board_bounds.end.x - 0.001, 0)
	board._set_board_card_position(chest, boundary)
	check(board._withdraw_chest(chest), "inspection withdrawal accepted near boundary")
	check(queried.size() == 1 and queried[0].position.is_equal_approx(boundary + Vector2(board._card_footprint(chest).x, 0)), "null-stack source placement does not clamp raw coin query")
	check(queried[0].position.x > board.session.board_bounds.end.x, "query occurs beyond right boundary")
	check(queried[0].ignored == board.session.cards[chest].stack_id, "spawn ignores originating chest stack")
	# Inspection convenience has no pointer-down origin and must not restore one.
	chest = fixture(board, Vector2(2, 0))
	board.drag_start_position = Vector3(-3, 0, -3)
	board.selected = chest
	board._withdraw_selected()
	check(board.session.cards[chest].stored_coins == 1 and board.session.card_target_position(chest).is_equal_approx(Vector2(2, 0)), "inspection convenience does not use stale pointer origin")
	chest = fixture(board)
	board.session.cards[chest].stored_coins = 0
	var position: Vector2 = Vector2(0.01, 0)
	board._set_board_card_position(chest, position)
	check(not board._withdraw_chest(chest, false, Vector2.ZERO), "empty click fails")
	check(queried.is_empty() and board.session.card_target_position(chest) == position, "empty click neither spawns nor resets")
	# A carried click remains valid after phase changes, but cannot authorize a new press.
	chest = fixture(board)
	press(board, chest)
	origin = Vector2(board.drag_start_position.x, board.drag_start_position.z)
	board.session.phase = "feeding"
	board.drag_delta = Vector2(0.01, 0)
	board._finish_drag(Vector2.ZERO)
	check(board.session.cards[chest].stored_coins == 1 and board.session.card_target_position(chest).is_equal_approx(origin), "captured phase-boundary click restores origin")
	press(board, chest)
	board._finish_drag(Vector2.ZERO)
	check(board.session.cards[chest].stored_coins == 1 and queried.size() == 1, "feeding blocks subsequent presses")
	# Real board mouse picking on a still-interpolating singleton must capture
	# its visible pose, not leave the model at its distant settled endpoint.
	chest = fixture(board)
	board._set_board_card_position(chest, Vector2(2, 0))
	board._refresh()
	await physics_frame
	var visible := Vector2(board.views[chest].global_position.x, -board.views[chest].global_position.z)
	check(not visible.is_equal_approx(board.session.card_target_position(chest)), "singleton has distinct animated and settled positions")
	var mouse := InputEventMouseButton.new()
	mouse.button_index = MOUSE_BUTTON_LEFT
	mouse.position = board.camera.unproject_position(board.views[chest].global_position)
	mouse.pressed = true
	board._unhandled_input(mouse)
	check(board.drag_grant == chest, "real board mouse picking grants interpolating chest press")
	check(board.session.card_target_position(chest).is_equal_approx(visible), "whole-stack press immediately aligns held root with visible pose")
	check(is_equal_approx(board.drag_start_position.y, 0.0), "singleton press preserves source zero stack height")
	mouse.pressed = false
	board._input(mouse)
	check(board.session.cards[chest].stored_coins == 1, "unmoved interpolating singleton release is a click")
	# An ordinary drop, not a buyer/vendor purchase and not a direct model
	# call: partially fill a chest with one coin out of a two-coin tail.
	chest = fixture(board)
	var capacity: int = int(board.catalog.fields(board.session.cards[chest].base_definition_guid).capacity)
	board.session.cards[chest].stored_coins = capacity - 1
	var coin: int = board.session.spawn_card(board.session.world.currency_guid, Vector2(2, 0), -1, {"refuse_attach": true})
	var coin_stack: int = board.session.cards[coin].stack_id
	var remainder: int = board.session.spawn_card(board.session.world.currency_guid, Vector2(2, 0), coin_stack)
	board._refresh()
	# Freeze exact settled root and member poses while Board processing is off.
	board.views[chest].global_position = Vector3.ZERO
	board.views[coin].global_position = Vector3(2, 0, 0)
	board.views[remainder].global_position = Vector3(2, board._stack_step().y, -board._stack_step().z)
	await physics_frame
	await physics_frame
	var chest_view = board.views[chest]
	var has_price: bool = chest_view.stat_labels.has("price")
	check(has_price, "original chest prefab binds a price label")
	audio.observe = func():
		var text: String = str(chest_view.stat_labels.price.text) if has_price else ""
		return [text, board.session.cards.has(coin), board.session.cards.has(remainder)]
	audio.trace.clear()
	drag_coin(board, coin, chest, -0.44)
	check(board.session.cards[chest].stored_coins == capacity and not board.session.cards.has(coin) and board.session.cards.has(remainder), "capacity consumes only the first coin and retains its tail")
	check(audio.trace == [["Puff", [str(capacity - 1), true, true]], ["Coins", [str(capacity), false, true]]], "puff sees previous label, one deposit cue sees updated label and removal")
	# A real second drop on the now-full chest still puffs, but cannot play
	# Coins or consume the remainder. Move it away before the second press.
	board._set_board_card_position(remainder, Vector2(2, 0))
	board._refresh()
	if board.views.has(remainder): board.views[remainder].global_position = Vector3(2, 0, 0)
	await physics_frame
	await physics_frame
	audio.trace.clear()
	if board.views.has(remainder): drag_coin(board, remainder, chest)
	check(board.session.cards[chest].stored_coins == capacity and board.session.cards.has(remainder), "full chest consumes nothing")
	check(audio.trace == [["Puff", [str(capacity), false, true]]], "full chest puffs without a deposit cue")
	audio.trace.clear()
	check(board._withdraw_chest(chest), "board checkout withdraws a coin")
	check(audio.trace == [["Puff", [str(capacity - 1), false, true]], ["Coin", [str(capacity - 1), false, true]]], "withdrawal updates text before puff and requests a single Coin")
	audio.observe = Callable()
	board.session.spawn_target_selector = Callable()
	board.queue_free()
	await process_frame
	print("Chest click lifecycle: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
