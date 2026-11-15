extends SceneTree
const Options = preload("res://scripts/ui/options_panel.gd")
const Feedback = preload("res://scripts/ui/text_button_feedback.gd")
var calls := 0
var sounds := 0
var allowed := true
func _init(): call_deferred("run")
func send_button(index: int, down: bool, pos: Vector2):
	var motion := InputEventMouseMotion.new()
	motion.position = pos
	motion.global_position = pos
	root.push_input(motion,true)
	var event := InputEventMouseButton.new()
	event.button_index = index
	event.pressed = down
	event.position = pos
	event.global_position = pos
	root.push_input(event,true)
func run():
	root.size = Vector2i(800,600)
	var button = Feedback.new()
	root.add_child(button)
	button.position = Vector2(100,100)
	button.size = Vector2(200,80)
	button.configure(func(): calls += 1, func(): sounds += 1, func(): return allowed)
	var options = Options.new()
	var fake_layout = {"records": {"node": {"components": [{"m_Enabled":1,"m_Script":{"guid":"ef98d84a856977b44bbf49a1bab2060a"}}]}}}
	# Use actual source layout resolver with synthetic serialized provenance.
	var layout = preload("res://scripts/ui/title_scene_layout.gd").new()
	layout.records = fake_layout.records
	layout.records.node["name"] = "Graphics"
	layout.root_id = "root"
	layout.children = {"root":["node"]}
	var view = {"layout":layout}
	var data = {"provenance":{"source_commit":"a11a89b04cea8370476f2559b639bb9b4cbc08d8"}}
	assert(button.button_mask == MOUSE_BUTTON_MASK_LEFT)
	options._admit_source_text_pointer_buttons(data,view,"Missing",button)
	assert(button.button_mask == MOUSE_BUTTON_MASK_LEFT)
	options._admit_source_text_pointer_buttons({},view,"Graphics",button)
	assert(button.button_mask == MOUSE_BUTTON_MASK_LEFT,"missing provenance rejected")
	options._admit_source_text_pointer_buttons({"provenance":{"source_commit":"wrong"}},view,"Graphics",button)
	assert(button.button_mask == MOUSE_BUTTON_MASK_LEFT,"wrong provenance rejected")
	layout.records.node.components[0].m_Enabled = 0
	options._admit_source_text_pointer_buttons(data,view,"Graphics",button)
	assert(button.button_mask == MOUSE_BUTTON_MASK_LEFT,"disabled source component rejected")
	layout.records.node.components[0].m_Enabled = 1
	options._admit_source_text_pointer_buttons(data,view,"Graphics",button)
	assert(button.button_mask == 7)
	await process_frame
	for index in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
		var old := calls
		send_button(index,true,Vector2(150,140))
		assert(calls == old,"no callback on press")
		send_button(index,false,Vector2(150,140))
		assert(calls == old+1 and sounds == calls,"one action then sound on release")
		old = calls
		send_button(index,true,Vector2(150,140))
		send_button(index,false,Vector2(500,400))
		assert(calls == old,"release outside cancels")
	allowed = false
	for index in [1,2,3]:
		send_button(index,true,Vector2(150,140)); send_button(index,false,Vector2(150,140))
	assert(calls == 3,"modal guard remains authoritative")
	allowed = true
	button.disabled = true
	send_button(2,true,Vector2(150,140)); send_button(2,false,Vector2(150,140))
	assert(calls == 3)
	button.disabled = false
	button.button_mask = MOUSE_BUTTON_MASK_LEFT
	for index in [2,3]:
		send_button(index,true,Vector2(150,140)); send_button(index,false,Vector2(150,140))
	assert(calls == 3,"ordinary shared feedback remains left only")
	options.free(); button.queue_free()
	await process_frame
	print("Source Options pointer: PASS (source-only admission, sequential left/right/middle release, outside cancellation, modal/disabled guards, fallback unchanged)")
	quit()
