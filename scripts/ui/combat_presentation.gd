extends RefCounted
## Read-only model adapter. All motion is reconstructed from execution snapshots.
var projectiles: Dictionary = {}
var visual_assets
var scene_name: String = "Main"
var hurts: Dictionary = {}
var shake_age: float = INF
var affected: Dictionary = {}

static func view_position(point: Vector2, height: float = 0.12) -> Vector3:
	return Vector3(point.x, height, -point.y)

static func jump(from: Vector3, to: Vector3, ratio: float) -> Vector3:
	var t: float = clampf(ratio, 0, 1)
	# Explicit approximation of DOTween DOJump easing, source power=1 and one jump.
	return from.lerp(to, t) + Vector3.UP * (4.0 * t * (1.0 - t))

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

func hit(id: int, descriptor: Dictionary) -> void:
	if descriptor.is_empty() or not descriptor.flash.enabled: return
	hurts[id] = 0.0
	shake_age = 0.0

func advance(real_delta: float) -> void:
	if not is_finite(real_delta) or real_delta < 0: return
	shake_age += real_delta
	for id in hurts:
		hurts[id] += real_delta
		if hurts[id] >= 0.25: hurts.erase(id)

func camera_offset() -> Vector2:
	if shake_age >= 0.3: return Vector2.ZERO
	var decay: float = 1.0 - shake_age / 0.3
	# Deterministic presentation-only noise substitute, never session RNG.
	return Vector2(sin(shake_age * 113.0), sin(shake_age * 157.0)) * 0.1 * decay

func sync(tasks: Dictionary, views: Dictionary, durations: Dictionary, parent: Node3D) -> void:
	for old in affected.values():
		if is_instance_valid(old):
			old.rotation = Vector3.ZERO
			if old.has_method("set_hurt_flash"): old.set_hurt_flash(0)
	affected.clear()
	var live: Dictionary = {}
	for id in tasks:
		var execution: Dictionary = tasks[id].get("execution", {})
		if execution.is_empty() or not views.has(execution.actor): continue
		var actor: Node3D = views[execution.actor]
		var pose: Dictionary = execution_pose(execution, actor.position, float(durations.get(int(execution.combat_type), 0.3)))
		if pose.has("actor"): actor.position = pose.actor
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
			projectiles[id].position = pose.projectile
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
		if not views.has(id): hurts.erase(id); continue
		var view: Node3D = views[id]
		var age: float = hurts[id]
		var flash: float = clampf((age - 0.05) / 0.1, 0, 1) if age <= 0.15 else clampf((0.25 - age) / 0.1, 0, 1)
		if view.has_method("set_hurt_flash"): view.set_hurt_flash(flash)
		view.rotation.y = deg_to_rad(15.0) * sin(age / 0.25 * TAU * 25.0) * (1.0 - age / 0.25)
		affected[id] = view

func reset() -> void:
	for node in projectiles.values():
		if is_instance_valid(node): node.queue_free()
	for view in affected.values():
		if is_instance_valid(view):
			view.rotation = Vector3.ZERO
			if view.has_method("set_hurt_flash"): view.set_hurt_flash(0)
	projectiles.clear()
	affected.clear()
	hurts.clear()
	shake_age = INF
