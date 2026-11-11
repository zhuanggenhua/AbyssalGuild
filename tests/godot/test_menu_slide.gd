extends SceneTree
const Slide = preload("res://scripts/ui/menu_slide.gd")
const Board = preload("res://scripts/ui/board.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
var checks := 0
var failures := 0
var clicks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var missing := Slide.initial_state({})
	check(not missing.source_backed and not missing.open and not missing.warning.is_empty(), "missing metadata is explicit closed fallback")
	var source := {"referenced_prefabs": [{"name": "UIRoot", "documents": [
		{"script_class": "MenuToggle", "fields": {"targetRect": {"fileID": "target"}}},
		{"file_id": "decoy", "object_type": "RectTransform", "fields": {"m_AnchoredPosition": {"x": 500}}},
		{"file_id": "target", "object_type": "RectTransform", "fields": {"m_AnchoredPosition": {"x": 0}}}
	]}]}
	check(Slide.initial_state(source).source_backed and Slide.initial_state(source).open, "specific referenced rect determines source-open initial state")
	source.referenced_prefabs[0].documents[2].fields.m_AnchoredPosition.x = 400
	check(not Slide.initial_state(source).open, "positive source x initializes closed")
	source.referenced_prefabs[0].documents[0].fields.targetRect.fileID = "missing"
	check(not Slide.initial_state(source).source_backed, "dangling reference cannot silently use another rect")
	var host := Control.new()
	root.add_child(host)
	var panel := PanelContainer.new()
	panel.position = Vector2(100, 20)
	panel.size = Vector2(200, 300)
	host.add_child(panel)
	var button := Button.new()
	host.add_child(button)
	var slide = Slide.new()
	slide.configure(panel, button, func(): clicks += 1)
	check(not panel.visible and panel.position.x == 300 and button.text == "<<", "closed endpoint uses panel width, no fabricated assets")
	check(slide.toggle() and clicks == 1 and panel.visible and not button.disabled, "opening admits click, retains native GUI control")
	check(not slide.toggle() and clicks == 1, "repeated toggle ignored without sound")
	slide.advance(-1)
	check(panel.position.x == 300, "negative elapsed cannot reverse animation")
	slide.advance(0.25)
	check(is_equal_approx(panel.position.x, 150) and button.text == "<<", "half duration is 75 percent OutQuad; label waits for completion")
	check(not slide.day_ended() and slide.target_x == 0, "day end during opening at positive x does not reverse it")
	slide.advance(0.25)
	check(panel.position.x == 100 and button.text == ">>" and not slide.is_animating, "opening completes exactly")
	check(slide.day_ended() and clicks == 2, "day end closes stationary open panel with Click")
	check(not slide.day_ended() and clicks == 2, "day end at zero during active close is ignored")
	slide.advance(0.25)
	check(panel.visible and panel.mouse_filter == Control.MOUSE_FILTER_STOP and is_equal_approx(panel.position.x, 250), "closing panel remains an input owner while moving")
	slide.advance(1)
	check(not panel.visible and button.text == "<<" and not slide.is_animating, "closed endpoint hides native rows after overshoot")
	check(not slide.day_ended() and clicks == 2, "day end does not reopen closed panel")
	panel.show()
	check(panel.position.x == 100 and button.text == ">>", "explicit native show synchronizes open endpoint")
	host.hide()
	check(panel.position.x == 100 and button.text == ">>", "ancestor visibility does not alter local endpoint")
	host.show()
	slide.toggle()
	slide.advance(0.1)
	slide.reset(false)
	slide.advance(2)
	check(not panel.visible and panel.position.x == 300 and button.text == "<<", "lifecycle reset cancels in-flight callback and restores closed state")
	panel.show()
	slide.toggle()
	panel.hide()
	check(not slide.is_animating and panel.position.x == 300, "external native hide cancels active slide")
	host.queue_free()
	await process_frame
	var catalog = Catalog.new()
	if catalog.load_file() == OK:
		var board = Board.new()
		board.slot_root = "user://slide-%d" % Time.get_ticks_usec()
		board.options_path = board.slot_root + "/options.json"
		board.legacy_paths.clear()
		root.add_child(board)
		await process_frame
		board.start_new()
		board.set_process(false)
		check(board.detail_panel.visible and board.detail_toggle.text == ">>", "private source referenced target initializes open")
		board.detail_panel.hide()
		board.detail_toggle.pressed.emit()
		check(board.journal_slide.is_animating and board.detail_panel.visible, "real native toggle starts slide")
		board.session.paused = true
		board._process(0.25)
		check(board.journal_slide.elapsed == 0.25, "slide advances while game pace is paused")
		board.pause_overlay.show()
		board._process(0.25)
		check(not board.journal_slide.is_animating and board.detail_toggle.text == ">>", "slide completes under external menu pause")
		board.pause_overlay.hide()
		board._on_session_event("day_ended", {})
		check(board.journal_slide.is_animating and board.detail_panel.visible, "real day event starts rather than snaps close")
		board._process(0.5)
		var before: int = board.session.collection.seen_items.size()
		var row_id: String = str(board.session.quest_tracker.active_quests[0].id)
		board.ledger.meta_hover_started.emit(row_id)
		check(not board.detail_panel.visible and board.session.collection.seen_items.size() == before, "closed journal rejects stale row hover")
		board.detail_toggle.pressed.emit()
		board._show_title()
		board._process(1)
		check(not board.journal_slide.is_animating and not board.detail_panel.visible and board.detail_toggle.text == "<<", "title resets in-flight slide")
		board._enter_game()
		check(board.detail_panel.visible and board.detail_toggle.text == ">>", "scene and load entry restore source open endpoint")
		board.queue_free()
		await process_frame
		await create_timer(0.5).timeout
	else:
		print("SKIP: private source menu slide board checks unavailable")
	print("Menu slide: %d/%d checks passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
