extends Node
## Board adapter for the live-only reveal. This owns no global pause or save data.
const Sequence = preload("res://scripts/ui/vendor_unlock_sequence.gd")
var sequence = Sequence.new()
var info_panel: PanelContainer
var info_label: Label
var _board: WeakRef
var _tracker: WeakRef
var _owned_focus: Dictionary = {}

func _init() -> void:
	sequence.sequence_started.connect(_on_sequence_started)
	sequence.sequence_finished.connect(_on_sequence_finished)

## Call after the board has rebuilt its final scene geometry and quest state.
func bind(board) -> void:
	cancel()
	_board = weakref(board)
	if not is_instance_valid(info_panel):
		info_panel = PanelContainer.new()
		info_panel.name = "VendorUnlockInfo"
		info_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info_panel.position = Vector2(360, 735)
		info_panel.size = Vector2(720, 76)
		var style := StyleBoxFlat.new()
		style.bg_color = Color(0.035, 0.06, 0.09, 0.94)
		style.border_color = Color(0.94, 0.76, 0.24)
		style.set_border_width_all(1)
		style.content_margin_left = 12
		style.content_margin_right = 12
		style.content_margin_top = 8
		style.content_margin_bottom = 8
		info_panel.add_theme_stylebox_override("panel", style)
		board.hud.add_child(info_panel)
		info_label = Label.new()
		info_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		info_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		info_label.add_theme_font_size_override("font_size", 20)
		info_panel.add_child(info_label)
	sequence.restore(board.trade_zones)
	_tracker = weakref(board.session.quest_tracker)
	var tracker = _tracker.get_ref()
	tracker.quest_completed.connect(_on_quest_completed)
	_refresh_notice()

func is_active() -> bool:
	return sequence.is_active()

## Geometry refresh never acknowledges a quest. Use the actual tracker signal.
func update_zones(zones: Array) -> void:
	sequence.update_zones(zones)

## Call after camera motion with the real (unscaled) frame delta, even in menus.
func advance(real_delta: float) -> void:
	sequence.advance(real_delta)
	_refresh_notice()

## A scene/session rebind, title or teardown cancels only this owner. In-flight
## cycle camera focus is not cleared if it superseded this reveal's camera move.
func cancel() -> void:
	if _tracker != null:
		var tracker = _tracker.get_ref()
		if tracker != null and tracker.quest_completed.is_connected(_on_quest_completed):
			tracker.quest_completed.disconnect(_on_quest_completed)
	_tracker = null
	var board = _live_board()
	if board != null and not _owned_focus.is_empty() and is_same(board.camera_motion.focus, _owned_focus):
		board.camera_motion.focus.clear()
	_owned_focus = {}
	sequence.cancel()
	if is_instance_valid(info_panel): info_panel.hide()
	if is_instance_valid(info_label): info_label.text = ""

func _exit_tree() -> void:
	cancel()

func _live_board():
	return _board.get_ref() if _board != null else null

func _on_quest_completed(_instance: Dictionary) -> void:
	var board = _live_board()
	if board == null or not board.running:
		return
	# Activation is immediate, before its presentation starts. Keep all eligible
	# vendors visible while their individual reveals remain queued.
	board._sync_trade_zones()
	sequence.on_quest_completed(board.trade_zones)

func _on_sequence_started(zone: Dictionary) -> void:
	var board = _live_board()
	if board == null: return
	_refresh_notice()
	if board.trade_views.has(int(zone.index)):
		board.trade_views[int(zone.index)].set_highlighted(true)
	board._focus_camera_position(zone.center, Sequence.FOCUS_SECONDS)
	_owned_focus = board.camera_motion.focus
	# A card's existing pointer-down grant remains valid. Source only blocks
	# new card presses; it does not revoke an already held drag on unlock.
	call_deferred("_refresh_board")

func _on_sequence_finished(zone: Dictionary) -> void:
	var board = _live_board()
	if board != null and board.trade_views.has(int(zone.index)):
		var view = board.trade_views[int(zone.index)]
		if is_instance_valid(view): view.set_highlighted(false)
	_owned_focus = {}
	_refresh_notice()
	if board != null and board.running:
		call_deferred("_refresh_board")

func _refresh_board() -> void:
	var board = _live_board()
	if board != null and board.running:
		board._refresh()

func _refresh_notice() -> void:
	if not is_instance_valid(info_panel) or not is_instance_valid(info_label): return
	var board = _live_board()
	var info: Dictionary = sequence.info()
	info_label.text = "%s\n%s" % [info.header, info.body] if not info.is_empty() else ""
	# End-cycle has the source's higher Modal priority. Ordinary/save-error
	# notices stay in their existing independent label and are never overwritten.
	info_panel.visible = board != null and board.running and board.session.phase == "playing" and not info.is_empty()
