extends RefCounted
## Exact bounded branch of Unity 6000.5.4f1 TMP: plain ASCII, normal style,
## no wrapping/width compression, static source glyph metrics, overflow allowed.
## This measures layout, not Godot glyph rasterization or TMP SDF pixels.
static func unsupported(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}

static func measure(text: String, record: Dictionary, metrics: Dictionary, point_size: float) -> Dictionary:
	if text.strip_edges().is_empty(): return unsupported("empty_or_whitespace_only")
	for key in ["is_orthographic", "character_spacing", "word_spacing", "enable_kerning", "char_width_max_adjustment"]:
		if not record.has(key): return unsupported("missing_source_" + key)
	if int(record.get("font_weight", 400)) != 400 or int(record.get("font_style", -1)) != 0 or int(record.get("word_wrap", -1)) != 0 or int(record.get("overflow_mode", -1)) != 0 or float(record.char_width_max_adjustment) != 0:
		return unsupported("unsupported_style_wrap_overflow_or_compression")
	if int(record.get("horizontal_alignment", 2)) not in [1, 2, 4]: return unsupported("unsupported_alignment")
	if metrics.get("m_AtlasPopulationMode", -1) != 0 or not metrics.has("normalSpacingOffset"): return unsupported("missing_static_metrics_or_spacing")
	var face: Dictionary = metrics.get("m_FaceInfo", {})
	if float(face.get("m_PointSize", 0)) <= 0: return unsupported("missing_face")
	var chars := {}
	var glyphs := {}
	for row in metrics.get("m_CharacterTable", []): chars[int(row.m_Unicode)] = row
	for row in metrics.get("m_GlyphTable", []): glyphs[int(row.m_Index)] = row
	var sequence: Array = []
	for c in text:
		var code := c.unicode_at(0)
		if code < 32 or code > 126 or c in ["<", ">"]: return unsupported("unsupported_text")
		if not chars.has(code) or not glyphs.has(int(chars[code].m_GlyphIndex)): return unsupported("missing_glyph")
		sequence.append({"code": code, "char": chars[code], "glyph": glyphs[int(chars[code].m_GlyphIndex)]})
	var pairs := {}
	if bool(record.enable_kerning):
		for pair in metrics.get("m_FontFeatureTable", {}).get("m_GlyphPairAdjustmentRecords", []):
			pairs["%d:%d" % [pair.m_FirstAdjustmentRecord.m_GlyphIndex, pair.m_SecondAdjustmentRecord.m_GlyphIndex]] = pair
	var ortho := 1.0 if bool(record.is_orthographic) else 0.1
	var base := point_size / float(face.m_PointSize) * float(face.m_Scale) * ortho
	var em := point_size * 0.01 * ortho
	var advance := 0.0
	var width := 0.0
	var height := 0.0
	for i in sequence.size():
		var item: Dictionary = sequence[i]
		var scale := base * float(item.char.m_Scale) * float(item.glyph.m_Scale)
		var adjustment := 0.0
		var spacing := float(record.character_spacing)
		for side in [-1, 1]:
			var neighbor: int = i + side
			if neighbor < 0 or neighbor >= sequence.size(): continue
			var left: Dictionary = sequence[mini(i, neighbor)].glyph
			var right: Dictionary = sequence[maxi(i, neighbor)].glyph
			var pair: Dictionary = pairs.get("%d:%d" % [left.m_Index, right.m_Index], {})
			if pair.is_empty(): continue
			var value: Dictionary = pair["m_FirstAdjustmentRecord" if side == 1 else "m_SecondAdjustmentRecord"].m_GlyphValueRecord
			# Nonzero placement changes ascenders/baselines; do not approximate.
			if float(value.m_YPlacement) != 0 or float(value.m_YAdvance) != 0: return unsupported("vertical_pair_adjustment")
			adjustment += float(value.m_XAdvance)
			if int(pair.m_FeatureLookupFlags) != 0: return unsupported("pair_feature_flags")
		var horizontal := float(item.glyph.m_Metrics.m_HorizontalAdvance)
		if int(item.code) != 32:
			width = maxf(width, absf(advance) + horizontal * scale)
			height = maxf(height, (float(face.m_AscentLine) - float(face.m_DescentLine)) * scale)
		advance += (horizontal + adjustment) * scale + (float(metrics.normalSpacingOffset) + spacing) * em
		if int(item.code) == 32: advance += float(record.word_spacing) * em
	return {"ok": true, "width": width, "height": height, "advance": advance}

static func fit(text: String, record: Dictionary, metrics: Dictionary, bounds: Vector2) -> Dictionary:
	for key in ["font_size", "font_size_min", "font_size_max", "auto_size"]:
		if not record.has(key): return unsupported("missing_source_" + key)
	var lower := float(record.font_size_min)
	var upper := float(record.font_size_max)
	if lower <= 0 or upper < lower: return unsupported("invalid_size_limits")
	var point := clampf(float(record.get("font_size_base", record.font_size)), lower, upper) if bool(record.auto_size) else float(record.font_size)
	var result: Dictionary
	for iteration in 101:
		result = measure(text, record, metrics, point)
		if not result.ok: return result
		var overflow: bool = result.width > bounds.x + 0.0001 or result.height > bounds.y + 0.0001
		if bool(record.auto_size) and iteration < 100:
			if overflow and point > float(record.font_size_min):
				upper = point
				point = maxf(float(int((point - maxf((point - lower) / 2.0, 0.05)) * 20.0 + 0.5)) / 20.0, float(record.font_size_min))
				continue
			if upper - lower > 0.051 and point < float(record.font_size_max):
				lower = point
				point = minf(float(int((point + maxf((upper - point) / 2.0, 0.05)) * 20.0 + 0.5)) / 20.0, float(record.font_size_max))
				continue
		result.merge({"point_size": point, "overflow": overflow, "iterations": iteration + 1})
		return result
	return unsupported("iteration_limit")
