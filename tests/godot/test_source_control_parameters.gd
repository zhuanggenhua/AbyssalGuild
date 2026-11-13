extends SceneTree
const Metadata = preload("res://scripts/ui/source_control_metadata.gd")
const SliderAdapter = preload("res://scripts/ui/source_slider_adapter.gd")
const ToggleAdapter = preload("res://scripts/ui/source_text_toggle_adapter.gd")
const Tint = preload("res://scripts/ui/selectable_tint.gd")
func _init() -> void: call_deferred("run")
func run() -> void:
	if not FileAccess.file_exists("res://data/stackcraft.json"):
		print("Source control private parameters: SKIP (licensed catalog unavailable)")
		quit()
		return
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/stackcraft.json"))
	var docs: Dictionary = {}
	for scene in catalog.get("scenes", []):
		if scene.get("name") == "Title": docs["Title.unity"] = scene.documents
	for prefab in catalog.get("referenced_prefabs", []):
		if prefab.get("name") == "GameOptionsUI": docs["GameOptionsUI.prefab"] = prefab.documents
	var refs: Array = []
	var toggle_ref: Dictionary = {}
	for name in docs:
		for doc in docs[name]:
			var f: Dictionary = doc.fields
			for key in ["durationSlider", "sliderSFX", "sliderBGM"]:
				if f.has(key): refs.append([docs[name],f[key],key])
			if f.has("isFriendlyToggle"): toggle_ref = f.isFriendlyToggle
	assert(refs.size() == 3)
	for ref in refs:
		var source := Metadata.slider(ref[0],ref[1])
		assert(not source.is_empty())
		var model := HSlider.new()
		root.add_child(model)
		model.size = Vector2(450,20) if ref[2] == "durationSlider" else Vector2(360,20)
		model.min_value = source.control.m_MinValue
		model.max_value = source.control.m_MaxValue
		model.step = 1 if source.control.m_WholeNumbers else 0
		model.value = source.control.m_Value
		var calls := [0]
		model.value_changed.connect(func(_v): calls[0] += 1)
		var adapter = SliderAdapter.new()
		assert(adapter.bind(model,source))
		adapter.refresh()
		assert(calls[0] == 0)
		assert(adapter.handle.size.is_equal_approx(Vector2(20,40) if ref[2] == "durationSlider" else Vector2(10,20)))
		adapter.update_drag(Vector2(0,10))
		assert(model.value == model.min_value)
		adapter.update_drag(Vector2(model.size.x,10))
		assert(model.value == model.max_value and calls[0] == 2)
		assert(adapter.fill.size.y == 10)
		model.queue_free()
	var toggle_source := Metadata.text_toggle(docs["Title.unity"],toggle_ref)
	assert(not toggle_source.is_empty() and toggle_source.label.m_fontSize == 32)
	var original := CheckBox.new()
	original.text = "Friendly Mode: OFF\n(Enemies may appear)"
	root.add_child(original)
	var counts := [0,0]
	original.toggled.connect(func(value):
		counts[0] += 1
		original.text = "Friendly Mode: ON\n(No enemies will appear)" if value else "Friendly Mode: OFF\n(Enemies may appear)")
	original.pressed.connect(func(): counts[1] += 1)
	var toggle = ToggleAdapter.new()
	assert(toggle.bind(original,toggle_source))
	assert(toggle.detail_size == 23)
	toggle._activate()
	assert(original.button_pressed and counts == [1,1] and toggle.label.text.contains("No enemies will appear"))
	original.disabled = true
	toggle._activate()
	assert(counts == [1,1])
	original.queue_free()
	var tint = Tint.new()
	tint.configure({"m_NormalColor":{"r":1,"g":1,"b":1,"a":1},"m_PressedColor":{"r":0,"g":0,"b":0,"a":1},"m_FadeDuration":0.1})
	tint.set_state("Pressed")
	assert(tint.advance(0.05).is_equal_approx(Color(0.5,0.5,0.5,1)))
	assert(tint.advance(0.05).is_equal_approx(Color(0,0,0,1)))
	await process_frame
	print("Source control adapters: PASS (3 private sliders, source geometry, callback preservation, no-icon toggle, 32/23 text, selectable transition)")
	quit()
