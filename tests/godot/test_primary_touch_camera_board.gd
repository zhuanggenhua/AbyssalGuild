extends SceneTree
## Frame-separated injected native events, not physical touchscreen/GPU acceptance.
class QuietAudio extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_event:String)->bool:return false
	func play_music()->bool:return false
class TraceBoard extends "res://scripts/ui/board.gd":
	var input_types:Array=[]
	func _input(event:InputEvent)->void:
		input_types.append([event.get_class(),event.device])
		super._input(event)
var checks := 0
var failures := 0
var board:TraceBoard
var start := Vector2(700,450)
func check(value:bool,label:String)->void:
	checks+=1
	if not value:failures+=1;printerr("FAIL: ",label)
func _init()->void:call_deferred("run")
func touch(index:int,down:bool,point:Vector2,canceled:bool=false)->void:
	var event:=InputEventScreenTouch.new();event.index=index;event.pressed=down;event.position=point;event.canceled=canceled
	await deliver(event)
func drag(index:int,point:Vector2)->void:
	var event:=InputEventScreenDrag.new();event.index=index;event.position=point;event.relative=Vector2(10,0)
	await deliver(event)
func mouse(button:int,down:bool,point:Vector2)->void:
	var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=down;event.position=point;event.device=0
	await deliver(event)
func deliver(event:InputEvent)->void:
	Input.parse_input_event(event);Input.flush_buffered_events()
	await process_frame
	board._update_camera_motion(1.0/60)
func run()->void:
	Input.emulate_mouse_from_touch=true
	root.size=Vector2i(1440,900)
	board=TraceBoard.new();board.feedback.free();board.feedback=QuietAudio.new()
	var path:="user://primary-touch-%d"%Time.get_ticks_usec()
	board.slot_root=path+"/slots";board.options_path=path+"/options.json";board.legacy_paths.clear()
	root.add_child(board);await process_frame
	check(board.data_error==OK,"private source catalog available")
	board.start_new();board.set_process(false)
	for id in board.session.cards.keys():board.session._remove_card(id)
	board._sync_views();await physics_frame
	check(board._pick_target(start).card_id<0 and board._pick_target(start).panel_owner<0 and board._pick_target(start).trade_zone_index<0,"actual blank-board ray has no card, panel or trade hit")
	var initial:Vector3=board.camera_motion.target
	board.input_types.clear()
	await touch(3,true,start)
	check(board.input_types.slice(0,2)==[["InputEventMouseButton",-1],["InputEventScreenTouch",0]],"installed Godot delivers emulated mouse before touch")
	check(board.panning and board.dragging==-1,"first blank touch admits camera only")
	await drag(3,start+Vector2(10,0))
	check(board.camera_motion.target.is_equal_approx(initial+Vector3(-.1,0,0)),"primary drag changes target once with source pan speed")
	await touch(5,true,start+Vector2(50,0));await drag(5,start+Vector2(70,0))
	check(board.camera_motion.target.is_equal_approx(initial+Vector3(-.1,0,0)),"secondary contact movement does not move shared primary")
	await touch(3,false,start+Vector2(20,0))
	check(board.panning,"first-up with secondary retained keeps source camera drag active")
	check(board.camera_motion.target.is_equal_approx(initial+Vector3(-.2,0,0)),"orphan-forming end applies primary final delta exactly once")
	var frozen:Vector3=board.camera_motion.target
	await drag(5,start+Vector2(80,0))
	check(board.panning and board.camera_motion.target==frozen,"secondary movement cannot move orphan")
	await touch(7,true,start+Vector2(90,0));await drag(7,start+Vector2(100,0))
	check(board.panning and board.camera_motion.target==frozen and board.camera_drag_origin==start+Vector2(20,0),"new third touch and its emulated mouse cannot restart orphan pan")
	await touch(5,false,start+Vector2(80,0))
	check(board.panning and board.camera_motion.target==frozen,"non-final secondary release retains orphan")
	await touch(7,false,start+Vector2(100,0),true)
	check(not board.panning and board.camera_motion.target==frozen,"last canceled secondary ends primary without position jump")
	await touch(1,true,start);await drag(1,start+Vector2(10,0))
	check(board.panning,"fresh contact after all-up starts another pan")
	frozen=board.camera_motion.target
	await touch(1,false,start+Vector2(20,0))
	check(not board.panning and board.camera_motion.target==frozen,"single-primary release stops before its final displacement")
	await touch(1,true,start);await touch(2,true,start+Vector2(40,0))
	await touch(1,false,start+Vector2(10,0),true)
	check(board.panning,"first-contact cancellation with another held keeps orphan pressed")
	await mouse(MOUSE_BUTTON_LEFT,false,start)
	check(not board.panning,"real left release still stops touch-originated camera pan")
	await mouse(MOUSE_BUTTON_MIDDLE,true,start)
	check(board.panning,"real middle press remains independent of orphan")
	await mouse(MOUSE_BUTTON_MIDDLE,false,start)
	check(not board.panning,"real middle release remains independent of orphan")
	await touch(2,false,start+Vector2(40,0))
	await touch(1,true,start);await touch(2,true,start+Vector2(40,0))
	board.session.phase="feeding"
	frozen=board.camera_motion.target
	await touch(1,false,start+Vector2(10,0));await touch(2,false,start+Vector2(40,0))
	check(board.panning and board.camera_motion.target==frozen,"InputManager lock skips release and movement without resetting held pan")
	board.session.phase="playing";board._update_camera_motion(1.0/60)
	check(board.panning and board.camera_drag_origin==start+Vector2(10,0),"unlock samples retained primary position without replaying locked release")
	await mouse(MOUSE_BUTTON_LEFT,false,start)
	check(not board.panning,"new unlocked real release ends retained lock-time pan")
	# Preserve existing native GUI admission. Do not invent a touch raycaster.
	var panel := Control.new();panel.position=Vector2(120,120);panel.size=Vector2(100,100);panel.mouse_filter=Control.MOUSE_FILTER_STOP
	board.hud.add_child(panel);panel.move_to_front();await process_frame
	await touch(1,true,Vector2(150,150))
	check(not board.panning,"native GUI-consumed first touch does not admit camera pan")
	await touch(2,true,start);await touch(1,false,Vector2(150,150));await touch(3,true,start+Vector2(80,0))
	check(not board.panning,"secondary and new-third blank touches cannot admit a GUI-origin orphan")
	await touch(2,false,start);await touch(3,false,start+Vector2(80,0))
	check(not board.panning,"GUI-origin orphan finishes without creating a camera drag")
	panel.queue_free()
	check(board.session.cards.is_empty() and not board.session.drag.active() and board.dragging==-1,"camera trace never creates cards or held stacks")
	board._show_title();board.queue_free();await process_frame;await create_timer(.2).timeout
	print("Primary touch camera board: %d/%d passed"%[checks-failures,checks])
	quit(1 if failures else 0)
