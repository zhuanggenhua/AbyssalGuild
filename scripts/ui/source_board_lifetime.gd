extends RefCounted
## Detach renderer instances only inside a retired, exclusively owned board tree.
## Never mutate/free shared Mesh resources or wait for a frame during destruction.
static func detach_meshes(board: Node) -> void:
	if not is_instance_valid(board): return
	if board is MeshInstance3D: board.mesh = null
	for child in board.get_children(): detach_meshes(child)
