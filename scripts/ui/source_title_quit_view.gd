extends Control
## Title's in-canvas ModalWindow, not a native ConfirmationDialog.
## Source text/layout inputs are preserved; native font measurement is not TMP parity.
const Fonts = preload("res://scripts/ui/source_font_registry.gd")
const Layout = preload("res://scripts/ui/title_scene_layout.gd")
const Documents = preload("res://scripts/ui/source_prefab_documents.gd")
const Feedback = preload("res://scripts/ui/text_button_feedback.gd")
var source_backed := false
var panel: ColorRect
var title_label: Label
var body_label: Label
var no_button: Button
var yes_button: Button
var canvas: Control
var layout := Layout.new()
var _guard: Callable
var _no: Callable
var _yes: Callable
var _panel_id := ""
var _buttons_id := ""
var _reference_height := 1080.0

func configure(data: Dictionary, on_no: Callable, on_yes: Callable,
		guard: Callable, play_click: Callable) -> bool:
	if canvas != null or not on_yes.is_valid(): return false
	var title := Layout.new()
	if not title.configure(data): return false
	_reference_height = title.reference_height
	var documents := Documents.resolve(data,"ModalWindow","Title")
	var owner := ""
	for document in documents:
		if document.get("object_type") == "GameObject" and document.fields.get("m_Name") == "ModalWindow":
			owner = str(document.file_id)
			document.fields.m_Name = "Canvas"
	if owner.is_empty(): return false
	documents.append({"object_type":"MonoBehaviour","file_id":"modal_source_scaler",
		"fields":{"m_GameObject":{"fileID":owner},"m_UiScaleMode":1,
			"m_MatchWidthOrHeight":1,"m_ReferenceResolution":{"y":_reference_height}}})
	if not layout.configure({"scenes":[{"name":"Title","documents":documents}]}): return false
	_panel_id = layout.resolve("DialogPanel")
	_buttons_id = layout.resolve("DialogPanel/Buttons")
	for path in ["DialogPanel","DialogPanel/Title","DialogPanel/Dialog","DialogPanel/Buttons",
			"DialogPanel/Buttons/NoButton","DialogPanel/Buttons/YesButton"]:
		if layout.resolve(path).is_empty(): return false
	if int(layout.field(_panel_id,"m_VerticalFit",0)) != 2: return false
	_guard=guard; _no=on_no; _yes=on_yes
	mouse_filter=Control.MOUSE_FILTER_STOP
	focus_mode=Control.FOCUS_NONE
	var shade := ColorRect.new()
	shade.color = Layout.color(layout.field(layout.root_id,"m_Color",{}))
	shade.mouse_filter=Control.MOUSE_FILTER_STOP
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	canvas=Control.new()
	canvas.mouse_filter=Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	panel=ColorRect.new()
	panel.name="DialogPanel"
	panel.color=Layout.color(layout.field(_panel_id,"m_Color",{}))
	panel.mouse_filter=Control.MOUSE_FILTER_STOP
	canvas.add_child(panel)
	title_label=_make_label("DialogPanel/Title","Quit Game")
	body_label=_make_label("DialogPanel/Dialog","Are you sure you want to quit the game?")
	no_button=_make_button("DialogPanel/Buttons/NoButton",false,play_click)
	yes_button=_make_button("DialogPanel/Buttons/YesButton",true,play_click)
	source_backed=true
	set_meta("layout_parity","native_preferred_measurement_not_verified_TMP")
	resized.connect(relayout)
	hide()
	relayout()
	return true

func _text_record(id: String) -> Dictionary:
	for component in layout.records[id].components:
		if component.has("m_fontAsset") and component.has("m_text"): return component
	return {}

func _style(control: Control, id: String) -> void:
	var record := _text_record(id)
	Fonts.shared().bind_control(control,record)
	control.add_theme_font_size_override("font_size",int(record.get("m_fontSize",32)))
	var tint := Layout.color(record.get("m_fontColor",{}))
	for state in ["font_color","font_hover_color","font_pressed_color","font_focus_color"]:
		control.add_theme_color_override(state,tint)
	# TMP's synthetic bold is not the Godot rasterizer. Retain the authored flag
	# and explicitly mark native emboldening as unverified presentation.
	if (int(record.get("m_fontStyle",0)) & 1) != 0:
		var bold := FontVariation.new()
		bold.base_font=control.get_theme_font("font")
		bold.variation_embolden=0.6
		control.add_theme_font_override("font",bold)
		control.set_meta("bold_parity","native_emboldening_not_verified_TMP")

func _make_label(path: String, text: String) -> Label:
	var label := Label.new()
	label.name=path.get_file()
	label.text=text
	label.mouse_filter=Control.MOUSE_FILTER_STOP
	label.horizontal_alignment=HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment=VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode=TextServer.AUTOWRAP_WORD_SMART
	panel.add_child(label)
	_style(label,layout.resolve(path))
	return label

func _make_button(path: String, accepting: bool, sound: Callable) -> Button:
	var button := Feedback.new()
	var id := layout.resolve(path)
	button.name=path.get_file()
	button.text=str(layout.field(id,"m_text",""))
	button.focus_mode=Control.FOCUS_NONE
	button.button_mask=MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE
	button.flat=true
	for state in ["normal","hover","pressed","focus","disabled"]:
		button.add_theme_stylebox_override(state,StyleBoxEmpty.new())
	panel.add_child(button)
	_style(button,id)
	button.configure(_choose.bind(accepting),sound,_admitted)
	return button

func _admitted() -> bool:
	return is_visible_in_tree() and not is_queued_for_deletion() and (not _guard.is_valid() or bool(_guard.call()))

func _choose(accepting: bool) -> void:
	if not _admitted(): return
	if accepting: _yes.call()
	elif _no.is_valid(): _no.call()
	close_dialog()

func show_dialog() -> void:
	if not source_backed: return
	show()
	relayout()

func close_dialog() -> void:
	hide()

func _preferred_height(label: Label, width: float) -> float:
	# Dynamic preferred height from current native shaping, not a stale serialized
	# prefab rect (Title scene overrides those driven heights to zero).
	var font := label.get_theme_font("font")
	return font.get_multiline_string_size(label.text,HORIZONTAL_ALIGNMENT_CENTER,width,
		label.get_theme_font_size("font_size"),-1,TextServer.BREAK_MANDATORY | TextServer.BREAK_WORD_BOUND |
		TextServer.BREAK_ADAPTIVE).y

func relayout() -> void:
	if not source_backed or size.y<=0: return
	var factor := size.y/_reference_height
	canvas.scale=Vector2.ONE*factor
	canvas.size=size/factor
	var padding: Dictionary=layout.field(_panel_id,"m_Padding",{})
	var left:=float(padding.get("m_Left",0))
	var right:=float(padding.get("m_Right",0))
	var top:=float(padding.get("m_Top",0))
	var bottom:=float(padding.get("m_Bottom",0))
	var width:=Layout.vector(layout.records[_panel_id].rect.m_SizeDelta).x
	var content_width:=width-left-right
	var gap:=float(layout.field(_panel_id,"m_Spacing",0))
	var title_height:=_preferred_height(title_label,content_width)
	var body_height:=_preferred_height(body_label,content_width)
	var no_id:=layout.resolve("DialogPanel/Buttons/NoButton")
	var yes_id:=layout.resolve("DialogPanel/Buttons/YesButton")
	var no_size:=Layout.vector(layout.records[no_id].rect.m_SizeDelta)
	var yes_size:=Layout.vector(layout.records[yes_id].rect.m_SizeDelta)
	var row_height:=maxf(no_size.y,yes_size.y)
	var height:=top+title_height+gap+body_height+gap+row_height+bottom
	panel.size=Vector2(width,height)
	panel.position=(canvas.size-panel.size)*.5
	title_label.position=Vector2(left,top)
	title_label.size=Vector2(content_width,title_height)
	body_label.position=Vector2(left,top+title_height+gap)
	body_label.size=Vector2(content_width,body_height)
	var button_gap:=float(layout.field(_buttons_id,"m_Spacing",0))
	var x:float=(width-no_size.x-yes_size.x-button_gap)*.5
	var y:=height-bottom-row_height
	no_button.position=Vector2(x,y+(row_height-no_size.y)*.5)
	no_button.size=no_size
	yes_button.position=Vector2(x+no_size.x+button_gap,y+(row_height-yes_size.y)*.5)
	yes_button.size=yes_size
