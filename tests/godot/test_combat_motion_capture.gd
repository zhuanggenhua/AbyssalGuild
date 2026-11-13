extends SceneTree
const P = preload("res://scripts/ui/combat_presentation.gd")
const C = preload("res://scripts/model/catalog.gd")
const S = preload("res://scripts/model/game_session.gd")
const Codec = preload("res://scripts/model/save_codec.gd")
var failures := 0
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var c = C.new()
	c.configure({"cards":[{"guid":"p","script_class":"CardDefinition","fields":{"id":"p","category":2,"faction":1,"combatType":1,"maxHealth":100,"attack":1}},{"guid":"m","script_class":"CardDefinition","fields":{"id":"m","category":9,"faction":2,"combatType":1,"maxHealth":100}}]})
	var s = S.new(); s.configure(c,123)
	var a: int = s.spawn_card("p",Vector2(12,13))
	var b: int = s.spawn_card("m",Vector2(19,20))
	var id: int = s.combat.start_combat([a],[b])
	s.combat.tasks[id].progress[a] = 1000
	s.combat.resolve_turn(id)
	var task: Dictionary = s.combat.tasks[id]
	var p = P.new()
	var poses := {a:Vector3(2,3,4),b:Vector3(8,5,9)}
	var homes := {a:Vector3(-5,0,7)}
	var sampler := func(key: int) -> Vector3:
		var active: Variant = p.sample_actor(key)
		return active if active is Vector3 else poses[key]
	var home := func(key: int) -> Vector3: return homes[key]
	var before_position: Vector2 = s.cards[a].position
	var before_rng: int = s.rng.state
	task.visual_motion = p.capture(id,task.execution,sampler,home,.3)
	check(task.visual_motion.start == Vector3(2,3,4) and task.visual_motion.finish == Vector3(8,5.05,9),"attack captures actual nonzero/high transforms")
	poses[b] = Vector3(90,50,90)
	p.advance(.15)
	var mid: Vector3 = p.sample_actor(a)
	check(mid.is_equal_approx(Vector3(6.5,5.671875,7.75)),"moving defender does not retarget nested jump")
	check(s.cards[a].position == before_position and s.rng.state == before_rng,"capture and sampling never mutate model target or RNG")
	task.execution.remaining = .15
	var saved := Codec.capture(s)
	check(saved.session.combat.tasks[0].execution.size() == 7,"execution schema unchanged")
	check(saved.session.combat.tasks[0].visual_motion.start == [2.0,3.0,4.0],"serialize full 3D geometry")
	var restored = S.new(); restored.configure(c,7)
	check(Codec.restore(restored,saved).ok,"new optional geometry restores")
	var replay = P.new()
	var pose: Dictionary = replay._motion_pose(id,restored.combat.tasks[id],restored.combat.tasks[id].execution)
	check(pose.actor.is_equal_approx(mid),"save replay exactly retains captured high endpoints")
	var legacy: Dictionary = saved.duplicate(true)
	legacy.session.combat.tasks[0].erase("visual_motion")
	check(Codec.restore(restored,legacy).ok,"old seven-field execution remains compatible")
	var stable: String = JSON.stringify(Codec.capture(restored))
	for mutation in ["nan","short","phase","actor","type","duration","extra","orphan"]:
		var bad: Dictionary = saved.duplicate(true)
		var row: Dictionary = bad.session.combat.tasks[0]
		match mutation:
			"nan": row.visual_motion.start[1] = NAN
			"short": row.visual_motion.finish = [1,2]
			"phase": row.visual_motion.phase = "return"
			"actor": row.visual_motion.actor = b
			"type": row.visual_motion.combat_type = 3
			"duration": row.visual_motion.duration = .5
			"extra": row.visual_motion.extra = 1
			"orphan": row.erase("execution")
		check(not Codec.restore(restored,bad).ok,"reject invalid geometry " + mutation)
		check(JSON.stringify(Codec.capture(restored)) == stable,"failed stage atomic " + mutation)
	# Clock advance is independent of simulation pause and reaches endpoint before return capture.
	s.paused = true
	p.advance(.15)
	task.execution.phase = "return"; task.execution.remaining = .3
	task.visual_motion = p.capture(id,task.execution,sampler,home,.3)
	check(task.visual_motion.start.is_equal_approx(Vector3(8,5.05,9)) and task.visual_motion.finish == homes[a],"return captures completed travel and current layout once")
	homes[a] = Vector3(100,0,100)
	p.advance(.3)
	check(p.sample_actor(a).is_equal_approx(Vector3(-5,0,7)),"return endpoint fixed while layout moves under pause")
	var return_save := Codec.capture(s)
	check(Codec.restore(restored,return_save).ok,"return geometry saves independently of paused clock")
	var parent := Node3D.new(); root.add_child(parent)
	p.sync({}, {}, {}, parent)
	check(p.sample_actor(a) == null,"canceled task removes sampled motion")
	p.reset(); replay.reset(); parent.queue_free()
	await process_frame
	print("Combat motion capture: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
