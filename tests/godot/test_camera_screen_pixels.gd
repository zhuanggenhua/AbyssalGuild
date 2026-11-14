extends SceneTree
## Native Window event routing, synthetic empty board. No desktop input/GPU claim.
class QuietAudio extends "res://scripts/ui/audio_feedback.gd":
 func play_event(_event:String)->bool:return false
 func play_music()->bool:return false
class EmptyBoard extends "res://scripts/ui/board.gd":
 func _pick_target(_point:Vector2)->Dictionary:return {"card_id":-1,"panel_owner":-1,"trade_zone_index":-1}
var checks:=0
var failures:=0
var board:EmptyBoard
func check(ok:bool,label:String)->void:
 checks+=1
 if not ok:failures+=1;printerr("FAIL: ",label)
func _init():call_deferred("run")
func deliver(event:InputEvent)->void:
 Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
func mouse(button:int,pressed:bool,point:Vector2)->void:
 var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=pressed;event.position=point
 await deliver(event)
func motion(point:Vector2)->void:
 var event:=InputEventMouseMotion.new();event.position=point
 await deliver(event)
func reset()->void:
 board.panning=false;board.camera_pointer.known=false
 board.camera.position=Vector3(0,10,1)
 board.camera_motion.configure(board.camera.position)
 board.session.phase="playing"
func run()->void:
 board=EmptyBoard.new();board.feedback.free();board.feedback=QuietAudio.new()
 board.options_path="user://camera-pixels/options.json";board.slot_root="user://camera-pixels/slots";board.legacy_paths.clear()
 board.options_apply_adapter=func(_plan):return {"ok":true,"capabilities":{},"warnings":[]}
 root.add_child(board);await process_frame;board.set_process(false)
 board.catalog.configure({});board.session.configure(board.catalog);board.running=true;board.title_panel.hide();board.hud.show();board._refresh()
 for size in [Vector2i(1024,768),Vector2i(1280,800),Vector2i(1280,720),Vector2i(1200,600),Vector2i(800,1000)]:
  root.size=size
  for i in 4:await process_frame
  var p:=Vector2(size)*.4
  for button in [MOUSE_BUTTON_MIDDLE,MOUSE_BUTTON_LEFT]:
   reset();var initial:Vector3=board.camera_motion.target
   await mouse(button,true,p);await motion(p+Vector2(20,10))
   check(board.panning,"press admitted "+str(size)+" button"+str(button))
   check(board.camera_motion.target.is_equal_approx(initial+Vector3(-.2,0,-.1)),"20x10 physical pixels give source pan displacement "+str(size)+" button"+str(button))
   await mouse(button,false,p+Vector2(20,10))
   check(not board.panning,"physical release ends pan")
  reset();var initial:Vector3=board.camera_motion.target
  await mouse(MOUSE_BUTTON_MIDDLE,true,p)
  board.session.phase="feeding";await motion(p+Vector2(30,15))
  check(board.camera_motion.target==initial,"lock suppresses pan")
  board.session.phase="playing";board._update_camera_motion(.016)
  check(board.camera_motion.target.is_equal_approx(initial+Vector3(-.3,0,-.15)),"unlock accumulated delta uses screen pixels "+str(size))
  await mouse(MOUSE_BUTTON_MIDDLE,false,p+Vector2(30,15))
 # Stable physical pointer does not jump when root scale changes during pan.
 root.size=Vector2i(1280,800);await process_frame;reset()
 var fixed:=Vector2(400,350);var initial:Vector3=board.camera_motion.target
 await mouse(MOUSE_BUTTON_MIDDLE,true,fixed)
 root.size=Vector2i(1024,768)
 for i in 4:await process_frame
 board._update_camera_motion(.016)
 check(board.camera_motion.target==initial,"resize without pointer event does not synthesize camera pan")
 await motion(fixed+Vector2(20,0))
 check(board.camera_motion.target.is_equal_approx(initial+Vector3(-.2,0,0)),"first motion after resize retains physical origin")
 await mouse(MOUSE_BUTTON_MIDDLE,false,fixed+Vector2(20,0))
 # Primary touchscreen pixels use the same conversion, not touch-emulated double input.
 Input.emulate_mouse_from_touch=true;reset();initial=board.camera_motion.target
 var down:=InputEventScreenTouch.new();down.index=2;down.pressed=true;down.position=fixed;await deliver(down)
 var drag:=InputEventScreenDrag.new();drag.index=2;drag.position=fixed+Vector2(20,10);await deliver(drag)
 check(board.camera_motion.target.is_equal_approx(initial+Vector3(-.2,0,-.1)),"primary touch pan has physical pixel units exactly once")
 down.pressed=false;down.position=drag.position;await deliver(down)
 check(not board.panning,"primary touch release ends camera pan")
 # Scaled multi-contact orphan retains primary physical position across resize.
 reset();initial=board.camera_motion.target
 down.pressed=true;down.position=fixed;await deliver(down)
 drag.position=fixed+Vector2(20,10);await deliver(drag)
 var second:=InputEventScreenTouch.new();second.index=5;second.pressed=true;second.position=fixed+Vector2(50,0);await deliver(second)
 var secondary_drag:=InputEventScreenDrag.new();secondary_drag.index=5;secondary_drag.position=fixed+Vector2(70,0);await deliver(secondary_drag)
 check(board.camera_motion.target.is_equal_approx(initial+Vector3(-.2,0,-.1)),"scaled secondary motion never replaces primary")
 down.pressed=false;down.position=fixed+Vector2(30,15);await deliver(down)
 check(board.panning and board.camera_pointer.orphan,"scaled primary release with secondary becomes orphan")
 check(board.camera_motion.target.is_equal_approx(initial+Vector3(-.3,0,-.15)),"orphan-forming end applies physical primary delta once")
 var frozen:Vector3=board.camera_motion.target
 root.size=Vector2i(1280,720)
 for i in 4:await process_frame
 board._update_camera_motion(.016)
 check(board.camera_motion.target==frozen,"resize leaves frozen physical orphan unchanged")
 secondary_drag.position=fixed+Vector2(90,0);await deliver(secondary_drag)
 check(board.camera_motion.target==frozen,"secondary after resize cannot move orphan")
 second.pressed=false;second.position=secondary_drag.position;await deliver(second)
 check(not board.panning and board.camera_motion.target==frozen,"last scaled secondary releases without displacement")
 board._show_title();board.queue_free();await process_frame;await create_timer(.3).timeout
 print("Camera screen pixels: %d/%d passed"%[checks-failures,checks])
 quit(1 if failures else 0)
