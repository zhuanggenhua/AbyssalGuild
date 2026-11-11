extends RefCounted
## Source-space trade geometry and pure transaction plans; never mutate Session.
const Spawn = preload("res://scripts/model/scene_spawn.gd")

static func zones(catalog, scene_name: String, board_bounds: Variant = null, top_margin: float = 1.5, completed_quests: int = 0, payments: Dictionary = {}, activated: Dictionary = {}) -> Dictionary:
	var result := {"zones": [], "errors": []}
	for scene in catalog.data.get("scenes", []):
		if str(scene.get("name", "")) != scene_name:
			continue
		var documents: Array = scene.get("documents", [])
		for document in documents:
			if document.get("script_class", "") != "TradeManager":
				continue
			var fields: Dictionary = document.get("fields", {})
			var transform: Variant = _manager_transform(documents, fields)
			if transform == null:
				result.errors.append("Unresolved TradeManager transform")
				return result
			if board_bounds is Rect2:
				transform.origin = Vector3(board_bounds.get_center().x, 0, board_bounds.end.y - top_margin * 0.5)
			var offered: Array = fields.get("offeredPacks", [])
			var scale: Vector3 = Spawn._vector(fields.get("zoneScale", {}), Vector3(1.125, 1, 1.125))
			var spacing := float(fields.get("spacing", 1.1))
			var offset: Vector3 = Spawn._vector(fields.get("spawnOffset", {"z": -1.4}))
			for index in range(offered.size() + 1):
				var buyer := index == 0
				var prefab_guid: String = catalog.ref_guid(fields.get("buyerPrefab" if buyer else "vendorPrefab", {}))
				var geometry := _prefab_geometry(catalog, prefab_guid, "CardBuyer" if buyer else "PackVendor")
				if geometry.is_empty():
					result.errors.append("Unresolved trade prefab geometry: " + prefab_guid)
					continue
				var local_x: float = -offered.size() * spacing * 0.5 + index * spacing
				var local := Transform3D(Basis(geometry.rotation).scaled_local(scale), Vector3(local_x, 0, 0))
				var world: Transform3D = transform * local
				if not _orthogonal(world.basis):
					result.errors.append("Sheared trade collider unsupported: " + str(index))
					continue
				var pack_guid: String = "" if buyer else catalog.ref_guid(offered[index - 1])
				var definition: Dictionary = catalog.get_definition(pack_guid)
				var pack: Dictionary = definition.get("fields", {})
				var minimum := int(pack.get("minQuests", 3))
				var active: bool = buyer or (definition.get("script_class", "") == "PackDefinition" and (bool(activated.get(pack_guid, false)) or completed_quests >= minimum))
				var price := int(pack.get("buyPrice", 3)) if not buyer else 0
				var paid := int(payments.get(pack_guid, 0)) if not buyer else 0
				var bounds: AABB = geometry.bounds
				result.zones.append({"index": index, "kind": "buyer" if buyer else "vendor", "prefab_guid": prefab_guid,
					"pack_guid": pack_guid, "pack_id": str(pack.get("id", "")), "currency_guid": catalog.ref_guid(fields.get("currencyCard", {})),
					"center": world.origin, "transform": world, "local_bounds": bounds, "world_bounds": world * bounds,
					"zone_scale": scale, "spawn_position": world.origin + offset, "collider_enabled": geometry.enabled,
					"active": active, "min_quests": minimum, "total_price": price, "paid": paid, "remaining_price": price - paid,
					"title": "Card Buyer" if buyer else (str(pack.get("displayName", "")) if active else ""),
					"price_text": "Price: %d" % (price - paid) if active and not buyer else ""})
			return result
	result.errors.append("No direct TradeManager resolved for scene: " + scene_name)
	return result

static func _manager_transform(documents: Array, fields: Dictionary) -> Variant:
	var object_id := str(fields.get("m_GameObject", {}).get("fileID", ""))
	for document in documents:
		if document.get("object_type", "") == "Transform" and str(document.get("fields", {}).get("m_GameObject", {}).get("fileID", "")) == object_id:
			return Spawn._world_transform(documents, str(document.get("file_id", "")), [])
	return null

static func _prefab_geometry(catalog, guid: String, script_class: String) -> Dictionary:
	for prefab in catalog.data.get("referenced_prefabs", []):
		if str(prefab.get("guid", "")) != guid:
			continue
		var documents: Array = prefab.get("documents", [])
		var object_id := ""
		for document in documents:
			if document.get("script_class", "") == script_class:
				object_id = str(document.get("fields", {}).get("m_GameObject", {}).get("fileID", ""))
		if object_id.is_empty(): return {}
		var rotation := Quaternion.IDENTITY
		var bounds: Variant = null
		var enabled := true
		for document in documents:
			var fields: Dictionary = document.get("fields", {})
			if str(fields.get("m_GameObject", {}).get("fileID", "")) != object_id: continue
			if document.get("object_type", "") == "BoxCollider":
				var size: Vector3 = Spawn._vector(fields.get("m_Size", {}))
				bounds = AABB(Spawn._vector(fields.get("m_Center", {})) - size * 0.5, size)
				enabled = bool(fields.get("m_Enabled", 1))
			elif document.get("object_type", "") == "Transform":
				var q: Dictionary = fields.get("m_LocalRotation", {})
				rotation = Quaternion(float(q.get("x", 0)), float(q.get("y", 0)), float(q.get("z", 0)), float(q.get("w", 1)))
		if bounds is AABB:
			return {"bounds": bounds, "rotation": rotation, "enabled": enabled}
	return {}

static func _orthogonal(basis: Basis) -> bool:
	if basis.x.length_squared() <= 0 or basis.y.length_squared() <= 0 or basis.z.length_squared() <= 0: return false
	return absf(basis.x.normalized().dot(basis.y.normalized())) < 0.00001 and absf(basis.x.normalized().dot(basis.z.normalized())) < 0.00001 and absf(basis.y.normalized().dot(basis.z.normalized())) < 0.00001

static func intersects(zone: Dictionary, position: Vector3, radius: float) -> bool:
	if radius < 0 or not bool(zone.get("collider_enabled", true)): return false
	var transform: Transform3D = zone.transform
	if not _orthogonal(transform.basis): return false
	var bounds: AABB = zone.local_bounds
	var local: Vector3 = transform.affine_inverse() * position
	var nearest: Vector3 = transform * local.clamp(bounds.position, bounds.end)
	return position.distance_squared_to(nearest) <= radius * radius

static func nearest_zone(zone_list: Array, position: Vector3, radius: float) -> Dictionary:
	# Input order stands in for physics overlap-hit order. Do not filter eligibility.
	var best: Dictionary = {}
	var distance := INF
	for zone in zone_list:
		if not intersects(zone, position, radius): continue
		var squared: float = position.distance_squared_to(zone.center)
		if squared < distance:
			distance = squared
			best = zone
	return best

static func card_snapshots(session, ids: Array) -> Dictionary:
	var result: Array = []
	for id in ids:
		if not session.cards.has(id): return {"ok": false, "cards": []}
		var card = session.cards[id]
		var definition: Dictionary = session.catalog.get_definition(card.definition_guid)
		var fields: Dictionary = definition.get("fields", {})
		result.append({"id": id, "category": int(fields.get("category", 0)), "is_chest": session.world._is_chest(id),
			"stored_coins": card.stored_coins, "is_sellable": bool(fields.get("isSellable", true)), "sell_price": int(fields.get("sellPrice", 1))})
	return {"ok": true, "cards": result}

static func can_trade(zone: Dictionary, cards: Array) -> bool:
	if zone.is_empty() or not bool(zone.get("active", false)): return false
	for card in cards:
		if zone.kind == "buyer":
			if not bool(card.get("is_sellable", true)) or (bool(card.get("is_chest", false)) and int(card.get("stored_coins", 0)) > 0): return false
		elif int(card.get("category", 0)) != 7 and not (bool(card.get("is_chest", false)) and int(card.get("stored_coins", 0)) > 0):
			return false
	return true

static func payment_plan(zone: Dictionary, cards: Array) -> Dictionary:
	# Source BottomCard is LAST in Cards. Empty chests remain and block earlier cards.
	var result := {"accepted": false, "purchased": false, "paid": int(zone.get("paid", 0)), "consumed_ids": [], "stored_after": {}, "remaining_ids": [], "terminal": false, "stats_changed": false}
	for card in cards: result.remaining_ids.append(card.id)
	if zone.get("kind", "") != "vendor" or not can_trade(zone, cards): return result
	result.accepted = true
	var price := int(zone.get("total_price", 0))
	for index in range(cards.size() - 1, -1, -1):
		if result.paid >= price: break
		var card: Dictionary = cards[index]
		if int(card.get("category", 0)) == 7:
			result.consumed_ids.append(card.id)
			result.remaining_ids.erase(card.id)
			result.paid += 1
			result.stats_changed = true
		else:
			var amount: int = mini(price - result.paid, int(card.get("stored_coins", 0)))
			result.stored_after[card.id] = int(card.stored_coins) - amount
			result.paid += amount
			result.stats_changed = result.stats_changed or amount > 0
			break # Remains BottomCard; once empty, source stops rather than skipping it.
	if result.paid >= price:
		result.purchased = true
		result.paid = 0
	result.terminal = result.remaining_ids.is_empty()
	return result
