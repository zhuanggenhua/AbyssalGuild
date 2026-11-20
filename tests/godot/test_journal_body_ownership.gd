extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
var checks := 0
var failures := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ", label)
func _init() -> void: call_deferred("run")
func settle() -> void:
	await process_frame
	await process_frame
func point_event(point: Vector2, button := 0, pressed := true, factor := 1.0, device := 0) -> void:
	var motion := InputEventMouseMotion.new()
	motion.device = device
	motion.position = point
	motion.global_position = point
	root.push_input(motion,true)
	if button == 0: return
	var event := InputEventMouseButton.new()
	event.device = device
	event.position = point
	event.global_position = point
	event.button_index = button
	event.pressed = pressed
	event.factor = factor
	root.push_input(event,true)

func test_native_scroll(board, q, r) -> void:
	board._configure_source_hud()
	board.journal_slide.reset(true)
	await settle()
	q.set_process(false)
	r.set_process(false)
	check(q.clip_contents and is_equal_approx(q.size.x,400) and is_equal_approx(q.position.y,60),
		"full source viewport under header, not permanently clipped padding")
	check(q.content.size.x == q.size.x and q.motion.hidden_length() > 0,
		"overflow from actual content bounds in full-width host")
	var where: Vector2 = q.get_global_transform_with_canvas()*Vector2(5,5)
	q.reset_scroll()
	board.session.phase = "playing"
	var forward: Vector3 = -board.camera.global_basis.z
	board.camera_motion.configure(-forward*10)
	var expected_camera = preload("res://scripts/ui/camera_motion.gd").new()
	expected_camera.configure(board.camera_motion.target)
	expected_camera.zoom(-1,forward)
	point_event(where,MOUSE_BUTTON_WHEEL_DOWN)
	check(is_equal_approx(q.motion.position,6) and q.content.position.y == -6 and r.motion.position == 0,
		"one viewport-routed wheel tick scrolls only active body by six source units")
	check(board.camera_motion.target.is_equal_approx(expected_camera.target),
		"same event keeps exactly one independent camera wheel update")
	point_event(where,MOUSE_BUTTON_WHEEL_LEFT,true,.5)
	check(is_equal_approx(q.motion.position,3),"fractional horizontal wheel uses vertical-only source fallback")
	var tab: Control = board.journal_tabs.get_child(0)
	point_event(tab.get_global_transform_with_canvas()*(tab.size/2),MOUSE_BUTTON_WHEEL_DOWN)
	check(is_equal_approx(q.motion.position,3),"header does not acquire body wheel")
	var blocker := Control.new()
	blocker.mouse_filter = Control.MOUSE_FILTER_STOP
	board.source_hud.add_child(blocker)
	blocker.position = board.detail_panel.position + q.position
	blocker.size = q.size
	await settle()
	point_event(where,MOUSE_BUTTON_WHEEL_DOWN)
	check(is_equal_approx(q.motion.position,3),"topmost GUI blocker prevents rectangle-based input leak")
	blocker.free()
	q.reset_scroll()
	var group: String = board.ledger_visible_groups.keys()[0]
	var hit: Vector2 = q.get_global_transform_with_canvas()*Vector2(30,25)
	if not q.source_scroll_bound or not r.source_scroll_bound:
		# CI has no original ScrollRect asset; exercise the same Board router
		# through its test geometry without claiming actual source admission.
		check(not q.source_pointer_managed and not r.source_pointer_managed,"no source admission in fallback")
		q.source_pointer_managed = true
		r.source_pointer_managed = true
		board.journal_rows.quests.source_pointer_managed = true
		board.journal_rows.recipes.source_pointer_managed = true
	else:
		check(q.source_pointer_managed and r.source_pointer_managed,"both exact contracts activate framed routing")
	point_event(hit,MOUSE_BUTTON_LEFT)
	await settle()
	point_event(hit+Vector2(0,30))
	await settle()
	point_event(hit+Vector2(0,50))
	await settle()
	check(q.motion.dragging and not is_zero_approx(q.motion.position),"source capture receives earlier-frame left ScrollRect movement")
	point_event(hit+Vector2(0,50),MOUSE_BUTTON_LEFT,false)
	await settle()
	check(board.ledger_expansion.get(group,true) and board.dragging == -1 and not q.motion.dragging,
		"scroll drag cancels row click and cannot grab the board")
	q.reset_scroll()
	for pair in [[MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT],[MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_LEFT]]:
		point_event(hit,MOUSE_BUTTON_LEFT)
		point_event(hit,MOUSE_BUTTON_RIGHT)
		await settle()
		point_event(hit,pair[0],false)
		await settle()
		check(not board.ledger_expansion.get(group,true),"first chord release toggles exactly once")
		point_event(hit,pair[1],false)
		await settle()
		check(not board.ledger_expansion.get(group,true),"second chord release consumes nothing")
		point_event(hit,MOUSE_BUTTON_RIGHT)
		point_event(hit,MOUSE_BUTTON_RIGHT,false)
		await settle()
		check(board.ledger_expansion.get(group,true),"plain right tap reopens same group")
	var physical: Transform2D = root.get_final_transform()
	var offset: Vector2 = physical.affine_inverse().basis_xform(Vector2(0,10))
	point_event(hit,MOUSE_BUTTON_RIGHT)
	await settle()
	point_event(hit+offset)
	await settle()
	point_event(hit,MOUSE_BUTTON_RIGHT,false)
	await settle()
	check(board.ledger_expansion.get(group,true) and not q.motion.dragging and q.motion.position==0,
		"right capture crosses exact drag threshold without moving ScrollRect or clicking")
	point_event(hit,MOUSE_BUTTON_MIDDLE)
	await settle()
	point_event(hit+offset,MOUSE_BUTTON_MIDDLE,false)
	await settle()
	check(not board.ledger_expansion.get(group,true),
		"movement sampled in the release frame is not an earlier drag")
	point_event(hit,MOUSE_BUTTON_LEFT,true,1.0,InputEvent.DEVICE_ID_EMULATION)
	point_event(hit,MOUSE_BUTTON_LEFT,false,1.0,InputEvent.DEVICE_ID_EMULATION)
	check(board.ledger_expansion.get(group,true),"touch emulation retains its independent compatibility path")
	# Capture of native ScrollRect is tied to the press view, not active tab.
	point_event(hit,MOUSE_BUTTON_LEFT)
	await settle()
	point_event(hit+Vector2(0,30))
	await settle()
	board._show_journal_tab("recipes")
	point_event(hit+Vector2(0,50))
	await settle()
	check(q.motion.dragging and q.motion.position!=0 and r.motion.position==0,
		"hidden captured Quests body still owns its physical left drag")
	point_event(hit+Vector2(0,50),MOUSE_BUTTON_LEFT,false)
	await settle()
	check(not q.motion.dragging and r.motion.position==0,"hidden owner receives matching release")
	board._show_journal_tab("quests")
	q.reset_scroll()
	q.motion.position = 25
	q.motion.velocity = 120
	board._show_journal_tab("recipes")
	q.advance_unscaled(.05)
	check(q.motion.position > 25 and r.motion.position == 0,
		"hidden tab continues its own unscaled inertia while Recipes is selected")
	board._show_journal_tab("quests")
	q.reset_scroll()
	r.reset_scroll()
	point_event(where-Vector2(10,40))
	await settle()

func test_captured_release(board, q: Control, rows: Control) -> void:
	var group: String = board.ledger_visible_groups.keys()[0]
	var row: Control = rows.rows["group:" + group]
	var local := Vector2(24, 4)
	q.motion.position = row.position.y + 8
	q._apply_motion()
	await settle()
	var hit: Vector2 = q.get_global_transform_with_canvas() * local
	var behind_mask: Vector2 = q.get_global_transform_with_canvas() * Vector2(local.x, -3)
	var mask_clicks := {"n":0}
	var note_mask := func(_meta): mask_clicks.n += 1
	rows.meta_clicked.connect(note_mask)
	check(row.get_global_rect().has_point(behind_mask) and not q.get_global_rect().has_point(behind_mask),
		"part of the same header is outside the viewport mask")
	for button in [MOUSE_BUTTON_LEFT,MOUSE_BUTTON_RIGHT,MOUSE_BUTTON_MIDDLE]:
		point_event(hit,button)
		await settle()
		point_event(behind_mask,button,false)
		await settle()
		check(mask_clicks.n==0 and board.ledger_expansion.get(group,true),
			"captured release outside the mask does not toggle: %s" % button)
	var factor: Transform2D = root.get_final_transform()
	var near_hit: Vector2 = q.get_global_transform_with_canvas()*Vector2(local.x,1)
	var excursion: Vector2 = factor.affine_inverse().basis_xform(Vector2(0,3))
	point_event(near_hit,MOUSE_BUTTON_RIGHT)
	await settle()
	point_event(near_hit-excursion)
	await settle()
	point_event(near_hit)
	await settle()
	point_event(near_hit,MOUSE_BUTTON_RIGHT,false)
	await settle()
	check(mask_clicks.n==1,"exit and return below drag threshold preserves click ticket")
	rows.meta_clicked.disconnect(note_mask)
	board.ledger_expansion[group]=true
	board._refresh_ledger()
	q.reset_scroll()
	await settle()
	var on_row: Vector2 = row.get_global_transform_with_canvas()*Vector2(4,4)
	var blocker := Control.new()
	blocker.mouse_filter=Control.MOUSE_FILTER_STOP
	board.source_hud.add_child(blocker)
	blocker.position=board.detail_panel.position+q.position
	blocker.size=q.size
	point_event(on_row,MOUSE_BUTTON_RIGHT)
	point_event(on_row,MOUSE_BUTTON_RIGHT,false)
	await settle()
	check(board.ledger_expansion.get(group,true),"later GUI blocker masks framed click admission")
	blocker.free()
	point_event(on_row,MOUSE_BUTTON_MIDDLE)
	await settle()
	var received := {"n":0}
	var note_click := func(_meta): received.n += 1
	rows.meta_clicked.connect(note_click)
	check(board.scene_transition.begin(func(): pass),"real outbound fader acquires raycasts")
	board._sync_scene_fader()
	point_event(on_row,MOUSE_BUTTON_MIDDLE,false)
	board.journal_pointer.flush(root.get_final_transform(),board._journal_source_mouse_hit,
		q.drag_threshold,board._dispatch_journal_source_mouse)
	check(received.n==0 and board.scene_shade.mouse_filter==Control.MOUSE_FILTER_STOP,
		"captured release is not emitted through the visible outbound fader")
	board.scene_transition.advance(1.0)
	board._sync_scene_fader()
	point_event(on_row,MOUSE_BUTTON_MIDDLE)
	point_event(on_row,MOUSE_BUTTON_MIDDLE,false)
	board.journal_pointer.flush(root.get_final_transform(),board._journal_source_mouse_hit,
		q.drag_threshold,board._dispatch_journal_source_mouse)
	check(received.n==1 and not board.ledger_expansion.get(group,true) and board.scene_shade.color.a==1.0,
		"opaque inbound fader ignores pointer and permits ordinary Journal release")
	rows.meta_clicked.disconnect(note_click)
	board.scene_transition.cancel()
	board._sync_scene_fader()
	board.ledger_expansion[group] = true
	board._refresh_ledger()
	q.reset_scroll()
	await settle()

# The original height-matched layout brings the two real controls
# into overlap at a portrait-like logical width; no fake blocker.
func test_source_canvas_order(board, q: Control) -> void:
	var size_before: Vector2 = board.hud.size
	var phase_before: String = board.session.phase
	board.hud.size = Vector2(620,900)
	board._configure_source_hud()
	board.journal_slide.reset(true)
	board.session.phase = "ready"
	board._sync_source_info()
	await settle()
	var overlap: Rect2 = board.info_action.get_global_rect().intersection(q.get_global_rect())
	check(overlap.has_area() and board.info_action.visible and root.get_visible_rect().has_point(overlap.get_center()),
		"narrow source canvas overlaps action and journal inside real input surface")
	if overlap.has_area():
		point_event(Vector2(-12,-12))
		point_event(overlap.get_center())
		var hovered: Control = root.gui_get_hovered_control()
		check(hovered != null and (hovered == q or q.is_ancestor_of(hovered)),
			"actual GUI prioritizes later source MenuPanel over the covered InfoPanel action")
	check(board.watermark.get_index() < board.day_clock.get_index()
		and board.card_hover.get_index() < board.info_action.get_index()
		and board.info_action.get_index() < board.detail_panel.get_index(),
		"single Canvas preserves original relative draw and pointer order")
	point_event(Vector2(-12,-12))
	board.session.phase = phase_before
	board.hud.size = size_before
	board._configure_source_hud()
	board.journal_slide.reset(true)
	board._sync_source_info()
	await settle()

## Real locked header pointer entry must arbitrate even when its info is blank.
func test_source_group_hover(board) -> void:
	board.journal_slide.reset(true)
	await settle()
	var seen_before: Dictionary = board.session.collection.seen_items.duplicate(true)
	var quest_rows: Control = board.journal_rows.quests
	var key := "quests:Main:0"
	var group: Control = quest_rows.rows.get("group:" + key)
	check(group != null and group.is_visible_in_tree(),"actual Introduction header is visible")
	if group == null: return
	var hit: Vector2 = group.get_global_transform_with_canvas() * Vector2(24,12)
	board.info_requests.submit("older_hover",0,{"header":"Older"})
	point_event(hit)
	check(board.info_requests.requests.has("journal") and board.info_requests.current().is_empty(),
		"locked non-null QuestGroup owns a blank request over older hover")
	board._sync_source_info()
	check(not board.card_hover.visible and not board.info_action.visible,"blank owner does not draw an empty panel or action")
	board.info_requests.submit("higher",1,{"header":"Higher"})
	check(board.info_requests.current().get("header")=="Higher","blank Hover cannot mask higher priority")
	board.info_requests.submit("higher",1,{})
	check(board.info_requests.current().is_empty(),"releasing higher request restores the blank owner")
	point_event(Vector2(8,8))
	check(not board.info_requests.requests.has("journal") and board.info_requests.current().get("header")=="Older",
		"exiting the QuestGroup immediately restores its older peer")
	check(board.session.collection.seen_items==seen_before,"group hover does not mark a quest seen")
	for record in board.catalog.data.get("recipes", []):
		var fields: Dictionary = record.fields
		if board.catalog.fields(board.catalog.ref_guid(fields.get("resultingCard",{}))).is_empty(): continue
		board.session.discovered_recipes[str(fields.id)] = true
		break
	board._show_journal_tab("recipes")
	board._refresh_ledger()
	await settle()
	var recipe_rows: Control = board.journal_rows.recipes
	check(not board.ledger_visible_groups.is_empty(),"locked recipe category visible")
	if board.ledger_visible_groups.is_empty(): return
	var category: String = board.ledger_visible_groups.keys()[0]
	board.info_requests.submit("journal:recipes",0,{"header":"Own recipe request"})
	recipe_rows.meta_hover_started.emit({"journal_group":category})
	check(not board.info_requests.requests.has("journal:recipes") and board.info_requests.current().get("header")=="Older",
		"null Recipe category hover clears only its own key")
	quest_rows.meta_hover_started.emit({"journal_group":key})
	check(not board.info_requests.requests.has("journal"),"hidden QuestGroup cannot claim visible request")
	board.info_requests.submit("older_hover",0,{})

func run() -> void:
	# Godot's isolated headless runner otherwise starts with a 64×64 viewport.
	# Set the real input surface before laying out the test HUD.
	root.size = Vector2i(1440,900)
	var drain = preload("res://tests/godot/source_test_audio_drain.gd").new()
	var board = Board.new()
	board.slot_root = "user://journal-bodies"
	board.options_path = board.slot_root + "/options.json"
	board.legacy_paths.clear()
	root.add_child(board)
	await settle()
	board.set_process(false)
	# Synthetic catalog tests stop the full campaign frame, but still pump
	# the identical journal frame tick after real Viewport input.
	process_frame.connect(board._advance_journal_pointer_input)
	drain.observe_music(board.feedback.music)
	board.title_panel.hide()
	board.source_hud.show()
	board.hud.show()
	board.running = true
	board.detail_panel.show()
	var quests: Array = []
	var refs: Array = []
	var active: Array = []
	var recipes: Array = []
	for i in range(80):
		var id := "q%02d" % i
		quests.append({"guid":id,"fields":{"id":id,"title":"Quest " + id,"description":"Info " + id,"targetAmount":2,"type":3}})
		refs.append({"guid":id})
		active.append({"QuestId":id,"CurrentAmount":0})
		var rid := "r%02d" % i
		recipes.append({"guid":rid,"fields":{"id":rid,"displayName":rid,"category":0,"resultingCard":{"guid":"result"}}})
		board.session.discovered_recipes[rid] = true
	recipes.append({"guid":"late","fields":{"id":"late","displayName":"late","category":1,"resultingCard":{"guid":"result"}}})
	board.catalog.configure({"quests":quests,"recipes":recipes,"cards":[{"guid":"result","fields":{"displayName":"Output"}}]})
	board.session.catalog = board.catalog
	board.session.quest_tracker.configure(board.catalog, "Main", [{"GroupName":"Test","Quests":refs}])
	board.session.quest_tracker.restore_state({"CompletedQuests":[],"ActiveQuests":active})
	board.active_tab = "quests"
	board._refresh_ledger()
	var q: Control = board.journal_bodies.quests
	var r: Control = board.journal_bodies.recipes
	var qrows: Control = board.journal_rows.quests
	var rrows: Control = board.journal_rows.recipes
	await settle()
	check(q != r and q.motion != r.motion, "two real persistent native motion owners")
	check(board.ledger == qrows and q.visible and not r.visible, "active public reference and inactive participation")
	await test_native_scroll(board,q,r)
	await test_captured_release(board,q,qrows)
	await test_source_canvas_order(board,q)
	q.motion.position = 120
	check(q.motion.position == 120, "quest nonzero scroll established")
	board._show_journal_tab("recipes")
	await settle()
	check(board.ledger == rrows and r.motion.position == 0, "first recipe entry never inherits quest scroll")
	r.motion.position = 240
	check(r.motion.position == 240, "distinct recipe nonzero scroll established")
	for i in range(3):
		board._show_journal_tab("quests")
		await settle()
		check(board.ledger == qrows and q.motion.position == 120, "quest identity and scroll restored")
		board._show_journal_tab("recipes")
		await settle()
		check(board.ledger == rrows and r.motion.position == 240, "recipe identity and scroll restored")
	var hidden_quest: Dictionary = board.session.quest_tracker.active_quests[0]
	hidden_quest.current_amount = 2
	board.session.quest_tracker.quest_completed.emit(hidden_quest)
	await settle()
	check(not q.visible and qrows.get_parsed_text().contains("Quest " + hidden_quest.id + " √"), "hidden quest completion updates its own body through event")
	check(q.motion.position == 120 and r.motion.position == 240, "hidden quest rebuild preserves independent offsets")
	rrows.meta_hover_started.emit("r00")
	check(board.info_requests.current().get("header", "") == "Recipe: Output", "recipe owns hover descriptor")
	qrows.meta_hover_ended.emit("q00")
	check(board.info_requests.current().get("header", "") == "Recipe: Output", "hidden quest exit cannot erase recipe request")
	qrows.meta_hover_started.emit("q00")
	check(not board.session.collection.seen_items.has("q00"), "hidden metadata cannot mark quest read")
	board._show_journal_tab("quests")
	qrows.meta_hover_started.emit("q00")
	rrows.meta_hover_ended.emit("r00")
	check(board.info_requests.current().get("header", "") == "Quest q00", "hidden recipe exit cannot erase quest request")
	board.ledger_expansion["recipes:1"] = false
	board.session.discovered_recipes.late = true
	board._collection_changed()
	await settle()
	await settle()
	check(board.ledger == qrows and not r.visible, "hidden discovery never switches public active body")
	check(board.journal_body_state.recipes.groups.has("recipes:1"), "hidden discovery creates its category header")
	check(not board.journal_body_state.recipes.ids.has("late"), "discovery respects collapsed category")
	board.ledger_expansion["recipes:1"] = true
	board._refresh_ledger()
	await settle()
	check(board.journal_body_state.recipes.ids.has("late"), "hidden expansion retains discovery for later entry")
	check(r.motion.position == 240, "hidden content refresh preserves owned recipe scroll")
	board._show_journal_tab("recipes")
	await settle()
	check(board.ledger == rrows and board.ledger_visible_ids.has("late"), "reentry exposes current hidden content")
	board.detail_panel.hide()
	await settle()
	board.detail_panel.show()
	await settle()
	check(r.motion.position == 240 and q.motion.position == 120, "drawer hide/show preserves both offsets")
	board.ledger_session_id = 0 # same boundary used by _enter_source_scene/start_new.
	board._refresh_ledger()
	await settle()
	check(q.motion.position == 0 and r.motion.position == 0, "fresh source view lifecycle resets both scrolls")
	check(board.ledger_expansion.is_empty() and board.info_requests.requests.is_empty(), "fresh view clears expansion and both hover owners")
	board._show_journal_tab("invalid")
	check(board.active_tab == "recipes" and board.ledger == rrows, "unknown tab cannot corrupt active compatibility reference")
	if board.catalog.load_file() == OK:
		board.data_error = OK
		board.start_new()
		board.set_process(false)
		await settle()
		check(board.active_tab == "quests" and board.ledger == qrows, "real start-new source lifecycle restores authored Quests selection")
		check(q.motion.position == 0 and r.motion.position == 0, "real start-new clears both native offsets")
		await test_source_group_hover(board)
		check(q.source_scroll_bound and r.source_scroll_bound and qrows.row_padding==Vector4(20,10,20,10)
			and rrows.row_padding==qrows.row_padding and qrows.row_spacing==10.0 and rrows.row_spacing==10.0,
			"both live source panels resolve separate exact viewport and content chains")
		# Exercise the real Board _process entry with initialized original data as well.
		board._show_journal_tab("quests")
		board.journal_slide.reset(true)
		await settle()
		var owned_key: String = board.ledger_visible_groups.keys()[0]
		var owned_row: Control = qrows.rows["group:"+owned_key]
		var owned_point := owned_row.get_global_transform_with_canvas()*Vector2(4,4)
		process_frame.disconnect(board._advance_journal_pointer_input)
		board.set_process(true)
		point_event(owned_point,MOUSE_BUTTON_RIGHT)
		point_event(owned_point,MOUSE_BUTTON_RIGHT,false)
		await settle()
		check(not board.ledger_expansion.get(owned_key,true),"initialized source Board advances framed Journal clicks in its real process")
		board.set_process(false)
		print("Journal body private lifecycle: verified")
	else:
		print("SKIP: private source start-new lifecycle unavailable")
	drain.observe_music(board.feedback.music)
	board.free()
	check(await drain.wait_after_teardown(self), "native audio teardown drained")
	print("Journal body ownership: %d/%d checks passed" % [checks-failures, checks])
	quit(0 if failures == 0 else 1)
