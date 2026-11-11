extends RefCounted
## Read actual scene/prefab references, not a catalog-wide shop.
static func offered_packs(catalog, scene_name: String = "Main") -> Array[String]:
	var result: Array[String] = []
	for scene in catalog.data.get("scenes", []):
		if str(scene.get("name", "")) != scene_name:
			continue
		for document in scene.get("documents", []):
			if document.get("script_class", "") == "TradeManager":
				_append(catalog, document.get("fields", {}).get("offeredPacks", []), result)
			# TradeManager can be provided by a referenced prefab. Overrides win.
			var fields: Dictionary = document.get("fields", {})
			var source: String = catalog.ref_guid(fields.get("m_SourcePrefab", {}))
			for prefab in catalog.data.get("referenced_prefabs", []):
				if str(prefab.get("guid", "")) != source:
					continue
				for component in prefab.get("documents", []):
					if component.get("script_class", "") != "TradeManager":
						continue
					var refs: Array = component.get("fields", {}).get("offeredPacks", []).duplicate(true)
					for modification in fields.get("m_Modification", {}).get("m_Modifications", []):
						if str(modification.get("target", {}).get("fileID", "")) != str(component.file_id):
							continue
						var property: String = str(modification.get("propertyPath", ""))
						if property == "offeredPacks.Array.size":
							refs.resize(int(modification.get("value", refs.size())))
						elif property.begins_with("offeredPacks.Array.data["):
							var index: int = int(property.get_slice("[", 1).trim_suffix("]"))
							if index >= refs.size():
								refs.resize(index + 1)
							refs[index] = modification.get("objectReference", {})
					_append(catalog, refs, result)
	return result

static func _append(catalog, refs: Array, result: Array[String]) -> void:
	for reference in refs:
		var guid: String = catalog.ref_guid(reference)
		if not guid.is_empty() and catalog.get_definition(guid).get("script_class", "") == "PackDefinition" and not result.has(guid):
			result.append(guid)
