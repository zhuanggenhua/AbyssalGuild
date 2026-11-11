extends Panel
## Native, bounded information panel. Plain text only; no TMP/BBCode parsing.
## The board decides placement and priority; this never replaces modal actions.
var header: Label
var body: RichTextLabel
var descriptor: Dictionary = {}
var font_scale: float = 1.0
const PADDING = 12.0

func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_contents = true
	var background := StyleBoxFlat.new()
	background.bg_color = Color("172b32")
	background.border_color = Color("78969e")
	background.set_border_width_all(1)
	background.set_corner_radius_all(6)
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
	position = rect.position
	size = Vector2(maxf(0, rect.size.x), maxf(0, rect.size.y))
	_layout_content()

func _layout_content() -> void:
	if header == null or body == null: return
	var padding: float = minf(PADDING, minf(size.x, size.y) / 2.0)
	var width: float = maxf(0, size.x - padding * 2)
	var height: float = maxf(0, size.y - padding * 2)
	var header_size: int = maxi(1, roundi(22 * font_scale))
	var body_size: int = maxi(1, roundi(18 * font_scale))
	header.add_theme_font_size_override("font_size", header_size)
	body.add_theme_font_size_override("normal_font_size", body_size)
	var title_height: float = minf(height, ThemeDB.fallback_font.get_height(header_size) * 2)
	header.position = Vector2(padding, padding)
	header.size = Vector2(width, title_height)
	body.position = Vector2(padding, padding + title_height)
	body.size = Vector2(width, maxf(0, height - title_height))
	body.visible = height > title_height
