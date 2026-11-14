extends SceneTree
## Actual production root configuration. No content-scale reset or mock display.
const SourceCamera = preload("res://scripts/ui/source_camera.gd")
const SIZES := [Vector2i(1024,768),Vector2i(1280,800),Vector2i(1280,720),Vector2i(1200,600),Vector2i(800,1000),Vector2i(1364,1024),Vector2i(800,600)]
var checks := 0
var failures := 0
var rows: Array = []
var clicks := 0
func check(ok: bool, label: String) -> void:
 checks += 1
 if not ok: failures += 1; printerr("FAIL: ",label)
func _init(): call_deferred("run")
func vec(v: Vector2) -> Array: return [v.x,v.y]
func matrix(t: Transform2D) -> Array: return [vec(t.x),vec(t.y),vec(t.origin)]
func settle() -> void:
 for i in 6: await process_frame
func physical_rect(c: Control) -> Rect2:
 return root.get_final_transform() * c.get_global_transform_with_canvas() * Rect2(Vector2.ZERO,c.size)
func close(a: Vector2,b: Vector2,epsilon: float=.5) -> bool: return a.distance_to(b)<=epsilon
func click_physical(point: Vector2) -> void:
 var motion := InputEventMouseMotion.new();motion.position=point
 Input.parse_input_event(motion);Input.flush_buffered_events();await process_frame
 for down in [true,false]:
  var event:=InputEventMouseButton.new();event.position=point;event.button_index=MOUSE_BUTTON_LEFT;event.pressed=down
  Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
func run() -> void:
 check(ProjectSettings.get_setting("display/window/size/viewport_width")==1440 and root.content_scale_size==Vector2i(1440,900),"production project settings retained at engine startup")
 check(root.content_scale_mode==Window.CONTENT_SCALE_MODE_CANVAS_ITEMS,"actual root canvas_items startup mode")
 check(root.min_size.x<=1024 and root.min_size.y<=768,"existing minimum does not block source serialized 1024x768 mode")
 var scene:=Node3D.new();root.add_child(scene)
 var camera:=Camera3D.new();scene.add_child(camera);camera.current=true
 SourceCamera.apply(camera,{"cameras":[{"resolved_pose":true,"orthographic":0,"field_of_view":30,"fov_axis":0,"near":2,"far":40,"transform_chain":[{"m_LocalPosition":{"x":0,"y":10,"z":-1},"m_LocalRotation":{"x":.67559016,"y":0,"z":0,"w":.7372774},"m_LocalScale":{"x":1,"y":1,"z":1}}]}]})
 var background:=ColorRect.new();root.add_child(background);background.color=Color(.2,.4,.6);background.mouse_filter=Control.MOUSE_FILTER_IGNORE;background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
 var button:=Button.new();root.add_child(button);button.text="root input";button.size=Vector2(120,50);button.pressed.connect(func(): clicks+=1)
 var output_dir:=OS.get_environment("ROOT_VIEWPORT_CAPTURE_DIR")
 for size in SIZES:
  root.size=size;await settle()
  var transform:=root.get_final_transform()
  var visible:=root.get_visible_rect().size
  check(root.size==size,"requested actual window size "+str(size))
  check(close(transform.origin,Vector2.ZERO,.01),"root attached origin has no black-bar margin "+str(size))
  check(close(transform*visible,Vector2(size),.02),"root attached content covers entire physical window "+str(size))
  check(absf(transform.x.length()-transform.y.length())<.001,"only engine viewport integer rounding, no anisotropic stretch policy "+str(size))
  var row:={"size":vec(root.size),"visible":vec(visible),"final_transform":matrix(transform),"content_scale_size":vec(root.content_scale_size),"aspect":root.content_scale_aspect,"minimum":vec(root.min_size)}
  for world in [Vector3.ZERO,Vector3(1.2,0,.7),Vector3(-1.2,.1,-.7)]:
   var eye:Vector3=camera.global_transform.affine_inverse()*world
   var focal:=float(size.y)*.5/tan(deg_to_rad(15))
   var expected:=Vector2(float(size.x)*.5+focal*eye.x/-eye.z,float(size.y)*.5-focal*eye.y/-eye.z)
   var actual:=transform*camera.unproject_position(world)
   check(close(actual,expected,.25),"source full-window pinhole projection "+str(size)+" "+str(world))
  for fraction in [Vector2(.03,.03),Vector2(.97,.03),Vector2(.03,.97),Vector2(.97,.97),Vector2(.5,.5)]:
   var point: Vector2=Vector2(size)*fraction
   var local: Vector2=transform.affine_inverse()*point
   var f:=float(size.y)*.5/tan(deg_to_rad(15))
   var expected_ray:Vector3=camera.global_basis*Vector3((point.x-float(size.x)*.5)/f,-(point.y-float(size.y)*.5)/f,-1).normalized()
   check(camera.project_ray_normal(local).distance_to(expected_ray)<.0002,"physical corner ray uses source full-window aspect "+str(size)+" "+str(fraction))
  button.position=transform.affine_inverse()*(Vector2(size)*Vector2(.72,.72))-button.size*.5
  var old:=clicks
  await click_physical(Vector2(size)*Vector2(.72,.72))
  check(clicks==old+1,"native physical input reaches UI after root transform "+str(size))
  row["ui_clicks"]=clicks
  if DisplayServer.get_name()!="headless" and not output_dir.is_empty():
   await RenderingServer.frame_post_draw
   var picture:=root.get_texture().get_image()
   check(picture.get_size()==size,"actual render image dimensions "+str(size))
   for fraction in [Vector2(.01,.01),Vector2(.99,.01),Vector2(.01,.99),Vector2(.99,.99)]:
    var p:=Vector2i(Vector2(size-Vector2i.ONE)*fraction)
    var sample:=picture.get_pixelv(p)
    check(absf(sample.r-.2)<.01 and absf(sample.g-.4)<.01 and absf(sample.b-.6)<.01,"full-window sentinel pixels "+str(size))
   var path:=output_dir.path_join("root-%dx%d.png"%[size.x,size.y])
   check(picture.save_png(path)==OK,"private native PNG saved")
   row["png"]=path
  rows.append(row)
 button.queue_free();background.queue_free();scene.queue_free();await process_frame
 if FileAccess.file_exists("res://data/stackcraft.json"):
  await source_hud_checks()
 else: print("Root viewport private HUD branch SKIPPED: licensed data not present")
 print("ROOT_VIEWPORT_ROWS="+JSON.stringify(rows))
 print("Root viewport: %d/%d passed (%s; pixel captures only on native display)"%[checks-failures,checks,DisplayServer.get_name()])
 await create_timer(.3).timeout
 quit(1 if failures else 0)
func source_hud_checks() -> void:
 var board=load("res://scripts/ui/board.gd").new()
 board.options_path="user://root-viewport/options.json";board.slot_root="user://root-viewport/slots";board.legacy_paths.clear()
 # Do not change the display from this geometry suite. Native fullscreen option
 # round trips are a separate real-release acceptance step.
 board.options_apply_adapter=func(_plan): return {"ok":true,"capabilities":{},"warnings":[]}
 root.add_child(board);await settle();board.start_new();board.set_process(false)
 check(board.running,"actual source Main entered")
 for size in SIZES:
  root.size=size;await settle()
  var scale:=float(size.y)/1080.0
  var day:=physical_rect(board.day_clock)
  check(close(day.position,Vector2(30,30)*scale) and close(day.size,Vector2(300,50)*scale),"actual source DayClock rect "+str(size))
  check(absf(day.get_center().y-55*scale)<.25,"actual Day vertical center "+str(size))
  check(absf(physical_rect(board.journal_tabs).get_center().y-30*scale)<.25,"actual Quests/Recipes header center "+str(size))
  check(absf(physical_rect(board.detail_panel).end.x-size.x)<.25 and absf(physical_rect(board.detail_panel).size.y-size.y)<.25,"actual source right/full-height menu anchors "+str(size))
  check(absf(board.source_hud.size.x-float(size.x)*1080/size.y)<.2 and absf(board.source_hud.size.y-1080)<.01,"actual CanvasScaler logical extent "+str(size))
  for label in board.stat_labels:
   check(absf(physical_rect(label).get_center().y-55*scale)<=.55*scale+.05,"Stats center retains known half-logical-pixel HBox rounding "+str(size))
  var watermark:=physical_rect(board.watermark)
  check(absf(watermark.get_center().x-size.x*.5)<.25 and watermark.end.y<=size.y+.25,"watermark bottom-center anchors "+str(size))
  if DisplayServer.get_name()!="headless" and not OS.get_environment("ROOT_VIEWPORT_CAPTURE_DIR").is_empty():
   await RenderingServer.frame_post_draw
   var screenshot:=root.get_texture().get_image()
   check(screenshot.get_size()==size,"actual source Main image dimensions "+str(size))
   check(screenshot.save_png(OS.get_environment("ROOT_VIEWPORT_CAPTURE_DIR").path_join("main-%dx%d.png"%[size.x,size.y]))==OK,"private source Main diagnostic PNG saved")
  board.pause_overlay.show();await settle()
  for control in board.pause_controls:
   check(Rect2(Vector2.ZERO,Vector2(size)).grow(.5).encloses(physical_rect(control)),"source pause control fits "+str(size))
  board.pause_overlay.hide()
  board.options_panel.open();await settle()
  check(Rect2(Vector2.ZERO,Vector2(size)).grow(.5).encloses(physical_rect(board.options_panel.close_button)),"source options close remains reachable "+str(size))
  board.options_panel.request_close()
  await actual_card_input(board,size)
 board._show_title();await settle()
 for size in SIZES:
  root.size=size;await settle()
  var scale:=float(size.y)/1080.0
  check(absf(board.source_title.canvas.size.x-float(size.x)*1080/size.y)<.2,"actual Title height-matched logical width "+str(size))
  for control in [board.title_new_button,board.title_load_button,board.title_options_button,board.title_quit_button]:
   check(Rect2(Vector2.ZERO,Vector2(size)).grow(.5).encloses(physical_rect(control)),"source Title button fits "+str(size))
 if DisplayServer.get_name()!="headless" and not OS.get_environment("ROOT_VIEWPORT_CAPTURE_DIR").is_empty():
  # Native-only app-local display change, through production adapter/UI callback.
  # This does not set monitor resolution or change system settings.
  board.options_panel.adapter=board.native_options_adapter.apply
  board.options_panel.model.values.fullscreen="windowed"
  board.options_panel._apply_and_save("refresh")
  board.options_panel.open();await settle()
  for expected in [DisplayServer.WINDOW_MODE_FULLSCREEN,DisplayServer.WINDOW_MODE_WINDOWED]:
   check(not board.options_panel.buttons.fullscreen.disabled,"real native fullscreen control is available")
   await click_physical(physical_rect(board.options_panel.buttons.fullscreen).get_center())
   for frame in 30:await process_frame
   check(DisplayServer.window_get_mode()==expected,"production UI fullscreen/windowed round trip "+str(expected))
   var transform:=root.get_final_transform()
   check(close(transform.origin,Vector2.ZERO,.01) and close(transform*root.get_visible_rect().size,Vector2(root.size),.1),"actual window-mode round trip remains full viewport")
  board.options_panel.request_close()
 board.queue_free();await process_frame;await create_timer(.3).timeout

func physical_mouse(button:int,down:bool,point:Vector2)->void:
 var event:=InputEventMouseButton.new();event.button_index=button;event.pressed=down;event.position=point
 Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
func physical_motion(point:Vector2)->void:
 var event:=InputEventMouseMotion.new();event.position=point
 Input.parse_input_event(event);Input.flush_buffered_events();await process_frame
func actual_card_input(board,size:Vector2i)->void:
 # Explicit isolated fixture positions/quest unlock, NOT natural gameplay.
 # Real source card colliders, production picking and event route are retained.
 for id in board.session.cards.keys():board.session._remove_card(id)
 board.session.phase="playing";board.session.vendor_payments.clear()
 board.camera.position=Vector3(0,10,1);board.camera_motion.configure(board.camera.position)
 var id:int=board.session.spawn_card(board.catalog.find_by_name("Wood"),Vector2.ZERO,-1,{"refuse_attach":true})
 board._refresh();board.card_motion.reset();board._sync_views();board.views[id].position=Vector3(0,.06,0)
 await physics_frame;await process_frame
 var down:Vector2=root.get_final_transform()*board.camera.unproject_position(board.views[id].position)
 check(board._pick_target(root.get_final_transform().affine_inverse()*down).card_id==id,"actual source card collider ray "+str(size))
 await physical_motion(down);await physical_mouse(MOUSE_BUTTON_LEFT,true,down)
 check(board.dragging==id and board.session.drag.active(),"physical window press picks actual card "+str(size))
 var up:Vector2=root.get_final_transform()*board.camera.unproject_position(Vector3(-.8,0,0))
 await physical_motion(up);await physical_mouse(MOUSE_BUTTON_LEFT,false,up)
 check(board.dragging<0 and not board.session.drag.active(),"physical release clears held state "+str(size))
 check(board.session.cards.has(id) and board.session.cards[id].position.distance_to(Vector2(-.8,0))<.03,"actual physical drag reaches expected board-plane destination "+str(size))
 for quest in board.session.quest_tracker.definitions:board.session.quest_tracker.completed_ids[quest]=true
 board._refresh()
 for index in [0,1]:
  for card_id in board.session.cards.keys():board.session._remove_card(card_id)
  board.session.vendor_payments.clear();board._refresh()
  var zone:Dictionary=board.trade_zones[index]
  var destination:=Vector2(zone.center.x,zone.center.z)
  var start:=destination+Vector2(0,-1)
  var card_id:int=board.session.spawn_card(board.catalog.find_by_name("Wood" if index==0 else "Coin"),start,-1,{"refuse_attach":true})
  board._refresh();board.card_motion.reset();board._sync_views();board.views[card_id].position=Vector3(start.x,.06,-start.y)
  board.camera.position=Vector3(destination.x,10,-destination.y+1)
  board.camera_motion.configure(board.camera.position)
  await physics_frame;await process_frame
  down=root.get_final_transform()*board.camera.unproject_position(board.views[card_id].position)
  up=root.get_final_transform()*board.camera.unproject_position(Vector3(destination.x,0,-destination.y))
  check(board._pick_target(root.get_final_transform().affine_inverse()*down).card_id==card_id,"actual trade-payment card ray "+str(size)+" zone"+str(index))
  await physical_motion(down);await physical_mouse(MOUSE_BUTTON_LEFT,true,down)
  check(board.dragging==card_id,"physical trade drag starts "+str(size)+" zone"+str(index))
  await physical_motion(up);await physical_mouse(MOUSE_BUTTON_LEFT,false,up)
  check(not board.session.cards.has(card_id),"physical center drop consumed buyer/vendor card "+str(size)+" zone"+str(index))
  check(board.dragging<0 and not board.session.drag.active(),"trade releases hold exactly once")
 board.camera.position=Vector3(0,10,1);board.camera_motion.configure(board.camera.position)
