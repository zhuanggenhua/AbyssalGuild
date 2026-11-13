extends SceneTree
const Groups = preload("res://scripts/ui/journal_groups.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const Board = preload("res://scripts/ui/board.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
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
func restored_progress_rows() -> void:
	# Source RestoreQuests retains Active status at/above target without replay.
	# QuestsView still uses the numeric QuestInstance.IsComplete predicate.
	var catalog = Catalog.new()
	var quests: Array = []
	var references: Array = []
	for id in ["below", "at", "above", "done", "child"]:
		var fields := {"id":id, "title":id, "description":"Description " + id, "targetAmount":2, "type":3}
		if id == "at": fields["questsToUnlock"] = [{"guid":"child"}]
		if id == "child": fields["prerequisiteQuests"] = [{"guid":"at"}]
		quests.append({"guid":id, "fields":fields})
		references.append({"guid":id})
	catalog.configure({"quests":quests})
	var session = Session.new()
	var tracker = session.quest_tracker
	check(tracker.configure(catalog, "Main", [{"GroupName":"Fixture", "Quests":references}]), "Synthetic restore definitions valid")
	var signals := {"activated":0, "completed":0}
	tracker.quest_activated.connect(func(_quest): signals.activated += 1)
	tracker.quest_completed.connect(func(_quest): signals.completed += 1)
	tracker.restore_state({"CompletedQuests":["done"], "ActiveQuests":[{"QuestId":"below","CurrentAmount":1},{"QuestId":"at","CurrentAmount":2},{"QuestId":"above","CurrentAmount":5}]})
	check(signals.activated == 3 and signals.completed == 0, "Restore activates rows without replaying completion")
	var before: Dictionary = tracker.save_state().duplicate(true)
	var rows := Groups.describe(catalog, session, "quests", {})
	var mapped := {}
	for row in rows:
		if not row.id.is_empty(): mapped[row.id] = row
	check(ids(rows) == ["above", "at", "below", "done"], "Numeric completion does not reorder restored rows")
	for id in ["at", "above", "done"]:
		check(mapped[id].text.ends_with(" √"), "Numeric completion suffix for " + id)
		check(mapped[id].info.body == "Description " + id, "Numeric completion hides progress for " + id)
	check(not mapped.below.text.ends_with(" √"), "Below-target Active row has no suffix")
	check(mapped.below.info.body == "Description below\n\nProgress: 1 / 2", "Below-target progress remains visible")
	check(Groups.describe(catalog, session, "quests", {}) == rows, "Repeated view refresh is stable")
	check(tracker.save_state() == before, "Rendering does not mutate saved quest progress/status")
	check(tracker.completed_count() == 1 and not tracker.completed_ids.has("at") and not tracker.completed_ids.has("above"), "Numeric UI completion does not alter completion count or vendor gates")
	check(tracker.active_quests.all(func(q): return q.status == tracker.QuestStatus.ACTIVE), "Restored active instances remain Active")
	check(not mapped.has("child") and signals.activated == 3 and signals.completed == 0, "View does not unlock successors or emit progression events")
	check(session.collection.seen_items.is_empty(), "Displaying restored rows does not mark them seen")
func run() -> void:
	restored_progress_rows()
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
	# A valid full-session save may contain an Active quest at its target.
	# Restore must preserve that state while the native ledger uses IsComplete.
	var snapshot := Codec.capture(board.session)
	var restored_id: String = board.session.quest_tracker.active_quests[0].id
	var target: int = int(board.session.quest_tracker.definitions[restored_id].targetAmount)
	for saved in snapshot.session.quests.ActiveQuests:
		if saved.QuestId == restored_id: saved.CurrentAmount = target
	# A synthetic saved Food record using an actual source definition lets the
	# ordinary stats handler demonstrate a genuine progress decrease after load.
	var food_id := ""
	for id in board.session.quest_tracker.definitions:
		if int(board.session.quest_tracker.definitions[id].type) == board.session.quest_tracker.QuestType.FOOD:
			food_id = id
			break
	check(not food_id.is_empty(), "Actual source Food quest exists for decrease fixture")
	var food_target: int = int(board.session.quest_tracker.definitions[food_id].targetAmount)
	var food_saved := false
	for saved in snapshot.session.quests.ActiveQuests:
		if saved.QuestId == food_id:
			saved.CurrentAmount = food_target
			food_saved = true
	if not food_saved: snapshot.session.quests.ActiveQuests.append({"QuestId":food_id,"CurrentAmount":food_target})
	var completed_before: int = board.session.quest_tracker.completed_count()
	check(Codec.restore(board.session, snapshot).ok, "Actual catalog accepts Active-at-target save")
	board.active_tab = "quests"
	board._refresh_ledger()
	var restored_title: String = board.session.quest_tracker.definitions[restored_id].title
	check(board.ledger.get_parsed_text().contains(restored_title + " √"), "Native restored row shows numeric completion")
	check(not board.ledger_info[restored_id].body.contains("Progress:"), "Native restored info hides completed progress")
	check(board.session.quest_tracker.completed_count() == completed_before and not board.session.quest_tracker.completed_ids.has(restored_id), "Native refresh leaves completed membership unchanged")
	var active_saved: Array = board.session.quest_tracker.save_state().ActiveQuests
	check(active_saved.any(func(q): return q.QuestId == restored_id and q.CurrentAmount == target), "Native save round trip retains Active-at-target")
	board.detail_panel.show()
	var food_instance: Dictionary = {}
	for item in board.session.quest_tracker.active_quests:
		if item.id == food_id: food_instance = item
	var food_title: String = board.session.quest_tracker.definitions[food_id].title
	board.ledger.meta_hover_started.emit(food_id)
	check(not board.info_requests.requests.journal.info.body.contains("Progress:"), "Hover samples restored numeric completion")
	board._refresh_ledger() # Settle removal of the unread dot, as in TextButton.
	var display_key: String = board.ledger_key
	var request_serial: int = board.info_requests.serial
	board.session.quest_tracker.sync_stats(board.session)
	check(int(food_instance.current_amount) < food_target, "Real stats handler lowers restored Food amount")
	var after_stats: Dictionary = board.session.quest_tracker.save_state().duplicate(true)
	board._refresh_ledger()
	check(board.ledger.get_parsed_text().contains(food_title + " √"), "Progress decrease retains existing native title suffix")
	check(board.ledger_key == display_key, "Progress-only refresh does not recreate native row text")
	check(board.info_requests.serial == request_serial and not board.info_requests.requests.journal.info.body.contains("Progress:"), "Refresh does not renew or mutate an already submitted hover snapshot")
	check(board.session.quest_tracker.save_state() == after_stats, "Native presentation preserves post-stats quest/save state")
	board.ledger.meta_hover_ended.emit(food_id)
	check(not board.info_requests.requests.has("journal"), "Hover exit clears only its requester")
	board.ledger.meta_hover_started.emit(food_id)
	check(board.info_requests.requests.journal.info.body.contains("Progress:"), "Reentry queries current decreased progress")
	# Deliberate numerical mutation without a refresh isolates hover query timing.
	food_instance.current_amount = food_target
	board.ledger.meta_hover_ended.emit(food_id)
	board.ledger.meta_hover_started.emit(food_id)
	check(not board.info_requests.requests.journal.info.body.contains("Progress:"), "Hover reads current progress without waiting for ledger refresh")
	board.session.quest_tracker.sync_stats(board.session)
	board.ledger.meta_hover_ended.emit(food_id)
	board.active_tab = "recipes"
	board._refresh_ledger()
	board.active_tab = "quests"
	board._refresh_ledger()
	check(board.ledger.get_parsed_text().contains(food_title + " √"), "Tab hiding/showing is not a QuestsView rebuild")
	# Recreate only the source presentation lifetime, not the game/session state.
	var before_rebuild: Dictionary = board.session.quest_tracker.save_state().duplicate(true)
	board.ledger_session_id = 0
	board._refresh_ledger()
	check(not board.ledger.get_parsed_text().contains(food_title + " √"), "Fresh view reevaluates current below-target amount")
	check(board.session.quest_tracker.save_state() == before_rebuild, "View reconstruction does not complete or replay quests")
	food_instance.current_amount = food_target
	board.session.quest_tracker._check(food_instance, board.session)
	check(board.ledger.get_parsed_text().contains(food_title + " √"), "Completion event updates native text immediately without a frame refresh")
	check(board.session.quest_tracker.completed_ids.has(food_id), "Actual tracker completion still owns completed membership")
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
