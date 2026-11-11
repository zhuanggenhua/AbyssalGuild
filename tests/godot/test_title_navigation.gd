extends SceneTree
const Navigation = preload("res://scripts/ui/title_navigation.gd")
func _init() -> void:
	var n = Navigation.new()
	assert(n.destination == n.HOME and not n.consume_new_game())
	assert(not n.open("invalid") and n.destination == n.HOME)
	n.open(n.PREFS)
	n.open(n.PREFS)
	assert(n.consume_new_game() and not n.consume_new_game())
	for target in [n.HOME, n.SAVES]:
		n.open(n.PREFS)
		n.open(target)
		assert(not n.consume_new_game())
	print("Title navigation: 5 checks passed")
	quit()
