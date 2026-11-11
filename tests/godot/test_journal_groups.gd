extends SceneTree
const Groups = preload("res://scripts/ui/journal_groups.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Board = preload("res://scripts/ui/board.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func ids(rows: Array) -> Array:
	return rows.filter(func(row): return not row.id.is_empty()).map(func(row): return row.id)
func run() -> void:
	var catalog = Catalog.new()
	catalog.configure({"cards": [{"guid": "output", "fields": {"displayName": "Output"}}], "enums": {"RecipeCategory": {"Early": 0, "Later": 1}}, "recipes": [
		{"guid": "z", "fields": {"id": "z", "displayName": "Zulu", "category": 0, "resultingCard": {"guid": "output"}}},
		{"guid": "a", "fields": {"id": "a", "displayName": "Alpha", "category": 0, "resultingCard": {"guid": "output"}}},
		{"guid": "b", "fields": {"id": "b", "displayName": "Beta", "category": 1, "resultingCard": {"guid": "output"}}},
		{"guid": "null", "fields": {"id": "null", "displayName": "Null", "category": 0}}
	]})
	var session = Session.new()
	session.discovered_recipes = {"z": true, "a": true, "null": true}
	var rows := Groups.describe(catalog, session, "recipes", {})
	check(ids(rows) == ["a", "z"], "Recipe names sort within category; null result omitted")
	check(rows[0].text == "Early ▼" and rows.size() == 3, "Only discovered category headers shown, expanded by default")
	var expansion := {"recipes:0": false}
	session.discovered_recipes.erase("z")
	Groups.describe(catalog, session, "recipes", expansion)
	session.discovered_recipes.z = true
	check(ids(Groups.describe(catalog, session, "recipes", expansion)).is_empty(), "New discovery inside collapsed category stays hidden")
	session.discovered_recipes.b = true
	rows = Groups.describe(catalog, session, "recipes", expansion)
	check(ids(rows) == ["b"] and rows[0].text == "Early ▶", "Discovery keeps collapsed group closed while new group appears expanded")
	check(session.collection.seen_items.is_empty(), "Pure descriptors never mark discovery seen")
	expansion["recipes:0"] = true
	check(ids(Groups.describe(catalog, session, "recipes", expansion)) == ["a", "z", "b"], "Category enum order precedes display name")
	check(Groups.header_color(catalog, "recipes") == Color.WHITE, "Source-free catalog has neutral header color")
	check(Groups.describe(catalog, session, "recipes", {"foreign": false}) == Groups.describe(catalog, session, "recipes", {}), "Foreign expansion keys cannot hide known groups")
	var tracker = session.quest_tracker
	tracker.active_quests = [{"id": "first"}, {"id": "second"}]
	var order := Groups.reconcile_quest_order(tracker, [])
	check(order == ["second", "first"], "Initial quest order reverses source rebuild insertion")
	tracker.completed_quests = [tracker.active_quests.pop_back()]
	check(Groups.reconcile_quest_order(tracker, order) == order, "Completion changes status without reordering existing rows")
	tracker.active_quests.append({"id": "third"})
	order = Groups.reconcile_quest_order(tracker, order)
	check(order == ["third", "second", "first"], "New activation inserts before older group rows")
	check(Groups.reconcile_quest_order(tracker, order) == order, "Repeated refresh retains presentation chronology")
	var private_catalog = Catalog.new()
	if private_catalog.load_file() != OK:
		print("SKIP: private source journal board checks unavailable")
		print("Journal groups: %d/%d checks passed" % [checks - failures, checks])
		quit(0 if failures == 0 else 1)
		return
	# Headless native signal integration uses actual private imported scene groups.
	var board = Board.new()
	board.slot_root = "user://journal-%d" % Time.get_ticks_usec()
	board.options_path = board.slot_root + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	check(board.data_error == OK, "Private source catalog loads")
	check(Groups.header_color(board.catalog, "quests").is_equal_approx(Color(0.3, 0.8, 1, 1)), "Header tint resolves from imported UIRoot view metadata")
	if board.data_error != OK: board.queue_free(); quit(1); return
	board.start_new()
	board.set_process(false)
	board.detail_panel.show()
	board.active_tab = "quests"
	board._refresh_ledger()
	var first: Dictionary = board.session.quest_tracker.active_quests[0]
	var quest_id: String = first.id
	var group: String = board.ledger_visible_groups.keys()[0]
	check(board.ledger.get_parsed_text().contains(board.session.quest_tracker.quest_groups[0].GroupName), "Real scene group caption replaces generic active bucket")
	var before: int = board.session.collection.seen_items.size()
	board.ledger.meta_hover_started.emit({"journal_group": group})
	board.ledger.meta_clicked.emit({"journal_group": "foreign"})
	board.ledger.meta_clicked.emit(quest_id)
	check(board.session.collection.seen_items.size() == before and board.ledger_expansion.is_empty(), "Header hover, foreign group and raw-ID click do not mutate state")
	board.ledger.meta_clicked.emit({"journal_group": group})
	check(not board.ledger_visible_ids.has(quest_id), "Native header click collapses member rows")
	board.ledger.meta_hover_started.emit(quest_id)
	check(board.session.collection.is_unread(quest_id), "Stale hidden raw-ID hover cannot mark read")
	var old_order: Array = board.ledger_quest_order.duplicate()
	first.current_amount = int(board.session.quest_tracker.definitions[quest_id].targetAmount)
	board.session.quest_tracker._check(first, board.session)
	board._refresh_ledger()
	check(not board.ledger_visible_ids.has(quest_id), "Completion and unlocked discovery retain collapsed state")
	check(board.ledger_quest_order.filter(func(id): return old_order.has(id)) == old_order, "Native completion retains existing row chronology")
	board.active_tab = "recipes"
	board._refresh_ledger()
	board.ledger.meta_clicked.emit({"journal_group": group})
	board.active_tab = "quests"
	board._refresh_ledger()
	check(not board.ledger_expansion[group], "Tab transitions retain collapse and reject other-tab metadata")
	board.ledger.meta_clicked.emit({"journal_group": group})
	check(board.ledger_visible_ids.has(quest_id) and board.ledger.get_parsed_text().contains("√"), "Reopening reveals completed quest history")
	board.ledger.meta_hover_started.emit(quest_id)
	check(board.session.collection.seen_items.has(quest_id), "Visible row keeps exact raw-ID read marker")
	board.detail_panel.hide()
	board.ledger.meta_clicked.emit({"journal_group": group})
	check(board.ledger_expansion[group], "Hidden journal rejects header clicks")
	board.start_new()
	board.set_process(false)
	check(board.ledger_expansion.is_empty(), "New session resets presentation state")
	board.detail_panel.show()
	var recipe_id: String = ""
	for recipe in board.catalog.data.recipes:
		if not board.catalog.ref_guid(recipe.fields.get("resultingCard", {})).is_empty():
			recipe_id = str(recipe.fields.id)
			break
	board.session._discover_recipe(recipe_id)
	board.active_tab = "recipes"
	board._refresh_ledger()
	var recipe_group: String = board.ledger_visible_groups.keys()[0]
	board.ledger.meta_clicked.emit({"journal_group": recipe_group})
	check(not board.ledger_visible_ids.has(recipe_id), "Recipe group genuinely collapsed before travel")
	board.active_tab = "quests"
	board._refresh_ledger()
	board.ledger_expansion[group] = false
	board.session.quest_tracker.configure(board.catalog, "Island")
	board.session.scene_name = "Island"
	board.session.quest_tracker.start_new_game(board.session)
	board._refresh_ledger()
	check(board.ledger_expansion.is_empty(), "Main to Island clears quest and recipe collapse state")
	board.active_tab = "recipes"
	board._refresh_ledger()
	check(board.ledger_visible_ids.has(recipe_id), "Recipe category reopens expanded in destination scene")
	board.active_tab = "quests"
	board._refresh_ledger()
	check(board.ledger.get_parsed_text().contains("The Basics") and not board.ledger_visible_groups.has(group), "Scene switch uses Island group mapping and rejects stale Main headers")
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	print("Journal groups: %d/%d checks passed" % [checks - failures, checks])
	quit(0 if failures == 0 else 1)
