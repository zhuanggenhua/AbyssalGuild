extends SceneTree
## Headless board clock-routing regression, not GPU/manual interaction acceptance.
const Board = preload("res://scripts/ui/board.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
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

func _init() -> void:
	call_deferred("run")

func spawn(board, name: String, position: Vector2) -> int:
	return board.session.spawn_card(board.catalog.find_by_name(name), position, -1, {"refuse_attach": true})

func prepare(board) -> Array:
	board.vendor_unlock.cancel()
	board.session.drag.reset(); board.dragging = -1; board.drag_grant = -1
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board.session.cycle.reset(); board.session.phase = "playing"; board.session.paused = false
	board.session.elapsed = 0; board.session.speed = 1
	board.session.spawn_target_selector = Callable(); board.session.spawn_layout_resolver = Callable()
	board.pause_overlay.hide(); board.options_panel.hide()
	var apple: int = spawn(board, "Apple", Vector2(-3, 0))
	var berry: int = spawn(board, "Berry", Vector2(-2, 0))
	check(board.session.move_to_stack(berry, board.session.cards[apple].stack_id), "actual Fruit Salad recipe assembled")
	var ready = board.session.stacks[board.session.cards[apple].stack_id]
	var wood: int = spawn(board, "Wood", Vector2(3, 0))
	var worker: int = spawn(board, "Villager", Vector2(4, 0))
	check(board.session.move_to_stack(worker, board.session.cards[wood].stack_id), "actual Timber recipe assembled")
	var pending = board.session.stacks[board.session.cards[wood].stack_id]
	board.session.tick(3)
	# Explicit codec edge fixture: an already-complete task loaded while paused.
	# The real-order/quest/travel tests never inject timers or quest state.
	ready.progress = float(board.catalog.fields(ready.recipe_guid).craftingDuration)
	ready.paused = true
	check(Codec.restore(board.session, Codec.capture(board.session)).ok, "completed paused checkpoint restores")
	board._refresh()
	return [ready.id, pending.id, worker, wood]

func run() -> void:
	var board = Board.new()
	board.feedback.free(); board.feedback = SilentFeedback.new()
	var path := "user://crafting-order-board-%d" % Time.get_ticks_usec()
	board.slot_root = path + "/slots"; board.options_path = path + "/options.json"; board.legacy_paths.clear()
	root.add_child(board); await process_frame
	check(board.data_error == OK, "actual private catalog available")
	if board.data_error != OK:
		board.queue_free(); quit(1); return
	board.start_new(); board.set_process(false)
	for pause in ["user", "menu", "options", "vendor", "held_tail", "held_whole"]:
		var ids := prepare(board)
		var pending = board.session.stacks[ids[1]]
		if pause == "user": board.session.set_paused(true)
		elif pause == "vendor":
			board.vendor_unlock.bind(board)
			var zones: Array = board.trade_zones.duplicate(true)
			zones[1].active = true
			board.vendor_unlock.sequence.on_quest_completed(zones)
			check(board.vendor_unlock.is_active(), "vendor reveal supplies external pause")
		else:
			if pause.begins_with("held"):
				var picked: int = ids[2] if pause == "held_tail" else ids[3]
				board._begin_card_press({"card_id": picked, "panel_owner": -1}, board.camera.unproject_position(board.views[picked].global_position))
				check(board.session.drag.active() and board.drag_grant == picked, pause + " has real pointer grant")
			if pause == "options": board._open_options()
			else: board.pause_overlay.show()
		var events: Array = []
		var on_event := func(kind, payload):
			if kind == "crafted": events.append(board.catalog.fields(payload.definition_guid).displayName)
		board.session.event_occurred.connect(on_event)
		board._process(0.5)
		check(events == ["Fruit Salad"], pause + " board route executes already-complete paused recipe once")
		check(pending.progress == 3 and board.session.elapsed == 3, pause + " does not advance incomplete craft or gameplay clock")
		check(not board.session.stacks.has(ids[0]) and not board.craft_progress.bars.has(ids[0]), pause + " removes completed task and its feedback")
		if pause.begins_with("held"):
			check(board.session.drag.active() and board.drag_grant >= 0 and pending.paused == (pause == "held_tail"), pause + " preserves source hold state during unrelated completion")
		board._process(0.1)
		check(events == ["Fruit Salad"] and pending.progress == 3, pause + " next paused frame neither repeats output nor advances pending work")
		board.session.event_occurred.disconnect(on_event)
	board.queue_free(); await process_frame; await create_timer(0.1).timeout
	print("Crafting order board clock: %d/%d passed; headless integration only" % [checks - failures, checks])
	quit(1 if failures else 0)
