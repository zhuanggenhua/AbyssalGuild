extends SceneTree
const Presentation = preload("res://scripts/ui/combat_presentation.gd")
const Impact = preload("res://scripts/model/impact_feedback.gd")
const ImpactPopup = preload("res://scripts/ui/impact_view.gd")
class View extends Node3D:
	var hurt_flash := 0.0
	func set_hurt_flash(value: float) -> void: hurt_flash = value
class Assets extends RefCounted:
	func create_hit_popup(_kind: String, _damage: String, _edge: int, _scene: String) -> Node3D:
		var node := Node3D.new()
		node.scale = Vector3(2,3,4)
		return node
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value:
		failures += 1
		push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var p = Presentation.new()
	var parent := Node3D.new()
	root.add_child(parent)
	var view := View.new()
	parent.add_child(view)
	var views := {1:view}
	var hit := Impact.describe(1,{"type":"normal","damage":2})
	view.hurt_flash = 0.2
	view.rotation = Vector3(0.1,0.2,0.3)
	p.hit(1,hit)
	p.advance(0.049); p.sync({},views,{},parent)
	check(view.hurt_flash == 0.2 and view.rotation.is_equal_approx(Vector3(.1,.2,.3)),"delay preserves properties")
	# Getters run at first active child update, not event dispatch.
	view.hurt_flash = 0.4
	p.advance(0.001); p.sync({},views,{},parent)
	check(is_equal_approx(view.hurt_flash,0.4),"startup captures current flash")
	p.advance(0.1); p.sync({},views,{},parent)
	check(is_equal_approx(view.hurt_flash,1),"flash peak at .15")
	check(not is_equal_approx(view.rotation.y,0.2),"rotation punch remains active at flash peak")
	check(p.hurts[1].punch.targets[0].y < 0,"source positive Unity Y first knot reflects to negative Godot Y")
	p.advance(0.1); p.sync({},views,{},parent)
	check(is_equal_approx(view.hurt_flash,0.4) and p.hurts.has(1),"flash ends .25 but rotation lives")
	view.hurt_flash = 0.6
	p.advance(0.01); p.sync({},views,{},parent)
	check(view.hurt_flash == 0.6,"completed flash no longer overwrites other writers")
	var residual: Vector3 = view.rotation
	p.hit(1,hit); p.hit(1,hit)
	p.sync({},views,{},parent)
	check(view.rotation == residual and view.hurt_flash == 0.6,"two pre-start replacements do not reset")
	p.advance(0.05); p.sync({},views,{},parent)
	check(view.rotation.is_equal_approx(residual),"replacement captures residual rotation")
	p.advance(0.25); p.sync({},views,{},parent)
	check(p.hurts.is_empty() and view.rotation.is_equal_approx(residual) and is_equal_approx(view.hurt_flash,.6),".30 finish returns to replacement bases")
	p.hit(1,hit); p.advance(5); p.sync({},views,{},parent)
	check(p.hurts.is_empty() and view.rotation.is_equal_approx(residual),"large frame flushes endpoints")
	p.hit(1,hit); p.advance(-1); p.advance(INF)
	check(p.hurts[1].age == 0,"invalid deltas ignored")
	p.sync({}, {}, {}, parent)
	check(p.hurts.is_empty(),"removed targets cancel without writes")
	var popup = ImpactPopup.new()
	parent.add_child(popup)
	popup.set_process(false)
	popup.configure(hit, Vector3.ZERO, "normal", Assets.new())
	popup._process(1.0/55.0)
	check(popup.source_popup.scale.is_equal_approx(Vector3(2.15,3.15,4)),"source popup uses additive nonunit scale")
	check(popup.caption.modulate.a == 1,"no invented alpha fade")
	popup._process(1)
	check(popup.is_queued_for_deletion() and popup.source_popup.scale.is_equal_approx(Vector3(2,3,4)),"source popup endpoint before free")
	p.reset()
	parent.queue_free()
	await process_frame
	print("Source tween lifecycle: %s (%d checks)" % ["PASS" if failures == 0 else "FAIL", checks])
	quit(0 if failures == 0 else 1)
