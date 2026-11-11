extends SceneTree
const Prefs = preload("res://scripts/ui/title_gameplay_prefs.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void:
	var documents := [
		{"file_id": "decoy", "fields": {"m_MinValue": 60, "m_MaxValue": 180, "m_Value": 120, "m_WholeNumbers": 1}},
		{"script_class": "GameplayPrefsUI", "fields": {"durationSlider": {"fileID": "selected"}, "isFriendlyToggle": {"fileID": "toggle"}}},
		{"file_id": "selected", "fields": {"m_MinValue": 67, "m_MaxValue": 193, "m_Value": 131, "m_WholeNumbers": 1}},
		{"file_id": "toggle", "fields": {"m_IsOn": 1}}]
	var source := {"scenes": [{"name": "Main", "documents": []}, {"name": "Title", "documents": documents}]}
	var config := Prefs.resolve(source)
	check(config.source_backed and config.minimum == 67 and config.maximum == 193 and config.initial == 131 and config.friendly, "resolve references instead of first slider or constants")
	check(config.whole_numbers, "whole-second source slider")
	documents[2].fields.m_WholeNumbers = 0
	documents[2].fields.m_Value = 131.75
	config = Prefs.resolve(source)
	check(not config.whole_numbers and config.initial == 131.75 and Prefs.duration_text(config.initial) == "Day Duration: 131 sec", "continuous slider keeps value but source label truncates")
	documents[2].fields.m_Value = 1000
	check(Prefs.resolve(source).initial == 193, "initial value clamps to source maximum")
	documents[1].fields.durationSlider.fileID = "absent"
	config = Prefs.resolve(source)
	check(not config.source_backed and not config.warning.is_empty() and config.initial == 120, "broken reference is explicit fallback, never unrelated slider")
	config = Prefs.resolve({})
	check(not config.source_backed and config.minimum == 60 and config.maximum == 180 and not config.friendly, "missing scene fallback")
	check(Prefs.friendly_text(true) == "Friendly Mode: ON\n(No enemies will appear)" and Prefs.friendly_text(false) == "Friendly Mode: OFF\n(Enemies may appear)", "source flag wording for both states")
	print("Title gameplay prefs: %d checks, %d failures" % [checks, failures])
	quit(1 if failures else 0)
