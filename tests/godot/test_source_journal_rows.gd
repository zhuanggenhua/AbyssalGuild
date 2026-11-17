extends SceneTree
const Rows = preload("res://scripts/ui/source_journal_rows.gd")
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var rows = Rows.new()
	root.add_child(rows)
	var events := {"enter":0,"exit":0,"click":0}
	rows.meta_hover_started.connect(func(_meta): events.enter += 1)
	rows.meta_hover_ended.connect(func(_meta): events.exit += 1)
	rows.meta_clicked.connect(func(_meta): events.click += 1)
	var data := [{"group":"g","id":"","text":"Group ▼","unread":false},{"group":"","id":"q","text":"• First quest","unread":true}]
	rows.set_rows(data, Color.CYAN)
	await process_frame
	rows.layout_rows()
	var first = rows.rows["group:g"]
	var quest = rows.rows["item:q"]
	check(first.position == Vector2(20,10), "moving content source top/left padding")
	check(quest.position.y == first.position.y + first.size.y + 10, "source inter-child spacing")
	check(rows.preferred_height == quest.position.y + quest.size.y + 10, "source bottom padding")
	check(first.label.get_theme_font_size("normal_font_size") == 35 and quest.label.get_theme_font_size("normal_font_size") == 30, "header/item source font sizes")
	check(first.size.x <= 360 and quest.size.x <= 360, "preferred child width capped to padded content")
	check(first.label.mouse_filter == Control.MOUSE_FILTER_IGNORE and first.mouse_filter == Control.MOUSE_FILTER_PASS, "raycast row bubbles to host")
	check(not quest.label.scroll_active, "rows never own native scroll")
	quest.enter()
	check(events.enter == 1 and quest.hovered, "one source hover event")
	data[1].unread = false
	rows.set_rows(data, Color.CYAN)
	check(rows.rows["item:q"] == quest and quest.hovered and events.enter == 1 and events.exit == 0, "mark-read refresh retains row and hover identity")
	check(not rows.get_parsed_text().contains("●"), "mark-read removes new indicator")
	data[1].text += " √"
	rows.set_rows(data, Color.CYAN)
	check(rows.rows["item:q"] == quest and rows.get_parsed_text().contains("√"), "completion edits retained row")
	rows.set_rows([data[0]], Color.CYAN)
	check(not quest.visible and events.exit == 1 and not quest.hovered, "collapse deactivates row and clears hover")
	rows.set_rows(data, Color.CYAN)
	check(rows.rows["item:q"] == quest and quest.visible, "expand reuses source row")
	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.position = Vector2(1,1)
	press.pressed = true
	var release = press.duplicate()
	release.pressed = false
	rows.can_click = func(): return false
	first._gui_input(press)
	first._gui_input(release)
	check(events.click == 0, "host drag guard rejects header click")
	rows.can_click = func(): return true
	first._gui_input(press)
	first._gui_input(release)
	check(events.click == 1, "admitted header invokes one action")
	quest._gui_input(press)
	quest._gui_input(release)
	check(events.click == 1, "item without source onClick has no action")
	rows.set_rows([{"id":"","group":"","text":"invented placeholder","unread":false}])
	check(rows.get_parsed_text().is_empty() and rows.preferred_height == 20, "empty source view has padding only and no invented text")
	check(rows.get_meta("source_font_guid") == str(rows.registry.manifest.get("tmp_default_font_guid","")), "runtime TMP default identity not prefab font")
	check(rows.get_meta("layout_parity") == "native_wrapping_fallback_not_TMP_preferred_metrics", "native layout never claimed as TMP parity")
	rows.reset_rows()
	check(rows.rows.is_empty(), "scene reset destroys retained source items")
	rows.queue_free()
	await process_frame
	print("JOURNAL_ROWS_CHECKS=",checks," FAILURES=",failures)
	quit(1 if failures else 0)
