extends SceneTree
const Slot = preload("res://scripts/ui/source_saved_slot.gd")
const Layout = preload("res://scripts/ui/source_saved_layout.gd")
const Bridge = preload("res://scripts/ui/saved_slot_callback_bridge.gd")
func rectangle(lo: Vector2, hi: Vector2, delta: Vector2, pos: Vector2, pivot: Vector2) -> Dictionary:
	return {"m_AnchorMin":{"x":lo.x,"y":lo.y},"m_AnchorMax":{"x":hi.x,"y":hi.y},"m_SizeDelta":{"x":delta.x,"y":delta.y},"m_AnchoredPosition":{"x":pos.x,"y":pos.y},"m_Pivot":{"x":pivot.x,"y":pivot.y}}
func fixture() -> Dictionary:
	var text := {"m_fontSize":24,"m_fontColor":{"r":1,"g":1,"b":1,"a":1},"m_text":"Load"}
	return {"SavedGameSlot":{"rect":rectangle(Vector2.ZERO,Vector2.ZERO,Vector2(500,80),Vector2.ZERO,Vector2.ZERO)},"Label":{"rect":rectangle(Vector2.ZERO,Vector2(0,1),Vector2(350,-16),Vector2(8,0),Vector2(0,0.5)),"text":text},"Actions":{"rect":rectangle(Vector2(1,0),Vector2.ONE,Vector2(120,-16),Vector2(-8,0),Vector2(1,0.5))},"Load":{"rect":rectangle(Vector2(0,1),Vector2.ONE,Vector2(0,32),Vector2.ZERO,Vector2(0.5,1)),"text":text},"Delete":{"rect":rectangle(Vector2.ZERO,Vector2(1,0),Vector2(0,32),Vector2.ZERO,Vector2(0.5,0)),"text":text},"background":{"m_Color":{"r":1,"g":1,"b":1,"a":0.2}}}
func _init() -> void: call_deferred("run")
func run() -> void:
	var counts := [0,0]
	var entry := {"slot":7,"scene":"Island","quest_progress":60,"valid":true,"modified_unix":100}
	var original := entry.duplicate(true)
	var slot = Slot.new()
	root.add_child(slot)
	slot.size = Vector2(500,80)
	assert(slot.configure(entry,fixture(),func(id): counts[0] += id,func(id): counts[1] += id))
	assert(slot.info.get_meta("source_rect") == Rect2(8,8,350,64))
	assert(slot.load_button.position == Vector2(372,8))
	assert(slot.archive_button.position == Vector2(372,40))
	assert(slot.info.text.contains("File modified:") and not slot.info.text.contains("Last Saved:"))
	slot.load_button.pressed.emit()
	slot.archive_button.pressed.emit()
	assert(counts == [7,7] and entry == original and slot.archive_button.text == "Archive")
	slot.allowed = func(): return false
	slot.archive_button.pressed.emit()
	assert(counts == [7,7])
	assert(Slot.describe({"slot":1,"valid":true}).ends_with("Last Saved: unavailable"))
	assert(Slot.describe({"slot":1,"valid":true,"saved_timestamp":{"provenance":"persisted_save_field","display":"verified stamp"}}).ends_with("Last Saved: verified stamp"))
	var rows := Layout.rows(600,[80,80],Vector4(8,6,8,6),12)
	assert(rows.rectangles[0] == Rect2(8,6,584,80) and rows.preferred_height == 184)
	var footer := Layout.footer(Vector2(600,70),[160,120],[40,40],Vector4.ZERO,40)
	assert(footer.ok and footer.rectangles == [Rect2(140,15,160,40),Rect2(340,15,120,40)])
	assert(not Layout.footer(Vector2(200,70),[160,120],[40,40],Vector4.ZERO,40).ok)
	var selector := OptionButton.new()
	root.add_child(selector)
	selector.add_item("seven",7)
	selector.set_item_metadata(0,entry)
	var selected := [0]
	selector.item_selected.connect(func(_index): selected[0] += 1)
	var bridge = Bridge.new()
	bridge.selector = selector
	bridge.load_action = func(): selected[0] += 10
	bridge.archive_action = func(): selected[0] += 100
	assert(bridge.request(7,false) and selected[0] == 11)
	assert(not bridge.request(8,true) and selected[0] == 11)
	assert(bridge.request(7,true) and selected[0] == 112)
	selector.free()
	slot.queue_free()
	await process_frame
	print("Source slot synthetic: PASS (template geometry, callback bridge, safe archive, timestamp provenance, row/footer layout)")
	quit()
