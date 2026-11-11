extends Node3D
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const SaveCodec = preload("res://scripts/model/save_codec.gd")
const AudioFeedback = preload("res://scripts/ui/audio_feedback.gd")
const VisualAssets = preload("res://scripts/ui/visual_assets.gd")
const SceneConfig = preload("res://scripts/ui/scene_config.gd")
var catalog = Catalog.new()
var visual_assets = VisualAssets.new()
var board_mesh: MeshInstance3D
var original_board: Node3D
var geometry_key: String = ""
var feedback = AudioFeedback.new()
var friendly_choice: CheckBox
var session = Session.new()
var camera: Camera3D
var views: Dictionary = {}
var running: bool = false
var selected: int = -1
var dragging: int = -1
var press_position := Vector2.ZERO
var drag_origin := Vector2.ZERO
var drag_delta := Vector2.ZERO
var drag_moved: bool = false
var hud: Control
var title_panel: PanelContainer
var title_status: Label
var status: Label
var inspection: Label
var ledger: RichTextLabel
var notice: Label
var day_button: Button
var pause_button: Button
var shop: VBoxContainer
var duration: HSlider
var continue_button: Button
var vendor_guids: Array[String] = []
var vendor_buttons: Dictionary = {}
var data_error: Error = OK
var refresh_clock: float = 0.0
var active_tab: String = "quests"

func _ready() -> void:
	add_child(feedback)
	_build_world()
	_build_ui()
	data_error = catalog.load_file()
	visual_assets.load_manifest()
	feedback.configure(catalog, visual_assets)
	feedback.play_music()
	if data_error != OK:
		title_status.text = "Source data is missing or invalid.\nImport your licensed StackCraft copy first:\npython tools/import_stackcraft.py --source /path/to/Assets/StackCraft --output data\nThen restart. See docs/data-import.md.\nNo replacement/mock game is loaded."
	else:
		title_status.text = "Original Godot geometry • source-backed rules\nMain and Island • native saves • optional original assets
Visual and manual input acceptance are not complete."
		vendor_guids = SceneConfig.offered_packs(catalog)
		_build_shop()
	continue_button.disabled = not _has_save()

func _build_world() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("10242c")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("b7ced0")
	world.environment.ambient_light_energy = 0.8
	add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-65, -20, 0)
	light.light_energy = 0.8
	add_child(light)
	var board := MeshInstance3D.new()
	board_mesh = board
	var mesh := BoxMesh.new()
	mesh.size = Vector3(28, 0.2, 22)
	board.mesh = mesh
	board.position.y = -0.2
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("25434a")
	board.material_override = material
	add_child(board)
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.size = 23
	camera.position = Vector3(0, 24, 8)
	add_child(camera)
	camera.look_at(Vector3.ZERO)
	camera.current = true

func _label(text: String, parent: Node, size: int = 16) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _button(text: String, parent: Node, callback: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.tooltip_text = text
	button.clip_text = true
	button.custom_minimum_size.y = 34
	button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _panel(parent: Node, rect: Rect2) -> VBoxContainer:
	var panel := PanelContainer.new()
	parent.add_child(panel)
	panel.position = rect.position
	panel.size = rect.size
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 14)
	panel.add_child(margin)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	margin.add_child(box)
	return box

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	layer.add_child(hud)
	hud.hide()
	var top := _panel(hud, Rect2(18, 16, 1404, 70))
	status = _label("", top, 19)
	var left := _panel(hud, Rect2(18, 100, 248, 600))
	_label("STACKCRAFT / MAIN", left, 22)
	pause_button = _button("Pause [Space]", left, _toggle_pause)
	var speeds := HBoxContainer.new()
	left.add_child(speeds)
	for speed in [1.0, 2.0, 3.0]:
		_button("%dx" % speed, speeds, func(): session.set_speed(speed))
	day_button = _button("", left, _advance_day)
	_button("Save", left, _save_game)
	_button("Save & title", left, _return_title)
	_label("MARKET", left, 20)
	var market_scroll := ScrollContainer.new()
	market_scroll.custom_minimum_size = Vector2(220, 250)
	market_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(market_scroll)
	shop = VBoxContainer.new()
	shop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	market_scroll.add_child(shop)
	_label("Select a card to inspect.\nClick a pack to draw.\nDrag a card and its tail.\nDrop on another stack to craft.\nDrop on empty board to split.\nRight-click to inspect a pack.\nWheel: zoom · WASD: pan", left, 13)
	var right := _panel(hud, Rect2(1174, 100, 248, 710))
	_label("INSPECT", right, 20)
	inspection = _label("Select a card", right)
	inspection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	inspection.custom_minimum_size.y = 125
	_button("Sell selected card", right, _sell_selected)
	_button("Sell selected stack", right, _sell_selected_stack)
	_button("Withdraw selected chest coin", right, _withdraw_selected)
	_button("Unequip selected character", right, _unequip_selected)
	_button("Engage selected enemy", right, _engage_selected)
	var tabs := HBoxContainer.new()
	right.add_child(tabs)
	_button("Quests", tabs, func(): active_tab = "quests"; _refresh_ledger())
	_button("Recipes", tabs, func(): active_tab = "recipes"; _refresh_ledger())
	ledger = RichTextLabel.new()
	ledger.custom_minimum_size = Vector2(210, 260)
	ledger.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(ledger)
	notice = _label("", hud, 16)
	notice.position = Vector2(285, 835)
	notice.size = Vector2(865, 50)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_panel = PanelContainer.new()
	layer.add_child(title_panel)
	title_panel.position = Vector2(380, 190)
	title_panel.size = Vector2(680, 480)
	var margin := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	title_panel.add_child(margin)
	var title := VBoxContainer.new()
	title.add_theme_constant_override("separation", 16)
	margin.add_child(title)
	_label("ABYSSAL GUILD", title, 36)
	_label("StackCraft · Godot migration", title, 22)
	title_status = _label("Loading source data…", title)
	title_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_label("Day duration · 60–180 seconds", title)
	duration = HSlider.new()
	duration.min_value = 60
	duration.max_value = 180
	duration.value = 120
	duration.step = 10
	title.add_child(duration)
	friendly_choice = CheckBox.new()
	friendly_choice.text = "Friendly mode (skip aggressive encounters)"
	title.add_child(friendly_choice)
	_button("New game", title, start_new)
	continue_button = _button("Continue", title, _continue_game)

func _build_shop() -> void:
	for child in shop.get_children():
		child.queue_free()
	vendor_buttons.clear()
	for guid in vendor_guids:
		vendor_buttons[guid] = _button(_name(guid), shop, _buy.bind(guid))
	if vendor_guids.is_empty():
		_label("No Main scene vendors resolved.\nCheck imported scene configuration.", shop, 13)

func start_new() -> void:
	if data_error != OK:
		return
	session = Session.new()
	session.configure(catalog, int(Time.get_unix_time_from_system()))
	session.day_duration = duration.value
	session.friendly_mode = friendly_choice.button_pressed
	if session.start_new_game() < 0:
		title_status.text = "Starter pack is absent from the source data. Reimport and verify data."
		return
	_enter_game()

func _enter_game() -> void:
	if not session.event_occurred.is_connected(_on_session_event):
		session.event_occurred.connect(_on_session_event)
	vendor_guids = SceneConfig.offered_packs(catalog, session.scene_name)
	_build_shop()
	visual_assets.apply_scene(camera, board_mesh, session.scene_name)
	# Original mesh is optional; validated source vertex bounds remain the fallback.
	geometry_key = ""
	_update_board_geometry()
	session.ai.point_validator = _ai_point_valid
	session.ai.combat_geometry = _combat_geometry
	for view in views.values(): view.queue_free()
	views.clear()
	running = true
	selected = -1
	title_panel.hide()
	hud.show()
	_refresh()

func _process(delta: float) -> void:
	if not running:
		return
	session.tick(delta)
	_sync_views()
	refresh_clock += delta
	if refresh_clock >= 0.2:
		refresh_clock = 0
		_refresh()
	var direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_A): direction.x -= 1
	if Input.is_physical_key_pressed(KEY_D): direction.x += 1
	if Input.is_physical_key_pressed(KEY_W): direction.z -= 1
	if Input.is_physical_key_pressed(KEY_S): direction.z += 1
	camera.position += direction * delta * 8
	camera.position.x = clampf(camera.position.x, -10, 10)
	camera.position.z = clampf(camera.position.z, 0, 16)

func _name(guid: String) -> String:
	var fields: Dictionary = catalog.fields(guid)
	return str(fields.get("displayName", fields.get("id", guid)))

func _sync_views() -> void:
	for id in views.keys():
		if not session.cards.has(id):
			views[id].queue_free()
			views.erase(id)
	for id in session.cards:
		if views.has(id) and views[id].get_meta("definition_guid", "") != session.cards[id].definition_guid:
			views[id].hide()
			views[id].queue_free()
			views.erase(id)
		if not views.has(id):
			var card = session.cards[id]
			var view = CardView.new()
			add_child(view)
			view.configure(id, _name(card.definition_guid), int(catalog.fields(card.definition_guid).get("category", 0)), catalog.get_definition(card.definition_guid).get("script_class", "") == "PackDefinition", visual_assets, catalog.fields(card.definition_guid), session.scene_name)
			view.set_meta("definition_guid", card.definition_guid)
			views[id] = view
		views[id].visible = not session.equipment.owners.has(id)
		for child in views[id].get_children():
			if child is StaticBody3D: child.collision_layer = 1 if views[id].visible else 0
		views[id].caption.text = _name(session.cards[id].definition_guid)
		views[id].highlight(id == selected)
		if session.combat.membership.has(id):
			views[id].position = Vector3(session.cards[id].position.x, 0.12, session.cards[id].position.y)
	for stack in session.stacks.values():
		for index in range(stack.card_ids.size()):
			var id: int = stack.card_ids[index]
			var card = session.cards[id]
			if not views.has(id):
				var view = CardView.new()
				add_child(view)
				view.configure(id, _name(card.definition_guid), int(catalog.fields(card.definition_guid).get("category", 0)), catalog.get_definition(card.definition_guid).get("script_class", "") == "PackDefinition", visual_assets, catalog.fields(card.definition_guid), session.scene_name)
				view.set_meta("definition_guid", card.definition_guid)
				views[id] = view
			var offset := Vector2.ZERO
			if dragging >= 0 and session.cards.has(dragging) and card.stack_id == session.cards[dragging].stack_id and index >= stack.card_ids.find(dragging):
				offset = drag_delta
			views[id].position = Vector3(stack.position.x + offset.x, 0.06 + index * _stack_step().y, stack.position.y + offset.y + index * _stack_step().z)
			views[id].highlight(id == selected)

func _pick(screen: Vector2) -> int:
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 100)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return -1
	return int(hit.collider.get_meta("card_id", -1))

func _board_point(screen: Vector2) -> Vector2:
	var point = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if point == null: return Vector2.ZERO
	return Vector2(point.x, point.z)

func _unhandled_input(event: InputEvent) -> void:
	if not running: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_toggle_pause()
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			camera.size = clampf(camera.size + (-1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1), 12, 34)
		if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
			selected = _pick(event.position)
			_refresh()
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				selected = _pick(event.position)
				dragging = selected if not session.combat.membership.has(selected) else -1
				if dragging >= 0:
					session.combat.dragged[dragging] = true
					feedback.play_event("CardPick")
				press_position = event.position
				drag_origin = _board_point(event.position)
				drag_delta = Vector2.ZERO
				drag_moved = false
			else:
				_finish_drag(event.position)
	if event is InputEventMouseMotion and dragging >= 0:
		drag_moved = drag_moved or event.position.distance_to(press_position) > 7
		if drag_moved: drag_delta = _board_point(event.position) - drag_origin

# Releases over a panel still terminate a drag. GUI should never leave cards attached.
func _input(event: InputEvent) -> void:
	if running and dragging >= 0 and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered != null and hovered != hud:
			session.combat.dragged.clear()
			dragging = -1
			drag_delta = Vector2.ZERO
		else:
			_finish_drag(event.position)

func _finish_drag(screen: Vector2) -> void:
	var id: int = dragging
	session.combat.dragged.clear()
	dragging = -1
	if not session.cards.has(id): return
	feedback.play_event("CardDrop")
	if drag_moved:
		var stack = session.stacks[session.cards[id].stack_id]
		var destination: Vector2 = stack.position + drag_delta
		var target: int = -1
		var best: float = 1.15
		# Explicit stack footprint hit test avoids picking our own dragged collider.
		var drop: Vector2 = _board_point(screen)
		for other in session.stacks.values():
			if other.id == stack.id: continue
			for index in range(other.card_ids.size()):
				var distance: float = drop.distance_to(other.position + Vector2(0, index * _stack_step().z))
				if distance < best:
					best = distance
					target = other.id
		if target >= 0:
			var target_card: int = session.stacks[target].card_ids[0]
			if catalog.get_definition(session.cards[target_card].base_definition_guid).get("script_class", "") == "ChestDefinition":
				var dropped: int = session.split_stack(id, stack.position)
				var result: Dictionary = session.world.deposit_stack(target_card, dropped)
				if result.handled:
					notice.text = "Stored %d coins." % result.deposited
				elif not session.move_to_stack(id, target):
					notice.text = "Chest accepts currency; this stack cannot join."
			elif int(catalog.fields(session.cards[id].definition_guid).get("category", 0)) == 5 and int(catalog.fields(session.cards[target_card].definition_guid).get("category", 0)) == 2:
				if stack.card_ids.back() != id:
					notice.text = "Split equipment from its tail before equipping."
				else:
					notice.text = "Equipped." if session.equipment.equip(target_card, id) else "Cannot equip this item."
			elif not session.move_to_stack(id, target): notice.text = "These cards cannot stack, or the current recipe rejects extra ingredients."
		else:
			destination = _clamp_stack_position(id, destination)
			session.split_stack(id, destination)
	else:
		if catalog.get_definition(session.cards[id].definition_guid).get("script_class", "") == "PackDefinition":
			var spawned: int = session.open_pack(id)
			# Separate each drawn card so the pack remains clickable.
			if spawned >= 0: session.split_stack(spawned, session.cards[spawned].position + Vector2(1.7, float(spawned % 4) * 0.5))
	drag_delta = Vector2.ZERO
	_refresh()

func _refresh() -> void:
	_update_board_geometry()
	_sync_views()
	var stats: Dictionary = session.stats()
	status.text = "Day %d  ·  %.0f / %.0f s  ·  %s  |  Coins %d  ·  Food %d / %d  ·  Cards %d / %d" % [session.day, session.elapsed, session.day_duration, session.phase.to_upper() + (" / PAUSED" if session.paused else " / %.0fx" % session.speed), stats.currency, stats.nutrition, stats.nutrition_need, stats.cards_owned, stats.card_limit]
	pause_button.text = "Resume [Space]" if session.paused else "Pause [Space]"
	pause_button.disabled = session.phase != "playing"
	day_button.text = {"playing": "End day & feed", "feeding": "Feed villagers", "selling": "Sell %d excess cards" % stats.excess, "ready": "Start next day", "game_over": "Game over · return to title"}.get(session.phase, session.phase)
	day_button.disabled = session.phase == "selling"
	for guid in vendor_buttons:
		var fields: Dictionary = catalog.fields(guid)
		var minimum: int = int(fields.get("minQuests", 0))
		var price: int = maxi(0, int(fields.get("buyPrice", 3)) - int(session.vendor_payments.get(guid, 0)))
		vendor_buttons[guid].text = "%s · %d coins%s" % [_name(guid), price, " · locked" if session.completed_quests < minimum else ""]
		vendor_buttons[guid].disabled = session.phase != "playing" or session.completed_quests < minimum or stats.currency < price
	inspection.text = "Select a card"
	if session.cards.has(selected):
		var card = session.cards[selected]
		var fields: Dictionary = catalog.fields(card.definition_guid)
		inspection.text = "%s\n%s\nHealth %d · Food %d · Uses %d\nSell: %s" % [_name(card.definition_guid), str(fields.get("description", "")), card.health, card.nutrition, card.uses_left, str(fields.get("sellPrice", 1)) if fields.get("isSellable", true) else "not sellable"]
		var category: int = int(fields.get("category", 0))
		if category in [2, 9]:
			var combat_stats: Dictionary = session.equipment.stats(selected)
			inspection.text += "\nAttack %d · Defense %d" % [combat_stats.attack, combat_stats.defense]
			if session.combat.membership.has(selected): inspection.text += "\nIN COMBAT"
			for item in session.equipment.equipped.get(selected, {}).values():
				inspection.text += "\nEquipped: " + _name(session.cards[item].definition_guid)
		var stack = session.stacks.get(card.stack_id)
		if stack != null and not stack.recipe_guid.is_empty(): inspection.text += "\nCraft: %.1f / %.1f s" % [stack.progress, float(catalog.fields(stack.recipe_guid).get("craftingDuration", 5))]
	_refresh_ledger()

func _refresh_ledger() -> void:
	var lines: Array[String] = []
	if active_tab == "quests":
		lines.append("Completed: %d\n" % session.completed_quests)
		for instance in session.quest_tracker.active_quests:
			var fields: Dictionary = session.quest_tracker.definitions.get(instance.id, {})
			lines.append("%s  (%d/%d)\n%s\n" % [fields.get("title", instance.id), instance.current_amount, int(fields.get("targetAmount", 1)), fields.get("description", "")])
		if session.quest_tracker.active_quests.is_empty(): lines.append("No active quests. Check scene import if this is unexpected.")
	else:
		for recipe in catalog.data.get("recipes", []):
			if not session.discovered_recipes.has(str(recipe.fields.get("id", ""))): continue
			var ingredients: Array[String] = []
			for ingredient in recipe.fields.get("requiredIngredients", []):
				ingredients.append("%d %s" % [int(ingredient.get("count", 1)), _name(catalog.ref_guid(ingredient.get("card", {})))])
			lines.append("%s → %s\n" % [" + ".join(ingredients), _name(catalog.ref_guid(recipe.fields.get("resultingCard", {})))])
		if lines.is_empty(): lines.append("Discover recipes by combining cards or opening packs.")
	ledger.text = "\n".join(lines)

func _toggle_pause() -> void:
	if session.phase == "playing": session.set_paused(not session.paused)
	_refresh()

func _advance_day() -> void:
	match session.phase:
		"playing", "feeding": session.end_day()
		"ready": session.start_day()
		"game_over": _return_title()
	_refresh()

func _buy(guid: String) -> void:
	if session.phase != "playing" or not vendor_guids.has(guid): return
	var id: int = session.buy_pack(guid)
	notice.text = "Purchased " + _name(guid) if id >= 0 else "Pack unavailable: check currency and completed quests."
	if id >= 0: session.split_stack(id, Vector2(-4 + vendor_guids.find(guid) * 1.8, -4))
	_refresh()

func _sell_selected() -> void:
	if session.phase == "game_over" or session.combat.membership.has(selected): return
	notice.text = "Card sold." if session.sell_card(selected) else "Select a sellable card. Empty coin storage first."
	_refresh()

func _sell_selected_stack() -> void:
	if session.phase == "game_over" or not session.cards.has(selected) or session.combat.membership.has(selected): return
	notice.text = "Stack sold." if session.sell_stack(session.cards[selected].stack_id) else "This stack contains a card that cannot be sold."
	_refresh()

func _has_save() -> bool:
	return FileAccess.file_exists("user://session.json") or FileAccess.file_exists("user://session.json.bak")

func _save_game() -> void:
	var result: Dictionary = session.campaign.save_file("user://session.json")
	notice.text = "Saved locally." if result.ok else "Save failed: " + str(result.get("error", "Unknown error"))

func _continue_game() -> void:
	if data_error != OK: return
	var candidate = Session.new()
	candidate.configure(catalog)
	var result: Dictionary = candidate.campaign.load_file("user://session.json")
	if not result.ok:
		title_status.text = "Cannot continue: " + str(result.get("error", "Unknown error"))
		return
	session = candidate
	_enter_game()
	notice.text = "Save restored." + (" Recovered from backup." if result.get("recovered", false) else "")

func _return_title() -> void:
	var result: Dictionary = session.campaign.save_file("user://session.json")
	if not result.ok:
		notice.text = "Could not save; session kept open: " + str(result.get("error", "Unknown error"))
		return
	running = false
	dragging = -1
	hud.hide()
	title_panel.show()
	continue_button.disabled = not _has_save()
	for view in views.values(): view.hide()

func _unequip_selected() -> void:
	if session.phase != "playing" or not session.cards.has(selected) or session.combat.membership.has(selected): return
	session.equipment.unequip_all(selected)
	_refresh()

func _engage_selected() -> void:
	if session.phase != "playing" or not session.cards.has(selected) or session.combat.membership.has(selected): return
	if int(catalog.fields(session.cards[selected].definition_guid).get("faction", 0)) != 2:
		notice.text = "Select an enemy; the nearest available friendly will engage."
		return
	var fighter: int = -1
	var nearest: float = INF
	for card in session.cards.values():
		var fields: Dictionary = catalog.fields(card.definition_guid)
		if int(fields.get("faction", 0)) != 1 or int(fields.get("category", 0)) not in [2, 9] or session.combat.membership.has(card.id): continue
		var distance: float = card.position.distance_squared_to(session.cards[selected].position)
		if distance < nearest:
			nearest = distance
			fighter = card.id
	if fighter < 0:
		notice.text = "No available friendly combatant."
		return
	var result: int = session.combat.start_combat([fighter], [selected])
	notice.text = "Combat started. Select a fighter to inspect health." if result >= 0 else "Cannot start combat."
	_refresh()

func _on_session_event(kind: String, payload: Dictionary) -> void:
	if kind == "scene_changed":
		_enter_game()
		notice.text = "Arrived at " + session.scene_name
	elif kind == "travel_failed":
		notice.text = "Travel failed: " + str(payload.get("error", ""))
	if kind == "pack_purchased": feedback.play_event("CashRegister")
	elif kind == "cards_sold": feedback.play_event("Coins")
	elif kind == "crafted": feedback.play_event("Pop")
	elif kind == "combat_hit":
		var combat_type: int = int(catalog.fields(session.cards[int(payload.attacker_id)].definition_guid).get("combatType", 0))
		var style: String = ["Melee", "Melee", "Ranged", "Magic"][clampi(combat_type, 0, 3)]
		feedback.play_event("Attack" + style)
		feedback.play_event("Miss" if payload.result.type == "miss" else ("Critical" if payload.result.type == "critical" else "Hit" + style))
	elif kind == "encounter":
		notice.text = "Event: " + str(payload.get("message", ""))

func _withdraw_selected() -> void:
	if session.phase != "playing" or not session.world.can_click_chest(selected):
		notice.text = "Select an unstacked chest to withdraw a coin."
		return
	var position: Vector2 = _clamp_stack_position(selected, session.cards[selected].position + Vector2(1.7, 0))
	notice.text = "Withdrew a coin." if session.world.withdraw_coin(selected, true, position) else "Chest is empty."
	_refresh()

func _stack_step() -> Vector3:
	var step: Dictionary = catalog.settings("CardSettings").get("stackStep", {})
	return Vector3(float(step.get("x", 0)), float(step.get("y", 0.002)), float(step.get("z", -0.18)))

func _card_footprint(id: int) -> Vector2:
	if not session.cards.has(id): return Vector2.ZERO
	var fields: Dictionary = catalog.fields(session.cards[id].definition_guid)
	var appearance: Dictionary = visual_assets.appearance(int(fields.get("category", 0)), catalog.get_definition(session.cards[id].definition_guid).get("script_class", "") == "PackDefinition", fields, session.scene_name)
	var size: Dictionary = appearance.get("prefab", {}).get("size", {})
	return Vector2(float(size.get("x", 1.4)), float(size.get("z", 1.95)))

func _update_board_geometry() -> void:
	if session.catalog == null: return
	var base_limit: int = int(catalog.settings("CardSettings").get("baseCardLimit", 24))
	var boost: float = clampf((session.stats().card_limit - base_limit) / 100.0, 0.0, 1.0)
	var key: String = session.scene_name + ":" + str(boost)
	if key == geometry_key: return
	geometry_key = key
	var bounds: Rect2 = visual_assets.board_local_rect(session.scene_name, boost)
	if not bounds.has_area():
		# Verified original Board.fbx vertices: 12x8 base, 24x16 Scale target.
		bounds = Rect2(Vector2(-6, -4) * (1.0 + boost), Vector2(12, 8) * (1.0 + boost))
	var old_bounds: Variant = session.board_bounds
	session.board_bounds = bounds
	if original_board != null:
		original_board.hide()
		original_board.queue_free()
	original_board = visual_assets.create_board_mesh(session.scene_name, boost)
	if original_board != null:
		add_child(original_board)
		original_board.position.y = -0.05
		board_mesh.hide()
	else:
		board_mesh.show()
		board_mesh.mesh.size = Vector3(bounds.size.x, 0.2, bounds.size.y)
		visual_assets.apply_scene(camera, board_mesh, session.scene_name)
	if old_bounds is Rect2 and bounds.get_area() < old_bounds.get_area():
		for stack in session.stacks.values():
			stack.position = _clamp_stack_position(stack.card_ids[0], stack.position)
			for id in stack.card_ids: session.cards[id].position = stack.position

func _clamp_stack_position(card_id: int, point: Vector2) -> Vector2:
	if not session.board_bounds is Rect2: return point
	var bounds: Rect2 = session.board_bounds
	var footprint: Vector2 = _card_footprint(card_id)
	var stack = session.stacks.get(session.cards[card_id].stack_id)
	var count: int = 1 if stack == null else stack.card_ids.size() - stack.card_ids.find(card_id)
	var min_x: float = bounds.position.x + footprint.x * 0.5
	var max_x: float = bounds.end.x - footprint.x * 0.5
	var min_z: float = bounds.position.y + footprint.y * 0.5 + (count - 1) * absf(_stack_step().z)
	var max_z: float = bounds.end.y - session.board_top_margin - footprint.y * 0.5
	return Vector2(clampf(point.x, min_x, max_x), clampf(point.y, min_z, max_z))

func _ai_point_valid(point: Vector2, stack_id: int) -> bool:
	if not session.board_bounds is Rect2 or not session.stacks.has(stack_id): return false
	return session.ai.point_in_board(point, session.board_bounds, _card_footprint(session.stacks[stack_id].card_ids[0]), session.board_top_margin)

func _combat_geometry() -> Array:
	var result: Array = []
	for id in session.combat.tasks:
		var task: Dictionary = session.combat.tasks[id]
		var position := Vector2.ZERO
		var count: int = 0
		var has_player: bool = false
		for card_id in task.attackers + task.defenders:
			if not session.cards.has(card_id): continue
			position += session.cards[card_id].position
			count += 1
			has_player = has_player or int(catalog.fields(session.cards[card_id].definition_guid).get("faction", 0)) == 1
		if count > 0: result.append({"id": id, "ongoing": true, "has_player": has_player, "position": position / count})
	return result
