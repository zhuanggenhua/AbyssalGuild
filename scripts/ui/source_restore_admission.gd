extends RefCounted
## Narrow cold-entry admission. Unsupported branches keep their existing behavior
## and report the unproven boundary; never pretend a broad source restore match.
const Planner = preload("res://scripts/model/source_restore_layout.gd")
const SOURCE_COMMIT := "a11a89b04cea8370476f2559b639bb9b4cbc08d8"
static func _fail(reason: String) -> Dictionary: return {"ok": false, "reason": reason}
static func _has_script(catalog, guid: String, kind: String) -> bool:
	for document in _documents(catalog, guid):
		if document.get("script_class", "") == kind: return true
	return false
static func _documents(catalog, guid: String) -> Array:
	var prefabs: Variant = catalog.data.get("referenced_prefabs", [])
	if not prefabs is Array: return []
	for prefab in prefabs:
		if not prefab is Dictionary or prefab.get("guid", "") != guid: continue
		var documents: Variant = prefab.get("documents", [])
		if not documents is Array: return []
		for document in documents:
			if not document is Dictionary: return []
		return documents
	return []
static func _fields(document: Dictionary) -> Dictionary:
	var fields: Variant = document.get("fields")
	return fields if fields is Dictionary else {}
static func _object_id(reference: Variant) -> String:
	return str(reference.get("fileID", "0")) if reference is Dictionary else "0"
static func _root_object(documents: Array) -> String:
	var roots: Array = []
	for document in documents:
		if document.get("script_class", "") == "CardInstance":
			roots.append(_object_id(_fields(document).get("m_GameObject")))
	return str(roots[0]) if roots.size() == 1 and roots[0] != "0" else ""
static func _has_root_script(catalog, guid: String, kind: String) -> bool:
	var documents := _documents(catalog, guid)
	var root := _root_object(documents)
	if root.is_empty(): return false
	for document in documents:
		if document.get("script_class", "") == kind and _object_id(_fields(document).get("m_GameObject")) == root: return true
	return false
static func _owner_panel_bound(catalog, guid: String) -> bool:
	var documents := _documents(catalog, guid)
	var root := _root_object(documents)
	if root.is_empty(): return false
	var owners: Array = []
	for document in documents:
		if document.get("script_class", "") == "CardEquipper" and _object_id(_fields(document).get("m_GameObject")) == root: owners.append(document)
	if owners.size() != 1: return false
	var reference: Variant = _fields(owners[0]).get("equipmentPanel")
	if not reference is Dictionary or not str(reference.get("guid", "")).is_empty(): return false
	var target := str(reference.get("fileID", "0"))
	if target in ["", "0"]: return false
	var matches: Array = []
	for document in documents:
		if str(document.get("file_id", "")) == target: matches.append(document)
	return matches.size() == 1 and matches[0].get("script_class", "") == "EquipmentPanel"
static func plan(board) -> Dictionary:
	var session = board.session
	var catalog = board.catalog
	if catalog.data.get("provenance", {}).get("source_commit", "") != SOURCE_COMMIT: return _fail("Unknown source restore contract")
	if session.scene_name not in ["Main", "Island"]: return _fail("Unmapped source scene")
	if session.phase not in ["playing", "selling"] or session.cycle.stage != "idle" or session.drag.active(): return _fail("In-flight cycle/held restoration remains separate")
	if not session.combat.tasks.is_empty() or not session.combat.membership.is_empty(): return _fail("Combat restoration listener order not verified")
	var boost: int = int(session.stats().card_limit) - int(catalog.settings("CardSettings").get("baseCardLimit", 24))
	if boost != 0: return _fail("Expanded board Awake/Start ordering not verified")
	var defaults: Dictionary = session.campaign._defaults(session.scene_name)
	var character := ""; var equipment := ""
	for item in defaults.get("cardPrefabs", []):
		if int(item.get("category", -1)) == 2: character = catalog.ref_guid(item.get("prefab", {}))
		if int(item.get("category", -1)) == 5: equipment = catalog.ref_guid(item.get("prefab", {}))
	if not _owner_panel_bound(catalog, character): return _fail("Missing/resolution-failed source owner equipmentPanel reference")
	if not _has_root_script(catalog, equipment, "CardEquipment") or _has_script(catalog, equipment, "CardEquipper"): return _fail("Source equipment graph depth not verified")
	var rules: Array = catalog.stacking_rules()
	if rules.size() != 144: return _fail("Missing source stacking matrix")
	var rows: Array = []
	var seen := {}
	for stack in session.stacks.values():
		if not stack.recipe_guid.is_empty(): return _fail("Active crafting restoration remains separate")
		var row := {"id": stack.id, "position": stack.position, "cards": []}
		for id in stack.card_ids:
			if not session.cards.has(id): return _fail("Missing source card")
			var card = session.cards[id]
			var fields: Dictionary = catalog.fields(card.definition_guid)
			var category: int = int(fields.get("category", -1))
			var is_pack: bool = catalog.get_definition(card.definition_guid).get("script_class", "") == "PackDefinition"
			if not is_pack and session.friendly_mode and bool(fields.get("isAggressive", false)): return _fail("Source friendly-mode factory would reject saved aggressive card")
			var forbidden := is_pack and category >= 0 and category < 12
			if forbidden:
				for other in 12: forbidden = forbidden and int(rules[category * 12 + other]) == 0
			var descriptor := {"id": id, "size": board._card_footprint(id), "pack": is_pack, "attachment_forbidden": forbidden, "equipper_supported": category == 2, "equipment": []}
			seen[id] = true
			for slot in session.equipment.equipped.get(id, {}):
				var item_id: int = session.equipment.equipped[id][slot]
				if not session.cards.has(item_id) or session.equipment.owners.get(item_id, -1) != id: return _fail("Invalid source equipment ownership")
				var item_fields: Dictionary = catalog.fields(session.cards[item_id].definition_guid)
				if int(item_fields.get("category", -1)) != 5 or session.equipment.equipped.has(item_id): return _fail("Nested/custom equipment restoration not verified")
				descriptor.equipment.append({"id": item_id, "size": board._card_footprint(item_id), "pack": false, "equipment": [], "slot": int(slot), "equip_succeeds": true})
				seen[item_id] = true
			row.cards.append(descriptor)
		rows.append(row)
	if seen.size() != session.cards.size(): return _fail("Unstacked source records outside admitted branch")
	return Planner.plan(rows, [], {"scene": session.scene_name, "bounds": session.board_bounds, "step": board._stack_step(), "top_margin": float(session.board_top_margin), "max_iterations": int(catalog.settings("CardSettings").get("maxIterations", 0)), "combat": false, "board_boost": boost, "default_spawn": false})
