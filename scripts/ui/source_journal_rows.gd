extends Control
## MenuView's persistent TextButton children and moving VerticalLayoutGroup padding.
## Native text shaping is an explicitly unaccepted fallback, NOT TMP layout parity.
const Fonts = preload("res://scripts/ui/source_font_registry.gd")
signal extent_changed(height: float)
signal meta_hover_started(meta: Variant)
signal meta_hover_ended(meta: Variant)
signal meta_clicked(meta: Variant)
var can_click: Callable
var preferred_height := 20.0
var rows: Dictionary = {}
var ordered_keys: Array[String] = []
var content_width := 400.0
var binding: Dictionary = {}
var default_font_id := ""
var registry: RefCounted

class Item extends Control:
	var owner_rows: Control
	var descriptor: Dictionary = {}
	var label := RichTextLabel.new()
	var hovered := false
	var pressed_button := 0
	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_PASS
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.bbcode_enabled = true
		label.scroll_active = false
		label.fit_content = true
		label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		label.add_theme_stylebox_override("normal", StyleBoxEmpty.new())
		label.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
		add_child(label)
		mouse_entered.connect(enter)
		mouse_exited.connect(leave)
		visibility_changed.connect(func():
			if not is_visible_in_tree(): leave())
	func meta() -> Variant:
		return {"journal_group":descriptor.group} if not str(descriptor.get("group", "")).is_empty() else str(descriptor.get("id", ""))
	func enter() -> void:
		if hovered or not is_visible_in_tree(): return
		hovered = true
		render()
		owner_rows.meta_hover_started.emit(meta())
	func leave() -> void:
		pressed_button = 0
		if not hovered: return
		hovered = false
		render()
		owner_rows.meta_hover_ended.emit(meta())
	func render() -> void:
		label.clear()
		if hovered: label.push_underline()
		label.add_text(str(descriptor.get("text", "")))
		if descriptor.get("unread", false):
			label.push_color(Color.RED)
			label.add_text(" ●")
			label.pop()
		if hovered: label.pop()
	func _gui_input(event: InputEvent) -> void:
		if not event is InputEventMouseButton or event.button_index not in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]: return
		if event.pressed:
			pressed_button = event.button_index
			return
		var admitted: bool = pressed_button == event.button_index and Rect2(Vector2.ZERO, size).has_point(event.position)
		pressed_button = 0
		if admitted and event.button_index == MOUSE_BUTTON_LEFT and owner_rows.can_click.is_valid(): admitted = bool(owner_rows.can_click.call())
		if admitted and not str(descriptor.get("group", "")).is_empty(): owner_rows.meta_clicked.emit(meta())

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	set_meta("layout_parity", "native_wrapping_fallback_not_TMP_preferred_metrics")

func configure(font_registry: RefCounted = null) -> void:
	registry = font_registry if font_registry != null else Fonts.shared()
	# Runtime font identity is read from the local caller-owned manifest, never
	# embedded as an asset identifier in the distributable project.
	default_font_id = str(registry.manifest.get("tmp_default_font_guid", ""))
	binding = registry.resolve(default_font_id)
	set_meta("source_font_guid", default_font_id)
	set_meta("source_font_status", binding.get("status", "missing_source_font_binding"))
	for item in rows.values(): _bind_font(item)

func _bind_font(item: Item) -> void:
	item.label.remove_theme_font_override("normal_font")
	if binding.get("font") != null: item.label.add_theme_font_override("normal_font", binding.font)
	item.label.set_meta("source_font_guid", default_font_id)
	item.label.set_meta("source_font_status", binding.get("status", "missing_source_font_binding"))

func set_rows(descriptors: Array, header_color: Color = Color.WHITE) -> void:
	if registry == null: configure()
	var next: Array[String] = []
	for descriptor in descriptors:
		var group := str(descriptor.get("group", ""))
		var id := str(descriptor.get("id", ""))
		# Source has no invented empty-list placeholder TextButton.
		if group.is_empty() and id.is_empty(): continue
		var key := "group:" + group if not group.is_empty() else "item:" + id
		if next.has(key): continue
		next.append(key)
		var item: Item = rows.get(key)
		if item == null:
			item = Item.new()
			item.owner_rows = self
			rows[key] = item
			add_child(item)
			_bind_font(item)
		var changed: bool = item.descriptor.get("text") != descriptor.get("text") or item.descriptor.get("unread") != descriptor.get("unread")
		item.descriptor = descriptor.duplicate(true)
		item.label.add_theme_font_size_override("normal_font_size", 35 if not group.is_empty() else 30)
		item.label.add_theme_color_override("default_color", header_color if not group.is_empty() else Color.WHITE)
		if changed: item.render()
		item.show()
	for key in rows:
		if not next.has(key): rows[key].hide()
	ordered_keys = next
	layout_rows()

func set_content_width(width: float) -> void:
	if not is_finite(width): return
	content_width = maxf(width, 0)
	layout_rows()

func layout_rows() -> void:
	var y := 10.0
	var available := maxf(0, content_width - 40)
	for key in ordered_keys:
		var item: Item = rows[key]
		# Native preferred width/height deliberately remain tagged fallback.
		item.label.autowrap_mode = TextServer.AUTOWRAP_OFF
		item.label.size = Vector2(available, 0)
		var width := minf(available, float(item.label.get_content_width()))
		item.label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.label.size = Vector2(width, 0)
		var height := float(item.label.get_content_height())
		item.position = Vector2(20, y)
		item.size = Vector2(width, height)
		item.label.size = item.size
		y += height + 10
	preferred_height = y + 10 - (10 if not ordered_keys.is_empty() else 0)
	size = Vector2(content_width, preferred_height)
	extent_changed.emit(preferred_height)

func get_parsed_text() -> String:
	var texts: PackedStringArray = []
	for key in ordered_keys:
		var item: Item = rows[key]
		texts.append(item.label.get_parsed_text())
	return "\n".join(texts)

func reset_rows() -> void:
	for item in rows.values():
		item.leave()
		remove_child(item)
		item.queue_free()
	rows.clear()
	ordered_keys.clear()
	layout_rows()
