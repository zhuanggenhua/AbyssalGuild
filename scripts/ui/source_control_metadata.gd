extends RefCounted
## Resolves local component references; no source defaults are guessed.
static func fields(docs: Array, ref: Dictionary) -> Dictionary:
	if ref.has("guid") or str(ref.get("fileID", "0")) == "0": return {}
	for doc in docs:
		if str(doc.get("file_id", "")) == str(ref.fileID): return doc.get("fields", {})
	return {}
static func component(docs: Array, owner: Dictionary, key: String) -> Dictionary:
	for doc in docs:
		var value: Dictionary = doc.get("fields", {})
		if value.get("m_GameObject") == owner and value.has(key): return value
	return {}
static func rect(docs: Array, image: Dictionary) -> Dictionary:
	return component(docs, image.get("m_GameObject", {}), "m_AnchorMin")
static func slider(docs: Array, reference: Dictionary) -> Dictionary:
	var value := fields(docs, reference)
	if value.get("m_Direction", -1) != 0 or value.get("m_Transition", -1) != 1: return {}
	var handle := fields(docs, value.get("m_HandleRect", {}))
	var fill := fields(docs, value.get("m_FillRect", {}))
	var root := rect(docs, value)
	if handle.is_empty() or fill.is_empty() or root.is_empty(): return {}
	var background: Dictionary = {}
	for doc in docs:
		var f: Dictionary = doc.get("fields", {})
		if doc.get("object_type") == "RectTransform" and str(f.get("m_Father", {}).get("fileID")) == _id(docs, root) and f.get("m_GameObject") != handle.get("m_GameObject"):
			var image := component(docs, f.get("m_GameObject", {}), "m_Sprite")
			if not image.is_empty(): background = {"rect": f, "image": image}
	if background.is_empty() or not value.has("m_Colors") or str(background.image.get("m_Sprite", {}).get("fileID", "0")) != "0": return {}
	var result := {"control": value, "handle": handle, "fill": fill, "handle_parent": fields(docs, handle.get("m_Father", {})), "fill_parent": fields(docs, fill.get("m_Father", {})), "background": background}
	for key in ["handle", "fill"]:
		var image := component(docs, result[key].get("m_GameObject", {}), "m_Sprite")
		if image.is_empty() or str(image.get("m_Sprite", {}).get("fileID", "0")) != "0": return {} # Explicitly only flat source Images.
		result[key + "_image"] = image
	return result
static func text_toggle(docs: Array, reference: Dictionary) -> Dictionary:
	var value := fields(docs, reference)
	if value.get("m_Transition", -1) != 1 or str(value.get("graphic", {}).get("fileID", "")) != "0": return {}
	var label := fields(docs, value.get("m_TargetGraphic", {}))
	if not label.has("m_text") or not label.has("m_fontSize"): return {}
	return {"control": value, "label": label, "rect": rect(docs, label)}
static func _id(docs: Array, value: Dictionary) -> String:
	for doc in docs:
		if doc.get("fields") == value: return str(doc.file_id)
	return ""
static func v(value: Dictionary) -> Vector2: return Vector2(float(value.get("x", 0)), float(value.get("y", 0)))
static func color(value: Dictionary) -> Color: return Color(float(value.get("r", 1)),float(value.get("g", 1)),float(value.get("b", 1)),float(value.get("a", 1)))
static func rectangle(value: Dictionary, parent_size: Vector2) -> Rect2:
	var lo := v(value.m_AnchorMin)
	var hi := v(value.m_AnchorMax)
	var pivot := v(value.m_Pivot)
	var extent := parent_size * (hi-lo) + v(value.m_SizeDelta)
	var lower := parent_size * lo + parent_size * (hi-lo) * pivot + v(value.m_AnchoredPosition) - extent*pivot
	return Rect2(Vector2(lower.x, parent_size.y-lower.y-extent.y), extent)
