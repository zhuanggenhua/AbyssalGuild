extends SceneTree
const Drag = preload("res://scripts/ui/card_drag_input.gd")
class WitnessBoard extends "res://scripts/ui/board.gd":
	var release_queries: Array[Vector3] = []
	func _nearby_stack(id: int, point: Vector3, radius: float, ignored: int = -1, equipment_drop: bool = false, held_root: int = -1, ordinary_live_rank: bool = false) -> int:
		if not equipment_drop and held_root >= 0: release_queries.append(point)
		return super._nearby_stack(id, point, radius, ignored, equipment_drop, held_root, ordinary_live_rank)
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	var events: Array[String] = []
	func play_event(kind: String) -> bool:
		events.append(kind)
		return false
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
func press(board, id: int) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = true
	event.position = board.camera.unproject_position(board.views[id].global_position)
	board._unhandled_input(event)

func motion(board, delta: Vector2) -> void:
	var point: Vector2 = board.drag_origin + delta
	board._update_drag_position(board.camera.unproject_position(Vector3(point.x,0,-point.y)))
func release(board) -> void:
	var event := InputEventMouseButton.new()
	event.button_index = MOUSE_BUTTON_LEFT; event.pressed = false; event.position = board._card_pointer
	board._input(event)
func touch(point: Vector2, down: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.index=0; event.pressed=down; event.position=root.get_final_transform()*point
	Input.parse_input_event(event)
	Input.flush_buffered_events()
func run() -> void:
	var board = WitnessBoard.new(); board.feedback.free(); board.feedback = SilentFeedback.new()
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
	await physics_frame; await physics_frame
	press(board,coin)
	check(board.dragging == coin and board.session.drag.active_for(coin), "actual board pointer hit captures a loose currency card")
	var vendor_point := Vector2(vendor.center.x,vendor.center.z)
	motion(board,vendor_point-board.drag_anchor)
	var held: Vector2 = board.session.card_target_position(coin)
	var placement: Vector2 = board._clamp_stack_position(coin,vendor_point)
	check(held.y > placement.y+0.1,"held source pointer may enter top-margin trade region")
	check(preload("res://scripts/model/trade_layout.gd").intersects(vendor,Vector3(held.x,0,held.y),0.25),"real held position intersects intended vendor collider")
	board.feedback.events.clear()
	release(board)
	check(not board.session.cards.has(coin) and board.session.vendor_payments.get(str(vendor.pack_guid),0) == 1,"actual pointer release pays vendor installment rather than dropping below header")
	check(board.feedback.events == ["CardDrop","Puff","CashRegister"], "real pointer settlement requests drop, zone puff and installment audio exactly once")
	await ordinary_pointer_rank(board,vendor_point)
	board.queue_free(); await process_frame; await create_timer(0.3).timeout
	print("Card drag board: %d/%d passed" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)

func ordinary_pointer_rank(board: WitnessBoard, vendor_point: Vector2) -> void:
	for id in board.session.cards.keys(): board.session._remove_card(id)
	var wood: String=board.catalog.find_by_name("Wood")
	var first: int=board.session.spawn_card(wood,Vector2(-2,-1.5),-1,{"refuse_attach":true})
	board._refresh()
	await physics_frame; await physics_frame
	var height: float=Drag.source_settings(board.catalog,board.session.scene_name).dragHeight
	for mode in ["mouse","touch"]:
		board.release_queries.clear()
		var point: Vector2=board.camera.unproject_position(board.views[first].global_position)
		if mode=="mouse": press(board,first)
		else: touch(point,true)
		var held: Vector2=board.session.card_target_position(first)
		if mode=="mouse": release(board)
		else: touch(point,false)
		check(board.release_queries.size()==1 and board.release_queries[0].is_equal_approx(Vector3(held.x,height,held.y)),
			"captured "+mode+" down/up without motion uses the last lifted source position")
		await physics_frame; await physics_frame
	board.release_queries.clear()
	press(board,first)
	motion(board,vendor_point-board.drag_anchor)
	var released: Vector2=board.session.card_target_position(first)
	var final: Vector2=board._clamp_stack_position(first,released)
	release(board)
	check(released.y>final.y+.1 and board.session.card_target_position(first).is_equal_approx(final)
		and board.release_queries.size()==1 and board.release_queries[0].is_equal_approx(Vector3(released.x,height,released.y)),
		"rejected vendor uses pre-placement pose but still grounds below the header")
	for id in board.session.cards.keys(): board.session._remove_card(id)
	var chest: int=board.session.spawn_card(board.catalog.find_by_name("Card_Chest_WoodenChest"),Vector2.ZERO,-1,{"refuse_attach":true})
	board.session.cards[chest].stored_coins=3
	board._refresh()
	await physics_frame; await physics_frame
	board.release_queries.clear()
	press(board,chest)
	release(board)
	check(board.session.cards[chest].stored_coins==2 and board.release_queries.is_empty(),"no-motion chest click still withdraws once")
	for id in board.session.cards.keys(): board.session._remove_card(id)
	var click_pack: int=board.session.spawn_card(board.OUTBOUND_STARTER_PACK,Vector2.ZERO,-1,{"refuse_attach":true})
	var uses: int=board.session.cards[click_pack].uses_left
	board._refresh()
	await physics_frame; await physics_frame
	press(board,click_pack)
	release(board)
	check(board.session.cards[click_pack].uses_left==uses-1 and board.release_queries.is_empty(),"no-motion pack click still draws once")
	for id in board.session.cards.keys(): board.session._remove_card(id)
	var base:=Vector2(-1.5,-1.5)
	var drag_id: int=board.session.spawn_card(wood,base-Vector2(1.5,0),-1,{"refuse_attach":true})
	var a: int=board.session.spawn_card(wood,base+Vector2(-.16,0),-1,{"refuse_attach":true})
	var b: int=board.session.spawn_card(wood,base+Vector2(.04,.18),-1,{"refuse_attach":true})
	var tail: int=board.session.spawn_card(wood,base+Vector2(0,-2),-1,{"refuse_attach":true})
	var pack: int=board.session.spawn_card(board.OUTBOUND_STARTER_PACK,base,-1,{"refuse_attach":true})
	var a_stack: int=board.session.cards[a].stack_id
	var b_stack: int=board.session.cards[b].stack_id
	check(board.session.move_to_stack(tail,b_stack),"receiving stack has a second member")
	board.layout_key=board._layout_signature()
	board._refresh()
	board._sync_views(1)
	board._set_board_card_position(b,base+Vector2(.34,.18))
	board.layout_key=board._layout_signature()
	board._sync_views(0)
	var query:=Vector3(base.x,height,base.y)
	var radius: float=board.catalog.settings("CardSettings").attachRadius
	check(not board.session.can_move_to_stack(drag_id,board.session.cards[pack].stack_id)
		and board._nearby_stack(drag_id,query,radius,a_stack)==b_stack
		and board._nearby_stack(drag_id,query,radius,b_stack)==a_stack,"both settled stacks are admitted and the nearest pack is not eligible")
	check(board._nearby_stack(drag_id,query,radius)==a_stack and board._nearby_stack(drag_id,query,radius,-1,true)==a_stack,
		"spawn-style and equipment queries keep their settled winner")
	var ap: Variant=board._sample_ai_actor_pose(a)
	var bp: Variant=board._sample_ai_actor_pose(b)
	var tailp: Variant=board._sample_ai_actor_pose(tail)
	check(ap is Vector3 and bp is Vector3 and tailp is Vector3
		and query.distance_squared_to(tailp)<query.distance_squared_to(ap)
		and query.distance_squared_to(ap)<query.distance_squared_to(bp),"only the real animated nonfirst receiver beats the settled winner")
	board._set_board_card_position(b,base+Vector2(3,.18))
	board.layout_key=board._layout_signature()
	board._sync_views(0)
	check(board._nearby_stack(drag_id,query,radius,-1,false,-1,true)==a_stack,
		"current proximity does not readmit a receiver outside the existing broad phase")
	board._set_board_card_position(b,base+Vector2(.34,.18))
	board.layout_key=board._layout_signature()
	board._sync_views(0)
	board.views[tail].rotation.y=.1
	check(board._nearby_stack(drag_id,query,radius,-1,false,-1,true)==a_stack,"unmapped receiver forces the entire query to settled ranking")
	board.views[tail].rotation.y=0.0
	await physics_frame; await physics_frame
	press(board,drag_id)
	motion(board,base-board.drag_anchor)
	release(board)
	check(board.session.cards[drag_id].stack_id==b_stack,"ordinary native release chooses the closest live member of an admitted stack")
