extends RefCounted
## Read-only view over the audited source-data export. References are GUIDs.
var data: Dictionary = {}
var definitions: Dictionary = {}

func load_file(path: String = "res://data/stackcraft.json") -> Error:
	var file = FileAccess.open(path, FileAccess.READ)
	if file == null:
		return FileAccess.get_open_error()
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("schema_version", 0) != 1:
		return ERR_PARSE_ERROR
	configure(parsed)
	return OK

func configure(source: Dictionary) -> void:
	data = source
	definitions.clear()
	for group in ["cards", "packs", "recipes", "quests", "encounters", "settings"]:
		for item in data.get(group, []):
			definitions[str(item.guid)] = item

func get_definition(guid: String) -> Dictionary:
	return definitions.get(guid, {})

func fields(guid: String) -> Dictionary:
	return get_definition(guid).get("fields", {})

func ref_guid(reference: Variant) -> String:
	return str(reference.get("guid", "")) if reference is Dictionary else ""

func find_by_name(query: String, group: String = "cards") -> String:
	for item in data.get(group, []):
		if item.get("name", "") == query or item.fields.get("displayName", "") == query:
			return str(item.guid)
	return ""

func settings(script_class: String) -> Dictionary:
	for item in data.get("settings", []):
		if item.get("script_class", "") == script_class:
			return item.fields
	return {}

func stacking_rules() -> Array:
	var raw = settings("StackingRulesMatrix").get("rules", [])
	if raw is Array:
		return raw
	var decoded: Array = []
	if raw is String:
		var bytes: PackedByteArray = raw.hex_decode()
		for offset in range(0, bytes.size() - 3, 4):
			decoded.append(bytes.decode_s32(offset))
	return decoded
