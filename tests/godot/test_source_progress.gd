extends SceneTree
const View = preload("res://scripts/ui/craft_progress_view.gd")
var checks := 0
var failures := 0
func check(value: bool, label: String) -> void:
	checks += 1
	if not value: failures += 1; push_error(label)
func _initialize() -> void: call_deferred("run")
func run() -> void:
	var image := Image.create(2,2,false,Image.FORMAT_RGBA8)
	image.fill(Color.WHITE)
	var texture := ImageTexture.create_from_image(image)
	var view = View.new(); root.add_child(view)
	var chain := [{"m_LocalPosition":{"x":2,"y":-3,"z":4},"m_LocalRotation":{"x":0,"y":0,"z":0,"w":1},"m_LocalScale":{"x":2,"y":3,"z":4}}]
	var pose: Transform3D = View.effective_transform(chain)
	check(pose.origin == Vector3(2,-3,-4) and pose.basis.get_scale() == Vector3(2,3,4),"effective TRS preserves scale and reflects source Z")
	view.configure({"size":{"x":.8,"y":.05},"background":{"r":.25,"g":.25,"b":.25,"a":.8},"fill":{"r":1,"g":.7974138,"b":0,"a":1}},texture,Basis(Vector3.RIGHT,-PI/2))
	view.sync({1:{"anchor":Vector3(2,0,3.55),"ratio":.5,"paused":true}})
	var bar: MeshInstance3D = view.bars[1].root
	check(bar.position == Vector3(2,0,-3.55),"no invented surface lift")
	check(bar.mesh.size.is_equal_approx(Vector2(.8,.05)),"source dimensions preserved")
	check(bar.get_child_count()==0,"single coplanar draw")
	var bg := Color(.25,.25,.25,.8)
	var fg := Color(1,.7974138,0,1)
	check(View.composite(bg,Color.WHITE,fg,.25,.5).is_equal_approx(fg),"opaque source fill overlays background")
	check(View.composite(bg,Color.WHITE,fg,.75,.5).is_equal_approx(bg),"horizontal clipped region remains background")
	check(View.composite(bg,Color(1,0,0,0),fg,.25,.5).is_equal_approx(bg),"transparent texel retains background")
	var semi: Color = View.composite(bg,Color(1,1,1,.5),Color.WHITE,.25,.5)
	check(is_equal_approx(semi.a,.9) and is_equal_approx(semi.r,2.0/3.0),"alpha-over layer order")
	check(View.composite(bg,Color.WHITE,fg,0,0).is_equal_approx(bg),"zero fill fully hidden including left boundary")
	check(View.composite(bg,Color.WHITE,fg,1,1).is_equal_approx(fg),"full fill includes right boundary")
	view.sync({1:{"anchor":Vector3(2,0,3.55),"ratio":.5,"paused":true}})
	check(view.bars[1].root == bar and bar.material_override.get_shader_parameter("ratio") == .5,"paused sync has no local clock or replacement")
	view.hide(); check(not bar.is_visible_in_tree(),"parent visibility hides bar")
	view.show(); view.reset()
	check(view.bars.is_empty() and bar.is_queued_for_deletion() and not bar.visible,"cancel removes and hides before free")
	view.queue_free(); await process_frame
	print("Source progress composition: %s (%d checks)" % ["PASS" if failures==0 else "FAIL",checks])
	quit(0 if failures==0 else 1)
