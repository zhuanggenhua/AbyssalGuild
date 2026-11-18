extends SceneTree
## Inject native event records through Board's real root viewport. This is not a
## physical touchscreen, Unity compare, or mixed mouse/pen input acceptance.
class QuietAudio extends "res://scripts/ui/audio_feedback.gd":
	var events: Array[String] = []
	func play_event(kind: String) -> bool:
		events.append(kind)
		return false
	func play_music() -> bool: return false
class BoardUnderTest extends "res://scripts/ui/board.gd":
	var events: Array = []
	func _input(event: InputEvent) -> void:
		events.append([event.get_class(),event.device])
		super._input(event)
const Session = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var board: BoardUnderTest
var checks := 0
var failures := 0

func _init() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",label)

func inject(event: InputEvent) -> void:
	Input.parse_input_event(event)
	Input.flush_buffered_events()
	await process_frame
	board._advance_running_frame(0)
	await physics_frame

# Input.parse_input_event receives window coordinates, unlike Board camera projection.
func touch(index: int, down: bool, point: Vector2, cancel: bool = false) -> void:
	var e := InputEventScreenTouch.new()
	e.index = index
	e.pressed = down
	e.canceled = cancel
	e.position = root.get_final_transform() * point
	await inject(e)

func move(index: int, point: Vector2) -> void:
	var e := InputEventScreenDrag.new()
	e.index = index
	e.position = root.get_final_transform() * point
	e.relative = Vector2(10,0)
	await inject(e)

func mouse(down: bool, point: Vector2) -> void:
	var e := InputEventMouseButton.new()
	e.pressed = down
	e.button_index = MOUSE_BUTTON_LEFT
	e.position = root.get_final_transform() * point
	await inject(e)

func clear_cards() -> void:
	board.session.drag.reset()
	board.session.combat.dragged.clear()
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board.session.phase = "playing"
	board.session.paused = true
	board.session.spawn_target_selector = Callable()
	board.session.spawn_layout_resolver = Callable()
	board._refresh()

func spawn(label: String, point: Vector2) -> int:
	return board.session.spawn_card(board.catalog.find_by_name(label),point,-1,{"refuse_attach":true})

func fruit(at: Vector2) -> Array:
	var apple := spawn("Apple",at)
	var berry := spawn("Berry",at)
	var stack_id: int = board.session.cards[apple].stack_id
	assert(board.session.move_to_stack(berry,stack_id))
	board.session.stacks[stack_id].progress = 2.0
	return [apple,berry,stack_id]

func where(id: int) -> Vector2:
	return board.camera.unproject_position(board.views[id].global_position)

func reachable(id: int) -> Vector2:
	var center: Vector3 = board.views[id].global_position
	for z in range(-30,31):
		var candidate := board.camera.unproject_position(center+Vector3(0,0,z*.025))
		if board._pick(candidate)==id: return candidate
	return Vector2.INF

func settle_views() -> void:
	board._refresh()
	await process_frame
	await physics_frame
	await process_frame

func run() -> void:
	Input.emulate_mouse_from_touch = true
	root.size = Vector2i(1440,900)
	board = BoardUnderTest.new()
	board.feedback.free()
	board.feedback = QuietAudio.new()
	var save := "user://touch-card-board-%d" % Time.get_ticks_usec()
	board.slot_root = save.path_join("slots")
	board.options_path = save.path_join("options.json")
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	check(board.data_error == OK,"locked scene catalog present")
	if board.data_error != OK:
		board.queue_free()
		quit(1)
		return
	board.start_new()
	board.set_process(false)
	clear_cards()
	var a := spawn("Wood",Vector2(-3,1))
	var b := spawn("Wood",Vector2(0,1))
	await settle_views()
	var ap := where(a)
	var bp := where(b)
	check(board._pick(ap)==a and board._pick(bp)==b,"both contact points hit actual card colliders")
	board.events.clear()
	await touch(0,true,ap)
	check(board.events.slice(0,2)==[["InputEventMouseButton",-1],["InputEventScreenTouch",0]],"emulated mouse edge arrives before canonical touch")
	check(board.touch_card_receivers.owns(0) and board._touch_drags.has(a) and board.dragging<0
		and board.session.drag.held_ids()==[a] and not board.panning,"one source card press, no emulated duplicate or pan")
	await touch(1,true,bp)
	check(board.touch_card_receivers.owns(1) and board.session.drag.held_ids()==[a,b],"separate per-card holds in actual Board")
	var a0: Vector2 = board.session.card_target_position(a)
	var b0: Vector2 = board.session.card_target_position(b)
	await move(1,bp+Vector2(25,0))
	check(board.session.card_target_position(a)==a0 and board.session.card_target_position(b)==b0,
		"secondary motion never supplies the shared drag pointer")
	await move(0,ap+Vector2(40,0))
	var a1: Vector2 = board.session.card_target_position(a)
	var b1: Vector2 = board.session.card_target_position(b)
	check(a1.x>a0.x and (a1-a0).is_equal_approx(b1-b0),"both actual card stacks follow primary using separate offsets")
	var panel := Control.new()
	panel.position = Vector2(120,120)
	panel.size = Vector2(100,100)
	panel.mouse_filter = Control.MOUSE_FILTER_STOP
	board.hud.add_child(panel)
	panel.move_to_front()
	await process_frame
	# Freeze the accepted pointer's location for the eventual orphan, but send
	# the up away over actual GUI. A must drop at its last transform.
	await touch(0,false,Vector2(150,150))
	check(not board.touch_card_receivers.owns(0) and not board.session.drag.active_for(a)
		and board.session.drag.active_for(b) and board.session.combat.dragged.has(b),"release over GUI ends only original receiver")
	check(board.session.card_target_position(a).distance_to(a1)<.1,"up position is not a new sample for the released card")
	var orphan: Vector2 = board.session.card_target_position(b)
	await move(1,bp+Vector2(75,0))
	check(board.camera_pointer.orphan and board.session.card_target_position(b)==orphan,"secondary cannot move orphaned primary")
	await touch(1,false,bp,true)
	check(not board.session.drag.active() and board._touch_drags.is_empty() and board.session.combat.dragged.is_empty(),
		"canceled touch dispatches native card up and leaves no hold")
	panel.queue_free()
	# In source pointerPress is set even when the card rejects DOWN due to lock.
	clear_cards()
	a = spawn("Wood",Vector2(-3,1))
	await settle_views()
	ap = where(a)
	board.session.phase = "feeding"
	await touch(0,true,ap)
	check(board.touch_card_receivers.owns(0) and not board.session.drag.active(),"real locked DOWN still retains receiver")
	board.session.phase = "playing"
	await touch(1,true,ap)
	check(board.session.drag.held_ids()==[a],"another touch may start the formerly locked card")
	var sound_count: int = board.feedback.events.count("CardPick")
	await touch(2,true,where(a))
	check(board.session.drag.held_ids()==[a] and board.feedback.events.count("CardPick")==sound_count+1,
		"accepted repeated DOWN updates one card and plays one additional source pick")
	var drops: int = board.feedback.events.count("CardDrop")
	await touch(0,false,ap,true)
	check(not board.session.drag.active() and board.touch_card_receivers.owns(1) and board.touch_card_receivers.owns(2)
		and board.feedback.events.count("CardDrop")==drops+1,"first receiver up finishes current card even when its down was rejected")
	await touch(1,false,ap)
	await touch(2,false,ap)
	check(board.feedback.events.count("CardDrop")==drops+1,"remaining ups do not dispatch a duplicate card drop")
	await mouse(true,where(a))
	check(board.dragging==a and board.session.drag.active_for(a) and board._touch_drags.is_empty(),"standalone real mouse keeps old route")
	await mouse(false,where(a))
	check(board.dragging<0 and not board.session.drag.active(),"mouse release keeps old route")
	# Two real fruit recipes independently pause at pickup. A source return can
	# bypass its own active recipe, never another root's paused original.
	clear_cards()
	var left := fruit(Vector2(-3,-1))
	var right := fruit(Vector2(0,-1))
	await settle_views()
	ap = where(left[1])
	bp = where(right[1])
	check(board._pick(ap)==left[1] and board._pick(bp)==right[1],"actual rays select both fruit recipe tails")
	await touch(0,true,ap)
	await touch(1,true,bp)
	var left_base = board.session.stacks[left[2]]
	var right_base = board.session.stacks[right[2]]
	check(left_base.paused and right_base.paused and board.session.drag.held_ids()==[left[1],right[1]],
		"two actual splits pause exactly their own crafting tasks")
	var random_before: int = board.session.rng.state
	var clone = Session.new()
	clone.configure(board.catalog,123)
	var save_record: Dictionary = Codec.capture(board.session)
	check(Codec.restore(clone,save_record).ok and not clone.drag.active()
		and not clone.stacks[left[2]].paused and not clone.stacks[right[2]].paused,
		"two live holds normalize only in the restored native checkpoint")
	check(left_base.paused and right_base.paused and board.session.rng.state==random_before,
		"capture does not alter either live hold, pause or RNG")
	await touch(1,false,Vector2(760,660),true)
	check(not right_base.paused and right_base.progress==2.0 and right_base.card_ids==[right[0],right[1]]
		and left_base.paused and board.session.drag.held_ids()==[left[1]],"canceled secondary up returns only its original recipe tail without losing progress")
	var buyer: Dictionary = board.trade_zones[0]
	var lift: Vector2 = board.session.card_target_position(left[1])
	var token = board._touch_drags.get(left[1])
	var sale_board_point: Vector2 = Vector2(buyer.center.x,buyer.center.z) + (token.origin if token != null else Vector2.ZERO) - lift
	var sale_screen := board.camera.unproject_position(Vector3(sale_board_point.x,0,-sale_board_point.y))
	await move(0,sale_screen)
	await touch(0,false,ap)
	check(not board.session.cards.has(left[1]) and left_base.recipe_guid.is_empty() and not left_base.paused
		and right_base.progress==2.0 and not board.session.drag.active(),"real touch buyer drop cancels only its own original craft")

	# After a child is picked from a held stack, it may reattach to the held head.
	clear_cards()
	var head := spawn("Wood",Vector2(-2,-1))
	var tail := spawn("Wood",Vector2(-2,-1))
	var shared: int = board.session.cards[head].stack_id
	check(board.session.move_to_stack(tail,shared),"two stack-compatible cards placed together")
	await settle_views()
	ap = where(head)
	var head_only := reachable(head)
	check(head_only.is_finite(),"explicit uncovered head hit reaches original receiver")
	if not head_only.is_finite(): head_only = ap
	await touch(0,true,head_only)
	await settle_views()
	bp = reachable(tail)
	check(bp.is_finite(),"second contact hits visible held-stack tail")
	if not bp.is_finite(): bp = where(tail)
	await touch(1,true,bp)
	check(board.session.drag.held_ids()==[head,tail] and board.session.cards[tail].stack_id!=shared,
		"later tail press splits after the still-held root")
	await touch(1,false,bp)
	check(board.session.drag.held_ids()==[head] and board.session.cards[tail].stack_id==shared,
		"tail can attach to a different card's live held stack")
	var previous: Vector2 = board.session.card_target_position(head)
	await move(0,head_only+Vector2(30,0))
	check(board.session.card_target_position(head).x>previous.x and board.session.cards[tail].stack_id==shared,
		"remaining receiver still moves the combined actual stack")
	await touch(0,false,head_only)
	check(not board.session.drag.active() and not board._has_card_drag(),"combined stack releases exactly once")
	a = head
	ap = where(a)
	# Scene return abandons captures; ups cannot target a new card with reused ID.
	await touch(3,true,where(a))
	check(board.touch_card_receivers.owns(3),"captured before title return")
	board._show_title()
	await touch(3,false,ap)
	check(not board.touch_card_receivers.owns(3) and not board.session.drag.active(),"title resets receiver and transient model")
	board.queue_free()
	await process_frame
	await create_timer(.2).timeout
	print("Source card touch Board: %d/%d passed" % [checks-failures,checks])
	quit(1 if failures else 0)
