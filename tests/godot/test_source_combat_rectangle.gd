extends SceneTree
const Adapter = preload("res://scripts/ui/source_combat_rectangle.gd")
var checks := 0
var failures := 0

func check(ok: bool, note: String) -> void:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: ",note)

func _init() -> void:
	call_deferred("run")

func run() -> void:
	var border := Vector4(64,64,64,64)
	var pixels := Vector2(128,128)
	var ppu := 128.0*128.0/100.0
	var size := Vector2(2,3)
	var mesh := Adapter.sliced_mesh(size,Vector2(0.5,0.5),border,pixels,ppu,true)
	if mesh == null: quit(1); return
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var uv: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	check(vertices.size() == 36 and indices.size() == 54,"nine quads including degenerate-UV center")
	check(vertices[0] == Vector3(-1,-1.5,0) and vertices[2] == Vector3(-0.609375,-1.109375,0),"lower-left actual uniform border")
	check(vertices[16] == Vector3(-0.609375,-1.109375,0) and vertices[18] == Vector3(0.609375,1.109375,0),"positive geometry in center")
	check(Array(uv.slice(16,20)) == [Vector2(0.5,0.5),Vector2(0.5,0.5),Vector2(0.5,0.5),Vector2(0.5,0.5)],"keep constant center sample")
	check(uv[0] == Vector2(0,1) and uv[34] == Vector2(1,0),"source texture is inverted on V once")
	check(Vector2(mesh.get_aabb().size.x,mesh.get_aabb().size.y) == size,"physical bounds unpadded")
	var narrow := Adapter.sliced_mesh(Vector2(0.25,3),Vector2(0.5,0.5),border,pixels,ppu,true)
	check(narrow.surface_get_array_len(0) == 24 and Vector2(narrow.get_aabb().size.x,narrow.get_aabb().size.y) == Vector2(0.25,3),"clamp both sides to same X when width cannot fit borders")
	var tiny := Adapter.sliced_mesh(Vector2(0.25,0.25),Vector2(0.5,0.5),border,pixels,ppu,true)
	check(tiny.surface_get_array_len(0) == 16,"clamp both axes, dropping only empty strips")
	var cutout := Adapter.sliced_mesh(size,Vector2(0.5,0.5),border,pixels,ppu,false)
	check(cutout.surface_get_array_len(0) == 32,"Fill Center off skips real interior quad")
	var asymmetric := Adapter.sliced_mesh(Vector2(2,3),Vector2(0.2,0.8),Vector4(16,32,48,64),pixels,128.0,true)
	var geom: Array = asymmetric.surface_get_arrays(0)
	check(geom[Mesh.ARRAY_VERTEX][0].is_equal_approx(Vector3(-0.4,-2.4,0)) and geom[Mesh.ARRAY_TEX_UV][2] == Vector2(0.125,0.75),"asymmetric L/B/R/T and pivot order")
	check(Adapter.sliced_mesh(Vector2.ZERO,Vector2.ZERO,border,pixels,ppu,true) == null,"reject nonpositive dimensions")
	if failures == 0: print("Source CombatRect sliced mesh: PASS (%d checks)" % checks)
	quit(0 if failures == 0 else 1)
