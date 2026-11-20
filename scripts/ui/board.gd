extends Node3D
const SourceStatsText = preload("res://scripts/ui/source_stats_text.gd")
const WorldPostProcess = preload("res://scripts/ui/world_post_process.gd")
const CyclePresentation = preload("res://scripts/ui/cycle_presentation.gd")
const CameraMotion = preload("res://scripts/ui/camera_motion.gd")
const CombatPresentation = preload("res://scripts/ui/combat_presentation.gd")
const EquipmentDisplay = preload("res://scripts/ui/equipment_display_controller.gd")
const ImpactFeedback = preload("res://scripts/model/impact_feedback.gd")
const ImpactView = preload("res://scripts/ui/impact_view.gd")
const CombatMergeGeometry = preload("res://scripts/model/combat_merge_geometry.gd")
const CombatLayout = preload("res://scripts/model/combat_layout.gd")
const BoardLayout = preload("res://scripts/model/board_layout.gd")
const SourceRestoreLayout = preload("res://scripts/model/source_restore_layout.gd")
const SourceTravelLayout = preload("res://scripts/ui/source_travel_layout.gd")
const SourceRestoreAdmission = preload("res://scripts/ui/source_restore_admission.gd")
const SourceColdCrafting = preload("res://scripts/ui/source_cold_crafting.gd")
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const CardMotion = preload("res://scripts/ui/card_motion.gd")
const CardDragInput = preload("res://scripts/ui/card_drag_input.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const CardInteraction = preload("res://scripts/ui/card_interaction_descriptors.gd")
const CardHoverView = preload("res://scripts/ui/card_hover_view.gd")
const CraftProgressView = preload("res://scripts/ui/craft_progress_view.gd")
const NavigationInput = preload("res://scripts/ui/navigation_input.gd")
const OptionsPanel = preload("res://scripts/ui/options_panel.gd")
const MenuFocus = preload("res://scripts/ui/menu_focus.gd")
const MenuSlide = preload("res://scripts/ui/menu_slide.gd")
const DayClock = preload("res://scripts/ui/day_clock.gd")
const SceneTransition = preload("res://scripts/ui/scene_transition.gd")
const TitleNavigation = preload("res://scripts/ui/title_navigation.gd")
const TitleGameplayPrefs = preload("res://scripts/ui/title_gameplay_prefs.gd")
const OptionsAdapter = preload("res://scripts/ui/options_adapter.gd")
const TradeLayout = preload("res://scripts/model/trade_layout.gd")
const TradeZoneView = preload("res://scripts/ui/trade_zone_view.gd")
const VendorUnlockPresenter = preload("res://scripts/ui/vendor_unlock_presenter.gd")
const SaveSlots = preload("res://scripts/model/save_slots.gd")
const SaveCodec = preload("res://scripts/model/save_codec.gd")
const AudioFeedback = preload("res://scripts/ui/audio_feedback.gd")
const QUIT_AUDIO_DRAIN_SECONDS := 0.5
const SourceCombatRectangle = preload("res://scripts/ui/source_combat_rectangle.gd")
const VisualAssets = preload("res://scripts/ui/visual_assets.gd")
const SourceBoardLifetime = preload("res://scripts/ui/source_board_lifetime.gd")
const SceneConfig = preload("res://scripts/ui/scene_config.gd")
var source_hud: Control
const JournalPointerInput := preload("res://scripts/ui/source_journal_pointer_input.gd")
const JournalScrollContract = preload("res://scripts/ui/source_journal_scroll_contract.gd")
var hud_layout = preload("res://scripts/ui/source_hud_layout.gd").new()
var info_requests = preload("res://scripts/ui/info_request_queue.gd").new()
var stats_background: Panel
var stats_box: Control
var stat_labels: Array[SourceStatsText] = []
var journal_tabs: HBoxContainer
var watermark: Label
var ledger_info: Dictionary = {}
var info_action: Button
var info_action_source_record: Dictionary = {}
var info_action_appearance = preload("res://scripts/ui/source_info_action_appearance.gd").new()
var catalog = Catalog.new()
var visual_assets = VisualAssets.new()
var board_mesh: MeshInstance3D
var original_board: Node3D
var source_background: Node3D
var world_environment: Environment
var flat_board_lighting
var source_flat_environment_bound: bool = false
var geometry_key: String = ""
var layout_key: String = ""
## Explicit actual cold scene entry only, not Codec staging or travel admission.
var source_restore_entry: String = ""
var source_restore_report: Dictionary = {}
var source_crafting_report: Dictionary = {}
var source_travel_report: Dictionary = {}
var layout_locks: Dictionary = {}
var combat_layouts: Dictionary = {}
var _ranged_resize_receipt: Dictionary = {}
var combat_rectangles: Dictionary = {}
var puffs: Array[Node3D] = []
var puff_rng := RandomNumberGenerator.new()
var puff_factory: Callable = Callable()
var camera_motion = CameraMotion.new()
var card_motion = CardMotion.new()
# Bounded source terminal departure presentation, retained at ground after tween.
var _combat_slot_returns: Dictionary = {}
var _terminal_landings: Dictionary = {}
var _terminal_landing_receipt: int = -1
var combat_presentation = CombatPresentation.new()
var equipment_display = EquipmentDisplay.new()
var pressed_panel: int = -1
var right_pressed_panel: int = -1
var feedback = AudioFeedback.new()
var source_audio_clock = preload("res://scripts/ui/source_audio_clock.gd").new()
var slot_root: String = "user://slots"
var legacy_paths: Array[String] = ["user://session.json", "user://campaign.json"]
var slots = SaveSlots.new()
var options_path: String = "user://options.json"
var options_apply_adapter: Callable = Callable()
var options_hardware_modes: Array = []
var native_options_adapter = OptionsAdapter.new()
var options_panel
var pause_overlay: Control
var pause_controls: Array = []
var pause_restore_focus: WeakRef
var trade_zones: Array = []
var trade_views: Dictionary = {}
var trade_activated: Dictionary = {}
var vendor_unlock = VendorUnlockPresenter.new()
var journal_bodies: Dictionary = {}
var journal_pointer := JournalPointerInput.new()
var journal_rows: Dictionary = {}
var journal_body_state: Dictionary = {}
var ledger_visible_ids: Dictionary = {}
var ledger_key: String = ""
var ledger_expansion: Dictionary = {}
var ledger_visible_groups: Dictionary = {}
var ledger_session_id: int = 0
var ledger_scene_name: String = ""
var ledger_quest_order: Array = []
var quest_journal = preload("res://scripts/ui/quest_journal_state.gd").new()
var collection_refresh_pending: bool = false
var active_slot: int = 0
var selected_slot: int = 0
var archive_dialog: ConfirmationDialog
var archive_selected_button: Button
var archive_all_button: Button
var archive_picker: OptionButton
var restore_archive_button: Button
var listed_slot_ids: Array[int] = []
var pending_archive_plan: Dictionary = {}
var slot_picker: OptionButton
var legacy_picker: OptionButton
var legacy_button: Button
var game_over_dialog: ConfirmationDialog
var quit_dialog: ConfirmationDialog
var title_quit_button: Button
var quit_callback: Callable = Callable()
var pending_quit: String = ""
var quit_dispatched: bool = false
var friendly_choice: CheckBox
var session = Session.new()
var _tail_receipt: Dictionary = {}
var camera: Camera3D
var source_light: DirectionalLight3D
var panning: bool = false
var camera_drag_origin := Vector2.ZERO
var camera_pointer = preload("res://scripts/ui/source_camera_pointer.gd").new()
var views: Dictionary = {}
var running: bool = false
var selected: int = -1
# A CardController owns the held pose; the EventSystem separately owns receiver slots.
class BoardDrag extends RefCounted:
	var receiver: WeakRef
	var id: int = -1
	var combat: Dictionary = {}
	var screen: Vector2 = Vector2.ZERO
	var grant: int = -1
	var origin: Vector2 = Vector2.ZERO
	var anchor: Vector2 = Vector2.ZERO
	var delta: Vector2 = Vector2.ZERO
	var moved: bool = false
	var start: Vector3 = Vector3.ZERO
	var deferred_gear_pose: bool = false
var _mouse_drag := BoardDrag.new()
var _touch_drags: Dictionary = {}
var _touch_panel_presses: Dictionary = {}
var _touch_panel_serial := 0
var touch_card_receivers = preload("res://scripts/ui/source_touch_card_receivers.gd").new()
const SourceEquipmentOutsidePress = preload("res://scripts/ui/source_equipment_outside_press.gd")
var _source_equipment_outside: SourceEquipmentOutsidePress
# Preserve the existing mouse adapter and direct Board API.
var dragging: int:
	get: return _mouse_drag.id
	set(value): _mouse_drag.id = value
var _combat_hold: Dictionary:
	get: return _mouse_drag.combat
	set(value): _mouse_drag.combat = value
var press_position: Vector2:
	get: return _mouse_drag.screen
	set(value): _mouse_drag.screen = value
var drag_grant: int:
	get: return _mouse_drag.grant
	set(value): _mouse_drag.grant = value
var drag_origin: Vector2:
	get: return _mouse_drag.origin
	set(value): _mouse_drag.origin = value
var drag_anchor: Vector2:
	get: return _mouse_drag.anchor
	set(value): _mouse_drag.anchor = value
var drag_delta: Vector2:
	get: return _mouse_drag.delta
	set(value): _mouse_drag.delta = value
var drag_moved: bool:
	get: return _mouse_drag.moved
	set(value): _mouse_drag.moved = value
var drag_start_position: Vector3:
	get: return _mouse_drag.start
	set(value): _mouse_drag.start = value
var hud: Control
var world_post_process = WorldPostProcess.new()
var scene_transition = SceneTransition.new()
var scene_shade: ColorRect
var _transition_pause_frame: bool = false
var title_navigation = TitleNavigation.new()
var title_home: Control
var title_preferences: Control
var title_saves: Control
var title_new_button: Button
var title_load_button: Button
var title_confirm_button: Button
var title_cancel_button: Button
var title_back_button: Button
var title_panel: Control
var source_title
var source_title_quit: Control
var _source_title_quit_catalog: Dictionary = {}
var source_saved_rows
var recovery_window: Window
var recovery_button: Button
var duration_adapter: Control
var friendly_adapter: Control
var title_options_button: Button
var title_status: Label
var day_clock
var source_pause_configured := false
var market_heading: Label
var status: Label
var inspection: Label
var ledger: Control
var notice: Label
var day_button: Button
var pause_button: Button
var speed_buttons: Dictionary = {}
var shop: VBoxContainer
var market_panel: Control
var detail_panel: Control
var detail_toggle: Button
var journal_slide = MenuSlide.new()
var duration_label: Label
var duration: HSlider
var continue_button: Button
var vendor_guids: Array[String] = []
var vendor_buttons: Dictionary = {}
var data_error: Error = OK
var refresh_clock: float = 0.0
var active_tab: String = "quests"
var card_hover
var craft_progress
var hovered_trade_index: int = -1
var hovered_card_id: int = -1
var hovered_panel_owner: int = -1
var card_drag_targets: Dictionary = {}
var drag_highlights = preload("res://scripts/ui/drag_highlight_lifetime.gd").new()
var _card_pointer := Vector2.ZERO
var _card_pointer_known: bool = false
var _hover_view_instance: int = 0
var _hover_definition: String = ""
var _feedback_session_instance: int = 0
var _feedback_scene: String = ""

func _ready() -> void:
	NavigationInput.ensure_cancel_bindings()
	puff_rng.randomize()
	add_child(feedback)
	add_child(vendor_unlock)
	_build_world()
	world_post_process.attach(self)
	_build_ui()
	_build_scene_fader()
	for dialog in [archive_dialog, game_over_dialog, quit_dialog, options_panel.reset_dialog]:
		NavigationInput.enable_modal_cancel(dialog)
		dialog.visibility_changed.connect(_sync_card_feedback)
	for panel in [pause_overlay, options_panel]: panel.visibility_changed.connect(_sync_card_feedback)
	data_error = catalog.load_file()
	var gameplay_prefs: Dictionary = TitleGameplayPrefs.resolve(catalog.data)
	duration.min_value = gameplay_prefs.minimum
	duration.max_value = gameplay_prefs.maximum
	duration.step = 1.0 if gameplay_prefs.whole_numbers else 0.0
	duration.rounded = gameplay_prefs.whole_numbers
	duration.value = gameplay_prefs.initial
	duration_label.text = TitleGameplayPrefs.duration_text(duration.value)
	friendly_choice.button_pressed = gameplay_prefs.friendly
	friendly_choice.text = TitleGameplayPrefs.friendly_text(friendly_choice.button_pressed)
	visual_assets.load_manifest()
	visual_assets.load_render_pipeline(str(catalog.data.get("provenance", {}).get("source_commit", "")))
	_configure_source_title()
	options_panel.configure_source(catalog.data, visual_assets)
	_configure_source_pause()
	hud_layout.configure(catalog.data)
	_configure_source_hud()
	feedback.configure(catalog, visual_assets)
	feedback.play_music()
	if data_error != OK:
		title_status.text = "Source data is missing or invalid.\nImport your licensed StackCraft copy first:\npython tools/import_stackcraft.py --source /path/to/Assets/StackCraft --output data\nThen restart. See docs/data-import.md.\nNo replacement/mock game is loaded."
	else:
		title_status.text = "" if source_title != null else "Source-backed rules; native fallback presentation."
		vendor_guids = SceneConfig.offered_packs(catalog)
		_build_shop()
	if not gameplay_prefs.source_backed: title_status.text += "\n" + gameplay_prefs.warning
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
	flat_board_lighting = preload("res://scripts/ui/source_flat_board_lighting.gd").new()
	add_child(flat_board_lighting)
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world_environment = world.environment
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("10242c")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color("b7ced0")
	world.environment.ambient_light_energy = 0.8
	add_child(world)
	var light := DirectionalLight3D.new()
	source_light = light
	add_child(light)
	var board := MeshInstance3D.new()
	board_mesh = board
	var mesh := BoxMesh.new()
	board.mesh = mesh
	add_child(board)
	camera = Camera3D.new()
	add_child(camera)
	_restore_title_world()
	camera.current = true
	craft_progress = CraftProgressView.new()
	craft_progress.name = "CraftProgress"
	add_child(craft_progress)

func _restore_title_world() -> void:
	if is_instance_valid(flat_board_lighting): flat_board_lighting.clear()
	source_flat_environment_bound = false
	# Unity returns by loading Title as a fresh scene. This native single-scene
	# shell must likewise discard gameplay geometry, lighting and camera state.
	# Preserve the same explicit native title backdrop used on first launch.
	if is_instance_valid(original_board):
		original_board.hide()
		SourceBoardLifetime.detach_meshes(original_board)
		original_board.queue_free()
	original_board = null
	_replace_scene_background("Title")
	# Title remains a separately documented native shell until its scene port.
	world_environment.ambient_light_color = Color("b7ced0")
	world_environment.ambient_light_energy = 0.8
	geometry_key = ""
	board_mesh.mesh.size = Vector3(28, 0.2, 22)
	board_mesh.position = Vector3(0, -0.2, 0)
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("25434a")
	board_mesh.material_override = material
	board_mesh.visible = source_title == null
	source_light.transform = Transform3D.IDENTITY
	source_light.rotation_degrees = Vector3(-65, -20, 0)
	source_light.light_color = Color.WHITE
	source_light.light_energy = 0.8
	source_light.shadow_enabled = false
	source_light.shadow_opacity = 1.0
	camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	camera.keep_aspect = Camera3D.KEEP_HEIGHT
	camera.size = 23
	camera.fov = 75
	camera.near = 0.05
	camera.far = 4000
	camera.position = Vector3(0, 24, 8)
	camera.look_at(Vector3.ZERO)
	camera.h_offset = 0
	camera.v_offset = 0
	camera_motion.configure(camera.position)
	panning = false
	camera_pointer.take_pan_edges()

func _label(text: String, parent: Node, size: int = 16) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", size)
	parent.add_child(label)
	return label

func _button(text: String, parent: Node, callback: Callable, source_text: bool = false) -> Button:
	var button: Button = preload("res://scripts/ui/text_button_feedback.gd").new() if source_text else Button.new()
	button.text = text
	button.tooltip_text = text
	button.clip_text = true
	button.custom_minimum_size.y = 34
	if source_text:
		button.configure(callback, _play_ui_click, _text_button_allowed.bind(button))
	else:
		button.pressed.connect(callback)
	parent.add_child(button)
	return button

func _play_ui_click() -> void:
	feedback.play_event("Click")

func _text_button_allowed(button: Button) -> bool:
	if recovery_window != null and recovery_window.visible and not recovery_window.is_ancestor_of(button): return false
	if scene_transition.blocks_input() or quit_dispatched or _navigation_modal_active(): return false
	if options_panel != null and options_panel.visible: return false
	if title_panel != null and title_panel.is_ancestor_of(button):
		if source_title != null and title_home.is_ancestor_of(button) and title_navigation.destination != TitleNavigation.HOME: return false
		return _title_navigation_allowed()
	if pause_overlay != null and pause_overlay.is_ancestor_of(button):
		# Existing source Pause buttons remain usable if day end arrives later.
		# Cancel/new-menu admission is gated separately; these retain their owner.
		return running and pause_overlay.visible
	return running and not _ui_pause_active()

func _friendly_changed(enabled: bool) -> void:
	# Keep programmatic preference synchronization live without inventing a user click.
	friendly_choice.text = TitleGameplayPrefs.friendly_text(enabled)
	if not friendly_choice.is_visible_in_tree() or friendly_choice.disabled or not _title_navigation_allowed(): return
	_play_ui_click()

func _show_journal_tab(tab: String) -> void:
	if not journal_bodies.has(tab): return
	if not ledger.is_visible_in_tree() or _ui_pause_active() or _navigation_modal_active(): return
	active_tab = tab
	_sync_journal_header(false, true)
	_refresh_ledger()
	_play_ui_click()

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
	source_hud = Control.new()
	source_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(source_hud)
	day_clock = DayClock.new()
	source_hud.add_child(day_clock)
	day_clock.pressed.connect(_cycle_clock_pace)
	stats_background = Panel.new()
	stats_background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	source_hud.add_child(stats_background)
	stats_box = preload("res://scripts/ui/source_stats_group.gd").new()
	source_hud.add_child(stats_box)
	stats_box.add_theme_constant_override("separation", 0)
	status = _label("", hud)
	status.hide() # Legacy diagnostic text, never source HUD chrome.
	var left := _panel(hud, Rect2(18, 100, 248, 600))
	market_panel = left.get_parent().get_parent()
	market_panel.hide()
	market_heading = _label("NATIVE DEBUG CONTROLS", left, 22)
	# Natural day end is the source trigger; no duplicate End Day control.
	pause_button = _button("Pause [Space]", left, _toggle_pause)
	var speeds := HBoxContainer.new()
	left.add_child(speeds)
	for speed in [1.0, 2.0]:
		speed_buttons[speed] = _button("%dx" % speed, speeds, _set_speed.bind(speed))
		speed_buttons[speed].clip_text = false
		speed_buttons[speed].size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_button("Save", left, _save_game)
	_button("Save & title", left, _request_return_title)
	_label("MARKET", left, 20)
	var market_scroll := ScrollContainer.new()
	market_scroll.custom_minimum_size = Vector2(220, 250)
	market_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	left.add_child(market_scroll)
	shop = VBoxContainer.new()
	shop.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	market_scroll.add_child(shop)
	_label("Select a card to inspect.\nClick a pack to draw.\nDrag a card and its tail.\nDrop on another stack to craft.\nDrop on empty board to split.\nRight-click to inspect a pack.\nWheel: zoom · WASD: pan", left, 13)
	# Native convenience actions remain opt-in diagnostics, not the source journal.
	var right := left
	inspection = _label("Select a card", right)
	inspection.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	for entry in [["Sell selected card", _sell_selected], ["Sell selected stack", _sell_selected_stack], ["Withdraw chest coin", _withdraw_selected], ["Unequip character", _unequip_selected], ["Engage enemy", _engage_selected]]:
		_button(entry[0], right, entry[1])
	detail_panel = Panel.new()
	# Unity MenuPanel is a RectTransform, not a Graphic; only its visible children hit.
	detail_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	detail_panel.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	source_hud.add_child(detail_panel)
	var tabs := HBoxContainer.new()
	detail_panel.add_child(tabs)
	journal_tabs = tabs
	for tab in ["quests", "recipes"]:
		var tab_button = preload("res://scripts/ui/source_journal_toggle.gd").new()
		tabs.add_child(tab_button)
		tab_button.text = tab.capitalize()
		tab_button.pressed.connect(_show_journal_tab.bind(tab))
		tab_button.clip_text = false
		tab_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for tab in ["quests", "recipes"]:
		var body = preload("res://scripts/ui/source_journal_scroll_host.gd").new()
		body.name = "QuestsView" if tab == "quests" else "RecipesView"
		detail_panel.add_child(body)
		var rows = preload("res://scripts/ui/source_journal_rows.gd").new()
		body.content.add_child(rows)
		rows.extent_changed.connect(body.set_content_height)
		rows.meta_hover_started.connect(_on_ledger_hover.bind(tab))
		rows.meta_hover_ended.connect(_on_ledger_hover_ended.bind(tab))
		rows.meta_clicked.connect(_on_ledger_group_clicked.bind(tab))
		rows.can_click = body.can_click
		rows.release_uncovered = _journal_release_uncovered.bind(tab)
		journal_bodies[tab] = body
		journal_rows[tab] = rows
		journal_body_state[tab] = {"key":"", "info":{}, "ids":{}, "groups":{}}
	_sync_active_journal_body()
	# Optional native diagnostics have no source HUD button; F3 reveals them.
	detail_toggle = _button(">>", source_hud, func(): journal_slide.toggle())
	detail_toggle.position = Vector2(1174, 835)
	detail_toggle.size = Vector2(248, 40)
	journal_slide.configure(detail_panel, detail_toggle, func(): feedback.play_event("Click"))
	notice = _label("", hud, 16)
	notice.position = Vector2(400, 770)
	notice.size = Vector2(650, 60)
	notice.visible = false
	notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	# Native status chrome, not source styling: bright Island geometry must
	# never wash out save/travel feedback. Keep the existing board input route.
	notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	notice.add_theme_color_override("font_color", Color.WHITE)
	var notice_background := StyleBoxFlat.new()
	notice_background.bg_color = Color("20262b")
	notice_background.set_corner_radius_all(3)
	notice_background.content_margin_left = 12
	notice_background.content_margin_right = 12
	notice_background.content_margin_top = 6
	notice_background.content_margin_bottom = 6
	notice.add_theme_stylebox_override("normal", notice_background)
	card_hover = CardHoverView.new()
	card_hover.name = "CardHoverInfo"
	# Header and background prevent card clicks/drags through the information
	# panel. The independent source camera wheel observes input before GUI.
	card_hover.mouse_filter = Control.MOUSE_FILTER_STOP
	source_hud.add_child(card_hover)
	info_action = _button("", source_hud, _advance_day, true)
	day_button = info_action
	info_action.hide()
	watermark = _label("", source_hud, 24)
	watermark.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	watermark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# UIRoot UICanvas puts Watermark below the HUD, then InfoPanel
	# (including its ActionButton) before MenuPanel. Restore sibling
	# order for both rendering and native GUI hit priority.
	source_hud.move_child(watermark, 0)
	source_hud.move_child(card_hover, detail_panel.get_index())
	source_hud.move_child(info_action, detail_panel.get_index())
	hud.resized.connect(_configure_source_hud)
	_layout_card_hover()
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
	var title_scroll := ScrollContainer.new()
	title_scroll.name = "TitleScroll"
	title_scroll.custom_minimum_size.y = 620
	title_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	margin.add_child(title_scroll)
	title_scroll.add_child(title)
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label("ABYSSAL GUILD", title, 36)
	_label("StackCraft · Godot migration", title, 22)
	title_status = _label("Loading source data…", title)
	title_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	title_home = VBoxContainer.new()
	title_home.name = "TitleHome"
	title.add_child(title_home)
	title_new_button = _button("New Game", title_home, _open_title_preferences, true)
	title_load_button = _button("Load Game", title_home, _open_title_saves, true)
	title_preferences = VBoxContainer.new()
	title_preferences.name = "GameplayPreferences"
	title.add_child(title_preferences)
	_label("Gameplay Preferences", title_preferences, 22)
	duration_label = _label(TitleGameplayPrefs.duration_text(120), title_preferences)
	duration = HSlider.new()
	title_preferences.add_child(duration)
	duration.value_changed.connect(func(value: float): duration_label.text = TitleGameplayPrefs.duration_text(value))
	friendly_choice = CheckBox.new()
	friendly_choice.text = TitleGameplayPrefs.friendly_text(false)
	title_preferences.add_child(friendly_choice)
	friendly_choice.toggled.connect(_friendly_changed)
	title_confirm_button = _button("Confirm · create new slot", title_preferences, _confirm_title_new_game, true)
	title_cancel_button = _button("Cancel", title_preferences, _title_back, true)
	title_saves = VBoxContainer.new()
	title_saves.name = "SavedGames"
	title.add_child(title_saves)
	_label("Saved games · native slots", title_saves)
	slot_picker = OptionButton.new()
	slot_picker.item_selected.connect(_select_slot)
	title_saves.add_child(slot_picker)
	continue_button = _button("Continue selected slot", title_saves, _request_continue_game, true)
	continue_button.disabled = true
	var archive_actions := HBoxContainer.new()
	title_saves.add_child(archive_actions)
	archive_selected_button = _button("Archive selected", archive_actions, _request_archive_selected, true)
	archive_all_button = _button("Archive all listed slots", archive_actions, _request_archive_all, true)
	for button in [archive_selected_button, archive_all_button]: button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_label("Recoverable archives · originals retained", title_saves)
	archive_picker = OptionButton.new()
	archive_picker.item_selected.connect(_select_archive)
	title_saves.add_child(archive_picker)
	restore_archive_button = _button("Restore copy into a new slot", title_saves, _restore_archive_copy)
	restore_archive_button.disabled = true
	archive_dialog = ConfirmationDialog.new()
	archive_dialog.title = "Archive listed save slots"
	archive_dialog.ok_button_text = "Archive these slots"
	preload("res://scripts/ui/text_button_feedback.gd").bind_modal(archive_dialog, _confirm_archive_slots, _cancel_archive_slots, _play_ui_click)
	add_child(archive_dialog)
	legacy_picker = OptionButton.new()
	title_saves.add_child(legacy_picker)
	legacy_button = _button("Copy legacy save into a new slot", title_saves, _adopt_selected_legacy)
	legacy_button.hide()
	legacy_picker.hide()
	title_back_button = _button("Back", title_saves, _title_back, true)
	game_over_dialog = ConfirmationDialog.new()
	game_over_dialog.title = "Return to Title"
	game_over_dialog.dialog_text = "This game has ended. Return to Title and move this slot, including backups, into the recoverable local archive?"
	game_over_dialog.ok_button_text = "Archive slot & return"
	preload("res://scripts/ui/text_button_feedback.gd").bind_modal(game_over_dialog, _request_game_over_return, Callable(), _play_ui_click)
	add_child(game_over_dialog)
	quit_dialog = ConfirmationDialog.new()
	quit_dialog.title = "Quit during day-end?"
	quit_dialog.dialog_text = "Day-end progress is not autosaved on quit. Your last checkpoint stays intact. Quit now?"
	preload("res://scripts/ui/text_button_feedback.gd").bind_modal(quit_dialog, _confirm_quit, _cancel_quit, _play_ui_click)
	add_child(quit_dialog)
	title_options_button = _button("Options", title_home, _open_options, true)
	title_quit_button = _button("Quit Game", title_home, _request_title_quit, true)
	_build_pause_options(layer)
	_sync_title_destination()

func _configure_source_title() -> void:
	if source_title != null: return
	var candidate = preload("res://scripts/ui/source_title_view.gd").new()
	candidate.name = "SourceTitle"
	title_panel.get_parent().add_child(candidate)
	title_panel.get_parent().move_child(candidate, title_panel.get_index())
	candidate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not candidate.configure(catalog.data, visual_assets):
		candidate.queue_free()
		return
	source_title = candidate
	var old_panel := title_panel
	var native_saves := title_saves
	for pair in [["new", title_new_button], ["load", title_load_button], ["options", title_options_button], ["quit", title_quit_button], ["duration_label", duration_label], ["duration", duration], ["friendly", friendly_choice], ["confirm", title_confirm_button], ["cancel", title_cancel_button], ["saves_close", title_back_button], ["saves_clear", archive_all_button]]:
		if candidate.mount(pair[0], pair[1]) and pair[0] in ["new", "load", "options", "cancel", "saves_close"]:
			candidate.admit_navigation_pointer(catalog.data, pair[0], pair[1])
	_configure_source_title_quit()
	var source_controls: Dictionary = candidate.bind_source_controls(catalog.data)
	if not source_controls.get("duration", {}).is_empty():
		duration_adapter = preload("res://scripts/ui/source_slider_adapter.gd").new()
		duration_adapter.bind(duration, source_controls.duration)
		duration_adapter.allowed = _title_navigation_allowed
	if not source_controls.get("friendly", {}).is_empty():
		friendly_adapter = preload("res://scripts/ui/source_text_toggle_adapter.gd").new()
		friendly_adapter.bind(friendly_choice, source_controls.friendly)
		friendly_adapter.allowed = _title_navigation_allowed
	title_confirm_button.text = "Confirm"
	title_cancel_button.text = "Cancel"
	title_back_button.text = "Close"
	archive_all_button.text = "Archive All"
	archive_all_button.tooltip_text = "Move all listed slots into a recoverable archive; originals are retained."
	# Recoverable archive/legacy transactions remain native, within the source
	# saved-games viewport. They are not relabelled as permanent source deletes.
	var scroll_host: Control = candidate.nodes[candidate.layout.resolve("SavedGamesUI/MainPanel/ScrollView")]
	for child in scroll_host.get_children(): child.hide()
	var scroll := ScrollContainer.new()
	scroll.name = "NativeSaveTransactions"
	scroll_host.add_child(scroll)
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	native_saves.reparent(scroll)
	native_saves.show()
	native_saves.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var diagnostic: Control = candidate.nodes[candidate.layout.resolve("MenuPanel/Version")]
	title_status.reparent(diagnostic)
	title_status.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	title_status.add_theme_font_size_override("font_size", 16)
	title_status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_panel = candidate
	title_home = candidate.home
	title_preferences = candidate.preferences_overlay
	title_saves = candidate.saves_overlay
	for overlay in [title_preferences, title_saves]:
		overlay.visibility_changed.connect(_source_title_overlay_visibility_changed.bind(overlay))
	old_panel.hide()
	old_panel.queue_free()
	_install_saved_rows()
	_sync_title_destination()
	board_mesh.hide() # Source Title is Canvas artwork, not a generated 3D board.

## The live TitleScreen Quit TextButton opens the linked ModalWindow instance.
## Missing/unsupported data retains the native confirmation rather than guessing.
func _configure_source_title_quit() -> void:
	if not is_instance_valid(source_title) or not source_title.source_backed or source_title_quit != null: return
	var button_id: String = source_title.layout.resolve("MenuPanel/QuitGame")
	if button_id.is_empty() or title_quit_button.get_parent() != source_title.nodes.get(button_id): return
	if catalog.data.get("provenance", {}).get("source_commit", "") != SourceColdCrafting.SOURCE_COMMIT: return
	var title_fields: Dictionary = {}
	var opener: Dictionary = {}
	var modal_fields: Dictionary = {}
	var instance: Dictionary = {}
	for scene in catalog.data.get("scenes", []):
		if scene.get("name", "") != "Title": continue
		for doc in scene.get("documents", []):
			var fields: Dictionary = doc.get("fields", {})
			var class_name_hint: String = doc.get("script_class", "")
			match str(doc.get("file_id", "")):
				"1960366055":
					if class_name_hint == "TitleScreen": title_fields = fields
				"242642538":
					if class_name_hint == "TextButton": opener = fields
				"274622151":
					if class_name_hint == "ModalWindow": modal_fields = fields
				"803427066985004391": instance = fields
	if title_fields.get("m_Enabled", 0) != 1 or title_fields.get("m_Script", {}).get("guid", "") != "7ceb2876a137ca34e88ae1d005e367d8": return
	if str(title_fields.get("quitGameButton", {}).get("fileID", "")) != "242642538" or str(title_fields.get("modalWindow", {}).get("fileID", "")) != "274622151": return
	if opener.get("m_Enabled", 0) != 1 or opener.get("m_Script", {}).get("guid", "") != "ef98d84a856977b44bbf49a1bab2060a" or opener.get("m_GameObject", {}) != source_title.layout.records[button_id].rect.get("m_GameObject", {}): return
	var prefab_guid := "a38dce0e37fdae5448eeb8ed7a3e8cdc"
	var link: Dictionary = modal_fields.get("m_CorrespondingSourceObject", {})
	if modal_fields.get("m_Enabled", 0) != 1 or modal_fields.get("m_Script", {}).get("guid", "") != "fde05c8a41ce4ff43b52e31f82f5e337" or link.get("guid", "") != prefab_guid or str(link.get("fileID", "")) != "8391004423961831919": return
	if str(modal_fields.get("m_PrefabInstance", {}).get("fileID", "")) != "803427066985004391" or instance.get("m_SourcePrefab", {}).get("guid", "") != prefab_guid: return
	if str(instance.get("m_Modification", {}).get("m_TransformParent", {}).get("fileID", "")) != source_title.layout.root_id: return
	var dialog = preload("res://scripts/ui/source_title_quit_view.gd").new()
	dialog.name = "SourceTitleQuit"
	source_title.add_child(dialog)
	dialog.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not dialog.configure(catalog.data, _decline_source_title_quit, _accept_source_title_quit, _source_title_quit_can_act, _play_ui_click):
		dialog.queue_free()
		return
	source_title_quit = dialog
	_source_title_quit_catalog = catalog.data
	dialog.visibility_changed.connect(_sync_card_feedback)
	source_title.visibility_changed.connect(func():
		if not source_title.is_visible_in_tree():
			dialog.close_dialog()
			if pending_quit == "source_title": pending_quit = "")
	title_quit_button.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE
	title_quit_button.focus_mode = Control.FOCUS_NONE

func _source_title_quit_home() -> bool:
	return is_instance_valid(source_title_quit) and is_instance_valid(source_title) and source_title.is_visible_in_tree() \
		and data_error == OK and is_same(catalog.data, _source_title_quit_catalog) and title_navigation.destination == TitleNavigation.HOME \
		and not running and not quit_dispatched and not scene_transition.active() and not options_panel.visible \
		and (not is_instance_valid(recovery_window) or not recovery_window.visible)

func _source_title_quit_can_act() -> bool:
	return _source_title_quit_home() and source_title_quit.is_visible_in_tree() and pending_quit == "source_title"

func _decline_source_title_quit() -> void:
	pending_quit = ""

func _accept_source_title_quit() -> void:
	pending_quit = ""
	_execute_quit()

func _title_navigation_allowed() -> bool:
	return not scene_transition.active() and not running and not quit_dispatched and not options_panel.visible and not _navigation_modal_active()

func _sync_title_destination() -> void:
	if recovery_window != null and title_navigation.destination != TitleNavigation.SAVES: recovery_window.hide()
	title_home.visible = source_title != null or title_navigation.destination == TitleNavigation.HOME
	title_preferences.visible = title_navigation.destination == TitleNavigation.PREFS
	title_saves.visible = title_navigation.destination == TitleNavigation.SAVES
	if source_title != null:
		for button in [title_new_button, title_load_button, title_options_button, title_quit_button]:
			button.focus_mode = Control.FOCUS_ALL if title_navigation.destination == TitleNavigation.HOME and (button != title_quit_button or source_title_quit == null) else Control.FOCUS_NONE

var _title_overlay_open_owner: Dictionary = {}
func _source_title_overlay_visibility_changed(overlay: Control) -> void:
	if not overlay.visible and _title_overlay_open_owner.get("overlay") == overlay: _title_overlay_open_owner.clear()
func _admit_title_overlay_open(destination: String) -> void:
	_title_overlay_open_owner.clear()
	if not _title_navigation_allowed() or title_navigation.destination != TitleNavigation.HOME: return
	if recovery_window != null and recovery_window.visible: return
	if not is_instance_valid(source_title) or not source_title.source_backed or not source_title.is_visible_in_tree(): return
	var prefs: bool = destination == TitleNavigation.PREFS
	var path: String = "MenuPanel/NewGame" if prefs else "MenuPanel/LoadGame"
	var button: Button = title_new_button if prefs else title_load_button
	var overlay = title_preferences if prefs else title_saves
	var source_id: String = "519257446" if prefs else "2090943496"
	if button.get_parent() != source_title.nodes.get(source_title.layout.resolve(path)) or overlay != source_title.nodes.get(source_id): return
	if not preload("res://scripts/ui/source_title_overlay_contract.gd").admits(catalog.data, destination): return
	_title_overlay_open_owner = {"data": catalog.data, "title": source_title, "overlay": overlay, "destination": destination}

func _source_title_overlay_cancel() -> bool:
	if _title_overlay_open_owner.is_empty(): return false
	if running or scene_transition.active() or title_navigation.destination != _title_overlay_open_owner.destination or not is_same(_title_overlay_open_owner.data,catalog.data) or _title_overlay_open_owner.title != source_title:
		_title_overlay_open_owner.clear()
		return false
	var overlay = _title_overlay_open_owner.overlay
	if not is_instance_valid(source_title) or not source_title.source_backed or not source_title.is_visible_in_tree() or not is_instance_valid(overlay) or not overlay.is_visible_in_tree():
		_title_overlay_open_owner.clear()
		return false
	if quit_dispatched or options_panel.visible or _navigation_modal_active() or (recovery_window != null and recovery_window.visible): return false
	if title_preferences.visible and title_saves.visible: return false
	return overlay == (title_preferences if title_navigation.destination == TitleNavigation.PREFS else title_saves)

func _open_title_preferences() -> void:
	if not _title_navigation_allowed(): return
	_admit_title_overlay_open(TitleNavigation.PREFS)
	title_navigation.open(TitleNavigation.PREFS)
	_sync_title_destination()
	(duration_adapter if duration_adapter != null else duration).grab_focus()
	MenuFocus.loop([duration_adapter if duration_adapter != null else duration, friendly_adapter if friendly_adapter != null else friendly_choice, title_confirm_button, title_cancel_button])

func _open_title_saves() -> void:
	if not _title_navigation_allowed(): return
	_admit_title_overlay_open(TitleNavigation.SAVES)
	title_navigation.open(TitleNavigation.SAVES)
	_refresh_slots()
	_sync_title_destination()
	title_back_button.grab_focus()
	if source_saved_rows != null: source_saved_rows.update_focus()

func _title_back() -> void:
	if not _title_navigation_allowed(): return
	_title_overlay_open_owner.clear()
	if recovery_window != null: recovery_window.hide()
	var previous: String = title_navigation.destination
	title_navigation.open(TitleNavigation.HOME)
	_sync_title_destination()
	if previous == TitleNavigation.PREFS: title_new_button.grab_focus()
	elif previous == TitleNavigation.SAVES: title_load_button.grab_focus()

func _confirm_title_new_game() -> void:
	if not _title_navigation_allowed() or not title_navigation.consume_new_game(): return
	_request_new_game()
	# Failure leaves prefs/error visible and permits another explicit Confirm.
	if not running: title_navigation.open(TitleNavigation.PREFS)

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
	candidate.day_duration = int(duration.value)
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

func _enter_game(travel_layout: Dictionary = {}, cold_crafting: Dictionary = {}) -> void:
	_source_equipment_outside = SourceEquipmentOutsidePress.new() if (
		session.scene_name in ["Main","Island"]
		and catalog.data.get("provenance",{}).get("source_commit")==SourceColdCrafting.SOURCE_COMMIT) else null
	_title_overlay_open_owner.clear()
	_title_options_open_owner.clear()
	source_crafting_report = cold_crafting
	options_panel.reset_source_lifecycle()
	world_post_process.configure(catalog.data, session.scene_name, visual_assets.render_pipeline)
	journal_slide.reset(MenuSlide.initial_state(catalog.data).open)
	title_navigation.open(TitleNavigation.HOME)
	_sync_title_destination()
	day_clock.configure(catalog.data, session.scene_name, visual_assets)
	_clear_card_feedback()
	vendor_unlock.cancel()
	_cancel_archive_slots()
	archive_dialog.hide()
	_clear_puffs()
	session.drag.reset()
	_touch_drags.clear()
	_touch_panel_presses.clear()
	touch_card_receivers.reset()
	session.combat.dragged.clear()
	_mouse_drag = BoardDrag.new()
	session.cycle.pose_sampler = _sample_cycle_pose
	session.cycle.layout_resolver = _resolve_layout
	card_motion.reset()
	_combat_slot_returns.clear()
	_terminal_landings.clear()
	_terminal_landing_receipt = -1
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
	ledger_session_id = 0 # Entering a source scene creates fresh MenuViews.
	active_tab = "quests" # Authored UIRoot starts on Quests, not the previous scene tab.
	_sync_journal_header(true)
	if not session.collection.changed.is_connected(_collection_changed):
		session.collection.changed.connect(_collection_changed)
	slots.configure(session.campaign, slot_root)
	session.campaign.before_travel = _departure_checkpoint
	session.travel_request = _request_travel
	session.travel_tail_request = _complete_travel_tail
	session.combat.start_overlap_selector = _combat_start_overlaps
	session.combat.start_center_sampler = _combat_start_center
	session.combat.start_layout_initializer = _combat_start_layout
	session.combat.merge_center_sampler = _combat_merge_center
	session.combat.resize_overlap_selector = _combat_resize_overlaps
	session.combat.flee_layout_updater = _combat_flee_layout
	session.combat.terminal_flee_layout_sampler = _combat_terminal_flee_layout
	session.combat.terminal_flee_rect_closer = _release_combat_layout
	for rectangle in combat_rectangles.values(): rectangle.queue_free()
	combat_rectangles.clear()
	combat_layouts.clear()
	_ranged_resize_receipt.clear()
	if not session.event_occurred.is_connected(_on_session_event):
		session.event_occurred.connect(_on_session_event)
	vendor_guids = SceneConfig.offered_packs(catalog, session.scene_name)
	_build_shop()
	visual_assets.apply_scene(camera, board_mesh, session.scene_name)
	visual_assets.apply_source_camera(camera, session.scene_name)
	camera_motion.configure(camera.position, CameraMotion.source_settings(catalog.data, session.scene_name))
	_clear_outbound_camera()
	panning = false
	camera_pointer.take_pan_edges()
	source_flat_environment_bound = visual_assets.apply_source_light(source_light, session.scene_name)
	source_flat_environment_bound = visual_assets.apply_source_environment(world_environment, session.scene_name) and source_flat_environment_bound
	_replace_scene_background(session.scene_name)
	# Original mesh is optional; validated source vertex bounds remain the fallback.
	geometry_key = ""
	_update_board_geometry()
	session.world.actor_pose_sampler = _sample_ai_actor_pose
	session.ai.point_validator = _ai_point_valid
	session.ai.combat_geometry = _combat_geometry
	session.ai.placement_resolver = _resolve_layout
	session.ai.produce_spawner = Callable()
	session.spawn_target_selector = _select_spawn_target
	session.spawn_layout_resolver = _resolve_layout
	layout_locks.clear()
	layout_key = ""
	source_restore_report = {}
	source_travel_report = {}
	if not travel_layout.is_empty():
		source_travel_report = SourceTravelLayout.apply(self, travel_layout)
		if source_travel_report.ok: layout_key = _layout_signature()
	elif source_restore_entry == "cold_load":
		var planned: Dictionary = SourceRestoreAdmission.plan(self)
		source_restore_report = SourceRestoreLayout.apply(session, planned) if planned.ok else planned
		if source_restore_report.ok:
			# The source has already performed finite per-initialize solver calls and
			# anchor resets. Do not add a second whole-board placement pass.
			layout_key = _layout_signature()
	source_restore_entry = ""
	for view in views.values(): view.queue_free()
	views.clear()
	running = true
	selected = -1
	title_panel.hide()
	hud.show()
	_refresh()
	vendor_unlock.bind(self)
	var focus: Dictionary = session.cycle.focus_state()
	if not focus.is_empty(): _focus_camera_position(focus.target_position, float(focus.duration))

func _advance_journal_pointer_input() -> void:
	if running and journal_bodies.has(active_tab):
		journal_pointer.flush(get_viewport().get_final_transform(),_journal_source_mouse_hit,
			journal_bodies[active_tab].drag_threshold,_dispatch_journal_source_mouse)

func _process(delta: float) -> void:
	_advance_journal_pointer_input()
	# Presentation ownership still changes while external pause skips clock sync.
	if day_clock != null: day_clock._sync_pause_icon_tint(_ordinary_source_pause_icon())
	_advance_source_audio_frame(delta)
	_sync_source_info()
	_transition_pause_frame = scene_transition.blocks_input()
	if _transition_pause_frame:
		# Finish the departing world's unscaled frame before committing at black.
		# Oversized frames cannot leak time past the fade-out boundary.
		var departing_delta: float = minf(maxf(delta, 0), maxf(0, SceneTransition.DURATION - scene_transition.elapsed))
		journal_slide.advance(departing_delta)
		_advance_running_frame(departing_delta)
		scene_transition.advance(delta)
		_sync_scene_fader()
		return
	journal_slide.advance(delta)
	scene_transition.advance(delta)
	_sync_scene_fader()
	_advance_running_frame(delta)

func _advance_source_audio_frame(real_delta: float) -> void:
	# One sample at root-frame entry, before gameplay/transition callbacks can
	# admit new waits. Title retains the last global scale after TimeManager dies.
	var pace: int = session.time_pace() if running and session.phase == "playing" else 0
	var blocked: bool = running and (scene_transition.blocks_input() or _temporal_ui_pause_active() or vendor_unlock.is_active())
	feedback.advance_scaled_time(source_audio_clock.sample(real_delta, running, pace, blocked))

func _advance_running_frame(delta: float) -> void:
	if not running:
		return
	world_post_process.advance(delta)
	# Sample ownership before advancing real-time reveals. An expiring reveal
	# cannot retroactively release the scaled time of this frame.
	var external_pause: bool = _transition_pause_frame or _temporal_ui_pause_active() or vendor_unlock.is_active()
	var scaled_delta: float = delta * session.speed if session.phase == "playing" and not session.paused and not external_pause else 0.0
	_advance_puffs(delta, scaled_delta)
	_update_camera_motion(delta)
	# Source recomputes the held target each frame, including camera-only motion.
	if _card_pointer_known:
		var pointer := _card_pointer
		if camera_pointer.primary_active and camera_pointer.known:
			pointer = get_viewport().get_final_transform().affine_inverse() * camera_pointer.position
		for state in _active_card_drags(): _update_card_drag(state,pointer)
	vendor_unlock.advance(delta)
	combat_presentation.advance(delta)
	if external_pause:
		# Combat travel/return and cycle waits remain real-time under external
		# menu/reveal pauses. Their scaled death waits and action clocks stop.
		session.tick_paused(delta)
		_advance_source_outside_equipment_press()
		_sync_views(delta)
		return
	session.tick(delta)
	day_clock.sync(session, running, _ui_pause_active(), _ordinary_source_pause_icon())
	equipment_display.advance(scaled_delta)
	_advance_source_outside_equipment_press()
	_sync_views(delta)
	refresh_clock += delta
	if refresh_clock >= 0.2:
		refresh_clock = 0
		_refresh()

func _name(guid: String) -> String:
	var fields: Dictionary = catalog.fields(guid)
	return str(fields.get("displayName", fields.get("id", guid)))

func _sync_views(real_delta: float = 0.0) -> void:
	for state in _active_card_drags():
		if not state.combat.is_empty() and not _source_combat_hold_current(state.id,state): state.combat.clear()
		if not _held_receiver_current(state): _discard_vanished_hold(state)
	_sync_combat_layouts()
	_ensure_layout()
	for id in views.keys():
		if not session.cards.has(id):
			if id in [hovered_card_id, hovered_panel_owner]: _clear_card_hover()
			views[id].queue_free()
			views.erase(id)
	for id in session.cards:
		if views.has(id) and views[id].get_meta("definition_guid", "") != session.cards[id].definition_guid:
			if id in [hovered_card_id, hovered_panel_owner]: _clear_card_hover()
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
			var held := _card_drag_for(id)
			var combat_position: Vector2 = session.cards[id].position + (held.delta if held != null else Vector2.ZERO)
			views[id].position = held.combat.pose if held != null and held.combat.get("id", -1) == id else Vector3(combat_position.x, 0.0, -combat_position.y)
	for landing_id in _terminal_landings.keys():
		if not _terminal_landing_current(landing_id): _terminal_landings.erase(landing_id)
	for return_id in _combat_slot_returns.keys():
		if not _combat_slot_return_current(return_id): _combat_slot_returns.erase(return_id)
	var motion_records: Array = []
	var motion_settings: Dictionary = CardDragInput.source_settings(catalog, session.scene_name)
	var cycle_id: int = int(session.cycle.presentation_state().get("card_id", -1))
	var step_fields: Dictionary = motion_settings.get("stackStep", {})
	var step := Vector3(float(step_fields.get("x", 0)), float(step_fields.get("y", 0.002)), -float(step_fields.get("z", -0.18)))
	for stack in session.stacks.values():
		var held_index := -1
		var held: BoardDrag
		for index in range(stack.card_ids.size()):
			held = _card_drag_for(stack.card_ids[index])
			if held != null:
				held_index = index
				break
		for index in range(stack.card_ids.size()):
			var id: int = stack.card_ids[index]
			var card = session.cards[id]
			var target := Vector3(stack.position.x, 0.06, -stack.position.y) + step * index
			if _terminal_landings.has(id): target = _terminal_landings[id].target
			var mode: String = "animated"
			if held_index >= 0 and index >= held_index:
				target += Vector3(held.delta.x, 0, -held.delta.y)
				target.y = float(motion_settings.get("dragHeight", 0.1)) + (index-held_index)*step.y
				mode = "instant" if index == held_index else "damped"
			if session.combat.membership.has(id) or session.equipment.owners.has(id) or id == cycle_id \
					or (held != null and held.id == id and held.deferred_gear_pose): mode = "blocked"
			motion_records.append({"id":id,"identity":"%d:%s" % [card.get_instance_id(),card.definition_guid],"target":target,"current":views[id].position,"mode":mode,"leader":stack.card_ids[index-1] if index > 0 else -1,"step":step})
			views[id].highlight(id == selected)
	for id in _combat_slot_returns:
		var card = session.cards[id]
		motion_records.append({"id":id,"identity":"%d:%s" % [card.get_instance_id(),card.definition_guid],"target":_combat_slot_returns[id].target,"current":views[id].position,"mode":"animated"})
	var motion_poses: Dictionary = card_motion.sync(motion_records, real_delta, motion_settings)
	for id in motion_poses: views[id].position = motion_poses[id]
	for id in _combat_slot_returns.keys():
		if views[id].position == _combat_slot_returns[id].target: _combat_slot_returns.erase(id)
	var durations := {0: 0.3, 1: 0.3, 2: session.combat.projectile_duration(2), 3: session.combat.projectile_duration(3)}
	combat_presentation.visual_assets = visual_assets
	combat_presentation.scene_name = session.scene_name
	combat_presentation.sync(session.combat.tasks, views, durations, self)
	var shake: Vector2 = combat_presentation.camera_offset()
	camera.h_offset = shake.x
	camera.v_offset = shake.y
	CyclePresentation.apply(session.cycle.presentation_state(), views)
	_sync_equipment_display()
	_sync_card_feedback()

# EquipmentPanel.Update 独立于 GUI，按本帧最新共享坐标发射实体射线。
func _advance_source_outside_equipment_press() -> void:
	if _source_equipment_outside == null: return
	var window_position: Variant = _source_equipment_outside.take_press()
	if window_position == null: return
	var screen: Vector2 = get_viewport().get_final_transform().affine_inverse() * window_position
	var hit := _pick_target(screen)
	var id: int = int(hit.card_id)
	var gear: bool = session.cards.has(id) and int(catalog.fields(session.cards[id].definition_guid).get("category",0))==5
	equipment_display.pointer_down(int(hit.panel_owner),gear)


func _pick_target(screen: Vector2) -> Dictionary:
	var origin := camera.project_ray_origin(screen)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(screen) * 100)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty(): return {"card_id": -1, "panel_owner": -1, "trade_zone_index": -1}
	return {"card_id": int(hit.collider.get_meta("card_id", -1)), "panel_owner": int(hit.collider.get_meta("equipment_panel_owner", -1)), "trade_zone_index": int(hit.collider.get_meta("trade_zone_index", -1))}

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

func _configure_source_hud() -> void:
	if source_hud == null: return
	var factor: float = hud.size.y / hud_layout.reference_height
	if factor <= 0: return
	source_hud.scale = Vector2.ONE * factor
	source_hud.size = hud.size / factor
	var extent := source_hud.size
	var day: Rect2 = hud_layout.rect("DayTimeUI", extent, Rect2(30, 30, 300, 50))
	day_clock.position = day.position
	day_clock.size = day.size
	var stats: Rect2 = hud_layout.rect("CardStatsUI", extent, Rect2(360, 30, 0, 50))
	stats_box.position = stats.position
	stats_box.size.y = stats.size.y
	var stats_fields:Dictionary={}
	for key in ["m_ChildAlignment","m_ChildControlWidth","m_ChildControlHeight","m_ChildForceExpandWidth","m_ChildForceExpandHeight","m_ChildScaleWidth","m_ChildScaleHeight","m_Spacing","m_Padding","m_ReverseArrangement","m_HorizontalFit","m_VerticalFit"]:
		stats_fields[key]=hud_layout.field("CardStatsUI",key,null)
	stats_box.configure_source(stats_fields)
	if stat_labels.is_empty() and not hud_layout.documents.is_empty():
		for field in ["Nutrition", "Currency", "Card"]:
			var icon := TextureRect.new()
			icon.texture = visual_assets.texture(str(hud_layout.field(field + "Icon", "m_Sprite", {}).get("guid", "")))
			icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
			icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
			var asset: Dictionary = visual_assets.manifest.get("assets", {}).get(str(hud_layout.field(field + "Icon", "m_Sprite", {}).get("guid", "")), {})
			var sprite: Dictionary = asset.get("sprite", {})
			var preferred_width: float = float(sprite.get("pixel_size", {}).get("x", 64)) * 100.0 / float(sprite.get("pixels_per_unit", 100))
			icon.custom_minimum_size = Vector2(preferred_width, 30)
			icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			stats_box.add_element(icon)
			var stat_label = SourceStatsText.new()
			stats_box.add_element(stat_label)
			stat_label.layout_contract_changed.connect(_restore_source_stats_height, CONNECT_DEFERRED)
			stat_label.configure(hud_layout.text_record("CardStatsUI/" + field + "Label"),SourceStatsText.source_height_from(hud_layout.field(field + "Label","m_SizeDelta",null)))
			stat_labels.append(stat_label)
	var stats_style := StyleBoxFlat.new()
	stats_style.bg_color = hud_layout.color("CardStatsUI", Color(0, 0, 0, 0.8))
	stats_background.add_theme_stylebox_override("panel", stats_style)
	var menu: Rect2 = hud_layout.rect("MenuPanel", extent, Rect2(extent.x-400, 0, 400, extent.y))
	var was_open: bool = journal_slide.target_x <= 0
	detail_panel.position = menu.position
	detail_panel.size = menu.size
	journal_slide.open_position = menu.position
	journal_slide.reset(was_open)
	var header: Rect2 = hud_layout.rect("Header", menu.size, Rect2(0, 0, menu.size.x, 60))
	journal_tabs.position = header.position
	journal_tabs.size = header.size
	journal_tabs.add_theme_constant_override("separation", 0)
	# Source Header Image remains visible below each Toggle graphic.
	if not detail_panel.has_node("HeaderBackdrop"):
		var background := ColorRect.new()
		background.name = "HeaderBackdrop"
		background.mouse_filter = Control.MOUSE_FILTER_IGNORE
		detail_panel.add_child(background)
		background.position = header.position
		background.size = header.size
		background.color = hud_layout.color("Header", Color(.5,.5,.5,.9))
		detail_panel.move_child(background, 0)
	var header_background: ColorRect = detail_panel.get_node("HeaderBackdrop")
	header_background.position = header.position
	header_background.size = header.size
	for index in journal_tabs.get_child_count():
		var tab: Control = journal_tabs.get_child(index)
		tab.add_theme_font_size_override("font_size", 32)
		var source_path := "MenuPanel/Header/" + ("QuestsToggle" if index == 0 else "RecipesToggle") + "/Label"
		preload("res://scripts/ui/source_font_registry.gd").shared().bind_control(tab, hud_layout.text_record(source_path))
		var toggle_name := "QuestsToggle" if index == 0 else "RecipesToggle"
		var toggle_metadata: Dictionary = {}
		for component in hud_layout.components(toggle_name):
			if component.has("m_IsOn"):
				toggle_metadata = tab.resolve(hud_layout.documents, component.m_GameObject)
		tab.configure(toggle_metadata)
	_sync_journal_header()
	var source_fonts = preload("res://scripts/ui/source_font_registry.gd").shared()
	for tab in journal_bodies:
		var body: Control = journal_bodies[tab]
		var view := "QuestsView" if tab == "quests" else "RecipesView"
		var viewport_rect: Rect2 = hud_layout.rect(view, menu.size,
			Rect2(0,header.size.y,menu.size.x,maxf(0,menu.size.y-header.size.y)))
		body.position = viewport_rect.position
		body.size = viewport_rect.size
		body.set_background(hud_layout.color(view, Color(0,0,0,0.9019608)))
		var contract: Dictionary = JournalScrollContract.resolve(hud_layout.documents, view)
		var admitted: bool = body.configure_source_scroll(contract)
		body.drag_threshold = float(hud_layout.field("EventSystem","m_DragThreshold",10))
		body.scroll_delta_per_tick = float(hud_layout.field("EventSystem","m_ScrollDeltaPerTick",6))
		var rows: Control = journal_rows[tab]
		if body.source_pointer_managed!=admitted:
			journal_pointer.reset()
		body.source_pointer_managed = admitted
		rows.source_pointer_managed = admitted
		rows.configure(source_fonts)
		rows.set_scroll_layout(contract if admitted else {})
		rows.set_content_width(viewport_rect.size.x)
	source_fonts.bind_control(detail_toggle, hud_layout.text_record("MenuPanel/MenuToggle/Label"))
	var watermark_record: Dictionary = hud_layout.text_record("Watermark")
	source_fonts.bind_control(watermark, watermark_record)
	hud_layout.apply_text_color(watermark, watermark_record)
	var info_text_record: Dictionary = hud_layout.text_record("InfoPanel/InfoText")
	source_fonts.bind_control(card_hover.header, info_text_record)
	source_fonts.bind_control(card_hover.body, info_text_record)
	card_hover.configure_source_text_color(info_text_record)
	# Rebind restores prior overrides before recapturing a replacement theme.
	info_action_appearance.reset(info_action)
	info_action_source_record = hud_layout.text_record("InfoPanel/ActionButton")
	source_fonts.bind_control(info_action, info_action_source_record)
	var wm: Rect2 = hud_layout.rect("Watermark", extent, Rect2(extent.x/2-300, extent.y-40, 600, 40))
	watermark.position = wm.position
	watermark.size = wm.size
	watermark.text = str(hud_layout.field("Watermark", "m_text", ""))
	_layout_card_hover()

func _layout_card_hover() -> void:
	if card_hover == null or source_hud == null: return
	var area: Rect2 = hud_layout.rect("InfoPanel", source_hud.size, Rect2(30, source_hud.size.y-30, 400, 0))
	card_hover.set_bounds(Rect2(area.position, Vector2(area.size.x, 0)))

func _sync_journal_header(instant := false, replay := false) -> void:
	if journal_tabs == null: return
	for index in journal_tabs.get_child_count():
		journal_tabs.get_child(index).set_selected(index == (0 if active_tab == "quests" else 1), instant, replay and index == (0 if active_tab == "quests" else 1))

func _sync_source_info() -> void:
	if source_hud == null or not running: return
	_sync_journal_header()
	stats_background.position = stats_box.position
	stats_background.size = stats_box.size + Vector2(34, 0)
	stats_background.visible = stats_box.visible
	var toggle_rect: Rect2 = hud_layout.rect("MenuToggle", detail_panel.size, Rect2(-60, 60, 60, 60))
	detail_toggle.position = detail_panel.position + toggle_rect.position
	detail_toggle.size = toggle_rect.size
	detail_toggle.add_theme_font_size_override("font_size", 32)
	info_requests.submit("vendor", 1, vendor_unlock.sequence.info())
	var modal: Dictionary = {}
	match session.phase:
		"feeding":
			modal = {"header": "End of Day %d" % session.day, "body": "Your people are hungry!", "action": "Feed People"} if session.cycle.stage == "await_feed" else {"header": "Feeding People", "body": "Distributing food..."}
		"selling":
			var excess: int = session.stats().excess
			modal = {"header": "Sell Excess Cards", "body": "You must sell %d excess %s to continue." % [excess, "cards" if excess > 1 else "card"]}
		"encounter":
			var state: Dictionary = session.cycle.save_state()
			var message: String = str(catalog.fields(str(state.get("encounter_guid", ""))).get("notificationMessage", ""))
			if not message.is_empty(): modal = {"header": "Event", "body": message}
		"ready": modal = {"header": "Start of Day %d" % (session.day+1), "body": "Everything is ready.", "action": "Start Day"}
		"game_over": modal = {"header": "Game Over", "body": "You have no people left.", "action": "Return to Title"}
	info_requests.submit("day_cycle", 2, modal)
	var action_extent: Vector2 = preload("res://scripts/ui/source_info_action_layout.gd").resolve(catalog.data, str(info_requests.current().get("action", "")))
	card_hover.configure_source_action_height(action_extent.y if action_extent.y > 0.0 else -1.0)
	card_hover.set_descriptor(info_requests.current())
	notice.visible = market_panel.visible
	var action: String = str(info_requests.current().get("action", ""))
	info_action_appearance.apply(info_action, catalog.data, action, info_action_source_record)
	info_action.text = action
	info_action.visible = not action.is_empty()
	info_action.add_theme_font_size_override("font_size", 30)
	info_action.position = card_hover.position + Vector2(20, card_hover.size.y-40)
	info_action.size = Vector2(card_hover.size.x-40, 40)
	if action_extent.y > 0.0:
		info_action.position = card_hover.bottom_anchor - Vector2(0, action_extent.y)
		info_action.size = action_extent

func _record_card_pointer(screen: Vector2) -> void:
	if not screen.is_finite(): return
	_card_pointer = screen
	_card_pointer_known = true

func _clear_card_hover() -> void:
	hovered_trade_index = -1
	info_requests.submit("trade", 0, {})
	hovered_card_id = -1
	hovered_panel_owner = -1
	_hover_view_instance = 0
	_hover_definition = ""
	if is_instance_valid(card_hover):
		info_requests.submit("card", 0, {})
		_sync_source_info()

func _clear_drag_target_feedback() -> void:
	if drag_highlights.accepted_up(): card_drag_targets = {}

func _capture_drag_highlights(id: int) -> void:
	if session.combat.membership.has(id): return
	card_drag_targets.merge(drag_highlights.capture(session,views,trade_zones,trade_views,id))

func _clear_card_feedback() -> void:
	_card_pointer_known = false
	camera_pointer.known = false
	_feedback_session_instance = 0
	_feedback_scene = ""
	_clear_card_hover()
	_clear_drag_target_feedback()
	drag_highlights.dispose()
	card_drag_targets.clear()
	if is_instance_valid(craft_progress): craft_progress.reset()

func _hover_source_visible(id: int, panel: bool = false) -> bool:
	if not session.cards.has(id) or not views.has(id): return false
	var view = views[id]
	if not is_instance_valid(view) or view.is_queued_for_deletion() or not view.is_visible_in_tree(): return false
	if panel:
		return is_instance_valid(view.equipment_panel) and view.equipment_panel.is_visible_in_tree()
	return true

func _own_hover_control(control: Control) -> bool:
	return control != null and card_hover.visible and (control == card_hover or card_hover.is_ancestor_of(control))

func _sync_card_hover(gui: Control) -> void:
	# Source Hover is below Sequence and Modal. Keep notices/actions independent.
	if not _card_pointer_known or session.phase != "playing" or vendor_unlock.is_active():
		_clear_card_hover()
		return
	if gui != null and gui != hud and not _own_hover_control(gui):
		_clear_card_hover()
		return
	var trade_index: int = hovered_trade_index if _own_hover_control(gui) else int(_pick_target(_card_pointer).get("trade_zone_index", -1))
	if trade_index >= 0:
		var view = trade_views.get(trade_index)
		var info: Dictionary = view.get_info() if is_instance_valid(view) and view.is_visible_in_tree() and not view.is_queued_for_deletion() and view.pick_body.collision_layer != 0 else {}
		_clear_card_hover()
		hovered_trade_index = trade_index if not info.is_empty() else -1
		info_requests.submit("trade", 0, info)
		_sync_source_info()
		return
	hovered_trade_index = -1
	info_requests.submit("trade", 0, {})
	var id: int = hovered_panel_owner if hovered_panel_owner >= 0 else hovered_card_id
	var panel: bool = hovered_panel_owner >= 0
	if _own_hover_control(gui):
		# Preserve its valid source while scrolling; never ray-pick through the panel.
		if not _hover_source_visible(id, panel) or views[id].get_instance_id() != _hover_view_instance or session.cards[id].definition_guid != _hover_definition:
			_clear_card_hover()
			return
	else:
		var hit: Dictionary = _pick_target(_card_pointer)
		panel = int(hit.get("panel_owner", -1)) >= 0
		id = int(hit.get("panel_owner", -1)) if panel else int(hit.get("card_id", -1))
		if not _hover_source_visible(id, panel):
			_clear_card_hover()
			return
		hovered_panel_owner = id if panel else -1
		hovered_card_id = -1 if panel else id
		_hover_view_instance = views[id].get_instance_id()
		_hover_definition = session.cards[id].definition_guid
	var info: Dictionary = CardInteraction.equipment_panel_info(session, id) if panel else CardInteraction.hover_info(session, id)
	if info.is_empty(): _clear_card_hover()
	else:
		info_requests.submit("card", 0, info)
		_sync_source_info()

## Source ProgressUI is an old-scene object, not owned by the fade CanvasGroup.
## Keep only the source-attested ordinary playing scene. Menu/modal behavior is unchanged.
func _source_fade_progress_allowed() -> bool:
	if not (running and session.travel_pending and scene_transition.phase == "out" and session.phase == "playing" and session.catalog.data.get("provenance", {}).get("source_commit") == SourceColdCrafting.SOURCE_COMMIT and not pause_overlay.visible and not options_panel.visible and not _navigation_modal_active()): return false
	# A completed non-travel tail has unresolved source action ordering. Do not
	# silently suppress or display that task as part of this visibility adapter.
	var ready_travels := 0
	for stack in session.stacks.values():
		if stack.recipe_guid.is_empty(): continue
		var entry: Dictionary = catalog.get_definition(stack.recipe_guid)
		var duration: float = float(entry.get("fields", {}).get("craftingDuration", 0))
		var boundary := PackedFloat32Array([stack.progress, duration])
		if not is_finite(boundary[0]) or not is_finite(boundary[1]) or boundary[1] <= 0: return false
		if boundary[0] >= boundary[1]:
			if entry.get("script_class") != "TravelRecipe" or stack.progress < duration: return false
			ready_travels += 1
	return ready_travels == 1

func _sync_card_feedback() -> void:
	if not is_instance_valid(card_hover) or not is_instance_valid(craft_progress): return
	# Numeric IDs may be reused after travel/load, so clear before reading a new owner.
	if _feedback_session_instance != session.get_instance_id() or _feedback_scene != session.scene_name:
		_clear_card_feedback()
		_feedback_session_instance = session.get_instance_id()
		_feedback_scene = session.scene_name
	if not running or not hud.visible or title_panel.visible:
		_clear_card_hover()
		if is_instance_valid(craft_progress): craft_progress.reset()
		return
	var fade_progress: bool = _source_fade_progress_allowed()
	if _ui_pause_active() or _navigation_modal_active():
		_clear_card_hover()
		if not fade_progress:
			craft_progress.reset()
			return # Existing held pointer permission/model pause is never changed here.
	var progress: Dictionary = CardInteraction.crafting_progress(session)
	if fade_progress and session.travel_pending:
		# Source removes finished task UIs in the same Update, including travel.
		# Native's transaction retains those stacks until the destination swap.
		for id in progress.keys():
			if float(progress[id].remaining) <= 0 and catalog.get_definition(str(progress[id].recipe_guid)).get("script_class") == "TravelRecipe": progress.erase(id)
	if vendor_unlock.is_active():
		for descriptor in progress.values(): descriptor.paused = true
	craft_progress.bind_source(visual_assets, session.scene_name)
	craft_progress.sync(progress)
	if fade_progress:
		_clear_card_hover()
		return # Presentation only. No pointer/hover is admitted through the shade.
	var gui: Control = get_viewport().gui_get_hovered_control()
	_sync_card_hover(gui)

# Pointer routing is separate from ray casting for deterministic adapter tests.
func _begin_card_press(hit: Dictionary, screen: Vector2, raw_observed: bool = false) -> void:
	if _mouse_drag.id >= 0: return
	if _touch_drags.has(int(hit.get("card_id",-1))): return
	_record_card_pointer(screen)
	var id: int = int(hit.get("card_id",-1))
	var panel: int = int(hit.get("panel_owner",-1))
	var is_gear: bool = session.cards.has(id) and int(catalog.fields(session.cards[id].definition_guid).get("category",0)) == 5
	if not raw_observed: equipment_display.pointer_down(panel,is_gear)
	selected = id
	pressed_panel = panel if panel >= 0 and _allows_equipment_panel_input() else -1
	if panel >= 0:
		_sync_card_feedback()
		return
	_begin_card_drag(_mouse_drag,id,screen)

func _begin_card_drag(state: BoardDrag, id: int, pointer: Vector2) -> void:
	if state != _mouse_drag and not session.combat.membership.has(id) and not session.equipment.owners.has(id) and not session.drag.can_begin_for(id):
		return
	state.grant = -1
	state.combat.clear()
	state.deferred_gear_pose = false
	var detached_pose: Variant = null
	var is_gear: bool = session.cards.has(id) and int(catalog.fields(session.cards[id].definition_guid).get("category",0)) == 5
	if is_gear and session.equipment.owners.has(id) and _allows_card_actions():
		var wearer: int = session.equipment.owners[id]
		var old_position: Vector3 = views[id].global_position
		for slot in session.equipment.equipped.get(wearer, {}):
			if session.equipment.equipped[wearer][slot] == id and session.equipment.unequip(wearer,slot,Vector2(old_position.x,-old_position.z)) == id:
				detached_pose = Vector3(old_position.x,0,old_position.z)
				break
		if detached_pose == null: return
		state.id = id # Lock the just-detached stack before placement can move its visible pose.
		state.deferred_gear_pose = true
		_sync_views()
		views[id].global_position = detached_pose
	state.id = id if _can_drag_card(id) else -1
	if state.id == id:
		_terminal_landings.erase(id)
		_combat_slot_returns.erase(id)
	if state.id >= 0 and session.combat.membership.has(id):
		state.start = session.card_target_position_3d(id) # Existing unrelated combat drop adapter.
	if state.id >= 0 and not session.combat.membership.has(id):
		var pose: Vector3 = views[id].global_position
		var lifted := Vector2(pose.x,-pose.z)
		if detached_pose == null:
			state.start = session.card_target_position_3d(id)
			state.start.x = lifted.x
			state.start.z = lifted.y
			views[id].standard_drag_start = state.start
		else:
			state.start = views[id].standard_drag_start
		if not _begin_model_drag(state,id,lifted).ok:
			state.id = -1
			state.deferred_gear_pose = false
		elif detached_pose == null:
			_set_board_card_position(id, lifted)
	state.grant = state.id
	if state.id >= 0:
		session.combat.dragged[state.id] = true
		# Source combat PointerDown returns before the standard CardPick call.
		# Do not suppress CardDrop: accepted PointerUp dispatches it before drop classification.
		if detached_pose == null and not session.combat.membership.has(state.id): feedback.play_event("CardPick")
	state.screen = pointer
	state.origin = _board_point(pointer)
	state.anchor = session.card_target_position(state.id) if session.cards.has(state.id) else Vector2.ZERO
	if detached_pose is Vector3: state.anchor = Vector2(detached_pose.x,-detached_pose.z)
	state.delta = Vector2.ZERO
	state.moved = false
	if state.id >= 0 and _source_combat_hold_allowed(id):
		var pose: Vector3 = views[id].global_position
		state.combat = {"id":id,"task":session.combat.membership[id],"card":session.cards[id].get_instance_id(),"view":views[id].get_instance_id(),"pose":pose}
		var slot: Variant = combat_layouts[session.combat.membership[id]].positions.get(id)
		if slot is Vector2 and session.combat.tasks[session.combat.membership[id]].get("execution", {}).is_empty() and pose == Vector3(slot.x,0,-slot.y):
			state.combat["return_slot"] = pose
		state.anchor = Vector2(pose.x,-pose.z)
	if state.id >= 0: _capture_drag_highlights(state.id)
	_sync_card_feedback()

func _active_card_drags() -> Array[BoardDrag]:
	var result: Array[BoardDrag] = []
	if _mouse_drag.id >= 0: result.append(_mouse_drag)
	for state: BoardDrag in _touch_drags.values():
		if state.id >= 0: result.append(state)
	return result

func _card_drag_for(id: int) -> BoardDrag:
	if id < 0: return null
	if _mouse_drag.id == id: return _mouse_drag
	var state: BoardDrag = _touch_drags.get(id)
	return state if state != null and state.id == id else null

func _has_card_drag() -> bool:
	return _mouse_drag.id >= 0 or not _touch_drags.is_empty()

func _held_receiver_current(state: BoardDrag) -> bool:
	if not session.cards.has(state.id): return false
	if state.receiver == null: return true
	var view = state.receiver.get_ref()
	return is_instance_valid(view) and not view.is_queued_for_deletion() and views.get(state.id) == view and view.get_meta("definition_guid","") == session.cards[state.id].definition_guid

func _discard_vanished_hold(state: BoardDrag) -> void:
	var vanished: int = state.id
	state.id = -1
	state.grant = -1
	state.delta = Vector2.ZERO
	_touch_drags.erase(vanished)
	session.combat.dragged.erase(vanished)
	session.drag.finish_standard_for(vanished)

func _drag_locks_stack(id: int) -> bool:
	for state in _active_card_drags():
		if session.cards.has(state.id) and session.cards[state.id].stack_id == id: return true
	return false

func _begin_model_drag(state: BoardDrag, id: int, lifted: Variant) -> Dictionary:
	return session.drag.begin(id,lifted) if state == _mouse_drag else session.drag.begin_for(id,lifted)

# Run only after native GUI has had its chance to consume the actual contact.
# Receiver location is per contact; CardController projects the shared Pointer.
func _touch_card_down(index: int, screen: Vector2) -> bool:
	if not running or not camera_pointer.contacts.has(index) or not screen.is_finite(): return false
	var hit := _pick_target(screen)
	var id: int = int(hit.card_id)
	if int(hit.panel_owner) >= 0: return _touch_panel_down(index,int(hit.panel_owner))
	if id < 0 or not _hover_source_visible(id): return false
	var view: Node3D = views[id]
	if not touch_card_receivers.capture(index,view): return false
	if not _allows_card_actions() or _mouse_drag.id == id: return true
	var state: BoardDrag = _touch_drags.get(id)
	if state != null and not _held_receiver_current(state):
		_discard_vanished_hold(state)
		state = null
	if state == null:
		state = BoardDrag.new()
		state.receiver = weakref(view)
		_touch_drags[id] = state
	var is_gear: bool = int(catalog.fields(session.cards[id].definition_guid).get("category",0)) == 5
	if _source_equipment_outside == null and camera_pointer.primary_index == index and not camera_pointer.orphan:
		equipment_display.pointer_down(-1,is_gear)
	selected = id
	var pointer := _card_pointer if _card_pointer_known else screen
	var ordinary: bool = not session.combat.membership.has(id) and not session.equipment.owners.has(id)
	_begin_card_drag(state,id,pointer)
	if state.id >= 0 and ordinary: _update_card_drag(state,pointer)
	if state.id < 0: _touch_drags.erase(id)
	return true

# EquipmentPanel is an IPointerClick rather than CardController's captured UP.
# GUI admits both edges; a canceled/occluded release cannot click the panel.
func _touch_panel_down(index: int, wearer: int) -> bool:
	var collider = equipment_display.records.get(wearer,{}).get("collider")
	if not is_instance_valid(collider) or collider.is_queued_for_deletion(): return false
	if _source_equipment_outside == null and camera_pointer.primary_index == index and not camera_pointer.orphan:
		equipment_display.pointer_down(wearer,false)
	selected = wearer
	_touch_panel_serial += 1
	_touch_panel_presses[index] = {"receiver":weakref(collider),"wearer":wearer,"serial":_touch_panel_serial}
	_sync_card_feedback()
	return true

func _expire_touch_panel_press(index: int, serial: int) -> void:
	if _touch_panel_presses.get(index,{}).get("serial",-1) == serial:
		_touch_panel_presses.erase(index)

func _touch_panel_up(index: int, position: Vector2) -> bool:
	if not _touch_panel_presses.has(index): return false
	var receipt: Dictionary = _touch_panel_presses[index]
	_touch_panel_presses.erase(index)
	if not _allows_equipment_panel_input() or not position.is_finite() or _hud_blocks_panel_click(hud,position): return true
	var collider = receipt.receiver.get_ref()
	var wearer: int = receipt.wearer
	if (is_instance_valid(collider) and not collider.is_queued_for_deletion()
			and equipment_display.records.get(wearer,{}).get("collider") == collider
			and int(_pick_target(position).panel_owner) == wearer):
		equipment_display.click_panel(wearer)
		_sync_card_feedback()
	return true

# Godot cannot deliver a new GUI target a release that started on the Board.
# Source IPointerClick still checks the current event-position ray. Test the
# visible, unclipped HUD hit boxes here; never reuse cached mouse hover for a finger.
func _hud_blocks_panel_click(control: Control, point: Vector2) -> bool:
	if not is_instance_valid(control) or not control.is_visible_in_tree(): return false
	var inside := _journal_rect_contains(control,point)
	if control.clip_contents and not inside: return false
	if inside and control.mouse_filter == Control.MOUSE_FILTER_STOP: return true
	for child in control.get_children():
		if child is Control and _hud_blocks_panel_click(child,point): return true
	return false

func _touch_card_up(index: int) -> bool:
	if not touch_card_receivers.owns(index): return false
	var view = touch_card_receivers.release(index)
	if not running or not is_instance_valid(view): return true
	var id: int = view.card_id
	var state: BoardDrag = _touch_drags.get(id)
	if state == null or state.id != id or state.receiver.get_ref() != view: return true
	if _held_receiver_current(state):
		_touch_drags.erase(id)
		_finish_card_drag(state)
	else:
		_discard_vanished_hold(state)
	return true

func _board_point(screen: Vector2) -> Vector2:
	var point = Plane(Vector3.UP, 0).intersects_ray(camera.project_ray_origin(screen), camera.project_ray_normal(screen))
	if point == null: return Vector2.ZERO
	return Vector2(point.x, -point.z)

func _unhandled_input(event: InputEvent) -> void:
	if scene_transition.blocks_input():
		get_viewport().set_input_as_handled()
		return
	if NavigationInput.is_cancel_press(event):
		_handle_escape()
		get_viewport().set_input_as_handled()
		return
	if event is InputEventScreenTouch:
		var accepted := false
		if not event.canceled:
			accepted = _touch_card_down(event.index,event.position) if event.pressed else _touch_panel_up(event.index,event.position)
		if accepted: get_viewport().set_input_as_handled()
		return
	if not running or _ui_pause_active(): return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_RIGHT:
			var right_hit: Dictionary = _pick_target(event.position)
			if event.pressed:
				selected = int(right_hit.card_id)
				right_pressed_panel = int(right_hit.panel_owner)
				_refresh()
			else:
				if _allows_equipment_panel_input() and right_pressed_panel >= 0 and right_pressed_panel == int(right_hit.panel_owner): equipment_display.click_panel(right_pressed_panel)
				right_pressed_panel = -1
		if event.button_index == MOUSE_BUTTON_LEFT:
			if event.pressed:
				var hit: Dictionary = _pick_target(event.position)
				# Native touch remains authoritative for card receivers. Keep
				# touch-emulated mouse on the existing panel/blank path.
				if event.device != InputEvent.DEVICE_ID_EMULATION or int(hit.card_id) < 0:
					_begin_card_press(hit, event.position, _source_equipment_outside!=null)
			else:
				if event.device != InputEvent.DEVICE_ID_EMULATION or pressed_panel >= 0:
					_finish_drag(event.position)

# Releases over a panel still terminate a drag. GUI should never leave cards attached.
var _outbound_camera_owner: int = 0
var _outbound_camera_generation: int = -1
var _camera_scroll_sample: float = 0.0
var _camera_scroll_owner: int = 0
var _camera_scroll_generation: int = -1
var _camera_scroll_during_fade: bool = false
# An ordinary portal externally pauses the clock, not InputManager. Only the
# verified departing owner/phase uses this branch; the full-screen fade still
# consumes new UI/world presses and blocks CameraController's fresh left clause.
func _source_outbound_camera_allowed() -> bool:
	return _outbound_camera_owner == session.get_instance_id() \
		and _outbound_camera_generation == scene_transition.generation \
		and running and session.travel_pending and scene_transition.phase == "out" \
		and session.phase == "playing" and session.scene_name in ["Main", "Island"] \
		and catalog.data.get("provenance", {}).get("source_commit") == SourceColdCrafting.SOURCE_COMMIT \
		and not vendor_unlock.is_active() and camera_motion.focus.is_empty() and not _has_card_drag() \
		and not pause_overlay.visible and not options_panel.visible and not _navigation_modal_active()

func _clear_outbound_camera() -> void:
	_outbound_camera_owner = 0
	_outbound_camera_generation = -1

func _input(event: InputEvent) -> void:
	if running:
		journal_pointer.observe(event,get_viewport().get_final_transform())
	if NavigationInput.is_cancel_press(event) and (_source_title_overlay_cancel() or _source_title_options_cancel() or _source_options_cancel()):
		get_viewport().set_input_as_handled()
		return
	# Device state advances even while source InputManager skips camera handling.
	# Only CameraController pan uses source window pixels. Card picking and
	# GUI events retain viewport coordinates. Store physical samples/origins so
	# a resize during a held pan cannot reinterpret an old logical pointer.
	var camera_event: Dictionary = camera_pointer.observe(event.xformed_by(get_viewport().get_final_transform()))
	if _source_equipment_outside != null and running:
		_source_equipment_outside.observe(event,camera_event,camera_pointer.position)
	if running and camera_event.sample and (event is InputEventScreenTouch or event is InputEventScreenDrag):
		_record_card_pointer(get_viewport().get_final_transform().affine_inverse() * camera_pointer.position)
	# A captured receiver gets up even if the up ray now hits GUI or a lock
	# arrived during the hold. The edge's position is not a new drag sample.
	if event is InputEventScreenTouch and (not event.pressed or event.canceled) and _touch_panel_presses.has(event.index):
		if event.canceled:
			_touch_panel_presses.erase(event.index)
		else:
			# If GUI consumes this release there is no world click, but the contact still expires.
			call_deferred("_expire_touch_panel_press",event.index,_touch_panel_presses[event.index].serial)
	var touch_up: bool = event is InputEventScreenTouch and (not event.pressed or event.canceled) and _touch_card_up(event.index)
	if OS.is_debug_build() and running and event is InputEventKey and event.keycode == KEY_F3 and event.pressed and not event.echo and not _ui_pause_active():
		market_panel.visible = not market_panel.visible
		get_viewport().set_input_as_handled()
		return
	if scene_transition.blocks_input():
		if _source_outbound_camera_allowed(): _observe_camera_scroll(event, true)
		get_viewport().set_input_as_handled()
		return
	if running and pause_overlay.visible and not options_panel.visible and not _navigation_modal_active():
		if MenuFocus.recover_navigation(event, pause_controls, get_viewport()): return
	# Gameplay owns Space before native GUI ui_accept can consume it. Keep
	# title, menu, options and modal activation on Godot's normal input route.
	if event is InputEventKey and event.keycode == KEY_SPACE and running and session.phase == "playing" and not _ui_pause_active() and not _navigation_modal_active():
		if event.pressed and not event.echo: _toggle_pause()
		# Consume release and autorepeat too, without toggling or pressing a HUD control.
		get_viewport().set_input_as_handled()
		return
	if running and (event is InputEventMouseMotion or event is InputEventMouseButton) and not camera_pointer.suppress_emulated_camera_event(event):
		_record_card_pointer(event.position)
	# Source HandleZoom never checks EventSystem: observe wheel before GUI, but
	# do not consume it (the same event can also scroll a source-style panel).
	if _camera_input_enabled(): _observe_camera_scroll(event, false)
	if touch_up:
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and not event.pressed and get_viewport().gui_get_hovered_control() != null:
		pressed_panel = -1
		right_pressed_panel = -1
	if _source_equipment_outside == null and running and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered != null and hovered != hud: equipment_display.pointer_down()
	if running and dragging >= 0 and event.device != InputEvent.DEVICE_ID_EMULATION:
		if event is InputEventMouseMotion:
			if _source_combat_hold_current(dragging): _record_card_pointer(event.position)
			else: _update_drag_position(event.position)
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			# Pointer-up belongs to the original press even over GUI or later locks.
			_finish_drag(event.position)

# Source-backed unrelated nonterminal attacker, or idle last player attacker.
# Terminal admission requires the locked no-AI player and native survivor slots.
# No melee actor, current target, equipment or transformed board.
func _source_combat_hold_allowed(id: int) -> bool:
	if global_transform != Transform3D.IDENTITY or not session.combat.membership.has(id): return false
	if catalog.data.get("provenance", {}).get("source_commit") != SourceColdCrafting.SOURCE_COMMIT or session.scene_name not in ["Main","Island"]: return false
	var task_id: int = session.combat.membership[id]
	if not session.combat.tasks.has(task_id) or not combat_layouts.has(task_id): return false
	var task: Dictionary = session.combat.tasks[task_id]
	if not task.player_is_attacker or id not in task.attackers or task.defenders.is_empty(): return false
	var execution: Dictionary = task.get("execution", {})
	if task.attackers.size() == 1:
		if not execution.is_empty() or session.ai.has_ai(id): return false
		# The departing hold is excluded from the terminal sampler after Flee.
		# Validate survivors now without moving either model or native nodes.
		for survivor in task.defenders:
			if not _source_terminal_hold_survivor(task_id, survivor): return false
	if not execution.is_empty():
		if execution.get("combat_type", -1) not in [2,3] or execution.get("phase","") not in ["travel","return"]: return false
		if id in [execution.get("actor",-1),execution.get("target",-1)]: return false
	if session.equipment.owners.has(id) or int(session.cycle.presentation_state().get("card_id",-1)) == id: return false
	if not views.has(id) or not is_instance_valid(views[id]) or views[id].is_queued_for_deletion() or views[id].get_parent() != self: return false
	return combat_presentation.sample_actor(id) == null and views[id].global_position.is_finite()

func _source_terminal_hold_survivor(task_id: int, id: int) -> bool:
	if not session.cards.has(id) or session.combat.membership.get(id,-1) != task_id: return false
	if session.combat.dragged.has(id) or _card_drag_for(id) != null or session.equipment.owners.has(id) or int(session.cycle.presentation_state().get("card_id",-1)) == id: return false
	if not views.has(id) or not is_instance_valid(views[id]) or views[id].is_queued_for_deletion() or views[id].get_parent() != self: return false
	var card = session.cards[id]
	if views[id].get_meta("definition_guid", "") != card.definition_guid or combat_presentation.sample_actor(id) != null: return false
	if card_motion.states.has(id) and card_motion.states[id].get("identity", "") != "%d:%s" % [card.get_instance_id(),card.definition_guid]: return false
	var point: Variant = combat_layouts[task_id].positions.get(id)
	return point is Vector2 and point.is_finite()

func _source_flee_unobstructed(id: int, destination: Vector2) -> bool:
	var task_id: int = session.combat.membership.get(id,-1)
	if not session.combat.tasks.has(task_id) or not combat_layouts.has(task_id): return false
	var task: Dictionary = session.combat.tasks[task_id]
	var remaining: Array = task.attackers.duplicate()
	remaining.erase(id)
	var resized: Dictionary = CombatLayout.update_layout(combat_layouts[task_id],_fighter_records(remaining),_fighter_records(task.defenders))
	if resized.is_empty(): return false
	var states: Array = _layout_states()
	states.append(BoardLayout.stack_state(-999,destination,_card_footprint(id),1,false,_stack_step()))
	var rectangles: Array = []
	for key in combat_layouts:
		# EndCombat closes this rectangle before ResolveOverlaps. Its defenders
		# are now separately registered, grounded singleton placement targets.
		if key == task_id and remaining.is_empty(): continue
		rectangles.append(resized.bounds if key == task_id else combat_layouts[key].bounds)
	if remaining.is_empty():
		for survivor in task.defenders:
			var point: Vector2 = resized.positions[survivor]
			var state := BoardLayout.stack_state(survivor,point,_card_footprint(survivor),1,false,_stack_step())
			state.position = BoardLayout.enforce_placement(point,state,session.board_bounds,session.board_top_margin)
			states.append(state)
	for i in states.size():
		var bounds: Rect2 = BoardLayout.stack_bounds(states[i])
		for rectangle in rectangles:
			if BoardLayout.separation(bounds,rectangle) != Vector2.ZERO: return false
		for j in range(i+1,states.size()):
			if BoardLayout.separation(bounds,BoardLayout.stack_bounds(states[j])) != Vector2.ZERO: return false
	return true

func _source_combat_hold_current(id: int, state: BoardDrag = null) -> bool:
	if state == null: state = _mouse_drag
	return state.combat.get("id",-1) == id and _source_combat_hold_allowed(id) and state.combat.task == session.combat.membership[id] and state.combat.card == session.cards[id].get_instance_id() and state.combat.view == views[id].get_instance_id()

func _update_drag_position(screen: Vector2) -> void:
	_record_card_pointer(screen)
	_update_card_drag(_mouse_drag,screen)

func _update_card_drag(state: BoardDrag, screen: Vector2) -> void:
	if not _held_receiver_current(state) or not screen.is_finite(): return
	state.deferred_gear_pose = false
	var point := _board_point(screen)
	state.delta = point - state.origin
	if _source_combat_hold_current(state.id,state):
		var held := _clamp_stack_position(state.id, state.anchor + state.delta, false)
		var height := float(CardDragInput.source_settings(catalog,session.scene_name).get("dragHeight",0.1))
		state.combat.pose = Vector3(held.x,height,-held.y)
		views[state.id].global_position = state.combat.pose
		state.delta = held - session.cards[state.id].position
	if session.drag.active_for(state.id) and not session.combat.membership.has(state.id):
		# Move the registered split, not only its drawing: saves/other systems
		# observe the real held position. Combat keeps its separate drag offset.
		_set_board_card_position(state.id, _clamp_stack_position(state.id, state.anchor + state.delta, false))
		state.delta = Vector2.ZERO
	state.moved = not CardDragInput.is_click(state.start, session.card_target_position(state.id) + state.delta, CardDragInput.source_settings(catalog, session.scene_name))

func _finish_drag(screen: Vector2) -> void:
	if pressed_panel >= 0:
		if _allows_equipment_panel_input() and int(_pick_target(screen).panel_owner) == pressed_panel: equipment_display.click_panel(pressed_panel)
		pressed_panel = -1
		return
	_finish_card_drag(_mouse_drag)

func _finish_card_drag(state: BoardDrag) -> void:
	var id: int = state.id
	var held_root := id
	var deferred_gear := state.deferred_gear_pose
	state.deferred_gear_pose = false
	# Pointer-up's event position is not a new UpdateDragPosition sample.
	var held_pose: Variant = views[id].global_position if _source_combat_hold_current(id,state) else null
	var return_slot: Variant = state.combat.get("return_slot")
	state.combat = {}
	var carried_press: bool = id >= 0 and state.grant == id and running
	state.grant = -1
	session.combat.dragged.erase(id)
	state.id = -1
	if id >= 0 and session.cards.has(id): _clear_drag_target_feedback()
	if (not _allows_card_actions() and not carried_press) or not session.cards.has(id):
		session.drag.finish_standard_for(held_root)
		state.delta = Vector2.ZERO
		return
	feedback.play_event("CardDrop")
	if session.combat.membership.has(id):
		_sync_combat_layouts()
		var task_id: int = session.combat.membership[id]
		var task: Dictionary = session.combat.tasks[task_id]
		var released: Vector2 = Vector2(held_pose.x,-held_pose.z) if held_pose is Vector3 else session.cards[id].position + state.delta
		var result: Dictionary = CombatLayout.drop_result(id, released, combat_layouts.get(task_id, {}), task.player_is_attacker, _card_footprint(id), session.board_bounds, session.board_top_margin)
		if result.flee:
			# Only no-separation releases enter the source held-position transaction.
			# Complex overlap settlement retains its existing, unaccepted adapter.
			var source_release: bool = held_pose is Vector3 and _source_flee_unobstructed(id, result.position)
			session.cards[id].position = released if source_release else result.position
			var terminal_landing: bool = source_release and task.attackers == [id] and task.get("execution", {}).is_empty()
			_terminal_landing_receipt = -1
			if session.combat.flee(id):
				_set_board_card_position(id, result.position)
				if terminal_landing and _terminal_landing_receipt == task_id and not session.combat.tasks.has(task_id) and not combat_layouts.has(task_id) and not combat_rectangles.has(task_id):
					_begin_terminal_landing(id, held_pose, result.position)
				notice.text = "Fled combat."
			_terminal_landing_receipt = -1
		elif held_pose is Vector3 and return_slot is Vector3 and task.get("execution", {}).is_empty() and CombatLayout.contains(combat_layouts.get(task_id, {}), released):
			_begin_combat_slot_return(id, task_id, held_pose, return_slot)
		session.drag.finish_terminal_for(held_root)
		state.delta = Vector2.ZERO
		_refresh()
		return
	# Programmatic/native adapter callers may submit a release directly. Actual
	# pointer input already split at press; this fallback never re-splits a hold.
	if not session.drag.active_for(held_root) and not _begin_model_drag(state,id,null).ok:
		state.delta = Vector2.ZERO
		return
	var destination: Vector2 = session.card_target_position(id) + state.delta
	if deferred_gear and views.has(id):
		var pose: Vector3 = views[id].global_position
		destination = Vector2(pose.x,-pose.z)
	_set_board_card_position(id, destination)
	var click_handled := false
	# Captured presses use the final world displacement, not whether the pointer
	# ever crossed a pixel threshold. Returning to the origin can be a click.
	var is_click: bool = CardDragInput.is_click(state.start, destination, CardDragInput.source_settings(catalog, session.scene_name)) if carried_press else not state.moved
	if is_click:
		if catalog.get_definition(session.cards[id].definition_guid).get("script_class", "") == "PackDefinition":
			var pack_stack: int = session.cards[id].stack_id
			layout_locks[pack_stack] = true
			session.open_pack(id, carried_press)
			layout_locks.erase(pack_stack)
			click_handled = true
		elif session.world._is_chest(id):
			click_handled = _withdraw_chest(id, carried_press, Vector2(state.start.x, state.start.z) if carried_press else destination)
	if click_handled:
		# Native safety cleanup for source HandleClick's early-return pause leak.
		session.drag.finish_standard_for(held_root)
	else:
		var trade: Dictionary = _try_trade_drop(id, destination, carried_press)
		if trade.terminal:
			session.drag.finish_terminal_for(held_root)
		else:
			id = int(trade.card_id)
			if not session.cards.has(id):
				session.drag.finish_standard_for(held_root)
			else:
				var equipment_target: int = _nearby_stack(id, Vector3(destination.x, 0, destination.y), float(catalog.settings("CardSettings").get("attachRadius", 0.25)), -1, true, held_root)
				if _try_equip_drop(id, destination):
					if session.equipment.owners.has(id): session.drag.finish_terminal_for(held_root)
					else: session.drag.finish_standard_for(held_root) # Existing native equipment-tail guard.
				elif _try_combat_drop(id, destination, equipment_target):
					session.drag.finish_terminal_for(held_root)
				else:
					destination = _clamp_stack_position(id, destination)
					_set_board_card_position(id, destination)
					var target: int = _nearby_stack(id, Vector3(destination.x, 0, destination.y), float(catalog.settings("CardSettings").get("attachRadius", 0.25)), -1, false, held_root)
					var attached := -1
					if target >= 0:
						var target_card: int = session.stacks[target].card_ids.back()
						var stored_before: int = session.cards[target_card].stored_coins
						if session.move_to_stack(id, target, session.drag.original_stack_id_for(held_root,id)):
							attached = target
							if session.world._is_chest(target_card): notice.text = "Stored %d coins." % (session.cards[target_card].stored_coins - stored_before)
						else:
							notice.text = "These cards cannot stack, or the current recipe rejects extra ingredients."
					session.drag.finish_standard_for(held_root,attached)
	state.delta = Vector2.ZERO
	_refresh()

func _refresh() -> void:
	_update_board_geometry()
	_sync_trade_zones()
	_sync_views()
	var stats: Dictionary = session.stats()
	day_clock.sync(session, running, _ui_pause_active(), _ordinary_source_pause_icon())
	market_heading.text = "STACKCRAFT / " + session.scene_name.to_upper()
	status.text = "Coins %d  ·  Food %d / %d  ·  Cards %d / %d\n%s" % [stats.currency, stats.nutrition, stats.nutrition_need, stats.cards_owned, stats.card_limit, "PAUSED" if session.paused else "%.0fx" % session.speed]
	status.hide()
	stats_box.visible = running and session.phase == "playing"
	if stat_labels.size() == 3:
		stat_labels[0].text = "%d/%d" % [stats.nutrition, stats.nutrition_need]
		stat_labels[1].text = str(stats.currency)
		stat_labels[2].text = "%d/%d" % [stats.cards_owned, stats.card_limit]
	pause_button.text = "Resume [Space]" if session.paused else "Pause [Space]"
	pause_button.disabled = not running or _ui_pause_active() or session.phase != "playing"
	for button in speed_buttons.values(): button.disabled = pause_button.disabled
	day_button.text = {"playing": "End day & feed", "feeding": "Feed villagers", "selling": "Sell %d excess cards" % stats.excess, "ready": "Start next day", "game_over": "Game over · return to title"}.get(session.phase, session.phase)
	if session.phase == "feeding" and session.cycle.stage != "await_feed":
		day_button.text = "Feeding · " + str(session.cycle.stage).replace("_", " ")
	elif session.phase == "encounter":
		day_button.text = "Encounter · " + str(session.cycle.stage).replace("_", " ")
	day_button.tooltip_text = day_button.text
	day_button.disabled = not running or _ui_pause_active() or session.phase in ["selling", "encounter"] or (session.phase == "feeding" and session.cycle.stage != "await_feed")
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
	_sync_source_info()

func _refresh_ledger() -> void:
	if not quest_journal.changed.is_connected(_on_quest_journal_changed):
		quest_journal.changed.connect(_on_quest_journal_changed)
	if ledger_session_id != session.get_instance_id() or ledger_scene_name != session.scene_name:
		ledger_session_id = session.get_instance_id()
		ledger_scene_name = session.scene_name
		journal_pointer.reset()
		ledger_expansion.clear()
		ledger_quest_order.clear()
		ledger_key = ""
		for tab in journal_body_state:
			journal_body_state[tab].key = ""
			journal_bodies[tab].reset_scroll()
			journal_rows[tab].reset_rows()
			info_requests.submit(_journal_request_key(tab), 0, {})
		quest_journal.bind(session.quest_tracker)
		info_requests.submit("journal", 0, {})
	ledger_quest_order = preload("res://scripts/ui/journal_groups.gd").reconcile_quest_order(session.quest_tracker, quest_journal.order)
	# MenuView hides through CanvasGroup, not SetActive: both views continue
	# observing activation/completion/discovery even when their tab is hidden.
	for tab in journal_bodies:
		_refresh_journal_body(tab)
	_sync_active_journal_body()

func _refresh_journal_body(tab: String) -> void:
	var renderer: Control = journal_rows[tab]
	var state: Dictionary = journal_body_state[tab]
	var rows: Array = preload("res://scripts/ui/journal_groups.gd").describe(catalog, session, tab, ledger_expansion, ledger_quest_order, quest_journal.captions())
	# Changing progress must not recreate a source button or renew a hover request.
	# Keep compatibility descriptors current, but exclude them from display identity.
	state.info.clear()
	if hud_layout.source_backed:
		rows = rows.filter(func(row): return not row.id.is_empty() or not row.group.is_empty())
	var display_rows: Array = []
	for row in rows:
		if not row.id.is_empty(): state.info[row.id] = row.get("info", {})
		var display: Dictionary = row.duplicate()
		if tab == "quests": display.erase("info")
		display_rows.append(display)
	var signature: String = tab + str(display_rows)
	if signature == state.key: return
	state.key = signature
	state.ids.clear()
	state.groups.clear()
	for row in rows:
		if not row.group.is_empty(): state.groups[row.group] = true
		elif not row.id.is_empty(): state.ids[row.id] = true
	renderer.set_rows(rows,preload("res://scripts/ui/journal_groups.gd").header_color(catalog,tab))

func _journal_source_mouse_hit(point: Vector2) -> Dictionary:
	if not get_viewport().get_visible_rect().has_point(point) or not _journal_release_uncovered(point,active_tab):
		return {}
	var body: Control = journal_bodies[active_tab]
	if not body.source_pointer_managed or _journal_has_later_blocker(body,point): return {}
	var id := body.get_instance_id()
	return {"click":journal_rows[active_tab].source_receiver_at(point),"drag":id,"scroll":id}

func _journal_has_later_blocker(control: Control, point: Vector2) -> bool:
	var ancestor: Node = control.get_parent()
	while ancestor is Control:
		for i in range(control.get_index()+1,ancestor.get_child_count()):
			var sibling := ancestor.get_child(i) as Control
			if sibling!=null and _hud_blocks_panel_click(sibling,point): return true
		control = ancestor
		ancestor = control.get_parent()
	return false

func _dispatch_journal_source_mouse(receipt: Dictionary, point: Vector2) -> void:
	var target := instance_from_id(receipt.receiver) as Control
	if not is_instance_valid(target) or target.is_queued_for_deletion(): return
	if receipt.kind=="click":
		var rows: Control = journal_rows.get(active_tab)
		if rows!=null and rows.owns_source_receiver(target) and target.is_visible_in_tree():
			target.click_source()
	elif target in journal_bodies.values():
		if receipt.kind=="scroll": target.scroll_ticks(receipt.ticks)
		elif receipt.button==MOUSE_BUTTON_LEFT: target.source_drag(receipt.kind,point)

## Unity TextButton click requires the release raycast to still resolve to the
## row. Native GUI capture can deliver the release after the mask or a later
## sibling changed. Do not consult the cached hover owner for that decision.
func _journal_release_uncovered(point: Vector2, tab: String) -> bool:
	if tab != active_tab or not journal_bodies.has(tab) or quit_dispatched: return false
	var body: Control = journal_bodies[tab]
	if not body.tab_active or not _journal_rect_contains(body,point): return false
	if _navigation_modal_active() or (recovery_window != null and recovery_window.visible): return false
	# These later source layers own pointer hits only in their current geometry.
	# Inbound ScreenFader is IGNORE even at opaque alpha; outbound is STOP.
	for blocker in [detail_toggle, pause_overlay, options_panel, scene_shade]:
		if is_instance_valid(blocker) and blocker.mouse_filter == Control.MOUSE_FILTER_STOP \
				and _journal_rect_contains(blocker,point):
			return false
	return true

func _journal_rect_contains(control: Control, point: Vector2) -> bool:
	return control.is_visible_in_tree() and Rect2(Vector2.ZERO,control.size).has_point(
		control.get_global_transform_with_canvas().affine_inverse() * point)

func _journal_request_key(tab: String) -> String:
	# Retain the existing quest requester key for callers; Recipes owns another.
	return "journal" if tab == "quests" else "journal:recipes"

func _sync_active_journal_body() -> void:
	for tab in journal_bodies:
		var body: Control = journal_bodies[tab]
		var selected_tab: bool = tab == active_tab
		if body.visible and not selected_tab:
			info_requests.submit(_journal_request_key(tab), 0, {})
		body.set_tab_active(selected_tab)
	# The compatibility/query reference is the active actual text renderer.
	ledger = journal_rows[active_tab]
	var state: Dictionary = journal_body_state[active_tab]
	ledger_key = state.key
	ledger_info = state.info
	ledger_visible_ids = state.ids
	ledger_visible_groups = state.groups

func _on_ledger_hover_ended(_meta: Variant, tab: String) -> void:
	info_requests.submit(_journal_request_key(tab), 0, {})

func _on_quest_journal_changed() -> void:
	# Source activation/completion updates its buttons synchronously. This path
	# only updates journal presentation, never geometry, transactions, or saves.
	if running: _refresh_ledger()

func _on_ledger_group_clicked(meta: Variant, tab: String = "") -> void:
	if tab.is_empty(): tab = active_tab
	if tab != active_tab: return
	if not meta is Dictionary or meta.size() != 1 or not meta.get("journal_group") is String: return
	if not ledger.is_visible_in_tree() or not ledger_visible_groups.has(meta.journal_group) or _ui_pause_active() or _navigation_modal_active(): return
	var key: String = meta.journal_group
	ledger_expansion[key] = not ledger_expansion.get(key, true)
	_refresh_ledger()
	_play_ui_click()

func _on_ledger_hover(meta: Variant, tab: String = "") -> void:
	if tab.is_empty(): tab = active_tab
	if tab != active_tab or not ledger.is_visible_in_tree(): return
	# QuestsView passes its QuestGroup object: the empty result still competes
	# at Hover priority. Recipes passes null and only clears its own key.
	if meta is Dictionary and meta.size() == 1 and ledger_visible_groups.has(meta.get("journal_group")):
		var owner := _journal_request_key(tab)
		if tab == "quests" and hud_layout.source_backed and catalog.data.get("provenance", {}).get("source_commit", "") == SourceColdCrafting.SOURCE_COMMIT:
			info_requests.submit_blank(owner, 0)
		else:
			info_requests.submit(owner, 0, {})
		return
	if not meta is String or not ledger_visible_ids.has(meta): return
	# MenuView queries GetItemInfo at pointer entry, not at the previous refresh.
	var info: Dictionary = quest_journal.info(meta) if active_tab == "quests" else ledger_info.get(meta, {})
	info_requests.submit(_journal_request_key(tab), 0, info)
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
	return "COMPLETED" if progress.complete else "Discovered:\n%d/%d" % [progress.found, progress.total]

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

func _cycle_clock_pace() -> void:
	if not running or title_panel.visible or _ui_pause_active() or session.phase != "playing": return
	session.cycle_time_pace()
	_refresh()
	# DayTimeUI sets its selected pace sprite before requesting Click.
	feedback.play_event("Click")

func _toggle_pause() -> void:
	if _ui_pause_active(): return
	if session.phase == "playing": session.set_paused(not session.paused)
	_refresh()

func _set_speed(speed: float) -> void:
	if not running or _ui_pause_active() or session.phase != "playing": return
	session.set_speed(speed)
	_refresh()

func _advance_day() -> void:
	if not running or _ui_pause_active() or game_over_dialog.visible: return
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
	return running and not _ui_pause_active() and not vendor_unlock.is_active() and session.phase in ["playing", "selling"]

func _allows_equipment_panel_input() -> bool:
	# Source EquipmentPanel visibility does not consult InputManager locks.
	return running and not _ui_pause_active() and session.phase in ["playing", "selling"]

func _active_slot_path() -> String:
	return slots.slot_path(active_slot)

func _has_save() -> bool:
	return selected_slot > 0 and slots._inspect(selected_slot).valid

func _refresh_slots() -> void:
	slots.configure(session.campaign, slot_root)
	listed_slot_ids.clear()
	archive_selected_button.disabled = true
	archive_all_button.disabled = true
	restore_archive_button.disabled = true
	var inventory: Dictionary = slots.list_slots()
	slot_picker.clear()
	if not inventory.ok:
		title_status.text = "Cannot read saves: " + str(inventory.error)
		continue_button.disabled = true
		if source_saved_rows != null: source_saved_rows.sync([])
		return
	var selected_index: int = -1
	for entry in inventory.slots:
		listed_slot_ids.append(int(entry.slot))
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
	archive_selected_button.disabled = selected_slot <= 0
	archive_all_button.disabled = listed_slot_ids.is_empty()
	_refresh_archives()
	if source_saved_rows != null: source_saved_rows.sync(inventory.slots)

func _select_slot(index: int) -> void:
	var entry: Variant = slot_picker.get_item_metadata(index)
	if not entry is Dictionary:
		selected_slot = 0
		archive_selected_button.disabled = true
		continue_button.disabled = true
		return
	selected_slot = int(entry.slot)
	archive_selected_button.disabled = false
	continue_button.disabled = not bool(entry.valid)
	if not entry.valid:
		title_status.text = "Slot %d is unavailable. Existing files were kept. %s" % [selected_slot, str(entry.errors)]

var _first_departure_save_owner = null
var _source_close_receipt: Dictionary = {}
var _source_inbound_close_receipt: Dictionary = {}

func _save_active_slot() -> Dictionary:
	if active_slot <= 0: return {"ok": false, "error": "No active save slot"}
	slots.configure(session.campaign if _first_departure_save_owner == null else _first_departure_save_owner, slot_root)
	var result: Dictionary = slots.save_slot(active_slot)
	if _first_departure_save_owner != null:
		if result.ok: session.campaign.last_saved = _first_departure_save_owner.last_saved.duplicate(true)
		slots.configure(session.campaign, slot_root)
	return result

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
	source_restore_entry = "cold_load"
	_enter_game({}, SourceColdCrafting.apply(session))
	notice.text = "Slot %d restored." % active_slot + (" Recovered from backup." if result.get("recovered", false) else "")

func _adopt_selected_legacy() -> void:
	if legacy_picker.item_count <= 0: return
	_request_scene_change(_adopt_legacy.bind(str(legacy_picker.get_item_metadata(legacy_picker.selected))))

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
	source_restore_entry = "cold_load"
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
	_source_equipment_outside = null
	_title_overlay_open_owner.clear()
	_title_options_open_owner.clear()
	_source_options_open_owner.clear()
	_source_options_owner_cache.clear()
	_source_inbound_close_receipt = {}
	if running: options_panel.reset_source_lifecycle()
	quest_journal.clear()
	ledger_session_id = 0
	for tab in journal_bodies:
		info_requests.submit(_journal_request_key(tab), 0, {})
	world_post_process.cancel()
	journal_pointer.reset()
	for body in journal_bodies.values():
		if body.source_pointer_managed and not body.pending_drag: body.motion.end_drag()
	journal_slide.reset(false)
	_clear_card_feedback()
	vendor_unlock.cancel()
	_cancel_archive_slots()
	archive_dialog.hide()
	_clear_puffs()
	session.drag.reset()
	_touch_drags.clear()
	_touch_panel_presses.clear()
	touch_card_receivers.reset()
	session.combat.dragged.clear()
	_mouse_drag = BoardDrag.new()
	card_motion.reset()
	_combat_slot_returns.clear()
	_terminal_landings.clear()
	_terminal_landing_receipt = -1
	combat_presentation.reset()
	camera.h_offset = 0
	camera.v_offset = 0
	equipment_display.reset()
	pressed_panel = -1
	right_pressed_panel = -1
	pause_overlay.hide()
	running = false
	_restore_title_world()
	dragging = -1
	hud.hide()
	title_navigation.open(TitleNavigation.HOME)
	_sync_title_destination()
	title_panel.show()
	_refresh_slots()
	for view in views.values(): view.hide()
	for rectangle in combat_rectangles.values(): rectangle.hide()
	for zone in trade_views.values(): zone.hide()
	_clear_card_feedback() # Menu visibility callbacks must not repopulate old bars.

func _prepare_quit() -> bool:
	# Source IsEndingCycle stays set from feeding through ready/game-over.
	if not running or session.phase != "playing": return true
	var result: Dictionary = _checkpoint("Quit checkpoint")
	return result.ok

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		# Detach only this owned source tabletop before child material Refs die.
		if is_instance_valid(flat_board_lighting): flat_board_lighting.clear()
		if is_instance_valid(original_board): SourceBoardLifetime.detach_meshes(original_board)
		return
	if what in [NOTIFICATION_WM_MOUSE_EXIT, NOTIFICATION_WM_WINDOW_FOCUS_OUT]:
		if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			camera_pointer.take_pan_edges()
			journal_pointer.reset()
			for body in journal_bodies.values():
				if body.source_pointer_managed and not body.pending_drag: body.motion.end_drag()
		_card_pointer_known = false
		camera_pointer.known = false
		_clear_card_hover()
		return
	if what != NOTIFICATION_WM_CLOSE_REQUEST or quit_dispatched or _navigation_modal_active(): return
	if scene_transition.active():
		if scene_transition.phase == "in":
			if preload("res://scripts/ui/source_inbound_close.gd").allowed(self, _source_inbound_close_receipt) and _prepare_quit(): _execute_quit()
			return
		var snapshot: Dictionary = preload("res://scripts/ui/source_precommit_close.gd").capture(self, _source_close_receipt)
		if snapshot.is_empty(): return
		var save_owner = Session.new()
		save_owner.configure(catalog)
		var restored: Dictionary = save_owner.campaign.restore(snapshot)
		if not restored.ok:
			notice.text = "Quit checkpoint · SAVE FAILED: " + str(restored.get("error", "Invalid source quit snapshot")) + ". Live game kept open; retry close."
			return
		_first_departure_save_owner = save_owner.campaign
		var saved: Dictionary = _checkpoint("Quit checkpoint")
		_first_departure_save_owner = null
		if saved.ok: _execute_quit()
		return
	if options_panel != null and options_panel.visible and options_panel.dirty:
		options_panel.request_close()
		if options_panel.visible: return
	if running and session.phase != "playing":
		pending_quit = "day_end"
		quit_dialog.title = "Quit during day-end?"
		quit_dialog.dialog_text = "Day-end progress is not autosaved on quit. Your last checkpoint stays intact. Quit now?"
		quit_dialog.popup_centered()
	elif _prepare_quit():
		_execute_quit()

func _navigation_modal_active() -> bool:
	if is_instance_valid(source_title_quit) and source_title_quit.visible: return true
	for dialog in [archive_dialog, game_over_dialog, quit_dialog]:
		if dialog != null and dialog.visible: return true
	return options_panel != null and options_panel.reset_dialog != null and options_panel.reset_dialog.visible

func _request_title_quit() -> void:
	if scene_transition.active(): return
	if running or quit_dispatched or options_panel.visible or _navigation_modal_active(): return
	if data_error == OK and is_instance_valid(source_title_quit):
		if not _source_title_quit_home(): return
		var focus: Control = get_viewport().gui_get_focus_owner()
		if is_instance_valid(focus): focus.release_focus()
		pending_quit = "source_title"
		source_title_quit.show_dialog()
		return
	pending_quit = "title"
	quit_dialog.title = "Quit Game"
	quit_dialog.dialog_text = "Are you sure you want to quit the game?"
	quit_dialog.popup_centered()

func _cancel_quit() -> void:
	if pending_quit != "source_title": pending_quit = ""

func _confirm_quit() -> void:
	if scene_transition.active() or pending_quit == "source_title": return
	var requested: String = pending_quit
	pending_quit = "" # Consume a confirmation once, including a stale request.
	quit_dialog.hide()
	if requested == "title" and not running and not options_panel.visible:
		_execute_quit()
	elif requested == "day_end" and running and session.phase != "playing":
		_execute_quit()

func _execute_quit() -> void:
	_source_inbound_close_receipt = {}
	_source_close_receipt = {}
	scene_transition.cancel()
	session.travel_pending = false
	if quit_dispatched: return
	quit_dispatched = true
	if quit_callback.is_valid():
		# Request-only seam for navigation tests; those tests retain the live board.
		quit_callback.call()
	else:
		# Stopping during _exit_tree is too late: AudioServer releases its queued
		# playback references on the mix thread, after SceneTree.quit has returned.
		# Freeze this subtree only after save/confirmation succeeded, close audio
		# admission, and keep the engine alive briefly for that release to finish.
		process_mode = Node.PROCESS_MODE_DISABLED
		feedback.shutdown()
		_finish_quit(Time.get_ticks_usec() + int(QUIT_AUDIO_DRAIN_SECONDS * 1000000))

func _finish_quit(deadline_usec: int) -> void:
	if not is_inside_tree() or not quit_dispatched: return
	var remaining := float(deadline_usec - Time.get_ticks_usec()) / 1000000.0
	if remaining > 0:
		# A new timer can consume the current frame's entire delta, including a
		# slow frame before shutdown began. Check wall time before actually exiting.
		get_tree().create_timer(remaining, true, false, true).timeout.connect(_finish_quit.bind(deadline_usec))
	else:
		get_tree().quit()

func _unequip_selected() -> void:
	if not _allows_card_actions() or not session.cards.has(selected): return
	session.equipment.unequip_all(selected)
	_refresh()

func _engage_selected() -> void:
	if not _allows_card_actions() or session.phase != "playing" or not session.cards.has(selected) or session.combat.membership.has(selected): return
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
	if kind == "combat_entered":
		if drag_highlights.enter_combat(): card_drag_targets.clear()
	if running: world_post_process.event(kind, payload)
	if kind == "day_ended":
		journal_slide.day_ended()
		day_clock.hide()
		status.hide()
		stats_box.hide()
		stats_background.hide()
		call_deferred("_refresh")
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
		_capture_combat_motion(payload)
		feedback.play_event(ImpactFeedback.attack_sound(int(payload.combat_type)))
	elif kind == "combat_hit":
		_present_impact(payload)
	elif kind == "combat_return_started":
		_capture_combat_motion(payload)
	elif kind == "encounter":
		notice.text = "Event: " + str(payload.get("message", ""))

func _withdraw_selected() -> void:
	_withdraw_chest(selected)
	_refresh()

func _withdraw_chest(id: int, carried_press: bool = false, click_origin: Variant = null) -> bool:
	if (not _allows_card_actions() and not carried_press) or not session.world.can_click_chest(id):
		notice.text = "Select an unstacked chest to withdraw a coin."
		return false
	var position: Vector2 = session.card_target_position(id) + Vector2(_card_footprint(id).x, 0)
	# Source EnforcePlacementRules(spawnPos, null) returns unchanged, even
	# outside board bounds. The factory queries attachment before placement.
	var withdrew: bool = session.world.withdraw_coin(id, true, position)
	notice.text = "Withdrew a coin." if withdrew else "Chest is empty."
	if withdrew:
		feedback.play_event("Coin")
		if click_origin is Vector2 and session.cards.has(id):
			# Successful OnClick restores the press origin after coin creation,
			# then resolves again. Inspection withdrawal has no pointer origin.
			_set_board_card_position(id, click_origin)
			_resolve_layout()
	return withdrew

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

func _replace_scene_background(scene_name: String) -> void:
	if is_instance_valid(source_background):
		source_background.hide()
		source_background.queue_free()
	source_background = visual_assets.create_scene_background(scene_name)
	if source_background != null:
		add_child(source_background)

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
	if is_instance_valid(flat_board_lighting): flat_board_lighting.clear()
	if original_board != null:
		original_board.hide()
		SourceBoardLifetime.detach_meshes(original_board)
		original_board.queue_free()
	original_board = visual_assets.create_board_mesh(session.scene_name, boost)
	if original_board != null:
		add_child(original_board)
		if is_instance_valid(flat_board_lighting) and source_flat_environment_bound and session.scene_name in ["Main", "Island"]:
			flat_board_lighting.bind(original_board, world_environment)
		board_mesh.hide()
	else:
		board_mesh.show()
		board_mesh.mesh.size = Vector3(bounds.size.x, 0.2, bounds.size.y)
		visual_assets.apply_scene(camera, board_mesh, session.scene_name)
	if old_bounds is Rect2 and bounds.get_area() < old_bounds.get_area():
		_apply_layout(BoardLayout.enforce_board_limits(_layout_states(), [], bounds, session.board_top_margin, int(catalog.settings("CardSettings").get("maxIterations", 8))))
	_clamp_camera()

func _clamp_stack_position(card_id: int, point: Vector2, placement_rules: bool = true) -> Vector2:
	if not session.board_bounds is Rect2 or not session.cards.has(card_id): return point
	var stack = session.stacks.get(session.cards[card_id].stack_id)
	var count: int = 1 if stack == null else stack.card_ids.size() - stack.card_ids.find(card_id)
	var state: Dictionary = BoardLayout.stack_state(-1, point, _card_footprint(card_id), count, false, _stack_step())
	# Held cards can enter the source trade header; ordinary placement cannot.
	return BoardLayout.enforce_placement(point, state, session.board_bounds, session.board_top_margin) if placement_rules else BoardLayout.clamp_to_bounds(point, state, session.board_bounds)

# Original RepositionCard animates to the actual grounded pose cached by ArrangeCards.
# Only a previously observed idle slot is admitted; model geometry alone is not proof.
func _begin_combat_slot_return(id: int, task_id: int, held: Vector3, target: Vector3) -> void:
	var card = session.cards[id]
	var slot: Variant = combat_layouts[task_id].positions.get(id)
	if not slot is Vector2 or target != Vector3(slot.x,0,-slot.y): return
	_combat_slot_returns[id] = {"card":card.get_instance_id(),"view":views[id].get_instance_id(),"task":task_id,"target":target,"layout":combat_layouts[task_id].duplicate(true)}
	if not _combat_slot_return_current(id):
		_combat_slot_returns.erase(id)
		return
	card_motion.states[id] = {"identity":"%d:%s" % [card.get_instance_id(),card.definition_guid],"position":held,"target":held,"mode":"instant","elapsed":0.0}
	card_motion.set_target_animated(id,target)

func _combat_slot_return_current(id: int) -> bool:
	if not _combat_slot_returns.has(id) or not session.cards.has(id): return false
	var owner: Dictionary = _combat_slot_returns[id]
	if global_transform != Transform3D.IDENTITY or session.combat.membership.get(id,-1) != owner.task: return false
	if not session.combat.tasks.has(owner.task) or not combat_layouts.has(owner.task): return false
	if not session.combat.tasks[owner.task].get("execution",{}).is_empty() or combat_layouts[owner.task] != owner.layout: return false
	if session.cards[id].get_instance_id() != owner.card or session.cards[id].stack_id != -1: return false
	if _card_drag_for(id) != null or session.combat.dragged.has(id) or session.equipment.owners.has(id): return false
	if int(session.cycle.presentation_state().get("card_id",-1)) == id or combat_presentation.sample_actor(id) != null: return false
	return views.has(id) and is_instance_valid(views[id]) and not views[id].is_queued_for_deletion() and views[id].get_instance_id() == owner.view and views[id].get_parent() == self

# CardController terminal Flee registers the held singleton, then calls
# SetTargetPosition -> SetTargetAnimated. EnforcePlacementRules flattens Y=0.
# This owner is intentionally not generalized to overlap, survivors or stacks.
func _begin_terminal_landing(id: int, held: Vector3, point: Vector2) -> void:
	if not session.cards.has(id) or not views.has(id): return
	var card = session.cards[id]
	if not session.stacks.has(card.stack_id): return
	var stack = session.stacks[card.stack_id]
	var target := Vector3(point.x, 0, -point.y)
	_terminal_landings[id] = {"card":card.get_instance_id(), "view":views[id].get_instance_id(), "stack":stack.get_instance_id(), "target":target, "point":point}
	if not _terminal_landing_current(id):
		_terminal_landings.erase(id)
		return
	var identity := "%d:%s" % [card.get_instance_id(),card.definition_guid]
	card_motion.states[id] = {"identity":identity,"position":held,"target":held,"mode":"instant","elapsed":0.0}
	card_motion.set_target_animated(id,target)
	views[id].position = held

func _terminal_landing_current(id: int) -> bool:
	if not _terminal_landings.has(id) or not session.cards.has(id): return false
	var owner: Dictionary = _terminal_landings[id]
	var card = session.cards[id]
	if card.get_instance_id() != owner.card or not session.stacks.has(card.stack_id): return false
	var stack = session.stacks[card.stack_id]
	if stack.get_instance_id() != owner.stack or stack.card_ids != [id] or stack.position != owner.point: return false
	if not views.has(id) or not is_instance_valid(views[id]) or views[id].is_queued_for_deletion(): return false
	if views[id].get_instance_id() != owner.view or views[id].get_parent() != self or global_transform != Transform3D.IDENTITY: return false
	if _card_drag_for(id) != null or session.combat.dragged.has(id) or session.combat.membership.has(id) or session.equipment.owners.has(id): return false
	if int(session.cycle.presentation_state().get("card_id",-1)) == id or combat_presentation.sample_actor(id) != null: return false
	return true

# Correct live XZ only where the ordinary source/display height mapping is known.
# Ordinary roots add +0.06; drag/damped/combat owners do not share that contract.
# Vertical transitions return no sample and retain explicit settled-model fallback.
# Do not advance CardMotion here; the owner synchronizes it later in this frame.
func _sample_ai_actor_pose(id: int) -> Variant:
	if not views.has(id) or not is_instance_valid(views[id]) or views[id].is_queued_for_deletion(): return null
	if not card_motion.states.has(id): return null
	var state: Dictionary = card_motion.states[id]
	if state.get("mode", "") not in ["animated", "instant"]: return null
	if session.combat.membership.has(id) or session.equipment.owners.has(id) or session.combat.dragged.has(id): return null
	var source_height: float = session.card_target_position_3d(id).y
	var display_height: float = (Vector3(0, 0.06, 0) + Vector3(0, source_height, 0)).y
	var point: Vector3 = views[id].global_position
	# Exact same stable target height: horizontal tween progress is permitted,
	# but no inference about moving Y or a higher-priority owner is made.
	if state.target.y != display_height or state.position.y != display_height or point.y != display_height: return null
	return Vector3(point.x, source_height, -point.z)

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
	return running and session.phase in ["playing", "selling"] and not vendor_unlock.is_active() and not scene_transition.blocks_input()

func _clamp_camera() -> void:
	if session.board_bounds is Rect2: camera_motion.set_bounds(session.board_bounds)

func _observe_camera_scroll(event: InputEvent, during_fade: bool) -> void:
	if not event is InputEventMouseButton or not event.pressed or event.device<0: return
	# Read the same normalized physical wheel detent as the UI, but only Y;
	# ScrollRect's sensitivity and X/Y arbitration belong to its own receiver.
	var dy: float = JournalPointerInput.wheel_ticks(event).y
	if dy==0.0: return
	var owner := session.get_instance_id()
	var generation: int = scene_transition.generation
	if _camera_scroll_owner!=owner or _camera_scroll_generation!=generation or _camera_scroll_during_fade!=during_fade:
		_camera_scroll_sample=0.0
		_camera_scroll_owner=owner
		_camera_scroll_generation=generation
		_camera_scroll_during_fade=during_fade
	_camera_scroll_sample+=dy

func _flush_camera_scroll(input_enabled: bool, outbound_enabled: bool) -> void:
	var scroll := _camera_scroll_sample
	var owner := _camera_scroll_owner
	var generation := _camera_scroll_generation
	var during_fade := _camera_scroll_during_fade
	_camera_scroll_sample=0.0
	_camera_scroll_owner=0
	if owner!=session.get_instance_id() or generation!=scene_transition.generation or not is_finite(scroll): return
	if (during_fade and outbound_enabled) or (not during_fade and input_enabled):
		camera_motion.zoom(scroll, -camera.global_basis.z)

func _focus_camera(target: Vector2, duration: float = 0.5) -> void:
	_focus_camera_position(Vector3(target.x,0,target.y), duration)

func _focus_camera_position(source_position: Vector3, duration: float = 0.5) -> void:
	panning = false
	camera_drag_origin = camera_pointer.position
	camera_motion.move_to(camera.position, Vector3(source_position.x,source_position.y,-source_position.z), -camera.global_basis.z, duration)

# The source camera's PhysicsRaycaster includes trade zone colliders, even
# before the vendor starts accepting payment. Hover text or transaction
# eligibility is not the pointer-blocking test.
func _camera_left_blocked() -> bool:
	var screen: Vector2 = get_viewport().get_final_transform().affine_inverse() * camera_pointer.position
	if _hud_blocks_panel_click(hud,screen): return true
	var hit := _pick_target(screen)
	return int(hit.get("card_id",-1))>=0 or int(hit.get("panel_owner",-1))>=0 or int(hit.get("trade_zone_index",-1))>=0

func _update_camera_motion(delta: float) -> void:
	_clamp_camera()
	var enabled: bool = _camera_input_enabled()
	var outbound: bool = _source_outbound_camera_allowed()
	var edges: Dictionary = camera_pointer.take_pan_edges()
	if _outbound_camera_owner != 0 and (_outbound_camera_owner != session.get_instance_id() \
			or _outbound_camera_generation != scene_transition.generation or scene_transition.phase != "out"):
		_clear_outbound_camera()
		panning = false
		# An invalidated outgoing frame isn't a new-scene press.
		edges = {"left_pressed":false,"middle_pressed":false,"released":false}
	# InputManager skips HandlePan in a locked update: discard that update's
	# edge bits but retain drag/origin and the shared pointer's last position.
	if enabled or outbound:
		# The fader is a full-screen raycast target, not a drag cancellation.
		# Start (left gated, middle unconditional), then either release.
		if (edges.left_pressed and not outbound and not _camera_left_blocked()) or edges.middle_pressed:
			panning = true
			camera_drag_origin = camera_pointer.position
		if edges.released: panning = false
		# All motion this frame resolves to one final physical sample and
		# one clamp. A start+motion frame has zero displacement; a release
		# frame cannot move even when motion arrived before the release.
		if panning and camera_pointer.known:
			camera_motion.pan(camera_pointer.position - camera_drag_origin,camera.position.y)
			camera_drag_origin = camera_pointer.position
	# CameraController.Update: final pan sample, one signed vertical sum,
	# then unscaled SmoothDamp. Reject an oversize step rather than applying
	# valid intermediate wheel events against a moving/clamped target.
	_flush_camera_scroll(enabled, outbound)
	camera.position = camera_motion.step(camera.position, delta, enabled or outbound)

func _layout_states() -> Array:
	var result: Array = []
	for stack in session.stacks.values():
		if stack.card_ids.is_empty(): continue
		var locked: bool = layout_locks.has(stack.id) or _drag_locks_stack(stack.id)
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
	# A pickup split is not a placement: keep the original in reach until drop.
	if session.drag.active(): return
	if session.catalog != null and _layout_signature() != layout_key:
		_resolve_layout()

func _nearby_stack(card_id: int, point: Vector3, radius: float, ignored: int = -1, equipment_drop: bool = false, held_root: int = -1) -> int:
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
			var eligible: bool = session.can_move_to_stack(card_id, stack.id, session.drag.original_stack_id_for(held_root if held_root >= 0 else card_id,card_id))
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
		_sync_combat_task_layout(id, config)

func _sync_combat_task_layout(id: int, config: Dictionary) -> void:
	var task: Dictionary = session.combat.tasks[id]
	var attackers: Array = _fighter_records(task.attackers)
	var defenders: Array = _fighter_records(task.defenders)
	var previous: Dictionary = task.get("layout", {})
	if not previous.is_empty(): previous["config"] = config
	var state: Dictionary = CombatLayout.initialize(attackers, defenders, config, session.board_bounds, session.board_top_margin, task.get("initial_center")) if previous.is_empty() else CombatLayout.update_layout(previous, attackers, defenders)
	if state.is_empty(): return
	task.erase("initial_center") # Never overwrite an existing/saved layout center.
	task["layout"] = state
	combat_layouts[id] = state
	for card_id in state.positions: session.cards[card_id].position = state.positions[card_id]
	_draw_combat_rectangle(id, state)

func _draw_combat_rectangle(id: int, state: Dictionary) -> void:
	var rectangle: MeshInstance3D = combat_rectangles.get(id)
	if rectangle == null:
		rectangle = SourceCombatRectangle.bind(visual_assets,visual_assets.scene_configuration(session.scene_name))
		if rectangle == null: return # Nothing synthetic replaces a missing licensed visual.
		add_child(rectangle)
		combat_rectangles[id] = rectangle
	if not SourceCombatRectangle.update(rectangle,state):
		combat_rectangles.erase(id)
		rectangle.hide()
		rectangle.queue_free()

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

func _departure_checkpoint(checkpoint_campaign = null) -> Dictionary:
	_first_departure_save_owner = checkpoint_campaign
	var result: Dictionary = _checkpoint("Travel departure")
	_first_departure_save_owner = null
	return result

# CombatRect.Initialize averages live transforms before EnterCombat. Admit only
# complete ordinary grounded observations, never a mixed live/target center.
func _combat_start_center(attackers: Array, defenders: Array) -> Variant:
	var ids: Array = attackers + defenders
	if attackers.is_empty() or defenders.is_empty(): return null
	var center := Vector2.ZERO
	for id in ids:
		var pose: Variant = _sample_ai_actor_pose(id)
		if not pose is Vector3 or not pose.is_finite() or pose.y != 0.0: return null
		center += Vector2(pose.x, pose.z)
	return center / ids.size()

# Standalone singleton entrants, optionally with separated ordinary stacks.
# Both original ResolveOverlaps passes must attempt no separation. Check source
# target-position bounds, not live transforms or equal final clamped positions.
# Crowded/partial/merge/restore paths retain their prior adapter.
func _combat_start_layout(attackers: Array, defenders: Array, center: Variant) -> Dictionary:
	var ids: Array = attackers + defenders
	if global_transform != Transform3D.IDENTITY or not center is Vector2 or not center.is_finite(): return {}
	if not session.combat.tasks.is_empty() or not combat_layouts.is_empty() or not layout_locks.is_empty(): return {}
	if session.drag.active() or _has_card_drag(): return {}
	var fresh_center := Vector2.ZERO
	for id in ids:
		if not session.cards.has(id) or int(session.cycle.presentation_state().get("card_id", -1)) == id: return {}
		var card = session.cards[id]
		var stack = session.stacks.get(card.stack_id)
		if stack == null or stack.card_ids != [id] or session.equipment.owners.has(id): return {}
		var pose: Variant = _sample_ai_actor_pose(id)
		if not pose is Vector3 or not pose.is_finite() or pose.y != 0.0: return {}
		if views[id].get_parent() != self or views[id].get_meta("definition_guid", "") != card.definition_guid: return {}
		if not session.card_target_position_3d(id).is_finite(): return {}
		if card_motion.states[id].get("identity", "") != "%d:%s" % [card.get_instance_id(),card.definition_guid]: return {}
		fresh_center += Vector2(pose.x, pose.z)
	if ids.is_empty() or not (fresh_center / ids.size()).is_equal_approx(center): return {}
	var config: Dictionary = CombatLayout.imported_config(catalog.data, session.scene_name)
	if not config.get("ok", false) or not session.board_bounds is Rect2: return {}
	var layout: Dictionary = CombatLayout.initialize(_fighter_records(attackers), _fighter_records(defenders), config, session.board_bounds, session.board_top_margin, center)
	if layout.is_empty(): return {}
	for point in layout.positions.values():
		if not point.is_finite(): return {}
	var stacks: Array = _layout_states()
	for i in stacks.size():
		if stacks[i].locked: return {}
		for j in range(i + 1, stacks.size()):
			if BoardLayout.separation(BoardLayout.stack_bounds(stacks[i]), BoardLayout.stack_bounds(stacks[j])) != Vector2.ZERO: return {}
		# EnterCombat removes the whole singleton participating stack. Remaining
		# stacks must also have no separation against the newly registered rect.
		if session.stacks[stacks[i].id].card_ids[0] not in ids:
			if BoardLayout.separation(BoardLayout.stack_bounds(stacks[i]), layout.bounds) != Vector2.ZERO: return {}
	# Validate the whole cohort before changing even its first native transform.
	for id in ids:
		var point: Vector2 = layout.positions[id]
		views[id].position = Vector3(point.x, 0, -point.y)
		card_motion.states.erase(id)
	return layout

# Called after CleanUpForMerge removed old tasks/membership, before replacement
# entry/progress draws. A blocked old fighter is not an ordinary raised card.
func _combat_merge_center(attackers: Array, defenders: Array, old_members: Dictionary) -> Variant:
	if attackers.is_empty() or defenders.is_empty() or global_transform != Transform3D.IDENTITY: return null
	var ids: Array = attackers + defenders
	var resized: Dictionary = _consume_ranged_resize_receipt(ids, old_members)
	var center := Vector2.ZERO
	for id in ids:
		var pose: Variant
		if int(session.cycle.presentation_state().get("card_id", -1)) == id: return null
		if old_members.has(id):
			if (not old_members[id] and not resized.has(id)) or _card_drag_for(id) != null or session.equipment.owners.has(id): return null
			if not views.has(id) or not is_instance_valid(views[id]) or views[id].is_queued_for_deletion(): return null
			var card = session.cards[id]
			if views[id].get_meta("definition_guid", "") != card.definition_guid: return null
			if card_motion.states.has(id):
				var motion: Dictionary = card_motion.states[id]
				if motion.get("mode", "") != "blocked" or motion.get("identity", "") != "%d:%s" % [card.get_instance_id(),card.definition_guid]: return null
			var laid_out := false
			for layout in combat_layouts.values():
				if id in layout.attackers or id in layout.defenders:
					laid_out = true
					break
			if not laid_out: return null
			# Even a ground endpoint can still belong to an in-flight/pending tween.
			if combat_presentation.sample_actor(id) != null: return null
			# Source resize arranges instantly. Do not read a stale rendered pose
			# before this Board has synchronized the updated model slot.
			var slot: Vector2 = session.card_target_position(id)
			if views[id].position != Vector3(slot.x, 0, -slot.y): return null
			var point: Vector3 = views[id].global_position
			if not point.is_finite() or point.y != 0.0: return null
			pose = Vector3(point.x, 0, -point.z)
		else:
			pose = _sample_ai_actor_pose(id)
		if not pose is Vector3 or not pose.is_finite() or pose.y != 0.0: return null
		center += Vector2(pose.x, pose.z)
	return center / ids.size()

# Receipt is valid only inside the exact synchronous AddCombatants selector/merge
# call. The source task reference survives cleanup solely to validate no callback
# changed its phase or membership after the native grounded write.
func _consume_ranged_resize_receipt(ids: Array, old_members: Dictionary) -> Dictionary:
	var receipt: Dictionary = _ranged_resize_receipt
	_ranged_resize_receipt = {}
	if receipt.is_empty() or receipt.context != session.combat.resize_geometry_context(): return {}
	var source: Dictionary = receipt.task
	if source != receipt.snapshot or session.combat.tasks.has(receipt.context.task_id): return {}
	var source_ids: Array = source.attackers + source.defenders
	if source_ids != receipt.ids: return {}
	for id in source_ids:
		if id not in ids or not old_members.has(id) or old_members[id]: return {}
		if not session.cards.has(id) or session.combat.membership.has(id): return {}
		if not views.has(id) or not is_instance_valid(views[id]) or views[id].is_queued_for_deletion(): return {}
		if views[id].get_parent() != self or views[id].get_instance_id() != receipt.views[id]: return {}
		if session.cards[id].get_instance_id() != receipt.cards[id]: return {}
		if views[id].position != receipt.positions[id]: return {}
	return receipt.positions

func _combat_start_overlaps(attackers: Array, defenders: Array) -> Array:
	_sync_combat_layouts()
	var attacking: Array = CombatMergeGeometry.current_ground_records(_fighter_records(attackers), _sample_ai_actor_pose)
	var defending: Array = CombatMergeGeometry.current_ground_records(_fighter_records(defenders), _sample_ai_actor_pose)
	return CombatMergeGeometry.before_start(attacking, defending, combat_layouts)

# AddCombatants calls Rect.UpdateLayout (instant grounded transforms) before
# CheckAndMergeCombats. Ranged travel/return has no card combat tween: its
# projectile owns an independent captured world endpoint and clock. Only reset
# complete observed card slots; never alter execution or presentation records.
# Melee, death-wait, unknown actions and drag retain the conservative fallback.
func _combat_resize_native_slots(task_id: int, validate_only: bool = false) -> bool:
	if global_transform != Transform3D.IDENTITY or not session.combat.tasks.has(task_id): return false
	var task: Dictionary = session.combat.tasks[task_id]
	if not combat_layouts.has(task_id): return false
	var execution: Dictionary = task.get("execution", {})
	if not execution.is_empty():
		if execution.get("combat_type", -1) not in [2, 3] or execution.get("phase", "") not in ["travel", "return"]: return false
		var members: Array = task.attackers + task.defenders
		if execution.get("actor", -1) not in members or execution.get("target", -1) not in members: return false
		if (execution.actor in task.attackers) == (execution.target in task.attackers): return false
		var remaining: Variant = execution.get("remaining")
		if not (remaining is float or remaining is int) or not is_finite(float(remaining)) or float(remaining) < 0: return false
	var positions: Dictionary = combat_layouts[task_id].positions
	var ids: Array = task.attackers + task.defenders
	if ids.is_empty(): return false
	for id in ids:
		if not session.cards.has(id) or not positions.has(id): return false
		if session.combat.membership.get(id, -1) != task_id or session.combat.dragged.has(id): return false
		if _card_drag_for(id) != null or session.equipment.owners.has(id) or int(session.cycle.presentation_state().get("card_id", -1)) == id: return false
		if not views.has(id) or not is_instance_valid(views[id]) or views[id].is_queued_for_deletion(): return false
		if views[id].get_parent() != self: return false
		var card = session.cards[id]
		if views[id].get_meta("definition_guid", "") != card.definition_guid: return false
		if combat_presentation.sample_actor(id) != null: return false
		if card_motion.states.has(id) and card_motion.states[id].get("identity", "") != "%d:%s" % [card.get_instance_id(), card.definition_guid]: return false
		if not positions[id] is Vector2 or not positions[id].is_finite(): return false
	if validate_only: return true
	# The source instant setter cancels ordinary movement before setting position.
	# Observe only after writing the native nodes, never relabel model slots as poses.
	for id in ids:
		var slot: Vector2 = positions[id]
		_combat_slot_returns.erase(id)
		card_motion.states.erase(id)
		views[id].position = Vector3(slot.x, 0.0, -slot.y)
	return true

# Flee removes membership and calls Rect.UpdateLayout, not CheckAndMergeCombats.
# Reuse atomic native slot guards, but issue neither merge selection nor receipt.
func _combat_flee_layout(task_id: int) -> void:
	if not session.combat.tasks.has(task_id): return
	var config: Dictionary = CombatLayout.imported_config(catalog.data, session.scene_name)
	if not config.get("ok", false): return
	_sync_combat_task_layout(task_id, config)
	_combat_resize_native_slots(task_id)

# Last-attacker idle Flee only. Observe the real post-UpdateLayout native nodes;
# do not substitute pre-update model positions for original transform.position.
func _combat_terminal_flee_layout(task_id: int) -> Dictionary:
	if global_transform != Transform3D.IDENTITY: return {}
	if catalog.data.get("provenance", {}).get("source_commit") != SourceColdCrafting.SOURCE_COMMIT or session.scene_name not in ["Main", "Island"]: return {}
	if not session.combat.tasks.has(task_id) or not combat_layouts.has(task_id): return {}
	var task: Dictionary = session.combat.tasks[task_id]
	if not task.attackers.is_empty() or task.defenders.is_empty() or not task.get("execution", {}).is_empty(): return {}
	var config: Dictionary = CombatLayout.imported_config(catalog.data, session.scene_name)
	if not config.get("ok", false): return {}
	# Preflight the same atomic native guards before changing model layout.
	if not _combat_resize_native_slots(task_id, true): return {}
	_sync_combat_task_layout(task_id, config)
	if not _combat_resize_native_slots(task_id): return {}
	var positions: Dictionary = {}
	var targets: Dictionary = {}
	for id in task.defenders:
		var pose: Vector3 = views[id].global_position
		var point := Vector2(pose.x, -pose.z)
		positions[id] = point
		targets[id] = BoardLayout.enforce_placement(point, BoardLayout.stack_state(id, point, _card_footprint(id), 1), session.board_bounds, session.board_top_margin)
	_terminal_landing_receipt = task_id
	return {"ok": true, "ids": task.defenders.duplicate(), "positions": positions, "targets": targets}

func _combat_resize_overlaps(task_id: int) -> Array:
	_ranged_resize_receipt = {}
	_sync_combat_layouts()
	var applied: bool = _combat_resize_native_slots(task_id)
	var context: Dictionary = session.combat.resize_geometry_context()
	if applied and context.get("task_id", -1) == task_id:
		var task: Dictionary = session.combat.tasks[task_id]
		if not task.get("execution", {}).is_empty():
			var ids: Array = task.attackers + task.defenders
			var receipt := {"context":context,"task":task,"snapshot":task.duplicate(true),
				"ids":ids.duplicate(),"views":{},"cards":{},"positions":{}}
			for id in ids:
				receipt.views[id] = views[id].get_instance_id()
				receipt.cards[id] = session.cards[id].get_instance_id()
				receipt.positions[id] = views[id].position
			_ranged_resize_receipt = receipt
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
			view.bind_source(visual_assets, catalog)
			add_child(view)
			trade_views[index] = view
		trade_views[index].configure(zone, _pack_tracker(str(zone.pack_guid)))
	for index in trade_views.keys():
		if not present.has(index):
			trade_views[index].queue_free()
			trade_views.erase(index)
	vendor_unlock.update_zones(trade_zones)
	if not result.errors.is_empty(): notice.text = "Trade geometry unavailable: " + "; ".join(result.errors)

func _try_trade_drop(card_id: int, destination: Vector2, carried_press: bool = false) -> Dictionary:
	var outcome := {"terminal": false, "accepted": false, "card_id": card_id}
	if (not _allows_card_actions() and not carried_press) or not session.cards.has(card_id): return outcome
	_sync_trade_zones()
	# Source trades before grounding the held root. _finish_drag has already
	# cleared dragging, so use the same scene-bound height as its instant view.
	var height := float(CardDragInput.source_settings(catalog, session.scene_name).get("dragHeight", 0.1))
	var zone: Dictionary = TradeLayout.nearest_zone(trade_zones, Vector3(destination.x, height, destination.y), float(catalog.settings("CardSettings").get("attachRadius", 0.25)))
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
	# Pickup already registered the held tail. Preserve that identity and craft.
	var stack_id: int = source.id
	if source.card_ids.front() != card_id: stack_id = session.split_stack(card_id, destination)
	_set_board_card_position(card_id, destination)
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
	pause_controls = [
		_button("Continue [Escape]", box, _continue_pause_menu, true),
		_button("Options", box, _open_options, true),
		_button("Save & return to title", box, _request_return_title, true),
	]
	pause_overlay.hide()
	options_panel = OptionsPanel.new()
	options_panel.play_click = _play_ui_click
	layer.add_child(options_panel)
	options_panel.visibility_changed.connect(func():
		_source_options_owner_cache.clear()
		if not options_panel.visible:
			_source_options_open_owner.clear()
			_title_options_open_owner.clear())

func _ordinary_source_pause_icon() -> bool:
	return source_pause_configured and running and session.phase == "playing" and pause_overlay.visible and not options_panel.visible and not scene_transition.active() and not _navigation_modal_active() and not quit_dispatched and (recovery_window == null or not recovery_window.visible)

func _ui_pause_active() -> bool:
	return scene_transition.blocks_input() or (running and ((pause_overlay != null and pause_overlay.visible) or (options_panel != null and options_panel.visible)))

## The source Options sibling owns input, not a TimeManager pause lock.
## Only admit the exact linked records and mounted ordinary gameplay panels.
var _source_options_owner_cache: Dictionary = {}
var _source_options_open_owner: Dictionary = {}
func _source_options_pause_owner() -> bool:
	if scene_transition.active() or not running or options_panel == null or not options_panel.visible:
		_source_options_open_owner.clear()
	if _source_options_open_owner.is_empty(): return false
	if _source_options_open_owner.session != session or _source_options_open_owner.scene != session.scene_name or _source_options_open_owner.view != options_panel.source_view or not is_same(_source_options_open_owner.data, catalog.data):
		_source_options_open_owner.clear()
		_source_options_owner_cache.clear()
		return false
	var eligible: bool = running and session != null and session.catalog == catalog and session.scene_name in ["Main", "Island"] and source_pause_configured and options_panel != null and options_panel.visible
	eligible = eligible and not scene_transition.active() and not quit_dispatched and not _navigation_modal_active() and (recovery_window == null or not recovery_window.visible)
	if not eligible:
		_source_options_owner_cache.clear()
		return false
	if catalog.data.get("provenance", {}).get("source_commit") != SourceColdCrafting.SOURCE_COMMIT or not is_instance_valid(options_panel.source_view) or not options_panel.source_view.source_backed or options_panel.source_view.layout.root_id != "637356262954503982" or not options_panel.source_view.is_visible_in_tree():
		_source_options_owner_cache.clear()
		return false
	# Imported catalog records are immutable until configure/replacement. Cache
	# only this opening's actual session/scene/catalog/overlay identities.
	if not _source_options_owner_cache.is_empty() and _source_options_owner_cache.session == session and _source_options_owner_cache.scene == session.scene_name and _source_options_owner_cache.catalog == catalog and is_same(_source_options_owner_cache.data, catalog.data) and _source_options_owner_cache.view == options_panel.source_view:
		return _source_options_owner_cache.admitted
	var mounted_pause := false
	for child in pause_overlay.get_children():
		if child.get_script() == preload("res://scripts/ui/source_panel_view.gd") and child.source_backed and child.layout.root_id == "8532370488951995501": mounted_pause = true
	if not mounted_pause or not preload("res://scripts/ui/day_clock.gd").resolve(catalog.data, session.scene_name).source_backed: return false
	var pause_record: Dictionary = {}
	var options_link: Dictionary = {}
	var options_record: Dictionary = {}
	for prefab in catalog.data.get("referenced_prefabs", []):
		if prefab.get("guid", "") == "5e2985d7789c5254b831d166e6931134":
			for doc in prefab.get("documents", []):
				if str(doc.get("file_id", "")) == "8547574447435325085" and doc.get("script_class", "") == "PauseMenu": pause_record = doc.get("fields", {})
				if str(doc.get("file_id", "")) == "9020853386068679053" and doc.get("script_class", "") == "GameOptionsUI": options_link = doc.get("fields", {})
		if prefab.get("guid", "") == "386f59785c880f546bf078b8023091a8":
			for doc in prefab.get("documents", []):
				if str(doc.get("file_id", "")) == "98810512149128886" and doc.get("script_class", "") == "GameOptionsUI": options_record = doc.get("fields", {})
	var admitted: bool = pause_record.get("m_Script", {}).get("guid", "") == "c9da4713f45d2a3408a718a9d946f117" and options_record.get("m_Script", {}).get("guid", "") == "14a040b8aaafd8342878bfa503b99721" and pause_record.get("m_Enabled", 0) == 1 and str(pause_record.get("gameOptionsUI", {}).get("fileID", "")) == "9020853386068679053" and options_link.get("m_Enabled", 0) == 1 and options_link.get("m_CorrespondingSourceObject", {}).get("guid", "") == "386f59785c880f546bf078b8023091a8" and str(options_link.get("m_CorrespondingSourceObject", {}).get("fileID", "")) == "98810512149128886" and options_record.get("m_Enabled", 0) == 1 and str(options_record.get("closeButton", {}).get("fileID", "")) == "3374842419896805458"

	_source_options_owner_cache = {"session": session, "scene": session.scene_name, "catalog": catalog, "data": catalog.data, "view": options_panel.source_view, "admitted": admitted}
	return admitted

func _temporal_ui_pause_active() -> bool:
	if _source_options_pause_owner(): return pause_overlay.visible
	return _ui_pause_active()

func _source_options_cancel() -> bool:
	if not _source_options_pause_owner(): return false
	# PauseMenu.Update ignores raw Cancel during IsEndingCycle. Options stays.
	if session.phase == "playing":
		pause_overlay.visible = not pause_overlay.visible
		_refresh()
	return true

## Source ContinueButton invokes ToggleActiveState directly, independently of
## PauseMenu.Update's IsEndingCycle Cancel gate. Close only this existing owner.
func _continue_pause_menu() -> void:
	if not running or not pause_overlay.visible or scene_transition.blocks_input() or options_panel.visible: return
	pause_overlay.hide()
	_refresh()
	MenuFocus.restore(pause_restore_focus, day_clock)
	pause_restore_focus = null

func _toggle_pause_menu() -> void:
	if scene_transition.blocks_input(): return
	if not running or session.phase != "playing" or options_panel.visible: return
	var opening: bool = not pause_overlay.visible
	if opening:
		var previous := get_viewport().gui_get_focus_owner()
		pause_restore_focus = weakref(previous) if previous != null else null
	pause_overlay.visible = opening
	# External pause changes time, not an already captured pointer.
	_refresh()
	if opening:
		MenuFocus.loop(pause_controls)
		pause_controls[0].grab_focus()
	else:
		MenuFocus.restore(pause_restore_focus, day_clock)
		pause_restore_focus = null

var _title_options_open_owner: Dictionary = {}
func _source_title_options_cancel() -> bool:
	if _title_options_open_owner.is_empty(): return false
	if running or scene_transition.active() or options_panel == null or not options_panel.visible or title_navigation.destination != TitleNavigation.HOME:
		_title_options_open_owner.clear()
		return false
	if not is_same(_title_options_open_owner.data, catalog.data) or _title_options_open_owner.title != source_title or _title_options_open_owner.view != options_panel.source_view:
		_title_options_open_owner.clear()
		return false
	if quit_dispatched or _navigation_modal_active() or (recovery_window != null and recovery_window.visible): return false
	return is_instance_valid(source_title) and source_title.source_backed and source_title.is_visible_in_tree() and is_instance_valid(options_panel.source_view) and options_panel.source_view.source_backed and options_panel.source_view.is_visible_in_tree()

func _admit_title_options_open() -> void:
	_title_options_open_owner.clear()
	if running or options_panel.visible or title_navigation.destination != TitleNavigation.HOME or scene_transition.active() or quit_dispatched or _navigation_modal_active(): return
	if recovery_window != null and recovery_window.visible: return
	if not is_instance_valid(source_title) or not source_title.source_backed or not source_title.is_visible_in_tree(): return
	if not is_instance_valid(options_panel.source_view) or not options_panel.source_view.source_backed or options_panel.source_view.layout.root_id != "637356262954503982": return
	var button_host = source_title.nodes.get(source_title.layout.resolve("MenuPanel/GameOptions"))
	if button_host == null or title_options_button.get_parent() != button_host: return
	if not preload("res://scripts/ui/source_title_options_contract.gd").admits(catalog.data): return
	_title_options_open_owner = {"data": catalog.data, "title": source_title, "view": options_panel.source_view}

func _open_options() -> void:
	if scene_transition.blocks_input(): return
	if quit_dispatched or _navigation_modal_active(): return
	if running:
		if session.phase != "playing" and not pause_overlay.visible: return
		if not pause_overlay.visible: _toggle_pause_menu()
	_source_options_owner_cache.clear()
	_source_options_open_owner.clear()
	if running and session.phase == "playing" and pause_overlay.visible and not scene_transition.active() and not options_panel.visible:
		_source_options_open_owner = {"session": session, "scene": session.scene_name, "view": options_panel.source_view, "data": catalog.data}
	_admit_title_options_open()
	options_panel.open()
	if running: _refresh()

func _handle_escape() -> void:
	if _source_title_overlay_cancel(): return
	if _source_title_options_cancel(): return
	if _source_options_cancel(): return
	if scene_transition.blocks_input(): return
	if _navigation_modal_active(): return
	# Source PauseMenu never changes external pause during IsEndingCycle.
	if running and session.phase != "playing": return
	if options_panel.visible:
		options_panel.request_close()
	elif recovery_window != null and recovery_window.visible:
		_close_recovery()
	elif running:
		_toggle_pause_menu()
	else:
		_title_back()

func _sample_combat_pose(id: int) -> Vector3:
	# Sample same-frame tween time, not the previous rendered transform.
	var animated: Variant = combat_presentation.sample_actor(id)
	if animated is Vector3: return animated
	if views.has(id) and is_instance_valid(views[id]): return views[id].global_position
	return _sample_combat_home(id)

func _sample_combat_home(id: int) -> Vector3:
	# Rect.ArrangeRow forces ground Y=0 and caches that layout position.
	var point: Vector2 = session.card_target_position(id)
	return to_global(Vector3(point.x, 0, -point.y))

func _capture_combat_motion(payload: Dictionary) -> void:
	var id: int = int(payload.combat_id)
	if not session.combat.tasks.has(id): return
	var task: Dictionary = session.combat.tasks[id]
	if not task.has("execution"): return
	task["visual_motion"] = combat_presentation.capture(id, task.execution, _sample_combat_pose, _sample_combat_home, float(payload.duration))

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
	if views.has(defender) and is_instance_valid(views[defender]):
		var local_offset: Vector3 = descriptor.popup.defender_local_offset
		var sampled_transform: Transform3D = views[defender].global_transform
		sampled_transform.origin = _sample_combat_pose(defender)
		popup.global_position = sampled_transform * Vector3(local_offset.x, local_offset.y, -local_offset.z)

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

func _request_archive_selected() -> void:
	if running: return
	_request_archive_slots([selected_slot] if selected_slot > 0 else [])

func _request_archive_all() -> void:
	if running: return
	_request_archive_slots(listed_slot_ids.duplicate())

func _request_archive_slots(ids: Array) -> void:
	if running: return
	pending_archive_plan.clear()
	slots.configure(session.campaign, slot_root)
	var result: Dictionary = slots.prepare_delete_slots(ids)
	if not result.ok:
		title_status.text = "Cannot prepare archive: " + str(result.get("error", "Choose at least one listed slot."))
		return
	pending_archive_plan = result.plan.duplicate(true)
	var names: PackedStringArray = []
	for id in pending_archive_plan.slots: names.append(str(id))
	archive_dialog.dialog_text = "Archive %d listed slot(s): %s?\n\nIncludes their primary saves, backups and temporary files, including invalid or temp-only listed slots.\n\nOptions, legacy saves and existing archives are excluded. Nothing is permanently deleted. Newly created unlisted slots are not included." % [names.size(), ", ".join(names)]
	archive_dialog.popup_centered(Vector2i(640,300))

func _cancel_archive_slots() -> void:
	pending_archive_plan.clear()

func _confirm_archive_slots() -> void:
	if running:
		_cancel_archive_slots()
		return
	if pending_archive_plan.is_empty():
		title_status.text = "No pending archive confirmation. Choose the slots again."
		return
	var plan: Dictionary = pending_archive_plan.duplicate(true)
	pending_archive_plan.clear() # Consume authorization once, including failure.
	slots.configure(session.campaign, slot_root)
	var result: Dictionary = slots.delete_slots(plan)
	archive_dialog.hide()
	_refresh_slots()
	if source_saved_rows != null and title_saves.is_visible_in_tree() and (recovery_window == null or not recovery_window.visible):
		var focused := get_viewport().gui_get_focus_owner()
		if focused == null or not MenuFocus.eligible(focused): title_back_button.grab_focus()
	if not result.ok:
		title_status.text = "Archive failed: " + str(result.get("error", "Unknown error")) + ". Review the current files and confirm a new plan to retry."
		if result.has("archive"):
			title_status.text += " Recovery archive: " + str(result.archive) + "."
		if not result.get("rollback_errors", []).is_empty():
			title_status.text += " %d artifact(s) could not be returned; inspect both slots and archive inventory." % result.rollback_errors.size()
		return
	title_status.text = "Archived %d slot(s) into a recoverable local archive. Options and legacy saves were kept. Use Restore copy below to recover a save." % result.slots.size()

func _refresh_archives() -> void:
	var previous: Dictionary = {}
	if archive_picker.selected >= 0:
		var metadata: Variant = archive_picker.get_item_metadata(archive_picker.selected)
		if metadata is Dictionary: previous = metadata
	archive_picker.clear()
	restore_archive_button.disabled = true
	var result: Dictionary = slots.list_archives()
	if not result.ok:
		archive_picker.add_item("Archives unavailable: " + str(result.get("error", "Unknown error")))
		archive_picker.set_item_disabled(0,true)
		return
	var selected_index: int = -1
	var first_valid: int = -1
	for archive in result.archives:
		for entry in archive.entries:
			var row := {"archive_id":str(archive.id),"slot":int(entry.slot),"valid":bool(entry.valid),"errors":entry.get("errors",[])}
			var caption: String = "%s · slot %d · unavailable (files preserved)" % [archive.id, entry.slot]
			if row.valid:
				caption = "%s · slot %d · %s · day %d%s" % [archive.id, entry.slot, entry.scene, entry.day, " · backup recovery" if entry.recovered else ""]
			archive_picker.add_item(caption)
			var index: int = archive_picker.item_count-1
			archive_picker.set_item_metadata(index,row)
			if row.valid and first_valid < 0: first_valid = index
			if row.archive_id == previous.get("archive_id", "") and row.slot == previous.get("slot",-1): selected_index = index
	if archive_picker.item_count == 0:
		archive_picker.add_item("No recognized archived slots")
		archive_picker.set_item_disabled(0,true)
		return
	if selected_index < 0: selected_index = first_valid if first_valid >= 0 else 0
	archive_picker.select(selected_index)
	_select_archive(selected_index)

func _select_archive(index: int) -> void:
	var row: Variant = archive_picker.get_item_metadata(index)
	restore_archive_button.disabled = not row is Dictionary or not bool(row.get("valid", false))
	if row is Dictionary and not row.valid:
		title_status.text = "Archived slot %d is unavailable. Files were preserved. %s" % [row.slot, str(row.errors)]

func _restore_archive_copy() -> void:
	if running or archive_picker.selected < 0: return
	var row: Variant = archive_picker.get_item_metadata(archive_picker.selected)
	if not row is Dictionary or not bool(row.get("valid", false)):
		title_status.text = "Choose a valid archived save to restore."
		return
	slots.configure(session.campaign, slot_root)
	var result: Dictionary = slots.restore_archive(str(row.archive_id), int(row.slot))
	if not result.ok:
		title_status.text = "Restore failed: " + str(result.get("error", "Unknown error")) + ". The archive and current game were kept."
		return
	selected_slot = int(result.slot)
	_refresh_slots()
	title_status.text = "Restored a copy into slot %d%s. The archive was kept. Choose Continue to load the copy." % [selected_slot, " using its valid backup" if result.get("recovered",false) else ""]

func _build_scene_fader() -> void:
	var layer := CanvasLayer.new()
	layer.layer = 100
	add_child(layer)
	scene_shade = ColorRect.new()
	scene_shade.name = "SceneFade"
	layer.add_child(scene_shade)
	scene_shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_sync_scene_fader()

func _sync_scene_fader() -> void:
	if not scene_transition.active() or (not _source_inbound_close_receipt.is_empty() and _source_inbound_close_receipt.get("generation") != scene_transition.generation):
		_source_inbound_close_receipt = {}
	if scene_shade == null: return
	scene_shade.color = Color(0, 0, 0, scene_transition.alpha)
	scene_shade.visible = scene_transition.active()
	scene_shade.mouse_filter = Control.MOUSE_FILTER_STOP if scene_transition.blocks_input() else Control.MOUSE_FILTER_IGNORE

func _request_scene_change(action: Callable, source_portal_camera: bool = false) -> bool:
	var previous_generation: int = scene_transition.generation
	if quit_dispatched or (is_instance_valid(source_title_quit) and source_title_quit.visible) or not scene_transition.begin(action): return false
	_source_inbound_close_receipt = {}
	_clear_outbound_camera()
	if source_portal_camera:
		_outbound_camera_owner = session.get_instance_id()
		_outbound_camera_generation = scene_transition.generation
		# InputSystem wheel delta belongs to the dynamic frame, not the
		# coroutine that happens to begin before CameraController.Update.
		if _camera_scroll_owner==_outbound_camera_owner and _camera_scroll_generation==previous_generation \
				and not _camera_scroll_during_fade:
			_camera_scroll_generation = _outbound_camera_generation
			_camera_scroll_during_fade = true
	else:
		panning = false
		camera_pointer.take_pan_edges()
	pending_quit = ""
	_clear_card_hover()
	if is_instance_valid(craft_progress): craft_progress.reset()
	_sync_scene_fader()
	return true

func _request_new_game() -> void:
	if data_error != OK or running: return
	_request_scene_change(_commit_new_game.bind(session, int(duration.value), friendly_choice.button_pressed))

func _request_continue_game() -> void:
	if data_error != OK or running or selected_slot <= 0: return
	_request_scene_change(_commit_continue_game.bind(session, selected_slot))

func _request_return_title() -> void:
	if not running or scene_transition.active(): return
	if session.phase == "game_over":
		_return_title()
		return
	var result: Dictionary = _save_active_slot()
	if not result.ok:
		notice.text = "Could not save; session kept open: " + str(result.get("error", "Unknown error"))
		return
	_request_scene_change(_commit_title.bind(session))

func _commit_new_game(owner, requested_duration: int, requested_friendly: bool) -> void:
	if session != owner or running: return
	duration.value = requested_duration
	friendly_choice.button_pressed = requested_friendly
	start_new()

func _commit_continue_game(owner, requested_slot: int) -> void:
	if session != owner or running: return
	selected_slot = requested_slot
	_continue_game()

func _commit_title(owner) -> void:
	if session == owner and running: _show_title()

func _request_game_over_return() -> void:
	if not running or session.phase != "game_over": return
	_request_scene_change(_confirm_game_over_return)

func _request_travel(stack_id: int, recipe_guid: String) -> bool:
	if not running or scene_transition.active() or quit_dispatched: return false
	var candidate = Session.new()
	candidate.configure(catalog)
	var provenance: Dictionary = SourceTravelLayout.capture(session, stack_id, recipe_guid)
	var close_accepted: Dictionary = {}
	var result: Dictionary = candidate.campaign.restore(session.campaign.capture())
	if result.ok:
		# Stage against request-time state, without any live checkpoint callback.
		result = candidate.campaign.travel(stack_id, recipe_guid)
	if result.ok:
		# Retain exact returned IDs before checkpoint replaces this dictionary.
		provenance = SourceTravelLayout.seal(candidate, result, provenance)
		var snapshot: Dictionary = preload("res://scripts/ui/source_departure_checkpoint.gd").capture(session, stack_id, recipe_guid, result)
		# Only the accepted, source-locked ordinary traveler receipt grants this.
		# Carry it beside layout provenance without changing bound argument shape.
		provenance["source_arrival_no_save"] = not snapshot.is_empty()
		if not snapshot.is_empty(): close_accepted = result.duplicate(true)
		if snapshot.is_empty():
			result = _departure_checkpoint()
		else:
			var checkpoint_owner = Session.new()
			checkpoint_owner.configure(catalog)
			result = checkpoint_owner.campaign.restore(snapshot)
			if result.ok: result = _departure_checkpoint(checkpoint_owner.campaign)
	if not result.ok:
		if session.stacks.has(stack_id): session.stacks[stack_id].cancel_craft()
		_on_session_event("travel_failed", result)
		return false
	var close_receipt: Dictionary = {}
	if provenance.get("source_arrival_no_save", false):
		# Retain original accepted remap separately from later checkpoint result.
		close_receipt = {"owner": session, "candidate": candidate, "stack": session.stacks.get(stack_id), "recipe": recipe_guid}
		close_receipt["members"] = close_receipt.stack.card_ids.map(func(id): return session.cards[id])
		close_receipt["craft_generation"] = close_receipt.stack.craft_generation
		close_receipt["accepted"] = close_accepted
	# The ordinary locked Main ↔ Island portal uses TravelSequence even with
	# a first-time destination (layout/quit receipts have narrower ownership).
	var source_recipe: Dictionary = catalog.get_definition(recipe_guid)
	var source_portal_camera: bool = session.phase == "playing" and session.scene_name in ["Main","Island"] \
		and catalog.data.get("provenance", {}).get("source_commit") == SourceColdCrafting.SOURCE_COMMIT \
		and recipe_guid == SourceTravelLayout.RECIPE_GUID and source_recipe.get("source_sha256") == SourceTravelLayout.RECIPE_SHA \
		and source_recipe.get("script_class") == "TravelRecipe" \
		and source_recipe.get("fields", {}).get("targetScenes", []) == ["Main","Island"] \
		and candidate.scene_name == ("Island" if session.scene_name == "Main" else "Main")
	var accepted: bool = _request_scene_change(_commit_travel.bind(session, candidate, provenance), source_portal_camera)
	if accepted and not close_receipt.is_empty():
		close_receipt["generation"] = scene_transition.generation
		_source_close_receipt = close_receipt
	if accepted:
		_tail_receipt = {"owner":session.get_instance_id(),"generation":scene_transition.generation,"serial":session.crafting._active_serial}
	return accepted

func _complete_travel_tail(task: Dictionary, members: Array, step: float, serial: int) -> void:
	var receipt: Dictionary = _tail_receipt
	_tail_receipt = {} # One attempt only, including a rejected attempt.
	if task.is_empty(): return
	preload("res://scripts/ui/source_craft_tail_permit.gd").execute(self,task,members,step,serial,receipt)

func _commit_travel(owner, candidate, provenance: Dictionary = {}) -> void:
	var incoming: Dictionary = preload("res://scripts/ui/source_inbound_close.gd").admit_commit(self, _source_close_receipt, owner, candidate, provenance)
	_source_inbound_close_receipt = {}
	_source_close_receipt = {}
	_tail_receipt = {}
	owner.travel_pending = false
	if owner != session or not running: return
	# Atomic validated candidate swap; real-time old-scene activity after the
	# departure capture intentionally cannot rewrite captured travelers.
	session = candidate
	var source_arrival_no_save: bool = provenance.get("source_arrival_no_save", false)
	_enter_game(provenance)
	if not incoming.is_empty() and session == candidate and scene_transition.generation == incoming.generation and scene_transition.phase == "commit":
		_source_inbound_close_receipt = incoming
	if source_arrival_no_save:
		notice.text = "Arrived at " + session.scene_name
	else:
		_checkpoint("Arrived at " + session.scene_name)

func _exit_tree() -> void:
	_title_overlay_open_owner.clear()
	_title_options_open_owner.clear()
	_source_options_open_owner.clear()
	_source_options_owner_cache.clear()
	_source_inbound_close_receipt = {}
	_source_close_receipt = {}
	_tail_receipt = {}
	quest_journal.clear()
	world_post_process.cancel()
	scene_transition.cancel()
	session.travel_pending = false

func _configure_source_pause() -> void:
	_source_options_open_owner.clear()
	_source_options_owner_cache.clear()
	source_pause_configured = false
	var candidate = preload("res://scripts/ui/source_panel_view.gd").new()
	pause_overlay.add_child(candidate)
	candidate.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if not candidate.configure_panel(catalog.data,"UIRoot","UICanvas","PauseMenu",visual_assets):
		candidate.queue_free()
		return
	source_pause_configured = true
	for child in pause_overlay.get_children():
		if child is Control and child != candidate: child.hide()
	for i in pause_controls.size():
		var path: String = ["MainPanel/ContinueButton","MainPanel/OptionsButton","MainPanel/TitleButton"][i]
		var button: Button = pause_controls[i]
		if candidate.mount_path(path,button):
			button.text = str(candidate.layout.field(candidate.layout.resolve(path),"m_text",button.text))
			_admit_source_pause_pointer(catalog.data, candidate, i)

## PauseMenu.Awake wires its three own TextButtons; no filtering by mouse
## button in the original PointerClick. Do not widen fallback/safety targets.
func _admit_source_pause_pointer(data: Dictionary, view, index: int) -> bool:
	if index < 0 or index >= pause_controls.size() or index >= 3: return false
	var button: Button = pause_controls[index]
	button.button_mask = MOUSE_BUTTON_MASK_LEFT
	if data.get("provenance", {}).get("source_commit") != SourceColdCrafting.SOURCE_COMMIT: return false
	if not is_instance_valid(view) or not view.source_backed or view.get_parent() != pause_overlay or view.layout.root_id != "8532370488951995501": return false
	var path: String = ["MainPanel/ContinueButton","MainPanel/OptionsButton","MainPanel/TitleButton"][index]
	var link: String = ["continueButton","optionsButton","titleButton"][index]
	var button_id: String = ["8171884105890585185","2697808248802931809","6850422679154243207"][index]
	var host: String = view.layout.resolve(path)
	if not view.nodes.has(host) or button.get_parent() != view.nodes[host]: return false
	var controller: Dictionary = {}
	var text_button: Dictionary = {}
	for prefab in data.get("referenced_prefabs", []):
		if prefab.get("name") != "UIRoot" or prefab.get("guid") != "5e2985d7789c5254b831d166e6931134": continue
		for doc in preload("res://scripts/ui/source_prefab_documents.gd").resolve(data, "UIRoot"):
			if str(doc.get("file_id")) == "8547574447435325085" and doc.get("script_class") == "PauseMenu": controller = doc.get("fields", {})
			elif str(doc.get("file_id")) == button_id and doc.get("script_class") == "TextButton": text_button = doc.get("fields", {})
	if controller.get("m_Enabled") != 1 or controller.get("m_Script", {}).get("guid") != "c9da4713f45d2a3408a718a9d946f117": return false
	if controller.get("m_GameObject", {}) != view.layout.records[view.layout.root_id].rect.get("m_GameObject", {}): return false
	if str(controller.get(link, {}).get("fileID")) != button_id: return false
	if text_button.get("m_Enabled") != 1 or text_button.get("m_Script", {}).get("guid") != "ef98d84a856977b44bbf49a1bab2060a": return false
	if text_button.get("m_GameObject", {}) != view.layout.records[host].rect.get("m_GameObject", {}): return false
	button.button_mask = MOUSE_BUTTON_MASK_LEFT | MOUSE_BUTTON_MASK_RIGHT | MOUSE_BUTTON_MASK_MIDDLE
	return true

func _install_saved_rows() -> void:
	if source_title == null: return
	source_saved_rows = source_title.install_saved_rows(catalog.data,slot_picker,_request_continue_game,_request_archive_selected,func(): return _title_navigation_allowed() and title_navigation.destination == TitleNavigation.SAVES and (recovery_window == null or not recovery_window.visible),_play_ui_click)
	if source_saved_rows == null: return
	# Keep selector and old action objects alive as transaction state, not duplicate UI.
	slot_picker.hide()
	continue_button.hide()
	archive_selected_button.hide()
	recovery_window = Window.new()
	recovery_window.title = "Native recovery tools · recoverable archives and legacy saves"
	recovery_window.exclusive = true
	recovery_window.transient = true
	recovery_window.size = Vector2i(660,420)
	recovery_window.visible = false
	title_saves.add_child(recovery_window)
	recovery_window.close_requested.connect(_close_recovery)
	var margin := MarginContainer.new()
	recovery_window.add_child(margin)
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left","top","right","bottom"]: margin.add_theme_constant_override("margin_"+side,16)
	var box := VBoxContainer.new()
	margin.add_child(box)
	_label("Recoverable archives · originals retained",box,22)
	for control in [archive_picker,restore_archive_button,legacy_picker,legacy_button]: control.reparent(box)
	var close := _button("Close recovery tools",box,_close_recovery,true)
	var header: Control = source_title.nodes[source_title.layout.resolve("SavedGamesUI/MainPanel/Label")]
	recovery_button = _button("Recovery tools",header,func():
		if not _title_navigation_allowed(): return
		recovery_window.popup_centered()
		MenuFocus.loop([archive_picker,restore_archive_button,legacy_picker,legacy_button,close])
		close.grab_focus(),true)
	recovery_button.set_anchors_and_offsets_preset(Control.PRESET_CENTER_RIGHT)
	recovery_button.position = Vector2(570,10)
	recovery_button.size = Vector2(190,40)
	source_saved_rows.footer_controls = [archive_all_button,title_back_button,recovery_button]
	var reflow := func(): source_title.reflow_saved_footer([archive_all_button,title_back_button])
	source_title.resized.connect(reflow)
	reflow.call_deferred()

func _close_recovery() -> void:
	if recovery_window != null: recovery_window.hide()
	if recovery_button != null and recovery_button.is_visible_in_tree(): recovery_button.grab_focus()

func _restore_source_stats_height() -> void:
	# Reapply the source fixed parent RectTransform after a temporary native
	# fallback minimum grows and then shrinks; HBox does not shrink itself.
	if not is_instance_valid(stats_box) or not is_instance_valid(source_hud) or not is_instance_valid(stats_background): return
	var original := hud_layout.rect("CardStatsUI",source_hud.size,Rect2())
	if original.size.y <= 0: return
	stats_box.size = Vector2(stats_box.get_combined_minimum_size().x,original.size.y)
	stats_background.size = stats_box.size + Vector2(34,0)
