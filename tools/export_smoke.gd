extends SceneTree
## External probe of the release PCK, hosted by the official editor executable.
## Official templates disable path overrides. This is not release-binary UI QA.
## Explicit checks also remain valid if a template supports this probe later.
const Main = preload("res://scenes/main.tscn")
const Catalog = preload("res://scripts/model/catalog.gd")
const VisualAssets = preload("res://scripts/ui/visual_assets.gd")
var checks := 0
var failures := 0
var completed := false
var counts := {"png": 0, "wav": 0, "fbx": 0}
var packed_files := 0

func audit_directory(path: String, assets) -> void:
	var directory := DirAccess.open(path)
	if not check(directory != null, "packed directory opens: " + path): return
	directory.include_hidden = true
	directory.list_dir_begin()
	var name := directory.get_next()
	while not name.is_empty():
		var full := path.path_join(name)
		if directory.current_is_dir():
			audit_directory(full, assets)
		else:
			packed_files += 1
			var allowed: bool = full in ["res://project.binary", "res://data/stackcraft.json", "res://assets/imported/manifest.json", "res://.godot/global_script_class_cache.cfg", "res://.godot/uid_cache.bin"]
			if full.begins_with("res://.godot/imported/"):
				allowed = full.get_extension() in ["ctex", "sample", "scn", "res"]
			if full.begins_with("res://.godot/exported/"):
				allowed = full.get_extension() in ["scn", "res", "gdc"]
			if full.begins_with("res://scripts/") or full.begins_with("res://scenes/"):
				allowed = full.get_extension() in ["gd", "gdc", "gdshader", "tscn", "scn", "tres", "res", "remap"]
			if full.begins_with("res://assets/imported/") and full.ends_with(".import"):
				for entry in assets.manifest.assets.values():
					if full == assets.root_path + str(entry.path) + ".import": allowed = true
			check(allowed, "runtime-only packed file: " + full)
		name = directory.get_next()
	directory.list_dir_end()

func check(ok: bool, label: String) -> bool:
	checks += 1
	if not ok:
		failures += 1
		printerr("FAIL: Export smoke: ", label)
	return ok

func _init() -> void:
	call_deferred("run")

func run() -> void:
	if not check(FileAccess.file_exists("res://project.binary") and not FileAccess.file_exists("res://project.godot"), "exported PCK required, not source checkout"):
		quit(1)
		return
	var catalog = Catalog.new()
	var assets = VisualAssets.new()
	if not check(catalog.load_file() == OK and assets.load_manifest() == OK, "packed JSON catalog and visual manifest load"):
		quit(1)
		return
	audit_directory("res://", assets)
	for entry in assets.manifest.assets.values():
		var path: String = assets.root_path + str(entry.path)
		var resource = ResourceLoader.load(path)
		match str(entry.kind):
			"png": check(resource is CompressedTexture2D, "packed PNG is cache-backed: " + path)
			"wav": check(resource is AudioStreamWAV and resource.get_length() > 0, "packed WAV decodes: " + path)
			"fbx": check(resource is PackedScene, "packed FBX scene loads: " + path)
			_: check(false, "unexpected resource kind")
		if counts.has(entry.kind): counts[entry.kind] += 1
	for kind in counts: check(counts[kind] > 0, "nonempty packed " + kind)
	for directory in ["source", "third_party", "tests", "tools", "docs", ".git", ".github"]:
		check(not DirAccess.dir_exists_absolute("res://" + directory), "excluded directory: " + directory)
	check(not FileAccess.file_exists("res://data/manifest.json"), "private provenance manifest excluded")
	if failures > 0:
		quit(1)
		return
	root.gui_embed_subwindows = true
	var board = Main.instantiate()
	root.add_child(board)
	await process_frame
	board.set_process(false)
	check(board.data_error == OK and board.title_panel.visible, "main scene starts at the real title")
	board.start_new()
	board.set_process(false)
	if not check(board.running and board.session.cards.size() == 1 and board.views.size() == 1, "New creates source-backed Starter"):
		board.feedback.shutdown()
		board.queue_free()
		await create_timer(0.5).timeout
		quit(1)
		return
	check(board.original_board != null, "original packed board mesh is bound")
	for view in board.views.values():
		check(view.caption.text.contains("Starter"), "packed starter view bound")
	board._save_game()
	check(FileAccess.file_exists(board._active_slot_path()), "isolated checkpoint written")
	board._return_title()
	board._continue_game()
	board.set_process(false)
	check(board.running and board.views.size() == 1, "Continue restores packed game")
	board._return_title()
	if failures > 0:
		board.feedback.shutdown()
		board.queue_free()
		await create_timer(0.5).timeout
		quit(1)
		return
	completed = true
	# Production quit owns cleanup and the real-time audio drain; no forced quit.
	board.title_quit_button.pressed.emit()
	board.quit_dialog.confirmed.emit()

func _finalize() -> void:
	if completed and failures == 0:
		print("LINUX EXPORTED PACK SMOKE: PASS (%d checks; %d PNG, %d WAV, %d FBX; New/Save/Continue/production Quit)" % [checks, counts.png, counts.wav, counts.fbx])
		print("Runtime-only PCK audit: PASS (%d files; editor-hosted pack probe)" % packed_files)
	else:
		printerr("FAIL: Export smoke did not finish")
