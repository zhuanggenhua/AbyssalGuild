extends SceneTree
const Effect = preload("res://scripts/ui/world_post_process.gd")
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func fixture() -> Dictionary:
	return {"scenes": [{"name": "Active", "documents": [{"fields": {"m_SourcePrefab": {"guid": "chosen"}}}]}, {"name": "Other", "documents": []}], "guid_index": {"material-other": {"kind": "mat"}}, "referenced_prefabs": [{"guid": "unused", "documents": []}, {"guid": "chosen", "documents": [
		{"file_id": "obj", "class_id": 1, "fields": {"m_IsActive": 1}},
		{"file_id": "camera", "class_id": 20, "fields": {"m_GameObject": {"fileID": "obj"}, "m_Enabled": 1}},
		{"file_id": "fx", "script_class": "BuiltInPostProcess", "fields": {"m_GameObject": {"fileID": "obj"}, "m_Enabled": 1, "effectMaterial": {"fileID": "material-id", "guid": "material-other"}, "grayscaleIntensity": 0.2, "vignetteIntensity": 0.4}}
	]}]}
func _init() -> void:
	var data := fixture()
	var config := Effect.resolve(data, "Active")
	check(config.source_backed and config.material_guid == "material-other" and config.component_id == "fx", "unequal arbitrary scene/component/material references")
	check(not Effect.resolve(data, "Other").source_backed, "unreferenced prefab excluded")
	check(not Effect.resolve({}, "Active").source_backed, "missing data explicit passthrough")
	var modified := fixture()
	modified.scenes[0].documents[0].fields.m_Modification = {"m_Modifications": [{"target": {"fileID": "fx"}, "propertyPath": "m_Enabled", "value": "0"}]}
	check(not Effect.resolve(modified, "Active").source_backed, "disabled component override")
	modified = fixture()
	modified.referenced_prefabs[1].documents[0].fields.m_IsActive = 0
	check(not Effect.resolve(modified, "Active").source_backed, "inactive game object")
	modified = fixture()
	modified.guid_index.clear()
	check(not Effect.resolve(modified, "Active").source_backed, "dangling material")
	modified = fixture()
	modified.referenced_prefabs[1].documents[1].fields.m_Enabled = 0
	check(not Effect.resolve(modified, "Active").source_backed, "disabled camera")
	modified = fixture()
	modified.scenes[0].documents[0].fields.m_Modification = {"m_RemovedComponents": [{"fileID": "fx"}]}
	check(not Effect.resolve(modified, "Active").source_backed, "removed effect component")
	modified = fixture()
	modified.guid_index["replacement"] = {"kind": "mat"}
	modified.scenes[0].documents[0].fields.m_Modification = {"m_Modifications": [{"target": {"fileID": "fx", "guid": "chosen"}, "propertyPath": "effectMaterial", "objectReference": {"guid": "replacement", "fileID": "new-id"}}]}
	check(Effect.resolve(modified, "Active").material_guid == "replacement", "exact target material override")
	modified.scenes[0].documents[0].fields.m_Modification.m_Modifications[0].target.guid = "foreign"
	check(Effect.resolve(modified, "Active").material_guid == "material-other", "foreign target cannot override same file ID")
	modified = fixture()
	modified.referenced_prefabs[1].documents.append({"file_id": "transform", "class_id": 4, "fields": {"m_GameObject": {"fileID": "obj"}, "m_Father": {"fileID": "parent-transform"}}})
	modified.referenced_prefabs[1].documents.append({"file_id": "parent-transform", "class_id": 4, "fields": {"m_GameObject": {"fileID": "parent"}, "m_Father": {"fileID": "0"}}})
	modified.referenced_prefabs[1].documents.append({"file_id": "parent", "class_id": 1, "fields": {"m_IsActive": 0}})
	check(not Effect.resolve(modified, "Active").source_backed, "inactive camera ancestor")
	var effect = Effect.new()
	effect.configure(data, "Active")
	check(is_equal_approx(effect.grayscale, 0.2), "serialized initialize, not inferred current pace")
	effect.event("time_pace_changed", {"pace": 0})
	effect.advance(0.15)
	check(is_equal_approx(effect.grayscale, 0.8), "half-time OutQuad")
	effect.event("time_pace_changed", {"pace": 2})
	effect.advance(0.15)
	check(is_equal_approx(effect.grayscale, 0.2), "reentrant restart from current value")
	effect.event("day_ended")
	effect.advance(0.5)
	check(is_equal_approx(effect.grayscale, 0) and is_equal_approx(effect.vignette, 1.2), "independent day and pace tracks")
	effect.event("time_pace_changed", {"pace": 0})
	effect.advance(1)
	effect.event("day_started")
	effect.advance(1)
	check(is_equal_approx(effect.grayscale, 1) and is_zero_approx(effect.vignette), "day started never invents pace event")
	effect.event("day_ended")
	effect.advance(NAN)
	effect.advance(-1)
	check(is_zero_approx(effect.vignette), "invalid delta ignored")
	effect.cancel()
	effect.advance(99)
	check(effect.tracks.is_empty() and is_zero_approx(effect.grayscale), "cancel clears stale tweens")
	effect.configure(data, "Other")
	effect.event("day_ended")
	check(effect.tracks.is_empty(), "inactive scene ignores events")
	var red := Effect.shade(Color(1, 0, 0, 0.7), Vector2(0.5, 0.5), 1, 1.2)
	check(is_equal_approx(red.r, 0.299) and red.r == red.g and is_equal_approx(red.a, 0.7), "luma and alpha")
	check(Effect.shade(Color.WHITE, Vector2.ZERO, 0, 1.2).r == 0, "corner full vignette")
	check(Effect.shade(Color.WHITE, Vector2.ZERO, 0, 0) == Color.WHITE, "zero-power passthrough")
	print("World post-process: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
