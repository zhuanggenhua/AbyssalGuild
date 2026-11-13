extends Panel
## Native, bounded information panel. Plain text only; no TMP/BBCode parsing.
## The board decides placement and priority; this never replaces modal actions.
var header: Label
var body: RichTextLabel
var descriptor: Dictionary = {}
var font_scale: float = 1.0
var bottom_anchor := Vector2.ZERO
const PADDING = 20.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var background := StyleBoxFlat.new()
	background.bg_color = Color(0, 0, 0, 0.9019608)
	background.border_color = Color("78969e")
	background.set_border_width_all(0)
	background.set_corner_radius_all(0)
	add_theme_stylebox_override("panel", background)
	header = Label.new()
	header.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.clip_text = true
	header.max_lines_visible = 2
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(header)
	body = RichTextLabel.new()
	body.bbcode_enabled = false
	body.fit_content = false
	body.scroll_active = true
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(body)
	resized.connect(_layout_content)
	set_descriptor({})

func configure_source_text_color(record: Dictionary) -> bool:
	# Both native text nodes represent the one source InfoPanel.infoText TMP.
	# Apply its vertex color, not container modulation (which would tint the
	# independent panel background/action). Missing records restore native theme.
	header.remove_theme_color_override("font_color")
	body.remove_theme_color_override("default_color")
	var value = record.get("m_fontColor")
	if not value is Dictionary: return false
	for channel in ["r", "g", "b", "a"]:
		if not value.get(channel) is int and not value.get(channel) is float: return false
		if not is_finite(float(value[channel])): return false
	var color := Color(float(value.r), float(value.g), float(value.b), float(value.a))
	header.add_theme_color_override("font_color", color)
	body.add_theme_color_override("default_color", color)
	return true

func set_descriptor(value: Dictionary) -> void:
	if descriptor == value and not value.is_empty(): return # Preserve scroll on unchanged frames.
	descriptor = value.duplicate(true)
	header.text = "[%s]" % str(value.get("header", "")) if not str(value.get("header", "")).is_empty() else ""
	body.text = str(value.get("body", ""))
	visible = not value.is_empty()
	body.scroll_to_line(0)
	_layout_content()

## A viewport-logical rectangle, already accounting for the HUD's available area.
## Scrollable body preserves complete information at narrow sizes / large UI scale.
func set_bounds(rect: Rect2, scale_factor: float = 1.0) -> void:
	if not rect.position.is_finite() or not rect.size.is_finite(): return
	font_scale = clampf(scale_factor, 0.5, 3.0) if is_finite(scale_factor) else 1.0
	bottom_anchor = rect.position
	position = rect.position
	size = Vector2(maxf(0, rect.size.x), maxf(0, rect.size.y))
	_layout_content()

func _layout_content() -> void:
	if header == null or body == null: return
	var width: float = maxf(0, size.x-PADDING*2)
	header.add_theme_font_size_override("font_size", 34)
	body.add_theme_font_size_override("normal_font_size", 30)
	var header_font := header.get_theme_font("font")
	var body_font := body.get_theme_font("normal_font")
	var header_height: float = header_font.get_multiline_string_size(header.text, HORIZONTAL_ALIGNMENT_LEFT, width, 34).y if not header.text.is_empty() else 0.0
	var body_height: float = body_font.get_multiline_string_size(body.text, HORIZONTAL_ALIGNMENT_LEFT, width, 30).y if not body.text.is_empty() else 0.0
	var action_height: float = 40.0 if not str(descriptor.get("action", "")).is_empty() else 0.0
	var preferred := minf(header_height+body_height+PADDING*2+action_height, maxf(60, bottom_anchor.y-30))
	if not is_equal_approx(size.y, preferred): size.y = preferred
	position = bottom_anchor-Vector2(0, preferred)
	header.position = Vector2(PADDING, PADDING)
	header.size = Vector2(width, header_height)
	body.position = Vector2(PADDING, PADDING+header_height)
	body.size = Vector2(width, maxf(0, preferred-header_height-PADDING*2-action_height))
	body.visible = body_height > 0 and width > 0 and body.size.y > 0
