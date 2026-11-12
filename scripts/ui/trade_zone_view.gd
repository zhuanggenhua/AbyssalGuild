extends Node3D
## Original thin plate/label presentation. Hit tests use TradeLayout's raw box,
## never this visible thickness. No original UI art or physics collider is copied.
var assets
var catalog
var source_nodes: Dictionary = {}
var source_key: String = ""
var pick_body: StaticBody3D
var plate: MeshInstance3D
var caption: Label3D
var material: StandardMaterial3D
var zone_snapshot: Dictionary = {}
var highlighted: bool = false
var highlight_outline: MeshInstance3D

func _init() -> void:
	visibility_changed.connect(_sync_pick_visibility)
	plate = MeshInstance3D.new()
	plate.mesh = BoxMesh.new()
	material = StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	plate.material_override = material
	add_child(plate)
	highlight_outline = MeshInstance3D.new()
	highlight_outline.mesh = ImmediateMesh.new()
	var outline_material := StandardMaterial3D.new()
	outline_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	outline_material.albedo_color = Color(1.0, 0.85, 0.2)
	outline_material.no_depth_test = true
	highlight_outline.material_override = outline_material
	highlight_outline.visible = false
	add_child(highlight_outline)
	caption = Label3D.new()
	caption.font_size = 30
	caption.pixel_size = 0.0032
	caption.width = 220
	caption.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	caption.rotation_degrees.x = -90
	caption.position.y = 0.035
	caption.outline_size = 2
	add_child(caption)

func bind_source(visual_assets, source_catalog) -> void:
	assets = visual_assets
	catalog = source_catalog

func get_info() -> Dictionary:
	if zone_snapshot.is_empty(): return {}
	if zone_snapshot.kind == "buyer": return {"header":"Card Buyer", "body":"Sell your cards here."}
	if not zone_snapshot.active: return {}
	return {"header":"Pack Vendor", "body":"You can buy %s card pack here." % str(zone_snapshot.title)}

func configure(zone: Dictionary, tracker: String) -> void:
	zone_snapshot = zone
	var reflection := Basis(Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, -1))
	var source: Transform3D = zone.transform
	transform = Transform3D(reflection * source.basis * reflection, reflection * source.origin)
	var bounds: AABB = zone.local_bounds
	plate.mesh.size = Vector3(bounds.size.x, maxf(0.025, bounds.size.y), bounds.size.z)
	plate.position = reflection * bounds.get_center()
	_update_highlight(bounds, reflection)
	material.albedo_color = Color(0.15, 0.65, 0.62, 0.7) if zone.kind == "buyer" else (Color(0.7, 0.48, 0.18, 0.75) if zone.active else Color(0.1, 0.15, 0.2, 0.6))
	_bind_source_zone(zone)
	update_caption(zone, tracker)

func update_caption(zone: Dictionary, tracker: String) -> void:
	zone_snapshot = zone
	if not source_nodes.is_empty():
		var labels: Dictionary = source_nodes.labels
		if labels.has("title"):
			labels.title.text = str(zone.title) if zone.kind == "vendor" and zone.active else str(labels.title.get_meta("source_text", ""))
		if labels.has("price"): labels.price.text = str(zone.price_text) if zone.active else str(labels.price.get_meta("source_text", ""))
		if labels.has("tracker"):
			labels.tracker.text = tracker if zone.active else str(labels.tracker.get_meta("source_text", ""))
			labels.tracker.modulate = Color("FFD700") if zone.active and tracker == "COMPLETED" else labels.tracker.get_meta("source_color")
	if not zone.active:
		caption.text = ""
	elif zone.kind == "buyer":
		caption.text = "SELL\nDrop sellable cards"
	else:
		caption.text = "%s\n%s%s" % [zone.title, zone.price_text, "\n" + tracker if not tracker.is_empty() else ""]

func set_highlighted(value: bool) -> void:
	highlighted = value
	highlight_outline.visible = value and source_nodes.is_empty()
	if source_nodes.get("outline") != null: source_nodes.outline.visible = value

func _update_highlight(bounds: AABB, reflection: Basis) -> void:
	var mesh: ImmediateMesh = highlight_outline.mesh
	mesh.clear_surfaces()
	var corners: Array[Vector3] = [
		Vector3(bounds.position.x, bounds.end.y + 0.04, bounds.position.z),
		Vector3(bounds.end.x, bounds.end.y + 0.04, bounds.position.z),
		Vector3(bounds.end.x, bounds.end.y + 0.04, bounds.end.z),
		Vector3(bounds.position.x, bounds.end.y + 0.04, bounds.end.z)]
	mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for index in corners.size():
		mesh.surface_add_vertex(reflection * corners[index])
		mesh.surface_add_vertex(reflection * corners[(index + 1) % corners.size()])
	mesh.surface_end()

func _bind_source_zone(zone: Dictionary) -> void:
	if pick_body == null:
		pick_body = StaticBody3D.new()
		pick_body.name = "TradeZonePick"
		var shape := CollisionShape3D.new()
		shape.shape = BoxShape3D.new()
		pick_body.add_child(shape)
		add_child(pick_body)
	pick_body.set_meta("trade_zone_index", int(zone.index))
	pick_body.collision_layer = 1 if bool(zone.get("collider_enabled", true)) and is_visible_in_tree() else 0
	var bounds: AABB = zone.local_bounds
	var shape: CollisionShape3D = pick_body.get_child(0)
	shape.shape.size = bounds.size
	shape.position = Vector3(bounds.get_center().x, bounds.get_center().y, -bounds.get_center().z)
	if assets == null or catalog == null: return
	var record: Dictionary = {}
	for scene in assets.manifest.get("scenes", {}).values():
		var candidate: Dictionary = scene.get("trading", {}).get(str(zone.kind), {})
		if candidate.get("prefab_guid") == zone.prefab_guid:
			record = candidate
			break
	var art: String = str(catalog.fields(str(zone.currency_guid)).get("artTexture", {}).get("guid", ""))
	var key: String = str(zone.prefab_guid) + ":" + art
	if key != source_key or source_nodes.is_empty():
		if source_nodes.has("root"):
			remove_child(source_nodes.root)
			source_nodes.root.queue_free()
		source_nodes = preload("res://scripts/ui/trade_source_binding.gd").create(assets, record, art)
		source_key = key
		if not source_nodes.is_empty(): add_child(source_nodes.root)
	plate.visible = source_nodes.is_empty()
	caption.visible = source_nodes.is_empty()
	set_highlighted(highlighted)

func _sync_pick_visibility() -> void:
	if pick_body != null:
		pick_body.collision_layer = 1 if is_visible_in_tree() and bool(zone_snapshot.get("collider_enabled", true)) else 0
