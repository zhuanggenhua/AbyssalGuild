extends RefCounted
## Bounded TMP Middle baseline correction, not an SDF rasterizer.
static func source_baseline(record: Dictionary, metrics: Dictionary, point: float, center_y: float) -> Dictionary:
	if int(record.get("vertical_alignment", 0)) != 512:
		return {"ok": false, "reason": "unsupported_vertical_alignment"}
	var pivot: Dictionary = record.get("rect_pivot", {})
	if float(pivot.get("x", -1)) != 0.5 or float(pivot.get("y", -1)) != 0.5:
		return {"ok": false, "reason": "unsupported_or_missing_pivot"}
	var face: Dictionary = metrics.get("m_FaceInfo", {})
	if float(face.get("m_PointSize", 0)) <= 0:
		return {"ok": false, "reason": "missing_source_face"}
	# The admitted title branch uses one static face and unit glyph/character scales.
	for rows in [metrics.get("m_GlyphTable", []), metrics.get("m_CharacterTable", [])]:
		for row in rows:
			if float(row.get("m_Scale", 0)) != 1.0:
				return {"ok": false, "reason": "nonunit_element_scale"}
	var scale := point / float(face.m_PointSize) * float(face.m_Scale) * (1.0 if bool(record.is_orthographic) else 0.1)
	var ascent := float(face.m_AscentLine) * scale
	var descent := float(face.m_DescentLine) * scale
	return {"ok": true, "baseline": center_y - (ascent + descent) / 2.0, "ascent": ascent, "descent": descent}

static func apply(label: Label3D, record: Dictionary, metrics: Dictionary, point: float, center_y: float) -> Dictionary:
	var result := source_baseline(record, metrics, point, center_y)
	if not result.ok: return result
	if label.font == null or label.pixel_size <= 0 or label.vertical_alignment != VERTICAL_ALIGNMENT_CENTER or label.autowrap_mode != TextServer.AUTOWRAP_OFF or label.uppercase:
		return {"ok": false, "reason": "unsupported_native_label"}
	if label.text_direction == TextServer.DIRECTION_RTL:
		return {"ok": false, "reason": "unsupported_native_label"}
	# Same native font/size and single-line shaping backend as Label3D. Godot's
	# CENTER baseline = center + half(lineHeight) - ascent (label_3d.cpp574/608).
	var line := TextLine.new()
	line.direction = label.text_direction
	line.add_string(label.text, label.font, label.font_size, label.language if not label.language.is_empty() else TranslationServer.get_locale())
	var native_relative := (line.get_size().y / 2.0 - line.get_line_ascent()) * label.pixel_size
	var delta: float = result.baseline - (center_y + native_relative)
	label.offset.y += delta / label.pixel_size
	result["native_baseline_before"] = center_y + native_relative
	result["offset_delta"] = delta
	result["native_baseline_after"] = center_y + native_relative + delta
	return result
