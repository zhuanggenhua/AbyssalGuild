extends SceneTree
const Metadata = preload("res://scripts/ui/source_control_metadata.gd")
const SliderAdapter = preload("res://scripts/ui/source_slider_adapter.gd")
func rect(lo: Vector2, hi: Vector2, extent: Vector2) -> Dictionary:
	return {"m_AnchorMin":{"x":lo.x,"y":lo.y},"m_AnchorMax":{"x":hi.x,"y":hi.y},"m_Pivot":{"x":0.5,"y":0.5},"m_SizeDelta":{"x":extent.x,"y":extent.y},"m_AnchoredPosition":{"x":0,"y":0}}
func _init() -> void: call_deferred("run")
func run() -> void:
	assert(Metadata.slider([], {}) == {} and Metadata.text_toggle([], {}) == {})
	var image := {"m_Color":{"r":0.2,"g":0.3,"b":0.4,"a":0.5}}
	var source := {"control":{"m_WholeNumbers":false,"m_Colors":{"m_NormalColor":{"r":1,"g":1,"b":1,"a":1},"m_FadeDuration":0.2}},"background":{"rect":rect(Vector2(0,0.25),Vector2(1,0.75),Vector2.ZERO),"image":image},"fill_parent":rect(Vector2.ZERO,Vector2.ONE,Vector2(-10,0)),"handle_parent":rect(Vector2.ZERO,Vector2.ONE,Vector2(-10,0)),"fill":rect(Vector2.ZERO,Vector2(0.5,1),Vector2.ZERO),"handle":rect(Vector2(0.5,0),Vector2(0.5,1),Vector2(10,0)),"handle_image":image,"fill_image":image}
	var model := HSlider.new()
	root.add_child(model)
	model.size = Vector2(100,20)
	model.min_value = 10
	model.max_value = 30
	model.step = 0
	model.value = 20
	var calls := [0]
	model.value_changed.connect(func(_v): calls[0] += 1)
	var view = SliderAdapter.new()
	assert(view.bind(model,source))
	assert(not view.bind(model,source))
	assert(model.value == 20 and calls[0] == 0)
	assert(view.handle.position.is_equal_approx(Vector2(45,0)))
	assert(view.fill.size.is_equal_approx(Vector2(45,20)))
	view.update_drag(Vector2(27.5,10))
	assert(is_equal_approx(model.value,15) and calls[0] == 1)
	model.value = 25
	assert(is_equal_approx(view.handle.position.x,67.5))
	model.queue_free()
	await process_frame
	print("Source control synthetic: PASS (no private data, nonzero domain, geometry, lifecycle, bidirectional values)")
	quit()
