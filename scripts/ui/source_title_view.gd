extends Control
## Source scene shell only. Transactions and their callbacks belong to the caller.
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
	control.add_theme_font_size_override("font_size", int(layout.field(id, "m_fontSize", 24)))
	var tint: Dictionary = layout.field(id, "m_fontColor", {})
	control.add_theme_color_override("font_color", Layout.color(tint))
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
	# The referenced TMP font is unresolved. Native glyph metrics are not parity.

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
