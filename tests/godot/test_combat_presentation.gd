extends SceneTree
const Presentation = preload("res://scripts/ui/combat_presentation.gd")
const Impact = preload("res://scripts/model/impact_feedback.gd")
class SpriteAssets extends RefCounted:
	func create_projectile(_type: int, _scene: String) -> Sprite3D: return Sprite3D.new()
class FlashView extends Node3D:
	var hurt_flash: float = 0
	func set_hurt_flash(value: float) -> void: hurt_flash = value
var checks := 0
func check(value: bool, label: String) -> void:
	checks += 1
	assert(value, label)
func _init() -> void: call_deferred("run")
func run() -> void:
	var p = Presentation.new()
	var parent := Node3D.new()
	root.add_child(parent)
	var actor = FlashView.new()
	var target = FlashView.new()
	parent.add_child(actor); parent.add_child(target)
	var views := {1: actor, 2: target}
	var execution := {"actor":1,"target":2,"phase":"travel","remaining":0.15,"combat_type":1,"attacker_position":Vector2(-2,3),"defender_position":Vector2(2,3)}
	var tasks := {5:{"execution":execution}}
	var original: Dictionary = tasks.duplicate(true)
	actor.position = Vector3(-2,0.12,-3)
	p.sync(tasks, views, {}, parent)
	check(actor.position.is_equal_approx(Vector3(1,0.916875,-3)), "half melee travel source power1 and reflected Z")
	check(tasks == original, "presentation does not mutate model snapshots")
	check(p.projectiles.is_empty(), "melee creates no projectile")
	execution.phase = "return"
	actor.position = Vector3(-4,0.12,-3)
	p.sync(tasks,views,{},parent)
	check(actor.position.is_equal_approx(Vector3(-2.5,0.873125,-3)), "return uses current layout home with source jump")
	execution.phase = "death_wait"
	actor.position = Vector3(-4,0.12,-3)
	p.sync(tasks,views,{},parent)
	check(actor.position == Vector3(-4,0.12,-3), "death wait returns to normal layout")
	execution.phase = "travel"; execution.combat_type = 2; execution.remaining = 0.3
	p.sync(tasks,views,{2:0.6},parent)
	check(p.projectiles.size() == 1 and p.projectiles[5].position.is_equal_approx(Vector3(0,0.17,-3)), "restored ranged phase reconstructs linear projectile")
	check(actor.position == Vector3(-4,0.12,-3), "ranged actor remains home")
	p.sync(tasks,views,{2:0.6},parent)
	check(p.projectiles.size() == 1, "refresh never duplicates projectile")
	execution.phase = "return"
	p.sync(tasks,views,{2:0.6},parent)
	check(p.projectiles.is_empty(), "impact removes projectile during ranged return")
	p.hit(2,Impact.describe(1,{"type":"normal","damage":1}))
	p.advance(0.1)
	p.sync({},views,{},parent)
	check(is_equal_approx(target.hurt_flash,0.75), "source flash delay then ascending leg")
	check(p.camera_offset().length() <= 0.15 and p.camera_offset() != Vector2.ZERO, "bounded additive shake independent of gameplay RNG")
	p.hit(2,Impact.describe(1,{"type":"normal","damage":1}))
	check(p.hurts[2].age == 0, "later hurt replaces prior timeline")
	p.advance(0.2); p.sync({},views,{},parent)
	check(is_equal_approx(target.hurt_flash,0.9375), "source descending flash leg")
	p.advance(0.1); p.sync({},views,{},parent)
	check(is_equal_approx(target.hurt_flash,0.75), "expired replacement returns to captured residual flash")
	check(p.camera_offset() == Vector2.ZERO, "shake expires without base camera drift")
	p.hit(2,Impact.describe(1,{"type":"miss"}))
	check(p.hurts.is_empty(), "miss causes no hurt flash or shake")
	execution.phase = "travel"
	p.sync(tasks,views,{2:0.6},parent)
	p.sync({},views,{},parent)
	check(p.projectiles.is_empty(), "merge/removal absent task clears projectile")
	p.visual_assets = SpriteAssets.new()
	p.sync(tasks,views,{2:0.6},parent)
	check(p.projectiles[5] is Sprite3D and p.projectiles[5].basis.y.dot(Vector3.RIGHT) > 0.999, "private arrow local Y follows reflected flat trajectory")
	check(p.projectiles[5].basis.z.dot(Vector3.UP) > 0.999, "private sprite normal faces board up")
	p.hit(2,Impact.describe(1,{"type":"critical","damage":2}))
	p.advance(0.1); p.sync({},views,{},parent)
	p.reset()
	check(p.hurts.is_empty() and target.hurt_flash == 0 and target.rotation == Vector3.ZERO, "scene reset clears transient state")
	parent.queue_free()
	await process_frame
	print("Combat presentation checks: %d passed" % checks)
	quit()
