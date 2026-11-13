extends "res://scripts/ui/source_title_view.gd"
## Shared source prefab panel geometry; caller retains controller transactions.
func configure_panel(data: Dictionary, prefab_name: String, root_name: String, subtree: String, assets) -> bool:
	var documents: Array = []
	var height := 0.0
	for prefab in data.get("referenced_prefabs", []):
		if prefab.get("name") == prefab_name: documents = preload("res://scripts/ui/source_prefab_documents.gd").resolve(data, prefab_name)
		if prefab.get("name") == "UIRoot":
			for doc in prefab.get("documents", []):
				if doc.get("fields", {}).has("m_ReferenceResolution"): height = float(doc.fields.m_ReferenceResolution.y)
	if documents.is_empty() or height <= 0: return false
	var owner := ""
	for doc in documents:
		if doc.get("object_type") == "GameObject" and doc.fields.get("m_Name") == root_name:
			owner = str(doc.file_id)
			doc.fields.m_Name = "Canvas"
	documents.append({"object_type":"MonoBehaviour", "file_id":"adapter_scaler", "fields":{"m_GameObject":{"fileID":owner}, "m_UiScaleMode":1,"m_MatchWidthOrHeight":1,"m_ReferenceResolution":{"y":height}}})
	if not layout.configure({"scenes":[{"name":"Title","documents":documents}]}): return false
	if not subtree.is_empty(): layout.root_id = layout.resolve(subtree)
	if layout.root_id.is_empty(): return false
	source_backed = true
	canvas = Control.new()
	add_child(canvas)
	var shade := ColorRect.new()
	shade.color = Layout.color(layout.field(layout.root_id, "m_Color", {}))
	add_child(shade)
	move_child(shade, 0)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	_build(layout.root_id, canvas, assets)
	resized.connect(relayout)
	relayout()
	return true
func mount_path(path: String, control: Control) -> bool:
	var id: String = layout.resolve(path)
	if not nodes.has(id): return false
	for child in nodes[id].get_children(): child.hide()
	control.reparent(nodes[id])
	control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_style(control,id)
	return true
func _layout_children(parent_id: String, parent: Control) -> void:
	var group: Dictionary = {}
	var vertical := false
	var horizontal := false
	for component in layout.records.get(parent_id, {}).get("components", []):
		var guid: String = str(component.get("m_Script", {}).get("guid", ""))
		vertical = vertical or guid == "59f8146938fff824cb5fd77236b75775"
		horizontal = horizontal or guid == "30649d3a9faa99c48a7b1166b86bf2a0"
	if vertical: group = layout.vertical_rects(parent_id, parent.size)
	if horizontal: group = _horizontal_rects(parent_id, parent.size)
	for id in layout.children.get(parent_id, []):
		if not nodes.has(id): continue
		var rect: Rect2 = group.get(id, layout.rect(id,parent.size))
		# ContentSizeFitter Vertical PreferredSize: sum actual fixed child heights.
		if int(layout.field(id,"m_VerticalFit",0)) == 2:
			var padding: Dictionary = layout.field(id,"m_Padding",{})
			rect.size.y = float(padding.get("m_Top",0))+float(padding.get("m_Bottom",0))
			var children: Array = layout.children.get(id,[])
			for child in children: rect.size.y += Layout.vector(layout.records[child].rect.m_SizeDelta).y
			rect.size.y += max(0,children.size()-1)*float(layout.field(id,"m_Spacing",0))
			var source: Dictionary = layout.records[id].rect
			if Layout.vector(source.m_AnchorMin) == Vector2(0.5,0.5) and Layout.vector(source.m_AnchorMax) == Vector2(0.5,0.5): rect.position.y = (parent.size.y-rect.size.y)/2
		nodes[id].position = rect.position
		nodes[id].size = rect.size
		_layout_children(id,nodes[id])

func _horizontal_rects(id: String, size: Vector2) -> Dictionary:
	var children: Array = layout.children.get(id, [])
	var padding: Dictionary = layout.field(id,"m_Padding",{})
	var left := float(padding.get("m_Left",0))
	var right := float(padding.get("m_Right",0))
	var top := float(padding.get("m_Top",0))
	var bottom := float(padding.get("m_Bottom",0))
	var spacing := float(layout.field(id,"m_Spacing",0))
	var total: float = left+right+spacing*max(0,children.size()-1)
	for child in children: total += Layout.vector(layout.records[child].rect.m_SizeDelta).x
	var spare := maxf(0,size.x-total)
	var expand := bool(layout.field(id,"m_ChildForceExpandWidth",false))
	var alignment := int(layout.field(id,"m_ChildAlignment",0))
	var align_x := (alignment % 3)*0.5
	var align_y := floori(alignment/3.0)*0.5
	var extra: float = spare/max(1,children.size()) if expand else 0.0
	var x := left+(0.0 if expand else spare*align_x)
	var result: Dictionary = {}
	for child in children:
		var extent := Layout.vector(layout.records[child].rect.m_SizeDelta)
		if bool(layout.field(id,"m_ChildControlHeight",false)): extent.y = size.y-top-bottom
		result[child] = Rect2(x+extra*align_x,top+(size.y-top-bottom-extent.y)*align_y,extent.x,extent.y)
		x += extent.x+extra+spacing
	return result
