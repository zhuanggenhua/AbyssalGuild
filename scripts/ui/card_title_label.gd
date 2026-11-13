extends RefCounted
## Source-bounded single-line TMP fitting, with explicit unsupported fallback.
const TMPLayout = preload("res://scripts/ui/tmp_single_line_layout.gd")
const Baseline = preload("res://scripts/ui/tmp_title_baseline.gd")
const Fonts = preload("res://scripts/ui/source_font_registry.gd")

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
	# Prepare an explicit native fallback for unsupported metadata/text first.
	# A supported source branch below replaces this native width/height fit with
	# the authored TMP min/max/base point size, quantized search and world scale.
	# That source layout selection does not claim native glyph/SDF raster parity.
	label.text = title.replace("\r\n", " ").replace("\n", " ").replace("\r", " ")
	if label.font == null:
		label.font = ThemeDB.fallback_font
	label.font_size = 36
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.outline_size = 0
	var rect := content_rect(record, fallback_size)
	var pixels := label.font.get_string_size(label.text, HORIZONTAL_ALIGNMENT_LEFT, -1, label.font_size)
	label.pixel_size = minf(rect.size.x / maxf(pixels.x, 1.0), rect.size.y / maxf(label.font.get_height(label.font_size), 1.0))
	var binding: Dictionary = Fonts.shared().resolve(Fonts.font_guid(record))
	var fitted := TMPLayout.fit(title, record, binding.get("source_metrics", {}), rect.size)
	# Measuring scaled source metrics is supported by TMPLayout, but this native
	# raster branch cannot faithfully reproduce per-element scaling. Admit only
	# the verified unit-scale face/elements; do not mislabel fallback as parity.
	if fitted.ok and not _native_unit_scales(binding.get("source_metrics", {})):
		fitted = {"ok": false, "reason": "unsupported_native_raster_scale"}
	label.set_meta("source_layout_result", fitted)
	if binding.get("font") != null and fitted.ok:
		# Raster resolution is not the chosen point size. Physical size is controlled
		# solely by source fit and world-space 0.1 multiplier, never native width.
		label.font_size = maxi(1, roundi(float(binding.source_metrics.m_FaceInfo.m_PointSize)))
		label.pixel_size = float(fitted.point_size) * (1.0 if bool(record.is_orthographic) else 0.1) / label.font_size
		label.set_meta("source_layout_status", "source_ascii_autosize_native_raster")
	else:
		label.set_meta("source_layout_status", "unsupported_native_fallback")
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
	var baseline := {"ok": false, "reason": "unsupported_source_layout"}
	if binding.get("font") != null and fitted.ok:
		baseline = Baseline.apply(label, record, binding.source_metrics, float(fitted.point_size), rect.get_center().y)
	label.set_meta("source_baseline_result", baseline)

static func _positive(value: Variant, fallback: float) -> float:
	return float(value) if (value is float or value is int) and is_finite(float(value)) and float(value) > 0 else maxf(fallback, 0.001)

static func _nonnegative(value: Variant) -> float:
	return float(value) if (value is float or value is int) and is_finite(float(value)) and float(value) >= 0 else 0.0

static func _native_unit_scales(metrics: Dictionary) -> bool:
	if float(metrics.get("m_FaceInfo", {}).get("m_Scale", 0)) != 1.0:
		return false
	for key in ["m_GlyphTable", "m_CharacterTable"]:
		if not metrics.get(key) is Array or metrics[key].is_empty(): return false
		for row in metrics[key]:
			if float(row.get("m_Scale", 0)) != 1.0: return false
	return true
