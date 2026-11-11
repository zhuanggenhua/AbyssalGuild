extends Button
## TextButton.cs: action first, one Click request, silent pointer enter/exit.
## Original native font/geometry; not a TextMeshPro glyph-layout reproduction.
var action: Callable
var play_click: Callable
var allowed: Callable
var underline := false

func configure(callback: Callable, sound: Callable, guard: Callable = Callable()) -> void:
	action = callback
	play_click = sound
	allowed = guard
	if not pressed.is_connected(_activate): pressed.connect(_activate)
	if not mouse_entered.is_connected(_enter): mouse_entered.connect(_enter)
	if not mouse_exited.is_connected(_leave): mouse_exited.connect(_leave)
	if not visibility_changed.is_connected(_leave): visibility_changed.connect(_leave)

func _activate() -> void:
	if not is_visible_in_tree() or disabled or is_queued_for_deletion() or not action.is_valid(): return
	if allowed.is_valid() and not allowed.call(): return
	action.call()
	# Callback may close its panel or change the audio volume. Do not recheck
	# visibility after it: source still requests Click for this admitted action.
	if play_click.is_valid(): play_click.call()

func _enter() -> void:
	if disabled or not is_visible_in_tree(): return
	underline = true
	queue_redraw()

func _leave() -> void:
	underline = false
	queue_redraw()

func _process(_delta: float) -> void:
	if underline and (disabled or not is_visible_in_tree()): _leave()

func _draw() -> void:
	if not underline or disabled or not is_visible_in_tree(): return
	var font := get_theme_font("font")
	var font_size := get_theme_font_size("font_size")
	var width := minf(font.get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x, maxf(0, size.x - 12))
	var y := (size.y + font.get_height(font_size)) * 0.5 - font.get_descent(font_size) + 2
	draw_line(Vector2((size.x - width) * 0.5, y), Vector2((size.x + width) * 0.5, y), get_theme_color("font_hover_color"), 1.0)

static func bind_modal(dialog: ConfirmationDialog, accept: Callable, decline: Callable, sound: Callable) -> void:
	# Native default hides before confirmed, losing the admission evidence.
	# Own that hide so stale/hidden signal emissions remain silent and inert.
	dialog.dialog_hide_on_ok = false
	dialog.confirmed.connect(_modal_action.bind(dialog, true, accept, sound))
	dialog.canceled.connect(_modal_action.bind(dialog, false, decline, sound))

static func _modal_action(dialog: ConfirmationDialog, accepting: bool, action_callback: Callable, sound: Callable) -> void:
	if not is_instance_valid(dialog) or not dialog.visible or dialog.is_queued_for_deletion(): return
	var button := dialog.get_ok_button() if accepting else dialog.get_cancel_button()
	if button.disabled: return
	if action_callback.is_valid(): action_callback.call()
	dialog.hide()
	if sound.is_valid(): sound.call()
