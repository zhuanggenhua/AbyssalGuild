extends SceneTree
class BoardAdapter extends "res://scripts/ui/board.gd":
	var hit := {"card_id":-1,"panel_owner":-1}
	func _pick_target(_point: Vector2) -> Dictionary: return hit
class SilentFeedback extends "res://scripts/ui/audio_feedback.gd":
	func play_event(_event: String) -> bool: return false
	func play_music() -> bool: return false
var checks := 0
var failures := 0
func check(value: bool,label: String) -> void:
	checks+=1
	if not value: failures+=1; push_error(label)
func _initialize() -> void: call_deferred("run")
func spawn(board,name: String,point: Vector2) -> int:
	return board.session.spawn_card(board.catalog.find_by_name(name),point)
func press(board,id: int) -> void:
	board.hit={"card_id":id,"panel_owner":-1}
	board._begin_card_press(board.hit,board.camera.unproject_position(board.views[id].global_position))
func run() -> void:
	var board := BoardAdapter.new()
	board.feedback.free(); board.feedback=SilentFeedback.new()
	board.slot_root="user://highlight-lifetime-%d" % Time.get_ticks_usec()
	board.options_path=board.slot_root+"/options.json"; board.legacy_paths.clear()
	root.add_child(board); await process_frame
	board.start_new(); board.set_process(false)
	board.session.spawn_target_selector=Callable(); board.session.spawn_layout_resolver=Callable()
	for id in board.session.cards.keys(): board.session._remove_card(id)
	board._clear_card_feedback()
	var incoming: int=spawn(board,"Wood",Vector2(-3,-1))
	var target: int=spawn(board,"Wood",Vector2(3,-1))
	var station: int=spawn(board,"Sawmill",Vector2(0,1))
	var work=board.session.stacks[board.session.cards[station].stack_id]
	for i in 4: board.session.spawn_card(board.catalog.find_by_name("Wood"),Vector2.ZERO,work.id)
	board.session._check_recipe(work)
	board._refresh()
	check(board.session.can_move_to_stack(incoming,work.id),"drop accepts excess craft; highlight must independently reject")
	press(board,incoming)
	check(board.card_drag_targets.has(target) and not board.card_drag_targets.has(work.card_ids.back()),"actual down uses source highlight-only predicate")
	var target_view=board.views[target]
	check(target_view.drag_target.visible and board.trade_views[0].highlighted,"actual down samples both card and buyer targets")
	var entries: int=board.drag_highlights.cards.size()
	board.pause_overlay.show(); board._sync_card_feedback()
	check(target_view.drag_target.visible and board.drag_highlights.cards.size()==entries,"pause does not clear source snapshot")
	board.hud.hide(); board._sync_card_feedback()
	check(target_view.drag_target.visible,"hiding unrelated HUD does not dispose highlight manager")
	board.hud.show()
	board._request_scene_change(func(): pass)
	check(target_view.drag_target.visible,"scene fade start is not scene manager disposal")
	board.scene_transition.cancel()
	board.pause_overlay.hide(); board.vendor_unlock.sequence.stage="hold"; board._sync_card_feedback()
	check(target_view.drag_target.visible,"new vendor input lock preserves existing highlight")
	board._notification(Node.NOTIFICATION_WM_MOUSE_EXIT)
	check(target_view.drag_target.visible,"mouse exit does not invent source highlight clear")
	board.session.stacks[board.session.cards[target].stack_id].recipe_guid="synthetic-changed-after-down"
	var late: int=spawn(board,"Wood",Vector2(1,-3))
	board._sync_views(); board._sync_card_feedback()
	check(target_view.drag_target.visible and not board.card_drag_targets.has(late),"changed eligibility retained and late new candidate not recomputed")
	target_view.hide(); target_view.show()
	check(target_view.drag_target.visible,"disable/enable retains child active flag")
	board.session.stacks[board.session.cards[target].stack_id].recipe_guid=""
	board._finish_drag(Vector2(400,400))
	check(not target_view.drag_target.visible and not board.trade_views[0].highlighted and board.drag_highlights.cards.is_empty(),"real release under lock clears both lists")
	board.vendor_unlock.sequence.stage="idle"
	# Real combat model entry must clear cards but not trade list.
	press(board,incoming)
	var fighter: int=spawn(board,"Villager",Vector2(-2,2))
	var enemy_guid := ""
	for definition in board.catalog.data.cards:
		if int(definition.fields.get("category",0))==9 and int(definition.fields.get("faction",0))==2:
			enemy_guid=definition.guid; break
	var enemy: int=board.session.spawn_card(enemy_guid,Vector2(2,2))
	var combat: int=board.session.combat.start_combat([fighter],[enemy])
	check(combat>=0 and board.drag_highlights.cards.is_empty() and not target_view.drag_target.visible,"actual EnterCombat signal clears card snapshots")
	check(not board.drag_highlights.zones.is_empty() and board.trade_views[0].highlighted,"EnterCombat leaves trade highlights alone")
	board._finish_drag(Vector2(400,400))
	board._sync_views()
	press(board,fighter)
	check(board.drag_highlights.cards.is_empty() and board.drag_highlights.zones.is_empty(),"actual combat down skips both highlight managers")
	board._finish_drag(Vector2(400,400))
	# Reveal writes same source zone setter, not a separate high-priority channel.
	var coin: int=spawn(board,"Coin",Vector2(-3,-2))
	board._sync_views()
	board.trade_zones[1].active=true
	board.trade_views[1].configure(board.trade_zones[1], "")
	press(board,coin)
	check(board.trade_views[1].highlighted,"currency down highlights active vendor")
	board.vendor_unlock._on_sequence_started(board.trade_zones[1])
	board._finish_drag(Vector2(400,400))
	check(not board.trade_views[1].highlighted,"accepted release can turn off active reveal highlight")
	board.vendor_unlock._on_sequence_finished(board.trade_zones[1])
	check(not board.trade_views[1].highlighted,"reveal false is a direct competing write")
	# Object identity survives stack edits, but destroyed refs surface a diagnostic.
	board._sync_views(); press(board,incoming)
	board.views[target].free(); board.views.erase(target)
	board._clear_drag_target_feedback()
	check(board.drag_highlights.last_error.get("error","")=="source_missing_reference","dead target reports explicit source boundary")
	board.drag_highlights.dispose(); board.card_drag_targets.clear()
	board.queue_free(); await process_frame; await create_timer(.3).timeout
	print("Source highlight live board: %s (%d checks)" % ["PASS" if failures==0 else "FAIL",checks])
	quit(0 if failures==0 else 1)
