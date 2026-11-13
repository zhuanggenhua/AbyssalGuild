extends SceneTree
const Baseline = preload("res://scripts/ui/tmp_title_baseline.gd")
func _init() -> void:
	var record := {"vertical_alignment":512,"rect_pivot":{"x":0.5,"y":0.5},"is_orthographic":true}
	var metrics := {"m_FaceInfo":{"m_PointSize":10,"m_Scale":1,"m_AscentLine":8,"m_DescentLine":-2},"m_GlyphTable":[],"m_CharacterTable":[]}
	var expected := Baseline.source_baseline(record,metrics,10,2)
	assert(expected.ok and expected.baseline == -1)
	var label := Label3D.new()
	label.font = ThemeDB.fallback_font
	label.font_size = 30
	label.pixel_size = 0.1
	label.text = "ABC"
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.offset = Vector2(9,20)
	var before := label.transform
	var result := Baseline.apply(label,record,metrics,10,2)
	assert(result.ok and is_equal_approx(result.native_baseline_after, -1))
	assert(label.offset.x == 9 and label.transform == before and is_equal_approx(label.pixel_size, 0.1))
	record.vertical_alignment = 4096
	assert(not Baseline.apply(label,record,metrics,10,2).ok)
	record.vertical_alignment = 512
	record.erase("rect_pivot")
	assert(not Baseline.apply(label,record,metrics,10,2).ok)
	var offset_before := label.offset
	record.rect_pivot = {"x":0.0,"y":0.5}
	assert(not Baseline.apply(label,record,metrics,10,2).ok and label.offset == offset_before)
	record.rect_pivot = {"x":0.5,"y":0.5}
	metrics.m_FaceInfo.m_AscentLine = 95
	metrics.m_FaceInfo.m_DescentLine = -1
	assert(Baseline.source_baseline(record,metrics,10,2).baseline == -45)
	metrics.m_FaceInfo.m_AscentLine = 1
	metrics.m_FaceInfo.m_DescentLine = -95
	assert(Baseline.source_baseline(record,metrics,10,2).baseline == 49)
	record.is_orthographic = false
	assert(is_equal_approx(Baseline.source_baseline(record,metrics,10,2).baseline, 6.7))
	metrics.m_GlyphTable = [{"m_Scale":2}]
	assert(not Baseline.apply(label,record,metrics,10,2).ok and label.offset == offset_before)
	label.free()
	print("Source TMP Middle baseline: PASS")
	quit()
