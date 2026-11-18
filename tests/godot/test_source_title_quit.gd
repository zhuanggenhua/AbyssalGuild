extends SceneTree
## Native viewport routing; geometry checks are not Unity pixel/baseline acceptance.
const Board = preload("res://scripts/ui/board.gd")
var checks := 0
var failures := 0
var quits := 0
func _init(): call_deferred("run")
func check(value: bool, label: String):
	checks += 1
	if not value: failures += 1; printerr("FAIL: ",label)
func pointer(index: int, down: bool, at: Vector2):
	var motion := InputEventMouseMotion.new()
	motion.position=at;motion.global_position=at
	root.push_input(motion,true)
	var e := InputEventMouseButton.new()
	e.button_index=index;e.pressed=down;e.position=at;e.global_position=at
	root.push_input(e,true)
func click(index: int, button: Control):
	var at := button.get_global_rect().get_center()
	pointer(index,true,at)
	pointer(index,false,at)
func key(code: Key):
	var e := InputEventKey.new()
	e.keycode=code;e.pressed=true
	root.push_input(e,true)
	e=InputEventKey.new();e.keycode=code;e.pressed=false
	root.push_input(e,true)
func make_board():
	var b=Board.new()
	var path="user://source-title-quit-%d"%Time.get_ticks_usec()
	DirAccess.make_dir_recursive_absolute(path)
	b.slot_root=path+"/slots";b.options_path=path+"/options.json";b.legacy_paths.clear()
	b.options_apply_adapter=func(_p):return {"ok":true,"capabilities":{},"warnings":[]}
	b.quit_callback=func():quits+=1
	root.add_child(b)
	await process_frame
	b.set_process(false)
	return b
func run():
	root.gui_embed_subwindows=true
	root.size=Vector2i(1440,900)
	var b=await make_board()
	var source=b.get("source_title_quit")
	if source==null:
		b._request_title_quit()
		check(b.quit_dialog.visible and b.pending_quit=="title","no source keeps native confirmation")
		key(KEY_ESCAPE);await process_frame
		check(not b.quit_dialog.visible and quits==0,"source-free native Escape decline preserved")
		print("Source Title Quit: SKIP (locked catalog absent); fallback checks: %d"%checks)
		b.queue_free();await process_frame
		quit(1 if failures else 0)
		return
	check(not source.visible and not b.quit_dialog.visible,"source modal starts inactive")
	check(source.no_button.button_mask==7 and source.yes_button.button_mask==7,"source modal accepts all three mouse buttons")
	check(source.no_button.focus_mode==Control.FOCUS_NONE and source.yes_button.focus_mode==Control.FOCUS_NONE,"no invented keyboard selection")
	for index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
		click(index,b.title_quit_button);await process_frame
		check(source.visible and not b.quit_dialog.visible and b.pending_quit=="source_title","original modal replaces OS window")
		var at=source.no_button.get_global_rect().get_center()
		pointer(index,true,at);check(source.visible,"No requires release")
		pointer(index,false,at);await process_frame
		check(not source.visible and b.pending_quit.is_empty() and quits==0,"No closes without quitting")
	b._request_title_quit();await process_frame
	for code in [KEY_ESCAPE,KEY_ENTER,KEY_SPACE]:
		key(code);await process_frame
		check(source.visible and quits==0,"source has no keyboard cancel or submit")
	var joy:=InputEventJoypadButton.new()
	joy.button_index=JOY_BUTTON_B;joy.pressed=true;root.push_input(joy,true);await process_frame
	check(source.visible and quits==0,"source has no gamepad East handler")
	pointer(MOUSE_BUTTON_LEFT,true,Vector2(5,5));pointer(MOUSE_BUTTON_LEFT,false,Vector2(5,5));await process_frame
	check(source.visible and quits==0,"background is blocking, not a dismiss action")
	var at=source.yes_button.get_global_rect().get_center()
	pointer(MOUSE_BUTTON_LEFT,true,at);pointer(MOUSE_BUTTON_LEFT,false,Vector2(5,5));await process_frame
	check(source.visible and quits==0,"captured Yes release outside cannot quit")
	b._request_title_quit()
	b._notification(Node.NOTIFICATION_WM_CLOSE_REQUEST)
	check(source.visible and quits==0,"active modal prevents repeated entry or window-close bypass")
	for width in [1440,620]:
		root.size=Vector2i(width,900);await process_frame;await process_frame
		var r: Rect2=source.panel.get_global_rect()
		var viewport: Rect2=source.get_global_rect()
		check(r.get_center().distance_to(viewport.get_center())<1.0,"preferred panel remains viewport centered")
		check(absf(r.size.x-500.0*viewport.size.y/1080.0)<1.0,"panel scales from source 500 and MatchHeight")
		check(absf(source.no_button.size.x-100)<.1 and absf(source.no_button.size.y-50)<.1,"authored logical button extent")
	root.size=Vector2i(1440,900);await process_frame
	click(MOUSE_BUTTON_RIGHT,source.no_button);await process_frame
	b.archive_dialog.popup_centered();await process_frame
	b._request_title_quit()
	check(not source.visible and b.archive_dialog.visible,"archive modal blocks Title Quit")
	b.archive_dialog.hide();await process_frame
	b._open_options();b._request_title_quit()
	check(b.options_panel.visible and not source.visible,"options blocks Title Quit")
	b.options_panel.request_close();await process_frame
	b._request_title_quit();await process_frame
	var sequence: Array=[]
	b.quit_callback=func():quits+=1;sequence.append("quit")
	source.yes_button.play_click=func():sequence.append("click")
	# A source-owned fade cannot admit this modal's captured release.
	at=source.yes_button.get_global_rect().get_center()
	pointer(MOUSE_BUTTON_LEFT,true,at)
	b.scene_transition.begin(func():pass);b._sync_scene_fader()
	pointer(MOUSE_BUTTON_LEFT,false,at);await process_frame
	check(quits==0 and source.visible,"fader rejects an already captured Yes release")
	b.scene_transition.cancel();b._sync_scene_fader()
	click(MOUSE_BUTTON_MIDDLE,source.yes_button);await process_frame
	check(sequence==["quit","click"],"Yes invokes action before exactly one click sound")
	check(quits==1 and b.quit_dispatched and not source.visible and b.pending_quit.is_empty(),"Yes invokes safe injected quit exactly once")
	b._confirm_quit();source.yes_button.pressed.emit();b._request_title_quit()
	check(quits==1 and not source.visible,"stale or duplicate confirmation never replays")
	b.queue_free();await process_frame
	print("Source Title Quit: %d/%d checks passed (native geometry, not pixel parity)"%[checks-failures,checks])
	quit(1 if failures else 0)
