extends RefCounted
## Read-only geometry/component adapter for the private Title scene.
var records: Dictionary = {}
var children: Dictionary = {}
var root_id := ""
var reference_height := 0.0

func configure(data: Dictionary) -> bool:
	records.clear()
	children.clear()
	root_id = ""
	var documents: Array = []
	for scene in data.get("scenes", []):
		if scene.get("name") == "Title": documents = scene.get("documents", [])
	var objects: Dictionary = {}
	for document in documents:
		if document.get("object_type") == "GameObject": objects[str(document.file_id)] = document.fields
	for document in documents:
		var fields: Dictionary = document.get("fields", {})
		if document.get("object_type") != "RectTransform" or not fields.has("m_Father"): continue
		var id := str(document.file_id)
		var owner := str(fields.get("m_GameObject", {}).get("fileID", ""))
		var components: Array = []
		for candidate in documents:
			if candidate.get("object_type") == "MonoBehaviour" and str(candidate.get("fields", {}).get("m_GameObject", {}).get("fileID", "")) == owner: components.append(candidate.fields)
		records[id] = {"name": objects.get(owner, {}).get("m_Name", ""), "rect": fields, "components": components}
		children[id] = []
		for child in fields.get("m_Children", []): children[id].append(str(child.fileID))
		if records[id].name == "Canvas": root_id = id
	for component in records.get(root_id, {}).get("components", []):
		if int(component.get("m_UiScaleMode", -1)) == 1 and float(component.get("m_MatchWidthOrHeight", -1)) == 1:
			reference_height = float(component.get("m_ReferenceResolution", {}).get("y", 0))
	return not root_id.is_empty() and reference_height > 0

func resolve(path: String) -> String:
	var current := root_id
	for part in path.split("/", false):
		var found := ""
		for child in children.get(current, []):
			if records.get(child, {}).get("name") == part: found = child; break
		if found.is_empty(): return ""
		current = found
	return current

func field(id: String, key: String, fallback: Variant = null) -> Variant:
	for component in records.get(id, {}).get("components", []):
		if component.has(key): return component[key]
	return fallback

func rect(id: String, parent_size: Vector2) -> Rect2:
	var value: Dictionary = records.get(id, {}).get("rect", {})
	if value.is_empty(): return Rect2()
	var lo := vector(value.m_AnchorMin)
	var hi := vector(value.m_AnchorMax)
	var pivot := vector(value.m_Pivot)
	var extent := parent_size * (hi - lo) + vector(value.m_SizeDelta)
	var lower := parent_size * lo + parent_size * (hi-lo) * pivot + vector(value.m_AnchoredPosition) - extent * pivot
	return Rect2(Vector2(lower.x, parent_size.y - lower.y - extent.y), extent)

func vertical_rects(id: String, size: Vector2) -> Dictionary:
	var padding: Dictionary = field(id, "m_Padding", {})
	var left := float(padding.get("m_Left", 0))
	var right := float(padding.get("m_Right", 0))
	var top := float(padding.get("m_Top", 0))
	var bottom := float(padding.get("m_Bottom", 0))
	var spacing := float(field(id, "m_Spacing", 0))
	var ids: Array = children.get(id, [])
	var total: float = top + bottom + spacing * max(0, ids.size()-1)
	for child in ids: total += vector(records[child].rect.m_SizeDelta).y
	var extra := maxf(0, size.y - total)
	var expand := bool(field(id, "m_ChildForceExpandHeight", false))
	var alignment := int(field(id, "m_ChildAlignment", 0))
	var align_y := floori(alignment / 3.0) * 0.5
	var slot_extra: float = extra / max(1, ids.size()) if expand else 0.0
	var y := top + (0.0 if expand else extra * align_y)
	var result: Dictionary = {}
	for child in ids:
		var height := vector(records[child].rect.m_SizeDelta).y
		result[child] = Rect2(left, y + slot_extra * align_y, maxf(0, size.x-left-right), height)
		y += height + slot_extra + spacing
	return result

static func vector(value: Dictionary) -> Vector2: return Vector2(float(value.get("x", 0)), float(value.get("y", 0)))
static func color(value: Dictionary) -> Color: return Color(float(value.get("r", 1)), float(value.get("g", 1)), float(value.get("b", 1)), float(value.get("a", 1)))
