extends RefCounted
## Only the successful cold Continue caller uses this source re-registration step.
## Codec clones, native saves, travel and the running task scheduler stay unchanged.
const SOURCE_COMMIT := "a11a89b04cea8370476f2559b639bb9b4cbc08d8"
const RECIPE_SCRIPT := "97f7fb60f81c4a649a9a909539c0bdb6"
static func _fail(reason: String) -> Dictionary:
	return {"ok": false, "reason": reason}
static func _source_recipe(entry: Dictionary) -> bool:
	# Classification, not a two-example recipe whitelist. All admitted definitions
	# execute the same locked base class; special/travel subclasses stay outside.
	if entry.get("script_class") != "RecipeDefinition" or entry.get("file_id") != "11400000": return false
	if not str(entry.get("source_path", "")).begins_with("Resources/Recipes/"): return false
	var digest: String = str(entry.get("source_sha256", ""))
	if digest.length() != 64: return false
	for digit in digest:
		if digit not in "0123456789abcdef": return false
	var metadata: Variant = entry.get("unity_fields")
	if not metadata is Dictionary or metadata.get("m_Enabled") != 1: return false
	var script: Variant = metadata.get("m_Script")
	return script is Dictionary and script.get("guid") == RECIPE_SCRIPT and str(script.get("fileID")) == "11500000"
static func plan(session) -> Dictionary:
	if session.catalog.data.get("provenance", {}).get("source_commit") != SOURCE_COMMIT: return _fail("Unknown source crafting restore contract")
	if session.scene_name not in ["Main", "Island"]: return _fail("Unmapped crafting restore scene")
	if session.phase != "playing" or session.cycle.stage != "idle" or session.elapsed >= session.day_duration: return _fail("Day/cycle boundary crafting restore remains separate")
	var source_day := PackedFloat32Array([session.elapsed, session.day_duration])
	if not is_finite(source_day[0]) or not is_finite(source_day[1]) or source_day[0] >= source_day[1]: return _fail("Source float32 day deadline remains separate")
	if session.drag.active() or session.travel_pending: return _fail("Held/pending travel crafting restore remains separate")
	if not session.combat.tasks.is_empty() or not session.combat.membership.is_empty(): return _fail("Combat crafting restore remains separate")
	var order: Array = []
	for stack in session.stacks.values():
		if stack.recipe_guid.is_empty(): continue
		var entry: Dictionary = session.catalog.get_definition(stack.recipe_guid)
		if not _source_recipe(entry): return _fail("Unverified/special crafting restore remains separate")
		var fields: Dictionary = entry.get("fields", {})
		var duration: Variant = fields.get("craftingDuration")
		if not (duration is int or duration is float) or not is_finite(float(duration)) or float(duration) <= 0.0: return _fail("Unverified crafting duration")
		# A canceled already-complete source task can still execute in the old
		# manager. Do not widen the existing native stale-task safety policy here.
		if stack.paused or not is_finite(stack.progress) or stack.progress < 0.0 or stack.progress >= float(duration): return _fail("Paused/complete crafting restore remains separate")
		var source_float := PackedFloat32Array([stack.progress, float(duration)])
		if not is_finite(source_float[0]) or not is_finite(source_float[1]) or source_float[0] >= source_float[1]: return _fail("Source float32 completion boundary remains separate")
		var recipe_id: String = str(fields.get("id", ""))
		if recipe_id.is_empty() or not session.discovered_recipes.has(recipe_id): return _fail("Undiscovered restore callback remains separate")
		order.append(stack.id)
	if order.is_empty(): return _fail("No active crafting to re-register")
	var staged: Dictionary = session.crafting.stage_state({"activation_order": order}, session.stacks)
	if not staged.ok: return _fail("Invalid source crafting membership")
	return {"ok": true, "activation_order": order}
static func apply(session) -> Dictionary:
	var result := plan(session)
	if not result.ok: return result
	var previous: Array = session.crafting.save_state().activation_order
	result.changed = previous != result.activation_order
	if result.changed:
		# No recipe reselection, callback, RNG, timer/paused-state or save mutation.
		session.crafting.apply_state(result)
	return result
