extends "res://tests/godot/test_equipped_touch_board.gd"
## Locked Board + real HUD + independent 3D physics; not a Unity execution-order oracle.
class StopSurface extends Control:
	var pressed := 0
	func _gui_input(event: InputEvent) -> void:
		if (event is InputEventMouseButton or event is InputEventScreenTouch) and event.pressed:
			pressed += 1
			accept_event()


func run() -> void:
	root.size=Vector2i(1440,900)
	Input.emulate_mouse_from_touch=true
	board=BoardUnderTest.new()
	board.feedback.free()
	board.feedback=QuietAudio.new()
	var save := "user://equipment-outside-%d" % Time.get_ticks_usec()
	board.slot_root=save.path_join("slots")
	board.options_path=save.path_join("options.json")
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	check(board.data_error==OK,"locked Board catalog")
	if board.data_error!=OK:
		finish()
		return
	board.start_new()
	check(board._source_equipment_outside!=null,"locked gameplay enables raw equipment observer by default")
	board.set_process(false)
	clear_cards()
	var wearer := spawn("Villager",Vector2(-1,2))
	var gear := spawn("Sword",Vector2(-4,2))
	await settle_views()
	check(board.session.equipment.equip(wearer,gear),"actual equipped card")
	await settle_views()
	var panel := panel_point(wearer)
	var gear_at := reachable(gear)
	var empty := Vector2(620,200)
	var hit: Dictionary = board._pick_target(empty)
	check(panel.is_finite() and gear_at.is_finite() and int(hit.panel_owner)<0 and int(hit.card_id)<0,
		"tested positions are panel, equipment and non-card ray respectively")
	if not panel.is_finite() or not gear_at.is_finite():
		finish()
		return
	var hud := StopSurface.new()
	hud.size=Vector2(1440,900)
	hud.mouse_filter=Control.MOUSE_FILTER_STOP
	board.hud.add_child(hud)
	hud.move_to_front()
	await process_frame
	await mouse(true,panel)
	check(hud.pressed>0 and board.equipment_display.is_expanded(wearer) and not board._has_card_drag(),
		"GUI consumes physical press but exact physics panel preserves itself")
	await mouse(false,panel)
	await touch(0,true,gear_at)
	check(board.equipment_display.is_expanded(wearer) and board.session.equipment.owners.has(gear),
		"GUI consumes primary touch; physics equipment preserves panel without initiating drag")
	await touch(0,false,gear_at)
	# Queue actual press at the empty ray then move before Update. The source
	# reads the shared pointer at Update, not the old event's screen position.
	edge(0,true,empty)
	var motion := InputEventScreenDrag.new()
	motion.index=0
	motion.position=root.get_final_transform()*panel
	motion.relative=panel-empty
	Input.parse_input_event(motion)
	Input.flush_buffered_events()
	board._advance_running_frame(0)
	check(board.equipment_display.is_expanded(wearer),"one frame uses the latest shared position rather than press position")
	await touch(1,true,empty)
	check(board.equipment_display.is_expanded(wearer),"secondary touch does not become a raw primary press")
	await touch(0,false,panel)
	await touch(1,false,empty)
	check(board.equipment_display.is_expanded(wearer),"releases and orphan retirement do not close panels")
	await touch(0,true,empty)
	check(not board.equipment_display.is_expanded(wearer),"GUI-consumed primary press outside closes panel via physics")
	await touch(0,false,empty)
	check(board.equipment_display.click_panel(wearer),"reopen through its normal registered owner")
	await mouse(true,empty)
	check(not board.equipment_display.is_expanded(wearer),"GUI-consumed physical mouse outside also closes panel")
	await mouse(false,empty)
	hud.hide()
	await physics_frame
	await process_frame
	panel=panel_point(wearer)
	check(panel.is_finite() and int(board._pick_target(panel).card_id)==wearer,
		"real panel collider also carries the wearer card ID")
	await touch(0,true,panel)
	check(board._touch_panel_presses.has(0) and not board._has_card_drag(),
		"admitted panel touch is not a wearer Down")
	await touch(0,false,panel)
	check(board.equipment_display.is_expanded(wearer),"touch plus emulation toggles once")
	await physics_frame
	await process_frame
	panel=panel_point(wearer)
	await mouse(true,panel)
	check(board.pressed_panel==wearer and not board._has_card_drag(),
		"physical mouse still captures the real panel, not the card")
	await mouse(false,panel)
	check(not board.equipment_display.is_expanded(wearer),"physical mouse click toggles once")
	finish()


func finish() -> void:
	board.free()
	print("Source equipment raw outside press: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
