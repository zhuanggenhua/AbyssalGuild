extends RefCounted
## Admit only the locked Journal viewport/Content layout and vertical ScrollRect
## branch. Native clipping does not prove pixel parity of the Unity mask sprite.
const REQUIRED_SCROLL := {"m_Enabled":1, "m_Horizontal":0, "m_Vertical":1, "m_MovementType":1}
const REQUIRED_LAYOUT := {"m_Enabled":1, "m_ChildAlignment":0, "m_ChildControlHeight":1,
	"m_ChildControlWidth":1, "m_ChildForceExpandHeight":0, "m_ChildForceExpandWidth":0,
	"m_ChildScaleHeight":0, "m_ChildScaleWidth":0, "m_ReverseArrangement":0}

static func resolve(docs: Array, view_name: String) -> Dictionary:
	if view_name not in ["QuestsView","RecipesView"]: return {}
	var view := _unique_object(docs, view_name)
	var menu := _unique_object(docs, "MenuPanel")
	if view.is_empty() or menu.is_empty() or view.fields.get("m_IsActive") != 1: return {}
	var scroll := _component(docs, view, "m_Viewport")
	var view_rect := _component(docs, view, "m_AnchorMin", "RectTransform")
	var menu_rect := _component(docs, menu, "m_AnchorMin", "RectTransform")
	if not _matches(scroll, REQUIRED_SCROLL) or menu_rect.is_empty() or not _unit_rect(view_rect) \
			or _local(view_rect.fields.get("m_Father")) != _ref(menu_rect) \
			or not _zero_ref(scroll.get("m_HorizontalScrollbar")) or not _zero_ref(scroll.get("m_VerticalScrollbar")) \
			or typeof(scroll.get("m_Inertia")) not in [TYPE_INT,TYPE_FLOAT] or (scroll.m_Inertia != 0 and scroll.m_Inertia != 1):
		return {}
	for key in ["m_Elasticity","m_DecelerationRate","m_ScrollSensitivity"]:
		if not _nonnegative(scroll.get(key)): return {}
	if scroll.m_Elasticity <= 0.0 or scroll.m_DecelerationRate > 1.0: return {}
	var viewport := _document(docs, scroll.get("m_Viewport"), "RectTransform")
	var content := _document(docs, scroll.get("m_Content"), "RectTransform")
	var owner := _component(docs, view, "content")
	if owner.get("m_Enabled") != 1 or _local(owner.get("content")) != _ref(content): return {}
	if viewport.is_empty() or content.is_empty() or _ref(viewport) == _ref(content) \
			or not _sole_child(view_rect, viewport) or not _sole_child(viewport, content) \
			or not _stretch_rect(viewport.fields, 0.0) or not _stretch_rect(content.fields, 1.0):
		return {}
	var viewport_object := _document(docs, viewport.fields.get("m_GameObject"), "GameObject")
	var content_object := _document(docs, content.fields.get("m_GameObject"), "GameObject")
	if viewport_object.is_empty() or content_object.is_empty() \
			or viewport_object.fields.get("m_IsActive") != 1 or content_object.fields.get("m_IsActive") != 1: return {}
	var mask := _component(docs, viewport_object, "m_ShowMaskGraphic")
	var image := _component(docs, viewport_object, "m_Sprite")
	var layout := _component(docs, content_object, "m_Padding")
	var fitter := _component(docs, content_object, "m_VerticalFit")
	if not _matches(mask, {"m_Enabled":1,"m_ShowMaskGraphic":0}) \
			or not _matches(image, {"m_Enabled":1,"m_Type":1,"m_RaycastTarget":1,"m_PreserveAspect":0,"m_UseSpriteMesh":0}) \
			or not _zero_ref(image.get("m_Material")) \
			or not _numbers(image.get("m_RaycastPadding"),{"x":0,"y":0,"z":0,"w":0}) \
			or not _matches(image.get("m_Sprite",{}), {"fileID":"10917","guid":"0000000000000000f000000000000000"}) \
			or not _matches(fitter, {"m_Enabled":1,"m_HorizontalFit":0,"m_VerticalFit":2}) \
			or not _matches(layout, REQUIRED_LAYOUT):
		return {}
	var padding = layout.get("m_Padding")
	if not padding is Dictionary or not _nonnegative(layout.get("m_Spacing")): return {}
	for side in ["m_Left","m_Right","m_Top","m_Bottom"]:
		if not _nonnegative(padding.get(side)): return {}
	return {"scroll":scroll, "padding":Vector4(float(padding.m_Left),float(padding.m_Top),
		float(padding.m_Right),float(padding.m_Bottom)), "spacing":float(layout.m_Spacing)}

static func _ref(doc: Dictionary) -> String:
	return str(doc.get("file_id",""))

static func _local(reference: Variant) -> String:
	return str(reference.get("fileID","")) if reference is Dictionary and not reference.has("guid") else ""

static func _zero_ref(reference: Variant) -> bool:
	return _local(reference) == "0"

static func _document(docs: Array, reference: Variant, object_type: String) -> Dictionary:
	var id := _local(reference)
	if id in ["","0"]: return {}
	var found: Dictionary = {}
	for doc in docs:
		if _ref(doc) != id: continue
		if not found.is_empty() or doc.get("object_type") != object_type: return {}
		found = doc
	return found

static func _unique_object(docs: Array, name: String) -> Dictionary:
	var found: Dictionary = {}
	for doc in docs:
		if doc.get("object_type") != "GameObject" or doc.fields.get("m_Name") != name: continue
		if not found.is_empty(): return {}
		found = doc
	return found

static func _component(docs: Array, object: Dictionary, key: String, type := "MonoBehaviour") -> Dictionary:
	var found: Dictionary = {}
	for doc in docs:
		var f: Dictionary = doc.get("fields",{})
		if doc.get("object_type") != type or _local(f.get("m_GameObject")) != _ref(object) or not f.has(key):
			continue
		if not found.is_empty(): return {}
		found = doc
	return found if type == "RectTransform" else found.get("fields",{})

static func _sole_child(parent: Dictionary, child: Dictionary) -> bool:
	var children: Variant = parent.fields.get("m_Children")
	return children is Array and children.size() == 1 and _local(children[0]) == _ref(child) \
		and _local(child.fields.get("m_Father")) == _ref(parent)

static func _unit_rect(doc: Dictionary) -> bool:
	if doc.is_empty(): return false
	var f: Dictionary = doc.fields
	return _numbers(f.get("m_LocalScale"),{"x":1,"y":1,"z":1}) \
		and _numbers(f.get("m_LocalRotation"),{"x":0,"y":0,"z":0,"w":1}) \
		and _numbers(f.get("m_LocalPosition"),{"x":0,"y":0,"z":0})

static func _stretch_rect(f: Dictionary, min_y: float) -> bool:
	return _unit_rect({"fields":f}) and _numbers(f.get("m_AnchorMin"),{"x":0,"y":min_y}) \
		and _numbers(f.get("m_AnchorMax"),{"x":1,"y":1}) and _numbers(f.get("m_Pivot"),{"x":0,"y":1}) \
		and _numbers(f.get("m_SizeDelta"),{"x":0,"y":0}) and _numbers(f.get("m_AnchoredPosition"),{"x":0,"y":0})

static func _matches(value: Variant, expected: Dictionary) -> bool:
	if not value is Dictionary: return false
	for key in expected:
		var actual: Variant = value.get(key)
		var wanted: Variant = expected[key]
		if wanted is int:
			if typeof(actual) not in [TYPE_INT,TYPE_FLOAT] or actual != wanted: return false
		elif typeof(actual) != typeof(wanted) or actual != wanted: return false
	return true

static func _numbers(value: Variant, expected: Dictionary) -> bool:
	if not value is Dictionary: return false
	for key in expected:
		var n: Variant = value.get(key)
		# Unity's exact negative zero is preserved as a string by the importer.
		if n is String and n == "-0": n = 0
		if typeof(n) not in [TYPE_INT,TYPE_FLOAT] or n != expected[key]: return false
	return true

static func _nonnegative(value: Variant) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and value >= 0
