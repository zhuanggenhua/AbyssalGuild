extends Node3D
const CyclePresentation = preload("res://scripts/ui/cycle_presentation.gd")
const CameraMotion = preload("res://scripts/ui/camera_motion.gd")
const CombatPresentation = preload("res://scripts/ui/combat_presentation.gd")
const EquipmentDisplay = preload("res://scripts/ui/equipment_display_controller.gd")
const ImpactFeedback = preload("res://scripts/model/impact_feedback.gd")
const ImpactView = preload("res://scripts/ui/impact_view.gd")
const CombatMergeGeometry = preload("res://scripts/model/combat_merge_geometry.gd")
const CombatLayout = preload("res://scripts/model/combat_layout.gd")
const BoardLayout = preload("res://scripts/model/board_layout.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const OptionsPanel = preload("res://scripts/ui/options_panel.gd")
const OptionsAdapter = preload("res://scripts/ui/options_adapter.gd")
const TradeLayout = preload("res://scripts/model/trade_layout.gd")
const TradeZoneView = preload("res://scripts/ui/trade_zone_view.gd")
const SaveSlots = preload("res://scripts/model/save_slots.gd")
const SaveCodec = preload("res://scripts/model/save_codec.gd")
const AudioFeedback = preload("res://scripts/ui/audio_feedback.gd")
const VisualAssets = preload("res://scripts/ui/visual_assets.gd")
const SceneConfig = preload("res://scripts/ui/scene_config.gd")
var catalog = Catalog.new()
var visual_assets = VisualAssets.new()
var board_mesh: MeshInstance3D
var original_board: Node3D
var geometry_key: String = ""
var layout_key: String = ""
var layout_locks: Dictionary = {}
var combat_layouts: Dictionary = {}
var combat_rectangles: Dictionary = {}
var puffs: Array[Node3D] = []
var puff_rng := RandomNumberGenerator.new()
var puff_factory: Callable = Callable()
var camera_motion = CameraMotion.new()
var combat_presentation = CombatPresentation.new()
var equipment_display = EquipmentDisplay.new()
var pressed_panel: int = -1
var right_pressed_panel: int = -1
var feedback = AudioFeedback.new()
var slot_root: String = "user://slots"
var legacy_paths: Array[String] = ["user://session.json", "user://campaign.json"]
var slots = SaveSlots.new()
var options_path: String = "user://options.json"
var options_apply_adapter: Callable = Callable()
var options_hardware_modes: Array = []
var native_options_adapter = OptionsAdapter.new()
var options_panel
var pause_overlay: Control
var trade_zones: Array = []
var trade_views: Dictionary = {}
var trade_activated: Dictionary = {}
var ledger_visible_ids: Dictionary = {}
var ledger_key: String = ""
var collection_refresh_pending: bool = false
var active_slot: int = 0
var selected_slot: int = 0
var slot_picker: OptionButton
var legacy_picker: OptionButton
var legacy_button: Button
var game_over_dialog: ConfirmationDialog
var quit_dialog: ConfirmationDialog
var friendly_choice: CheckBox
var session = Session.new()
var camera: Camera3D
var source_light: DirectionalLight3D
var panning: bool = false
var views: Dictionary = {}
var running: bool = false
var selected: int = -1
var dragging: int = -1
var press_position := Vector2.ZERO
var drag_grant: int = -1
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
var market_panel: Control
var detail_panel: Control
var duration: HSlider
var continue_button: Button
var vendor_guids: Array[String] = []
var vendor_buttons: Dictionary = {}
var data_error: Error = OK
var refresh_clock: float = 0.0
var active_tab: String = "quests"

func _ready() -> void:
	puff_rng.randomize()
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
	native_options_adapter.configure(feedback)
	var options_adapter: Callable = options_apply_adapter if options_apply_adapter.is_valid() else native_options_adapter.apply
	var options_loaded: Dictionary = options_panel.configure(options_adapter, options_hardware_modes, options_path)
	if not options_loaded.ok: title_status.text += "\nOptions could not be read; defaults are in use. Open Options for details."
	get_tree().auto_accept_quit = false
	if data_error == OK:
		session.configure(catalog)
		slots.configure(session.campaign, slot_root)
		_refresh_slots()

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
	source_light = light
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
	market_panel = left.get_parent().get_parent()
	market_panel.hide()
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
	detail_panel = right.get_parent().get_parent()
	detail_panel.hide()
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
	ledger.meta_hover_started.connect(_on_ledger_hover)
	ledger.custom_minimum_size = Vector2(210, 260)
	ledger.size_flags_vertical = Control.SIZE_EXPAND_FILL
	right.add_child(ledger)
	var market_toggle := _button("Market & controls", hud, func(): market_panel.visible = not market_panel.visible)
	market_toggle.position = Vector2(18, 835)
	market_toggle.size = Vector2(248, 40)
	var detail_toggle := _button("Inspect & journal", hud, func(): detail_panel.visible = not detail_panel.visible)
	detail_toggle.position = Vector2(1174, 835)
	detail_toggle.size = Vector2(248, 40)
	notice = _label("", hud, 16)
	notice.position = Vector2(285, 835)
	notice.size = Vector2(865, 50)
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_panel = PanelContainer.new()
	layer.add_child(title_panel)
	title_panel.position = Vector2(380, 90)
	title_panel.size = Vector2(680, 710)
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
	_label("Saved games · native slots", title)
	slot_picker = OptionButton.new()
	slot_picker.item_selected.connect(_select_slot)
	title.add_child(slot_picker)
	_button("New game · new slot", title, start_new)
	continue_button = _button("Continue selected slot", title, _continue_game)
	continue_button.disabled = true
	legacy_picker = OptionButton.new()
	title.add_child(legacy_picker)
	legacy_button = _button("Copy legacy save into a new slot", title, _adopt_selected_legacy)
	legacy_button.hide()
	legacy_picker.hide()
	game_over_dialog = ConfirmationDialog.new()
	game_over_dialog.title = "Return to Title"
	game_over_dialog.dialog_text = "This game has ended. Return to Title and move this slot, including backups, into the recoverable local archive?"
	game_over_dialog.ok_button_text = "Archive slot & return"
	game_over_dialog.confirmed.connect(_confirm_game_over_return)
	add_child(game_over_dialog)
	quit_dialog = ConfirmationDialog.new()
	quit_dialog.title = "Quit during day-end?"
	quit_dialog.dialog_text = "Day-end progress is not autosaved on quit. Your last checkpoint stays intact. Quit now?"
	quit_dialog.confirmed.connect(func(): get_tree().quit())
	add_child(quit_dialog)
	_button("Options", title, _open_options)
	_build_pause_options(layer)

func _build_shop() -> void:
	for child in shop.get_children():
		child.queue_free()
	vendor_buttons.clear()
	for guid in vendor_guids:
		vendor_buttons[guid] = _button(_name(guid), shop, _buy.bind(guid))
	if vendor_guids.is_empty():
		_label("No Main scene vendors resolved.\nCheck imported scene configuration.", shop, 13)

func start_new() -> void:
	if data_error != OK: return
	var candidate = Session.new()
	candidate.configure(catalog, int(Time.get_unix_time_from_system()))
	candidate.day_duration = duration.value
	candidate.friendly_mode = friendly_choice.button_pressed
	if candidate.start_new_game() < 0:
		title_status.text = "Starter pack is absent from the source data. Reimport and verify data."
		return
	var candidate_slots = SaveSlots.new()
	candidate_slots.configure(candidate.campaign, slot_root)
	var result: Dictionary = candidate_slots.create_slot()
	if not result.ok:
		title_status.text = "Cannot create game slot: " + str(result.error)
		notice.text = title_status.text
		return
	session = candidate
	slots = candidate_slots
	active_slot = int(result.slot)
	selected_slot = active_slot
	_enter_game()
	notice.text = "Created slot %d. Existing saves were kept." % active_slot

func _enter_game() -> void:
	_clear_puffs()
	drag_grant = -1
	session.cycle.pose_sampler = _sample_cycle_pose
	session.cycle.layout_resolver = _resolve_layout
	combat_presentation.reset()
	camera.h_offset = 0
	camera.v_offset = 0
	equipment_display.reset()
	pause_overlay.hide()
	for zone in trade_views.values(): zone.queue_free()
	trade_views.clear()
	trade_zones.clear()
	trade_activated.clear()
	ledger_key = ""
	if not session.collection.changed.is_connected(_collection_changed):
		session.collection.changed.connect(_collection_changed)
	slots.configure(session.campaign, slot_root)
	session.campaign.before_travel = _departure_checkpoint
	session.combat.start_overlap_selector = _combat_start_overlaps
	session.combat.resize_overlap_selector = _combat_resize_overlaps
	for rectangle in combat_rectangles.values(): rectangle.queue_free()
	combat_rectangles.clear()
	combat_layouts.clear()
	if not session.event_occurred.is_connected(_on_session_event):
		session.event_occurred.connect(_on_session_event)
	vendor_guids = SceneConfig.offered_packs(catalog, session.scene_name)
	_build_shop()
	visual_assets.apply_scene(camera, board_mesh, session.scene_name)
	visual_assets.apply_source_camera(camera, session.scene_name)
	camera_motion.configure(camera.position, CameraMotion.source_settings(catalog.data, session.scene_name))
	panning = false
	visual_assets.apply_source_light(source_light, session.scene_name)
	# Original mesh is optional; validated source vertex bounds remain the fallback.
	geometry_key = ""
	_update_board_geometry()
	session.ai.point_validator = _ai_point_valid
	session.ai.combat_geometry = _combat_geometry
	session.ai.produce_spawner = Callable()
	session.spawn_target_selector = _select_spawn_target
	session.spawn_layout_resolver = _resolve_layout
	layout_locks.clear()
	layout_key = ""
	for view in views.values(): view.queue_free()
	views.clear()
	running = true
	selected = -1
	title_panel.hide()
	hud.show()
	_refresh()
	var focus: Dictionary = session.cycle.focus_state()
	if not focus.is_empty(): _focus_camera_position(focus.target_position, float(focus.duration))

func _process(delta: float) -> void:
	if not running:
		return
	var scaled_delta: float = delta * session.speed if session.phase == "playing" and not session.paused and not _ui_pause_active() else 0.0
	_advance_puffs(delta, scaled_delta)
	_update_camera_motion(delta)
	combat_presentation.advance(delta)
	if _ui_pause_active():
		# Travel/return use real time even under an external menu pause.
		session.combat.tick(0.0, delta)
		session.cycle.advance(delta)
		_sync_views()
		return
	session.tick(delta)
	equipment_display.advance(scaled_delta)
	_sync_views()
	refresh_clock += delta
	if refresh_clock >= 0.2:
		refresh_clock = 0
		_refresh()

func _name(guid: String) -> String:
	var fields: Dictionary = catalog.fields(guid)
	return str(fields.get("displayName", fields.get("id", guid)))

func _sync_views() -> void:
	_sync_combat_layouts()
	_ensure_layout()
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
			view.configure(id, _name(card.definition_guid), int(catalog.fields(card.definition_guid).get("category", 0)), catalog.get_definition(card.definition_guid).get("script_class", "") == "PackDefinition", visual_assets, catalog.fields(card.definition_guid), session.scene_name, _card_collider_size(id))
			view.set_meta("definition_guid", card.definition_guid)
			views[id] = view
		views[id].visible = not session.equipment.owners.has(id)
		for child in views[id].get_children():
			if child is StaticBody3D: child.collision_layer = 1 if views[id].visible else 0
		views[id].caption.text = _name(session.cards[id].definition_guid)
		var current_card = session.cards[id]
		var current_fields: Dictionary = catalog.fields(current_card.definition_guid)
		var display_state := {"health": current_card.health, "nutrition": current_card.nutrition, "sell_price": int(current_fields.get("sellPrice", 1)), "equipment_slots": session.equipment.equipped.get(id, {}).keys()}
		if session.world._is_chest(id): display_state["price_override"] = str(current_card.stored_coins)
		views[id].update_state(display_state)
		views[id].highlight(id == selected)
		if session.combat.membership.has(id):
			var combat_position: Vector2 = session.cards[id].position + (drag_delta if dragging == id else Vector2.ZERO)
			views[id].position = Vector3(combat_position.x, 0.12, -combat_position.y)
	for stack in session.stacks.values():
		for index in range(stack.card_ids.size()):
			var id: int = stack.card_ids[index]
			var card = session.cards[id]
			if not views.has(id):
				var view = CardView.new()
				add_child(view)
				view.configure(id, _name(card.definition_guid), int(catalog.fields(card.definition_guid).get("category", 0)), catalog.get_definition(card.definition_guid).get("script_class", "") == "PackDefinition", visual_assets, catalog.fields(card.definition_guid), session.scene_name, _card_collider_size(id))
				view.set_meta("definition_guid", card.definition_guid)
				views[id] = view
			var offset := Vector2.ZERO
			if dragging >= 0 and session.cards.has(dragging) and card.stack_id == session.cards[dragging].stack_id and index >= stack.card_ids.find(dragging):
				offset = drag_delta
			views[id].position = Vector3(stack.position.x + offset.x, 0.06 + index * _stack_step().y, -(stack.position.y + offset.y + index * _stack_step().z))
			views[id].highlight(id == selected)
	var durations := {0: 0.3, 1: 0.3, 2: session.combat.projectile_duration(2), 3: session.combat.projectile_duration(3)}
	combat_presentation.visual_assets = visual_assets
	combat_presentation.scene_name = session.scene_name
	combat_presentation.sync(session.combat.tasks, views, durations, self)
	var shake: Vector2 = combat_presentation.camera_offset()
	camera.h_offset = shake.x
	camera.v_offset = shake.y
	CyclePresentation.apply(session.cycle.presentation_state(), views)
	_sync_equipment_display()

func _pick_target(screen: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 100)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {"card_id": -1, "panel_owner": -1}
	return {"card_id": int(hit.collider.get_meta("card_id", -1)), "panel_owner": int(hit.collider.get_meta("equipment_panel_owner", -1))}

func _pick(screen: Vector2) -> int:
	return int(_pick_target(screen).card_id)

func _sync_equipment_display() -> void:
	var metadata: Dictionary = {}
	for id in views:
		if not session.cards.has(id): continue
		var fields: Dictionary = catalog.fields(session.cards[id].definition_guid)
		var appearance: Dictionary = visual_assets.appearance(int(fields.get("category", 0)), false, fields, session.scene_name)
		var panel: Dictionary = appearance.get("prefab", {}).get("equipment_panel", {})
		if not panel.is_empty(): metadata[id] = panel
	equipment_display.sync(session.equipment.equipped, views, metadata, session.phase == "playing")

# Pointer routing is separate from ray casting for deterministic adapter tests.
func _begin_card_press(hit: Dictionary, screen: Vector2) -> void:
	drag_grant = -1
	var id: int = int(hit.get("card_id", -1))
	var panel: int = int(hit.get("panel_owner", -1))
	var is_gear: bool = session.cards.has(id) and int(catalog.fields(session.cards[id].definition_guid).get("category", 0)) == 5
	equipment_display.pointer_down(panel, is_gear)
	selected = id
	if panel >= 0:
		pressed_panel = panel if _allows_card_actions() else -1
		dragging = -1
		return
	pressed_panel = -1
	if is_gear and session.equipment.owners.has(id) and _allows_card_actions():
		var wearer: int = session.equipment.owners[id]
		var old_position: Vector3 = views[id].global_position
		for slot in session.equipment.equipped.get(wearer, {}):
			if session.equipment.equipped[wearer][slot] == id:
				session.equipment.unequip(wearer, slot)
				_set_board_card_position(id, Vector2(old_position.x, -old_position.z))
				break
		dragging = id # Lock the just-detached stack before placement can move its visible pose.
		_sync_views()
	dragging = id if _can_drag_card(id) else -1
	drag_grant = dragging
	if dragging >= 0:
		session.combat.dragged[dragging] = true
		feedback.play_event("CardPick")
	press_position = screen
	drag_origin = _board_point(screen)
	drag_delta = Vector2.ZERO
	drag_moved = false

func _board_point(screen: Vector2) -> Vector2:
	var point = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if point == null: return Vector2.ZERO
	return Vector2(point.x, -point.z)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		_handle_escape()
		return
	if not running or _ui_pause_active(): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_SPACE:
		_toggle_pause()
	if event is InputEventMouseButton:
		if event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			_zoom_camera(1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0)
		if event.button_index == MOUSE_BUTTON_MIDDLE:
			panning = event.pressed and _camera_input_enabled()
		if event.button_index == MOUSE_BUTTON_RIGHT:
			var right_hit: Dictionary = _pick_target(event.position)
			if event.pressed:
				selected = int(right_hit.card_id)
				right_pressed_panel = int(right_hit.panel_owner)
				_refresh()
			else:
				if _allows_card_actions() and right_pressed_panel >= 0 and right_pressed_panel == int(right_hit.panel_owner): equipment_display.click_panel(right_pressed_panel)
				right_pressed_panel = -1
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var hit: Dictionary = _pick_target(event.position)
				panning = _camera_input_enabled() and int(hit.card_id) < 0
				_begin_card_press(hit, event.position)
			else:
				panning = false
				_finish_drag(event.position)
	if event is InputEventMouseMotion and dragging >= 0:
		drag_moved = drag_moved or event.position.distance_to(press_position) > 7
		if drag_moved: drag_delta = _board_point(event.position) - drag_origin

# Releases over a panel still terminate a drag. GUI should never leave cards attached.
func _input(event: InputEvent) -> void:
	# Middle-button pan bypasses GUI blocking, matching the source input path.
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_MIDDLE:
		panning = event.pressed and _camera_input_enabled()
	if event is InputEventMouseButton and event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_MIDDLE] and not event.pressed:
		panning = false
	if event is InputEventMouseMotion and panning and _camera_input_enabled():
		camera_motion.pan(event.relative, camera.position.y)
	if event is InputEventMouseButton and not event.pressed and get_viewport().gui_get_hovered_control() != null:
		pressed_panel = -1
		right_pressed_panel = -1
	if running and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered != null and hovered != hud: equipment_display.pointer_down()
	if running and dragging >= 0 and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered != null and hovered != hud:
			session.combat.dragged.clear()
			dragging = -1
			drag_grant = -1
			drag_delta = Vector2.ZERO
		else:
			_finish_drag(event.position)

func _finish_drag(screen: Vector2) -> void:
	if pressed_panel >= 0:
		if _allows_card_actions() and int(_pick_target(screen).panel_owner) == pressed_panel: equipment_display.click_panel(pressed_panel)
		pressed_panel = -1
		return
	var id: int = dragging
	var carried_press: bool = id >= 0 and drag_grant == id and running and not _ui_pause_active()
	drag_grant = -1
	session.combat.dragged.clear()
	dragging = -1
	if (not _allows_card_actions() and not carried_press) or not session.cards.has(id):
		drag_delta = Vector2.ZERO
		return
	feedback.play_event("CardDrop")
	if session.combat.membership.has(id):
		_sync_combat_layouts()
		var task_id: int = session.combat.membership[id]
		var task: Dictionary = session.combat.tasks[task_id]
		var result: Dictionary = CombatLayout.drop_result(id, session.cards[id].position + drag_delta, combat_layouts.get(task_id, {}), task.player_is_attacker, _card_footprint(id), session.board_bounds, session.board_top_margin)
		if result.flee:
			session.cards[id].position = result.position
			if session.combat.flee(id):
				_set_board_card_position(id, result.position)
				notice.text = "Fled combat."
		drag_delta = Vector2.ZERO
		_refresh()
		return
	if drag_moved:
		var stack = session.stacks[session.cards[id].stack_id]
		var destination: Vector2 = session.card_target_position(id) + drag_delta
		var trade: Dictionary = _try_trade_drop(id, destination, carried_press)
		if trade.terminal:
			drag_delta = Vector2.ZERO
			_refresh()
			return
		id = int(trade.card_id)
		if not session.cards.has(id):
			drag_delta = Vector2.ZERO
			_refresh()
			return
		stack = session.stacks[session.cards[id].stack_id]
		var target: int = _nearby_stack(id, Vector3(destination.x, 0, destination.y), float(catalog.settings("CardSettings").get("attachRadius", 0.25)), -1, true)
		if _try_equip_drop(id, destination) or _try_combat_drop(id, destination, target):
			drag_delta = Vector2.ZERO
			_refresh()
			return
		if target >= 0:
			var target_card: int = session.stacks[target].card_ids.back()
			if int(catalog.fields(session.cards[id].definition_guid).get("category", 0)) == 5 and int(catalog.fields(session.cards[target_card].definition_guid).get("category", 0)) == 2:
				if stack.card_ids.back() != id:
					notice.text = "Split equipment from its tail before equipping."
				else:
					notice.text = "Equipped." if session.equipment.equip(target_card, id) else "Cannot equip this item."
			else:
				var stored_before: int = session.cards[target_card].stored_coins
				if not session.move_to_stack(id, target):
					notice.text = "These cards cannot stack, or the current recipe rejects extra ingredients."
				elif session.world._is_chest(target_card):
					notice.text = "Stored %d coins." % (session.cards[target_card].stored_coins - stored_before)
		else:
			destination = _clamp_stack_position(id, destination)
			session.split_stack(id, destination)
	else:
		if catalog.get_definition(session.cards[id].definition_guid).get("script_class", "") == "PackDefinition":
			var pack_stack: int = session.cards[id].stack_id
			layout_locks[pack_stack] = true
			session.open_pack(id, carried_press)
			layout_locks.erase(pack_stack)

	drag_delta = Vector2.ZERO
	_refresh()

func _refresh() -> void:
	_update_board_geometry()
	_sync_trade_zones()
	_sync_views()
	var stats: Dictionary = session.stats()
	status.text = "Day %d  ·  %.0f / %.0f s  ·  %s  |  Coins %d  ·  Food %d / %d  ·  Cards %d / %d" % [session.day, session.elapsed, session.day_duration, session.phase.to_upper() + (" / PAUSED" if session.paused else " / %.0fx" % session.speed), stats.currency, stats.nutrition, stats.nutrition_need, stats.cards_owned, stats.card_limit]
	pause_button.text = "Resume [Space]" if session.paused else "Pause [Space]"
	pause_button.disabled = session.phase != "playing"
	day_button.text = {"playing": "End day & feed", "feeding": "Feed villagers", "selling": "Sell %d excess cards" % stats.excess, "ready": "Start next day", "game_over": "Game over · return to title"}.get(session.phase, session.phase)
	if session.phase == "feeding" and session.cycle.stage != "await_feed":
		day_button.text = "Feeding · " + str(session.cycle.stage).replace("_", " ")
	elif session.phase == "encounter":
		day_button.text = "Encounter · " + str(session.cycle.stage).replace("_", " ")
	day_button.disabled = session.phase in ["selling", "encounter"] or (session.phase == "feeding" and session.cycle.stage != "await_feed")
	_refresh_market_labels()
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
	var rows: Array = []
	if active_tab == "quests":
		rows.append({"id": "", "text": "Active quests\n"})
		for instance in session.quest_tracker.active_quests:
			var fields: Dictionary = session.quest_tracker.definitions.get(instance.id, {})
			rows.append({"id": str(instance.id), "text": "%s  (%d/%d)\n%s\n" % [fields.get("title", instance.id), instance.current_amount, int(fields.get("targetAmount", 1)), fields.get("description", "")]})
		rows.append({"id": "", "text": "Completed: %d\n" % session.completed_quests})
		for instance in session.quest_tracker.completed_quests:
			var fields: Dictionary = session.quest_tracker.definitions.get(instance.id, {})
			rows.append({"id": str(instance.id), "text": "✓ %s\n%s\n" % [fields.get("title", instance.id), fields.get("description", "")]})
	else:
		for recipe in catalog.data.get("recipes", []):
			var id: String = str(recipe.fields.get("id", ""))
			if not session.discovered_recipes.has(id): continue
			var ingredients: Array[String] = []
			for ingredient in recipe.fields.get("requiredIngredients", []):
				ingredients.append("%d %s" % [int(ingredient.get("count", 1)), _name(catalog.ref_guid(ingredient.get("card", {})))])
			rows.append({"id": id, "text": "%s → %s\n" % [" + ".join(ingredients), _name(catalog.ref_guid(recipe.fields.get("resultingCard", {})))]})
		if rows.is_empty(): rows.append({"id": "", "text": "Discover recipes by combining cards or opening packs."})
	for row in rows:
		row["unread"] = not row.id.is_empty() and session.collection.is_unread(row.id)
	var signature: String = active_tab + str(rows)
	if signature == ledger_key: return
	ledger_key = signature
	var scroll: float = ledger.get_v_scroll_bar().value
	ledger.clear()
	ledger_visible_ids.clear()
	for row in rows:
		if not row.id.is_empty():
			ledger_visible_ids[row.id] = true
			ledger.push_meta(row.id)
		ledger.add_text(("NEW · " if row.unread else "") + row.text + "\n")
		if not row.id.is_empty(): ledger.pop()
	ledger.get_v_scroll_bar().value = scroll

func _on_ledger_hover(meta: Variant) -> void:
	if not meta is String or not ledger.is_visible_in_tree() or not ledger_visible_ids.has(meta): return
	session.collection.mark_seen(meta)

func _collection_changed() -> void:
	# A discovery may occur halfway through a factory/transaction. Only defer
	# presentation updates; never reenter geometry, gameplay or save here.
	if collection_refresh_pending: return
	collection_refresh_pending = true
	call_deferred("_refresh_collection_presentation")

func _refresh_collection_presentation() -> void:
	collection_refresh_pending = false
	if not running: return
	_refresh_market_labels()
	for zone in trade_zones:
		if trade_views.has(int(zone.index)):
			trade_views[int(zone.index)].update_caption(zone, _pack_tracker(str(zone.pack_guid)))
	_refresh_ledger()

func _pack_tracker(guid: String) -> String:
	if guid.is_empty(): return ""
	var progress: Dictionary = session.collection.pack_progress(guid, session.discovered_recipes)
	if int(progress.total) <= 0: return ""
	return "COMPLETED" if progress.complete else "%d / %d found" % [progress.found, progress.total]

func _refresh_market_labels() -> void:
	var currency: int = int(session.stats().currency)
	for guid in vendor_buttons:
		var fields: Dictionary = catalog.fields(guid)
		var minimum: int = int(fields.get("minQuests", 0))
		var price: int = maxi(0, int(fields.get("buyPrice", 3)) - int(session.vendor_payments.get(guid, 0)))
		var tracker: String = _pack_tracker(guid)
		vendor_buttons[guid].text = "%s · %d coins%s%s" % [_name(guid), price, " · locked" if session.completed_quests < minimum else "", " · " + tracker if not tracker.is_empty() else ""]
		vendor_buttons[guid].tooltip_text = vendor_buttons[guid].text
		vendor_buttons[guid].disabled = not _allows_card_actions() or session.completed_quests < minimum or currency < price

func _toggle_pause() -> void:
	if _ui_pause_active(): return
	if session.phase == "playing": session.set_paused(not session.paused)
	_refresh()

func _advance_day() -> void:
	if session.phase == "feeding" and session.cycle.stage != "await_feed": return
	match session.phase:
		"playing", "feeding": session.end_day()
		"ready":
			if session.start_day(): _checkpoint("Day %d started" % session.day)
		"game_over": _return_title()
	_refresh()

func _buy(guid: String) -> void:
	if not _allows_card_actions() or not vendor_guids.has(guid): return
	var id: int = session.buy_pack(guid)
	notice.text = "Purchased " + _name(guid) if id >= 0 else "Pack unavailable: check currency and completed quests."
	_refresh()

func _sell_selected() -> void:
	if not _allows_card_actions() or session.combat.membership.has(selected): return
	notice.text = "Card sold." if session.sell_card(selected) else "Select a sellable card. Empty coin storage first."
	_refresh()

func _sell_selected_stack() -> void:
	if not _allows_card_actions() or not session.cards.has(selected) or session.combat.membership.has(selected): return
	notice.text = "Stack sold." if session.sell_stack(session.cards[selected].stack_id) else "This stack contains a card that cannot be sold."
	_refresh()

func _allows_card_actions() -> bool:
	return running and not _ui_pause_active() and session.phase in ["playing", "selling"]

func _active_slot_path() -> String:
	return slots.slot_path(active_slot)

func _has_save() -> bool:
	return selected_slot > 0 and slots._inspect(selected_slot).valid

func _refresh_slots() -> void:
	var inventory: Dictionary = slots.list_slots()
	slot_picker.clear()
	if not inventory.ok:
		title_status.text = "Cannot read saves: " + str(inventory.error)
		continue_button.disabled = true
		return
	var selected_index: int = -1
	for entry in inventory.slots:
		var label: String = "Slot %d · unavailable (files preserved)" % entry.slot
		if entry.valid:
			label = "Slot %d · %s · %d%% · %s UTC%s" % [entry.slot, entry.scene, entry.quest_progress, Time.get_datetime_string_from_unix_time(int(entry.modified_unix)).replace("T", " "), " · backup" if entry.recovered else ""]
		slot_picker.add_item(label, int(entry.slot))
		var index: int = slot_picker.item_count - 1
		slot_picker.set_item_metadata(index, entry)
		if int(entry.slot) == selected_slot: selected_index = index
	if selected_index < 0:
		for index in slot_picker.item_count:
			if slot_picker.get_item_metadata(index).valid:
				selected_index = index
				break
	if selected_index < 0 and slot_picker.item_count > 0: selected_index = 0
	selected_slot = 0
	if selected_index >= 0:
		slot_picker.select(selected_index)
		_select_slot(selected_index)
	else:
		slot_picker.add_item("No saved slots")
		slot_picker.set_item_disabled(0, true)
		continue_button.disabled = true
	legacy_picker.clear()
	for path in legacy_paths:
		if FileAccess.file_exists(path) or FileAccess.file_exists(path + ".bak"):
			legacy_picker.add_item(path.get_file())
			legacy_picker.set_item_metadata(legacy_picker.item_count - 1, path)
	legacy_picker.visible = legacy_picker.item_count > 0
	legacy_button.visible = legacy_picker.visible

func _select_slot(index: int) -> void:
	var entry: Variant = slot_picker.get_item_metadata(index)
	if not entry is Dictionary:
		selected_slot = 0
		continue_button.disabled = true
		return
	selected_slot = int(entry.slot)
	continue_button.disabled = not bool(entry.valid)
	if not entry.valid:
		title_status.text = "Slot %d is unavailable. Existing files were kept. %s" % [selected_slot, str(entry.errors)]

func _save_active_slot() -> Dictionary:
	if active_slot <= 0: return {"ok": false, "error": "No active save slot"}
	slots.configure(session.campaign, slot_root)
	return slots.save_slot(active_slot)

func _checkpoint(reason: String) -> Dictionary:
	var result: Dictionary = _save_active_slot()
	notice.text = reason + (" · saved." if result.ok else " · SAVE FAILED: " + str(result.error) + ". Live game kept open; retry Save.")
	return result

func _save_game() -> void:
	if session.phase == "game_over":
		notice.text = "Game over: confirm Return to Title to archive this slot."
		return
	var result: Dictionary = _save_active_slot()
	notice.text = "Saved locally." if result.ok else "Save failed: " + str(result.get("error", "Unknown error"))

func _continue_game() -> void:
	if data_error != OK or selected_slot <= 0: return
	var candidate = Session.new()
	candidate.configure(catalog)
	var candidate_slots = SaveSlots.new()
	candidate_slots.configure(candidate.campaign, slot_root)
	var result: Dictionary = candidate_slots.load_slot(selected_slot)
	if not result.ok:
		title_status.text = "Cannot continue slot %d: %s" % [selected_slot, result.get("error", "Unknown error")]
		return
	session = candidate
	slots = candidate_slots
	active_slot = int(result.slot)
	_enter_game()
	notice.text = "Slot %d restored." % active_slot + (" Recovered from backup." if result.get("recovered", false) else "")

func _adopt_selected_legacy() -> void:
	if legacy_picker.item_count <= 0: return
	_adopt_legacy(str(legacy_picker.get_item_metadata(legacy_picker.selected)))

func _adopt_legacy(path: String) -> void:
	if data_error != OK or path not in legacy_paths: return
	var candidate = Session.new()
	candidate.configure(catalog)
	var loaded: Dictionary = candidate.campaign.load_file(path)
	if not loaded.ok:
		title_status.text = "Legacy copy failed; original kept: " + str(loaded.error)
		return
	var candidate_slots = SaveSlots.new()
	candidate_slots.configure(candidate.campaign, slot_root)
	var created: Dictionary = candidate_slots.create_slot()
	if not created.ok:
		title_status.text = "Cannot create legacy-copy slot; original kept: " + str(created.error)
		return
	session = candidate
	slots = candidate_slots
	active_slot = int(created.slot)
	selected_slot = active_slot
	_enter_game()
	notice.text = "Copied legacy save into slot %d. Original and backup were kept.%s" % [active_slot, " Recovered from legacy backup." if loaded.get("recovered", false) else ""]

func _return_title() -> void:
	if session.phase == "game_over":
		game_over_dialog.popup_centered()
		return
	var result: Dictionary = _save_active_slot()
	if not result.ok:
		notice.text = "Could not save; session kept open: " + str(result.get("error", "Unknown error"))
		return
	_show_title()

func _confirm_game_over_return() -> void:
	if not running or session.phase != "game_over": return
	var result: Dictionary = slots.delete_slot(active_slot)
	if not result.ok:
		notice.text = "Could not archive ended slot; game kept open: " + str(result.error)
		return
	active_slot = 0
	selected_slot = 0
	_show_title()
	title_status.text = "Ended game archived locally at %s. No save files were permanently deleted." % str(result.archive)

func _show_title() -> void:
	_clear_puffs()
	drag_grant = -1
	combat_presentation.reset()
	camera.h_offset = 0
	camera.v_offset = 0
	equipment_display.reset()
	pressed_panel = -1
	right_pressed_panel = -1
	pause_overlay.hide()
	running = false
	dragging = -1
	hud.hide()
	title_panel.show()
	_refresh_slots()
	for view in views.values(): view.hide()
	for rectangle in combat_rectangles.values(): rectangle.hide()
	for zone in trade_views.values(): zone.hide()

func _prepare_quit() -> bool:
	# Source IsEndingCycle stays set from feeding through ready/game-over.
	if not running or session.phase != "playing": return true
	var result: Dictionary = _checkpoint("Quit checkpoint")
	return result.ok

func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST: return
	if options_panel != null and options_panel.visible and options_panel.dirty:
		options_panel.request_close()
		if options_panel.visible: return
	if running and session.phase != "playing":
		quit_dialog.popup_centered()
	elif _prepare_quit():
		get_tree().quit()

func _unequip_selected() -> void:
	if not _allows_card_actions() or not session.cards.has(selected): return
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
		var distance: float = session.card_target_position(card.id).distance_squared_to(session.card_target_position(selected))
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
	if kind == "cycle_focus_requested":
		_focus_camera_position(payload.target_position, float(payload.duration))
	elif kind == "cycle_sound":
		feedback.play_event(str(payload.sound))
	elif kind == "cycle_stage_changed":
		call_deferred("_refresh")
	if kind == "combat_ended": _release_combat_layout(int(payload.combat_id))
	if kind == "scene_changed":
		_enter_game()
		_checkpoint("Arrived at " + session.scene_name)
	elif kind == "travel_failed":
		notice.text = "Travel failed: " + str(payload.get("error", ""))
	if kind == "pack_purchased": feedback.play_event("CashRegister")
	elif kind == "cards_sold": feedback.play_event("Coins")
	elif kind == "recipe_pop_requested": feedback.play_event("Pop")
	elif kind == "puff_requested": _spawn_puff(payload)
	elif kind == "combat_attack_started":
		feedback.play_event(ImpactFeedback.attack_sound(int(payload.combat_type)))
	elif kind == "combat_hit":
		_present_impact(payload)
	elif kind == "encounter":
		notice.text = "Event: " + str(payload.get("message", ""))

func _withdraw_selected() -> void:
	if not _allows_card_actions() or not session.world.can_click_chest(selected):
		notice.text = "Select an unstacked chest to withdraw a coin."
		return
	var position: Vector2 = session.card_target_position(selected) + Vector2(_card_footprint(selected).x, 0)
	# Source EnforcePlacementRules(spawnPos, null) uses no card footprint.
	position = BoardLayout.enforce_placement(position, BoardLayout.stack_state(-1, position, Vector2.ZERO, 1), session.board_bounds, session.board_top_margin)
	notice.text = "Withdrew a coin." if session.world.withdraw_coin(selected, true, position) else "Chest is empty."
	_refresh()

func _stack_step() -> Vector3:
	var step: Dictionary = catalog.settings("CardSettings").get("stackStep", {})
	return Vector3(float(step.get("x", 0)), float(step.get("y", 0.002)), float(step.get("z", -0.18)))

func _card_collider_size(id: int) -> Vector3:
	if not session.cards.has(id): return Vector3.ZERO
	var fields: Dictionary = catalog.fields(session.cards[id].definition_guid)
	var is_pack: bool = catalog.get_definition(session.cards[id].definition_guid).get("script_class", "") == "PackDefinition"
	var appearance: Dictionary = visual_assets.appearance(int(fields.get("category", 0)), is_pack, fields, session.scene_name)
	var size: Dictionary = appearance.get("prefab", {}).get("size", {})
	if size.has("x") and size.has("z"):
		return Vector3(float(size.x), float(size.get("y", 0)), float(size.z))
	# Gameplay import contains colliders even when optional private media is absent.
	var config: Dictionary = session.campaign._defaults(session.scene_name)
	var prefab_guid: String = ""
	if is_pack:
		prefab_guid = catalog.ref_guid(config.get("packPrefab", {}))
	elif int(fields.get("category", 0)) == 9 and bool(fields.get("isAggressive", false)):
		prefab_guid = catalog.ref_guid(config.get("aggressiveMobPrefab", {}))
	else:
		for entry in config.get("cardPrefabs", []):
			if int(entry.get("category", -1)) == int(fields.get("category", 0)):
				prefab_guid = catalog.ref_guid(entry.get("prefab", {}))
	for prefab in catalog.data.get("referenced_prefabs", []):
		if str(prefab.get("guid", "")) != prefab_guid: continue
		for document in prefab.get("documents", []):
			if document.get("object_type", "") == "BoxCollider":
				size = document.get("fields", {}).get("m_Size", {})
				return Vector3(float(size.get("x", 0)), float(size.get("y", 0)), float(size.get("z", 0)))
	return Vector3.ZERO

func _card_footprint(id: int) -> Vector2:
	var size := _card_collider_size(id)
	if size == Vector3.ZERO: return Vector2.ZERO
	var margin: Dictionary = catalog.settings("CardSettings").get("margin", {})
	return BoardLayout.card_size(size, Vector2(float(margin.get("x", 0.1)), float(margin.get("y", 0.1))))

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
		original_board.scale.z = -1.0
		board_mesh.hide()
	else:
		board_mesh.show()
		board_mesh.mesh.size = Vector3(bounds.size.x, 0.2, bounds.size.y)
		visual_assets.apply_scene(camera, board_mesh, session.scene_name)
	if old_bounds is Rect2 and bounds.get_area() < old_bounds.get_area():
		_apply_layout(BoardLayout.enforce_board_limits(_layout_states(), [], bounds, session.board_top_margin, int(catalog.settings("CardSettings").get("maxIterations", 8))))
	_clamp_camera()

func _clamp_stack_position(card_id: int, point: Vector2) -> Vector2:
	if not session.board_bounds is Rect2 or not session.cards.has(card_id): return point
	var stack = session.stacks.get(session.cards[card_id].stack_id)
	var count: int = 1 if stack == null else stack.card_ids.size() - stack.card_ids.find(card_id)
	var state: Dictionary = BoardLayout.stack_state(-1, point, _card_footprint(card_id), count, false, _stack_step())
	return BoardLayout.enforce_placement(point, state, session.board_bounds, session.board_top_margin)

func _ai_point_valid(point: Vector2, stack_id: int) -> bool:
	if not session.board_bounds is Rect2 or not session.stacks.has(stack_id): return false
	return session.ai.point_in_board(point, session.board_bounds, _card_footprint(session.stacks[stack_id].card_ids[0]), session.board_top_margin)

func _combat_geometry() -> Array:
	_sync_combat_layouts()
	var result: Array = []
	for id in combat_layouts:
		var state: Dictionary = combat_layouts[id]
		result.append({"id": id, "ongoing": true, "has_player": state.has_player, "position": state.center})
	return result

# Model coordinates retain Unity XZ. Only the view reflects source +Z to Godot -Z.
func _camera_input_enabled() -> bool:
	return running and session.phase in ["playing", "selling"] and not _ui_pause_active()

func _clamp_camera() -> void:
	if session.board_bounds is Rect2: camera_motion.set_bounds(session.board_bounds)

func _zoom_camera(scroll: float) -> void:
	if _camera_input_enabled(): camera_motion.zoom(scroll, -camera.global_basis.z)

func _focus_camera(target: Vector2, duration: float = 0.5) -> void:
	_focus_camera_position(Vector3(target.x,0,target.y), duration)

func _focus_camera_position(source_position: Vector3, duration: float = 0.5) -> void:
	panning = false
	camera_motion.move_to(camera.position, Vector3(source_position.x,source_position.y,-source_position.z), -camera.global_basis.z, duration)

func _update_camera_motion(delta: float) -> void:
	_clamp_camera()
	var enabled: bool = _camera_input_enabled()
	if not enabled: panning = false
	if enabled:
		# Explicit native convenience extension; source only supports pointer pan.
		var direction := Vector3.ZERO
		if Input.is_physical_key_pressed(KEY_A): direction.x -= 1
		if Input.is_physical_key_pressed(KEY_D): direction.x += 1
		if Input.is_physical_key_pressed(KEY_W): direction.z -= 1
		if Input.is_physical_key_pressed(KEY_S): direction.z += 1
		if direction != Vector3.ZERO:
			camera_motion.target += direction * delta * 8
			camera_motion.clamp_target()
	camera.position = camera_motion.step(camera.position, delta, enabled)

func _layout_states() -> Array:
	var result: Array = []
	for stack in session.stacks.values():
		if stack.card_ids.is_empty(): continue
		var locked: bool = layout_locks.has(stack.id) or (session.cards.has(dragging) and session.cards[dragging].stack_id == stack.id)
		result.append(BoardLayout.stack_state(stack.id, stack.position, _card_footprint(stack.card_ids[0]), stack.card_ids.size(), locked, _stack_step()))
	return result

func _layout_signature() -> String:
	var entries: Array = []
	for stack in session.stacks.values(): entries.append([stack.id, stack.position, stack.card_ids])
	for id in combat_layouts: entries.append([id, combat_layouts[id].bounds])
	return str(entries)

func _apply_layout(result: Dictionary) -> void:
	for state in result.stacks:
		if not session.stacks.has(state.id): continue
		var stack = session.stacks[state.id]
		stack.position = state.position
		for id in stack.card_ids: session.cards[id].position = stack.position
	layout_key = _layout_signature()

func _resolve_layout() -> void:
	if not session.board_bounds is Rect2: return
	_sync_combat_layouts()
	var rectangles: Array = []
	for state in combat_layouts.values(): rectangles.append(state.bounds)
	_apply_layout(BoardLayout.resolve_overlaps(_layout_states(), rectangles, session.board_bounds, session.board_top_margin, int(catalog.settings("CardSettings").get("maxIterations", 8))))

func _ensure_layout() -> void:
	if session.catalog != null and _layout_signature() != layout_key:
		_resolve_layout()

func _nearby_stack(card_id: int, point: Vector3, radius: float, ignored: int = -1, equipment_drop: bool = false) -> int:
	if not session.cards.has(card_id): return -1
	var candidates: Array = []
	for stack in session.stacks.values():
		if stack.id == session.cards[card_id].stack_id or stack.id == ignored: continue
		var positions: Array[Vector3] = []
		var intersects: bool = false
		for index in range(stack.card_ids.size()):
			var center := Vector3(stack.position.x, 0, stack.position.y) + _stack_step() * index
			positions.append(center)
			var raw: Vector3 = _card_collider_size(stack.card_ids[index])
			intersects = intersects or BoardLayout.sphere_intersects_aabb(point, radius, AABB(center - raw * 0.5, raw))
		if intersects:
			var eligible: bool = session.can_move_to_stack(card_id, stack.id)
			# Equipment drops are a separate source action ahead of ordinary attachment.
			var incoming: Dictionary = catalog.fields(session.cards[card_id].definition_guid)
			var receiver: Dictionary = catalog.fields(session.cards[stack.card_ids.back()].definition_guid)
			if equipment_drop and int(incoming.get("category", 0)) == 5 and int(receiver.get("category", 0)) == 2: eligible = true
			candidates.append({"id": stack.id, "eligible": eligible, "card_positions": positions})
	return BoardLayout.choose_attach_candidate(point, candidates, session.cards[card_id].stack_id, ignored)

func _select_spawn_target(card_id: int, ignored: int = -1) -> int:
	if not session.cards.has(card_id): return -1
	var position: Vector2 = session.cards[card_id].position
	return _nearby_stack(card_id, Vector3(position.x, session.spawn_query_height, position.y), float(catalog.settings("CardSettings").get("spawnAttachRadius", 1)), ignored)

func _fighter_records(ids: Array) -> Array:
	var result: Array = []
	for id in ids:
		if not session.cards.has(id): continue
		var card = session.cards[id]
		result.append({"id": id, "position": session.card_target_position(id), "size": _card_footprint(id), "faction": int(catalog.fields(card.definition_guid).get("faction", 0))})
	return result

func _set_board_card_position(id: int, point: Vector2) -> void:
	if not session.cards.has(id): return
	session.cards[id].position = point
	var stack = session.stacks.get(session.cards[id].stack_id)
	if stack != null:
		stack.position = point
		for member in stack.card_ids: session.cards[member].position = point

func _release_combat_layout(id: int) -> void:
	if combat_layouts.has(id):
		var state: Dictionary = combat_layouts[id]
		var units: Array = _fighter_records(state.attackers + state.defenders)
		var positions: Dictionary = CombatLayout.survivor_positions(units, session.board_bounds, session.board_top_margin)
		for card_id in positions:
			if not session.combat.membership.has(card_id): _set_board_card_position(card_id, positions[card_id])
	combat_layouts.erase(id)
	if combat_rectangles.has(id):
		combat_rectangles[id].queue_free()
		combat_rectangles.erase(id)

func _sync_combat_layouts() -> void:
	for id in combat_layouts.keys():
		if not session.combat.tasks.has(id): _release_combat_layout(id)
	if session.combat.tasks.is_empty(): return
	var config: Dictionary = CombatLayout.imported_config(catalog.data, session.scene_name)
	if not config.get("ok", false):
		notice.text = "Combat layout unavailable: " + str(config.get("error", "Unknown source configuration"))
		return
	for id in session.combat.tasks:
		var task: Dictionary = session.combat.tasks[id]
		var attackers: Array = _fighter_records(task.attackers)
		var defenders: Array = _fighter_records(task.defenders)
		var previous: Dictionary = task.get("layout", {})
		if not previous.is_empty(): previous["config"] = config
		var state: Dictionary = CombatLayout.initialize(attackers, defenders, config, session.board_bounds, session.board_top_margin) if previous.is_empty() else CombatLayout.update_layout(previous, attackers, defenders)
		if state.is_empty(): continue
		task["layout"] = state
		combat_layouts[id] = state
		for card_id in state.positions: session.cards[card_id].position = state.positions[card_id]
		_draw_combat_rectangle(id, state)

func _draw_combat_rectangle(id: int, state: Dictionary) -> void:
	if not combat_rectangles.has(id):
		var rectangle := MeshInstance3D.new()
		var material := StandardMaterial3D.new()
		material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		material.albedo_color = Color(0.9, 0.24, 0.16, 0.2)
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.cull_mode = BaseMaterial3D.CULL_DISABLED
		rectangle.material_override = material
		add_child(rectangle)
		combat_rectangles[id] = rectangle
	var rectangle: MeshInstance3D = combat_rectangles[id]
	if rectangle.get_meta("size", Vector2.ZERO) == state.size: return
	rectangle.set_meta("size", state.size)
	var vertices := PackedVector3Array()
	var minimum: Vector2 = -state.config.pivot * state.size
	for local in [minimum, minimum + Vector2(state.size.x, 0), minimum + state.size, minimum, minimum + state.size, minimum + Vector2(0, state.size.y)]:
		var point: Vector2 = state.center + state.config.axis_x * local.x + state.config.axis_y * local.y
		vertices.append(Vector3(point.x, 0.015, -point.y))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	rectangle.mesh = mesh

func _can_drag_card(id: int) -> bool:
	if not _allows_card_actions(): return false
	if not session.cards.has(id): return false
	if not session.combat.membership.has(id): return true
	return session.combat.can_drag_combatant(id)

func _combatants(ids: Array) -> Array:
	var result: Array = []
	for id in ids:
		var fields: Dictionary = catalog.fields(session.cards[id].definition_guid)
		if int(fields.get("category", 0)) in [2, 9] and int(fields.get("faction", 0)) in [1, 2]: result.append(id)
	return result

func _try_combat_drop(id: int, destination: Vector2, equipment_target: int) -> bool:
	var incoming: Dictionary = catalog.fields(session.cards[id].definition_guid)
	# Equipment remains a terminal action before join/start, as in the source.
	if int(incoming.get("category", 0)) == 5 and equipment_target >= 0:
		var receiver: int = session.stacks[equipment_target].card_ids.back()
		if int(catalog.fields(session.cards[receiver].definition_guid).get("category", 0)) == 2: return false
	var faction: int = int(incoming.get("faction", 0))
	if faction not in [1, 2]: return false
	var source = session.stacks[session.cards[id].stack_id]
	var ids: Array = _combatants(source.card_ids.slice(source.card_ids.find(id)))
	if ids.is_empty(): return false
	_sync_combat_layouts()
	var task_id: int = CombatLayout.task_at_position(combat_layouts, destination)
	if task_id >= 0:
		var original_join: Vector2 = source.position
		_set_board_card_position(id, original_join + destination - session.card_target_position(id))
		var joined: bool = session.combat.add_combatants(task_id, ids)
		if session.stacks.has(source.id) and not session.stacks[source.id].card_ids.is_empty():
			_set_board_card_position(session.stacks[source.id].card_ids[0], original_join)
		return joined
	var target: int = _raw_nearby_stack(id, Vector3(destination.x, 0, destination.y), float(catalog.settings("CardSettings").get("attachRadius", 0.25)))
	if target < 0: return false
	var target_stack = session.stacks[target]
	var other_faction: int = int(catalog.fields(session.cards[target_stack.card_ids[0]].definition_guid).get("faction", 0))
	if other_faction not in [1, 2] or other_faction == faction: return false
	var defenders: Array = _combatants(target_stack.card_ids)
	if defenders.is_empty(): return false
	# Translate the source root while the model captures all derived member poses.
	# Restore any preceding tail survivors, including the full stack on rejection.
	var original: Vector2 = source.position
	var offset: Vector2 = destination - session.card_target_position(id)
	_set_board_card_position(id, original + offset)
	var started: int = session.combat.start_combat(ids, defenders, faction == 1)
	if session.stacks.has(source.id):
		var remaining = session.stacks[source.id]
		if not remaining.card_ids.is_empty(): _set_board_card_position(remaining.card_ids[0], original)
	return started >= 0

func _raw_nearby_stack(id: int, point: Vector3, radius: float) -> int:
	var candidates: Array = []
	for stack in session.stacks.values():
		if stack.id == session.cards[id].stack_id: continue
		var positions: Array[Vector3] = []
		var hit: bool = false
		for index in range(stack.card_ids.size()):
			var center := Vector3(stack.position.x, 0, stack.position.y) + _stack_step() * index
			positions.append(center)
			var raw: Vector3 = _card_collider_size(stack.card_ids[index])
			hit = hit or BoardLayout.sphere_intersects_aabb(point, radius, AABB(center - raw * 0.5, raw))
		if hit: candidates.append({"id": stack.id, "eligible": true, "card_positions": positions})
	return BoardLayout.choose_attach_candidate(point, candidates, session.cards[id].stack_id)

func _try_equip_drop(id: int, destination: Vector2) -> bool:
	if int(catalog.fields(session.cards[id].definition_guid).get("category", 0)) != 5: return false
	var point := Vector3(destination.x, 0, destination.y)
	var radius: float = float(catalog.settings("CardSettings").get("attachRadius", 0.25))
	var best: int = -1
	var distance: float = INF
	for card in session.cards.values():
		if card.stack_id == session.cards[id].stack_id or int(catalog.fields(card.definition_guid).get("category", 0)) != 2: continue
		var center: Vector3 = session.card_target_position_3d(card.id)
		var raw: Vector3 = _card_collider_size(card.id)
		if BoardLayout.sphere_intersects_aabb(point, radius, AABB(center - raw * 0.5, raw)) and center.distance_squared_to(point) < distance:
			best = card.id
			distance = center.distance_squared_to(point)
	if best < 0: return false
	if session.stacks[session.cards[id].stack_id].card_ids.back() != id:
		notice.text = "Split equipment from its tail before equipping."
		return true
	if session.equipment.equip(best, id):
		notice.text = "Equipped."
		return true
	return false

func _departure_checkpoint() -> Dictionary:
	return _checkpoint("Travel departure")

func _combat_start_overlaps(attackers: Array, defenders: Array) -> Array:
	_sync_combat_layouts()
	return CombatMergeGeometry.before_start(_fighter_records(attackers), _fighter_records(defenders), combat_layouts)

func _combat_resize_overlaps(task_id: int) -> Array:
	_sync_combat_layouts()
	return CombatMergeGeometry.after_resize(task_id, combat_layouts)

func _sync_trade_zones() -> void:
	var result: Dictionary = TradeLayout.zones(catalog, session.scene_name, session.board_bounds, session.board_top_margin, session.completed_quests, session.vendor_payments, trade_activated)
	trade_zones = result.zones
	var present: Dictionary = {}
	for zone in trade_zones:
		var index: int = int(zone.index)
		present[index] = true
		if zone.kind == "vendor" and zone.active: trade_activated[str(zone.pack_guid)] = true
		if not trade_views.has(index):
			var view = TradeZoneView.new()
			add_child(view)
			trade_views[index] = view
		trade_views[index].configure(zone, _pack_tracker(str(zone.pack_guid)))
	for index in trade_views.keys():
		if not present.has(index):
			trade_views[index].queue_free()
			trade_views.erase(index)
	if not result.errors.is_empty(): notice.text = "Trade geometry unavailable: " + "; ".join(result.errors)

func _try_trade_drop(card_id: int, destination: Vector2, carried_press: bool = false) -> Dictionary:
	var outcome := {"terminal": false, "accepted": false, "card_id": card_id}
	if (not _allows_card_actions() and not carried_press) or not session.cards.has(card_id): return outcome
	_sync_trade_zones()
	var zone: Dictionary = TradeLayout.nearest_zone(trade_zones, Vector3(destination.x, 0, destination.y), float(catalog.settings("CardSettings").get("attachRadius", 0.25)))
	if zone.is_empty(): return outcome
	# Select nearest physical zone BEFORE checking whether it can trade. Never
	# retry a farther accepting zone when this one rejects the dropped tail.
	var source = session.stacks.get(session.cards[card_id].stack_id)
	if source == null: return outcome
	var ids: Array = source.card_ids.slice(source.card_ids.find(card_id))
	var snapshot: Dictionary = TradeLayout.card_snapshots(session, ids)
	if not snapshot.ok or not TradeLayout.can_trade(zone, snapshot.cards):
		notice.text = "This trade zone cannot accept these cards."
		return outcome
	var stack_id: int = session.split_stack(card_id, destination)
	var dropped = session.stacks[stack_id]
	if zone.kind == "buyer":
		outcome.accepted = session.sell_stack(stack_id)
		outcome.terminal = outcome.accepted and dropped.card_ids.is_empty()
		notice.text = "Stack sold." if outcome.accepted else "Buyer rejected this stack."
	else:
		var result: Dictionary = session.pay_vendor(str(zone.pack_guid), stack_id)
		outcome.accepted = result.accepted
		outcome.terminal = result.get("terminal", false)
		if result.accepted:
			notice.text = "Pack purchased." if int(result.pack_id) >= 0 else "Vendor payment saved: %d coins." % int(result.paid)
		else:
			notice.text = "Vendor rejected this payment."
	# Accepted chest/excess-coin payments are NOT terminal: resolve remaining
	# cards through equipment/combat/ordinary placement exactly once.
	if not outcome.terminal and not dropped.card_ids.is_empty(): outcome.card_id = int(dropped.card_ids[0])
	return outcome

func _build_pause_options(layer: CanvasLayer) -> void:
	pause_overlay = Control.new()
	pause_overlay.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pause_overlay.mouse_filter = Control.MOUSE_FILTER_STOP
	layer.add_child(pause_overlay)
	var shade := ColorRect.new()
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.02, 0.04, 0.06, 0.85)
	pause_overlay.add_child(shade)
	var box := _panel(pause_overlay, Rect2(500, 270, 440, 330))
	_label("PAUSED · MENU", box, 26)
	_label("Your selected time pace is preserved.", box, 15)
	_button("Continue [Escape]", box, _toggle_pause_menu)
	_button("Options", box, _open_options)
	_button("Save & return to title", box, _return_title)
	pause_overlay.hide()
	options_panel = OptionsPanel.new()
	layer.add_child(options_panel)

func _ui_pause_active() -> bool:
	return running and ((pause_overlay != null and pause_overlay.visible) or (options_panel != null and options_panel.visible))

func _toggle_pause_menu() -> void:
	if not running or session.phase != "playing" or options_panel.visible: return
	pause_overlay.visible = not pause_overlay.visible
	if pause_overlay.visible:
		dragging = -1
		drag_grant = -1
		drag_delta = Vector2.ZERO
		session.combat.dragged.clear()

func _open_options() -> void:
	if running:
		if session.phase != "playing": return
		pause_overlay.show()
		dragging = -1
		drag_grant = -1
		drag_delta = Vector2.ZERO
		session.combat.dragged.clear()
	options_panel.open()

func _handle_escape() -> void:
	# Source PauseMenu never changes external pause during IsEndingCycle.
	if running and session.phase != "playing": return
	if options_panel.visible:
		options_panel.request_close()
	elif running:
		_toggle_pause_menu()

func _present_impact(payload: Dictionary) -> void:
	var descriptor: Dictionary = ImpactFeedback.describe(int(payload.get("combat_type", 0)), payload.get("result", {}), ImpactFeedback.hit_ui_fields(catalog.data, session.scene_name))
	if descriptor.is_empty(): return
	for sound in descriptor.sounds: feedback.play_event(sound)
	var defender: int = int(payload.get("defender_id", -1))
	combat_presentation.hit(defender, descriptor)
	if not session.cards.has(defender): return
	# Snapshot before the model can delete a lethal target. No gameplay awaits/RNG.
	var target: Vector2 = session.card_target_position(defender)
	var popup = ImpactView.new()
	add_child(popup)
	popup.configure(descriptor, Vector3(target.x, 0.12, -target.y), str(payload.result.get("type", "")), visual_assets, session.scene_name, int(payload.result.get("advantage", 0)))

func _sample_cycle_pose(id: int) -> Vector3:
	var state: Dictionary = session.cycle.presentation_state()
	if int(state.get("card_id", -1)) == id:
		var point: Variant = CyclePresentation.sample(state)
		if point is Vector3: return point
	if views.has(id) and is_instance_valid(views[id]):
		var point: Vector3 = views[id].global_position
		return Vector3(point.x, point.y, -point.z)
	return session.card_target_position_3d(id)

func _spawn_puff(payload: Dictionary) -> void:
	feedback.play_event("Puff") # Sound is independent of optional private visuals.
	var id: int = int(payload.get("card_id", -1))
	var origin: Vector3
	if views.has(id) and is_instance_valid(views[id]) and not views[id].is_queued_for_deletion():
		origin = views[id].global_position
	elif payload.get("position") is Vector3:
		var source: Vector3 = payload.position
		origin = Vector3(source.x, source.y, -source.z)
	else:
		return
	var node: Node3D
	var seed_value: int = puff_rng.randi()
	if puff_factory.is_valid():
		node = puff_factory.call(session.scene_name, seed_value)
	elif visual_assets.has_method("create_puff"):
		node = visual_assets.create_puff(session.scene_name, seed_value)
	if node == null: return
	add_child(node)
	node.global_position = origin
	puffs.append(node)

func _advance_puffs(real_delta: float, scaled_delta: float) -> void:
	for node in puffs.duplicate():
		if not is_instance_valid(node) or node.is_queued_for_deletion():
			puffs.erase(node)
			continue
		node.advance(real_delta, scaled_delta)
		if node.is_expired():
			puffs.erase(node)
			if not node.is_queued_for_deletion(): node.queue_free()

func _clear_puffs() -> void:
	for node in puffs:
		if is_instance_valid(node) and not node.is_queued_for_deletion(): node.queue_free()
	puffs.clear()
