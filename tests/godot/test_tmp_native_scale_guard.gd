extends SceneTree
const Title = preload("res://scripts/ui/card_title_label.gd")
const Fonts = preload("res://scripts/ui/source_font_registry.gd")
func _init() -> void:
	var metrics := {"m_AtlasPopulationMode":0,"normalSpacingOffset":0,"m_FaceInfo":{"m_PointSize":10,"m_Scale":1,"m_AscentLine":8,"m_DescentLine":-2},"m_CharacterTable":[{"m_Unicode":65,"m_GlyphIndex":1,"m_Scale":1}],"m_GlyphTable":[{"m_Index":1,"m_Scale":1,"m_Metrics":{"m_HorizontalAdvance":5}}]}
	var record := {"font_guid":"synthetic","font_style":0,"word_wrap":0,"overflow_mode":0,"is_orthographic":true,"character_spacing":0,"word_spacing":0,"enable_kerning":false,"char_width_max_adjustment":0,"auto_size":true,"font_size":10,"font_size_min":2,"font_size_max":10}
	var registry = Fonts.shared()
	registry.cache.synthetic = {"font":ThemeDB.fallback_font,"source_metrics":metrics}
	var label := Label3D.new()
	Title.fit(label,"A",record,Vector2(20,20))
	assert(label.get_meta("source_layout_status") == "source_ascii_autosize_native_raster")
	for target in [metrics.m_FaceInfo,metrics.m_GlyphTable[0],metrics.m_CharacterTable[0]]:
		target.m_Scale = 2
		Title.fit(label,"A",record,Vector2(20,20))
		assert(label.get_meta("source_layout_status") == "unsupported_native_fallback")
		assert(label.get_meta("source_layout_result").reason == "unsupported_native_raster_scale")
		assert(not label.get_meta("source_baseline_result").ok)
		target.m_Scale = 1
	label.free()
	Fonts.reset_shared()
	print("Source TMP native scale guard: PASS (unit face; nonunit face/glyph/character rejected)")
	quit()
