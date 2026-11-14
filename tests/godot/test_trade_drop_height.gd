extends SceneTree
## a11a89 CardController trade overlap uses the held transform, not Flatten().
## This executes native drop paths against imported raw bounds. It is not a
## Unity/PhysX run or verification of its zero-height BoxCollider treatment.
const Board = preload("res://scripts/ui/board.gd")
const Drag = preload("res://scripts/ui/card_drag_input.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func sample(board, kind: String, edge: float, height: float, center: bool = false, direct: bool = false) -> void:
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board.session.vendor_payments.clear()
	board.session.phase = "playing"
	board._refresh()
	var index := 0 if kind == "buyer" else 1
	var zone: Dictionary = board.trade_zones[index]
	var bounds: AABB = zone.world_bounds
	var destination := Vector2(zone.center.x, zone.center.z if center else bounds.position.z-edge)
	var start := destination + Vector2(0, -1)
	var name := "Wood" if kind == "buyer" else "Coin"
	var id: int = board.session.spawn_card(board.catalog.find_by_name(name),start,-1,{"refuse_attach":true})
	board._refresh()
	board.views[id].position = Vector3(start.x,0.06,-start.y)
	var before_bounds: AABB = board.trade_zones[index].local_bounds
	var down: Vector2 = board.camera.unproject_position(Vector3(start.x,0,-start.y))
	var up: Vector2 = board.camera.unproject_position(Vector3(destination.x,0,-destination.y))
	var label := "%s h=%.2f edge=%.2f center=%s direct=%s" % [kind,height,edge,center,direct]
	if direct:
		# Existing adapter branch: _finish_drag begins a missing held session.
		board.dragging = id
		board.drag_moved = true
		board.drag_delta = destination-start
	else:
		board._begin_card_press({"card_id":id,"panel_owner":-1,"trade_zone_index":-1},down)
		check(board.dragging == id and board.drag_grant == id,label+" captured press")
		board._update_drag_position(up)
		board._sync_views(0.0)
		check(board.session.card_target_position(id).distance_to(destination)<0.0001,label+" ground projection/clamp unchanged")
		check(absf(board.views[id].global_position.y-height)<0.00001,label+" actual held root uses scene-bound height")
	var radius := float(Drag.source_settings(board.catalog,board.session.scene_name).attachRadius)
	var face_distance: float = 0.0 if center else maxf(edge,0.0)
	var expected := face_distance*face_distance+height*height <= radius*radius
	var payout := int(board.catalog.fields(board.session.cards[id].definition_guid).get("sellPrice",1)) if kind == "buyer" else 0
	board._finish_drag(up)
	check(board.dragging == -1 and board.drag_grant == -1,label+" release clears capture before trade")
	check(not board.session.cards.has(id) == expected,label+" transaction uses source-height overlap")
	check(board.trade_zones[index].local_bounds == before_bounds,label+" raw collider not expanded")
	if kind == "vendor":
		check(int(board.session.vendor_payments.get(zone.pack_guid,0)) == (1 if expected else 0),label+" installment iff accepted")
	else:
		check(board.session.stats().currency == (payout if expected else 0),label+" payout iff accepted")
func run() -> void:
	root.size = Vector2i(1280,720)
	root.content_scale_size = Vector2i.ZERO
	var board := Board.new()
	board.options_path = "user://trade-height-options.json"
	board.slot_root = "user://trade-height-slots"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	check(board.data_error == OK,"licensed source data loaded")
	if board.data_error != OK:
		board.queue_free()
		quit(1)
		return
	board.start_new()
	board.set_process(false)
	for id in board.session.quest_tracker.definitions: board.session.quest_tracker.completed_ids[id]=true
	board._refresh()
	var settings: Dictionary = Drag.source_settings(board.catalog,"Main")
	var original_height: float = settings.dragHeight
	check(is_equal_approx(original_height,0.1) and is_equal_approx(float(settings.attachRadius),0.25),"locked source settings")
	check(board.trade_zones[0].local_bounds.size.y == 0 and board.trade_zones[1].local_bounds.size.y == 0,"source raw zero-height boxes retained")
	for kind in ["buyer","vendor"]:
		sample(board,kind,0,0.1,true)
		for edge in [0.22,0.24,0.26]: sample(board,kind,edge,0.1)
		sample(board,kind,0.24,0.1,false,true)
		# A modified private fixture checks the actual CardSettings binding, not
		# a claim that the locked template ships with these non-default values.
		settings.dragHeight = 0.2
		sample(board,kind,0,0.2,true)
		sample(board,kind,0.14,0.2)
		sample(board,kind,0.16,0.2)
		settings.dragHeight = 0.0
		sample(board,kind,0.24,0.0)
		settings.dragHeight = original_height
	# A decoy global default must not supersede Main's explicit CardManager ref.
	var decoy := {"guid":"test-only-global-height","script_class":"CardSettings","fields":settings.duplicate(true)}
	decoy.fields.dragHeight = 0.4
	board.catalog.data.settings.push_front(decoy)
	check(is_equal_approx(float(board.catalog.settings("CardSettings").dragHeight),0.4),"decoy global setting differs")
	check(is_equal_approx(float(Drag.source_settings(board.catalog,"Main").dragHeight),0.1),"scene reference wins over global setting")
	sample(board,"buyer",0.22,0.1)
	sample(board,"vendor",0.24,0.1)
	board.catalog.data.settings.pop_front()
	settings.dragHeight = original_height
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Trade drop height: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
