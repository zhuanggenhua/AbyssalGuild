extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
const Card = preload("res://scripts/model/card.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_kind: String) -> bool: return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var board = Board.new(); board.feedback.free(); board.feedback = SilentFeedback.new()
	var path := "user://motion-board-%d" % Time.get_ticks_usec()
	board.slot_root = path+"/slots"; board.options_path = path+"/options.json"; board.legacy_paths.clear()
	root.add_child(board); await process_frame
	check(board.data_error == OK,"source data available")
	if board.data_error != OK: board.queue_free(); quit(1); return
	board.start_new(); board.set_process(false)
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board.session.spawn_target_selector = Callable(); board.session.spawn_layout_resolver = Callable()
	board.session.phase = "playing"; board.session.paused = true
	var guid: String = board.catalog.find_by_name("Apple")
	var id: int = board.session.spawn_card(guid,Vector2(-3,-1),-1,{"refuse_attach":true})
	var tail: int = board.session.spawn_card(guid,Vector2(-1,-1),-1,{"refuse_attach":true})
	board.session.move_to_stack(tail,board.session.cards[id].stack_id)
	board._sync_views()
	var initial: Vector3 = board.views[id].position
	board._set_board_card_position(id,Vector2(2,-1))
	var save_before: Dictionary = Codec.capture(board.session)
	board._sync_views(0.05)
	check(board.views[id].position.is_equal_approx(initial.lerp(Vector3(2,0.06,1),0.75)),"ordinary stack source OutQuad half-duration")
	check(Codec.capture(board.session) == save_before,"presentation sync leaves model save and RNG unchanged")
	board._sync_views(); var halfway: Vector3 = board.views[id].position
	check(halfway != Vector3(2,0.06,1),"zero-time refresh cannot snap target")
	board._process(0.05)
	check(board.views[id].position.is_equal_approx(Vector3(2,0.06,1)),"unscaled move completes while model paused")
	board._begin_card_press({"card_id":id,"panel_owner":-1},board.camera.unproject_position(board.views[id].position))
	board._card_pointer_known = false
	board._set_board_card_position(id,Vector2(-2,-1))
	var tail_before: Vector3 = board.views[tail].position
	board._sync_views(0.001)
	check(is_equal_approx(board.views[id].position.y,0.1) and is_equal_approx(board.views[id].position.x,-2),"held head snaps to source drag height")
	var tail_target: Vector3 = board.views[id].position + Vector3(0,0.002,0.18)
	check(board.views[tail].position.is_equal_approx(tail_before.lerp(tail_target,1-exp(-0.1))),"board tail uses source sharpness and reflected step")
	board.dragging = -1; board.session.drag.finish_standard(); board.session.combat.dragged.clear()
	board._sync_views(0.1)
	check(is_equal_approx(board.views[id].position.y,0.06),"release settles ordinary grounded pose")
	board._set_board_card_position(id,Vector2(3,-1)); board._sync_views(0.02)
	var replacement = Card.new(id,guid,board.catalog.fields(guid))
	replacement.position = board.session.cards[id].position; replacement.stack_id = board.session.cards[id].stack_id
	board.session.cards[id] = replacement
	board._sync_views()
	check(is_equal_approx(board.views[id].position.x,3),"same ID same definition new object has no stale tween")
	board.session._remove_card(tail); board._sync_views()
	check(not board.card_motion.states.has(tail),"deleted cards clear presentation state")
	board._show_title(); check(board.card_motion.states.is_empty(),"title clears motion state")
	board._enter_game(); check(board.card_motion.states.size() <= board.session.cards.size(),"entry rebuilds only live state")
	board.queue_free(); await process_frame
	print("Card motion board: %d/%d passed" % [checks-failures,checks]); quit(1 if failures else 0)
