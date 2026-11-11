extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const Drag = preload("res://scripts/ui/card_drag_input.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_kind: String) -> bool: return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func fixture(board) -> int:
	board.session.drag.reset(); board.dragging = -1; board.drag_grant = -1; board.drag_delta = Vector2.ZERO
	board.session.combat.dragged.clear(); board._card_pointer_known = false
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board.session.phase = "playing"; board.session.paused = true; board.session.cycle.reset()
	board.session.spawn_target_selector = Callable(); board.session.spawn_layout_resolver = Callable()
	board.pause_overlay.hide()
	var id: int = board.session.spawn_card(board.catalog.find_by_name("Card_Chest_WoodenChest"),Vector2.ZERO,-1,{"refuse_attach":true})
	board.session.cards[id].stored_coins = 3
	board._refresh()
	board._begin_card_press({"card_id":id,"panel_owner":-1},board.camera.unproject_position(board.views[id].position))
	return id
func motion(board, delta: Vector2) -> void:
	var point: Vector2 = board.drag_origin + delta
	board._update_drag_position(board.camera.unproject_position(Vector3(point.x,0,-point.y)))
func release(board) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = false; event.position = board._card_pointer
	board._input(event)
func run() -> void:
	var board = Board.new(); board.feedback.free(); board.feedback = SilentFeedback.new()
	var path := "user://drag-board-%d" % Time.get_ticks_usec()
	board.slot_root = path+"/slots"; board.options_path = path+"/options.json"; board.legacy_paths.clear()
	root.add_child(board); await process_frame
	check(board.data_error == OK,"source data available")
	if board.data_error != OK: board.queue_free(); quit(1); return
	board.start_new(); board.set_process(false)
	var id := fixture(board)
	var original: Vector2 = board.session.card_target_position(id)
	motion(board,Vector2(0.005,0))
	check(board.session.card_target_position(id).distance_to(original+Vector2(0.005,0)) < 0.0001,"sub-pixel movement updates held model without dead zone")
	check(not board.drag_moved,"below world threshold remains click")
	release(board)
	check(board.session.cards[id].stored_coins == 2,"small real motion permits source chest click")
	id = fixture(board); original = board.session.card_target_position(id)
	motion(board,Vector2(0.025,0))
	check(board._card_pointer.distance_to(board.press_position) < 7,"reproduction displacement is below former pixel threshold")
	check(board.drag_moved,"source world distance rejects click below former seven-pixel threshold")
	release(board)
	check(board.session.cards[id].stored_coins == 3,"small-pixel genuine drag cannot withdraw currency")
	id = fixture(board)
	motion(board,Vector2(2,0)); check(board.drag_moved,"moving away is a drag")
	motion(board,Vector2.ZERO); check(not board.drag_moved,"return to origin clears final-displacement classification")
	release(board)
	check(board.session.cards[id].stored_coins == 2,"away-and-return source click withdraws once")
	release(board); check(board.session.cards[id].stored_coins == 2,"duplicate release cannot withdraw twice")
	id = fixture(board); original = board.session.card_target_position(id)
	motion(board,Vector2(200,0)); var clamped: Vector2 = board.session.card_target_position(id)
	motion(board,Vector2(190,0))
	check(board.session.card_target_position(id).is_equal_approx(clamped),"beyond-board motion preserves original grab offset while clamped")
	motion(board,Vector2.ZERO)
	check(board.session.card_target_position(id).distance_to(original) < 0.0001,"return from clamped boundary restores original pointer offset")
	release(board)
	id = fixture(board); original = board.session.card_target_position(id)
	board._toggle_pause_menu(); board.camera.position.x += 0.5
	board._process(0.01)
	check(board.session.card_target_position(id).distance_to(original) > 0.4,"held card follows stationary pointer after camera changes even in pause menu")
	check(board.session.drag.active() and board.dragging == id,"menu and camera updates preserve captured drag permission")
	release(board); check(not board.session.drag.active(),"actual release over pause menu settles held state")
	board._toggle_pause_menu()
	var settings: Dictionary = Drag.source_settings(board.catalog,board.session.scene_name)
	var threshold: float = settings.clickThreshold
	settings.clickThreshold = 0.2
	id = fixture(board); motion(board,Vector2(0.1,0)); release(board)
	check(board.session.cards[id].stored_coins == 2,"scene-referenced custom threshold is honored")
	settings.clickThreshold = threshold
	# A high stack member's pre-split height contributes, not native mesh clearance.
	id = fixture(board)
	check(is_zero_approx(board.drag_start_position.y),"generated/native display clearance does not contaminate source click height")
	release(board)
	# Real held pointer motion must reach the source trade header before final placement.
	id = fixture(board); release(board)
	for card_id in board.session.cards.keys(): board.session._remove_card(card_id)
	for quest in board.session.quest_tracker.definitions: board.session.quest_tracker.completed_ids[quest] = true
	board.session.vendor_payments.clear(); board._refresh(); board.vendor_unlock.cancel()
	var vendor: Dictionary = board.trade_zones[1]
	var coin: int = board.session.spawn_card(board.session.world.currency_guid, Vector2.ZERO,-1,{"refuse_attach":true})
	board._refresh()
	board._begin_card_press({"card_id":coin,"panel_owner":-1},board.camera.unproject_position(board.views[coin].position))
	var vendor_point := Vector2(vendor.center.x,vendor.center.z)
	motion(board,vendor_point-board.drag_anchor)
	var held: Vector2 = board.session.card_target_position(coin)
	var placement: Vector2 = board._clamp_stack_position(coin,vendor_point)
	check(held.y > placement.y+0.1,"held source pointer may enter top-margin trade region")
	check(preload("res://scripts/model/trade_layout.gd").intersects(vendor,Vector3(held.x,0,held.y),0.25),"real held position intersects intended vendor collider")
	release(board)
	check(not board.session.cards.has(coin) and board.session.vendor_payments.get(str(vendor.pack_guid),0) == 1,"actual pointer release pays vendor installment rather than dropping below header")
	board.queue_free(); await process_frame; await create_timer(0.3).timeout
	print("Card drag board: %d/%d passed" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
