extends SceneTree
const Layout = preload("res://scripts/ui/source_hud_layout.gd")
const Queue = preload("res://scripts/ui/info_request_queue.gd")
var failures := 0
func check(value: bool, label: String) -> void:
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var layout = Layout.new()
	layout.configure(JSON.parse_string(FileAccess.get_file_as_string("res://data/stackcraft.json")))
	check(layout.source_backed and layout.reference_height == 1080, "source height-matched CanvasScaler")
	for extent in [Vector2(1920,1080), Vector2(1512,1080), Vector2(2400,1080)]:
		check(layout.rect("DayTimeUI", extent, Rect2()) == Rect2(30,30,300,50), "day rect invariant under aspect")
		check(layout.rect("MenuPanel", extent, Rect2()) == Rect2(extent.x-400,0,400,1080), "right anchored full height menu")
		check(layout.rect("InfoPanel", extent, Rect2()).position == Vector2(30,1050), "bottom left info pivot")
	var queue = Queue.new()
	queue.submit("card", 0, {"header":"Card"})
	queue.submit("quest", 0, {"header":"Quest"})
	check(queue.current().header == "Quest", "latest equal priority wins")
	queue.submit("modal", 2, {"header":"Modal"})
	queue.submit("sequence", 1, {"header":"Sequence"})
	check(queue.current().header == "Modal", "modal wins")
	queue.submit("modal", 2, {})
	check(queue.current().header == "Sequence", "clear reveals underlying request")
	var board = load("res://scripts/ui/board.gd").new()
	root.add_child(board)
	await process_frame
	board.session.start_new_game()
	board._enter_game()
	await process_frame
	check(board.source_hud.size.y == 1080, "source logical height")
	check(board.day_clock.size == Vector2(300,50), "native day source size")
	check(board.detail_panel.size.y == 1080, "native journal full height")
	check(board.stat_labels.size() == 3, "source three stats")
	board.info_requests.submit("test", 0, {"header":"Villager", "body":"A healthy villager."})
	board._sync_source_info()
	check(board.card_hover.position.x == 30, "native info left anchor")
	check(is_equal_approx(board.card_hover.position.y+board.card_hover.size.y, 1050), "native info bottom anchor")
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Source HUD failures: ", failures)
	quit(1 if failures else 0)
