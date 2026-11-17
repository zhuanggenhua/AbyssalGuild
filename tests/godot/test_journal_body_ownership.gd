extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func settle() -> void:
	await process_frame
	await process_frame
func run() -> void:
	var drain = preload("res://tests/godot/source_test_audio_drain.gd").new()
	var board = Board.new()
	board.slot_root = "user://journal-bodies"
	board.options_path = board.slot_root + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await settle()
	board.set_process(false)
	drain.observe_music(board.feedback.music)
	board.title_panel.hide()
	board.source_hud.show()
	board.hud.show()
	board.running = true
	board.detail_panel.show()
	var quests: Array = []
	var refs: Array = []
	var active: Array = []
	var recipes: Array = []
	for i in range(80):
		var id := "q%02d" % i
		quests.append({"guid":id,"fields":{"id":id,"title":"Quest " + id,"description":"Info " + id,"targetAmount":2,"type":3}})
		refs.append({"guid":id})
		active.append({"QuestId":id,"CurrentAmount":0})
		var rid := "r%02d" % i
		recipes.append({"guid":rid,"fields":{"id":rid,"displayName":rid,"category":0,"resultingCard":{"guid":"result"}}})
		board.session.discovered_recipes[rid] = true
	recipes.append({"guid":"late","fields":{"id":"late","displayName":"late","category":1,"resultingCard":{"guid":"result"}}})
	board.catalog.configure({"quests":quests,"recipes":recipes,"cards":[{"guid":"result","fields":{"displayName":"Output"}}]})
	board.session.catalog = board.catalog
	board.session.quest_tracker.configure(board.catalog, "Main", [{"GroupName":"Test","Quests":refs}])
	board.session.quest_tracker.restore_state({"CompletedQuests":[],"ActiveQuests":active})
	board.active_tab = "quests"
	board._refresh_ledger()
	var q: RichTextLabel = board.journal_bodies.quests
	var r: RichTextLabel = board.journal_bodies.recipes
	await settle()
	check(q != r and q.get_v_scroll_bar() != r.get_v_scroll_bar(), "two real persistent native bodies and scrollbars")
	check(board.ledger == q and q.visible and not r.visible, "active public reference and inactive participation")
	q.get_v_scroll_bar().value = 120
	check(q.get_v_scroll_bar().value == 120, "quest nonzero scroll established")
	board._show_journal_tab("recipes")
	await settle()
	check(board.ledger == r and r.get_v_scroll_bar().value == 0, "first recipe entry never inherits quest scroll")
	r.get_v_scroll_bar().value = 240
	check(r.get_v_scroll_bar().value == 240, "distinct recipe nonzero scroll established")
	for i in range(3):
		board._show_journal_tab("quests")
		await settle()
		check(board.ledger == q and q.get_v_scroll_bar().value == 120, "quest identity and scroll restored")
		board._show_journal_tab("recipes")
		await settle()
		check(board.ledger == r and r.get_v_scroll_bar().value == 240, "recipe identity and scroll restored")
	var hidden_quest: Dictionary = board.session.quest_tracker.active_quests[0]
	hidden_quest.current_amount = 2
	board.session.quest_tracker.quest_completed.emit(hidden_quest)
	await settle()
	check(not q.visible and q.get_parsed_text().contains("Quest " + hidden_quest.id + " √"), "hidden quest completion updates its own body through event")
	check(q.get_v_scroll_bar().value == 120 and r.get_v_scroll_bar().value == 240, "hidden quest rebuild preserves independent offsets")
	r.meta_hover_started.emit("r00")
	check(board.info_requests.current().get("header", "") == "Recipe: Output", "recipe owns hover descriptor")
	q.meta_hover_ended.emit("q00")
	check(board.info_requests.current().get("header", "") == "Recipe: Output", "hidden quest exit cannot erase recipe request")
	q.meta_hover_started.emit("q00")
	check(not board.session.collection.seen_items.has("q00"), "hidden metadata cannot mark quest read")
	board._show_journal_tab("quests")
	q.meta_hover_started.emit("q00")
	r.meta_hover_ended.emit("r00")
	check(board.info_requests.current().get("header", "") == "Quest q00", "hidden recipe exit cannot erase quest request")
	board.ledger_expansion["recipes:1"] = false
	board.session.discovered_recipes.late = true
	board._collection_changed()
	await settle()
	await settle()
	check(board.ledger == q and not r.visible, "hidden discovery never switches public active body")
	check(board.journal_body_state.recipes.groups.has("recipes:1"), "hidden discovery creates its category header")
	check(not board.journal_body_state.recipes.ids.has("late"), "discovery respects collapsed category")
	board.ledger_expansion["recipes:1"] = true
	board._refresh_ledger()
	await settle()
	check(board.journal_body_state.recipes.ids.has("late"), "hidden expansion retains discovery for later entry")
	check(r.get_v_scroll_bar().value == 240, "hidden content refresh preserves owned recipe scroll")
	board._show_journal_tab("recipes")
	await settle()
	check(board.ledger == r and board.ledger_visible_ids.has("late"), "reentry exposes current hidden content")
	board.detail_panel.hide()
	await settle()
	board.detail_panel.show()
	await settle()
	check(r.get_v_scroll_bar().value == 240 and q.get_v_scroll_bar().value == 120, "drawer hide/show preserves both offsets")
	board.ledger_session_id = 0 # same boundary used by _enter_source_scene/start_new.
	board._refresh_ledger()
	await settle()
	check(q.get_v_scroll_bar().value == 0 and r.get_v_scroll_bar().value == 0, "fresh source view lifecycle resets both scrolls")
	check(board.ledger_expansion.is_empty() and board.info_requests.requests.is_empty(), "fresh view clears expansion and both hover owners")
	board._show_journal_tab("invalid")
	check(board.active_tab == "recipes" and board.ledger == r, "unknown tab cannot corrupt active compatibility reference")
	if board.catalog.load_file() == OK:
		board.data_error = OK
		board.start_new()
		board.set_process(false)
		await settle()
		check(board.active_tab == "quests" and board.ledger == q, "real start-new source lifecycle restores authored Quests selection")
		check(q.get_v_scroll_bar().value == 0 and r.get_v_scroll_bar().value == 0, "real start-new clears both native offsets")
		print("Journal body private lifecycle: verified")
	else:
		print("SKIP: private source start-new lifecycle unavailable")
	drain.observe_music(board.feedback.music)
	board.free()
	check(await drain.wait_after_teardown(self), "native audio teardown drained")
	print("Journal body ownership: %d/%d checks passed" % [checks-failures, checks])
	quit(0 if failures == 0 else 1)
