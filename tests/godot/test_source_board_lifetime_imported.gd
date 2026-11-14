extends "res://tests/godot/source_board_lifecycle.gd"
## Reuse production lifecycle assertions but explicitly substitute logical frames.
## Native/GPU/error timing is separately accepted by the unmodified native entry.
func _requires_native() -> bool: return false
func _mode_label() -> String: return "Headless source board lifecycle"
func _frame_boundary() -> void:
	await process_frame
	if is_instance_valid(board) and is_instance_valid(board.flat_board_lighting):
		board.flat_board_lighting.refresh()
func run() -> void:
	var remap:=ConfigFile.new()
	if remap.load("res://assets/imported/Models/Board.fbx.import")!=OK or not FileAccess.file_exists(str(remap.get_value("remap","path",""))):
		print("Headless source board lifecycle: SKIP (private cached FBX unavailable; strict imported runner rejects this)")
		quit(0);return
	await super.run()
