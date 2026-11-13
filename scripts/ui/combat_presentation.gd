extends RefCounted
## Read-only model adapter. All motion is reconstructed from execution snapshots.
const SourceTween = preload("res://scripts/ui/source_tween.gd")
var projectiles: Dictionary = {}
var visual_assets
var scene_name: String = "Main"
var hurts: Dictionary = {}
var shake_age: float = INF
var affected: Dictionary = {}
var motions: Dictionary = {}

static func view_position(point: Vector2, height: float = 0.12) -> Vector3:
	return Vector3(point.x, height, -point.y)

static func jump(from: Vector3, to: Vector3, ratio: float) -> Vector3:
	return SourceTween.jump_one(from, to, 1.0, 1.0, ratio)

static func execution_pose(execution: Dictionary, home: Vector3, duration: float) -> Dictionary:
	var phase: String = str(execution.get("phase", ""))
	if phase not in ["travel", "return"] or duration <= 0: return {}
	var ranged: bool = int(execution.combat_type) in [2, 3]
	var start: Vector3 = view_position(execution.attacker_position)
	var target: Vector3 = view_position(execution.defender_position) + Vector3.UP * 0.05
	if phase == "return":
		return {} if ranged else {"actor": jump(target, home, 1.0 - float(execution.remaining) / 0.3)}
	var t: float = clampf(1.0 - float(execution.remaining) / duration, 0, 1)
	return {"projectile": (start + Vector3.UP * 0.05).lerp(target, t), "direction": target - start} if ranged else {"actor": jump(start, target, t)}

## Event-boundary capture. Samplers return current Godot-space WORLD positions.
## A captured endpoint is immutable even if its target/layout moves later.
func capture(task_id: int, execution: Dictionary, pose_sampler: Callable, home_sampler: Callable, duration: float) -> Dictionary:
	var actor: int = int(execution.actor)
	var phase: String = str(execution.phase)
	var start: Vector3 = pose_sampler.call(actor)
	var finish: Vector3
	if phase == "travel":
		finish = pose_sampler.call(int(execution.target)) + Vector3.UP * 0.05
		if int(execution.combat_type) in [2,3]: start += Vector3.UP * 0.05
	else:
		finish = home_sampler.call(actor)
	var record := {"actor":actor, "phase":phase, "combat_type":int(execution.combat_type), "start":start, "finish":finish, "duration":duration}
	motions[task_id] = record.duplicate(true)
	motions[task_id]["age"] = 0.0
	return record

func sample_actor(id: int) -> Variant:
	for record in motions.values():
		if int(record.actor) == id and int(record.combat_type) not in [2,3]:
			return SourceTween.jump_one(record.start,record.finish,1,record.duration,record.age)
	return null

func _motion_pose(task_id: int, task: Dictionary, execution: Dictionary) -> Dictionary:
	if not motions.has(task_id) and task.has("visual_motion"):
		motions[task_id] = task.visual_motion.duplicate(true)
	var record: Dictionary = motions.get(task_id,{})
	if record.is_empty() or record.phase != execution.phase or int(record.actor) != int(execution.actor): return {}
	record.age = clampf(float(record.duration) - float(execution.remaining), 0, record.duration)
	if int(record.combat_type) in [2,3]:
		return {"projectile":record.start.lerp(record.finish,record.age / record.duration), "direction":record.finish-record.start} if record.phase == "travel" else {}
	return {"actor":SourceTween.jump_one(record.start,record.finish,1,record.duration,record.age)}

func hit(id: int, descriptor: Dictionary) -> void:
	if descriptor.is_empty() or not descriptor.flash.enabled: return
	hurts[id] = {"age": 0.0, "started": false}
	shake_age = 0.0

func advance(real_delta: float) -> void:
	if not is_finite(real_delta) or real_delta < 0: return
	shake_age += real_delta
	for record in motions.values(): record.age = minf(record.duration, float(record.get("age",0)) + real_delta)
	for id in hurts:
		hurts[id].age += real_delta
		# Keep completed states until sync writes exact endpoint values.

func camera_offset() -> Vector2:
	if shake_age >= 0.3: return Vector2.ZERO
	var decay: float = 1.0 - shake_age / 0.3
	# Deterministic presentation-only noise substitute, never session RNG.
	return Vector2(sin(shake_age * 113.0), sin(shake_age * 157.0)) * 0.1 * decay

func sync(tasks: Dictionary, views: Dictionary, durations: Dictionary, parent: Node3D) -> void:
	var live: Dictionary = {}
	for id in motions.keys():
		if not tasks.has(id) or tasks[id].get("execution", {}).get("phase", "") not in ["travel", "return"]: motions.erase(id)
	for id in tasks:
		var execution: Dictionary = tasks[id].get("execution", {})
		if execution.is_empty() or not views.has(execution.actor): continue
		var actor: Node3D = views[execution.actor]
		var pose: Dictionary = _motion_pose(id, tasks[id], execution)
		# Legacy saves have no actual captured 3D geometry. Preserve old recovery only.
		if pose.is_empty() and not tasks[id].has("visual_motion") and not motions.has(id):
			pose = execution_pose(execution, actor.position, float(durations.get(int(execution.combat_type), 0.3)))
		if pose.has("actor"): actor.global_position = pose.actor
		if pose.has("projectile"):
			live[id] = true
			if not projectiles.has(id):
				var node: Node3D
				if visual_assets != null and visual_assets.has_method("create_projectile"):
					node = visual_assets.create_projectile(int(execution.combat_type), scene_name)
				if node == null:
					node = MeshInstance3D.new()
					var mesh := SphereMesh.new()
					mesh.radius = 0.06
					mesh.height = 0.12
					(node as MeshInstance3D).mesh = mesh
					var material := StandardMaterial3D.new()
					material.albedo_color = Color(0.4,0.65,1) if int(execution.combat_type) == 3 else Color(1,0.8,0.3)
					material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
					(node as MeshInstance3D).material_override = material
				parent.add_child(node)
				projectiles[id] = node
			projectiles[id].global_position = pose.projectile
			# Sprite source is XY-facing; reflect flight direction into the Godot board.
			if projectiles[id] is Sprite3D:
				var direction: Vector3 = pose.direction
				direction.y = 0
				if direction.length_squared() > 0.000001:
					projectiles[id].basis = Basis.looking_at(direction.normalized(), Vector3.UP) * Basis(Vector3.RIGHT, -PI / 2.0)
	for id in projectiles.keys():
		if not live.has(id):
			projectiles[id].queue_free()
			projectiles.erase(id)
	for id in hurts.keys():
		if not views.has(id):
			hurts.erase(id)
			affected.erase(id)
			continue
		var view: Node3D = views[id]
		var state: Dictionary = hurts[id]
		var age: float = state.age
		if age < 0.05: continue
		if not state.started:
			state.started = true
			state.flash_base = _read_flash(view)
			state.flash_done = false
			state.rotation_base = view.rotation
			# Reflect source Z: axial rotations about X/Y change sign.
			state.punch = SourceTween.punch_plan(Vector3(0, -deg_to_rad(15.0), 0), 0.25, 25)
		var flash: float = float(state.flash_base)
		if age <= 0.15:
			flash = lerpf(flash, 1.0, SourceTween.out_quad((age - 0.05) / 0.1))
		elif age < 0.25:
			flash = lerpf(flash, 1.0, SourceTween.out_quad((0.25 - age) / 0.1))
		if not state.flash_done and view.has_method("set_hurt_flash"):
			view.set_hurt_flash(flash)
			if age >= 0.25: state.flash_done = true
		view.rotation = SourceTween.punch_sample(state.punch, state.rotation_base, age - 0.05)
		affected[id] = view
		if age >= 0.3: hurts.erase(id)

static func _read_flash(view: Node3D) -> float:
	for property in view.get_property_list():
		if property.name == "hurt_flash": return float(view.get("hurt_flash"))
	return 0.0

func reset() -> void:
	for node in projectiles.values():
		if is_instance_valid(node): node.queue_free()
	for view in affected.values():
		if is_instance_valid(view):
			view.rotation = Vector3.ZERO
			if view.has_method("set_hurt_flash"): view.set_hurt_flash(0)
	projectiles.clear()
	motions.clear()
	affected.clear()
	hurts.clear()
	shake_age = INF
