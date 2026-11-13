extends Control
## Read-only slot presentation. Caller owns load/archive confirmation transactions.
const Geometry = preload("res://scripts/ui/source_control_metadata.gd")
var slot_id := 0
var info := Label.new()
var load_button = preload("res://scripts/ui/text_button_feedback.gd").new()
var archive_button = preload("res://scripts/ui/text_button_feedback.gd").new()
var background := ColorRect.new()
var records: Dictionary
var font_status: Dictionary = {}
var load_action: Callable
var archive_action: Callable
var allowed: Callable
var play_click: Callable
var font_resolver: Callable
var valid := false
static func metadata(documents: Array) -> Dictionary:
	var binding: Dictionary = {}
	for document in documents:
		var f: Dictionary = document.get("fields",{})
		if f.has("labelText") and f.has("loadButton") and f.has("deleteButton"): binding = f
	if binding.is_empty(): return {}
	var root := Geometry.rect(documents,binding)
	var result: Dictionary = {"SavedGameSlot":{"rect":root}}
	for pair in [["Label","labelText"],["Load","loadButton"],["Delete","deleteButton"]]:
		var component := Geometry.fields(documents,binding[pair[1]])
		var rectangle := Geometry.rect(documents,component)
		var text := Geometry.component(documents,component.get("m_GameObject",{}),"m_text")
		if rectangle.is_empty() or text.is_empty(): return {}
		result[pair[0]] = {"rect":rectangle,"text":text}
	var actions := Geometry.fields(documents,result.Load.rect.get("m_Father",{}))
	if actions.is_empty() or result.Load.rect.m_Father != result.Delete.rect.m_Father: return {}
	result.Actions = {"rect":actions}
	result.background = Geometry.component(documents,root.get("m_GameObject",{}),"m_Sprite")
	if result.background.is_empty() or str(result.background.m_Sprite.get("fileID","0")) != "0": return {}
	return result

func configure(entry: Dictionary, source: Dictionary, on_load: Callable, on_archive: Callable, guard: Callable = Callable()) -> bool:
	if source.is_empty() or not records.is_empty(): return false
	records = source
	slot_id = int(entry.get("slot",0))
	if slot_id <= 0: return false
	load_action = on_load
	archive_action = on_archive
	allowed = guard
	valid = bool(entry.get("valid",false))
	custom_minimum_size.y = Geometry.v(records.SavedGameSlot.rect.m_SizeDelta).y
	background.color = Geometry.color(records.background.m_Color)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(info)
	add_child(load_button)
	add_child(archive_button)
	info.text = describe(entry)
	info.mouse_filter = Control.MOUSE_FILTER_IGNORE
	info.add_theme_font_size_override("font_size",int(records.Label.text.m_fontSize))
	_apply_font(info,records.Label.text)
	info.add_theme_color_override("font_color",Geometry.color(records.Label.text.m_fontColor))
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART if bool(records.Label.text.get("m_enableWordWrapping",false)) else TextServer.AUTOWRAP_OFF
	info.clip_text = int(records.Label.text.get("m_overflowMode",0)) != 0
	info.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if int(records.Label.text.get("m_VerticalAlignment",256)) == 512 else VERTICAL_ALIGNMENT_TOP
	_style(load_button, records.Load.text)
	_style(archive_button, records.Delete.text)
	load_button.text = str(records.Load.text.m_text)
	archive_button.text = "Archive" # Explicit safe divergence, never label this Delete.
	archive_button.tooltip_text = "Request recoverable archiving; files are not permanently deleted."
	load_button.disabled = not valid
	archive_button.disabled = not archive_action.is_valid()
	load_button.configure(func():
		if valid and load_action.is_valid(): load_action.call(slot_id),play_click,_admitted)
	archive_button.configure(func():
		if archive_action.is_valid(): archive_action.call(slot_id),play_click,_admitted)
	resized.connect(relayout)
	relayout()
	return true
func _admitted() -> bool: return is_visible_in_tree() and (not allowed.is_valid() or allowed.call())
func _style(button: Button, source: Dictionary) -> void:
	button.flat = true
	button.set_meta("source_tmp_horizontal_alignment",int(source.get("m_HorizontalAlignment",2)))
	button.set_meta("source_text_layout_parity","flush_pending" if int(source.get("m_HorizontalAlignment",2)) == 16 else "native_unverified")
	_apply_font(button,source)
	button.add_theme_font_size_override("font_size",int(source.m_fontSize))
	for key in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]: button.add_theme_color_override(key,Geometry.color(source.m_fontColor))
	for state in ["normal","hover","pressed","focus","disabled"]: button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
func relayout() -> void:
	if records.is_empty(): return
	var label_rect := Geometry.rectangle(records.Label.rect,size)
	info.set_meta("source_rect",label_rect)
	info.position = label_rect.position
	info.size = label_rect.size
	var actions := Geometry.rectangle(records.Actions.rect,size)
	for pair in [[load_button,"Load"],[archive_button,"Delete"]]:
		var rect := Geometry.rectangle(records[pair[1]].rect,actions.size)
		pair[0].set_meta("source_rect",Rect2(actions.position+rect.position,rect.size))
		pair[0].position = actions.position+rect.position
		pair[0].size = rect.size
static func describe(entry: Dictionary) -> String:
	var header := "[Slot %03d] %s" % [int(entry.get("slot",0)),str(entry.get("scene","Unavailable"))]
	if entry.has("quest_progress") and bool(entry.get("valid",false)): header += " (%d%%)" % int(entry.quest_progress)
	if not bool(entry.get("valid",false)): return header+"\nUnavailable; files preserved"
	# Saved timestamp is accepted only when provenance identifies a persisted field.
	var timestamp: Dictionary = entry.get("saved_timestamp",{})
	if timestamp.get("provenance") == "persisted_save_field" and timestamp.has("display"):
		return header+"\nLast Saved: "+str(timestamp.display)
	if entry.has("modified_unix"):
		return header+"\nFile modified: "+Time.get_datetime_string_from_unix_time(int(entry.modified_unix)).replace("T"," ")+" UTC"+(" (backup)" if entry.get("recovered",false) else "")
	return header+"\nLast Saved: unavailable"

func _apply_font(control: Control, source: Dictionary) -> void:
	if ResourceLoader.exists("res://scripts/ui/source_font_registry.gd"):
		font_status = load("res://scripts/ui/source_font_registry.gd").shared().bind_control(control,source)
		return
	if not font_resolver.is_valid(): return
	var font: Variant = font_resolver.call(source.get("m_fontAsset",{}))
	if font is Font: control.add_theme_font_override("font",font)
