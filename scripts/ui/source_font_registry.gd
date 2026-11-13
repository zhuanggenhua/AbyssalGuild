extends RefCounted
## Exact source TTF identity plus private TMP metrics; not TMP rendering emulation.
static var _shared: RefCounted = null

static func shared() -> RefCounted:
	if _shared == null:
		_shared = load("res://scripts/ui/source_font_registry.gd").new()
		_shared.load_manifest()
	return _shared

static func reset_shared() -> void:
	_shared = null

static func font_guid(record: Dictionary) -> String:
	if record.has("font_guid"):
		return str(record.font_guid)
	for key in ["font_asset", "m_fontAsset"]:
		if record.get(key) is Dictionary:
			return str(record[key].get("guid", ""))
	if record.get("text") is Dictionary:
		return font_guid(record.text)
	return ""

var manifest: Dictionary = {}
var root_path := ""
var cache: Dictionary = {}

func load_manifest(path: String = "res://assets/imported/fonts/manifest.json") -> Error:
	manifest = {}
	cache.clear()
	if not FileAccess.file_exists(path):
		return ERR_FILE_NOT_FOUND
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not parsed is Dictionary or parsed.get("schema_version") != 1 or not parsed.get("fonts") is Dictionary:
		return ERR_PARSE_ERROR
	for entry in parsed.fonts.values():
		if not entry is Dictionary:
			return ERR_PARSE_ERROR
		for key in ["font_path", "metrics_path", "license_path"]:
			var relative := str(entry.get(key, ""))
			if relative.is_empty() or relative.is_absolute_path() or relative.contains("..") or relative.contains(":") or relative.contains("\\"):
				return ERR_PARSE_ERROR
	manifest = parsed
	root_path = path.get_base_dir() + "/"
	return OK

static func _digest(bytes: PackedByteArray) -> String:
	var context := HashingContext.new()
	context.start(HashingContext.HASH_SHA256)
	context.update(bytes)
	return context.finish().hex_encode()

func resolve(guid: String) -> Dictionary:
	if cache.has(guid):
		return cache[guid]
	var entry: Dictionary = manifest.get("fonts", {}).get(guid, {})
	if entry.is_empty():
		return {"font": null, "status": "missing_source_font_binding", "source_font_guid": guid}
	var path: String = root_path + str(entry.font_path)
	var font: FontFile = null
	# Exported Godot resources use import remaps. Validate the font's actual bytes.
	var remap := ConfigFile.new()
	var has_remap: bool = remap.load(path + ".import") == OK
	var cache_ready: bool = has_remap and FileAccess.file_exists(str(remap.get_value("remap", "path", "")))
	if (not has_remap or cache_ready) and ResourceLoader.exists(path, "FontFile"):
		font = ResourceLoader.load(path, "FontFile") as FontFile
	if font == null and FileAccess.file_exists(path):
		font = FontFile.new()
		font.data = FileAccess.get_file_as_bytes(path)
	if font == null or _digest(font.data) != str(entry.get("ttf_sha256", "")):
		return {"font": null, "status": "source_font_bytes_missing_or_mismatched", "source_font_guid": guid}
	var metrics_path: String = root_path + str(entry.metrics_path)
	if not FileAccess.file_exists(metrics_path):
		return {"font": null, "status": "source_metrics_missing_or_mismatched", "source_font_guid": guid}
	var metric_bytes := FileAccess.get_file_as_bytes(metrics_path)
	if _digest(metric_bytes) != str(entry.get("metrics_sha256", "")):
		return {"font": null, "status": "source_metrics_missing_or_mismatched", "source_font_guid": guid}
	var metrics = JSON.parse_string(metric_bytes.get_string_from_utf8())
	if not metrics is Dictionary or metrics.get("source_font_guid") != guid or metrics.get("source_ttf_guid") != entry.get("ttf_guid"):
		return {"font": null, "status": "source_metrics_guid_mismatch", "source_font_guid": guid}
	var result := {"font": font, "status": "source_font_bound_native_layout", "source_font_guid": guid,
		"source_metrics": metrics, "layout_parity": "Godot layout and rasterization are not TMP SDF parity"}
	cache[guid] = result
	return result

func bind_label(label: Label3D, source_record: Dictionary) -> Dictionary:
	var binding := resolve(font_guid(source_record))
	label.set_meta("source_font_status", binding.status)
	label.set_meta("source_font_guid", font_guid(source_record))
	if binding.font != null:
		label.font = binding.font
	# Missing binding preserves the caller's explicit native fallback, never invents identity.
	return binding

func bind_control(control: Control, source_record: Dictionary) -> Dictionary:
	var binding := resolve(font_guid(source_record))
	control.set_meta("source_font_status", binding.status)
	control.set_meta("source_font_guid", font_guid(source_record))
	if binding.font != null:
		if control is RichTextLabel:
			control.add_theme_font_override("normal_font", binding.font)
		else:
			control.add_theme_font_override("font", binding.font)
	return binding
