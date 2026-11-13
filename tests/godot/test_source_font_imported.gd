extends SceneTree
const Registry = preload("res://scripts/ui/source_font_registry.gd")
const SOURCE_GUID := "8f586378b4e144a9851e7b34d9b748ee"
func _init() -> void:
	var registry = Registry.new()
	assert(registry.load_manifest() == OK, "Private source-font manifest required")
	if OS.get_cmdline_user_args().has("--require-import-cache"):
		var config := ConfigFile.new()
		var font_path: String = registry.root_path + str(registry.manifest.fonts[SOURCE_GUID].font_path)
		assert(config.load(font_path + ".import") == OK)
		assert(FileAccess.file_exists(str(config.get_value("remap", "path", ""))))
	var result = registry.resolve(SOURCE_GUID)
	assert(result.font != null and result.status == "source_font_bound_native_layout")
	assert(result.font.get_font_name() == "Liberation Sans")
	assert(result.font.get_font_style_name() == "Regular")
	assert(result.source_metrics.m_FaceInfo.m_PointSize == 86)
	assert(result.source_metrics.m_GlyphTable.size() == 250)
	assert(result.source_metrics.m_CharacterTable.size() == 250)
	assert(registry.resolve(SOURCE_GUID).font == result.font)
	var label := Label3D.new()
	registry.bind_label(label, {"font_guid": SOURCE_GUID})
	assert(label.font == result.font)
	label.free()
	registry.cache.clear()
	registry.manifest.fonts[SOURCE_GUID].ttf_sha256 = "invalid"
	assert(registry.resolve(SOURCE_GUID).status == "source_font_bytes_missing_or_mismatched")
	print("Imported exact source font identity and TMP metrics: PASS")
	quit()
