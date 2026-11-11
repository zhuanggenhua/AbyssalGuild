extends SceneTree
const VisualAssets = preload("res://scripts/ui/visual_assets.gd")
var count: int = 0
func _init():
	var assets = VisualAssets.new()
	if assets.load_manifest() != OK:
		print("Source board mesh: SKIP (private manifest unavailable)")
		quit()
		return
	for scene in ["Main", "Island"]:
		var board: Node3D = assets.create_board_mesh(scene, 0.5)
		if board == null:
			print("Source board mesh: SKIP (run Godot editor --import first)")
			quit()
			return
		inspect(board)
		assert(assets.board_local_rect(scene, 0.0).is_equal_approx(Rect2(-6,-4,12,8)))
		assert(assets.board_local_rect(scene, 0.5).is_equal_approx(Rect2(-9,-6,18,12)))
		assert(assets.board_local_rect(scene, 1.0).is_equal_approx(Rect2(-12,-8,24,16)))
		board.free()
	assert(count == 2)
	print("Source board mesh: PASS (2 models, both surfaces, morph weights and bounds)")
	quit()
func inspect(node: Node):
	if node is MeshInstance3D:
		count += 1
		assert(node.mesh.get_surface_count() == 2)
		assert(node.get_surface_override_material(0).resource_name.begins_with("Body"))
		assert(node.get_surface_override_material(1).resource_name.begins_with("Header"))
		assert(is_equal_approx(node.get_blend_shape_value(0), 0.5))
	for child in node.get_children(): inspect(child)
