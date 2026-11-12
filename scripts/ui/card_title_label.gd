extends RefCounted
## Single-line title fitting. Source bounds/margins, native font metrics, not TMP.

static func content_rect(record: Dictionary, fallback_size: Vector2) -> Rect2:
	var source: Dictionary = record.get("rect_size", {})
	var size := Vector2(_positive(source.get("x"), fallback_size.x), _positive(source.get("y"), fallback_size.y))
	var margin: Dictionary = record.get("margin", {})
	var left: float = _nonnegative(margin.get("x"))
	var top: float = _nonnegative(margin.get("y"))
	var right: float = _nonnegative(margin.get("z"))
	var bottom: float = _nonnegative(margin.get("w"))
	# Malformed or older private metadata must not create zero/negative font scale.
	if left + right >= size.x: left = 0.0; right = 0.0
	if top + bottom >= size.y: top = 0.0; bottom = 0.0
	return Rect2(Vector2(-size.x / 2.0 + left, -size.y / 2.0 + bottom), size - Vector2(left + right, top + bottom))

static func fit(label: Label3D, title: String, record: Dictionary, fallback_size: Vector2) -> void:
	# The locked card/pack TMP components disable wrapping and enable auto-sizing.
	# Native line height is the size cap; width may shrink it further. TMP point-size
	# limits are kept in the manifest, but have no one-to-one Godot font conversion.
	label.text = title.replace("\r\n", " ").replace("\n", " ").replace("\r", " ")
	label.font = ThemeDB.fallback_font
	label.font_size = 36
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.outline_size = 0
	var rect := content_rect(record, fallback_size)
	var pixels := label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size)
	label.pixel_size = minf(rect.size.x / maxf(pixels.x, 1.0), rect.size.y / maxf(label.font.get_height(label.font_size), 1.0))
	label.width = rect.size.x / label.pixel_size
	var center := rect.get_center()
	match int(record.get("horizontal_alignment", 2)):
		1:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
			center.x = rect.position.x
		4:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			center.x = rect.end.x
		_:
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.offset = center / label.pixel_size

static func _positive(value: Variant, fallback: float) -> float:
	return float(value) if (value is float or value is int) and is_finite(float(value)) and float(value) > 0 else maxf(fallback, 0.001)

static func _nonnegative(value: Variant) -> float:
	return float(value) if (value is float or value is int) and is_finite(float(value)) and float(value) >= 0 else 0.0
