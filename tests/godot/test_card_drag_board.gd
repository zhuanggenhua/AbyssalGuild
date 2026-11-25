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
	await final_slot_receiver(board)
	await grounded_repeat(board)
	await captured_click_puff(board)
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
	var draw_samples: Array = []
	var puffs: Array[Vector3] = []
	var pack_stack: int=board.session.cards[click_pack].stack_id
	board.session.spawn_target_selector=func(spawned: int, _ignored: int) -> int:
		draw_samples.append([board.session.cards[spawned].position,board.session.spawn_query_height,
			board.session.cards[click_pack].uses_left,board.layout_locks.has(pack_stack)])
		return -1
	var capture_puff:=func(kind: String,payload: Dictionary):
		if kind=="puff_requested" and payload.card_id==click_pack: puffs.append(payload.position)
	board.session.event_occurred.connect(capture_puff)
	board._refresh()
	await physics_frame; await physics_frame
	press(board,click_pack)
	release(board)
	check(board.session.cards[click_pack].uses_left==uses-1 and board.release_queries.is_empty(),"no-motion pack click still draws once")
	check(draw_samples.size()==1 and draw_samples[0][0].is_equal_approx(Vector2.ZERO) and is_equal_approx(draw_samples[0][1],height+.1)
		and draw_samples[0][2]==uses and draw_samples[0][3],"native pack uses actual lifted target plus authored draw offset before using the slot")
	check(is_zero_approx(board.session.card_target_position_3d(click_pack).y) and puffs.is_empty(),"nonfinal native pack returns to grounded target without a destruction puff")
	for id in board.session.cards.keys():
		if id!=click_pack: board.session._remove_card(id)
	board.session.cards[click_pack].uses_left=1
	board._refresh()
	await physics_frame; await physics_frame
	press(board,click_pack)
	var final_held: Vector2=board.session.card_target_position(click_pack)
	release(board)
	check(not board.session.cards.has(click_pack) and draw_samples.size()==2
		and is_equal_approx(draw_samples[1][1],height+.1) and draw_samples[1][2]==1 and draw_samples[1][3],
		"final slot still draws once from the held target before destroying the pack")
	check(puffs.size()==1 and puffs[0].is_equal_approx(Vector3(final_held.x,height,final_held.y)),"final native pack puff uses the not-yet-grounded held pose")
	board.session.event_occurred.disconnect(capture_puff)
	board.session.spawn_target_selector=Callable()
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

## Starter's authored fourth draw is always Wood. Only the normal Godot
## pre-placement spawn selector is observed; no Unity collider result assumed.
func final_slot_receiver(board: WitnessBoard) -> void:
	var wood: String = board.catalog.find_by_name("Wood")
	for sample in [[1.370,true,false],[1.387,false,false],[1.405,false,false],[1.387,false,true]]:
		for id in board.session.cards.keys(): board.session._remove_card(id)
		board.session.spawn_target_selector = Callable()
		var wood_position := Vector2(sample[0],0)
		var receiver: int = board.session.spawn_card(wood,wood_position,-1,{"refuse_attach":true})
		var receiver_stack: int = board.session.cards[receiver].stack_id
		var starter: int = board.session.spawn_card(board.OUTBOUND_STARTER_PACK,Vector2.ZERO,-1,{"refuse_attach":true})
		board.session.cards[starter].uses_left = 1
		board.layout_key = board._layout_signature()
		board._refresh()
		board._sync_views(1.0)
		await physics_frame; await physics_frame
		var samples: Array = []
		board.session.spawn_target_selector = func(spawned: int, ignored: int) -> int:
			var winner := board._select_spawn_target(spawned,ignored)
			samples.append([spawned,board.session.cards[spawned].base_definition_guid,
				board.session.cards[spawned].position,board.session.spawn_query_height,
				board.session.card_target_position(receiver),winner])
			return winner
		if sample[2]:
			var point: Vector2 = board.camera.unproject_position(board.views[starter].global_position)
			touch(point,true)
			check(board.session.drag.active_for(starter), "native touch captures real Starter")
			touch(point,false)
		else:
			press(board,starter)
			check(board.drag_grant==starter, "physical press captures real Starter at X="+str(sample[0]))
			release(board)
		check(samples.size()==1 and not board.session.cards.has(starter),
			"only the final authored Starter slot draws once and destroys pack")
		if samples.size()!=1: continue
		var row: Array = samples[0]
		var expected: int = receiver_stack if sample[1] else -1
		check(row[1]==wood and row[2].is_equal_approx(Vector2.ZERO) and is_equal_approx(row[3],.2)
			and row[4].is_equal_approx(wood_position),
			"pre-resolution query is the authored Wood at held X/Z plus 0.2 Y at X="+str(sample[0]))
		check(row[5]==expected and (board.session.cards[row[0]].stack_id==receiver_stack)==sample[1],
			"real Godot spawn/merge boundary at X="+str(sample[0])+"; winner="+str(row[5]))
	board.session.spawn_target_selector = Callable()

func grounded_repeat(board: WitnessBoard) -> void:
	var chest_guid: String = board.catalog.find_by_name("Card_Chest_WoodenChest")
	for kind in [chest_guid,board.OUTBOUND_STARTER_PACK]:
		var is_chest: bool = kind == chest_guid
		for elapsed in [0.06,0.12]:
			for id in board.session.cards.keys(): board.session._remove_card(id)
			board.session.spawn_target_selector = Callable()
			board.session.spawn_layout_resolver = board._resolve_layout
			var item: int = board.session.spawn_card(kind,Vector2.ZERO,-1,{"refuse_attach":true})
			var counter := "stored_coins" if is_chest else "uses_left"
			if is_chest: board.session.cards[item].stored_coins = 3
			var initial: int = board.session.cards[item].get(counter)
			board.layout_key = board._layout_signature()
			board._refresh()
			board._sync_views(1.0)
			await physics_frame; await physics_frame
			var events: Array[String] = []
			var observe:=func(name: String, payload: Dictionary):
				if name=="card_created" or (name=="puff_requested" and payload.card_id==item): events.append(name)
			board.session.event_occurred.connect(observe)
			press(board,item)
			release(board)
			check(board.session.cards[item].get(counter)==initial-1
				and board.session.card_target_position(item).is_equal_approx(Vector2.ZERO),
				"first captured singleton click applies exactly once and restores unchanged XZ: "+counter)
			var first_events:=events.duplicate()
			board._sync_views(elapsed)
			await physics_frame; await physics_frame
			board.release_queries.clear()
			press(board,item)
			motion(board,Vector2(.013,0))
			var down: Vector3=board._mouse_drag.start
			release(board)
			var early: bool = elapsed < .1
			check(is_equal_approx(down.y,.016 if early else 0.0),
				"repeat snapshots authored OutQuad height after %.0fms: %s, Y=%.5f"%[elapsed*1000,counter,down.y])
			if early:
				check(board.session.cards[item].get(counter)==initial-1 and events==first_events
					and not board.release_queries.is_empty(),
					".013 plus .016 is a drag, no second debit/draw or puff: "+counter)
			else:
				check(board.session.cards[item].get(counter)==initial-2 and events.size()==2*first_events.size(),
					"settled repeat just .013 away clicks successfully: "+counter)
			board.session.event_occurred.disconnect(observe)
	board.session.spawn_layout_resolver = Callable()

func captured_click_puff(board: WitnessBoard) -> void:
	var chest_guid: String = board.catalog.find_by_name("Card_Chest_WoodenChest")
	for guid in [chest_guid,board.OUTBOUND_STARTER_PACK]:
		var chest: bool = guid == chest_guid
		for id in board.session.cards.keys(): board.session._remove_card(id)
		board._clear_puffs()
		board.session.spawn_target_selector = Callable()
		var at := Vector2(-1.3,-1.7)
		var id: int = board.session.spawn_card(guid,at,-1,{"refuse_attach":true})
		if chest: board.session.cards[id].stored_coins = 2
		else: board.session.cards[id].uses_left = 1
		board.layout_key = board._layout_signature()
		board._refresh()
		board._sync_views(1.0)
		await physics_frame; await physics_frame
		var former: Vector3 = board.views[id].global_position
		var observed: Array = []
		var label_at_effect: Array = []
		var created_renderer: Array[bool] = []
		board.puff_factory = func(scene_name: String, seed_no: int) -> Node3D:
			if chest: label_at_effect.append(board.views[id].stat_labels.price.text)
			var node: Node3D = board.visual_assets.create_puff(scene_name,seed_no)
			created_renderer.append(node != null)
			return node if node != null else Node3D.new()
		board.session.spawn_target_selector = func(spawned: int, _ignored: int) -> int:
			observed.append([board.session.cards[spawned].position,board.session.spawn_query_height])
			return -1
		press(board,id)
		motion(board,Vector2(.012,0))
		var held: Vector2 = board.session.card_target_position(id)
		var start_y: float = Drag.source_settings(board.catalog,board.session.scene_name).dragHeight
		var effect_at := Vector3(held.x,start_y,-held.y)
		check(not board.drag_moved and not former.is_equal_approx(effect_at)
			and board.views[id].global_position.is_equal_approx(former), "same-frame held model differs from live prior view")
		release(board)
		check(board.puffs.size()==1 and board.puffs[0].global_position.is_equal_approx(effect_at),
			"spawned captured click Puff uses held sample, not the live prior view: "+("chest" if chest else "pack"))
		if not board.visual_assets.puff_configuration(board.session.scene_name).is_empty():
			check(created_renderer==[true],"configured source particle node (not test dummy) was attached")
		else:
			print("SKIP captured click native Puff renderer; licensed visual manifest unavailable")
		if chest:
			check(label_at_effect==["1"] and board.session.cards[id].stored_coins==1
				and board.session.card_target_position(id).is_equal_approx(at),
				"chest label is updated before effect, then restores press origin")
			check(observed.size()==1 and observed[0][0].is_equal_approx(held+Vector2(board._card_footprint(id).x,0))
				and is_zero_approx(observed[0][1]), "attached coin query stays flat and at held point plus width")
		else:
			check(not board.session.cards.has(id) and observed.size()==1 and observed[0][0].is_equal_approx(held)
				and is_equal_approx(observed[0][1],.2), "last slot draw and pack removal intact")
		board.session.spawn_target_selector = Callable()
		board.puff_factory = Callable()
