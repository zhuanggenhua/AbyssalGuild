extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_name: String) -> bool: return false
	func play_music() -> bool: return false
var failures := 0
var checks := 0
func _initialize() -> void: call_deferred("_run")
func check(ok: bool, title: String) -> void:
	checks+=1
	if not ok:
		failures+=1
		printerr("FAIL ",title)
func mouse(index: MouseButton,down: bool,at: Vector2) -> void:
	var e:=InputEventMouseButton.new()
	e.position=at; e.global_position=at; e.pressed=down; e.button_index=index
	root.push_input(e,true)
func move(at: Vector2) -> void:
	var e:=InputEventMouseMotion.new()
	e.position=at; e.global_position=at; e.relative=Vector2.ONE
	root.push_input(e,true)

func frame() -> Image:
	await process_frame
	await RenderingServer.frame_post_draw
	return root.get_texture().get_image()
func compare_perimeter(a: Image,b: Image) -> int:
	if a.get_size()!=b.get_size(): return -1
	var w:=a.get_width()
	var h:=a.get_height()
	var diff:=0
	for x in w:
		for y in [1,2,h-3,h-2]:
			if a.get_pixel(x,y)!=b.get_pixel(x,y): diff+=1
	for y in h:
		for x in [1,2,w-3,w-2]:
			if a.get_pixel(x,y)!=b.get_pixel(x,y): diff+=1
	return diff
func verify(b: Board,aspect: Vector2i,phase: String) -> Image:
	var title = b.source_title
	var tag:=str(aspect)+" "+phase
	var id: String=title.layout.resolve("Background")
	var art:=title.surfaces.get(id) as TextureRect
	check(art!=null and art.texture!=null and art.texture.get_image().detect_alpha()==Image.ALPHA_NONE,tag+" source RGB artwork")
	if art==null: return null
	var bmp:=art.texture.get_image()
	var normal:=await frame()
	check(normal.get_size()==aspect,tag+" real framebuffer dimensions "+str(normal.get_size()))
	var saved:=b.world_environment.background_color
	b.world_environment.background_color=Color(1,0,1)
	var sentinel:=await frame()
	b.world_environment.background_color=saved
	check(compare_perimeter(normal,sentinel)==0,tag+" perimeter masks world clear")
	# Use points on all four edges away from the serialized right-side menu.
	var max_distance:=0.0
	for sample: Vector2 in [Vector2(.55,.05),Vector2(.95,.05),Vector2(.95,.5),Vector2(.55,.94),Vector2(.95,.94),Vector2(.66,.52)]:
		var live_pos:=Vector2i(Vector2(normal.get_size())*sample)
		var art_pos:=Vector2i(Vector2(bmp.get_size())*sample)
		var rendered:=normal.get_pixelv(live_pos)
		var source:=bmp.get_pixelv(art_pos)
		max_distance=maxf(max_distance,Vector3(rendered.r-source.r,rendered.g-source.g,rendered.b-source.b).length())
	check(max_distance<.16,tag+" source-stretched samples, max RGB diff %.3f"%max_distance)
	print("Title framebuffer ",tag," maximum sampled source color deviation ",max_distance)
	return normal
func verify_captions(b: Board, phase: String) -> void:
	var buttons: Array[Button]=[b.title_new_button,b.title_load_button,b.title_options_button,b.title_quit_button]
	var labels:=["New Game","Load Game","Game Options","Quit Game"]
	move(Vector2(root.get_visible_rect().size.x*.85,20))
	var normal:=await frame()
	var bounds: Array[Rect2i]=[]
	for button in buttons:
		var transform:=root.get_final_transform()*button.get_global_transform_with_canvas()
		bounds.append(Rect2i(Rect2(transform.origin,transform.basis_xform(button.size))))
		button.hide()
	var empty:=await frame()
	for button in buttons: button.show()
	for index in buttons.size():
		var button:=buttons[index]
		var box:=bounds[index].intersection(Rect2i(Vector2i.ZERO,normal.get_size()))
		var ink:=AABB()
		var count:=0
		for y in range(box.position.y,box.end.y):
			for x in range(box.position.x,box.end.x):
				if normal.get_pixel(x,y)!=empty.get_pixel(x,y):
					var pt:=Vector3(x,y,0)
					ink=AABB(pt,Vector3.ZERO) if count==0 else ink.expand(pt)
					count+=1
		var x_offset:=ink.position.x-box.position.x
		var y_offset:=ink.position.y+ink.size.y*.5-box.position.y
		check(button.text==labels[index] and button.alignment==HORIZONTAL_ALIGNMENT_LEFT and count>20
			and x_offset>=0 and x_offset<=maxf(4,box.size.x*.045)
			and absf(y_offset-box.size.y*.5)<box.size.y*.25,
			"%s %s left ink offset %.2f mid-row %.2f (area %s, pixel count %d)"%[
				phase,labels[index],x_offset,y_offset,box,count])
	# Exercise hover presentation through the native hover signal. The real
	# viewport click independently verifies pointer hit geometry and routing.
	var option:=b.title_options_button
	var target:=option.get_global_transform_with_canvas()*(option.size*.5)
	var quiet:=await frame()
	option.mouse_entered.emit()
	var hover:=await frame()
	var box:=bounds[2].grow(1).intersection(Rect2i(Vector2i.ZERO,quiet.get_size()))
	var offset:=box.size.x
	var ink_count:=0
	for y in range(box.position.y,mini(box.end.y+6,quiet.get_height())):
		for x in range(box.position.x,box.end.x):
			if quiet.get_pixel(x,y)!=hover.get_pixel(x,y):
				offset=mini(offset,x-box.position.x)
				ink_count+=1
	check(option.underline and ink_count>20 and offset<=4,
		phase+" hovered underline begins at left edge (%d, %d, active %s)"%[ink_count,offset,option.underline])
	option.mouse_exited.emit()
	check(not option.underline,phase+" exit signal resets underline")
	move(target)
	mouse(MOUSE_BUTTON_LEFT,true,target); mouse(MOUSE_BUTTON_LEFT,false,target)
	await process_frame
	check(b.options_panel.visible,phase+" actual Game Options row still dispatches")
	b.options_panel.request_close()
	move(Vector2(root.get_visible_rect().size.x*.85,20))
	await process_frame
	check(not option.underline and not b.options_panel.visible,phase+" options close and hover clears")

func _run() -> void:
	if DisplayServer.get_name()=="headless" or not FileAccess.file_exists("res://assets/imported/manifest.json") 			or not FileAccess.file_exists("res://data/stackcraft.json"):
		print("SKIP: private Title data and an actual rendered window are required.")
		quit()
		return
	for aspect in [Vector2i(1152,648),Vector2i(960,720)]:
		root.size=aspect
		var b:=Board.new()
		b.feedback.free(); b.feedback=SilentFeedback.new()
		var path:="user://sc-title-frame-%d"%Time.get_ticks_usec()
		DirAccess.make_dir_recursive_absolute(path)
		b.slot_root=path+"/slots"; b.options_path=path+"/options.json"; b.legacy_paths.clear()
		root.add_child(b)
		await process_frame
		DisplayServer.window_set_mode(DisplayServer.WINDOW_MODE_WINDOWED)
		for i in 3: await process_frame
		root.size=aspect
		for i in 5: await process_frame
		b.set_process(false)
		check(b.data_error==OK and b.source_title!=null,"licensed source title mounts")
		if b.source_title==null:
			b.queue_free(); await process_frame; continue
		var cold:=await verify(b,aspect,"cold")
		await verify_captions(b,str(aspect)+" cold")
		b.start_new(); b.set_process(false)
		b.vendor_unlock.cancel()
		var e:=InputEventKey.new()
		e.keycode=KEY_ESCAPE; e.pressed=true; root.push_input(e,true)
		e=InputEventKey.new()
		e.keycode=KEY_ESCAPE; e.pressed=false; root.push_input(e,true)
		await process_frame
		var button: Button=b.pause_controls[2]
		var center:=button.get_global_transform_with_canvas()*(button.size*.5)
		check(b.pause_overlay.visible and b._source_pause_title_open(),"actual Escape opens source Pause")
		move(center)
		mouse(MOUSE_BUTTON_LEFT,true,center); mouse(MOUSE_BUTTON_LEFT,false,center)
		b._process(1.0); b._process(1.0)
		check(not b.running and b.title_panel.visible and not b.scene_transition.active(),"actual Title button leaves gameplay")
		var returned:=await verify(b,aspect,"returned")
		await verify_captions(b,str(aspect)+" returned")
		check(cold!=null and returned!=null and compare_perimeter(cold,returned)==0,"cold and returned perimeter equality")
		b.queue_free()
		await process_frame
	print("Source Title framebuffer: ",checks-failures,"/",checks)
	quit(int(failures!=0))
