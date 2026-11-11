extends RefCounted
## Native composition of TitleScreen's separate preference and save panels.
const HOME := "home"
const PREFS := "preferences"
const SAVES := "saves"
var destination: String = HOME
var new_game_pending := false
func open(target: String) -> bool:
	if target not in [HOME, PREFS, SAVES]: return false
	destination = target
	new_game_pending = target == PREFS
	return true
func consume_new_game() -> bool:
	if destination != PREFS or not new_game_pending: return false
	new_game_pending = false
	return true
