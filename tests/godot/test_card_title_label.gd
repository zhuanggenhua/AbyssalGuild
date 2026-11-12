extends SceneTree
const Title = preload("res://scripts/ui/card_title_label.gd")
const CardView = preload("res://scripts/ui/card_view.gd")
const VisualAssets = preload("res://scripts/ui/visual_assets.gd")
var checks := 0

func _init() -> void:
	call_deferred("run")

func check(value: bool, message: String) -> void:
	checks += 1
	assert(value, message)

func bounds_fit(label: Label3D, rect: Rect2) -> void:
	var box := label.get_aabb()
	var epsilon := 0.0001
	check(box.position.x >= rect.position.x - epsilon and box.end.x <= rect.end.x + epsilon, "shaped title stays inside horizontal padding")
	check(box.position.y >= rect.position.y - epsilon and box.end.y <= rect.end.y + epsilon, "shaped title stays inside vertical padding")
	check(label.autowrap_mode == TextServer.AUTOWRAP_OFF, "title does not wrap onto the next stacked card")
	check(label.pixel_size > 0 and is_finite(label.pixel_size), "font scale remains finite and positive")

func run() -> void:
	var record := {"rect_size":{"x":1.6,"y":0.3}, "margin":{"x":0.1,"y":0.03,"z":0.12,"w":0.05}, "horizontal_alignment":1}
	var rect := Title.content_rect(record, Vector2.ONE)
	check(rect.position.is_equal_approx(Vector2(-0.7,-0.1)) and rect.size.is_equal_approx(Vector2(1.38,0.22)), "asymmetric source margins resolve inside centered rectangle")
	check(ThemeDB.fallback_font.get_string_size("Orchard Patch",HORIZONTAL_ALIGNMENT_LEFT,-1,36).x > 175, "synthetic multiword title would wrap under the old fixed width")
	var short_scale := 0.0
	for alignment in [1,2,4]:
		record.horizontal_alignment = alignment
		for title in ["Ore","Orchard Patch","A deliberately long synthetic card title","ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789","","Two\nlines"]:
			var label := Label3D.new()
			label.position = Vector3(2,3,4)
			Title.fit(label, title, record, Vector2.ONE)
			root.add_child(label)
			await process_frame
			bounds_fit(label, rect)
			check(label.position == Vector3(2,3,4), "fitting leaves the source pose untouched")
			check(not label.text.contains("\n"), "explicit breaks remain on one title line")
			if title == "Ore":
				short_scale = label.pixel_size
				check(is_equal_approx(label.font.get_height(label.font_size) * short_scale, rect.size.y), "short titles use the full available native line height")
			elif title == "A deliberately long synthetic card title":
				check(label.pixel_size < short_scale, "long titles shrink rather than wrap")
			label.free()
	# Legacy or invalid metadata is safe without guessing a replacement source pose.
	for metadata in [{}, {"rect_size":{"x":0,"y":-1},"margin":{"x":99,"w":99}}, {"rect_size":{"x":1.6}}]:
		var label := Label3D.new()
		Title.fit(label,"Fallback caption",metadata,Vector2(1.6,0.3))
		root.add_child(label)
		await process_frame
		bounds_fit(label,Title.content_rect(metadata,Vector2(1.6,0.3)))
		label.free()
	var card = CardView.new()
	card.configure(17,"Orchard Patch",1,false,null,{},"Main",Vector3(2,0.08,3))
	root.add_child(card)
	await process_frame
	bounds_fit(card.caption,Title.content_rect({},Vector2(2 * 0.875,3 * 0.1)))
	check(card.body.mesh.size == Vector3(2,0.08,3), "title fit does not resize generated card mesh")
	for child in card.get_children():
		if child is StaticBody3D:
			check(child.get_child(0).shape.size == Vector3(2,0.08,3), "title fit does not resize picking collider")
	var title_scale: float = card.caption.pixel_size
	card.update_state({"health":0})
	check(card.caption.text == "Orchard Patch" and card.caption.pixel_size == title_scale, "display updates do not disturb fitted title")
	card.free()
	print("Card title synthetic fitting: %d checks passed" % checks)
	await test_private()
	quit()

func test_private() -> void:
	var assets = VisualAssets.new()
	if assets.load_manifest() != OK or not FileAccess.file_exists("res://data/stackcraft.json"):
		print("Private card title fitting: SKIP (private manifest/catalog unavailable)")
		return
	var first: Dictionary = assets.appearance(1,false).prefab.title
	if not first.has("margin"):
		print("Private card title fitting: SKIP (regenerate private visual manifest)")
		return
	var catalog: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/stackcraft.json"))
	var count := 0
	var actual_meshes := 0
	for scene in ["Main","Island"]:
		for section in ["cards","packs"]:
			for definition in catalog.get(section,[]):
				var fields: Dictionary = definition.fields
				var is_pack: bool = section == "packs"
				var category: int = int(fields.get("category",0))
				var appearance: Dictionary = assets.appearance(category,is_pack,fields,scene)
				var record: Dictionary = appearance.prefab.title
				check(int(record.word_wrap) == 0 and int(record.auto_size) == 1, "source title disables wrap and enables auto-sizing")
				var card = CardView.new()
				var title: String = str(fields.get("displayName",definition.name))
				card.configure(count,title,category,is_pack,assets,fields,scene)
				root.add_child(card)
				await process_frame
				bounds_fit(card.caption,Title.content_rect(record,Vector2.ONE))
				check(card.caption.text == title, "actual source display name is retained in full")
				if card.source_material != null: actual_meshes += 1
				count += 1
				card.free()
	check(count > 0, "private definitions exercised")
	print("Private card title fitting: PASS (%d titles; %s)" % [count,"actual cached FBX" if actual_meshes == count else "generated fallback"])
