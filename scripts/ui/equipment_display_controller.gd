extends RefCounted
## Board-owned card views are positioned as if parented to the source panel.
## Keeping ownership stable prevents class-change view rebuilds deleting gear.
var records: Dictionary = {}
var scaled_time := 0.0
var rng := RandomNumberGenerator.new()
var noise := FastNoiseLite.new()

func _init() -> void:
	rng.randomize()
	noise.noise_type = FastNoiseLite.TYPE_PERLIN
	noise.fractal_type = FastNoiseLite.FRACTAL_NONE
	noise.frequency = 1.0

func sync(equipped: Dictionary, views: Dictionary, metadata: Dictionary, day_open: bool = true) -> void:
	var equipped_ids: Array = []
	for slots in equipped.values(): equipped_ids.append_array(slots.values())
	# metadata maps wearer ID to that prefab's private equipment_panel record.
	for wearer in records.keys():
		if not views.has(wearer) or not metadata.has(wearer) or not is_instance_valid(views[wearer]):
			_drop_record(wearer)
	for wearer in metadata:
		if not views.has(wearer) or not is_instance_valid(views[wearer]):
			continue
		var wearer_view: Node3D = views[wearer]
		var panel = wearer_view.get("equipment_panel")
		var config: Dictionary = _configuration(metadata[wearer])
		if not is_instance_valid(panel) or config.is_empty():
			_drop_record(wearer)
			continue
		var first_sync: bool = not records.has(wearer)
		if first_sync:
			records[wearer] = {"items":{},"expanded":false,"day_open":day_open,"offsets":{},"local_scales":{},"collider":null,"panel":null}
		var record: Dictionary = records[wearer]
		var items: Dictionary = {}
		for slot in equipped.get(wearer, {}):
			var id: int = int(equipped[wearer][slot])
			if slot is int and slot >= 0 and slot < 3 and views.has(id) and is_instance_valid(views[id]):
				items[slot] = id
		var attached := false
		for slot in items:
			if record.items.get(slot, -1) != items[slot]:
				attached = true
				# Source uses two independent random phase offsets for every attachment.
				record.offsets[items[slot]] = Vector2(rng.randf_range(0,1000),rng.randf_range(0,1000))
				record.local_scales[items[slot]] = views[items[slot]].global_basis.get_scale() / panel.global_basis.get_scale()
		for id in record.items.values():
			if id not in equipped_ids and record.get("views", {}).has(id) and is_instance_valid(record.views[id]):
				var detached: Node3D = record.views[id]
				detached.global_basis = Basis.IDENTITY.scaled(detached.global_basis.get_scale())
				_set_card_visibility(detached, true)
		for id in record.offsets.keys():
			if id not in items.values():
				record.offsets.erase(id)
				record.local_scales.erase(id)
		if attached and not first_sync:
			record.expanded = true
		if not day_open:
			record.expanded = false
		record.day_open = day_open
		record.items = items
		record.config = config
		record.views = views
		if record.panel != panel:
			if is_instance_valid(record.collider):
				record.collider.collision_layer = 0
				record.collider.queue_free()
			record.panel = panel
			record.collider = _make_collider(panel, wearer, metadata[wearer])
	for record in records.values(): _apply(record)

func advance(scaled_delta: float) -> void:
	if not is_finite(scaled_delta) or scaled_delta < 0: return
	scaled_time += scaled_delta
	for record in records.values(): _apply(record)

func pointer_down(panel_owner: int = -1, hit_equipment_card: bool = false) -> void:
	# Call for left presses only. ANY equipment card preserves every open panel.
	if hit_equipment_card: return
	for wearer in records:
		if wearer != panel_owner:
			records[wearer].expanded = false
			_apply(records[wearer])

func click_panel(wearer: int) -> bool:
	if not records.has(wearer): return false
	var record: Dictionary = records[wearer]
	if not record.day_open or record.items.is_empty(): return false
	record.expanded = not record.expanded
	_apply(record)
	return true

func is_expanded(wearer: int) -> bool:
	return bool(records.get(wearer, {}).get("expanded", false))

func hover_names(wearer: int, names: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for id in records.get(wearer, {}).get("items", {}).values():
		if names.has(id): result.append(str(names[id]))
	return result

func reset() -> void:
	for wearer in records.keys(): _drop_record(wearer)
	scaled_time = 0.0

func _drop_record(wearer: int) -> void:
	if not records.has(wearer): return
	var collider = records[wearer].get("collider")
	if is_instance_valid(collider):
		collider.collision_layer = 0
		collider.queue_free()
	records.erase(wearer)

func _configuration(metadata: Dictionary) -> Dictionary:
	var interaction: Dictionary = metadata.get("interaction", {})
	var points: Dictionary = interaction.get("attach_points", {})
	var result := {"points":{}}
	for slot in 3:
		var point: Dictionary = points.get(str(slot), {})
		if not point.has("x") or not point.has("y") or not point.has("z"): return {}
		var position := Vector3(float(point.x),float(point.y),-float(point.z))
		if not position.is_finite(): return {}
		result.points[slot] = position
	for key in ["animation_radius","animation_speed"]:
		if not interaction.has(key) or not is_finite(float(interaction[key])) or float(interaction[key]) < 0: return {}
		result[key] = float(interaction[key])
	return result

func _make_collider(panel: Node3D, wearer: int, metadata: Dictionary) -> StaticBody3D:
	var size: Dictionary = metadata.get("size", {})
	if float(size.get("x",0)) <= 0 or float(size.get("z",0)) <= 0: return null
	var collision := StaticBody3D.new()
	collision.name = "EquipmentPanelPick"
	collision.set_meta("equipment_panel_owner", wearer)
	collision.set_meta("card_id", wearer)
	var shape := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(float(size.x),maxf(0.02,float(size.get("y",0))),float(size.z))
	shape.shape = box
	var center: Dictionary = metadata.get("center", {})
	shape.position = Vector3(float(center.get("x",0)),float(center.get("y",0)),-float(center.get("z",0)))
	collision.add_child(shape)
	panel.add_child(collision)
	return collision

func _apply(record: Dictionary) -> void:
	if not is_instance_valid(record.panel): return
	var panel: Node3D = record.panel
	panel.set_slots(record.items.keys())
	if is_instance_valid(record.collider):
		record.collider.collision_layer = 1 if not record.items.is_empty() and panel.is_visible_in_tree() else 0
	for slot in record.items:
		var id: int = record.items[slot]
		if not record.views.has(id) or not is_instance_valid(record.views[id]): continue
		var view: Node3D = record.views[id]
		var position: Vector3 = record.config.points[slot]
		if record.expanded:
			var phase: Vector2 = record.offsets[id]
			var time: float = scaled_time * record.config.animation_speed
			var orbit := Vector3(noise.get_noise_2d(time + phase.x,0),0,-noise.get_noise_2d(0,time + phase.y))
			position += orbit * record.config.animation_radius
		# Source resets local rotation, not scale. Actual source parents use unit scale.
		var scale: Vector3 = record.local_scales[id]
		view.global_transform = panel.global_transform * Transform3D(Basis.IDENTITY.scaled(scale),position)
		_set_card_visibility(view, record.expanded and panel.is_visible_in_tree())

func _set_card_visibility(view: Node3D, value: bool) -> void:
	view.visible = value
	for child in view.get_children():
		if child is StaticBody3D: child.collision_layer = 1 if value else 0
