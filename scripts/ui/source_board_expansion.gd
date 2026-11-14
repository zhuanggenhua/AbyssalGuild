extends RefCounted
## Positive first-Start expansion only. Missing source/mesh evidence rejects the
## whole entry; this does not implement shrinking, new games or in-flight loads.
const BOARDS = {
	"Main": ["520b1b5bfc70f3046b560ac3246705d7", "d5f3a469345ddd0797450aa7bed46640c87507144b552b72c0a9d768fc8e12ac", "1a7cfc32364873b5a03e3eee42be7c2cc0f3dcad07a931bbe44fdc2ddd075c3b"],
	"Island": ["2d5c9720d0a21304a8cb9b8bf644f267", "2a54a1dbd9cdcd3da3fe8182753511557a92dee7a9872baac9202dd0f7a0152f", "48250c05c75f7a8b50e72160d8d2ad31fd860d6dd5adf38f3c26e52d5afbeb20"]}
const BOOSTERS = {"7d1a624a9c307ce4887a500cd41b0caf": [10, "0c3c2ca8bf7709e172dc1e9419bad3c5171bec5c42e5dc641d1054855e733e53"], "bd8ec86c3b7345a47b47067b776af305": [4, "c8a68d2e9f6cf6758a523d61abeee60b2b7071e0b62bdbf9af4963b4c1be6561"]}
static func _fail() -> Dictionary: return {"ok": false, "reason": "Missing/unverified source initial board expansion contract"}
static func _d(v: Variant) -> Dictionary: return v if v is Dictionary else {}
static func _a(v: Variant) -> Array: return v if v is Array else []
static func _identity(v: Variant, rotation: bool = false) -> bool:
	if not v is Dictionary: return false
	for key in (["x", "y", "z", "w"] if rotation else ["x", "y", "z"]):
		if not v.has(key) or not (v[key] is int or v[key] is float): return false
		if float(v[key]) != (1.0 if rotation and key == "w" else 0.0): return false
	return true
static func describe(board, boost: int) -> Dictionary:
	var s = board.session
	if boost <= 0 or s.phase != "playing" or s.elapsed >= s.day_duration or not BOARDS.has(s.scene_name): return _fail()
	var expected: Array = BOARDS[s.scene_name]
	var sum := 0
	for card in s.cards.values():
		var definition: Dictionary = board.catalog.get_definition(card.definition_guid)
		if definition.get("script_class") != "LimitBoosterDefinition": continue
		if not BOOSTERS.has(card.definition_guid): return _fail()
		var spec: Array = BOOSTERS[card.definition_guid]
		if definition.get("source_sha256") != spec[1] or _d(definition.get("fields")).get("boostAmount") != spec[0]: return _fail()
		sum += int(spec[0])
	if sum != boost: return _fail()
	var scene := {}; var prefab := {}
	for entry in _a(board.catalog.data.get("scenes")):
		if _d(entry).get("name") == s.scene_name: scene = entry
	for entry in _a(board.catalog.data.get("referenced_prefabs")):
		if _d(entry).get("guid") == expected[0]: prefab = entry
	if scene.get("source_sha256") != expected[2] or prefab.get("source_sha256") != expected[1]: return _fail()
	var renderer := {}; var transform := {}; var component := {}; var root := {}
	for document in _a(prefab.get("documents")):
		var d := _d(document); var fields := _d(d.get("fields"))
		match int(d.get("class_id", -1)):
			1: root = fields
			4: transform = fields
			137: renderer = fields
		if d.get("script_class") == "Board": component = fields
	if root.get("m_IsActive") != 1 or renderer.get("m_Enabled") != 1 or component.get("m_Enabled") != 1 or component.get("topMargin") != 1.5 or float(s.board_top_margin) != 1.5: return _fail()
	if not renderer.get("m_BlendShapeWeights") is Array or renderer.m_BlendShapeWeights.size() != 1 or renderer.m_BlendShapeWeights[0] != 0 or renderer.get("m_Bones") != [] or _d(renderer.get("m_Mesh")).get("guid") != "9d0e9f0cb495aa149a6b7dcedd746658": return _fail()
	if not _identity(transform.get("m_LocalPosition")) or not _identity(transform.get("m_LocalRotation"), true) or _d(transform.get("m_LocalScale")).get("x") != 1 or _d(transform.get("m_LocalScale")).get("y") != 1 or _d(transform.get("m_LocalScale")).get("z") != 1 or _d(transform.get("m_Father")).get("fileID") != "0": return _fail()
	var instances: Array = []
	for document in _a(scene.get("documents")):
		var fields := _d(_d(document).get("fields"))
		if _d(fields.get("m_SourcePrefab")).get("guid") == expected[0]: instances.append(fields)
	if instances.size() != 1: return _fail()
	var modification := _d(instances[0].get("m_Modification"))
	if _d(modification.get("m_TransformParent")).get("fileID") != "0": return _fail()
	for key in ["m_AddedComponents", "m_AddedGameObjects", "m_RemovedComponents", "m_RemovedGameObjects"]:
		if modification.get(key) != []: return _fail()
	var allowed := {"m_LocalPosition.x": 0.0, "m_LocalPosition.y": -0.05, "m_LocalPosition.z": 0.0, "m_LocalRotation.w": 1.0, "m_LocalRotation.x": 0.0, "m_LocalRotation.y": 0.0, "m_LocalRotation.z": 0.0, "m_LocalEulerAnglesHint.x": 0.0, "m_LocalEulerAnglesHint.y": 0.0, "m_LocalEulerAnglesHint.z": 0.0}
	var seen := {}
	for item in _a(modification.get("m_Modifications")):
		var change := _d(item); var path: String = str(change.get("propertyPath", ""))
		if seen.has(path) or _d(change.get("target")).get("guid") != expected[0]: return _fail()
		seen[path] = true
		if path == "m_Name": continue
		if not allowed.has(path) or not str(change.get("value", "")).is_valid_float() or float(change.value) != float(allowed[path]): return _fail()
	if seen.size() != 11: return _fail()
	var assets = board.visual_assets
	if assets == null or assets.scene_configuration(s.scene_name).get("boards") != [expected[0]]: return _fail()
	var initial: Rect2 = assets.board_local_rect(s.scene_name, 0.0)
	var final: Rect2 = assets.board_local_rect(s.scene_name, minf(float(boost), 100.0) / 100.0)
	# Validate actual cached vertex bounds; never use guessed geometry fallback.
	if not initial.is_equal_approx(Rect2(-6, -4, 12, 8)) or not final.has_area() or not s.board_bounds is Rect2 or not final.is_equal_approx(s.board_bounds): return _fail()
	var scale := 1.0 + minf(float(boost), 100.0) / 100.0
	if not final.is_equal_approx(Rect2(initial.position * scale, initial.size * scale)): return _fail()
	return {"ok": true, "initial_bounds": initial, "final_bounds": final, "boost": boost}
