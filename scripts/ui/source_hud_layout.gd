extends RefCounted
## Resolves Unity UI geometry from private imported documents, not screenshot pixels.
var documents: Array = []
var reference_height := 1080.0
var source_backed := false
func configure(data: Dictionary) -> void:
	documents = []
	reference_height = 1080.0
	source_backed = false
	for prefab in data.get("referenced_prefabs", []):
		if prefab.get("name", "") == "UIRoot": documents = prefab.get("documents", [])
	for component in components("UICanvas"):
		if component.has("m_ReferenceResolution") and int(component.get("m_UiScaleMode", 0)) == 1:
			reference_height = float(component.m_ReferenceResolution.y)
			source_backed = float(component.get("m_MatchWidthOrHeight", 0)) == 1.0
func components(object_name: String) -> Array:
	var ids: Array = []
	for doc in documents:
		if doc.get("object_type", "") == "GameObject" and doc.get("fields", {}).get("m_Name", "") == object_name: ids.append(str(doc.file_id))
	var result: Array = []
	for doc in documents:
		var fields: Dictionary = doc.get("fields", {})
		if ids.has(str(fields.get("m_GameObject", {}).get("fileID", ""))): result.append(fields)
	return result
func field(object_name: String, key: String, fallback: Variant) -> Variant:
	for fields in components(object_name):
		if fields.has(key): return fields[key]
	return fallback
func rect(object_name: String, parent_size: Vector2, fallback: Rect2) -> Rect2:
	for fields in components(object_name):
		if not fields.has("m_AnchorMin"): continue
		var lo := vector(fields.m_AnchorMin)
		var hi := vector(fields.m_AnchorMax)
		var pivot := vector(fields.m_Pivot)
		var extent := parent_size * (hi-lo) + vector(fields.m_SizeDelta)
		var lower := parent_size * lo + (parent_size * (hi-lo)) * pivot + vector(fields.m_AnchoredPosition) - extent*pivot
		return Rect2(Vector2(lower.x, parent_size.y-lower.y-extent.y), extent)
	return fallback
static func vector(value: Dictionary) -> Vector2: return Vector2(float(value.get("x", 0)), float(value.get("y", 0)))
func color(object_name: String, fallback: Color) -> Color:
	var value: Dictionary = field(object_name, "m_Color", {})
	return Color(float(value.get("r", fallback.r)), float(value.get("g", fallback.g)), float(value.get("b", fallback.b)), float(value.get("a", fallback.a)))

func text_record(path: String) -> Dictionary:
	# Resolve exact UICanvas-relative hierarchy. Repeated "Label" names are not aliases.
	var objects: Dictionary = {}
	var transforms: Dictionary = {}
	var owner_transforms: Dictionary = {}
	for doc in documents:
		if doc.get("object_type") == "GameObject": objects[str(doc.file_id)] = str(doc.fields.get("m_Name", ""))
		if doc.get("object_type") in ["RectTransform", "Transform"]:
			transforms[str(doc.file_id)] = doc.fields
			owner_transforms[str(doc.fields.get("m_GameObject", {}).get("fileID", ""))] = str(doc.file_id)
	for doc in documents:
		var fields: Dictionary = doc.get("fields", {})
		if not fields.has("m_fontAsset") or not fields.has("m_text"): continue
		var current: String = str(owner_transforms.get(str(fields.get("m_GameObject", {}).get("fileID", "")), ""))
		var names: Array[String] = []
		var seen: Dictionary = {}
		while transforms.has(current) and not seen.has(current):
			seen[current] = true
			var transform: Dictionary = transforms[current]
			var object_name: String = str(objects.get(str(transform.get("m_GameObject", {}).get("fileID", "")), ""))
			if object_name == "UICanvas":
				names.reverse()
				if "/".join(names) == path: return fields
				break
			names.append(object_name)
			current = str(transform.get("m_Father", {}).get("fileID", ""))
	return {}
