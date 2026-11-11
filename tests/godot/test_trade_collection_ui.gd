extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const TradeLayout = preload("res://scripts/model/trade_layout.gd")
var checks: int = 0
var failures: int = 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func clear_cards(board) -> void:
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board.session.vendor_payments.clear()
	board.session.phase = "playing"
	board._refresh()
func unlock(board) -> void:
	for id in board.session.quest_tracker.definitions: board.session.quest_tracker.completed_ids[id] = true
	board._refresh()
func drop(board, id: int, destination: Vector2) -> void:
	board.dragging = id
	board.drag_moved = true
	board.drag_delta = destination - board.session.cards[id].position
	board._finish_drag(board.camera.unproject_position(Vector3(destination.x, 0, -destination.y)))
func point(zone: Dictionary) -> Vector2:
	return Vector2(zone.center.x, zone.center.z)
func spawn(board, name: String, position: Vector2 = Vector2.ZERO, target: int = -1) -> int:
	if target >= 0: position = board.session.stacks[target].position
	return board.session.spawn_card(board.catalog.find_by_name(name), position, target, {"refuse_attach": true})
func run() -> void:
	var board = Board.new()
	board.slot_root = "user://trade-ui-%d-%d" % [Time.get_unix_time_from_system(), Time.get_ticks_usec()]
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	check(board.data_error == OK, "real source data loaded")
	if board.data_error != OK: quit(1); return
	board.start_new()
	board.set_process(false)
	check(board.trade_zones.size() == 9 and board.trade_views.size() == 9, "Main renders exact buyer and eight vendor zones")
	var buyer: Dictionary = board.trade_zones[0]
	var vendor: Dictionary = board.trade_zones[1]
	check(not vendor.active and board.trade_views[1].caption.text.is_empty(), "locked vendor keeps source text hidden but zone present")
	for zone in board.trade_zones:
		var view = board.trade_views[int(zone.index)]
		check(view.position.is_equal_approx(Vector3(zone.center.x, zone.center.y, -zone.center.z)), "zone origin reflects source Z: " + str(zone.index))
	check(is_zero_approx(vendor.local_bounds.size.y) and board.trade_views[1].plate.mesh.size.y > 0, "thin rendered plate does not replace zero-height source collider")
	check(not TradeLayout.intersects(vendor, vendor.center + Vector3(0, 0.26, 0), 0.25), "source hit test excludes point above raw collider")
	# Nearest inactive vendor blocks a farther eligible buyer, even though both intersect.
	clear_cards(board)
	var wood: int = spawn(board, "Wood", Vector2(0, -2))
	var between: Vector2 = point(buyer).lerp(point(vendor), 0.52)
	check(TradeLayout.intersects(buyer, Vector3(between.x, 0, between.y), 0.25) and TradeLayout.intersects(vendor, Vector3(between.x, 0, between.y), 0.25), "nearest-zone fixture intersects both zones")
	drop(board, wood, between)
	check(board.session.cards.has(wood) and board.session.stats().currency == 0, "nearest rejecting vendor never retries farther valid buyer")
	check(board.notice.text.contains("cannot accept"), "nearest rejection explained")
	# Trade wins before equipment even with a character directly under buyer.
	clear_cards(board)
	var wearer: int = spawn(board, "Villager", point(buyer))
	var gear: int = spawn(board, "Sword", Vector2(0, -2))
	drop(board, gear, point(buyer))
	check(not board.session.cards.has(gear) and board.session.equipment.equipped.get(wearer, {}).is_empty(), "buyer is first terminal action before equip")
	check(board.session.cards.has(wearer), "buyer does not consume unrelated nearby character")
	# Only dragged tail is sold, not the source stack below it.
	clear_cards(board)
	wearer = spawn(board, "Villager", Vector2(0, -2))
	wood = spawn(board, "Wood", Vector2.ZERO, board.session.cards[wearer].stack_id)
	drop(board, wood, point(buyer))
	check(board.session.cards.has(wearer) and not board.session.cards.has(wood), "buyer trades dragged tail rather than whole original stack")
	clear_cards(board)
	unlock(board)
	vendor = board.trade_zones[1]
	var price: int = int(vendor.total_price)
	var offer: String = str(vendor.pack_guid)
	check(vendor.active and price > 1, "source vendor unlocks with actual price")
	var coin: int = spawn(board, "Coin", Vector2(0, -2))
	drop(board, coin, point(vendor))
	check(not board.session.cards.has(coin) and int(board.session.vendor_payments[offer]) == 1, "partial coin installment is terminal when dropped stack empties")
	check(board.trade_views[1].caption.text.contains("Price: %d" % (price - 1)), "zone remaining-price text refreshes after installment")
	coin = spawn(board, "Coin", Vector2(0, -2))
	for i in range(price - 2): spawn(board, "Coin", Vector2.ZERO, board.session.cards[coin].stack_id)
	drop(board, coin, point(vendor))
	var purchased: int = 0
	for card in board.session.cards.values():
		if card.definition_guid == offer: purchased += 1
	check(purchased == 1 and int(board.session.vendor_payments[offer]) == 0, "remaining installment creates exactly one pack")
	# Actual chest payment is accepted but nonterminal: fallback must move its remainder.
	var chest_guid: String = ""
	for entry in board.catalog.data.cards:
		if entry.get("script_class", "") == "ChestDefinition": chest_guid = entry.guid; break
	clear_cards(board)
	var chest: int = board.session.spawn_card(chest_guid, Vector2(0, -2), -1, {"refuse_attach": true})
	board.session.cards[chest].stored_coins = 1
	drop(board, chest, point(vendor))
	check(board.session.cards.has(chest) and board.session.cards[chest].stored_coins == 0 and int(board.session.vendor_payments[offer]) == 1, "partial chest payment keeps empty chest")
	check(board.session.cards[chest].position.is_equal_approx(board._clamp_stack_position(chest, point(vendor))), "nonterminal chest payment continues ordinary placement")
	clear_cards(board)
	coin = spawn(board, "Coin", Vector2(0, -2))
	chest = board.session.spawn_card(chest_guid, Vector2.ZERO, board.session.cards[coin].stack_id)
	board.session.cards[chest].stored_coins = 1
	drop(board, coin, point(vendor))
	check(board.session.cards.has(coin) and board.session.cards[chest].stored_coins == 0 and int(board.session.vendor_payments[offer]) == 1, "last-first empty chest stops before earlier coin and falls through")
	clear_cards(board)
	chest = board.session.spawn_card(chest_guid, Vector2(0, -2), -1, {"refuse_attach": true})
	board.session.cards[chest].stored_coins = price + 2
	drop(board, chest, point(vendor))
	check(board.session.cards[chest].stored_coins == 2 and board.session.cards[chest].position != point(vendor), "full chest purchase retains excess and continues placement")
	purchased = 0
	for card in board.session.cards.values():
		if card.definition_guid == offer: purchased += 1
	check(purchased == 1, "nonterminal full chest purchase is not retried")
	# Source bounds/header and scene drive rendered origins.
	var before_center: Vector3 = board.trade_zones[0].center
	var booster_guid: String = ""
	for entry in board.catalog.data.cards:
		if int(entry.fields.get("boostAmount", 0)) > 0: booster_guid = entry.guid; break
	board.session.spawn_card(booster_guid, Vector2(-2, -2), -1, {"refuse_attach": true})
	board._refresh()
	check(board.trade_zones[0].center.z > before_center.z, "board growth moves zones to source header center")
	# A fresh game restores real quest history rather than test unlock markers.
	board.start_new()
	board.set_process(false)
	board.detail_panel.show()
	var initial_seen: int = board.session.collection.seen_items.size()
	board.active_tab = "quests"
	board._refresh_ledger()
	check(board.session.collection.seen_items.size() == initial_seen, "opening quest ledger marks nothing read")
	var instance: Dictionary = board.session.quest_tracker.active_quests[0]
	var quest_id: String = instance.id
	instance.current_amount = int(board.session.quest_tracker.definitions[quest_id].targetAmount)
	board.session.quest_tracker._check(instance, board.session)
	board._refresh()
	check(board.ledger_visible_ids.has(quest_id) and board.ledger.get_parsed_text().contains("✓"), "completed quest remains individually hoverable in history")
	check(board.session.collection.is_unread(quest_id), "quest completion does not mark its row read")
	var signature: String = board._layout_signature()
	var rng_state: int = board.session.rng.state
	board.ledger.meta_hover_started.emit(quest_id)
	await process_frame
	check(board.session.collection.seen_items.has(quest_id), "hover stores exact raw Quest.Id")
	check(board._layout_signature() == signature and board.session.rng.state == rng_state, "collection signal only refreshes labels without reentrant gameplay")
	var seen_after: int = board.session.collection.seen_items.size()
	board.ledger.meta_hover_started.emit(quest_id)
	board.ledger.meta_hover_started.emit("Completed")
	board.ledger.meta_hover_started.emit("unknown-row")
	check(board.session.collection.seen_items.size() == seen_after, "repeat hover headers and unknown rows do not create read markers")
	var recipe: Dictionary = board.catalog.data.recipes[0]
	var recipe_id: String = str(recipe.fields.id)
	board.session._discover_recipe(recipe_id)
	board.active_tab = "recipes"
	board._refresh_ledger()
	check(board.session.collection.is_unread(recipe_id) and board.ledger_visible_ids.has(recipe_id), "opening recipe tab leaves visible recipe unread")
	board.detail_panel.hide()
	board.ledger.meta_hover_started.emit(recipe_id)
	check(board.session.collection.is_unread(recipe_id), "hidden ledger cannot mark a row read")
	board.detail_panel.show()
	board.ledger.meta_hover_started.emit(recipe_id)
	await process_frame
	check(board.session.collection.seen_items.has(recipe_id), "recipe hover records raw Recipe.Id independently")
	check(not board.session.collection.seen_items.has("Recipe:" + recipe_id), "read marker never uses dynamic card ID prefix")
	# Vendor tracker uses Collection, including recipe entries, without marking them seen.
	var tracked: String = board.vendor_guids[0]
	var progress: Dictionary = board.session.collection.pack_progress(tracked, board.session.discovered_recipes)
	check(board._pack_tracker(tracked) == ("COMPLETED" if progress.complete else "%d / %d found" % [progress.found, progress.total]), "vendor tracker matches source unique collection totals")
	for entry in board.catalog.data.cards: board.session.collection.mark_card(str(entry.guid))
	for entry in board.catalog.data.recipes: board.session._discover_recipe(str(entry.fields.id))
	board._refresh_collection_presentation()
	check(board._pack_tracker(tracked) == "COMPLETED" and board.vendor_buttons[tracked].text.contains("COMPLETED"), "completed collection label updates both model tracker and convenience shop")
	check(board._pack_tracker("").is_empty(), "zero-total/no-pack tracker stays empty")
	print("Trade/collection UI checks: %d passed / %d total" % [checks - failures, checks])
	board.queue_free()
	await process_frame
	await create_timer(0.5).timeout
	quit(0 if failures == 0 else 1)
