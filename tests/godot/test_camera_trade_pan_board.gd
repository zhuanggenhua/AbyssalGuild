extends SceneTree
## Live source trade collider and Godot viewport event integration.
## No synthetic hit lookup; touches/physical mouse hardware are outside this fixture.
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_event: String) -> bool: return false
	func play_music() -> bool: return false

const Board := preload("res://scripts/ui/board.gd")
var board: Board
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL: ",label)

func press(button: MouseButton, down: bool, point: Vector2) -> void:
	var event := InputEventMouseButton.new()
	event.button_index=button
	event.pressed=down
	# Feed the Window route with window pixels, as the physical backend does.
	event.position=root.get_final_transform()*point
	root.push_input(event)
	board._update_camera_motion(.016)

func trade_point(index: int) -> Vector2:
	var receiver = board.trade_views[index]
	var body: StaticBody3D = receiver.pick_body
	var shape := body.get_child(0) as CollisionShape3D
	var center := shape.global_position
	# Scroll/camera affordance is tested on the actual original boxes even
	# if a default camera framing hides distant trade zones.
	board.camera.global_position=center+board.camera.global_basis.z*11
	board.camera_motion.configure(board.camera.position)
	board._clamp_camera()
	return board.camera.unproject_position(center)

func run() -> void:
	root.size=Vector2i(1280,800)
	board=Board.new()
	board.feedback.free()
	board.feedback=SilentFeedback.new()
	var path := "user://camera-trade-pan-%d"%Time.get_ticks_usec()
	board.options_path=path+"/options.json"
	board.slot_root=path+"/slots"
	board.legacy_paths.clear()
	board.options_apply_adapter=func(_plan): return {"ok":true,"capabilities":{},"warnings":[]}
	root.add_child(board)
	await process_frame
	check(board.data_error==OK,"locked data loaded")
	if board.data_error!=OK: finish(); return
	board.start_new()
	board.set_process(false)
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board.session.phase="playing"
	board._refresh()
	await physics_frame
	check(board.trade_views.has(0) and board.trade_views.has(1),"Main actual buyer and vendor instantiated")
	if not board.trade_views.has(0) or not board.trade_views.has(1): finish(); return
	for index in [0,1]:
		var point := trade_point(index)
		var receiver = board.trade_views[index]
		var hit: Dictionary = board._pick_target(point)
		check(int(hit.trade_zone_index)==index and int(hit.card_id)==-1 and not board._hud_blocks_panel_click(board.hud,point),
			"real trade ray owns this point independently of cards and HUD: %d"%index)
		check(bool(receiver.zone_snapshot.active)==(index==0) and receiver.pick_body.collision_layer==1,
			"locked vendor remains a collider without activation: %d"%index)
		var target: Vector3 = board.camera_motion.target
		press(MOUSE_BUTTON_LEFT,true,point)
		check(not board.panning and board.camera_motion.target==target,"left pan is blocked by actual trade ray: %d"%index)
		press(MOUSE_BUTTON_LEFT,false,point)
		press(MOUSE_BUTTON_MIDDLE,true,point)
		check(board.panning,"middle bypasses that real blocker: %d"%index)
		press(MOUSE_BUTTON_MIDDLE,false,point)
		check(not board.panning,"middle release ends pan: %d"%index)
	var hidden_point := trade_point(1)
	board.trade_views[1].hide()
	await physics_frame
	await physics_frame
	check(int(board._pick_target(hidden_point).trade_zone_index)==-1
		and not board._hud_blocks_panel_click(board.hud,hidden_point),"no ray coverage when collider is unavailable")
	press(MOUSE_BUTTON_LEFT,true,hidden_point)
	check(board.panning,"same unobstructed point now admits left pan")
	press(MOUSE_BUTTON_LEFT,false,hidden_point)
	finish()

func finish() -> void:
	board._show_title()
	board.queue_free()
	await process_frame
	await create_timer(.3).timeout
	print("Camera trade pan board: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
