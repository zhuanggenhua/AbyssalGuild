extends SceneTree
const Catalog = preload("res://scripts/model/catalog.gd")
const Session = preload("res://scripts/model/game_session.gd")
const P = preload("res://scripts/ui/combat_presentation.gd")
var failures := 0
var checks := 0
func check(ok: bool, label: String) -> void:
	checks += 1
	if not ok: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var stage := Node3D.new()
	root.add_child(stage)
	var actor := Node3D.new(); stage.add_child(actor)
	var defender := Node3D.new(); stage.add_child(defender)
	var views := {1:actor,2:defender}
	var points := {1:Vector3(2,3,4),2:Vector3(8,5,9)}
	var sampler := func(id: int) -> Vector3: return points[id]
	var home := func(_id: int) -> Vector3: return Vector3.ZERO
	for type in [2,3]:
		var p = P.new()
		var ex := {"actor":1,"target":2,"phase":"travel","remaining":0.6,"combat_type":type}
		var motion: Dictionary = p.capture(5,ex,sampler,home,.6)
		var tasks := {5:{"execution":ex,"visual_motion":motion}}
		var before: Dictionary = tasks.duplicate(true)
		p.sync(tasks,views,{type:.6},stage)
		check(p.projectiles.size()==1,"只创建一个飞行节点")
		var projectile: Node3D = p.projectiles.get(5)
		p.advance(.2); ex.remaining=.4; p.sync(tasks,views,{type:.6},stage)
		var expected: Vector3 = motion.start.lerp(motion.finish,1.0/3.0)
		check(projectile.global_position.is_equal_approx(expected),"线性独立时间推进")
		points[2]=Vector3(99,99,99)
		p.sync(tasks,views,{type:.6},stage)
		check(projectile.global_position.is_equal_approx(expected),"目标移动不改变已发射终点")
		tasks.clear()
		p.sync(tasks,{}, {}, stage)
		check(p.projectiles.get(5)==projectile and not projectile.is_queued_for_deletion(),"取消旧任务不销毁飞行节点")
		p.advance(.2); p.sync({}, {}, {}, stage)
		check(projectile.global_position.is_equal_approx(motion.start.lerp(motion.finish,2.0/3.0)),"无任务及卡牌时仍继续飞行")
		check(p.projectiles.size()==1,"反复 sync 不重复创建")
		p.advance(.21); p.sync({}, {}, {}, stage)
		check(projectile.is_queued_for_deletion() and p.projectiles.is_empty(),"原定时长结束自动释放")
		check(projectile.global_position.is_equal_approx(motion.finish),"释放前到达原终点")
		check(tasks.is_empty() and before[5].execution.phase=="travel","显示不制造伤害或修改任务")
		p.reset()
		# 当发射和合并发生于首次 sync 之间，已捕获 flight 仍应产生独立节点。
		points[2]=Vector3(8,5,9)
		p.capture(8,ex,sampler,home,.6)
		p.sync({}, {}, {}, stage)
		check(p.projectiles.has(8),"首次 sync 前取消也不吞掉已经发射的视觉")
		p.reset()
		check(p.projectiles.is_empty(),"场景 reset 显式清理独立飞行")
		await process_frame
		# 旧任务和替代任务在屏幕上可以有不同的同时在途射弹。
		ex.remaining=.6
		var first: Dictionary = p.capture(20,ex,sampler,home,.6)
		p.sync({20:{"execution":ex,"visual_motion":first}},views,{},stage)
		p.advance(.1)
		var second: Dictionary = p.capture(21,ex,sampler,home,.6)
		var current := {21:{"execution":ex,"visual_motion":second}}
		p.sync(current,views,{},stage)
		check(p.projectiles.size()==2,"合并替代任务不吞掉旧射弹")
		p.advance(.5); p.sync(current,views,{},stage)
		check(not p.projectiles.has(20) and p.projectiles.has(21),"按各自发射时间退休")
		p.advance(.11); p.sync(current,views,{},stage)
		check(p.projectiles.is_empty(),"全部独立计时结束")
		p.sync(current,views,{},stage)
		check(p.projectiles.is_empty(),"过时 travel 快照不能复活已完成射弹")
		ex.remaining=.6
		var third: Dictionary = p.capture(21,ex,sampler,home,.6)
		p.sync({21:{"execution":ex,"visual_motion":third}},views,{},stage)
		check(p.projectiles.has(21),"同任务下一次真实发射解除完成标记")
		p.reset()
		# 同一任务在前个视觉完成前再次 capture，也不能吞掉旧实例。
		p.capture(40,ex,sampler,home,.6)
		p.sync({}, {}, {}, stage)
		var older: Node3D = p.projectiles.get(40)
		p.advance(.2)
		p.capture(40,ex,sampler,home,.6)
		p.sync({}, {}, {}, stage)
		check(p.projectiles.size()==2 and p.projectiles.get(40)!=older,"同任务两次发射保留独立实例")
		p.advance(.4); p.sync({}, {}, {}, stage)
		check(older!=null and older.is_queued_for_deletion() and p.projectiles.size()==1,"同任务旧实例按自己的时长退出")
		p.reset()
		# 保存恢复有 geometry 时以剩余时间初始化一次，再独立运行。
		ex.remaining=.3
		var restored := {31:{"execution":ex,"visual_motion":first}}
		p.sync(restored,views,{},stage)
		var restored_node: Node3D = p.projectiles.get(31)
		check(restored_node != null and restored_node.global_position.is_equal_approx(first.start.lerp(first.finish,.5)),"恢复记录初始化已过时间")
		p.advance(.1); p.sync({}, {}, {}, stage)
		check(restored_node.global_position.is_equal_approx(first.start.lerp(first.finish,2.0/3.0)),"恢复后取消仍保留剩余视觉")
		p.reset()
		check(restored_node.is_queued_for_deletion(),"世界销毁清理恢复射弹")
		await process_frame
	await model_merge_case(stage,views)
	stage.free()
	print("Combat projectile lifetime: %s (%d checks)" % ["PASS" if failures==0 else "FAIL",checks])
	quit(0 if failures==0 else 1)


func model_merge_case(stage: Node3D, views: Dictionary) -> void:
	var c = Catalog.new()
	c.configure({"cards":[
		{"guid":"r","script_class":"CardDefinition","fields":{"id":"r","category":2,"faction":1,"combatType":2,"maxHealth":100}},
		{"guid":"m","script_class":"CardDefinition","fields":{"id":"m","category":9,"faction":2,"maxHealth":100}}],
		"scenes":[{"name":"Main","documents":[{"script_class":"CombatManager","fields":{"arrowProjectile":{"guid":"arrow"}}}]}],
		"referenced_prefabs":[{"guid":"arrow","documents":[{"script_class":"CombatProjectile","fields":{"duration":0.5}}]}]})
	var s = Session.new()
	s.configure(c,123)
	var a: int = s.spawn_card("r")
	var b: int = s.spawn_card("m")
	var old: int = s.combat.start_combat([a],[b])
	var p = P.new()
	var hits := []
	var point := func(id: int) -> Vector3: return Vector3(float(id)*2,0.12,0)
	var callback := func(kind: String, payload: Dictionary) -> void:
		if kind=="combat_hit": hits.append(payload.duplicate(true))
		if kind=="combat_attack_started":
			var task: Dictionary = s.combat.tasks[payload.combat_id]
			task.visual_motion = p.capture(payload.combat_id,task.execution,point,point,payload.duration)
	s.event_occurred.connect(callback)
	s.combat.tasks[old].progress[a]=1000
	s.combat.resolve_turn(old)
	check(s.combat.tasks[old].execution.remaining==0.5,"当前场景使用原序列化半秒而非 C# 回退时长")
	p.sync(s.combat.tasks,views,{},stage)
	var shot: Node3D = p.projectiles.get(old)
	check(shot!=null and shot.global_position.is_equal_approx(point.call(a)+Vector3.UP*.05),"发射帧不追补此前 elapsed")
	p.advance(.2)
	s.combat.tick(0,.2)
	p.sync(s.combat.tasks,views,{},stage)
	check(shot.global_position.is_equal_approx((point.call(a)+Vector3.UP*.05).lerp(point.call(b)+Vector3.UP*.05,.4)),"半秒射弹 .2 秒原端点插值")
	var replacement: int = s.combat.merge_combats([old])
	check(replacement>old and not s.combat.tasks.has(old),"真实模型 merge 删除旧任务")
	var health: int = s.cards[b].health
	var rng_state: int = s.rng.state
	p.sync(s.combat.tasks,views,{},stage)
	check(p.projectiles.get(old)==shot and not shot.is_queued_for_deletion(),"实际 merge 保留在途视觉")
	p.advance(.3)
	s.combat.tick(0,.3)
	p.sync(s.combat.tasks,views,{},stage)
	check(shot.is_queued_for_deletion() and p.projectiles.is_empty(),"旧射弹在 .5 秒视觉退休")
	check(hits.is_empty() and s.cards[b].health==health and s.rng.state==rng_state,"已取消协程绝不产生迟到伤害或随机消耗")
	check(s.combat.tasks[replacement].timer==1.0,"视觉退出不唤醒替代战斗")
	s.event_occurred.disconnect(callback)
	p.reset()
	await process_frame
