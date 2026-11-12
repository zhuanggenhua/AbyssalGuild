extends SceneTree
const View = preload("res://scripts/ui/source_title_view.gd")
const Layout = preload("res://scripts/ui/title_scene_layout.gd")
func _init() -> void:
	call_deferred("run")
func run() -> void:
	var parser = Layout.new()
	assert(not parser.configure({}))
	parser.records = {"child": {"rect": {"m_AnchorMin": {"x": 0.5, "y": 0.5}, "m_AnchorMax": {"x": 0.5, "y": 0.5}, "m_Pivot": {"x": 0.5, "y": 0.5}, "m_SizeDelta": {"x": 200, "y": 100}, "m_AnchoredPosition": {"x": 10, "y": 20}}}}
	assert(parser.rect("child", Vector2(1000, 600)) == Rect2(410, 230, 200, 100))
	assert(parser.resolve("missing").is_empty())
	print("Title geometry synthetic: PASS (reflected RectTransform anchors/pivot/offset)")
	var catalog := "res://data/stackcraft.json"
	if not FileAccess.file_exists(catalog):
		print("Source Title view: SKIP (private source documents required)")
		quit()
		return
	var data: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(catalog))
	assert(parser.configure(data))
	assert(parser.reference_height == 1080)
	assert(parser.resolve("MenuPanel/Title") != parser.resolve("GameplayPrefsUI/MainPanel/Title"))
	assert(parser.rect(parser.resolve("MenuPanel"), Vector2(1920,1080)).size == Vector2(500,1080))
	assert(parser.rect(parser.resolve("GameplayPrefsUI/MainPanel"), Vector2(1920,1080)).size == Vector2(500,330))
	assert(parser.rect(parser.resolve("SavedGamesUI/MainPanel"), Vector2(1920,1080)).size == Vector2(800,800))
	var view = View.new()
	root.add_child(view)
	view.size = Vector2(1280,720)
	assert(view.configure(data, null))
	assert(view.home.visible)
	assert(not view.preferences_overlay.visible and not view.saves_overlay.visible)
	view.set_overlay("preferences", true)
	view.set_overlay("saves", true)
	assert(view.home.visible and view.preferences_overlay.visible and view.saves_overlay.visible)
	view.set_overlay("preferences", false)
	assert(view.saves_overlay.visible and view.home.visible)
	assert(view.canvas.scale.is_equal_approx(Vector2.ONE * 2.0/3.0))
	assert(view.preference_content.size == Vector2(500,330))
	var button := Button.new()
	button.text = "transaction owned by caller"
	var calls := [0]
	button.pressed.connect(func(): calls[0] += 1)
	assert(view.mount("new", button))
	button.pressed.emit()
	assert(calls[0] == 1 and button.text == "transaction owned by caller")
	assert(button.get_parent() == view.nodes[parser.resolve("MenuPanel/NewGame")])
	assert(view.saves_content != null)
	view.queue_free()
	await process_frame
	print("Source Title view: PASS (private hierarchy, scaler, independent overlays, mounted callbacks)")
	quit()
