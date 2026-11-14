extends SceneTree
## Source-free renderer lifetime test. --legacy omits detach as an error-log control.
## Runner must reject engine ERROR even when assertions pass. No pixel claims.
const Lifetime=preload("res://scripts/ui/source_board_lifetime.gd")
var failures:=0
var checks:=0
var legacy:=false
func check(ok:bool,label:String)->void:
	checks+=1
	if not ok:failures+=1;printerr("FAIL: ",label)
func _init()->void:call_deferred("run")
func make_mesh()->ArrayMesh:
	var shared:=ArrayMesh.new()
	shared.add_blend_shape("Scale")
	shared.blend_shape_mode=Mesh.BLEND_SHAPE_MODE_RELATIVE
	for x in [0.0,2.0]:
		var a=[];a.resize(Mesh.ARRAY_MAX)
		a[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3(x,0,0),Vector3(x,0,1),Vector3(x+1,0,0)])
		a[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.UP,Vector3.UP,Vector3.UP])
		a[Mesh.ARRAY_INDEX]=PackedInt32Array([0,1,2])
		var shape=[];shape.resize(Mesh.ARRAY_MAX)
		shape[Mesh.ARRAY_VERTEX]=PackedVector3Array([Vector3.ZERO,Vector3(0,0,1),Vector3(1,0,0)])
		shape[Mesh.ARRAY_NORMAL]=PackedVector3Array([Vector3.ZERO,Vector3.ZERO,Vector3.ZERO])
		shared.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,a,[shape])
	return shared
func attach(shared:Mesh)->Dictionary:
	var board:=Node3D.new();root.add_child(board)
	var nested:=Node3D.new();board.add_child(nested)
	var instance:=MeshInstance3D.new();instance.mesh=shared;nested.add_child(instance)
	var weak_materials=[]
	var originals: Array[Material]=[]
	for surface in 2:
		var material:=ShaderMaterial.new();material.shader=Shader.new()
		material.shader.code="shader_type spatial; render_mode cull_back; void fragment(){ ALBEDO=vec3(0.4); }"
		originals.append(material)
		var replacement=material.duplicate()
		instance.set_surface_override_material(surface,replacement)
		weak_materials.append(weakref(material))
		weak_materials.append(weakref(replacement))
	instance.set_blend_shape_value(0,.5)
	return {"board":board,"instance":instance,"materials":weak_materials,"originals":originals}
func run()->void:
	legacy=OS.get_cmdline_user_args().has("--legacy")
	var shared:=make_mesh()
	var before0:PackedVector3Array=shared.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]
	var before1:PackedInt32Array=shared.surface_get_arrays(1)[Mesh.ARRAY_INDEX]
	var survivor:=attach(shared)
	var retired=attach(shared)
	for i in 3:await process_frame
	for cycle in 5:
		var old:Node3D=retired.board
		var mesh:MeshInstance3D=retired.instance
		var weak_old:WeakRef=weakref(old)
		var weak_materials:Array=retired.materials
		# Production binder.clear restores original references before retiring geometry.
		for surface in 2:mesh.set_surface_override_material(surface,retired.originals[surface])
		if not legacy:Lifetime.detach_meshes(old)
		check(legacy or mesh.mesh==null,"nested retiring instance detached")
		check(survivor.instance.mesh==shared,"live instance keeps shared mesh")
		check(shared.get_surface_count()==2 and shared.get_blend_shape_count()==1,"shared surface/shape structure unchanged")
		check(shared.surface_get_arrays(0)[Mesh.ARRAY_VERTEX]==before0 and shared.surface_get_arrays(1)[Mesh.ARRAY_INDEX]==before1,"shared arrays unchanged")
		old.queue_free()
		retired=attach(shared) # Same-frame replacement intentionally stresses dirty cleanup.
		for i in 3:await process_frame
		check(weak_old.get_ref()==null,"old owned subtree actually freed")
		for reference in weak_materials:check(reference.get_ref()==null,"old material truly released, not retained")
		for surface in 2:check(survivor.instance.get_active_material(surface)!=null,"live material unpolluted")
	for entry in [survivor,retired]:
		if not legacy:Lifetime.detach_meshes(entry.board)
		entry.board.queue_free()
	for i in 3:await process_frame
	Lifetime.detach_meshes(null)
	print("Source board lifetime: ",checks," checks, ",failures," failures; mode=", "legacy (engine ERROR expected)" if legacy else "detach; no pixel claim")
	quit(1 if failures else 0)
