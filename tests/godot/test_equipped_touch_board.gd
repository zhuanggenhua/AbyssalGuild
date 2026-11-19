extends "res://tests/godot/test_source_touch_card_board.gd"

func panel_point(wearer: int) -> Vector2:
	var shape: CollisionShape3D = board.equipment_display.records[wearer].collider.get_child(0)
	for x in range(-3,4):
		for z in range(-6,7):
			var p: Vector2 = board.camera.unproject_position(shape.global_position + Vector3(x*.04,0,z*.045))
			if int(board._pick_target(p).panel_owner) == wearer: return p
	return Vector2.INF

func edge(index: int, down: bool, p: Vector2, cancel: bool = false) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.position = root.get_final_transform() * p
	e.pressed = down
	e.canceled = cancel
	Input.parse_input_event(e)
	Input.flush_buffered_events()

func run() -> void:
	Input.emulate_mouse_from_touch = true
	root.size = Vector2i(1440,900)
	board = BoardUnderTest.new()
	board.feedback.free()
	board.feedback = QuietAudio.new()
	var save := "user://equipped-touch-%d" % Time.get_ticks_usec()
	board.slot_root = save.path_join("slots")
	board.options_path = save.path_join("options.json")
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	check(board.data_error == OK,"locked scene catalog present")
	if board.data_error != OK:
		board.queue_free()
		quit(1)
		return
	board.start_new()
	board.set_process(false)
	clear_cards()
	var wearer := spawn("Villager",Vector2(-1,2))
	var gear := spawn("Sword",Vector2(-4,2))
	await settle_views()
	check(board.equipment_display.records.has(wearer),"真实 Main 装备面板碰撞")
	if not board.equipment_display.records.has(wearer):
		board.queue_free()
		quit(1)
		return
	var loose_point := reachable(gear)
	check(loose_point.is_finite(),"可按原始散落装备")
	# 普通按键先写每卡独立的起点，随后装备再按，不能被面板位置改写。
	await touch(0,true,loose_point)
	var original_press: Vector3 = board.views[gear].standard_drag_start
	check(board._touch_drags.has(gear) and original_press != Vector3.ZERO,"普通接收者记录原卡三维起点")
	await touch(0,false,loose_point)
	check(board.session.equipment.equip(wearer,gear),"正式装备模型挂到穿戴者")
	board._sync_views()
	check(board.equipment_display.is_expanded(wearer) and board.equipment_display.click_panel(wearer),
		"正式装备后面板可收起")
	await settle_views()
	var panel := panel_point(wearer)
	check(panel.is_finite() and not board.views[gear].visible,"折叠面板有实体且隐藏装备")
	if not panel.is_finite():
		board.queue_free()
		quit(1)
		return
	await touch(0,true,panel)
	check(board._touch_panel_presses.has(0) and board.dragging < 0 and board._touch_drags.is_empty()
		and not board.equipment_display.is_expanded(wearer),"触点记录面板而不拖穿戴者，不在按下开合")
	await touch(0,false,panel,true)
	check(not board.equipment_display.is_expanded(wearer) and board._touch_panel_presses.is_empty(),"取消只清收据")
	await touch(0,true,panel)
	await touch(0,false,Vector2(20,60))
	check(not board.equipment_display.is_expanded(wearer),"另一落点不确认原面板")
	await touch(0,true,panel)
	var cover := Control.new()
	cover.size = Vector2(90,60)
	cover.position = panel-cover.size/2
	cover.mouse_filter = Control.MOUSE_FILTER_STOP
	board.hud.add_child(cover)
	await process_frame
	await touch(0,false,panel)
	check(not board.equipment_display.is_expanded(wearer) and board._touch_panel_presses.is_empty(),
		"释放被 GUI 截获，不能点击背后的面板")
	cover.free()
	await touch(0,true,panel)
	await touch(0,false,panel)
	check(board.equipment_display.is_expanded(wearer) and board.views[gear].visible and board._touch_panel_presses.is_empty(),
		"同一真实面板触点释放打开装备，不经模拟鼠标补发")
	await settle_views()
	var gear_point := reachable(gear)
	check(gear_point.is_finite(),"点到展开装备的独立碰撞体")
	if not gear_point.is_finite():
		board.queue_free()
		quit(1)
		return
	var before: Vector3 = board.views[gear].global_position
	board.feedback.events.clear()
	edge(0,true,gear_point)
	var hold = board._touch_drags.get(gear)
	check(hold != null and board.touch_card_receivers.owns(0) and not board.session.equipment.owners.has(gear),
		"实际装备按下卸装、捕获本卡和新单牌堆")
	check(hold != null and hold.start == original_press and hold.deferred_gear_pose
		and board.views[gear].global_position.is_equal_approx(Vector3(before.x,0,before.z)),
		"按下仅从挂点 XZ 注册归平，不抬高、不覆盖旧普通起点")
	check(not board.feedback.events.has("CardPick"),"装备分支不发 CardPick")
	board._advance_running_frame(0)
	var h := float(board.catalog.settings("CardSettings").get("dragHeight",0.1))
	check(hold != null and not hold.deferred_gear_pose and is_equal_approx(board.views[gear].global_position.y,h),
		"下一正常 Update 才把已卸装备抬到原拖动高度")
	await move(0,gear_point+Vector2(-50,0))
	var held_pos: Vector2 = board.session.card_target_position(gear)
	check(held_pos.x < before.x,"装备使用按下时的实时共享指针偏移")
	await touch(0,false,Vector2(1400,100),true)
	check(board.session.card_target_position(gear).is_equal_approx(held_pos) and not board.session.drag.active_for(gear)
		and board.feedback.events.count("CardDrop")==1 and not board.feedback.events.has("CardPick"),
		"取消后的原装备接收者只放下最后位置一次，不拿取消落点做采样")
	board.queue_free()
	await process_frame
	print("Source equipped touch Board: %d/%d passed" % [checks-failures,checks])
	quit(0 if failures == 0 else 1)
