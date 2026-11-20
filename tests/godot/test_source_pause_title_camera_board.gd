extends SceneTree
## 原暂停标题按钮 → 单次保存 → 旧相机淡出 → 新标题 → 同槽读取。
const Board = preload("res://scripts/ui/board.gd")
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_name: String) -> bool: return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")

func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func mouse(index: MouseButton, down: bool, pos: Vector2, factor := 1.0) -> void:
	var e := InputEventMouseButton.new()
	e.position = pos; e.global_position = pos; e.button_index = index; e.pressed = down; e.factor = factor
	root.push_input(e,true)

func move(pos: Vector2) -> void:
	var e := InputEventMouseMotion.new()
	e.position = pos; e.global_position = pos
	root.push_input(e,true)

func center(button: Control) -> Vector2:
	return button.get_global_transform_with_canvas() * (button.size*.5)

func click(index: MouseButton, pos: Vector2) -> void:
	move(pos)
	mouse(index,true,pos)
	mouse(index,false,pos)

func pause() -> void:
	var e := InputEventKey.new()
	e.keycode = KEY_ESCAPE; e.pressed = true
	root.push_input(e,true)
	e = InputEventKey.new()
	e.keycode = KEY_ESCAPE; e.pressed = false
	root.push_input(e,true)

func portal(b: Board) -> void:
	var portal_id: int = b.session.spawn_card(b.catalog.find_by_name("Grand Portal"),Vector2(3,0),-1,{"refuse_attach":true})
	var worker: int = b.session.spawn_card(b.catalog.find_by_name("Villager"),Vector2(4,0),-1,{"refuse_attach":true})
	check(b.session.move_to_stack(worker,b.session.cards[portal_id].stack_id),"组合原 Grand Portal")
	check(b.session.crafting.advance(5) and b.session.travel_pending,"原 Grand Portal 触发")
	b._process(1.0); b._process(1.0)

func run() -> void:
	root.gui_embed_subwindows = true
	root.size = Vector2i(1280,800)
	for scene in ["Main","Island"]:
		var b := Board.new()
		b.feedback.free(); b.feedback=SilentFeedback.new()
		var path := "user://pause-title-camera-%d" % Time.get_ticks_usec()
		b.slot_root=path+"/slots"; b.options_path=path+"/options.json"
		b.legacy_paths.clear()
		root.add_child(b)
		await process_frame
		b.set_process(false)
		if b.data_error!=OK:
			print("SKIP 原暂停标题往返需要已授权的本地原始数据。")
			b.queue_free()
			await process_frame
			quit(0)
			return
		b.start_new()
		if scene=="Island": portal(b)
		b.set_process(false); b.vendor_unlock.cancel()
		b.session.cycle.reset(); b.session.phase="playing"
		b.session.elapsed=2.0
		var id: int=b.session.spawn_card(b.catalog.find_by_name("Wood"),Vector2(2,0),-1,{"refuse_attach":true})
		var owner = b.session
		var slot: int = b.active_slot
		var zero:=Vector3(0,12,1)
		b.camera.position=zero; b.camera_motion.configure(zero); b._clamp_camera()
		check(owner.scene_name==scene and b.source_saved_rows!=null,scene+" 实际场景及原保存槽")
		if b.source_saved_rows==null:
			b.queue_free(); await process_frame; continue
		pause()
		await process_frame
		var button: Button=b.pause_controls[2]
		var at:=center(button)
		var edge:=at+Vector2(64,12)
		check(b.pause_overlay.visible and b._source_pause_title_open() and button.button_mask==7,
			scene+" Escape 打开原暂停，Title 绑定实际鼠标路由")

		# 先模拟真实保存失败，只用此测试的独立文件；不能取得淡出权限。
		var slot_dir:=b.slot_root
		var failure:=FileAccess.open(path+"/blocker",FileAccess.WRITE)
		if failure==null:
			check(false,"测试用失败路径不可写"); b.queue_free(); await process_frame; continue
		failure.store_string("not a directory")
		failure.close()
		b.slot_root=path+"/blocker/slots"
		click(MOUSE_BUTTON_LEFT,at)
		check(not b.scene_transition.active() and b.running and b.pause_overlay.visible
			and b._outbound_camera_kind==Board.OutboundCamera.NONE and "Could not save" in b.notice.text,
			scene+" 真实保存失败保留暂停和同一场景")
		b.slot_root=slot_dir
		b._update_camera_motion(0) # 上一个左键释放已在自己的帧结算。

		# Pause 本身不会锁相机；先在菜单以外区域按中键。
		move(edge); mouse(MOUSE_BUTTON_MIDDLE,true,edge); b._update_camera_motion(0)
		check(b.panning,scene+" 暂停背景中键可开始相机拖动")
		# 先送半笔轮量；点击 Title 的右键既不新建相机平移，也不结束中键。
		mouse(MOUSE_BUTTON_WHEEL_UP,true,edge,.25)
		click(MOUSE_BUTTON_RIGHT,at)
		var save_path: String=b.slots.slot_path(slot)
		var disk:=FileAccess.get_file_as_string(save_path)
		var parsed: Variant=JSON.parse_string(disk)
		check(b.scene_transition.phase=="out" and b._source_outbound_camera_allowed() and b.session==owner
			and b.panning and b._outbound_mouse_hold.is_empty(),scene+" 实际 Title 右键在保存后才接管出场相机")
		check(parsed is Dictionary and parsed.get("current_scene")==scene
			and is_equal_approx(float(parsed.scenes[scene].session.elapsed),2.0),
			scene+" 盘上仍为原游戏场景及已保存时间")
		var moved:=at+Vector2(28,6)
		var pixels: Vector2=root.get_final_transform()*moved-root.get_final_transform()*edge
		var scale: float=b.camera_motion.settings.panSpeed*zero.y/10.0
		var forward:Vector3=-b.camera.global_basis.z
		move(moved); mouse(MOUSE_BUTTON_WHEEL_UP,true,moved,.25)
		b._process(.15)
		check(b.panning and b.camera_motion.target.is_equal_approx(zero+Vector3(-pixels.x,0,-pixels.y)*scale+forward*.5)
			and b.camera.position!=zero and is_equal_approx(b.scene_transition.alpha,.15) and b.session.elapsed==2.0,
			scene+" 淡出中旧中键继续、轮量同帧合计、阻尼前进而日计时不动")

		var target:Vector3=b.camera_motion.target
		var prior:Vector3=b.camera.position
		mouse(MOUSE_BUTTON_MIDDLE,false,moved)
		mouse(MOUSE_BUTTON_LEFT,true,edge); move(edge+Vector2(25,0))
		b._process(.15)
		check(not b.panning and b.camera_motion.target==target and b.camera.position!=prior
			and not b._allows_card_actions() and not b._text_button_allowed(button),
			scene+" 遮罩挡新左键/卡牌/按钮，不冻结已开始的阻尼")
		mouse(MOUSE_BUTTON_LEFT,false,edge)
		b._update_camera_motion(0)
		mouse(MOUSE_BUTTON_MIDDLE,true,edge)
		move(edge+Vector2(16,0))
		b._process(.1)
		check(b.panning and b.camera_motion.target==target,scene+" 淡出中新中键以最后位置建立原点")
		b.vendor_unlock.sequence.stage="hold"
		prior=b.camera.position
		mouse(MOUSE_BUTTON_WHEEL_UP,true,edge,.5); move(edge+Vector2(45,0)); b._update_camera_motion(.06)
		check(b.camera.position==prior and b.camera_motion.target==target,scene+" 独立商贩输入锁仍禁止相机更新")
		b.vendor_unlock.cancel()

		b._process(1.0)
		check(not b.running and b.scene_transition.phase=="in" and b.title_panel.visible
			and not b.panning and b.camera_motion.velocity==Vector3.ZERO and b.camera_motion.target==b.camera.position
			and b._outbound_camera_kind==Board.OutboundCamera.NONE and FileAccess.get_file_as_string(save_path)==disk,
			scene+" 黑屏加载新标题、清理旧运动、不二次保存")
		var title_pose:Vector3=b.camera.position
		move(edge); mouse(MOUSE_BUTTON_WHEEL_UP,true,edge,.5)
		b._process(1.0)
		mouse(MOUSE_BUTTON_MIDDLE,false,edge)
		check(b.camera.position==title_pose and b._camera_scroll_sample==0,scene+" 旧手势不进入新标题")
		# 经真实标题及列表组件加载该槽，不走诊断恢复。
		click(MOUSE_BUTTON_LEFT,center(b.title_load_button))
		await process_frame
		check(b.title_saves.is_visible_in_tree() and b.source_saved_rows.rows.size()==1,scene+" 实际储存列表含独立槽")
		if not b.source_saved_rows.rows.is_empty():
			click(MOUSE_BUTTON_LEFT,center(b.source_saved_rows.rows[0].load_button))
			b._process(1.0)
			check(b.running and b.session!=owner and b.active_slot==slot and b.session.scene_name==scene
				and b.session.cards.has(id) and b.session.cards[id].definition_guid==b.catalog.find_by_name("Wood")
				and is_equal_approx(b.session.elapsed,2.0) and not b.pause_overlay.visible
				and b.camera_motion.target==b.camera.position and b.camera_motion.velocity==Vector3.ZERO,
				scene+" 读取同槽的真实牌和日期，不加载旧相机或暂停")
		b.queue_free()
		await process_frame
	print("原暂停标题旧相机：%d/%d（%s）" % [checks-failures,checks,DisplayServer.get_name()])
	quit(int(failures!=0))
