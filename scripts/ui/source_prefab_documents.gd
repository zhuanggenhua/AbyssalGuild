extends RefCounted
## Apply serialized local overrides before layout/Slider driven fields are rebuilt.
static func resolve(data: Dictionary, name: String, scene_name: String = "Title") -> Array:
	var documents: Array = []
	var guid := ""
	for prefab in data.get("referenced_prefabs", []):
		if prefab.get("name") == name:
			documents = prefab.get("documents", []).duplicate(true)
			guid = str(prefab.get("guid", ""))
	for scene in data.get("scenes", []):
		if scene.get("name") != scene_name: continue
		for document in scene.get("documents", []):
			var fields: Dictionary = document.get("fields", {})
			if str(fields.get("m_SourcePrefab", {}).get("guid", "")) != guid: continue
			for change in fields.get("m_Modification", {}).get("m_Modifications", []):
				for target in documents:
					if str(target.get("file_id", "")) == str(change.get("target", {}).get("fileID", "")):
						_apply(target.fields, change)
	return documents
static func _apply(fields: Dictionary, change: Dictionary) -> void:
	var path: PackedStringArray = str(change.get("propertyPath", "")).split(".")
	var current := fields
	for index in range(path.size()-1):
		if not current.get(path[index]) is Dictionary: return
		current = current[path[index]]
	var key: String = path[path.size()-1]
	if not current.has(key): return
	if current[key] is Dictionary:
		current[key] = change.get("objectReference", current[key]).duplicate(true)
	else:
		var text := str(change.get("value", ""))
		if current[key] is int: current[key] = int(text)
		elif current[key] is float: current[key] = float(text)
		elif current[key] is bool: current[key] = text == "1"
		else: current[key] = text
