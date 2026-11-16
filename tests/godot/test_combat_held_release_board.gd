extends SceneTree
## Private source fixtures. Native input/frame adapter assertions, not GPU parity.
const Board = preload("res://scripts/ui/board.gd")
const Layout = preload("res://scripts/model/board_layout.gd")
const AudioDrain = preload("res://tests/godot/source_test_audio_drain.gd")
var checks := 0
var failures := 0
func check(ok: bool, message: String) -> void:
	checks += 1
	if not ok: failures += 1; printerr("FAIL: ",message)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var b = Board.new()
	var drain := AudioDrain.new()
	var temp := "user://held-flee-%s" % Time.get_ticks_usec()
	b.slot_root=temp+"/slots"; b.options_path=temp+"/options.json"; b.legacy_paths.clear()
	root.add_child(b); await process_frame
	drain.observe_music(b.feedback.music)
	if b.data_error != OK: b.free(); quit(1); return
	b.start_new(); b.set_process(false); b.vendor_unlock.cancel()
	var s=b.session
	var guids: Dictionary = {1:"",2:"",3:"",4:""}
	for entry in b.catalog.data.cards:
		var f: Dictionary = entry.fields
		var type := int(f.get("combatType",0))
		if int(f.get("category",0)) == 2 and int(f.get("faction",0)) == 1 and type in [1,2,3]: guids[type]=entry.guid
		elif int(f.get("category",0)) == 9 and int(f.get("faction",0)) == 2: guids[4]=entry.guid
	for kind in [2,3]:
		for id in s.cards.keys(): s._remove_card(id)
		b._refresh()
		s.spawn_target_selector=Callable(); s.spawn_layout_resolver=Callable()
		var actor: int=s.spawn_card(guids[kind],Vector2(-2,0),-1,{"refuse_attach":true})
		var foe: int=s.spawn_card(guids[4],Vector2(0,0),-1,{"refuse_attach":true})
		var ally: int=s.spawn_card(guids[1],Vector2(4,0),-1,{"refuse_attach":true})
		b._refresh()
		var task_id: int=s.combat.start_combat([actor,ally],[foe])
		b._refresh()
		s.cards[foe].health=10000
		s.combat.tasks[task_id].progress[actor]=50.0
		s.combat.resolve_turn(task_id)
		b._sync_views()
		var task: Dictionary=s.combat.tasks[task_id]
		var execution: Dictionary=task.execution.duplicate(true)
		var flights: Dictionary=b.combat_presentation.projectile_flights.duplicate(true)
		var rng_before: int=s.rng.state
		var start: Vector3=b.views[ally].global_position
		var press: Vector2=b.camera.unproject_position(Vector3(start.x-.13,0,start.z+.09))
		b._begin_card_press({"card_id":ally},press)
		check(b._combat_hold.get("id",-1)==ally,"unrelated nonterminal attacker captures source hold")
		check(b.views[ally].global_position==start,"combat PointerDown does not force immediate Update")
		var pointer_ground: Vector2=b._board_point(press)
		var desired_ground:=Vector2(s.board_bounds.end.x+5,s.board_bounds.end.y+5)
		var motion:=InputEventMouseMotion.new()
		motion.position=b.camera.unproject_position(Vector3(desired_ground.x,0,-desired_ground.y))
		b._input(motion)
		check(b.views[ally].global_position==start,"motion callback only records pointer until source frame")
		b._advance_running_frame(0.0)
		var raw:=Vector2(start.x,-start.z)+b._board_point(motion.position)-pointer_ground
		var expected: Vector2=b._clamp_stack_position(ally,raw,false)
		var pose: Vector3=b.views[ally].global_position
		check(Vector2(pose.x,-pose.z).is_equal_approx(expected),"held singleton clamps actual offset to board bounds")
		check(is_equal_approx(pose.y,.1),"authored held height")
		check(expected.y>s.board_bounds.end.y-s.board_top_margin-b._card_footprint(ally).y*.5,"held may enter top margin before settlement")
		var observed: Array=[false]
		s.combat.flee_layout_updater=func(id):
			check(s.cards[ally].stack_id==-1 and not s.combat.membership.has(ally),"Flee callback before departing stack registration")
			check(s.cards[ally].position.is_equal_approx(expected),"Flee observes last held position, not enforced header target")
			b._combat_flee_layout(id)
			observed[0]=true
		# Unprocessed motion and release point are both inside: neither is an Update.
		motion.position=b.camera.unproject_position(Vector3(start.x,0,start.z))
		b._input(motion)
		var up:=InputEventMouseButton.new()
		up.button_index=MOUSE_BUTTON_LEFT; up.pressed=false; up.position=motion.position
		b._input(up)
		check(observed[0] and not s.combat.membership.has(ally),"release uses previous actual outside pose despite newer event coordinates")
		var settled: Vector2=b._clamp_stack_position(ally,expected,true)
		check(s.card_target_position(ally).is_equal_approx(settled),"placement rules applied only after Flee")
		check(task.execution==execution and b.combat_presentation.projectile_flights==flights,"captured ranged action and projectile clock unchanged")
		check(s.rng.state==rng_before,"no replacement RNG consumption")
		check(b._combat_hold.is_empty(),"capture consumed at release")
		s.combat.flee_layout_updater=b._combat_flee_layout
	b.queue_free(); await process_frame
	check(await drain.wait_after_teardown(self),"audio drained")
	if failures==0: print("Combat held release Board: %d/%d passed" % [checks,checks])
	quit(1 if failures else 0)
