extends SceneTree
## Audits actual authored Board stat transactions without advancing days.
const Board = preload("res://scripts/ui/board.gd")
const Layout = preload("res://scripts/model/board_layout.gd")

class QuietAudio extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_name: String) -> bool: return false
	func play_music() -> bool: return false

var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func run() -> void:
	var board := Board.new()
	board.feedback.free()
	board.feedback = QuietAudio.new()
	board.slot_root = "user://source-live-board-bounds/slots"
	board.options_path = "user://source-live-board-bounds/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	check(board.data_error == OK, "locked source catalog")
	if board.data_error != OK:
		board.free()
		finish()
		return
	board.start_new()
	var session = board.session
	for id in session.cards.keys(): session._remove_card(id)
	# Keep setup targets direct so the normal spawn overlap solver cannot move
	# our witnesses before the StatsSnapshot itself reaches Board.
	session.spawn_target_selector = Callable()
	session.spawn_layout_resolver = Callable()
	var neutral: Rect2 = session.board_bounds
	var booster := ""
	for guid in board.catalog.definitions:
		if int(board.catalog.fields(guid).get("boostAmount",0)) == 10:
			booster = guid
			break
	check(board.running and neutral.has_area() and not booster.is_empty(), "source neutral Board and 10-point capacity card")
	if booster.is_empty():
		board.free()
		finish()
		return
	var coin: String = session.world.currency_guid
	var wood: String = board.catalog.find_by_name("Wood")
	var a: int = session.spawn_card(wood, Vector2(2, 0), -1, {"refuse_attach":true})
	var b: int = session.spawn_card(wood, Vector2(-2, 0), -1, {"refuse_attach":true})
	var c: int = session.spawn_card(wood, Vector2(2, -2), -1, {"refuse_attach":true})
	var events: Array = []
	board.source_board_bounds_updated.connect(func(bounds: Rect2):
		var point: Vector2 = Vector2.INF
		if board.session.cards.has(a): point = board.session.cards[a].position
		var front: float = INF
		if not board.trade_zones.is_empty(): front = board.trade_zones[0].center.z
		events.append({"bounds":bounds,"point":point,"camera":board.camera_motion.target,"trade_front":front}))
	var first: int = session.spawn_card(booster, Vector2.ZERO, -1, {"refuse_attach":true})
	var extended: Rect2 = session.board_bounds
	check(events.size() == 1 and extended.size.is_equal_approx(neutral.size * 1.1)
		and session.cards[a].position == Vector2(2, 0), "ordinary source spawn expands immediately, without moving stacks")
	var edge := board._clamp_stack_position(a, extended.end)
	var locked := board._clamp_stack_position(b, Vector2(extended.position.x, extended.end.y))
	var soft_edge: Vector2 = Layout.enforce_placement(Vector2(neutral.end.x,-2), board._layout_states().filter(
			func(row): return row.id == session.cards[c].stack_id)[0], neutral, session.board_top_margin) + Vector2(0.01,0)
	board._set_board_card_position(a, edge)
	board._set_board_card_position(b, locked)
	board._set_board_card_position(c, soft_edge)
	board.layout_locks[session.cards[b].stack_id] = true
	board._sync_views(1)
	var old_pose: Vector3 = board.views[a].position
	board.camera_motion.target.x = extended.end.x + float(board.camera_motion.settings.panPadding)
	var old_camera: Vector3 = board.camera.position
	session._remove_card(first)
	board._refresh()
	check(session.stats().total_boost == 0 and events.size() == 1 and session.board_bounds == extended,
		"a silent mutation and UI refresh do not change bounds")
	session.spawn_card(coin, Vector2.ZERO, -1, {"refuse_attach":true})
	var padding: float = board.camera_motion.settings.panPadding
	var top_margin: float = session.board_top_margin
	check(events.size() == 2 and events.back().bounds == neutral and events.back().point == edge
		and is_equal_approx(events.back().camera.x, neutral.end.x + padding)
		and is_equal_approx(events.back().trade_front, neutral.end.y - top_margin * 0.5)
		and board.camera.position == old_camera, "same bounds event updates camera target and trade header before enforcing stacks")
	var corrected: Vector2 = board._clamp_stack_position(a, edge)
	check(session.cards[a].position.is_equal_approx(corrected) and corrected != edge
		and session.cards[b].position == locked and session.cards[c].position == soft_edge,
		"shrink corrects full target footprint, skips locked and below squared threshold")
	board._sync_views(0)
	var motion: Dictionary = board.card_motion.states[a]
	check(board.views[a].position == old_pose and motion.mode == "animated"
		and Vector2(motion.target.x, -motion.target.z).is_equal_approx(corrected),
		"existing ordinary view retargets without snapping")
	var duration: float = board.catalog.settings("CardSettings").get("moveDuration",0.1)
	board._sync_views(duration * 0.5)
	check(board.views[a].position.distance_squared_to(old_pose) > 0
		and board.views[a].position.distance_squared_to(motion.target) > 0,
		"half-duration motion is between the source and corrected target")
	board._sync_views(duration)
	check(board.views[a].position.is_equal_approx(motion.target), "the same ordinary tween settles")
	board.layout_locks.clear()
	for id in session.cards.keys(): session._remove_card(id)
	var ids: Array[int] = []
	for i in 10:
		ids.append(session.spawn_card(booster, Vector2.ZERO, -1, {"refuse_attach":true}))
	var capped: Rect2 = session.board_bounds
	check(session.stats().total_boost == 100 and capped.size.is_equal_approx(neutral.size * 2),
		"ten authored boosters reach exactly the source 100 cap")
	events.clear()
	session.spawn_card(coin, Vector2.ZERO, -1, {"refuse_attach":true})
	check(events.is_empty(), "raw total equal to cached capped weight does not notify")
	var excess: int = session.spawn_card(booster, Vector2.ZERO, -1, {"refuse_attach":true})
	board.camera_motion.target.x = capped.end.x + padding + 2
	session.spawn_card(coin, Vector2.ZERO, -1, {"refuse_attach":true})
	check(session.stats().total_boost == 110 and events.size() == 2 and session.board_bounds == capped
		and is_equal_approx(board.camera_motion.target.x, capped.end.x + padding),
		"110 vs capped 100 repeatedly notifies and re-clamps even with unchanged footprint")
	session._remove_card(excess)
	session.spawn_card(coin, Vector2.ZERO, -1, {"refuse_attach":true})
	check(events.size() == 2 and session.board_bounds == capped,
		"110 to exactly 100 does not notify, because stored weight was already 100")
	session._remove_card(ids.back())
	session.spawn_card(coin, Vector2.ZERO, -1, {"refuse_attach":true})
	check(events.size() == 3 and session.board_bounds.size.is_equal_approx(neutral.size * 1.9),
		"90 vs cached 100 actually shrinks")
	board.start_new()
	events.clear()
	session.spawn_card(booster, Vector2.ZERO, -1, {"refuse_attach":true})
	check(board.session != session and events.is_empty() and board.session.board_bounds == neutral,
		"replaced session cannot resize the new Board")
	board._show_title()
	board.session.spawn_card(booster, Vector2.ZERO, -1, {"refuse_attach":true})
	check(not board.running and events.is_empty() and board.geometry_key.is_empty(),
		"Title retired the gameplay bounds callback")
	board.free()
	await process_frame
	finish()

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func finish() -> void:
	print("Source live Board bounds: %d / %d" % [checks - failures, checks])
	quit(int(failures > 0))
