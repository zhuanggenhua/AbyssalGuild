extends SceneTree
const Bar=preload("res://scripts/ui/source_scrollbar_adapter.gd")
func rect(delta: Vector2) -> Dictionary:
	return {"m_AnchorMin":{"x":0,"y":0},"m_AnchorMax":{"x":1,"y":1},"m_SizeDelta":{"x":delta.x,"y":delta.y},"m_AnchoredPosition":{"x":0,"y":0},"m_Pivot":{"x":0.5,"y":0.5}}
func _init() -> void: call_deferred("run")
func run() -> void:
	var native:=VScrollBar.new()
	native.max_value=1; native.page=0.25
	native.value=0.375
	print("Native VScrollBar default step=",native.step," requested .375 -> ",native.value)
	native.free()
	var c:={"m_Value":0,"m_Size":1,"m_Interactable":1,"m_Colors":{"m_NormalColor":{"r":1,"g":1,"b":1,"a":1},"m_PressedColor":{"r":0.5,"g":0.5,"b":0.5,"a":1},"m_ColorMultiplier":1,"m_FadeDuration":0.1}}
	var b=Bar.new()
	root.add_child(b)
	b.size=Vector2(20,660)
	assert(b.configure({"control":c,"container":rect(Vector2(-20,-20)),"handle":rect(Vector2(20,20)),"image":{"m_Color":{"r":0.638,"g":0.638,"b":0.638,"a":1}}},func():return true))
	b.set_process(false)
	var calls:=[0]
	b.value_changed.connect(func(_v):calls[0]+=1)
	b.sync(0.123456789,0.25)
	assert(b.value==0.123456789 and calls[0]==0)
	assert(b.handle.size.is_equal_approx(Vector2(20,180)))
	assert(is_equal_approx(b.handle.position.y,640*(1-0.25)*(1-b.value)))
	b.sync(1,0.25)
	assert(b.handle.position==Vector2.ZERO)
	assert(b._has_point(Vector2(10,90)) and not b._has_point(Vector2(10,400)))
	# Direct callback tests the component algorithm; source empty track is not a raycast target.
	b.press(Vector2(10,400))
	# ClickRepeat centers at original press; not source size/.page increments.
	assert(is_equal_approx(b.value,(660-10-400-80)/480.0))
	var v:float=b.value
	b.repeat_press()
	assert(b.value==v and calls[0]==1)
	b.move_pointer(Vector2(10,448))
	assert(is_equal_approx(b.value,v-0.1))
	b.release()
	b.move_vertical(true)
	assert(is_equal_approx(b.value,v))
	b.move_vertical(false)
	assert(is_equal_approx(b.value,v-0.1))
	b.sync(1.2,0.3)
	assert(b.value==1.2 and b.handle.position.y==0)
	b.sync(0.5,1)
	b.update_drag(Vector2(10,20))
	assert(b.value==0.5 and b.handle.size.y==660)
	b.sync(0.5,0)
	assert(b.handle.size.y==20)
	b.sync(0,0.25)
	b.advance_navigation(1,0)
	assert(is_equal_approx(b.value,0.1))
	b.advance_navigation(1,0.5)
	assert(is_equal_approx(b.value,0.1))
	b.advance_navigation(1,0.501)
	assert(is_equal_approx(b.value,0.2))
	b.advance_navigation(1,0.601)
	assert(is_equal_approx(b.value,0.2))
	b.advance_navigation(1,0.602)
	assert(is_equal_approx(b.value,0.3))
	b.advance_navigation(-1,0.603)
	assert(is_equal_approx(b.value,0.2))
	b.sync(0.5,0)
	b.allowed=func():return false
	b.move_vertical(true)
	assert(b.value==0.5)
	b.queue_free()
	await process_frame
	print("Source scrollbar: PASS (continuous value, driven geometry, click-centering, drag, vertical move, full/zero fraction, guarded input)")
	quit()
