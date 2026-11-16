extends SceneTree
const Board = preload("res://scripts/ui/board.gd")
const AudioDrain = preload("res://tests/godot/source_test_audio_drain.gd")
var checks := 0
var failures := 0

func _initialize() -> void: call_deferred("run")
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		push_error(label)

func run() -> void:
	var board = Board.new()
	var drain := AudioDrain.new()
	board.slot_root = "user://private-active-resize-merge-%s" % Time.get_ticks_usec()
	board.legacy_paths.clear()
	root.add_child(board)
	await process_frame
	drain.observe_music(board.feedback.music)
	check(board.data_error == OK,"锁定原始数据已导入")
	if board.data_error != OK: board.free(); quit(1); return
	board.start_new()
	board.set_process(false)
	board.vendor_unlock.cancel()
	var s = board.session
	var guids := {1:"",2:"",3:"",4:""}
	for entry in board.catalog.data.cards:
		var f: Dictionary = entry.fields
		var n: int = int(f.get("combatType",0))
		if f.get("category",0)==2 and f.get("faction",0)==1 and n in [1,2,3]:
			guids[n]=entry.guid
		elif f.get("category",0)==9 and f.get("faction",0)==2:
			guids[4]=entry.guid
	for n in [1,2,3,4]:
		check(not guids[n].is_empty(),"原卡完整")
		if guids[n].is_empty(): board.free(); quit(1); return
	var original_selector: Callable = s.combat.resize_overlap_selector
	var center_adapter: Callable = s.combat.merge_center_sampler
	for ranged in [2,3]:
		for phase in ["travel","return"]:
			for guard in ["valid","moved","changed","neighbor_active","direct","model_drag"]:
				for id in s.cards.keys(): s._remove_card(id)
				board._refresh()
				var actor: int = spawn(board,guids[ranged],Vector2(-3,-1.2))
				var target: int = spawn(board,guids[4],Vector2(-3,-0.8))
				var other: int = spawn(board,guids[1],Vector2(3,-1.2))
				var independent: int = spawn(board,guids[4],Vector2(3,-0.8))
				var left: int = s.combat.start_combat([actor],[target])
				var right: int = s.combat.start_combat([other],[independent])
				if left < 0 or right < 0 or left == right:
					check(false,"fixture 必须开始两个分隔的战斗")
					break
				board._refresh()
				s.combat.tasks[left].progress[actor] = 100.0
				s.combat.resolve_turn(left)
				var p = board.combat_presentation
				p.advance(0.2 if phase=="travel" else 0.5)
				s.combat.tick(0,0.2 if phase=="travel" else 0.5)
				board._sync_views()
				var shot: Node3D = p.projectiles.get(left)
				check(phase=="return" or (shot is Sprite3D and shot.texture!=null),"测试实际原 UI prefab 射弹或已结束等待")
				var travel: Dictionary = s.combat.tasks[left].execution.duplicate(true)
				var motion: Dictionary = s.combat.tasks[left].visual_motion.duplicate(true)
				var old_pos: Vector3 = shot.global_position if is_instance_valid(shot) else Vector3.ZERO
				var hp: int = s.cards[target].health
				var entry_notifications: Array = []
				var control_poses := {other:board.views[other].position,independent:board.views[independent].position}
				var joiners: Array = []
				for i in range(10):
					joiners.append(spawn(board,guids[1],Vector2(0,-3)))
				board._sync_views()
				var all_ids: Array = [actor,target]+joiners
				var sampler_seen: Array = []
				var events := func(kind: String,payload: Dictionary):
					if kind=="combat_hit": entry_notifications.append(payload)
				s.event_occurred.connect(events)
				s.combat.resize_overlap_selector = func(task_id: int) -> Array:
					var overlaps: Array
					if guard=="direct":
						board._sync_combat_layouts()
						board._combat_resize_native_slots(task_id)
						overlaps = [right]
					else:
						overlaps = original_selector.call(task_id)
					sampler_seen.append(task_id)
					check(task_id==left and right in overlaps,"真实 resize 选出邻接战斗")
					var layout: Dictionary = board.combat_layouts[left]
					for id in all_ids:
						var slot: Vector2 = layout.positions[id]
						check(board.views[id].position.is_equal_approx(Vector3(slot.x,0,-slot.y)),"合并前真实 CardView 立即在新 slot")
					check(board.views[other].position == control_poses[other] and board.views[independent].position==control_poses[independent],"不触碰邻战节点")
					check(s.combat.tasks[left].execution==travel and s.combat.tasks[left].visual_motion==motion and (not is_instance_valid(shot) or shot.global_position==old_pos),"resize 不动战斗剩余时间、已捕获发射端点或视觉当前点")
					if guard=="moved": board.views[actor].position.x += 0.125
					if guard=="changed": s.combat.tasks[left].execution.remaining += 0.125
					if guard=="model_drag": s.combat.dragged[actor]=true
					if guard=="neighbor_active": s.combat.tasks[right]["execution"]={"phase":"death_wait"}
					return overlaps
				var center_calls: Array = []
				s.combat.merge_center_sampler = func(attackers: Array,defenders: Array,old_members: Dictionary) -> Variant:
					center_calls.append(true)
					check(old_members.has(actor) and not old_members[actor],"active merge center 仍不假定旧成员可采样")
					var expected := Vector2.ZERO
					for id in attackers+defenders:
						var at: Vector3 = board.views[id].global_position
						expected += Vector2(at.x,-at.z)
					expected /= (attackers.size()+defenders.size())
					var receipt: Variant = center_adapter.call(attackers,defenders,old_members)
					check((receipt is Vector2 and receipt.is_equal_approx(expected)) if guard=="valid" else receipt==null,
						"原生中心只接受同调用完整 resize，type=%s phase=%s guard=%s"%[ranged,phase,guard])
					check(center_adapter.call(attackers,defenders,old_members)==null,"active receipt only consumed once")
					return receipt
				check(s.combat.add_combatants(left,joiners),"真实托管 AddCombatants")
				check(sampler_seen==[left] and center_calls.size()==1 and s.combat.tasks.size()==1 and not s.combat.tasks.has(left) and not s.combat.tasks.has(right),"删除旧任务，单次合并")
				s.combat.resize_overlap_selector=original_selector
				s.combat.merge_center_sampler=center_adapter
				board._sync_views()
				if phase=="travel":
					check(p.projectiles.get(left)==shot and not shot.is_queued_for_deletion(),"已合并视觉保留")
					p.advance(0.301)
					s.combat.tick(0,0.301)
					board._sync_views()
					check(shot.is_queued_for_deletion() and shot.global_position.is_equal_approx(motion.finish),"射弹原终点自释放")
				check(s.cards[target].health==hp and entry_notifications.is_empty(),"旧任务无迟到伤害")
				s.event_occurred.disconnect(events)
				await process_frame
	board.queue_free()
	await process_frame
	check(await drain.wait_after_teardown(self),"audio drained")
	if failures==0: print("Combat ranged merge center Board: %d/%d passed"%[checks,checks])
	else: printerr("Combat ranged merge center Board FAILED: %d/%d"%[checks-failures,checks])
	quit(1 if failures else 0)

func spawn(board, guid: String, point: Vector2) -> int:
	var id: int = board.session.spawn_card(guid,point,-1,{"refuse_attach":true})
	board._set_board_card_position(id,point)
	return id
