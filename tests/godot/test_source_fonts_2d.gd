extends SceneTree
const View = preload("res://scripts/ui/source_title_view.gd")
const HUD = preload("res://scripts/ui/source_hud_layout.gd")
func _init() -> void:
	var view = View.new()
	view.layout.records = {
		"a": {"components": [{"m_text": "A", "m_fontAsset": {"guid": "synthetic-font-a"}, "m_fontSize": 19}]},
		"b": {"components": [{"m_text": "B", "m_fontAsset": {"guid": "synthetic-font-b"}, "m_fontSize": 31}]}}
	var a := Label.new()
	var b := Button.new()
	view._style(a, "a")
	view._style(b, "b")
	assert(a.get_meta("source_font_guid") == "synthetic-font-a")
	assert(b.get_meta("source_font_guid") == "synthetic-font-b")
	assert(a.get_meta("source_font_status") == "missing_source_font_binding")
	assert(a.get_theme_font_size("font_size") == 19 and b.get_theme_font_size("font_size") == 31)
	var hud = HUD.new()
	hud.documents = [
		{"object_type": "GameObject", "file_id": "1", "fields": {"m_Name": "UICanvas"}},
		{"object_type": "RectTransform", "file_id": "10", "fields": {"m_GameObject": {"fileID": "1"}, "m_Father": {"fileID": "0"}}}]
	for index in range(2):
		var owner := str(index + 2)
		var transform := str(index + 20)
		hud.documents.append({"object_type": "GameObject", "file_id": owner, "fields": {"m_Name": "Panel" + str(index)}})
		hud.documents.append({"object_type": "RectTransform", "file_id": transform, "fields": {"m_GameObject": {"fileID": owner}, "m_Father": {"fileID": "10"}}})
		var child := str(index + 4)
		hud.documents.append({"object_type": "GameObject", "file_id": child, "fields": {"m_Name": "Label"}})
		hud.documents.append({"object_type": "RectTransform", "file_id": str(index + 30), "fields": {"m_GameObject": {"fileID": child}, "m_Father": {"fileID": transform}}})
		hud.documents.append({"object_type": "MonoBehaviour", "file_id": str(index + 40), "fields": {"m_GameObject": {"fileID": child}, "m_text": "Synthetic", "m_fontAsset": {"guid": "synthetic-" + str(index)}}})
	assert(hud.text_record("Panel0/Label").m_fontAsset.guid == "synthetic-0")
	assert(hud.text_record("Panel1/Label").m_fontAsset.guid == "synthetic-1")
	assert(hud.text_record("Label").is_empty())
	a.free()
	b.free()
	view.free()
	print("Source 2D font component identity: PASS")
	quit()
