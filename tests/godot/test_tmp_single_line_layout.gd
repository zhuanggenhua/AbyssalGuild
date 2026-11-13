extends SceneTree
const Layout = preload("res://scripts/ui/tmp_single_line_layout.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ", label)
func _init() -> void:
	var metrics := {"m_AtlasPopulationMode": 0, "normalSpacingOffset": 0, "m_FaceInfo": {"m_PointSize": 10, "m_Scale": 1, "m_AscentLine": 8, "m_DescentLine": -2}, "m_CharacterTable": [], "m_GlyphTable": []}
	for code in [32,65,66]:
		metrics.m_CharacterTable.append({"m_Unicode": code, "m_GlyphIndex": code, "m_Scale": 1})
		metrics.m_GlyphTable.append({"m_Index": code, "m_Scale": 1, "m_Metrics": {"m_HorizontalAdvance": 5}})
	var record := {"font_style": 0, "word_wrap": 0, "overflow_mode": 0, "is_orthographic": true, "character_spacing": 0, "word_spacing": 0, "enable_kerning": false, "char_width_max_adjustment": 0, "auto_size": true, "font_size": 10, "font_size_min": 2, "font_size_max": 10}
	check(Layout.measure("AB", record, metrics, 10).width == 10, "glyph advances from source metrics")
	check(Layout.measure("AB ", record, metrics, 10).width == 10, "normal no-wrap trailing whitespace excluded")
	check(Layout.fit("AB", record, metrics, Vector2(100,100)).point_size == 10, "source maximum caps short title")
	check(Layout.fit("AB", record, metrics, Vector2(6,100)).point_size == 6, "horizontal quantized search")
	check(Layout.fit("AB", record, metrics, Vector2(100,4)).point_size == 4, "vertical quantized search")
	var under := Layout.fit("AB", record, metrics, Vector2(0.1,0.1))
	check(under.point_size == 2 and under.overflow, "minimum is honored even when overflow remains")
	record.is_orthographic = false
	check(is_equal_approx(Layout.measure("AB", record, metrics, 10).width, 1), "world TMP 0.1 multiplier")
	check(not Layout.fit("中文",record,metrics,Vector2.ONE).ok, "non ASCII explicitly unsupported")
	check(not Layout.fit("<b>A",record,metrics,Vector2.ONE).ok, "rich tags unsupported")
	var value1 := {"m_XAdvance": -1, "m_XPlacement": 0, "m_YAdvance": 0, "m_YPlacement": 0}
	var value2 := {"m_XAdvance": 0, "m_XPlacement": 0, "m_YAdvance": 0, "m_YPlacement": 0}
	metrics["m_FontFeatureTable"] = {"m_GlyphPairAdjustmentRecords": [{"m_FeatureLookupFlags": 0, "m_FirstAdjustmentRecord": {"m_GlyphIndex":65, "m_GlyphValueRecord":value1}, "m_SecondAdjustmentRecord": {"m_GlyphIndex":66, "m_GlyphValueRecord":value2}}]}
	record.is_orthographic = true
	record.enable_kerning = true
	check(Layout.measure("AB",record,metrics,10).width == 9, "pair advance affects next glyph bound")
	record.auto_size = false
	check(Layout.fit("AB",record,metrics,Vector2.ONE).point_size == 10, "disabled autosize does not shrink")
	# Exact GenerateTextMesh still executes its upper-bound search after Overflow
	# at minimum. Do not add an invented early return merely because it overflows.
	record.auto_size = true
	record.font_size_base = 2
	var initial_min := Layout.fit("AB", record, metrics, Vector2(0.01, 0.01))
	check(initial_min.point_size == 2 and initial_min.overflow and initial_min.iterations > 1, "initial minimum overflow follows source grow/shrink loop")
	record.font_size_base = 10
	record.character_spacing = 2
	record.word_spacing = 3
	check(is_equal_approx(Layout.measure("A B",record,metrics,10).width,15.7), "space advances and word/character spacing affect following visible glyph")
	check(is_equal_approx(Layout.measure("A  ",record,metrics,10).width,5), "trailing spaces advance without visible bounds")
	value2.m_XAdvance = -2
	check(is_equal_approx(Layout.measure("ABA",record,metrics,10).width,12.4), "previous pair second adjustment affects subsequent glyph")
	if failures == 0: print("Source TMP ASCII fit: PASS (%d checks)" % checks)
	quit(0 if failures == 0 else 1)
