extends SceneTree
## Source CardBuyer.ProcessTransaction; witness request origins, not settled poses.
const Board := preload("res://scripts/ui/board.gd")
const Spawn := preload("res://scripts/model/scene_spawn.gd")

class QuietAudio extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_name: String) -> bool: return false
	func play_music() -> bool: return false

var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func run() -> void:
	var board := Board.new()
	board.feedback.free()
	board.feedback=QuietAudio.new()
	board.slot_root="user://live-buyer-spawn/slots"
	board.options_path="user://live-buyer-spawn/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	check(board.data_error==OK,"locked source data")
	if board.data_error!=OK:
		board.free()
		finish()
		return
	board.start_new()
	var session=board.session
	for id in session.cards.keys(): session._remove_card(id)
	var neutral: Rect2=session.board_bounds
	var base_origin: Vector2=Spawn.buyer_position(board.catalog,session.scene_name,neutral,session.board_top_margin)
	var coin: String=session.world.currency_guid
	var requests: Array[Vector2] = []
	var select := board._select_spawn_target
	session.spawn_target_selector=func(id: int, ignored: int):
		if session.cards[id].definition_guid==coin: requests.append(session.cards[id].position)
		return select.call(id,ignored)
	var plank: int=session.spawn_card(board.catalog.find_by_name("Plank"),Vector2(-2,-2),-1,{"refuse_attach":true})
	await drop_to_buyer(board,plank)
	check(not session.cards.has(plank) and requests==[base_origin,base_origin],
		"ordinary two-coin sale preserves exact source spawn request origin")
	for id in session.cards.keys(): session._remove_card(id)
	requests.clear()
	var yard: int=session.spawn_card(board.catalog.find_by_name("Yard"),Vector2(-2,-2),-1,{"refuse_attach":true})
	var grown: Rect2=session.board_bounds
	var grown_origin: Vector2=Spawn.buyer_position(board.catalog,session.scene_name,grown,session.board_top_margin)
	check(yard>=0 and session.stats().total_boost==4 and grown_origin!=base_origin,"actual Yard expands the authored buyer")
	var scene_events: Array[Rect2]=[]
	board.source_board_bounds_updated.connect(func(bounds: Rect2): scene_events.append(bounds))
	await drop_to_buyer(board,yard)
	check(not session.cards.has(yard) and session.board_bounds==neutral
		and session.stats().currency==3 and scene_events==[neutral],
		"buyer destroys Yard, pays exactly three, and the first true stats event shrinks once")
	check(requests==[grown_origin,base_origin,base_origin],
		"three live buyer origins: pre-shrink first, post-shrink second/third; observed %s" % [str(requests)])
	session.spawn_target_selector=Callable()
	board.free()
	await process_frame
	finish()

func drop_to_buyer(board: Board, id: int) -> void:
	board._refresh()
	await physics_frame
	await physics_frame
	var press := InputEventMouseButton.new()
	press.button_index=MOUSE_BUTTON_LEFT
	press.pressed=true
	press.position=board.camera.unproject_position(board.views[id].global_position)
	board._unhandled_input(press)
	check(board.dragging==id and board.session.drag.active_for(id), "actual Board pick captures the sold card")
	var buyer: Vector3=board.trade_zones[0].center
	var dest:=board.camera.unproject_position(Vector3(buyer.x,0,-buyer.z))
	var motion := InputEventMouseMotion.new()
	motion.position=dest
	motion.relative=dest-press.position
	board._input(motion)
	var release := InputEventMouseButton.new()
	release.position=dest
	release.button_index=MOUSE_BUTTON_LEFT
	board._input(release)

func check(ok: bool,label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func finish() -> void:
	print("Source live buyer spawn: %d/%d" % [checks-failures,checks])
	quit(int(failures>0))
