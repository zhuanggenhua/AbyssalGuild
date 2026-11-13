extends Control
## Source scene shell only. Transactions and their callbacks belong to the caller.
const SourceFonts = preload("res://scripts/ui/source_font_registry.gd")
const Layout = preload("res://scripts/ui/title_scene_layout.gd")
var layout = Layout.new()
var source_backed := false
var home: Control
var preferences_overlay: Control
var saves_overlay: Control
var preference_content: Control
var saves_content: Control
var surfaces: Dictionary = {}
var nodes: Dictionary = {}
var canvas: Control
const PATHS := {"new": "MenuPanel/NewGame", "load": "MenuPanel/LoadGame", "options": "MenuPanel/GameOptions", "quit": "MenuPanel/QuitGame", "duration_label": "GameplayPrefsUI/MainPanel/DurationLabel", "duration": "GameplayPrefsUI/MainPanel/DurationSlider", "friendly": "GameplayPrefsUI/MainPanel/IsFriendlyToggle", "confirm": "GameplayPrefsUI/MainPanel/Footer/ConfirmButton", "cancel": "GameplayPrefsUI/MainPanel/Footer/CancelButton", "saves_close": "SavedGamesUI/MainPanel/Footer/CloseButton", "saves_clear": "SavedGamesUI/MainPanel/Footer/ClearButton"}

func configure(data: Dictionary, assets) -> bool:
	if canvas != null: return false # One construction, explicit transaction ownership.
	source_backed = layout.configure(data)
	if not source_backed: return false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	canvas = Control.new()
	canvas.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(canvas)
	_build(layout.root_id, canvas, assets)
	home = nodes.get(layout.resolve("MenuPanel"))
	preferences_overlay = nodes.get(layout.resolve("GameplayPrefsUI"))
	saves_overlay = nodes.get(layout.resolve("SavedGamesUI"))
	preference_content = nodes.get(layout.resolve("GameplayPrefsUI/MainPanel"))
	saves_content = nodes.get(layout.resolve("SavedGamesUI/MainPanel/ScrollView/Viewport/Content"))
	if home == null or preferences_overlay == null or saves_overlay == null: return false
	preferences_overlay.hide()
	saves_overlay.hide()
	resized.connect(relayout)
	relayout()
	return true

func _build(parent_id: String, parent: Control, assets) -> void:
	for id in layout.children.get(parent_id, []):
		if not layout.records.has(id): continue
		var record: Dictionary = layout.records[id]
		# External prefab instances and transition/modal controllers stay caller-owned.
		if record.name in ["ScreenFader"]: continue
		var control := Control.new()
		control.name = record.name
		control.mouse_filter = Control.MOUSE_FILTER_IGNORE
		parent.add_child(control)
		nodes[id] = control
		var tint: Variant = layout.field(id, "m_Color")
		if tint != null and layout.field(id, "m_Sprite") != null:
			var sprite: Dictionary = layout.field(id, "m_Sprite", {})
			var texture: Texture2D = assets.texture(str(sprite.get("guid", ""))) if assets != null else null
			var surface: Control
			if texture != null:
				var image := TextureRect.new()
				image.texture = texture
				image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
				image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED if bool(layout.field(id, "m_PreserveAspect", false)) else TextureRect.STRETCH_SCALE
				image.modulate = Layout.color(tint)
				surface = image
			elif not sprite.has("guid"):
				var color := ColorRect.new()
				color.color = Layout.color(tint)
				surface = color
			if surface != null:
				control.add_child(surface)
				surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
				surface.mouse_filter = Control.MOUSE_FILTER_STOP if bool(layout.field(id, "m_RaycastTarget", false)) else Control.MOUSE_FILTER_IGNORE
				surfaces[id] = surface
		var text: Variant = layout.field(id, "m_text")
		if text != null:
			var label := Label.new()
			label.text = str(text)
			label.mouse_filter = Control.MOUSE_FILTER_IGNORE
			control.add_child(label)
			label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			_style(label, id)
		_build(id, control, assets)

func mount(role: String, control: Control) -> bool:
	var id := layout.resolve(str(PATHS.get(role, "")))
	if not PATHS.has(role) or not nodes.has(id): return false
	for child in nodes[id].get_children(): child.hide()
	if control.get_parent() != null: control.reparent(nodes[id])
	else: nodes[id].add_child(control)
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_style(control, id)
	return true

func _style(control: Control, id: String) -> void:
	# Bind this exact source TMP component, not a view-wide assumed font.
	SourceFonts.shared().bind_control(control, text_record(id))
	control.add_theme_font_size_override("font_size", int(layout.field(id, "m_fontSize", 24)))
	var tint: Dictionary = layout.field(id, "m_fontColor", {})
	control.add_theme_color_override("font_color", Layout.color(tint))
	for state in ["font_hover_color", "font_pressed_color", "font_focus_color"]: control.add_theme_color_override(state, Layout.color(tint))
	if control is Button:
		control.flat = true
		control.custom_minimum_size = Vector2.ZERO
		for state in ["normal", "hover", "pressed", "focus", "disabled"]:
			control.add_theme_stylebox_override(state, StyleBoxEmpty.new())
	if control is Label:
		var horizontal := int(layout.field(id, "m_HorizontalAlignment", 1))
		control.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER if horizontal == 2 else (HORIZONTAL_ALIGNMENT_RIGHT if horizontal == 4 else HORIZONTAL_ALIGNMENT_LEFT)
		var vertical := int(layout.field(id, "m_VerticalAlignment", 256))
		control.vertical_alignment = VERTICAL_ALIGNMENT_CENTER if vertical == 512 else (VERTICAL_ALIGNMENT_BOTTOM if vertical == 1024 else VERTICAL_ALIGNMENT_TOP)
	# Accurate font identity does not establish TMP shaping/SDF rendering parity.

func text_record(id: String) -> Dictionary:
	for component in layout.records.get(id, {}).get("components", []):
		if component.has("m_fontAsset") and component.has("m_text"):
			return component
	return {}

func set_overlay(page: String, active: bool) -> void:
	if page == "preferences" and preferences_overlay != null: preferences_overlay.visible = active
	elif page == "saves" and saves_overlay != null: saves_overlay.visible = active
	# Deliberately do not hide Home or change the other independent source overlay.

func relayout() -> void:
	if not source_backed or canvas == null or size.y <= 0: return
	var factor: float = size.y / layout.reference_height
	canvas.scale = Vector2.ONE * factor
	canvas.size = size / factor
	_layout_children(layout.root_id, canvas)

func _layout_children(parent_id: String, parent: Control) -> void:
	var group: Dictionary = {}
	# Only the two audited vertical groups use driven child rectangles.
	if parent_id in [layout.resolve("MenuPanel"), layout.resolve("GameplayPrefsUI/MainPanel")]: group = layout.vertical_rects(parent_id, parent.size)
	for id in layout.children.get(parent_id, []):
		if not nodes.has(id): continue
		var rect: Rect2 = group.get(id, layout.rect(id, parent.size))
		nodes[id].position = rect.position
		nodes[id].size = rect.size
		_layout_children(id, nodes[id])

func bind_source_controls(data: Dictionary) -> Dictionary:
	var documents: Array = []
	for scene in data.get("scenes", []):
		if scene.get("name") == "Title": documents = scene.get("documents", [])
	for document in documents:
		var fields: Dictionary = document.get("fields", {})
		if not fields.has("durationSlider") or not fields.has("isFriendlyToggle"): continue
		var metadata = preload("res://scripts/ui/source_control_metadata.gd")
		return {"duration": metadata.slider(documents, fields.durationSlider), "friendly": metadata.text_toggle(documents, fields.isFriendlyToggle)}
	return {}

func install_saved_rows(data: Dictionary, selector: OptionButton, load_action: Callable, archive_action: Callable, guard: Callable, sound: Callable):
	var documents: Array = []
	for prefab in data.get("referenced_prefabs",[]):
		if prefab.get("name") == "SavedGameSlot": documents = prefab.get("documents",[])
	var host_id := layout.resolve("SavedGamesUI/MainPanel/ScrollView")
	var content_id := layout.resolve("SavedGamesUI/MainPanel/ScrollView/Viewport/Content")
	if not nodes.has(host_id): return null
	var host = preload("res://scripts/ui/source_saved_slot_host.gd").new()
	host.name = "SourceSavedRows"
	host.play_click = sound
	var scrollbar_id := layout.resolve("SavedGamesUI/MainPanel/ScrollView/ScrollbarVertical")
	var fields := {"m_Padding":layout.field(content_id,"m_Padding",{}),"m_Spacing":layout.field(content_id,"m_Spacing",0),"scrollbar_width":Layout.vector(layout.records.get(scrollbar_id,{}).get("rect",{}).get("m_SizeDelta",{})).x}
	fields["drag_threshold"] = layout.field(layout.resolve("EventSystem"),"m_DragThreshold",10)
	fields["scrollrect"] = {}
	for key in ["m_Horizontal","m_Vertical","m_MovementType","m_Elasticity","m_Inertia","m_DecelerationRate","m_ScrollSensitivity"]:
		fields.scrollrect[key] = layout.field(host_id,key,null)
	for scene in data.get("scenes",[]):
		if scene.get("name")=="Title":
			fields["scrollbar"] = preload("res://scripts/ui/source_scrollbar_adapter.gd").metadata(scene.get("documents",[]),layout.field(host_id,"m_VerticalScrollbar",{}))
			for document in scene.get("documents",[]):
				var input_fields: Dictionary=document.get("fields",{})
				if input_fields.has("m_ScrollDeltaPerTick"):
					fields["scroll_delta_per_tick"]=input_fields.m_ScrollDeltaPerTick
					fields.scrollbar["repeat_delay"]=input_fields.m_MoveRepeatDelay
					fields.scrollbar["repeat_rate"]=input_fields.m_MoveRepeatRate
	if not host.configure(documents,fields,selector,load_action,archive_action,guard):
		host.free()
		return null
	for child in nodes[host_id].get_children(): child.hide()
	nodes[host_id].add_child(host)
	host.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	return host

func reflow_saved_footer(controls: Array) -> Dictionary:
	var id := layout.resolve("SavedGamesUI/MainPanel/Footer")
	if not nodes.has(id): return {"ok":false}
	var widths: Array = []
	var heights: Array = []
	for control in controls:
		widths.append(control.get_theme_font("font").get_string_size(control.text,HORIZONTAL_ALIGNMENT_LEFT,-1,control.get_theme_font_size("font_size")).x)
		var source_height := 0.0
		for child_id in layout.children.get(id,[]):
			if nodes.get(child_id) == control.get_parent(): source_height = Layout.vector(layout.records[child_id].rect.m_SizeDelta).y
		heights.append(source_height)
	var padding: Dictionary = layout.field(id,"m_Padding",{})
	var result = preload("res://scripts/ui/source_saved_layout.gd").footer(nodes[id].size,widths,heights,Vector4(float(padding.get("m_Left",0)),float(padding.get("m_Top",0)),float(padding.get("m_Right",0)),float(padding.get("m_Bottom",0))),float(layout.field(id,"m_Spacing",0)))
	if result.ok:
		for index in controls.size():
			controls[index].get_parent().position = result.rectangles[index].position
			controls[index].get_parent().size = result.rectangles[index].size
	result.measurement_provenance = "native_font_measurement_not_verified_TMP_preferred_width"
	return result
