extends SceneTree
const Host = preload("res://scripts/ui/source_journal_scroll_host.gd")
const Contract = preload("res://scripts/ui/source_journal_scroll_contract.gd")
const Rows = preload("res://scripts/ui/source_journal_rows.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr(label)
func near(a: float,b: float) -> bool: return absf(a-b)<0.0001
func button(index: int, pressed: bool, at := Vector2.ZERO, factor := 1.0) -> InputEventMouseButton:
	var event := InputEventMouseButton.new()
	event.button_index = index; event.pressed = pressed; event.position = at; event.factor = factor
	return event
func move(at: Vector2) -> InputEventMouseMotion:
	var event := InputEventMouseMotion.new(); event.position = at; return event
func _initialize() -> void: call_deferred("run")
func run() -> void:
	test_source_contract()
	var a = Host.new(); var b = Host.new()
	root.add_child(a); root.add_child(b)
	a.set_process(false); b.set_process(false)
	a.size = Vector2(400,240); b.size = a.size
	a.set_content_height(740); b.set_content_height(740)
	check(a.clip_contents and a.content.size==Vector2(400,740),"full-width clip, complete preferred extent")
	check(a.get_child_count()==2 and a.background.size==a.size,"background plus content only: no scrollbar")
	a._gui_input(button(MOUSE_BUTTON_WHEEL_DOWN,true))
	check(near(a.motion.position,6) and near(a.content.position.y,-6),"one wheel tick is six source units")
	a._gui_input(button(MOUSE_BUTTON_WHEEL_UP,true,Vector2.ZERO,0.5))
	check(near(a.motion.position,3),"fractional reverse tick")
	a._gui_input(button(MOUSE_BUTTON_WHEEL_RIGHT,true))
	check(near(a.motion.position,9),"horizontal wheel mapped vertical")
	a.scroll_ticks(Vector2(-2,1)); check(near(a.motion.position,-3),"diagonal dominant horizontal")
	a.scroll_ticks(Vector2(0.5,-1)); check(near(a.motion.position,3),"diagonal dominant vertical")
	a.scroll_ticks(Vector2(NAN,1)); a.scroll_ticks(Vector2.ZERO)
	check(near(a.motion.position,3),"invalid/zero ticks ignored")
	a.reset_scroll(); a.scale = Vector2(2,2)
	a._gui_input(button(MOUSE_BUTTON_WHEEL_DOWN,true))
	check(near(a.motion.position,6) and near((a.content.get_global_transform_with_canvas().origin-a.get_global_transform_with_canvas().origin).y,-12),"wheel local units unaffected by Canvas scale")
	a.reset_scroll()
	a._input(button(MOUSE_BUTTON_LEFT,true,Vector2(10,10)))
	check(not a.pending_drag,"global press cannot bypass GUI ownership")
	a._gui_input(button(MOUSE_BUTTON_LEFT,true,Vector2(10,10)))
	var final_inverse := root.get_final_transform().affine_inverse()
	var press_physical: Vector2 = a._physical_pointer(Vector2(20,20))
	a._input(move(final_inverse*(press_physical+Vector2(0,9.99))))
	check(not a.motion.dragging and a.can_click(),"below ten physical pixels retains click")
	a._input(move(final_inverse*(press_physical+Vector2(0,10))))
	check(a.motion.dragging and not a.can_click() and near(a.motion.position,0),"threshold begins at current cursor, no retrospective displacement")
	var next_viewport: Vector2 = final_inverse*(press_physical-Vector2(0,10))
	var start_viewport: Vector2 = final_inverse*(press_physical+Vector2(0,10))
	a._input(move(next_viewport))
	check(near(a.motion.position,(start_viewport.y-next_viewport.y)/2.0),"physical drag transformed to local displacement")
	a.advance_unscaled(0.02)
	check(a.motion.velocity>0,"drag samples unscaled velocity")
	a._input(button(MOUSE_BUTTON_LEFT,false,Vector2(900,900)))
	check(not a.motion.dragging and not a.pending_drag and not a.can_click(),"outside release ends drag, click guard persists this dispatch")
	await process_frame
	a.set_process(false)
	check(a.can_click(),"guard resets after release dispatch")
	a.motion.position=100; a.motion.previous=100; a.motion.velocity=100
	a.set_tab_active(false); a.advance_unscaled(1)
	check(near(a.motion.position,113.5) and near(a.motion.velocity,13.5),"hidden tab continues source inertia")
	check(near(b.motion.position,0) and near(b.motion.velocity,0),"tab ownership independent")
	a._gui_input(button(MOUSE_BUTTON_WHEEL_DOWN,true))
	check(near(a.motion.position,113.5),"hidden tab rejects wheel")
	a.set_tab_active(true)
	check(near(a.motion.position,113.5),"reopening preserves motion")
	a.advance_unscaled(0)
	check(near(a.motion.velocity,13.5),"zero dt safe")
	a.set_content_height(50)
	for i in 180: a.advance_unscaled(1.0/60)
	check(absf(a.motion.position)<0.001,"content shrink restores short-content top pivot")
	a.reset_scroll(); a.scroll_ticks(Vector2(0,10))
	check(a.motion.position<0,"top elastic overscroll allowed")
	for i in 180: a.advance_unscaled(1.0/60)
	check(absf(a.motion.position)<0.001,"top elastic restitution")
	a.set_content_height(740); a.motion.position=520; a.motion.velocity=0
	for i in 180: a.advance_unscaled(1.0/60)
	check(absf(a.motion.position-500)<0.001,"bottom elastic restitution")
	a.size.y=400; a._resize_viewport()
	for i in 180: a.advance_unscaled(1.0/60)
	check(absf(a.motion.position-340)<0.001,"viewport resize recalculates bounds")
	a.reset_scroll()
	a._gui_input(button(MOUSE_BUTTON_RIGHT,true))
	check(not a.pending_drag and a.can_click(),"right click never starts ScrollRect drag")
	paused=true; a.motion.position=100; a.motion.previous=100; a.motion.velocity=100
	a.advance_unscaled(1)
	check(near(a.motion.position,113.5),"unscaled step while tree paused")
	paused=false
	a.reset_scroll()
	check(a.motion.position==0 and a.motion.velocity==0 and a.content.position==Vector2.ZERO,"scene reset clears complete motion")
	a.scale = Vector2.ONE; a.reset_scroll(); b.set_tab_active(false)
	# Full viewport padding is a legitimate GUI target; an overlaid modal wins picking.
	root.push_input(move(Vector2(5,5)),true)
	root.push_input(button(MOUSE_BUTTON_WHEEL_DOWN,true,Vector2(5,5)),true)
	check(near(a.motion.position,6),"actual GUI padding dispatch reaches host exactly once")
	var modal := Control.new(); modal.mouse_filter=Control.MOUSE_FILTER_STOP
	root.add_child(modal); modal.size=Vector2(400,240)
	root.push_input(move(Vector2(5,5)),true)
	root.push_input(button(MOUSE_BUTTON_WHEEL_DOWN,true,Vector2(5,5)),true)
	check(near(a.motion.position,6),"covering modal blocks host wheel")
	root.push_input(button(MOUSE_BUTTON_LEFT,true,Vector2(5,5)),true)
	check(not a.pending_drag,"covering modal blocks drag admission")
	modal.free()
	a.reset_scroll()
	a._gui_input(button(MOUSE_BUTTON_LEFT,true,Vector2(10,10)))
	a.set_tab_active(false)
	check(a.pending_drag,"CanvasGroup hiding does not discard captured pointer owner")
	a._input(button(MOUSE_BUTTON_LEFT,false,Vector2(900,900)))
	check(not a.pending_drag and not a.motion.dragging,"hidden captured owner receives release")
	a.free(); b.free()
	print("Source Journal ScrollRect host: %d/%d" % [checks-failures,checks])
	quit(1 if failures else 0)

func ref(id: String) -> Dictionary:
	return {"fileID":id}

func doc(id: String, type: String, fields: Dictionary) -> Dictionary:
	return {"file_id":id,"object_type":type,"fields":fields}

func rect(owner: String, parent: String, kids: Array, min_y: int) -> Dictionary:
	return {"m_GameObject":ref(owner), "m_Father":ref(parent),"m_Children":kids,
		"m_LocalScale":{"x":1,"y":1,"z":1},"m_LocalRotation":{"x":"-0","y":0,"z":0,"w":1},
		"m_LocalPosition":{"x":0,"y":0,"z":0},"m_Pivot":{"x":0,"y":1},
		"m_AnchorMin":{"x":0,"y":min_y},"m_AnchorMax":{"x":1,"y":1},
		"m_AnchoredPosition":{"x":0,"y":0},"m_SizeDelta":{"x":0,"y":0}}

func test_source_contract() -> void:
	var scroll := {"m_GameObject":ref("2"), "m_Content":ref("33"), "m_Viewport":ref("32"),
		"m_HorizontalScrollbar":ref("0"), "m_VerticalScrollbar":ref("0"),
		"m_Inertia":1,"m_Elasticity":0.2,"m_DecelerationRate":0.25,"m_ScrollSensitivity":2.0}
	scroll.merge(Contract.REQUIRED_SCROLL)
	var layout := {"m_GameObject":ref("4"), "m_Padding":{"m_Left":17,"m_Top":5,"m_Right":19,"m_Bottom":11},"m_Spacing":8}
	layout.merge(Contract.REQUIRED_LAYOUT)
	var docs := [
		doc("1","GameObject",{"m_Name":"MenuPanel","m_IsActive":1}),
		doc("2","GameObject",{"m_Name":"QuestsView","m_IsActive":1}),
		doc("3","GameObject",{"m_Name":"Viewport","m_IsActive":1}),
		doc("4","GameObject",{"m_Name":"Content","m_IsActive":1}),
		doc("30","RectTransform",rect("1","0",[ref("31")],0)),
		doc("31","RectTransform",rect("2","30",[ref("32")],0)),
		doc("32","RectTransform",rect("3","31",[ref("33")],0)),
		doc("33","RectTransform",rect("4","32",[],1)),
		doc("34","MonoBehaviour",scroll),
		doc("35","MonoBehaviour",{"m_GameObject":ref("3"),"m_Enabled":1,"m_ShowMaskGraphic":0}),
		doc("36","MonoBehaviour",{"m_GameObject":ref("3"),"m_Enabled":1,"m_Type":1,"m_RaycastTarget":1,
			"m_PreserveAspect":0,"m_UseSpriteMesh":0,"m_Material":ref("0"),"m_RaycastPadding":{"x":0,"y":0,"z":0,"w":0},
			"m_Sprite":{"fileID":"10917","guid":"0000000000000000f000000000000000"}}),
		doc("37","MonoBehaviour",layout),
		doc("38","MonoBehaviour",{"m_GameObject":ref("4"),"m_Enabled":1,"m_HorizontalFit":0,"m_VerticalFit":2}),
		doc("40","MonoBehaviour",{"m_GameObject":ref("2"),"m_Enabled":1,"content":ref("33")})]
	var admitted := Contract.resolve(docs,"QuestsView")
	check(not admitted.is_empty(),"local full-stretch viewport and top-pivot content admitted")
	if admitted.is_empty(): return
	var host := Host.new()
	var rows := Rows.new()
	check(host.configure_source_scroll(admitted) and host.source_scroll_bound
		and near(host.motion.sensitivity,2.0) and near(host.motion.deceleration,.25),
		"strictly admitted motion parameters reach the existing runtime")
	rows.set_scroll_layout(admitted)
	rows.layout_rows()
	check(rows.row_padding==Vector4(17,5,19,11) and near(rows.row_spacing,8) and near(rows.preferred_height,16),
		"authored padding and spacing drive preferred size without guessing TMP heights")
	for mutation in [
		[8,"m_Content",ref("32")], [8,"m_Viewport",{"fileID":"32","guid":"foreign"}],
		[8,"m_VerticalScrollbar",ref("99")], [8,"m_HorizontalScrollbar",{}],
		[8,"m_ScrollSensitivity","2"], [8,"m_Elasticity",NAN], [8,"m_DecelerationRate",1.1],
		[6,"m_Father",ref("30")], [6,"m_SizeDelta",{"x":3,"y":0}], [6,"m_Children",[]],
		[7,"m_Pivot",{"x":0,"y":.5}], [7,"m_LocalScale",{"x":1,"y":2,"z":1}],
		[9,"m_ShowMaskGraphic",1], [10,"m_RaycastTarget",0], [11,"m_ChildAlignment",1], [12,"m_VerticalFit",1], [13,"content",ref("32")]]:
		var changed := docs.duplicate(true)
		changed[mutation[0]].fields[mutation[1]] = mutation[2]
		check(Contract.resolve(changed,"QuestsView").is_empty(),"unsupported author field " + mutation[1] + " invalidates source admission")
	var ambiguous := docs.duplicate(true)
	ambiguous.append(doc("39","GameObject",{"m_Name":"QuestsView"}))
	check(Contract.resolve(ambiguous,"QuestsView").is_empty(),"duplicate named views cannot bind accidentally")
	host.motion.velocity = 80.0
	check(not host.configure_source_scroll({}) and not host.source_scroll_bound and near(host.motion.sensitivity,1.0)
		and near(host.motion.velocity,0.0) and host.get_meta("scroll_layout_status")=="unverified_native_fallback",
		"unsupported replacement clears previous source ownership and coefficients")
	host.free(); rows.free()
